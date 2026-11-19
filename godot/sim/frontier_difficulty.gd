class_name FrontierDifficulty
extends RefCounted
## 새 부임에서 선택한 난도만 적용한다. 옛 회차에는 필드를 추가하지 않는다.

const MAX_LEVEL := 5
static var _cached: Dictionary = {}


static func definitions(content: Dictionary = {}) -> Dictionary:
	return _data(content).duplicate(true)


static func _data(content: Dictionary = {}) -> Dictionary:
	if content.has("frontier_difficulty"): return content.frontier_difficulty
	if _cached.is_empty(): _cached = Content._load("res://content/frontier_difficulty.json")
	return _cached


static func enabled(state: Dictionary) -> bool:
	return state.get("frontier_difficulty") is Dictionary and state.frontier_difficulty.get("enabled") == true


static func unlocked(profile: Dictionary) -> int:
	var highest := 0
	for receipt in profile.get("receipts", {}).values():
		if not receipt is Dictionary or receipt.get("success") != true or receipt.get("reason") != "완주" or int(receipt.get("week", 0)) != 52: continue
		var cleared := int(receipt.get("difficulty_level", 0))
		if cleared >= 0 and cleared <= MAX_LEVEL: highest = maxi(highest, mini(MAX_LEVEL, cleared + 1))
	return highest


static func _row(level: int, content: Dictionary = {}) -> Dictionary:
	var row := {"level":level,"name":"개척 난도 %d" % level,"rules":[],"mods":{},"bonus_points":level * 2}
	for rule in _data(content).rules:
		if int(rule.level) > level: continue
		row.rules.append(rule.duplicate(true))
		for key in rule.mods: row.mods[key] = float(row.mods.get(key, 1.0)) * float(rule.mods[key])
	return row


static func overview(profile: Dictionary, content: Dictionary = {}) -> Dictionary:
	var maximum := unlocked(profile)
	var result := {"unlocked":maximum,"levels":[]}
	for level in range(MAX_LEVEL + 1):
		var row := _row(level,content)
		row["unlocked"] = level <= maximum
		row["error"] = "" if row.unlocked else "개척 난도 %d에서 52주 목표와 시련을 달성하세요." % (level - 1)
		result.levels.append(row)
	return result


static func setup(state: Dictionary, profile: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if not config.has("difficulty") or not RealmRules.enabled(state): return false
	if state.has("frontier_difficulty"): return valid(state,content)
	var requested: Variant = config.difficulty
	var level := int(requested) if _whole(requested) else 0
	level = clampi(level,0,unlocked(profile))
	state.frontier_difficulty = {"enabled":true,"version":1,"level":level,"unlocked_at_start":unlocked(profile)}
	return true


static func bonuses(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var mods := {}
	if not enabled(state): return mods
	for rule in _data(content).rules:
		if int(rule.level) > int(state.frontier_difficulty.level): continue
		for key in rule.mods: mods[key] = float(mods.get(key,1.0))*float(rule.mods[key])
	return mods


static func current(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var row := _row(int(state.frontier_difficulty.level) if enabled(state) else 0,content)
	row["enabled"] = enabled(state)
	return row


static func result(state: Dictionary, eligible: bool) -> Dictionary:
	if not enabled(state): return {}
	return {"difficulty_level":int(state.frontier_difficulty.level),"difficulty_points":int(state.frontier_difficulty.level) * 2 if eligible else 0}


static func valid(state: Dictionary, content: Dictionary = {}) -> bool:
	if not state.has("frontier_difficulty"): return true
	var value: Variant = state.frontier_difficulty
	if not value is Dictionary or value.size() != 4 or value.get("enabled") != true or not value.enabled is bool: return false
	if not _whole(value.get("version")) or value.version != 1: return false
	if not _whole(value.get("level")) or not _whole(value.get("unlocked_at_start")): return false
	return value.level <= value.unlocked_at_start and value.unlocked_at_start <= MAX_LEVEL and RealmRules.enabled(state) and data_errors(_data(content)).is_empty()


static func receipt_valid(receipt: Dictionary) -> bool:
	if not receipt.has("difficulty_level") and not receipt.has("difficulty_points"): return true
	if not _whole(receipt.get("difficulty_level")) or not _whole(receipt.get("difficulty_points")) or receipt.difficulty_level > MAX_LEVEL: return false
	return int(receipt.difficulty_points) == (int(receipt.difficulty_level) * 2 if int(receipt.get("week",0)) >= 13 else 0)


static func data_errors(data: Variant) -> Array:
	var errors := []
	if not data is Dictionary or data.get("version") != 1 or not data.get("rules") is Array or data.rules.size() != MAX_LEVEL: return ["개척 난도: 규칙 구조 오류"]
	var allowed := ["buy","maintenance","tool_use","heating","threat_growth"]
	for index in MAX_LEVEL:
		var rule: Variant = data.rules[index]
		if not rule is Dictionary or rule.get("level") != index + 1 or not rule.get("name") is String or not rule.get("text") is String or not rule.get("mods") is Dictionary: errors.append("개척 난도: 단계 오류"); continue
		if rule.mods.size() != 1 or not rule.mods.has(allowed[index]): errors.append("개척 난도: 소비 규칙 오류"); continue
		var value: Variant = rule.mods[allowed[index]]
		if not _number(value) or float(value) < 1.0 or float(value) > 1.2: errors.append("개척 난도: 배율 오류")
	return errors


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) == floor(float(value))
