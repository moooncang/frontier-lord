class_name Content
## 콘텐츠 JSON 로드와 검증(07번 6절). 임의 스크립트는 데이터에서 실행하지 않는다.


static func load_all() -> Dictionary:
	var events := _load("res://content/events.json")
	events.merge(_load("res://content/realm_events.json"))
	events.merge(_load("res://content/relic_events.json"))
	events.merge(_load("res://content/realm_events_plus.json"))
	events.merge(_load("res://content/realm_events_good.json"))
	events.merge(_load("res://content/realm_events_bad.json"))
	var fantasy := _load("res://content/fantasy_frontiers.json")
	events.merge(fantasy.events)
	var facilities := _load("res://content/facilities.json")
	facilities.merge(fantasy.facilities)
	return {
		"fantasy_frontiers":fantasy,
		"realm": _load("res://content/realm.json"),
		"village_relics": _load("res://content/village_relics.json"),
		"operating_builds": _load("res://content/operating_builds.json"),
		"facilities": facilities,
		"charters": _load("res://content/charters.json"),
		"events": events,
		"progression": _load("res://content/progression.json"),
		"legacy": _load("res://content/legacy.json"),
		"assets": _load("res://content/assets.json"),
		"chronicle": _load("res://content/chronicle.json"),
		"campaign": _load("res://content/campaign.json"),
		"workcrew": _load("res://content/workcrew.json"),
		"modifiers": _load("res://content/modifiers.json"),
		"crises": _load("res://content/crises.json"),
		"seasonal_support": _load("res://content/seasonal_support.json"),
		"frontier_difficulty": _load("res://content/frontier_difficulty.json"),
	}


static func _load(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "JSON 파싱 실패: " + path)
	return parsed


## 오류 문장 배열을 돌려준다. 비어 있으면 통과.
static func validate(c: Dictionary) -> Array:
	var errors := []
	for id in c.facilities:
		var d: Dictionary = c.facilities[id]
		for k in ["name", "grade", "stage", "kind"]:
			if not d.has(k):
				errors.append("%s: %s 없음" % [id, k])
		if not Constants.GRADE_COST.has(d.get("grade")):
			errors.append("%s: 등급 %s 없음" % [id, d.get("grade")])
		for k in ["storage", "housing", "water", "admin", "spoilage"]:
			if d.has(k) and d[k] < 0:
				errors.append("%s: %s 음수" % [id, k])
		if d.has("storage") != d.has("spoilage"):
			errors.append("%s: storage와 spoilage는 함께 있어야 함" % id)
	for id in c.charters:
		var st: Dictionary = c.charters[id].start
		for fid in st.facilities:
			if not c.facilities.has(fid):
				errors.append("%s: 시설 %s 없음" % [id, fid])
		for acct in ["public", "resident"]:
			for k in st[acct]:
				if st[acct][k] < 0:
					errors.append("%s: %s.%s 음수" % [id, acct, k])
	for id in c.events:
		var event: Dictionary = c.events[id]
		if event.get("options", []).is_empty():
			errors.append("%s: 선택지 없음" % id)
		elif not event.options.any(func(o): return o.get("cost", {}).is_empty() and not o.has("requires_housing")):
			errors.append("%s: 비용 없는 대안 없음" % id)
	for id in c.facilities:
		for need in c.facilities[id].get("requires", []):
			if not c.facilities.has(need):
				errors.append("%s: 선행 시설 %s 없음" % [id, need])
	for id in c.events:
		if c.events[id].get("tone", "") not in ["", "positive", "negative"]:
			errors.append("%s: 사건 분류 오류" % id)
		for option in c.events[id].get("options", []):
			if option.has("followup") and not c.events.has(option.followup.id):
				errors.append("%s: 후속 사건 %s 없음" % [id, option.followup.id])
			var need: Dictionary = option.get("requires", {})
			if need.has("facility") and not c.facilities.has(need.facility):
				errors.append("%s: 선택 조건 시설 %s 없음" % [id, need.facility])
			if need.has("policy") and not c.get("realm", {}).get("policies", {}).has(need.policy):
				errors.append("%s: 선택 조건 정책 %s 없음" % [id, need.policy])
			if need.has("relic_family") and not c.get("village_relics", {}).get("categories", {}).has(need.relic_family):
				errors.append("%s: 선택 조건 성물 계열 %s 없음" % [id, need.relic_family])
	for id in c.get("realm", {}).get("policies", {}):
		var need := str(c.realm.policies[id].get("requires", ""))
		if need != "" and not c.facilities.has(need):
			errors.append("%s: 정책 조건 시설 %s 없음" % [id, need])
	for id in c.progression.upgrades:
		var upgrade: Dictionary = c.progression.upgrades[id]
		if upgrade.cost < 0 or (upgrade.requires != "" and not c.progression.upgrades.has(upgrade.requires)):
			errors.append("%s: 업그레이드 조건 오류" % id)
	_validate_operating_builds(c, errors)
	_validate_legacy(c, errors)
	errors.append_array(SeasonalInvestments.data_errors(c.get("seasonal_support")))
	errors.append_array(FrontierDifficulty.data_errors(c.get("frontier_difficulty")))
	errors.append_array(FantasyFrontiers.data_errors(c.get("fantasy_frontiers"),c))
	return errors


## 표시만 존재하는 해금, 잘못된 단계 가격, 선행 순환을 시작 전에 검출한다.
static func _validate_legacy(c: Dictionary, errors: Array) -> void:
	var data: Variant = c.get("legacy")
	if not data is Dictionary or data.get("version") != 2:
		errors.append("가문 강화: 버전 2 정의 필요")
		return
	if not data.get("branches") is Dictionary or not data.get("talents") is Dictionary:
		errors.append("가문 강화: 계열·특성 목록 오류")
		return
	var branches: Dictionary = data.branches
	var talents: Dictionary = data.talents
	if branches.is_empty() or talents.is_empty(): errors.append("가문 강화: 빈 목록")
	var listed := []
	for branch in branches:
		var group: Variant = branches[branch]
		if not group is Dictionary or not group.get("name") is String or not group.get("talents") is Array:
			errors.append("가문 강화: 계열 %s 형식 오류" % str(branch))
			continue
		for id in group.talents:
			if not id is String or id in listed or not talents.has(id):
				errors.append("가문 강화: 계열 항목 %s 중복 또는 참조 오류" % str(id))
				continue
			listed.append(id)
			if not talents[id] is Dictionary or talents[id].get("branch") != branch:
				errors.append("가문 강화: %s 계열 불일치" % id)
	var raw_mods := ["logging","wages","maintenance","gather","harvest","seed","buy","storage","heating","tool_use","sow_labor","garden","quarry","smithy"]
	var resources := ["money","food","wood","stone","tools","fuel"]
	var choices := ["supply_pack","perk_refresh","perk_focus","relic_focus","relic_refresh","perk_banish","equipment_budget"]
	for id in talents:
		var item: Variant = talents[id]
		var label := "가문 특성 %s" % str(id)
		if not id is String or not item is Dictionary:
			errors.append(label + ": 형식 오류")
			continue
		for field in ["name","description","branch","kind","requires"]:
			if not item.get(field) is String or (field != "requires" and str(item.get(field, "")).strip_edges().is_empty()):
				errors.append(label + ": " + field + " 문자열 필요")
		if id not in listed or not branches.has(item.get("branch")): errors.append(label + ": 계열에 등록되지 않음")
		if item.get("kind") not in ["foundation","choice","doctrine"]: errors.append(label + ": 분류 오류")
		if not _legacy_whole(item.get("tier")) or float(item.get("tier", 0)) < 1: errors.append(label + ": 단계 순서 오류")
		if not _legacy_whole(item.get("max_rank")) or float(item.get("max_rank", 0)) < 1 or float(item.get("max_rank", 0)) > 3:
			errors.append(label + ": 최대 단계 오류")
			continue
		var maximum := int(item.max_rank)
		var prices: Variant = item.get("costs")
		if not prices is Array or prices.size() != maximum:
			errors.append(label + ": 단계 가격 개수 오류")
		else:
			var previous := 0.0
			for price in prices:
				if not _legacy_whole(price) or float(price) <= 0 or float(price) < previous:
					errors.append(label + ": 단계 가격은 증가하는 양의 정수 필요")
				else: previous = float(price)
		var requirement: Variant = item.get("requires")
		if requirement is String and not requirement.is_empty() and (requirement == id or not talents.has(requirement)):
			errors.append(label + ": 선행 특성 참조 오류")
		_legacy_map(item.get("resources"), resources, label + " 자원", errors, "resource")
		_legacy_map(item.get("bonuses"), raw_mods, label + " 단계 배율", errors, "increment", maximum)
		_legacy_map(item.get("adds", {}), ["tax","trust","winter_gather"], label + " 가산", errors, "finite")
		if item.get("kind") != "foundation":
			for field in ["resources","bonuses","adds"]:
				if item.get(field, {}) is Dictionary and not item.get(field, {}).is_empty(): errors.append(label + ": 해금·방침의 효과는 전용 정의에 필요")
		if item.get("kind") == "choice":
			var choice: Variant = item.get("choice")
			if maximum != 1 or not choice is Dictionary or choice.get("type") not in choices:
				errors.append(label + ": 실제 지원하는 해금 필요")
				continue
			if choice.type == "supply_pack":
				_legacy_map(choice.get("resources"), resources, label + " 지원 물자", errors, "resource")
				if choice.get("resources", {}) is Dictionary and choice.get("resources", {}).is_empty(): errors.append(label + ": 빈 지원 물자")
			elif choice.type not in ["perk_focus","relic_focus"]:
				if not _legacy_whole(choice.get("amount")) or float(choice.get("amount", 0)) < 1:
					errors.append(label + ": 해금 횟수 오류")
		elif item.get("kind") == "doctrine":
			var doctrine: Variant = item.get("doctrine")
			if maximum != 1 or not doctrine is Dictionary:
				errors.append(label + ": 방침 형식 오류")
				continue
			_legacy_map(doctrine.get("resources", {}), resources, label + " 방침 자원", errors, "resource")
			_legacy_map(doctrine.get("mods", {}), raw_mods + ["spoil","build_work"], label + " 방침 배율", errors, "multiplier")
			_legacy_map(doctrine.get("targets", {}), ["mood","health","security"], label + " 유지 기준", errors, "finite")
			_legacy_map(doctrine.get("adds", {}), ["tax","trust","winter_gather"], label + " 방침 가산", errors, "finite")
		# 존재하는 선행 조건도 순환하면 누구도 구매할 수 없다.
		var visited := [str(id)]
		var cursor := str(item.get("requires", ""))
		while not cursor.is_empty() and talents.has(cursor) and talents[cursor] is Dictionary:
			if cursor in visited:
				errors.append(label + ": 선행 조건 순환")
				break
			visited.append(cursor)
			cursor = str(talents[cursor].get("requires", ""))


static func _legacy_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _legacy_whole(value: Variant) -> bool:
	return _legacy_number(value) and float(value) == floor(float(value))


static func _legacy_map(values: Variant, allowed: Array, label: String, errors: Array, mode: String, maximum: int = 1) -> void:
	if not values is Dictionary:
		errors.append(label + ": 수치 목록 오류")
		return
	for key in values:
		if key not in allowed or not _legacy_number(values[key]):
			errors.append(label + ": 실제 지원하는 유한 수치 필요 · " + str(key))
			continue
		var amount := float(values[key])
		if mode == "resource" and (amount < 0 or (key == "money" and not _legacy_whole(values[key]))): errors.append(label + ": 음수 또는 소수 화폐")
		if mode == "increment" and 1.0 + amount * maximum <= 0: errors.append(label + ": 최대 단계 배율이 0 이하")
		if mode == "multiplier" and amount <= 0: errors.append(label + ": 배율이 0 이하")


static func _validate_operating_builds(c: Dictionary, errors: Array) -> void:
	var definitions: Dictionary = c.get("operating_builds", {}).get("builds", {})
	var relics: Dictionary = c.get("village_relics", {}).get("relics", {})
	var modifiers := ["harvest","gather","logging","garden","quarry","smithy","storage","tool_use","buy","heating","wages","maintenance","spoil","build_work","sow_labor","seed"]
	var triggers := ["harvest_trade","market_garden","granary","commons","timber_trade","stoneworks","prefab","caravan","garrison","infirmary","winter_hearth","civic"]
	for id in definitions:
		var build: Dictionary = definitions[id]
		if str(build.get("name", "")).is_empty() or str(build.get("text", "")).is_empty(): errors.append("%s: 조합 이름·설명 없음" % id)
		if not c.chronicle.families.has(build.get("family", "")) or int(build.get("perk_count", 0)) < 1: errors.append("%s: 조합 특전 조건 오류" % id)
		if build.get("trigger", "") not in triggers: errors.append("%s: 조합 발동 조건 오류" % id)
		var catalysts: Array = build.get("relics", [])
		if catalysts.size() != 2 or catalysts[0] == catalysts[1]: errors.append("%s: 서로 다른 연결 성물 2개 필요" % id)
		for relic in catalysts:
			if not relics.has(relic) or relics[relic].get("plus_only", false) != true: errors.append("%s: 연결 성물 %s 오류" % [id,relic])
		for key in build.get("mods", {}):
			var value := float(build.mods[key])
			if key not in modifiers or not is_finite(value) or value <= 0: errors.append("%s: 조합 배율 %s 오류" % [id,key])
		for key in build.get("targets", {}):
			if key not in ["mood","health","security"] or not is_finite(float(build.targets[key])): errors.append("%s: 조합 목표 %s 오류" % [id,key])
		var pays := false
		var gains := false
		for key in build.get("reward", {}):
			var value := float(build.reward[key])
			if key not in ["money","food","wood","stone","tools","fuel","health","mood","threat"] or not is_finite(value): errors.append("%s: 조합 주간 효과 %s 오류" % [id,key])
			if key in ["money","food","wood","stone","tools","fuel"] and value < 0: pays = true
			if (key == "threat" and value < 0) or (key != "threat" and value > 0): gains = true
		if not pays or not gains: errors.append("%s: 조합 교환의 비용·이득 필요" % id)
	for id in c.progression.perks:
		var perk: Dictionary = c.progression.perks[id]
		if not perk.has("build_id"): continue
		if not definitions.has(perk.build_id):
			errors.append("%s: 연결 운영 조합 없음" % id)
			continue
		if perk.get("family", "") != definitions[perk.build_id].family: errors.append("%s: 연결 조합과 특전 계열 불일치" % id)
		if perk.get("plus_only", false) != true: errors.append("%s: 확장 특전 구분 필요" % id)
		var effects: Dictionary = perk.get("extra_bonuses", {}).duplicate(true)
		effects[str(perk.get("effect", ""))] = perk.get("value", 0)
		for key in effects:
			var value := float(effects[key])
			if key not in modifiers + ["tax","trust","winter_gather"] or key in ["spoil","build_work"] or not is_finite(value) or (key not in ["tax","trust","winter_gather"] and value <= 0): errors.append("%s: 실제 적용되는 특전 효과 %s 필요" % [id,key])
