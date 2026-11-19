class_name VillageRelics
extends RefCounted
## 성물은 회차 안에서만 보유·장착한다. 도감만 profile에 남는다.
## 제안 전용 난수와 주간 지급 장부를 사용하며 화면 조회·재장착은 보상을 지급하지 않는다.

const DATA_PATH := "res://content/village_relics.json"
const RESOURCE_KEYS := ["money", "food", "wood", "stone", "tools", "fuel", "iron"]


static func definitions() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed if parsed is Dictionary else {}


static func _data(content: Dictionary) -> Dictionary:
	return content.village_relics if content.get("village_relics") is Dictionary else definitions()


static func enabled(state: Dictionary) -> bool:
	var realm: Variant = state.get("realm", {})
	return realm is Dictionary and realm.get("enabled", false) == true and realm.get("sanctuary", {}) is Dictionary and realm.get("sanctuary", {}).get("enabled", false) == true


static func plus_enabled(state: Dictionary) -> bool:
	return state.get("escalation") is Dictionary and state.escalation.get("enabled", false) == true


## 회차의 드래프트 범위. 영구 발견 도감은 전체 정의를 사용한다.
static func available_ids(state: Dictionary, content: Dictionary = {}) -> Array:
	var data := _data(content)
	var ids: Array = data.relics.keys().filter(func(id): return plus_enabled(state) or data.relics[id].get("plus_only", false) != true)
	ids.sort()
	return ids


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if config.get("village_relics", false) != true or not RealmRules.enabled(state): return false
	if state.realm.has("sanctuary"): return enabled(state) and valid(state, content)
	state.realm["sanctuary"] = {"enabled":true,"version":1,"owned":[],"equipped":[],"offer":[],"offer_source":"",
		"queue":[],"sources":[],"drafts":0,"last_week":0,"last_result":{}}
	return true


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))


static func _ids(value: Variant, known: Dictionary) -> bool:
	if not value is Array: return false
	var found := []
	for id in value:
		if not id is String or not known.has(id) or id in found: return false
		found.append(id)
	return true


static func profile_valid(profile: Dictionary, content: Dictionary = {}) -> bool:
	return not profile.has("relic_discoveries") or _ids(profile.relic_discoveries, _data(content).relics)


static func valid(state: Dictionary, content: Dictionary = {}) -> bool:
	if not state.get("realm", {}) is Dictionary: return false
	if not state.get("realm", {}).has("sanctuary"): return true
	var value: Variant = state.realm.sanctuary
	if not value is Dictionary or not value.get("enabled") is bool or not _integer(value.get("version")) or value.version != 1: return false
	var data := _data(content)
	var allowed := available_ids(state, content)
	for key in ["owned", "equipped", "offer"]:
		if not _ids(value.get(key), data.relics): return false
		for id in value[key]:
			if id not in allowed: return false
	if value.equipped.size() > int(data.slots) or value.offer.size() > 3: return false
	for id in value.equipped:
		if id not in value.owned: return false
	for id in value.offer:
		if id in value.owned: return false
	for key in ["drafts", "last_week"]:
		if not _integer(value.get(key)) or float(value[key]) < 0: return false
	if float(value.last_week) > maxf(0.0, float(state.get("week", 1)) - 1.0): return false
	if not value.get("sources") is Array or not value.get("queue") is Array or not value.get("offer_source") is String: return false
	var source_ids := []
	for source in value.sources:
		if not source is String or source.is_empty() or source.length() > 160 or source in source_ids: return false
		source_ids.append(source)
	if value.offer.is_empty() != str(value.offer_source).is_empty(): return false
	if not value.offer.is_empty() and value.offer_source not in source_ids: return false
	var pending := [value.offer_source] if not value.offer.is_empty() else []
	for source in value.queue:
		if not source is String or source not in source_ids or source in pending: return false
		pending.append(source)
	if not value.get("last_result") is Dictionary: return false
	if not value.last_result.is_empty():
		var result: Dictionary = value.last_result
		if not _integer(result.get("week")) or result.week != value.last_week: return false
		if not result.get("triggered") is Array or not result.get("totals") is Dictionary or not result.get("notes") is Array: return false
		for item in result.triggered:
			if not item is Dictionary or not data.relics.has(item.get("id", "")) or not item.get("name") is String or not item.get("effects") is Dictionary: return false
			if item.id not in allowed: return false
			if not _amounts_valid(item.effects): return false
		if result.has("builds") and not OperatingBuilds.results_valid(result.builds, state, content): return false
		if not _amounts_valid(result.totals): return false
		for note in result.notes:
			if not note is String: return false
	return true


static func _amounts_valid(amounts: Dictionary) -> bool:
	for key in amounts:
		if not key is String or key not in RESOURCE_KEYS + ["health", "mood", "threat"]: return false
		if not (amounts[key] is int or amounts[key] is float) or not is_finite(float(amounts[key])): return false
	return true


static func offer_error(state: Dictionary, content: Dictionary) -> String:
	if not enabled(state): return "이번 통치에서는 마을 성물을 사용할 수 없습니다."
	if state.get("status", "") != "active": return "종료된 회차입니다."
	if available_ids(state, content).all(func(id): return id in state.realm.sanctuary.owned): return "이번 통치에서 얻을 수 있는 성물을 모두 보유하고 있습니다."
	return ""


static func request_offer(state: Dictionary, content: Dictionary, source: String) -> String:
	var error := offer_error(state, content)
	if error != "": return error
	var value: Dictionary = state.realm.sanctuary
	if source.is_empty() or source.length() > 160: return "성물을 발견한 기록이 올바르지 않습니다."
	if source in value.sources: return "이미 처리한 성물 발견입니다."
	value.sources.append(source)
	value.queue.append(source)
	_next_offer(state, content)
	return ""


static func _next_offer(state: Dictionary, content: Dictionary, avoid: Array = []) -> void:
	var value: Dictionary = state.realm.sanctuary
	if not value.offer.is_empty() or value.queue.is_empty(): return
	var available: Array = available_ids(state, content).filter(func(id): return id not in value.owned)
	if available.is_empty():
		value.queue.clear()
		return
	value.offer_source = str(value.queue.pop_front())
	var random := Xoshiro128.new(int(state.seed) ^ ((int(value.drafts) * 7919 + 19087) & 0x7fffffff), 11)
	var focused := LegacyPath.relic_focus(state, str(value.offer_source))
	var original := available.duplicate()
	for index in mini(3, available.size()):
		var matching := OperatingBuilds.matching_relics(state, content, available) if index == 0 else []
		if index == 0 and not focused.is_empty():
			var family: Array = available.filter(func(id): return _data(content).relics[id].category == focused)
			if not family.is_empty(): matching = family
		if not matching.is_empty():
			var id := str(matching[random.randi_range(0, matching.size() - 1)])
			value.offer.append(id)
			available.erase(id)
			continue
		var picked := random.randi_range(0, available.size() - 1)
		value.offer.append(str(available[picked]))
		available.remove_at(picked)
	if not avoid.is_empty() and value.offer.all(func(id): return id in avoid):
		var fresh: Array = original.filter(func(id): return id not in avoid and id not in value.offer)
		if not fresh.is_empty(): value.offer[value.offer.size() - 1] = str(fresh[random.randi_range(0, fresh.size() - 1)])
	value.drafts = int(value.drafts) + 1


static func refresh_offer(state: Dictionary, content: Dictionary) -> String:
	if not enabled(state) or state.get("status", "") != "active" or state.realm.sanctuary.offer.is_empty(): return "새로고침할 성물 제안이 없습니다."
	if int(state.get("legacy_setup", {}).get("relic_refreshes", 0)) <= 0: return "남은 성물 새로고침권이 없습니다."
	var value: Dictionary = state.realm.sanctuary
	var previous: Array = value.offer.duplicate()
	var available := available_ids(state, content).filter(func(id): return id not in value.owned and id not in previous)
	if available.is_empty(): return "새롭게 제안할 성물이 없습니다."
	var source := str(value.offer_source)
	value.offer.clear()
	value.offer_source = ""
	value.queue.push_front(source)
	_next_offer(state, content, previous)
	state.legacy_setup.relic_refreshes -= 1
	return ""


static func choose(state: Dictionary, content: Dictionary, id: String, replace_id: String = "", profile: Dictionary = {}) -> String:
	if not enabled(state) or state.get("status", "") != "active": return "성물을 선택할 수 없습니다."
	var value: Dictionary = state.realm.sanctuary
	if id not in value.offer or id in value.owned or id not in available_ids(state, content): return "제안된 성물 중 하나를 선택하세요."
	if not replace_id.is_empty() and replace_id not in value.equipped: return "교체할 성물이 장착되어 있지 않습니다."
	value.owned.append(id)
	if not replace_id.is_empty(): value.equipped[value.equipped.find(replace_id)] = id
	elif value.equipped.size() < int(_data(content).slots): value.equipped.append(id)
	if not profile.has("relic_discoveries"): profile["relic_discoveries"] = []
	if id not in profile.relic_discoveries: profile.relic_discoveries.append(id)
	value.offer.clear()
	value.offer_source = ""
	_next_offer(state, content)
	return ""


static func equip(state: Dictionary, content: Dictionary, id: String, replace_id: String = "") -> String:
	if not enabled(state) or state.get("status", "") != "active": return "성물을 장착할 수 없습니다."
	var value: Dictionary = state.realm.sanctuary
	if id not in value.owned or id not in available_ids(state, content): return "이번 통치에서 보유한 성물이 아닙니다."
	if id in value.equipped: return "이미 장착한 성물입니다."
	if not replace_id.is_empty():
		if replace_id not in value.equipped: return "교체할 성물이 장착되어 있지 않습니다."
		value.equipped[value.equipped.find(replace_id)] = id
	elif value.equipped.size() < int(_data(content).slots): value.equipped.append(id)
	else: return "세 칸이 모두 찼습니다. 교체할 성물을 선택하세요."
	return ""


static func unequip(state: Dictionary, id: String) -> String:
	if not enabled(state) or state.get("status", "") != "active": return "성물을 보관할 수 없습니다."
	if id not in state.realm.sanctuary.equipped: return "장착하지 않은 성물입니다."
	state.realm.sanctuary.equipped.erase(id)
	return ""


static func bonuses(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"mods":{},"targets":{},"sets":[],"surges":[]}
	if not enabled(state): return result
	var data := _data(content)
	var counts := {}
	var new_families := []
	for id in state.realm.sanctuary.equipped:
		var definition: Dictionary = data.relics[id]
		if definition.get("plus_only", false) == true:
			if not plus_enabled(state): continue
			if definition.category not in new_families: new_families.append(definition.category)
		_merge(result, definition)
		counts[definition.category] = int(counts.get(definition.category, 0)) + 1
	for category in data.categories:
		if int(counts.get(category, 0)) >= 2:
			_merge(result, data.categories[category])
			result.sets.append(str(category))
		if int(counts.get(category, 0)) >= 3 and category in new_families:
			_merge(result, data.categories[category].get("plus_set", {}))
			result.surges.append(str(category))
	_merge(result, OperatingBuilds.bonuses(state, content))
	return result


static func _merge(result: Dictionary, definition: Dictionary) -> void:
	for key in definition.get("mods", {}): result.mods[key] = float(result.mods.get(key, 1.0)) * float(definition.mods[key])
	for key in definition.get("targets", {}): result.targets[key] = float(result.targets.get(key, 0.0)) + float(definition.targets[key])


static func after_week(before: Dictionary, state: Dictionary, content: Dictionary, report: Dictionary) -> Dictionary:
	var week := int(report.get("week", 0))
	var result := {"week":week,"triggered":[],"builds":[],"totals":{},"notes":[]}
	if not enabled(state) or not enabled(before) or report.get("advanced", false) != true: return result
	if state.get("status", "") != "active": return result
	if int(before.get("week", 0)) != week or int(state.get("week", 0)) != week + 1 or before.get("run_id", "") != state.get("run_id", ""): return result
	var value: Dictionary = state.realm.sanctuary
	if int(value.last_week) >= week: return result
	var previous: Array = before.get("ledger", [])
	var current: Array = state.get("ledger", [])
	if current.size() < previous.size() or current.slice(0,previous.size()) != previous: return result
	var entries: Array = current.slice(previous.size())
	var receipt := TurnReceipt.build(before,state,report)
	if not receipt.valid: return result
	if int(state.get("pop", 0)) <= 0:
		value.last_week = week
		value.last_result = result.duplicate(true)
		return result
	var data := _data(content)
	# 한 성물의 지급으로 같은 주 다른 성물의 비용을 충당하지 않는다.
	# 지급은 모두 같은 주의 실제 생산·소비 장부를 기준으로 판정한다.
	var spendable: Dictionary = state.public.duplicate(true)
	var reserved := RealmRules.held(state, content)
	for key in RESOURCE_KEYS:
		spendable[key] = maxf(0.0, float(spendable.get(key, 0)) - float(reserved.get(key, 0)))
	var outcome := state.duplicate(true)
	var candidates := []
	for id in before.realm.sanctuary.equipped:
		var definition: Dictionary = data.relics[id]
		if definition.get("plus_only", false) == true and not plus_enabled(before): continue
		if not _trigger(str(definition.get("trigger", "")), before, outcome, entries, receipt, content): continue
		candidates.append({"id":str(id),"name":str(definition.name),"reward":definition.get("reward", {}),"source":"relic:" + str(id),"kind":"triggered"})
	var builds: Dictionary = OperatingBuilds.definitions(content).get("builds", {})
	for id in OperatingBuilds.active(before, content):
		var definition: Dictionary = builds[id]
		if not OperatingBuilds.triggered(str(definition.get("trigger", id)), before, outcome, entries, receipt): continue
		candidates.append({"id":str(id),"name":str(definition.name),"reward":definition.get("reward", {}),"source":"build:" + str(id),"kind":"builds"})
	for candidate in candidates:
		var reward: Dictionary = candidate.reward
		if not _can_pay(reward, spendable) or not _has_gain(reward, state): continue
		for key in reward:
			if key in RESOURCE_KEYS and float(reward[key]) < 0: spendable[key] = float(spendable.get(key, 0)) + float(reward[key])
		var actual := {}
		for key in reward:
			var amount := float(reward[key])
			if key in RESOURCE_KEYS:
				if key == "money":
					state.public.money = int(state.public.money) + int(amount)
					amount = int(amount)
				else: state.public[key] = float(state.public[key]) + amount
				WeekSim._ledger(state,week,str(candidate.source),str(key),amount)
			elif key == "threat":
				var old := float(state.realm.threat)
				state.realm.threat = maxf(0.0,old + amount)
				amount = float(state.realm.threat) - old
			else:
				var old := float(state[key])
				state[key] = clampf(old + amount,0.0,100.0)
				amount = float(state[key]) - old
			if not is_zero_approx(amount):
				actual[str(key)] = amount
				result.totals[str(key)] = float(result.totals.get(key,0.0)) + amount
		if actual.is_empty(): continue
		result[candidate.kind].append({"id":str(candidate.id),"name":str(candidate.name),"effects":actual})
		var note := "%s · %s" % [candidate.name,RealmRules.changes_text(actual)]
		result.notes.append(note)
		if report.get("notes") is Array: report.notes.append(note)
	value.last_week = week
	value.last_result = result.duplicate(true)
	return result


static func _can_pay(reward: Dictionary, stock: Dictionary) -> bool:
	for key in reward:
		if key in RESOURCE_KEYS and float(reward[key]) < 0 and float(stock.get(key, 0)) < -float(reward[key]): return false
	return true


## 앞선 성물로 이미 회복·진압을 마쳤다면 비용만 내는 교환을 실행하지 않는다.
static func _has_gain(reward: Dictionary, state: Dictionary) -> bool:
	for key in reward:
		var amount := float(reward[key])
		if key in RESOURCE_KEYS and amount > 0: return true
		if key == "threat" and amount < 0 and float(state.realm.threat) > 0: return true
		if key in ["health", "mood"] and amount > 0 and float(state[key]) < 100: return true
	return false


static func _flow(entries: Array, source: String, asset: String, income: bool = true) -> float:
	var total := 0.0
	for entry in entries:
		if entry.get("src", "") == source and entry.get("asset", "") == asset:
			total += maxf(0.0, float(entry.get("qty", 0)) * (1.0 if income else -1.0))
	return total


static func _warm(before: Dictionary, state: Dictionary, entries: Array) -> bool:
	return WeekSim.season_of(WeekSim.week_of_year(int(before.week))) == 3 and float(state.get("heat_fill", 0)) >= 1.0 and _flow(entries, "heating", "fuel", false) > 0


static func _fed(before: Dictionary, state: Dictionary, entries: Array) -> bool:
	return float(before.ration) >= 1.0 and float(state.food_satisfaction) >= 1.0 and _flow(entries, "consume", "food", false) > 0


static func _trigger(id: String, before: Dictionary, state: Dictionary, entries: Array, receipt: Dictionary, content: Dictionary) -> bool:
	match id:
		"food_crew":
			if before.get("workcrew", {}).get("policy", "") != "food": return false
			var produced := 0.0
			for entry in entries:
				if entry.get("src", "") in ["gather", "garden"] and entry.get("asset", "") == "food": produced += maxf(0.0,float(entry.get("qty",0.0)))
			return produced >= 40.0
		"completion": return not receipt.development.completed.is_empty()
		"construction": return receipt.development.work_known and int(receipt.development.work_done) >= 8
		"security": return float(state.security) >= 55.0
		"winter_care":
			return _warm(before, state, entries) and _fed(before, state, entries)
		"farm_season":
			var week := WeekSim.week_of_year(int(before.week))
			return int(state.get("plots_sown", 0)) > 0 and (week in WeekSim.SOW_WEEKS or (week >= WeekSim.HARVEST_WEEKS[0] and week <= WeekSim.HARVEST_WEEKS[1])) and int(state.get("labor_report", {}).get("farm", 0)) >= 12 and (float(state.get("sow_f_sum", 0)) > float(before.get("sow_f_sum", 0)) or _flow(entries, "harvest", "food") > 0)
		"garden_mill": return _flow(entries, "garden", "food") >= 12.0
		"water_garden": return _flow(entries, "garden", "food") >= 4.0 and WeekSim.capacity(state, content, "water") >= float(state.pop)
		"smithy": return _flow(entries, "smithy", "tools") >= 1.0
		"imports":
			for key in RESOURCE_KEYS:
				if key != "money" and _flow(entries, "trade_arrival", key) > 0: return true
			return false
		"idle_maintenance": return receipt.development.work_known and int(receipt.development.work_done) == 0 and receipt.development.completed.is_empty() and state.get("projects", []).is_empty() and _flow(entries, "maintenance", "money", false) > 0
		"patrol_fuel": return float(state.security) >= 55.0 and float(state.realm.threat) > 0
		"relief_care": return float(state.health) < 60.0 and _fed(before, state, entries)
		"winter_supply": return _warm(before, state, entries)
	return false


static func overview(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var data := _data(content)
	var result := {"enabled":enabled(state),"slots":int(data.slots),"owned":[],"equipped":[],"offer":[],"sets":[],"offer_source":"","last_result":{}}
	if not result.enabled: return result
	var value: Dictionary = state.realm.sanctuary
	for key in ["owned", "equipped", "offer"]:
		for id in value[key]:
			var row: Dictionary = data.relics[id].duplicate(true)
			row["id"] = str(id)
			row["equipped"] = id in value.equipped
			row["category_name"] = str(data.categories[row.category].name)
			result[key].append(row)
	for category in bonuses(state,content).sets:
		var row: Dictionary = data.categories[category].duplicate(true)
		row["id"] = str(category)
		result.sets.append(row)
	for category in bonuses(state,content).surges:
		var row: Dictionary = data.categories[category].plus_set.duplicate(true)
		row["id"] = str(category) + "_surge"
		result.sets.append(row)
	result.offer_source = str(value.offer_source)
	result.last_result = value.last_result.duplicate(true)
	return result
