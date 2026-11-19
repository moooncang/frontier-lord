class_name OperatingBuilds
extends RefCounted
## 운영 조합은 보유 특전과 실제 장착 성물에서 매번 계산한다. 저장된 누적 배율은 만들지 않는다.

const DATA_PATH := "res://content/operating_builds.json"
static var _cached: Dictionary = {}


static func definitions(content: Dictionary = {}) -> Dictionary:
	if content.get("operating_builds") is Dictionary: return content.operating_builds
	if not _cached.is_empty(): return _cached
	if not FileAccess.file_exists(DATA_PATH): return {"version":1,"builds":{}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary: _cached = parsed
	return _cached if not _cached.is_empty() else {"version":1,"builds":{}}


static func enabled(state: Dictionary) -> bool:
	return VillageRelics.enabled(state) and VillageRelics.plus_enabled(state)


static func _perks(content: Dictionary) -> Dictionary:
	if content.get("progression") is Dictionary: return content.progression.get("perks", {})
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/progression.json"))
	return parsed.get("perks", {}) if parsed is Dictionary else {}


static func overview(state: Dictionary, content: Dictionary = {}) -> Array:
	var result := []
	var perks := _perks(content)
	var owned := {}
	for id in state.get("perks", []):
		if not perks.has(id): continue
		var family := str(perks[id].get("family", ""))
		owned[family] = int(owned.get(family, 0)) + 1
	var equipped: Array = state.get("realm", {}).get("sanctuary", {}).get("equipped", [])
	var builds: Dictionary = definitions(content).get("builds", {})
	for id in builds:
		var row: Dictionary = builds[id].duplicate(true)
		row["id"] = str(id)
		row["perks_owned"] = int(owned.get(row.family, 0))
		row["equipped_count"] = row.relics.filter(func(relic): return relic in equipped).size()
		row["active"] = enabled(state) and row.perks_owned >= int(row.perk_count) and row.equipped_count > 0
		result.append(row)
	return result


static func active(state: Dictionary, content: Dictionary = {}) -> Array:
	var result := []
	if not enabled(state): return result
	for row in overview(state, content):
		if row.active: result.append(str(row.id))
	return result


static func bonuses(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"mods":{},"targets":{}}
	for row in overview(state, content):
		if not row.active: continue
		for key in row.get("mods", {}): result.mods[key] = float(result.mods.get(key, 1.0)) * float(row.mods[key])
		for key in row.get("targets", {}): result.targets[key] = float(result.targets.get(key, 0.0)) + float(row.targets[key])
	return result


## 선택 전 장착·특전만 복제해서 비교한다. 자원·난수·저장 원본을 바꾸지 않는다.
static func preview(state: Dictionary, content: Dictionary, perk_id: String = "", relic_id: String = "", replace_id: String = "") -> Dictionary:
	var previous := active(state, content)
	var trial := state.duplicate(true)
	if not perk_id.is_empty() and _perks(content).has(perk_id) and perk_id not in trial.get("perks", []): trial.perks.append(perk_id)
	if enabled(trial):
		var equipped: Array = trial.realm.sanctuary.equipped
		if relic_id.is_empty() and not replace_id.is_empty(): equipped.erase(replace_id)
		elif relic_id in VillageRelics.available_ids(trial, content) and relic_id not in equipped:
			if replace_id in equipped: equipped[equipped.find(replace_id)] = relic_id
			elif replace_id.is_empty() and equipped.size() < 3: equipped.append(relic_id)
	var current := active(trial, content)
	return {"active":current,"activated":current.filter(func(id): return id not in previous),"deactivated":previous.filter(func(id): return id not in current)}


## 기존 특전 계열에 이어지는 발견 후보. 사용은 확장 회차의 첫 제안 칸에만 한정한다.
static func matching_relics(state: Dictionary, content: Dictionary, available: Array) -> Array:
	var result := []
	if not enabled(state): return result
	for row in overview(state, content):
		if row.perks_owned < 1: continue
		for id in row.relics:
			if id in available and id not in result: result.append(str(id))
	result.sort()
	return result


## 지급은 VillageRelics가 공통 가용재고·단일 주차 가드 아래 수행한다.
static func triggered(id: String, before: Dictionary, state: Dictionary, entries: Array, receipt: Dictionary) -> bool:
	match id:
		"harvest_trade": return VillageRelics._flow(entries, "harvest", "food") > 0
		"market_garden": return VillageRelics._flow(entries, "garden", "food") >= 12
		"granary": return WeekSim.food_weeks(state) >= 8 and VillageRelics._flow(entries, "maintenance", "money", false) > 0
		"commons": return float(state.mood) >= 60 and float(state.health) < 90 and VillageRelics._fed(before, state, entries)
		"timber_trade": return VillageRelics._flow(entries, "logging", "wood") >= 10
		"stoneworks": return VillageRelics._flow(entries, "quarry", "stone") >= 6
		"prefab": return receipt.development.work_known and int(receipt.development.work_done) >= 8
		"caravan":
			for key in VillageRelics.RESOURCE_KEYS:
				if key != "money" and VillageRelics._flow(entries, "trade_arrival", key) > 0: return true
			return false
		"garrison": return float(state.security) >= 55 and float(state.realm.threat) > 0
		"infirmary": return float(state.health) < 70 and VillageRelics._fed(before, state, entries)
		"winter_hearth": return VillageRelics._warm(before, state, entries)
		"civic": return float(state.mood) >= 55 and float(state.arrears_wage) <= 0 and VillageRelics._flow(entries, "wages", "money", false) > 0
	return false


static func results_valid(items: Variant, state: Dictionary, content: Dictionary = {}) -> bool:
	if not items is Array: return false
	if not items.is_empty() and not enabled(state): return false
	var builds: Dictionary = definitions(content).get("builds", {})
	var seen := []
	for item in items:
		if not item is Dictionary or not item.get("id") is String or item.id in seen or not builds.has(item.id): return false
		if not item.get("name") is String or item.name != builds[item.id].name or not item.get("effects") is Dictionary or item.effects.is_empty(): return false
		if not VillageRelics._amounts_valid(item.effects): return false
		var reward: Dictionary = builds[item.id].get("reward", {})
		for key in item.effects:
			if not reward.has(key): return false
			var amount := float(item.effects[key])
			var expected := float(reward[key])
			if key in VillageRelics.RESOURCE_KEYS:
				if not is_equal_approx(amount, expected): return false
			# 상태치의 실제 전후 차이만 부동소수 반올림 오차를 허용한다.
			elif amount * expected < 0 or absf(amount) > absf(expected) + 0.00000001: return false
		for key in reward:
			if key in VillageRelics.RESOURCE_KEYS and not item.effects.has(key): return false
		seen.append(item.id)
	return true
