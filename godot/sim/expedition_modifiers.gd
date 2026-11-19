class_name ExpeditionModifiers
extends RefCounted
## 출발 전에 공개하는 영지 조건. 기회·제약 하나씩을 독립 난수 스트림으로 정한다.
## 기본 bonuses에는 기록하지 않는다. RealmRules.refresh에서 매번 한 번만 합성한다.

const VERSION := 1
const STREAM := 91
const GROUPS := ["opportunities", "constraints"]
const KINDS := ["opportunity", "constraint"]
const EFFECTS := ["gather", "logging", "buy", "harvest", "heating", "spoil"]


static func enabled(state: Dictionary) -> bool:
	return state.get("expedition_modifiers") is Dictionary and state.expedition_modifiers.get("enabled") == true


## 순수한 출발 미리보기. 후보·지역·장비 선택과 사건 RNG를 소비하지 않는다.
static func preview(content: Dictionary, run_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var data: Variant = content.get("modifiers")
	if not _data_valid(data): return rows
	var random := Xoshiro128.new(run_seed, STREAM)
	for group in GROUPS:
		var ids: Array = data[group]
		var id := str(ids[random.randi_range(0, ids.size() - 1)])
		rows.append(_row(id, data.definitions[id]))
	return rows


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if state.is_empty() or config.get("modifiers", false) != true or config.get("realm", false) != true: return false
	# 계속하기·중복 초기화가 조건을 다시 뽑거나 기본 보너스를 재적용하지 않는다.
	if state.has("expedition_modifiers"): return valid(state, content)
	if not _whole(state.get("seed")): return false
	var rows := preview(content, int(state.seed))
	if rows.size() != 2: return false
	var ids: Array[String] = []
	var effects := {}
	for row in rows:
		ids.append(row.id)
		for key in row.bonuses: effects[key] = float(effects.get(key, 1.0)) * float(row.bonuses[key])
	state.expedition_modifiers = {"enabled":true, "version":VERSION, "ids":ids, "bonuses":effects}
	return true


## 반환값은 복제다. 조회자가 값을 바꿔도 저장된 효과에 영향을 주지 않는다.
static func bonuses(state: Dictionary) -> Dictionary:
	if not enabled(state): return {}
	var value: Variant = state.expedition_modifiers.get("bonuses")
	return value.duplicate(true) if _effects_valid(value) else {}


static func overview(state: Dictionary, content: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not enabled(state) or not valid(state, content): return rows
	for id in state.expedition_modifiers.ids:
		rows.append(_row(str(id), content.modifiers.definitions[id]))
	return rows


static func valid(state: Dictionary, content: Dictionary) -> bool:
	if not state.has("expedition_modifiers"): return true
	var value: Variant = state.expedition_modifiers
	if not value is Dictionary or value.size() != 4: return false
	if not value.get("enabled") is bool or value.enabled != true: return false
	if not _whole(value.get("version")) or int(value.version) != VERSION: return false
	if not _whole(state.get("seed")) or not _data_valid(content.get("modifiers")): return false
	if not value.get("ids") is Array or value.ids.size() != 2: return false
	if not _effects_valid(value.get("bonuses")): return false
	var expected := preview(content, int(state.seed))
	if expected.size() != 2: return false
	var combined := {}
	for index in 2:
		if not value.ids[index] is String or value.ids[index] != expected[index].id: return false
		for key in expected[index].bonuses:
			combined[key] = float(combined.get(key, 1.0)) * float(expected[index].bonuses[key])
	if value.bonuses.size() != combined.size(): return false
	for key in combined:
		if not value.bonuses.has(key) or not is_equal_approx(float(value.bonuses[key]), float(combined[key])): return false
	return true


static func _row(id: String, definition: Dictionary) -> Dictionary:
	return {"id":id, "name":str(definition.name), "kind":str(definition.kind),
		"description":str(definition.description), "hint":str(definition.hint),
		"bonuses":definition.bonuses.duplicate(true)}


static func _data_valid(value: Variant) -> bool:
	if not value is Dictionary or not _whole(value.get("version")) or int(value.version) != VERSION: return false
	if not value.get("definitions") is Dictionary or value.definitions.size() != 6: return false
	var seen: Array[String] = []
	for index in 2:
		var group: Variant = value.get(GROUPS[index])
		if not group is Array or group.size() != 3: return false
		for id in group:
			if not id is String or id in seen or not value.definitions.has(id): return false
			seen.append(id)
			var row: Variant = value.definitions[id]
			if not row is Dictionary or row.get("kind") != KINDS[index]: return false
			for key in ["name", "description", "hint"]:
				if not row.get(key) is String or row[key].is_empty(): return false
			if not _effects_valid(row.get("bonuses")) or row.bonuses.is_empty(): return false
	return true


static func _effects_valid(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty() or value.size() > EFFECTS.size(): return false
	for key in value:
		if not key is String or key not in EFFECTS: return false
		if not _number(value[key]) or float(value[key]) < 0.5 or float(value[key]) > 1.5: return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) == floor(float(value))
