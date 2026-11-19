class_name PeopleRules
extends RefCounted
## 사람들의 기억. 사건을 들고 온 인물은 영주가 청을 들어줬는지 물리쳤는지 기억한다.
## 호의가 쌓이면 보답하고, 서운함이 쌓이면 등을 돌린다. 새 통치에서만 깃발(people)로 켠다.

const LIMIT := 2  # 이만큼 쌓이면 보답하거나 등을 돌린다
const EFFECT_NAMES := {"trust":"행정관 신뢰", "security":"치안", "health":"건강", "guild":"상인 호감", "village":"주민 관계", "mood":"민심"}


static func enabled(state: Dictionary) -> bool:
	return state.get("people", {}) is Dictionary and state.get("people", {}).get("enabled", false) == true


static func setup(state: Dictionary, config: Dictionary) -> bool:
	if not bool(config.get("people", false)) or state.is_empty(): return false
	if enabled(state): return true
	state.people = {"enabled":true, "version":1, "regard":{}, "memory":{}, "pending":[], "tally":{"favor":0, "grudge":0}}
	return true


## 이 선택이 인물에게 어떻게 남는가. +1 청을 들어줌, -1 물리침, 0 기억에 남지 않음.
## 대가를 치르거나 위험을 지거나 뒷일을 약속하면 들어준 것이고, 그런 길이 있는데도 맨 끝의 공짜 선택지를 고르면 물리친 것이다.
static func stance(event: Dictionary, index: int) -> int:
	var options: Array = event.get("options", [])
	if index < 0 or index >= options.size() or not event.has("portrait"): return 0
	if _commits(options[index]): return 1
	if options.size() >= 2 and index == options.size() - 1 and options.any(func(option): return _commits(option)): return -1
	return 0


static func _commits(option: Dictionary) -> bool:
	return not option.get("cost", {}).is_empty() or option.has("followup") or option.has("chance")


## 사건 선택 직후에 부른다. 기억과 사이를 고치고, 한계에 닿으면 다음 주에 치를 보답·앙금을 예약한다.
static func record(state: Dictionary, content: Dictionary, event: Dictionary, index: int) -> void:
	if not enabled(state): return
	var who := str(event.get("portrait", ""))
	if not content.chronicle.characters.has(who): return
	var change := stance(event, index)
	var people: Dictionary = state.people
	people.memory[who] = {"week":int(state.week), "title":str(event.get("title", "")), "stance":change}
	if change == 0: return
	var regard := int(people.regard.get(who, 0)) + change
	if absi(regard) >= LIMIT:
		people.pending.append({"who":who, "kind":"favor" if regard > 0 else "grudge"})
		regard = 0
	people.regard[who] = regard


## 주가 끝날 때 예약된 보답과 앙금을 실제 수치에 적용한다.
static func after_week(state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	if not enabled(state) or not bool(report.get("advanced", false)): return
	var people: Dictionary = state.people
	for entry in people.pending:
		var person: Dictionary = content.chronicle.characters[entry.who]
		var favor: bool = entry.kind == "favor"
		var key := str(person.effect)
		var previous := float(state.get(key, 0))
		state[key] = clampf(previous + float(person.value) * (2.0 if favor else -2.0), 0, 100)
		people.tally[entry.kind] = int(people.tally.get(entry.kind, 0)) + 1
		var text := "%s의 %s · %s %+d" % [person.name, "보답" if favor else "앙금", EFFECT_NAMES.get(key, key), int(round(float(state[key]) - previous))]
		state.log.append(text)
		report.notes.append(text)
	people.pending = []


## 화면에 보여 줄 한 사람의 상태.
static func view(state: Dictionary, content: Dictionary, who: String) -> Dictionary:
	var person: Dictionary = content.chronicle.characters.get(who, {})
	var result := {"id":who, "name":str(person.get("name", "")), "role":str(person.get("role", "")), "regard":0, "mood":"", "memory":"", "known":false}
	if not enabled(state) or person.is_empty(): return result
	result.regard = int(state.people.regard.get(who, 0))
	result.mood = "호의" if result.regard > 0 else "서운함" if result.regard < 0 else "담담함"
	var memory: Dictionary = state.people.memory.get(who, {})
	if memory.is_empty(): return result
	result.known = true
	var ago := int(state.week) - int(memory.week)
	var when := "이번 주" if ago <= 0 else "%d주 전" % ago
	result.memory = "%s 「%s」 때 %s" % [when, memory.title, "청을 들어주셨습니다" if int(memory.stance) > 0 else "청을 물리치셨습니다" if int(memory.stance) < 0 else "이야기를 나눴습니다"]
	return result


## 최근에 만난 순서로 인물 목록을 돌려준다.
static func court(state: Dictionary, content: Dictionary, limit: int) -> Array:
	var rows: Array = []
	if not enabled(state): return rows
	var ids: Array = state.people.memory.keys()
	ids.sort_custom(func(a, b): return int(state.people.memory[a].week) > int(state.people.memory[b].week))
	for id in ids.slice(0, limit): rows.append(view(state, content, str(id)))
	return rows


## 선택지 옆에 적을 한 줄. 이 선택이 그 사람에게 어떻게 남는지 미리 보여 준다.
static func stance_text(state: Dictionary, content: Dictionary, event: Dictionary, index: int) -> String:
	if not enabled(state): return ""
	var who := str(event.get("portrait", ""))
	if not content.chronicle.characters.has(who): return ""
	var change := stance(event, index)
	if change == 0: return ""
	var after := int(state.people.regard.get(who, 0)) + change
	var name := str(content.chronicle.characters[who].name)
	if absi(after) >= LIMIT: return "%s이(가) %s" % [name, "보답합니다" if after > 0 else "등을 돌립니다"]
	return "%s · %s" % [name, "호의 +1" if change > 0 else "서운함 +1"]


static func valid(state: Dictionary, content: Dictionary) -> bool:
	if not state.has("people"): return true
	var people: Variant = state.people
	if not people is Dictionary or not people.get("enabled") is bool: return false
	if not people.get("regard") is Dictionary or not people.get("memory") is Dictionary or not people.get("pending") is Array or not people.get("tally") is Dictionary: return false
	var known: Dictionary = content.chronicle.characters
	for who in people.regard:
		var value: Variant = people.regard[who]
		if not known.has(who) or not (value is int or value is float) or absf(float(value)) >= LIMIT: return false
	for who in people.memory:
		var memory: Variant = people.memory[who]
		if not known.has(who) or not memory is Dictionary or not memory.get("title") is String: return false
		for key in ["week", "stance"]:
			if not (memory.get(key) is int or memory.get(key) is float): return false
	for entry in people.pending:
		if not entry is Dictionary or not known.has(entry.get("who", "")) or entry.get("kind") not in ["favor", "grudge"]: return false
	return true
