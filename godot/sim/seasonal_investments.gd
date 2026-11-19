class_name SeasonalInvestments
extends RefCounted
## 선택하지 않아도 진행되는 계절 지원. 구매 비용은 즉시 원장에 남고 효과는 계절 끝에 만료된다.

const OPEN_WEEKS := [7,20,33,46]
const RESOURCES := ["money","food","wood","stone","tools","fuel","iron"]
const MODS := ["gather","logging","tool_use","maintenance","build_work","wages","garden","spoil","storage","harvest","heating","threat_growth"]
const TARGETS := ["mood","health","security"]
static var _cached: Dictionary = {}


static func definitions(content: Dictionary = {}) -> Dictionary:
	return _data(content).duplicate(true)


static func _data(content: Dictionary = {}) -> Dictionary:
	if content.has("seasonal_support"): return content.seasonal_support
	if _cached.is_empty(): _cached = Content._load("res://content/seasonal_support.json")
	return _cached


static func enabled(state: Dictionary) -> bool:
	return state.get("seasonal_support") is Dictionary and state.seasonal_support.get("enabled") == true


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if config.get("seasonal_support", false) != true or not RealmRules.enabled(state): return false
	if state.has("seasonal_support"): return valid(state,content)
	state.seasonal_support = {"enabled":true,"version":1,"offer":{},"decisions":[],"active":{},"last_week":0}
	return true


static func _ids(content: Dictionary, season: int) -> Array:
	var result := []
	var data := _data(content)
	for id in data.definitions:
		if int(data.definitions[id].season) == season: result.append(str(id))
	result.sort()
	return result


static func after_week(before: Dictionary, state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	if not enabled(before) or not enabled(state) or report.get("advanced") != true: return
	var week := int(report.get("week",0))
	if week != int(before.week) or int(state.week) != week + 1 or before.run_id != state.run_id or week <= int(state.seasonal_support.last_week): return
	var value: Dictionary = state.seasonal_support
	value.last_week = week
	if not value.active.is_empty() and (week >= int(value.active.until) or state.pop <= 0):
		report.notes.append("계절 지원 종료 · " + str(_data(content).definitions[value.active.id].name))
		value.active = {}
	if not value.offer.is_empty() and (week >= int(value.offer.expires) or state.pop <= 0): value.offer = {}
	if state.pop <= 0 or int(state.week) > 52: return
	var season := OPEN_WEEKS.find(int(state.week))
	if season >= 0 and not value.decisions.any(func(row): return int(row.season) == season):
		value.offer = {"season":season,"opened_week":int(state.week),"expires":(season+1)*13,"ids":_ids(content,season)}
		report.notes.append("계절 지원 도착 · %d주까지 1종 선택 가능" % ((season+1)*13))


static func option_error(state: Dictionary, content: Dictionary, id: String) -> String:
	if not enabled(state) or state.get("status") != "active": return "진행 중인 계절 지원이 없습니다."
	var value: Dictionary = state.seasonal_support
	if value.offer.is_empty() or id not in value.offer.ids or int(state.week) > int(value.offer.expires): return "이번 계절에 제안된 지원이 아닙니다."
	var definition: Dictionary = _data(content).definitions[id]
	if int(state.week) > int(definition.get("last_week", value.offer.expires)): return "곡물 수확이 끝나 이번 지원은 받을 수 없습니다."
	var held := RealmRules.held(state,content)
	for asset in definition.cost:
		if float(state.public.get(asset,0)) - float(held.get(asset,0)) < float(definition.cost[asset]): return "예약 공사 몫을 제외한 %s이 부족합니다." % RealmRules.NAMES.get(asset,asset)
	return ""


static func choose(state: Dictionary, content: Dictionary, id: String) -> String:
	var error := option_error(state,content,id)
	if not error.is_empty(): return error
	var value: Dictionary = state.seasonal_support
	var definition: Dictionary = _data(content).definitions[id]
	var until_week := mini(int(value.offer.expires),int(definition.get("last_week",value.offer.expires)))
	var decision := {"season":int(value.offer.season),"id":id,"week":int(state.week),"cost":definition.cost.duplicate(true),"from":int(state.week),"until":until_week}
	for asset in definition.cost:
		state.public[asset] -= definition.cost[asset]
		WeekSim._ledger(state,int(state.week),"support:"+id,str(asset),-float(definition.cost[asset]))
	state.public.money = int(state.public.money)
	value.decisions.append(decision)
	value.active = {"id":id,"season":int(value.offer.season),"from":int(state.week),"until":until_week}
	value.offer = {}
	RealmRules.refresh(state,content)
	return ""


static func decline(state: Dictionary, content: Dictionary) -> String:
	if not enabled(state) or state.get("status") != "active" or state.seasonal_support.offer.is_empty(): return "넘길 계절 지원이 없습니다."
	var value: Dictionary = state.seasonal_support
	value.decisions.append({"season":int(value.offer.season),"id":"","week":int(state.week),"cost":{},"from":int(state.week),"until":int(value.offer.expires)})
	value.offer = {}
	return ""


static func bonuses(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"mods":{},"targets":{}}
	if not enabled(state): return result
	var active: Dictionary = state.seasonal_support.active
	if active.is_empty() or int(state.week) < int(active.from) or int(state.week) > int(active.until): return result
	var definition: Dictionary = _data(content).definitions[active.id]
	result.mods = definition.get("mods",{}).duplicate(true)
	result.targets = definition.get("targets",{}).duplicate(true)
	return result


static func _row(id: String, state: Dictionary, content: Dictionary, from_week: int, until_week: int) -> Dictionary:
	var definition: Dictionary = _data(content).definitions[id]
	until_week = mini(until_week,int(definition.get("last_week",until_week)))
	return {"id":id,"name":str(definition.name),"text":str(definition.text),"cost":definition.cost.duplicate(true),
		"mods":definition.get("mods",{}).duplicate(true),"targets":definition.get("targets",{}).duplicate(true),
		"from":from_week,"until":until_week,"weeks":maxi(0,until_week-int(state.week)+1),"error":option_error(state,content,id)}


static func overview(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"enabled":enabled(state),"season":clampi(WeekSim.season_of(int(state.get("week",1))),0,3),"title":"계절 지원","offer":[],"active":{},"expires":0,"remaining":0,"decisions":[]}
	if not enabled(state): return result
	var value: Dictionary = state.seasonal_support
	result.decisions = value.decisions.duplicate(true)
	if not value.offer.is_empty() and int(state.week) <= int(value.offer.expires) and state.status == "active":
		result.season = int(value.offer.season)
		result.expires = int(value.offer.expires)
		result.remaining = int(value.offer.expires)-int(state.week)+1
		for id in value.offer.ids: result.offer.append(_row(str(id),state,content,int(state.week),int(value.offer.expires)))
	if not value.active.is_empty() and int(state.week) <= int(value.active.until):
		result.active = _row(str(value.active.id),state,content,int(value.active.from),int(value.active.until))
		result.active.error = ""
		result.expires = int(value.active.until)
		result.remaining = int(value.active.until)-int(state.week)+1
	return result


static func valid(state: Dictionary, content: Dictionary = {}) -> bool:
	if not state.has("seasonal_support"): return true
	var value: Variant = state.seasonal_support
	if not value is Dictionary or value.size() != 6 or value.get("enabled") != true or not value.enabled is bool or value.get("version") != 1: return false
	if not RealmRules.enabled(state) or not _whole(value.get("last_week")) or int(value.last_week) > mini(52,int(state.get("week",1))-1): return false
	if not value.get("offer") is Dictionary or not value.get("active") is Dictionary or not value.get("decisions") is Array or value.decisions.size() > 4: return false
	var data := _data(content)
	if not data_errors(data).is_empty(): return false
	var seasons := []
	for decision in value.decisions:
		if not decision is Dictionary or decision.size() != 6 or not _whole(decision.get("season")) or decision.season > 3 or decision.season in seasons: return false
		seasons.append(decision.season)
		if not decision.get("id") is String or not _whole(decision.get("week")) or decision.get("from") != decision.week or not _whole(decision.get("until")): return false
		if decision.week < OPEN_WEEKS[int(decision.season)] or decision.week > decision.until or decision.week > state.week: return false
		if not decision.get("cost") is Dictionary: return false
		if decision.id == "":
			if not decision.cost.is_empty() or decision.until != (int(decision.season)+1)*13: return false
		else:
			if not data.definitions.has(decision.id): return false
			var definition: Dictionary = data.definitions[decision.id]
			if definition.season != decision.season or not _amounts_equal(decision.cost,definition.cost) or decision.week > int(definition.get("last_week",decision.until)): return false
			if int(decision.until) != mini((int(decision.season)+1)*13,int(definition.get("last_week",(int(decision.season)+1)*13))): return false
	if not value.offer.is_empty():
		var offer: Dictionary = value.offer
		if offer.size() != 4 or not _whole(offer.get("season")) or offer.season > 3 or offer.season in seasons: return false
		if offer.get("opened_week") != OPEN_WEEKS[int(offer.season)] or offer.get("expires") != (int(offer.season)+1)*13 or offer.get("ids") != _ids(content,int(offer.season)): return false
		if state.week < offer.opened_week or state.week > offer.expires: return false
	if not value.active.is_empty():
		var active: Dictionary = value.active
		if active.size() != 4 or not active.get("id") is String or not data.definitions.has(active.id): return false
		if not value.decisions.any(func(row): return row.id == active.id and row.season == active.get("season") and row.from == active.get("from") and row.until == active.get("until")): return false
		if state.week < active.from or state.week > active.until: return false
	return true


static func data_errors(data: Variant) -> Array:
	if not data is Dictionary or data.get("version") != 1 or not data.get("definitions") is Dictionary or data.definitions.size() != 12: return ["계절 지원: 12종 정의가 필요합니다."]
	var errors := []
	var counts := [0,0,0,0]
	for id in data.definitions:
		var row: Variant = data.definitions[id]
		if not row is Dictionary or not row.get("name") is String or not row.get("text") is String or not _whole(row.get("season")) or row.season > 3: errors.append("계절 지원: 이름·계절 오류"); continue
		counts[int(row.season)] += 1
		if not row.get("cost") is Dictionary or row.cost.is_empty(): errors.append("계절 지원: 비용 없음"); continue
		for key in row.cost:
			if key not in RESOURCES or not _whole(row.cost[key]) or float(row.cost[key]) <= 0: errors.append("계절 지원: 비용 오류")
		for pair in [["mods",MODS],["targets",TARGETS]]:
			var effects: Variant = row.get(pair[0],{})
			if not effects is Dictionary: errors.append("계절 지원: 효과 구조 오류"); continue
			for key in effects:
				if key not in pair[1] or not _number(effects[key]): errors.append("계절 지원: 효과 오류")
				elif pair[0] == "mods" and (effects[key] < 0.5 or effects[key] > 1.5): errors.append("계절 지원: 배율 범위 오류")
				elif pair[0] == "targets" and (effects[key] < 0 or effects[key] > 10): errors.append("계절 지원: 목표 범위 오류")
		if row.get("mods",{}).is_empty() and row.get("targets",{}).is_empty(): errors.append("계절 지원: 효과 없음")
		if row.has("last_week") and (not _whole(row.last_week) or row.last_week < OPEN_WEEKS[int(row.season)] or row.last_week > (int(row.season)+1)*13): errors.append("계절 지원: 마지막 효용 주차 오류")
	if counts != [3,3,3,3]: errors.append("계절 지원: 계절별 3종 필요")
	return errors


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _amounts_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for key in expected:
		if not actual.has(key) or not _number(actual[key]) or float(actual[key]) != float(expected[key]): return false
	return true


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) == floor(float(value))
