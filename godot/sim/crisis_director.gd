class_name CrisisDirector
extends RefCounted
## 예고한 수치로 대비하는 회차 위기. 경제 압박은 해당 주의 배율만 합성한다.
## 계획은 독립 시드로 고정하며 조회·불러오기·재호출은 난수나 보상을 소모하지 않는다.

const DATA_PATH := "res://content/crises.json"
const ASSETS := ["money","food","wood","stone","tools","fuel","iron"]
const STATS := ["mood","health","security","trust","village","guild"]


static func definitions() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return value if value is Dictionary else {}


static func _data(content: Dictionary) -> Dictionary:
	return content.crises if content.get("crises") is Dictionary else definitions()


static func enabled(state: Dictionary) -> bool:
	return state.get("escalation", {}) is Dictionary and state.get("escalation", {}).get("enabled", false) == true


static func _plan(seed_value: int, data: Dictionary) -> Array:
	var random := Xoshiro128.new(seed_value,103)
	var plan := []
	for index in data.windows.size():
		var window: Dictionary = data.windows[index]
		var id := str(window.pool[random.randi_range(0,window.pool.size()-1)])
		plan.append({"index":index,"id":id,"announce":int(window.announce),"deadline":int(window.deadline)})
	return plan


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if config.get("escalation",false) != true or not RealmRules.enabled(state): return false
	if state.has("escalation"): return enabled(state) and valid(state,content)
	state.escalation = {"enabled":true,"version":1,"plan":_plan(int(state.seed),_data(content)),
		"last_week":0,"active":{},"records":[],"notices":[],"news":[]}
	return true


static func _phase(state: Dictionary, data: Dictionary) -> int:
	var index := 0
	for next in data.phases.size():
		if int(state.get("week",1)) >= int(data.phases[next].start): index = next
	return index


static func bonuses(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	if not enabled(state): return {}
	var data := _data(content)
	return data.phases[_phase(state,data)].mods.duplicate(true)


static func _freeze(state: Dictionary, definition: Dictionary) -> Array:
	var checks: Array = definition.checks.duplicate(true)
	for check in checks:
		for condition in check.any:
			var target := float(condition.get("amount",0.0))
			if condition.has("per_pop"):
				target = float(state.pop)*float(condition.per_pop)
				if condition.has("bonus"): target *= WeekSim.bonus(state,str(condition.bonus))
			condition["target"] = ceilf(target) if condition.kind not in ["stat"] else target
	return checks


static func _value(state: Dictionary, content: Dictionary, condition: Dictionary) -> float:
	var key := str(condition.get("key",""))
	match str(condition.kind):
		"resource": return maxf(0.0,float(state.public.get(key,0.0))-float(RealmRules.held(state,content).get(key,0.0)))
		"food": return WeekSim.total_food(state)
		"facility": return float(state.facilities.get(key,0))
		"capacity": return WeekSim.capacity(state,content,key)
		"stat": return float(state.get(key,0.0))
	return 0.0


static func _checks(state: Dictionary, content: Dictionary, frozen: Array) -> Array:
	var rows := []
	for check in frozen:
		var row := {"label":str(check.label),"met":false,"alternatives":[],"text":"","current":0.0,"target":0.0}
		var texts: Array[String] = []
		for condition in check.any:
			var current := _value(state,content,condition)
			var target := float(condition.target)
			var below: bool = condition.get("comparison","") == "at_most"
			var met := current <= target+0.00001 if below else current+0.00001 >= target
			var scale := 100.0 if condition.get("key","") == "money" else 1.0
			var unit := "금" if scale == 100.0 else ""
			var text := "%s %.1f / %.1f%s%s" % [condition.label,current/scale,target/scale,unit," 이하" if below else ""]
			texts.append(text)
			row.alternatives.append({"label":str(condition.label),"current":current,"target":target,"met":met,"comparison":"at_most" if below else "at_least","text":text})
			row.met = row.met or met
		row.current = row.alternatives[0].current
		row.target = row.alternatives[0].target
		row.text = " 또는 ".join(texts)
		rows.append(row)
	return rows


static func _apply(state: Dictionary, content: Dictionary, amounts: Dictionary, week: int, source: String) -> Dictionary:
	var actual := {}
	var held := RealmRules.held(state,content)
	for key in amounts:
		var amount := float(amounts[key])
		if key in ASSETS:
			if amount < 0: amount = -minf(-amount,maxf(0.0,float(state.public[key])-float(held.get(key,0.0))))
			if key == "money":
				amount = int(amount)
				state.public.money = int(state.public.money)+int(amount)
			else: state.public[key] = float(state.public[key])+amount
			WeekSim._ledger(state,week,source,str(key),amount)
		elif key in STATS:
			var before := float(state[key])
			state[key] = clampf(before+amount,0.0,100.0)
			amount = float(state[key])-before
		if not is_zero_approx(amount): actual[str(key)] = amount
	return actual


static func _news(state: Dictionary, report: Dictionary, text: String, level: String = "info") -> void:
	state.escalation.news.append(text)
	if report.get("notes") is Array: report.notes.append(text)
	state.realm.news.append({"kind":"crisis","level":level,"text":text})


static func after_week(before: Dictionary, state: Dictionary, content: Dictionary, report: Dictionary) -> Dictionary:
	var result := {"resolved":false,"announced":false,"phase_notice":false}
	if not enabled(state) or not enabled(before) or report.get("advanced",false) != true: return result
	var week := int(report.get("week",0))
	if week < 1 or week > 52 or int(before.week) != week or int(state.week) != week+1 or before.run_id != state.run_id: return result
	var value: Dictionary = state.escalation
	if week <= int(value.last_week): return result
	var data := _data(content)
	value.last_week = week
	value.news.clear()
	if not value.active.is_empty() and int(value.active.deadline) == week:
		var active: Dictionary = value.active
		var definition: Dictionary = data.definitions[active.id]
		var checks := _checks(state,content,active.checks)
		var success: bool = checks.all(func(row): return row.met)
		var effects := _apply(state,content,definition.reward if success else definition.penalty,week,"crisis_reward" if success else "crisis_penalty")
		var relic := false
		if success and definition.get("relic",false):
			if int(state.week) <= 52 and int(state.pop) > 0 and VillageRelics.enabled(state) and VillageRelics.offer_error(state,content) == "":
				relic = VillageRelics.request_offer(state,content,"crisis:%s:%d" % [active.id,week]) == ""
			if not relic:
				var fallback := _apply(state,content,{"money":300},week,"crisis_reward")
				effects["money"] = float(effects.get("money",0.0))+float(fallback.get("money",0.0))
		var message := "%s %s · %s%s" % [definition.name,"대비 성공" if success else "대비 실패",RealmRules.changes_text(effects)," · 성물 선택" if relic else ""]
		value.records.append({"index":int(active.index),"id":str(active.id),"name":str(definition.name),"week":week,"success":success,"effects":effects,"checks":checks,"relic":relic,"message":message})
		value.active = {}
		_news(state,report,message,"good" if success else "bad")
		result.resolved = true
	for index in range(1,data.phases.size()):
		var phase: Dictionary = data.phases[index]
		if int(phase.start)-int(state.week) == 3 and str(phase.id) not in value.notices:
			value.notices.append(str(phase.id))
			_news(state,report,"%d주부터 %s · %s" % [phase.start,phase.name,phase.text],"warn")
			result.phase_notice = true
	if value.active.is_empty():
		for planned in value.plan:
			if int(planned.announce) != int(state.week): continue
			var definition: Dictionary = data.definitions[planned.id]
			value.active = planned.duplicate(true)
			value.active["checks"] = _freeze(state,definition)
			_news(state,report,"위기 예고 · %s · %d주 작업을 마친 뒤 판정" % [definition.name,planned.deadline],"warn")
			result.announced = true
	return result


static func overview(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"enabled":enabled(state),"pressure":{},"next_pressure":{},"current":{},"upcoming":{},"records":[],"news":[],"last_result":{}}
	if not result.enabled: return result
	var data := _data(content)
	var value: Dictionary = state.escalation
	var index := _phase(state,data)
	result.pressure = data.phases[index].duplicate(true)
	result.pressure["index"] = index
	if index+1 < data.phases.size():
		result.next_pressure = data.phases[index+1].duplicate(true)
		result.next_pressure["remaining"] = int(result.next_pressure.start)-int(state.week)
		result.next_pressure["warned"] = int(result.next_pressure.remaining) <= 3
	if not value.active.is_empty():
		var active: Dictionary = value.active
		var definition: Dictionary = data.definitions[active.id]
		var checks := _checks(state,content,active.checks)
		result.current = {"id":str(active.id),"name":str(definition.name),"announce":int(active.announce),"deadline":int(active.deadline),
			"remaining":maxi(0,int(active.deadline)-int(state.week)+1),"checks":checks,"ready":checks.all(func(row): return row.met),
			"hint":str(definition.hint),"reward":definition.reward.duplicate(true),"penalty":definition.penalty.duplicate(true),"relic":bool(definition.get("relic",false)),
			"met_count":checks.filter(func(row): return row.met).size(),"total_checks":checks.size()}
	for planned in value.plan:
		if int(planned.announce) > int(state.week):
			result.upcoming = {"announced":false,"name":"미확인 위기","announce":int(planned.announce),"deadline":int(planned.deadline),"remaining_to_announce":int(planned.announce)-int(state.week)}
			break
	result.records = value.records.duplicate(true)
	result.news = value.news.duplicate()
	if not value.records.is_empty(): result.last_result = value.records.back().duplicate(true)
	return result


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _effects_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key is String or key not in ASSETS+STATS or not _number(value[key]): return false
	return true


static func _result_checks_valid(value: Variant, definition: Dictionary) -> bool:
	if not value is Array or value.size() != definition.checks.size(): return false
	for index in value.size():
		var row: Variant = value[index]
		if not row is Dictionary or row.get("label") != definition.checks[index].label or not row.get("met") is bool or not row.get("text") is String: return false
		if not _number(row.get("current")) or not _number(row.get("target")): return false
		if not row.get("alternatives") is Array or row.alternatives.size() != definition.checks[index].any.size(): return false
		var met := false
		for option in row.alternatives.size():
			var item: Variant = row.alternatives[option]
			var expected: Dictionary = definition.checks[index].any[option]
			if not item is Dictionary or item.get("label") != expected.label or not item.get("text") is String or not item.get("met") is bool: return false
			if not _number(item.get("current")) or not _number(item.get("target")) or item.current < 0 or item.target < 0: return false
			var comparison := "at_most" if expected.get("comparison","") == "at_most" else "at_least"
			if item.get("comparison") != comparison: return false
			var actual: bool = float(item.current) <= float(item.target)+0.00001 if comparison == "at_most" else float(item.current)+0.00001 >= float(item.target)
			if item.met != actual: return false
			met = met or actual
		if row.met != met or row.current != row.alternatives[0].current or row.target != row.alternatives[0].target: return false
	return true


static func valid(state: Dictionary, content: Dictionary = {}) -> bool:
	if not state.has("escalation"): return true
	var value: Variant = state.escalation
	if not value is Dictionary or value.get("enabled") != true or not value.get("enabled") is bool or not _whole(value.get("version")) or value.version != 1: return false
	if not _whole(state.get("seed")) or not _whole(value.get("last_week")) or value.last_week < 0 or value.last_week > 52 or value.last_week >= float(state.get("week",0)): return false
	var data := _data(content)
	if not value.get("plan") is Array or value.plan.size() != data.windows.size(): return false
	var expected := _plan(int(state.seed),data)
	for index in expected.size():
		var item: Variant = value.plan[index]
		if not item is Dictionary or item.get("id") != expected[index].id: return false
		for key in ["index","announce","deadline"]:
			if not _whole(item.get(key)) or item[key] != expected[index][key]: return false
	if not value.get("active") is Dictionary or not value.get("records") is Array or value.records.size() > 4 or not value.get("notices") is Array or not value.get("news") is Array: return false
	var done := []
	for record in value.records:
		if not record is Dictionary or not _whole(record.get("index")) or record.index < 0 or record.index >= expected.size() or record.index in done: return false
		var planned: Dictionary = expected[int(record.index)]
		if record.get("id") != planned.id or record.get("week") != planned.deadline or record.week > value.last_week: return false
		if not record.get("success") is bool or not record.get("relic") is bool or not record.get("name") is String or not record.get("message") is String or not record.get("checks") is Array or not _effects_valid(record.get("effects")): return false
		var definition: Dictionary = data.definitions[record.id]
		if record.name != definition.name or not _result_checks_valid(record.checks,definition): return false
		if record.success != record.checks.all(func(row): return row.met): return false
		if record.relic and (not record.success or not definition.get("relic",false)): return false
		var limits: Dictionary = (definition.reward if record.success else definition.penalty).duplicate(true)
		if record.success and definition.get("relic",false) and not record.relic: limits["money"] = float(limits.get("money",0.0))+300.0
		for key in record.effects:
			if not limits.has(key): return false
			# 상태치는 clamp 후 before/after 차이라 +4가 4.00000000000001이 될 수 있다.
			# 원장에 직접 기록한 자원·금액의 한도는 느슨하게 만들지 않는다.
			var tolerance := 0.00000001 if key in STATS else 0.0
			if record.success and (float(record.effects[key]) < 0 or float(record.effects[key]) > float(limits[key]) + tolerance): return false
			if not record.success and (float(record.effects[key]) > 0 or float(record.effects[key]) < float(limits[key]) - tolerance): return false
		done.append(int(record.index))
	if not value.active.is_empty():
		var active: Dictionary = value.active
		if not _whole(active.get("index")) or active.index < 0 or active.index >= expected.size() or active.index in done: return false
		var planned: Dictionary = expected[int(active.index)]
		for key in ["id","announce","deadline"]:
			if active.get(key) != planned[key]: return false
		if int(state.week) < active.announce or int(state.week) > active.deadline or not active.get("checks") is Array: return false
		var original: Array = data.definitions[active.id].checks
		if active.checks.size() != original.size(): return false
		for index in original.size():
			var check: Variant = active.checks[index]
			if not check is Dictionary or check.get("label") != original[index].label or not check.get("any") is Array or check.any.size() != original[index].any.size(): return false
			for option in check.any.size():
				var saved: Variant = check.any[option]
				if not saved is Dictionary or not _number(saved.get("target")) or saved.target < 0 or saved.target > 1000000000: return false
				var definition: Dictionary = original[index].any[option]
				for key in definition:
					if saved.get(key) != definition[key]: return false
				if not definition.has("per_pop") and saved.target != definition.get("amount",0): return false
				if definition.has("per_pop") and (saved.target < 1 or not _whole(saved.target)): return false
	var notices := []
	for id in value.notices:
		if not id is String or id in notices or not data.phases.any(func(phase): return phase.id == id): return false
		notices.append(id)
	for line in value.news:
		if not line is String: return false
	return true
