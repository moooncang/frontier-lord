class_name CampaignDirector
extends RefCounted
## 새 캠페인에만 적용되는 네 계절의 목표·대가·보상. 기존 경제식과 최종 승리 판정은 유지한다.

const NAMES := {"money":"금고", "food":"식량", "wood":"목재", "stone":"석재", "tools":"도구", "fuel":"장작", "mood":"민심"}


static func enabled(state: Dictionary) -> bool:
	return state.get("campaign", {}) is Dictionary and state.get("campaign", {}).get("enabled", false) == true


static func valid(state: Dictionary, content: Dictionary) -> bool:
	if not state.has("campaign"): return true
	var campaign: Variant = state.campaign
	var data: Dictionary = content.get("campaign", {})
	if not campaign is Dictionary or data.get("phases", []).size() != 4: return false
	if not campaign.get("enabled") is bool or not _whole(campaign.get("version")) or campaign.version != data.get("version", 1): return false
	if not _whole(campaign.get("last_week")) or campaign.last_week < 0 or campaign.last_week > 52 or campaign.last_week > int(state.get("week", 0)) - 1: return false
	if not _whole(campaign.get("points")) or campaign.points < 0: return false
	if not _amounts_equal(campaign.get("balance"), data.get("balance", {})) and not data.get("legacy_balances", []).any(func(old): return _amounts_equal(campaign.get("balance"), old)): return false
	if campaign.has("regional") and not campaign.regional is bool: return false
	if not campaign.get("records") is Array or campaign.records.size() > 4: return false
	if not campaign.get("summary") is Array or campaign.summary.size() > 3: return false
	for line in campaign.summary:
		if not line is String or line.length() > 300: return false
	var seen := {}
	var earned := 0
	for record in campaign.records:
		if not record is Dictionary or not _whole(record.get("index")): return false
		var index := int(record.index)
		if index < 0 or index >= 4 or seen.has(index): return false
		seen[index] = true
		var phase: Dictionary = phases(state, content)[index]
		if record.get("id") != phase.id or record.get("season") != phase.season or record.get("title") != phase.title: return false
		if not _whole(record.get("week")) or record.week != phase.deadline or record.week > campaign.last_week: return false
		if not record.get("success") is bool or not record.get("claimed") is bool or not record.get("message") is String: return false
		if not _whole(record.get("points")) or record.points != (phase.points if record.success else 0): return false
		if not _amounts_equal(record.get("reward"), phase.reward) or not record.get("penalty") is Dictionary: return false
		if record.success:
			if not record.penalty.is_empty(): return false
			if record.claimed: earned += int(record.points)
		else:
			if not record.claimed or record.penalty.size() != phase.penalty.size(): return false
			for key in record.penalty:
				if not phase.penalty.has(key) or not _number(record.penalty[key]) or record.penalty[key] < phase.penalty[key] or record.penalty[key] > 0: return false
	return int(campaign.points) == earned


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))


static func _amounts_equal(actual: Variant, expected: Dictionary) -> bool:
	if not actual is Dictionary or actual.size() != expected.size(): return false
	for key in expected:
		if not actual.has(key) or not _number(actual[key]) or float(actual[key]) != float(expected[key]): return false
	return true


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if not bool(config.get("campaign", false)) or state.is_empty(): return false
	if enabled(state): return true
	var data: Dictionary = content.get("campaign", {})
	if data.get("phases", []).size() != 4: return false
	for key in data.get("balance", {}):
		state.bonuses[key] = WeekSim.raw_bonus(state, key) * float(data.balance[key])
	state.campaign = {"enabled":true, "version":int(data.get("version", 1)), "last_week":int(state.week) - 1,
		"points":0, "records":[], "summary":[], "balance":data.get("balance", {}).duplicate(true)}
	var region: Dictionary = data.get("regions", {}).get(str(state.get("region", "")), {})
	if bool(config.get("regional", false)) and not region.is_empty():
		# 지역의 주력 산업을 가른다. 이미 곱해진 기본 지역 배율을 새 배율로 바꿔 끼운다.
		var base: Dictionary = content.chronicle.regions[state.region].get("bonuses", {})
		for key in region.get("bonuses", {}):
			state.bonuses[key] = WeekSim.raw_bonus(state, key) * float(region.bonuses[key]) / float(base.get(key, 1.0))
		state.campaign.regional = true
	return true


## 이 통치에 적용되는 네 계절의 목표. 지역별 목표를 켠 통치는 봄·여름 목표가 지역마다 다르다.
static func phases(state: Dictionary, content: Dictionary) -> Array:
	var data: Dictionary = content.get("campaign", {})
	var result: Array = data.get("phases", []).duplicate(true)
	if not bool(state.get("campaign", {}).get("regional", false)): return result
	var overrides: Dictionary = data.get("regions", {}).get(str(state.get("region", "")), {}).get("phases", {})
	for phase in result:
		for key in overrides.get(str(phase.id), {}): phase[key] = overrides[phase.id][key]
	return result


## 부임 준비 화면에 보여 줄 지역 설명과 봄·여름 목표.
static func region_view(content: Dictionary, region: String) -> Dictionary:
	var data: Dictionary = content.get("campaign", {})
	var entry: Dictionary = data.get("regions", {}).get(region, {})
	var goals: Array[String] = []
	for phase in phases({"region":region, "campaign":{"regional":true}}, content).slice(0, 2):
		goals.append("%s · %s" % [phase.season, phase.title])
	return {"description":str(entry.get("description", content.chronicle.regions[region].description)), "hint":str(entry.get("hint", "")), "goals":goals}


static func after_week(state: Dictionary, content: Dictionary, report: Dictionary) -> Dictionary:
	if not enabled(state) or not bool(report.get("advanced", false)): return {}
	var week := int(report.get("week", 0))
	var campaign: Dictionary = state.campaign
	if week <= int(campaign.last_week) or week < 1 or week > 52 or int(state.week) != week + 1: return {}
	var data: Dictionary = content.get("campaign", {})
	if data.get("phases", []).size() != 4: return {}
	campaign.last_week = week
	var outcome := {}
	var plan := phases(state, content)
	for index in plan.size():
		var phase: Dictionary = plan[index]
		if week != int(phase.deadline): continue
		var goal := _objective(state, content, phase)
		var record := {"index":index, "id":phase.id, "season":phase.season, "week":week, "title":phase.title,
			"success":bool(goal.met), "reward":phase.reward.duplicate(true), "points":int(phase.points) if goal.met else 0,
			"claimed":false, "penalty":{}, "message":""}
		campaign.records.append(record)
		if goal.met:
			take_reward(state, content, campaign.records.size() - 1)
			record.message = "%s 목표 달성 · %s · 공훈 +%d" % [phase.season, _amounts(record.reward), record.points]
		else:
			record.penalty = _apply(state, phase.penalty, week, "campaign_penalty")
			record.claimed = true
			record.message = "%s 목표 미달 · %s" % [phase.season, _amounts(record.penalty)]
		state.log.append(record.message)
		report.notes.append(record.message)
		outcome = record.duplicate(true)
		break
	campaign.summary = _summary(state, report, outcome)
	return outcome


static func take_reward(state: Dictionary, _content: Dictionary, index: int) -> String:
	if not enabled(state): return "진행 중인 캠페인이 없습니다."
	var campaign: Dictionary = state.campaign
	if index < 0 or index >= campaign.records.size(): return "받을 계절 보상이 없습니다."
	var record: Dictionary = campaign.records[index]
	if not record.success: return "달성한 목표에만 보상이 지급됩니다."
	if record.claimed: return "이미 받은 계절 보상입니다."
	_apply(state, record.reward, int(record.week), "campaign_reward")
	campaign.points = int(campaign.points) + int(record.points)
	record.claimed = true
	return ""


static func overview(state: Dictionary, content: Dictionary) -> Dictionary:
	var empty := {"enabled":false, "index":-1, "season":"", "title":"", "deadline":0, "weeks_left":0,
		"objective":{}, "progress":0.0, "met":false, "reward_text":"", "penalty_text":"", "points":0,
		"records":[], "summary":[], "timeline":[], "chapters":[], "conditions":""}
	if not enabled(state): return empty
	var data: Dictionary = content.get("campaign", {})
	if data.get("phases", []).size() != 4: return empty
	var index := clampi(int((int(state.week) - 1) / 13.0), 0, 3)
	var plan := phases(state, content)
	var phase: Dictionary = plan[index]
	var goal := _objective(state, content, phase)
	var campaign: Dictionary = state.campaign
	var chapters: Array[Dictionary] = []
	for position in plan.size():
		var definition: Dictionary = plan[position]
		var status := "current" if position == index else "upcoming" if position > index else "missed"
		for record in campaign.records:
			if int(record.index) == position: status = "passed" if record.success else "failed"
		chapters.append({"index":position, "season":definition.season, "title":definition.title, "deadline":int(definition.deadline), "status":status})
	var timeline: Array[Dictionary] = []
	for moment in data.get("timeline", []):
		if int(moment.week) < int(state.week): continue
		var upcoming: Dictionary = moment.duplicate(true)
		upcoming.remaining = int(moment.week) - int(state.week)
		timeline.append(upcoming)
		if timeline.size() == 3: break
	return {"enabled":true, "index":index, "season":phase.season, "title":phase.title,
		"deadline":int(phase.deadline), "weeks_left":maxi(0, int(phase.deadline) - int(state.week) + 1),
		"objective":goal, "progress":goal.progress, "met":goal.met,
		"reward_text":_amounts(phase.reward) + " · 공훈 +%d" % int(phase.points), "penalty_text":_amounts(phase.penalty),
		"points":int(campaign.points), "records":campaign.records.duplicate(true), "summary":campaign.summary.duplicate(),
		"timeline":timeline, "chapters":chapters, "conditions":str(data.get("condition", ""))}


static func _objective(state: Dictionary, content: Dictionary, phase: Dictionary) -> Dictionary:
	var current := 0.0
	var target: float = float(phase.target)
	var detail := ""
	match str(phase.goal):
		"farms":
			current = float(state.facilities.get("B13", 0))
			detail = "농지 %d / %d구획" % [current, target]
		"granary":
			current = float(state.facilities.get("B22", 0))
			detail = "곡물 곳간 %d / %d개" % [current, target]
		"facilities":
			# 지역별 목표: 적힌 시설을 모두 갖춘다.
			var words: Array[String] = []
			for id in phase.need:
				var have := mini(int(state.facilities.get(id, 0)), int(phase.need[id]))
				current += have
				words.append("%s %d / %d" % [content.facilities[id].name, have, int(phase.need[id])])
			detail = " · ".join(words)
		"winter_fuel":
			var heating := WeekSim.bonus(state, "heating")
			if RealmRules.enabled(state):
				# 가을 날씨가 아니라 이미 정해진 겨울 날씨로 준비량을 예고한다.
				# 복제 상태에서 현 정책·시설·영구 효과를 다시 합쳐 캐시나 난수를 바꾸지 않는다.
				var winter := RealmRules.season_weather(state,content,3)
				if not winter.is_empty():
					var planned: Dictionary = state.duplicate(true)
					planned.realm.weather = str(winter.id)
					RealmRules.refresh(planned,content)
					heating = WeekSim.bonus(planned,"heating")
			if ChronicleRules.active(state) and state.get("trial", "") == "frost" and not bool(state.get("trial_started", false)):
				heating *= float(content.chronicle.trials.frost.value)
			target = maxf(1.0, ceil(float(state.pop) * 0.1 * target * heating))
			current = float(state.public.fuel)
			detail = "장작 %.0f / %.0f · 겨울 13주분" % [current, target]
		"final":
			current += 1 if int(state.facilities.get("B13", 0)) >= 6 else 0
			current += 1 if int(state.facilities.get("B22", 0)) >= 1 else 0
			current += 1 if WeekSim.total_food(state) >= float(state.pop) * 13.0 else 0
			current += 1 if not ChronicleRules.active(state) or ChronicleRules.trial_passed(content, state) else 0
			if int(state.pop) <= 0: current = 0
			detail = "연간 목표 3개 + 겨울 시련 · %d / 4 달성" % current
	return {"title":phase.title, "current":current, "target":target, "progress":clampf(current / maxf(1, target), 0, 1), "met":current >= target, "detail":detail}


static func _apply(state: Dictionary, amounts: Dictionary, week: int, source: String) -> Dictionary:
	var applied := {}
	for key in amounts:
		var amount: float = float(amounts[key])
		if key == "mood":
			var previous: float = state.mood
			state.mood = clampf(previous + amount, 0, 100)
			applied[key] = state.mood - previous
		else:
			var previous: float = float(state.public.get(key, 0))
			state.public[key] = maxf(0.0, previous + amount)
			if key == "money": state.public[key] = int(state.public[key])
			applied[key] = float(state.public[key]) - previous
			WeekSim._ledger(state, week, source, key, applied[key])
	return applied


static func _amounts(amounts: Dictionary) -> String:
	var words: Array[String] = []
	for key in amounts:
		var value: float = float(amounts[key]) / 100.0 if key == "money" else float(amounts[key])
		var number: String = "%+.0f" % value if is_equal_approx(value, roundf(value)) else "%+.2f" % value
		words.append(str(NAMES.get(key, key)) + " " + number + ("금" if key == "money" else ""))
	return " · ".join(words)


static func _summary(state: Dictionary, report: Dictionary, outcome: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not outcome.is_empty(): lines.append(str(outcome.message))
	for item in report.get("notes", []):
		var note := str(item)
		if "완공" in note or "수레 도착" in note or "시련 시작" in note:
			if note not in lines: lines.append(note)
		if lines.size() >= 2: break
	lines.append("식량 %.1f주분 · 금고 %.2f금" % [WeekSim.food_weeks(state), float(state.public.money) / 100.0])
	return lines.slice(0, 3)
