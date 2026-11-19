class_name LegacyPath
extends RefCounted
## 가문 특성은 공훈으로 구매한다. 진행 회차에는 부임 때 복사한 특성·방침만 적용한다.

const DATA_PATH := "res://content/legacy.json"
const PERK_FAMILIES := {"agriculture":"농업", "industry":"생산", "provisions":"보존", "court":"행정"}
const RELIC_FAMILIES := {"abundance":"풍요", "craft":"공방", "guard":"수호"}
const PREPARATION_KEYS := ["supply_pack", "perk_family", "relic_family"]
const RESOURCES := {"money":"금고", "food":"공공 식량", "wood":"목재", "stone":"석재", "tools":"도구", "fuel":"장작", "iron":"철"}
static var _definition_cache: Dictionary = {}
static var _definition_time: int = -1


static func definitions() -> Dictionary:
	var modified := FileAccess.get_modified_time(DATA_PATH)
	if not _definition_cache.is_empty() and modified == _definition_time: return _definition_cache.duplicate(true)
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("가문 특성 데이터를 읽지 못했습니다: " + DATA_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("가문 특성 데이터 형식이 올바르지 않습니다.")
		return {}
	_definition_cache = parsed.duplicate(true)
	_definition_time = modified
	return parsed


static func ensure(profile: Dictionary) -> void:
	# 잘못된 기존 값을 지우지 않는다. 손상 여부는 valid로 판정한다.
	if not profile.has("legacy_talents"):
		profile.legacy_talents = {}


static func rank(profile: Dictionary, id: String) -> int:
	var talents = profile.get("legacy_talents", {})
	if not talents is Dictionary:
		return 0
	var value = talents.get(id, 0)
	return int(value) if _whole(value) and value >= 0 else 0


## 최대 단계 또는 존재하지 않는 항목은 -1. 선행 특성과 점수는 current_error에서 검사한다.
static func cost(profile: Dictionary, id: String) -> int:
	var data := definitions()
	if not data.get("talents", {}).has(id):
		return -1
	var definition: Dictionary = data.talents[id]
	var level := rank(profile, id)
	if level >= int(definition.max_rank):
		return -1
	return int(definition.costs[level])


## 기존 저장에는 legacy_talents가 없어도 된다. JSON의 정수형 실수도 허용한다.
static func valid(profile: Dictionary) -> bool:
	if profile.has("points") and (not _whole(profile.points) or profile.points < 0):
		return false
	var talents = profile.get("legacy_talents", {})
	if not talents is Dictionary:
		return false
	var data := definitions()
	if data.is_empty():
		return false
	for id in talents:
		if not id is String or not data.talents.has(id):
			return false
		var level = talents[id]
		if not _whole(level) or level < 0 or level > int(data.talents[id].max_rank):
			return false
		var prerequisite: String = data.talents[id].requires
		if level > 0 and not prerequisite.is_empty() and rank(profile, prerequisite) < 1:
			return false
	var selected: Variant = profile.get("legacy_doctrines", [])
	if not selected is Array or selected.size() > 2: return false
	var seen := []
	for id in selected:
		if not id is String or id in seen or not data.talents.has(id) or data.talents[id].get("kind", "foundation") != "doctrine" or rank(profile, id) < 1: return false
		seen.append(id)
	var preparation: Variant = profile.get("legacy_preparation", {})
	if not preparation is Dictionary: return false
	for key in preparation:
		if key not in PREPARATION_KEYS or not preparation[key] is String or _preparation_error(profile, str(key), str(preparation[key])) != "": return false
	return true


static func current_error(profile: Dictionary, id: String) -> String:
	var data := definitions()
	if not data.get("talents", {}).has(id):
		return "존재하지 않는 가문 특성입니다."
	if not valid(profile) or not profile.has("points"):
		return "가문 기록 형식이 올바르지 않습니다."
	var definition: Dictionary = data.talents[id]
	var level := rank(profile, id)
	if level >= int(definition.max_rank):
		return "최대 %d단계까지 배웠습니다." % int(definition.max_rank)
	var prerequisite: String = definition.requires
	if not prerequisite.is_empty() and rank(profile, prerequisite) < 1:
		return "%s 1단계가 필요합니다." % data.talents[prerequisite].name
	var price := int(definition.costs[level])
	if profile.points < price:
		return "공훈 %d점이 더 필요합니다." % (price - int(profile.points))
	return ""


## 회차 진행 여부는 호출자가 검사한다. 이 함수는 진행 회차 상태를 받거나 변경하지 않는다.
static func buy(profile: Dictionary, id: String) -> String:
	var error := current_error(profile, id)
	if not error.is_empty():
		return error
	var price := cost(profile, id)
	var level := rank(profile, id)
	ensure(profile)
	profile.points = int(profile.points) - price
	profile.legacy_talents[id] = level + 1
	return ""


## 무료 재분배. 기존 profile.upgrades 구매분은 그대로 보존한다.
static func refund(profile: Dictionary) -> int:
	if not valid(profile) or not profile.has("points"):
		return 0
	var returned := 0
	var data := definitions()
	for id in profile.get("legacy_talents", {}):
		for level in rank(profile, id):
			returned += int(data.talents[id].costs[level])
	profile.points = int(profile.points) + returned
	profile.legacy_talents = {}
	if profile.has("legacy_doctrines"): profile.legacy_doctrines = []
	if profile.has("legacy_preparation"): profile.legacy_preparation = {}
	return returned


## 기존 출신·장비·강화 설정 뒤, 새 회차 시작에만 호출한다. 비어 있는 스냅숏도 적용 완료다.
static func apply(state: Dictionary, profile: Dictionary) -> void:
	if state.has("legacy_snapshot") or not valid(profile):
		return
	var data := definitions()
	var snapshot := {}
	for id in profile.get("legacy_talents", {}):
		var level := rank(profile, id)
		if level > 0:
			snapshot[id] = level
	state.legacy_snapshot = snapshot
	var capability := capabilities(profile)
	var selected: Array = profile.get("legacy_doctrines", []).duplicate()
	var effects := _doctrine_effects(selected, data)
	state["legacy_setup"] = {"version":2,"doctrines":selected,"preparation":profile.get("legacy_preparation", {}).duplicate(true),
		"mods":effects.mods,"targets":effects.targets,"adds":effects.adds,
		"relic_refreshes":int(capability.relic_refresh),"perk_banishes":int(capability.perk_banish),"banished_perks":[]}
	for id in snapshot:
		var definition: Dictionary = data.talents[id]
		if definition.get("kind", "foundation") != "foundation": continue
		var level: int = snapshot[id]
		for resource in definition.resources:
			state.public[resource] += definition.resources[resource] * level
		var bonuses := {}
		for key in definition.bonuses:
			# 같은 특성의 세 단계는 선형 합산하고, 다른 출처의 효과와는 기존 규칙대로 곱한다.
			bonuses[key] = 1.0 + float(definition.bonuses[key]) * level
		ChronicleRules.apply_bonuses(state, bonuses)
		var adds := {}
		for key in definition.get("adds", {}): adds[key] = float(definition.adds[key]) * level
		ChronicleRules.apply_bonuses(state, adds)
	state.refreshes += int(capability.perk_refresh)
	for key in effects.resources: state.public[key] = maxf(0.0, float(state.public[key]) + float(effects.resources[key]))
	var pack := str(state.legacy_setup.preparation.get("supply_pack", ""))
	if not pack.is_empty():
		for key in data.talents[pack].choice.resources: state.public[key] += data.talents[pack].choice.resources[key]
	# JSON의 400.0을 더해도 화폐 상태는 정수 동 단위를 유지한다.
	state.public.money = int(state.public.money)


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func capabilities(profile: Dictionary) -> Dictionary:
	var result := {"perk_refresh":0,"perk_focus":false,"relic_focus":false,"relic_refresh":0,"perk_banish":0,"equipment_budget":0}
	var data := definitions()
	for id in profile.get("legacy_talents", {}):
		if rank(profile, str(id)) <= 0 or not data.talents.has(id): continue
		var choice: Dictionary = data.talents[id].get("choice", {})
		var type := str(choice.get("type", ""))
		if type in ["perk_focus", "relic_focus"]: result[type] = true
		elif result.has(type): result[type] = int(result[type]) + int(choice.get("amount", 1)) * rank(profile, str(id))
	return result


static func equipment_budget(profile: Dictionary) -> int:
	return 3 + (1 if "M20" in profile.get("upgrades", []) else 0) + int(capabilities(profile).equipment_budget)


static func _preparation_error(profile: Dictionary, key: String, value: String) -> String:
	if key not in PREPARATION_KEYS: return "알 수 없는 부임 준비 항목입니다."
	if value.is_empty(): return ""
	var data := definitions()
	if key == "supply_pack":
		if not data.talents.has(value) or data.talents[value].get("choice", {}).get("type", "") != "supply_pack": return "알 수 없는 지원 물자입니다."
		return "해당 지원 물자를 먼저 해금하세요." if rank(profile, value) < 1 else ""
	var capability := capabilities(profile)
	if key == "perk_family":
		if not PERK_FAMILIES.has(value): return "알 수 없는 특전 계열입니다."
		return "첫 특전 계열 지정권이 필요합니다." if not capability.perk_focus else ""
	if not RELIC_FAMILIES.has(value): return "알 수 없는 성물 계열입니다."
	return "첫 성물 계열 지정권이 필요합니다." if not capability.relic_focus else ""


static func set_preparation(profile: Dictionary, key: String, value: String) -> String:
	if not valid(profile): return "가문 기록 형식이 올바르지 않습니다."
	var error := _preparation_error(profile, key, value)
	if error != "": return error
	if not profile.has("legacy_preparation"): profile["legacy_preparation"] = {}
	if value.is_empty(): profile.legacy_preparation.erase(key)
	else: profile.legacy_preparation[key] = value
	return ""


static func doctrine_error(profile: Dictionary, id: String, replace_id: String = "") -> String:
	var data := definitions()
	if not data.talents.has(id) or data.talents[id].get("kind", "") != "doctrine": return "알 수 없는 가문 방침입니다."
	if rank(profile, id) < 1: return "가문 방침을 먼저 해금하세요."
	var selected: Array = profile.get("legacy_doctrines", [])
	if id in selected: return "이미 선택한 방침입니다."
	if not replace_id.is_empty() and replace_id not in selected: return "교체할 방침이 선택되어 있지 않습니다."
	if selected.size() >= 2 and replace_id.is_empty(): return "두 방침을 선택했습니다. 교체할 방침을 고르세요."
	return ""


static func select_doctrine(profile: Dictionary, id: String, replace_id: String = "") -> String:
	if not valid(profile): return "가문 기록 형식이 올바르지 않습니다."
	var error := doctrine_error(profile, id, replace_id)
	if error != "": return error
	if not profile.has("legacy_doctrines"): profile["legacy_doctrines"] = []
	if replace_id.is_empty(): profile.legacy_doctrines.append(id)
	else: profile.legacy_doctrines[profile.legacy_doctrines.find(replace_id)] = id
	return ""


static func remove_doctrine(profile: Dictionary, id: String) -> String:
	if not valid(profile): return "가문 기록 형식이 올바르지 않습니다."
	if id not in profile.get("legacy_doctrines", []): return "선택된 방침이 아닙니다."
	profile.legacy_doctrines.erase(id)
	return ""


static func _doctrine_effects(ids: Array, data: Dictionary) -> Dictionary:
	var result := {"resources":{},"mods":{},"targets":{},"adds":{}}
	for id in ids:
		var definition: Dictionary = data.talents[id].get("doctrine", {})
		for group in result:
			for key in definition.get(group, {}):
				if group == "mods": result[group][key] = float(result[group].get(key, 1.0)) * float(definition[group][key])
				else: result[group][key] = float(result[group].get(key, 0.0)) + float(definition[group][key])
	return result


static func doctrine_bonuses(state: Dictionary) -> Dictionary:
	var setup: Dictionary = state.get("legacy_setup", {})
	return {"mods":setup.get("mods", {}).duplicate(true),"targets":setup.get("targets", {}).duplicate(true),"adds":setup.get("adds", {}).duplicate(true)}


static func perk_focus(state: Dictionary) -> String:
	return str(state.get("legacy_setup", {}).get("preparation", {}).get("perk_family", "")) if state.get("perks", []).is_empty() else ""


static func relic_focus(state: Dictionary, source: String) -> String:
	var sources: Array = state.get("realm", {}).get("sanctuary", {}).get("sources", [])
	if sources.is_empty() or source != sources[0]: return ""
	return str(state.get("legacy_setup", {}).get("preparation", {}).get("relic_family", ""))


static func state_valid(state: Dictionary, content: Dictionary) -> bool:
	if not state.has("legacy_setup"): return true
	var setup: Variant = state.legacy_setup
	if not setup is Dictionary or setup.get("version") != 2 or not setup.get("doctrines") is Array or not setup.get("preparation") is Dictionary: return false
	var frozen := {"legacy_talents":state.get("legacy_snapshot", {}),"legacy_doctrines":setup.doctrines,"legacy_preparation":setup.preparation}
	if not valid(frozen): return false
	var expected := _doctrine_effects(setup.doctrines, definitions())
	for group in ["mods", "targets", "adds"]:
		if not setup.get(group) is Dictionary or setup[group].size() != expected[group].size(): return false
		for key in setup[group]:
			var amount: Variant = setup[group][key]
			if not expected[group].has(key) or not (amount is int or amount is float) or not is_finite(float(amount)) or not is_equal_approx(float(amount), float(expected[group][key])): return false
	var capability := capabilities(frozen)
	for pair in [["relic_refreshes", "relic_refresh"], ["perk_banishes", "perk_banish"]]:
		if not _whole(setup.get(pair[0])) or setup[pair[0]] < 0 or setup[pair[0]] > capability[pair[1]]: return false
	if not setup.get("banished_perks") is Array: return false
	var seen := []
	for id in setup.banished_perks:
		if not id is String or not content.progression.perks.has(id) or id in seen or id in state.get("perks", []) or id in state.get("perk_offer", []): return false
		seen.append(id)
	return int(setup.perk_banishes) + seen.size() == int(capability.perk_banish)


static func effect_text(definition: Dictionary, level: int) -> String:
	if definition.get("kind", "foundation") != "foundation": return str(definition.description) if level > 0 else "미해금"
	if level <= 0: return "미습득"
	var parts: Array[String] = []
	for key in definition.get("resources", {}):
		var amount := float(definition.resources[key]) * level
		parts.append("금고 %+.1f금" % (amount / 100.0) if key == "money" else "%s %+.0f" % [RESOURCES.get(key, key), amount])
	for key in definition.get("bonuses", {}): parts.append("%s %+.0f%%" % [RealmRules.MOD_NAMES.get(key, key), float(definition.bonuses[key]) * level * 100])
	for key in definition.get("adds", {}):
		var amount := float(definition.adds[key]) * level
		parts.append("접견 신뢰 %+.0f" % amount if key == "trust" else "%s %+.0f%%p" % ["세금 수금" if key == "tax" else "겨울 채집", amount * 100])
	return " · ".join(parts)


static func preparation_options(profile: Dictionary) -> Dictionary:
	var result := {"supply_packs":[],"perk_families":[],"relic_families":[]}
	var data := definitions()
	for id in data.talents:
		var definition: Dictionary = data.talents[id]
		if definition.get("choice", {}).get("type", "") != "supply_pack": continue
		var error := _preparation_error(profile, "supply_pack", str(id))
		result.supply_packs.append({"id":str(id),"name":str(definition.name),"text":str(definition.description),"unlocked":error.is_empty(),"error":error})
	for pair in [["perk_families", "perk_family", PERK_FAMILIES], ["relic_families", "relic_family", RELIC_FAMILIES]]:
		for id in pair[2]:
			var error := _preparation_error(profile, str(pair[1]), str(id))
			result[pair[0]].append({"id":str(id),"name":str(pair[2][id]),"unlocked":error.is_empty(),"error":error})
	return result


static func overview(profile: Dictionary) -> Dictionary:
	var data := definitions()
	var result := {"branches":[],"items":[],"doctrines":[],"selected_doctrines":profile.get("legacy_doctrines", []).duplicate(),
		"preparation":profile.get("legacy_preparation", {}).duplicate(true),"preparation_options":preparation_options(profile),"capabilities":capabilities(profile),"legacy_upgrades":[],"points":int(profile.get("points", 0))}
	for id in data.branches:
		var branch: Dictionary = data.branches[id]
		result.branches.append({"id":str(id),"name":str(branch.name),"description":str(branch.description),"items":branch.talents.duplicate()})
	for id in data.talents:
		var definition: Dictionary = data.talents[id]
		var level := rank(profile, str(id))
		var kind := str(definition.get("kind", "foundation"))
		var prerequisite := str(definition.requires)
		var application := "부임 준비에서 선택한 두 방침만 다음 통치에 적용" if kind == "doctrine" else "다음 통치부터 자동 적용"
		if kind == "choice":
			application = {
				"supply_pack":"부임 준비에서 지원 물자 1종 선택",
				"perk_focus":"부임 준비에서 첫 특전 계열 선택",
				"relic_focus":"부임 준비에서 첫 성물 계열 선택",
				"perk_refresh":"통치 중 특전 선택 창에서 새로고침",
				"relic_refresh":"통치 중 성물 선택 창에서 새로고침",
				"perk_banish":"통치 중 특전 선택 창에서 후보 제외",
				"equipment_budget":"다음 부임 준비의 물자 예산에 자동 반영"
			}.get(str(definition.get("choice", {}).get("type", "")), "")
		var row := {"id":str(id),"branch":str(definition.branch),"kind":kind,"name":str(definition.name),"description":str(definition.description),
			"rank":level,"max_rank":int(definition.max_rank),"current_text":effect_text(definition,level),"next_text":effect_text(definition,level+1) if level < int(definition.max_rank) else "최대 단계",
			"cost":cost(profile,str(id)),"requires_text":"" if prerequisite.is_empty() else "%s 1단계" % data.talents[prerequisite].name,
			"error":current_error(profile,str(id)),"application_text":application,
			"selected":id in result.selected_doctrines,"selection_error":doctrine_error(profile,str(id)) if kind == "doctrine" else ""}
		result.items.append(row)
		if kind == "doctrine": result.doctrines.append(row.duplicate(true))
	var progression: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/progression.json"))
	for id in progression.upgrades:
		var upgrade: Dictionary = progression.upgrades[id]
		var owned: bool = id in profile.get("upgrades", [])
		var error := "이미 해금했습니다." if owned else "선행 가문 강화가 필요합니다." if upgrade.requires != "" and upgrade.requires not in profile.get("upgrades", []) else "공훈이 부족합니다." if int(profile.get("points", 0)) < int(upgrade.cost) else ""
		result.legacy_upgrades.append({"id":str(id),"name":str(upgrade.name),"description":str(upgrade.description),"owned":owned,"cost":int(upgrade.cost),"error":error})
	return result
