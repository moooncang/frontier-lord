class_name RealmFeedback
extends RefCounted
## 실제 사건 처리 결과와 마지막 완료 주를 읽는 순수 표시 모델. 경제·시간·난수는 변경하지 않는다.

const PUBLIC := ["money", "food", "wood", "stone", "tools", "fuel", "iron"]
const STATS := ["pop", "mood", "health", "security", "trust", "village", "guild", "trade_discount"]
const ORDER := ["money", "food", "resident_food", "wood", "stone", "tools", "fuel", "iron", "pop", "mood", "health", "security", "trust", "village", "guild", "threat", "crop", "trade_discount"]


static func snapshot(state: Dictionary) -> Dictionary:
	var values := {}
	for id in PUBLIC: values[id] = float(state.get("public", {}).get(id, 0))
	values["resident_food"] = float(state.get("resident", {}).get("food", 0))
	for id in STATS: values[id] = float(state.get(id, 0))
	var realm: Dictionary = state.get("realm", {})
	values["threat"] = float(realm.get("threat", 0))
	values["crop"] = float(realm.get("crop", 1))
	for id in realm.get("perm", {}): values["perm:" + str(id)] = float(realm.perm[id])
	return values


static func build(before: Dictionary, after: Dictionary, outcome: Dictionary, costs: Dictionary) -> Dictionary:
	var result: Dictionary = outcome.duplicate(true)
	var first := snapshot(before)
	var last := snapshot(after)
	for key in last:
		if not first.has(key): first[key] = 1.0 if str(key).begins_with("perm:") else 0.0
	for key in first:
		if not last.has(key): last[key] = 1.0 if str(key).begins_with("perm:") else 0.0
	result["feedback_version"] = 1
	result["before"] = first
	result["after"] = last
	result["costs"] = costs.duplicate(true)
	result["effects"] = {}
	result["changes"] = {}
	for key in last:
		var id := str(key)
		var delta: float = float(last[key]) - float(first[key])
		var effect := delta + float(costs.get(key, 0))
		# 기존 changes_text의 배율 표현 계약도 유지한다. 정확한 원수치는 before/after에 있다.
		if id == "crop" or id.begins_with("perm:"):
			if is_zero_approx(delta): continue
			var ratio := float(last[key]) / float(first[key]) if not is_zero_approx(float(first[key])) else 1.0
			result.changes[id] = ratio if id.begins_with("perm:") else ratio - 1.0
			result.effects[id] = result.changes[id]
		else:
			if not is_zero_approx(delta): result.changes[id] = delta
			if not is_zero_approx(effect): result.effects[id] = effect
	return result


static func outcome_lines(state: Dictionary, _content: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var outcome: Dictionary = state.get("realm", {}).get("outcome", {})
	if outcome.is_empty(): return rows
	var measured: bool = outcome.get("feedback_version", 0) == 1 and outcome.get("before") is Dictionary and outcome.get("after") is Dictionary
	var keys: Array = ORDER.duplicate()
	var extra: Array = []
	for key in outcome.get("changes", {}):
		if key not in keys: extra.append(str(key))
	extra.sort()
	keys.append_array(extra)
	for key in keys:
		var id := str(key)
		if not measured:
			if not outcome.get("changes", {}).has(id): continue
			var old: float = outcome.changes[id]
			var text := RealmRules.changes_text({id:old})
			rows.append({"id":id, "label":_label(id), "measured":false, "before":0.0, "after":0.0,
				"delta":0.0, "cost":0.0, "effect":old, "before_text":"", "after_text":"", "net_text":"",
				"cost_text":"확인할 수 없음", "effect_text":text, "favorable":0, "note":"이전 저장의 효과 기록 · 실제 지출과 순변화는 기록되지 않았습니다."})
			continue
		var before: float = outcome.before.get(id, 1.0 if id.begins_with("perm:") else 0.0)
		var after: float = outcome.after.get(id, before)
		var delta := after - before
		var cost := float(outcome.get("costs", {}).get(id, 0))
		var effect := delta + cost
		if is_zero_approx(delta) and is_zero_approx(cost) and is_zero_approx(effect): continue
		var relative := (after / before - 1.0) if not is_zero_approx(before) else 0.0
		rows.append({"id":id, "label":_label(id), "measured":true, "before":before, "after":after,
			"delta":delta, "cost":cost, "effect":effect, "before_text":_amount(id,before), "after_text":_amount(id,after),
			"net_text":_change(id,delta,relative), "cost_text":_change(id,-cost) if cost > 0 else "",
			"effect_text":_change(id,effect,relative) if not is_zero_approx(effect) else "", "favorable":_favorable(id,delta), "note":""})
	if outcome.get("fantasy") is Dictionary:
		rows.append({"id":"fantasy","label":"이계 협약","measured":false,"before":0.0,"after":0.0,"delta":0.0,"cost":0.0,"effect":0.0,
			"before_text":"","after_text":"","net_text":"","cost_text":"","effect_text":str(outcome.fantasy.get("text","")),"favorable":1,"note":""})
	return rows


static func weekly(state: Dictionary, content: Dictionary) -> Dictionary:
	var result := {"completed":[], "unlocked":[], "promoted":false, "rank_name":"", "news":[], "week":0}
	var receipt: Dictionary = state.get("last_receipt", {})
	if not receipt.get("valid", false): return result
	if int(receipt.get("week", 0)) != int(state.get("week", 1)) - 1: return result
	result.week = int(receipt.week)
	var previous: Dictionary = state.get("facilities", {}).duplicate(true)
	for built in receipt.get("development", {}).get("completed", []):
		var id := str(built.get("id", ""))
		if not content.facilities.has(id) or int(built.get("count", 0)) <= 0: continue
		result.completed.append({"id":id, "name":str(content.facilities[id].name), "count":int(built.count)})
		previous[id] = maxi(0,int(previous.get(id,0))-int(built.count))
	if not RealmRules.enabled(state): return result
	var ids: Array = content.facilities.keys()
	ids.sort()
	for id in ids:
		var facility: Dictionary = content.facilities[id]
		if facility.grade == "T" or int(state.facilities.get(id,0)) > 0: continue
		if facility.get("fantasy",false) and not FantasyFrontiers.build_error(state,content,str(id)).is_empty(): continue
		var requires: Array = facility.get("requires", [])
		if requires.is_empty(): continue
		if _requirements(state.facilities,requires) and not _requirements(previous,requires):
			result.unlocked.append({"id":str(id), "name":str(facility.name)})
	result.news = state.realm.get("news", []).duplicate(true)
	var rank := int(state.realm.get("rank", 0))
	if rank >= 0 and rank < content.realm.ranks.size(): result.rank_name = str(content.realm.ranks[rank].name)
	for item in result.news:
		if item.get("kind", "") == "rank" and int(item.get("week",0)) == int(result.week): result.promoted = true
	return result


static func _requirements(facilities: Dictionary, requires: Array) -> bool:
	return requires.all(func(id): return int(facilities.get(id,0)) > 0)


static func _label(id: String) -> String:
	if id == "food": return "공공 식량"
	if id == "trade_discount": return "운송료 할인"
	if id == "iron": return "철"
	if id.begins_with("perm:"): return str(RealmRules.MOD_NAMES.get(id.trim_prefix("perm:"),id)) + " (남은 통치)"
	return str(RealmRules.NAMES.get(id,id))


static func _amount(id: String, value: float) -> String:
	if id == "money": return _number(value/100.0) + "금"
	if id == "trade_discount": return _number(value*100.0) + "%"
	if id == "crop" or id.begins_with("perm:"): return "×" + _number(value)
	return _number(value) + ("명" if id == "pop" else "")


static func _change(id: String, value: float, relative: float = 0.0) -> String:
	if id == "money": return _signed(value/100.0) + "금"
	if id == "trade_discount": return _signed(value*100.0) + "%p"
	if id == "crop" or id.begins_with("perm:"): return _signed(relative*100.0) + "%"
	return _signed(value) + ("명" if id == "pop" else "")


static func _favorable(id: String, delta: float) -> int:
	var direction := -1 if id in ["threat","perm:tool_use","perm:buy","perm:spoil","perm:heating","perm:sow_labor","perm:maintenance","perm:build_work"] else 1
	return int(signf(delta)) * direction


static func _number(value: float) -> String:
	if is_equal_approx(value,roundf(value)): return "%.0f" % value
	return ("%.2f" % value).trim_suffix("0").trim_suffix(".")


static func _signed(value: float) -> String:
	return ("−" if value < 0 else "+") + _number(absf(value))
