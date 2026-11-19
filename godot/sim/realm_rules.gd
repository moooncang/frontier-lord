class_name RealmRules
extends RefCounted
## 2차 규칙 묶음. 민심·건강·치안에 결과가 있고, 시설이 서로를 열며, 사건과 날씨가 회차마다 달라진다.
## config.realm=true로 시작한 회차에만 켜진다. 기존 회차와 기존 테스트의 경제식은 바꾸지 않는다.
## 화면·파일·현재 시각을 참조하지 않는다. 난수는 state.realm.rolls 카운터로 재현한다.

const STATS := ["mood", "health", "security", "trust", "village", "guild"]
const RESOURCES := ["food", "wood", "stone", "tools", "fuel"]
const SEASONS := ["spring", "summer", "autumn", "winter"]
const MIGRANT_EVENTS := ["RV_MIG_S", "RV_MIG_M", "RV_MIG_L"]
const NAMES := {"money":"금고", "food":"식량", "wood":"목재", "stone":"석재", "tools":"도구", "fuel":"장작",
	"resident_food":"주민 식량", "pop":"주민", "mood":"민심", "health":"건강", "security":"치안", "trust":"행정관 신뢰",
	"village":"주민 관계", "guild":"상인 호감", "threat":"변경의 위협", "crop":"올해 수확", "trade_discount":"운송료"}
const MOD_NAMES := {"harvest":"수확", "gather":"채집", "logging":"벌목", "tool_use":"도구 소모", "buy":"구매가",
	"spoil":"보관 손실", "heating":"난방 소비", "sow_labor":"파종 노동", "maintenance":"유지비", "storage":"저장량", "build_work":"공사 작업량",
	"garden":"채소 생산", "quarry":"채석 생산", "smithy":"도구 생산", "wages":"공공 급여"}


static func enabled(state: Dictionary) -> bool:
	return state.get("realm", {}) is Dictionary and state.get("realm", {}).get("enabled", false) == true


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if state.is_empty() or config.get("realm", false) != true or not content.has("realm"): return false
	state.realm = {"enabled":true, "version":1, "labor_base":float(state.labor_ratio), "crop":1.0,
		"mods":{}, "adds":{}, "targets":{}, "perm":{}, "weather":"", "policies":[], "policy_next":0,
		"threat":0.0, "unrest":0, "sick":0, "next_event":int(content.realm.event.first_week), "raid_after":0,
		"rolls":0, "queue":[], "flags":[], "rank":0, "outcome":{}, "news":[],
		"tally":{"immigrants":0, "lost":0, "raids":0, "events":0}}
	# 날짜가 고정된 이민 사건은 매력도 기반 이주로 대체한다.
	for id in ["EV02", "EV04"]:
		if id not in state.seen_events: state.seen_events.append(id)
	_roll_weather(state, content, 0)
	refresh(state, content)
	return true


## ---------- 배율과 목표 ----------

static func mod(state: Dictionary, key: String) -> float:
	return float(state.realm.mods.get(key, 1.0)) if enabled(state) else 1.0


## WeekSim.bonus가 호출한다. 곱 보너스에는 배율을, 가산 보너스(세금 등)에는 가산값을 더한다.
static func apply(state: Dictionary, key: String, value: float, additive: bool) -> float:
	if not enabled(state): return value
	return value + float(state.realm.adds.get(key, 0.0)) if additive else value * float(state.realm.mods.get(key, 1.0))


static func target(state: Dictionary, key: String) -> float:
	return float(state.realm.targets.get(key, 0.0)) if enabled(state) else 0.0


static func weather_def(state: Dictionary, content: Dictionary) -> Dictionary:
	for season in content.realm.weather:
		for item in content.realm.weather[season]:
			if item.id == state.realm.weather: return item
	return {}


static func _merge(mods: Dictionary, extra: Dictionary) -> void:
	for key in extra: mods[key] = float(mods.get(key, 1.0)) * float(extra[key])


static func _sum(into: Dictionary, extra: Dictionary) -> void:
	for key in extra: into[key] = float(into.get(key, 0.0)) + float(extra[key])


## 날씨·정책·시설·수치에서 이번 주에 적용할 배율과 목표 보정을 다시 계산한다.
static func refresh(state: Dictionary, content: Dictionary, relief_fills: Dictionary = {}) -> void:
	if not enabled(state): return
	var realm: Dictionary = state.realm
	var mods := {}
	_merge(mods, ExpeditionModifiers.bonuses(state))
	_merge(mods, CrisisDirector.bonuses(state,content))
	_merge(mods, FrontierDifficulty.bonuses(state,content))
	var adds := {}
	var targets := {}
	var support := SeasonalInvestments.bonuses(state,content)
	_merge(mods, support.mods)
	_sum(targets, support.targets)
	var fantasy := FantasyFrontiers.bonuses(state,content)
	_merge(mods,fantasy.mods)
	_sum(targets,fantasy.targets)
	var house := LegacyPath.doctrine_bonuses(state)
	_merge(mods, house.mods)
	_sum(targets, house.targets)
	_sum(adds, house.adds)
	var labor := 0.0
	var relief_food := maxf(0.0, float(state.public.food))
	_merge(mods, realm.perm)
	var relics := VillageRelics.bonuses(state, content)
	_merge(mods, relics.mods)
	_sum(targets, relics.targets)
	_merge(mods, {"harvest":float(realm.crop)})
	var weather := weather_def(state, content)
	_merge(mods, weather.get("mods", {}))
	_sum(targets, weather.get("targets", {}))
	for id in realm.policies:
		var policy: Dictionary = content.realm.policies[id]
		_merge(mods, policy.get("mods", {}))
		_sum(adds, policy.get("adds", {}))
		var policy_targets: Dictionary = policy.get("targets", {}).duplicate(true)
		var relief_need := float(state.pop) * float(policy.get("relief", 0.0))
		if relief_need > 0:
			# 화면에서는 현재 지급 가능한 몫, 주 처리 중에는 실제로 나눠 준 몫을 쓴다.
			var projected := minf(relief_food, relief_need)
			relief_food -= projected
			var fill := clampf(float(relief_fills.get(id, projected / relief_need)), 0.0, 1.0)
			for key in policy_targets: policy_targets[key] = float(policy_targets[key]) * fill
		_sum(targets, policy_targets)
		labor += float(policy.get("labor", 0.0))
	for id in state.facilities:
		if int(state.facilities[id]) <= 0: continue
		var facility: Dictionary = content.facilities[id]
		_merge(mods, facility.get("mods", {}))
		_sum(targets, facility.get("targets", {}))
	# 수치의 결과: 민심은 일의 능률, 신뢰는 세금, 상인 호감은 가격, 건강은 일할 수 있는 사람 수.
	var work := mood_work(float(state.mood))
	if work != 1.0: _merge(mods, {"gather":work, "logging":work})
	_sum(adds, {"tax":clampf((float(state.trust) - 50.0) / 1000.0, -0.05, 0.05)})
	_merge(mods, {"buy":1.0 - clampf((float(state.guild) - 40.0) / 400.0, -0.05, 0.12)})
	labor += health_labor(float(state.health))
	realm.mods = mods
	realm.adds = adds
	realm.targets = targets
	state.labor_ratio = clampf(float(realm.labor_base) + labor, 0.3, 0.8)


static func mood_work(mood: float) -> float:
	return 0.8 if mood < 25 else 0.9 if mood < 40 else 1.05 if mood >= 70 else 1.0


static func health_labor(health: float) -> float:
	return -0.1 if health < 30 else -0.05 if health < 45 else 0.02 if health >= 70 else 0.0


## ---------- 건설 ----------

static func build_error(state: Dictionary, content: Dictionary, id: String, planned: int) -> String:
	var facility: Dictionary = content.facilities[id]
	var fantasy_error := FantasyFrontiers.build_error(state,content,id)
	if not fantasy_error.is_empty(): return fantasy_error
	var missing: Array[String] = []
	for need in facility.get("requires", []):
		if int(state.facilities.get(need, 0)) <= 0: missing.append(str(content.facilities[need].name))
	if not missing.is_empty(): return "%s: %s 먼저 필요" % [facility.name, " · ".join(missing)]
	if planned >= int(facility.get("max", 99)): return "%s: 최대 %d개까지 지을 수 있습니다" % [facility.name, int(facility.get("max", 99))]
	return ""


## 예약한 공사가 쓸 몫. 영지 규칙에서는 구매·사건 지출이 이 몫을 건드리지 못한다.
static func held(state: Dictionary, content: Dictionary) -> Dictionary:
	return WeekSim.reserved(state, content) if enabled(state) else {"money":0.0}


static func project_limit(state: Dictionary, content: Dictionary) -> int:
	return int(content.realm.project_limit) if enabled(state) else 1


## ---------- 주간 생산 (WeekSim 안에서 호출) ----------

## 주민 생업 인력으로 돌아가는 시설. 입력이 부족하면 그만큼만 가동한다.
static func produce(s: Dictionary, content: Dictionary, w: int, season: int, free_labor: int, efficiency: float) -> Dictionary:
	var result := {"used":0, "paid":0, "by":{}, "operations":{}}
	if not enabled(s): return result
	var ids: Array = s.facilities.keys()
	ids.sort()
	for id in ids:
		var facility: Dictionary = content.facilities[id]
		var count := int(s.facilities[id])
		if not facility.has("jobs") or count <= 0: continue
		var fantasy_operation := {"productive":true,"workers":0,"capacity":int(facility.jobs)*count,"status":"labor","missing":[],"fraction":0.0,"week":w}
		if facility.get("fantasy",false): result.operations[str(id)] = fantasy_operation
		var workers := mini(free_labor - int(result.used), int(facility.jobs) * count)
		if workers <= 0: continue
		var account := str(facility.get("account", "public"))
		var rate := float(workers) / float(facility.jobs)
		if account == "public": rate *= efficiency
		if season == 3: rate *= float(facility.get("winter", 1.0))
		var inputs: Dictionary = facility.get("input",{}).duplicate()
		if facility.get("fantasy",false) and inputs.has("tools"): inputs.tools = float(inputs.tools)*WeekSim.bonus(s,"tool_use")
		for asset in inputs:
			if float(s.public[asset]) < float(inputs[asset])*rate: fantasy_operation.missing.append(str(asset))
			rate = minf(rate, float(s.public[asset]) / float(inputs[asset]))
		if rate <= 0:
			fantasy_operation.status = "inputs"
			continue
		fantasy_operation.status = "operating"
		fantasy_operation.workers = workers
		fantasy_operation.fraction = rate
		for asset in inputs:
			s.public[asset] -= float(inputs[asset]) * rate
			WeekSim._ledger(s, w, str(facility.kind), asset, -float(inputs[asset]) * rate)
		for asset in facility.get("output", {}):
			var produced := float(facility.output[asset]) * rate
			if str(facility.kind) == "smithy": produced *= WeekSim.bonus(s, "smithy")
			elif facility.has("output_bonus"): produced *= WeekSim.bonus(s,str(facility.output_bonus))
			s[account][asset] += produced
			WeekSim._ledger(s, w, str(facility.kind), asset, produced)
		result.used += workers
		if account == "public": result.paid += workers
		result.by[id] = workers
	var relief_fills := {}
	for id in s.realm.policies:
		var share := float(content.realm.policies[id].get("relief", 0.0))
		if share > 0:
			var need := float(s.pop) * share
			var given := WeekSim._transfer(s, "food", "public", "resident", need)
			relief_fills[id] = given / need if need > 0 else 0.0
	# 배급 뒤 _wellbeing이 읽는 민심·건강 목표에는 실제 지급률만 반영한다.
	if not relief_fills.is_empty(): refresh(s, content, relief_fills)
	return result


## 장터 통행세. 외부 상인이 내는 돈이라 주민 계정에서 빼지 않는다.
static func market_fee(s: Dictionary, content: Dictionary) -> int:
	if not enabled(s) or int(s.facilities.get("B49", 0)) <= 0: return 0
	var rate := float(content.realm.market_fee_per_person)
	for id in s.realm.policies: rate *= float(content.realm.policies[id].get("market", 1.0))
	return int(round(float(s.pop) * rate))


## ---------- 한 주가 끝난 뒤 (GameSession에서 호출) ----------

static func after_week(state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	if not enabled(state) or not bool(report.get("advanced", false)): return
	var realm: Dictionary = state.realm
	var data: Dictionary = content.realm
	var week := int(report.week)
	realm.news = []
	for id in realm.policies:
		var weekly: Dictionary = data.policies[id].get("weekly", {})
		for key in weekly: state[key] = clampf(float(state[key]) + float(weekly[key]), 0, 100)
	# 치안은 시설·정책이 만든 목표로 천천히 수렴하고, 쌓인 위협이 목표를 깎는다.
	var security_target := clampf(40.0 + target(state, "security") - float(realm.threat) * 0.25, 0, 100)
	state.security = clampf(float(state.security) + clampf((security_target - float(state.security)) * 0.15, -4, 4), 0, 100)
	if week >= int(data.threat.start_week):
		var growth := float(data.threat.growth) * (0.5 if int(state.facilities.get("B71", 0)) > 0 else 1.0) * mod(state,"threat_growth")
		realm.threat = minf(float(data.threat.max), float(realm.threat) + growth)
	# 민심이 3주 연속 바닥이면 사람이 떠난다.
	realm.unrest = int(realm.unrest) + 1 if float(state.mood) < 35 else 0
	if int(realm.unrest) >= 3 and int(state.pop) > 10:
		var leaving := maxi(1, int(floor(float(state.pop) * 0.02)))
		state.pop = int(state.pop) - leaving
		realm.tally.lost = int(realm.tally.lost) + leaving
		_news(state, report, "bad", "민심이 바닥입니다. 주민 %d명이 영지를 떠났습니다." % leaving)
	# 건강이 3주 연속 나쁘면 병으로 쓰러지는 사람이 생긴다.
	realm.sick = int(realm.sick) + 1 if float(state.health) < 40 else 0
	if int(realm.sick) >= 3:
		state.death_res = float(state.death_res) + float(state.pop) * 0.01
		_news(state, report, "bad", "병이 돌고 있습니다. 건강을 40 위로 올려야 합니다.")
	if week in [13, 26, 39]:
		@warning_ignore("integer_division")
		_roll_weather(state, content, week / 13)
		var weather := weather_def(state, content)
		_news(state, report, "info", "새 계절의 날씨 · %s (%s)" % [weather.name, weather.text])
	# JSON 숫자는 실수라 `in`으로 정수 주차를 찾지 못한다.
	if data.immigration.weeks.any(func(item): return int(item) == week): _invite_migrants(state, content, report)
	_maybe_raid(state, content, week)
	_check_rank(state, content, report)
	refresh(state, content)


static func _news(state: Dictionary, report: Dictionary, level: String, text: String) -> void:
	state.realm.news.append({"level":level, "text":text})
	report.notes.append(text)


static func _roll(state: Dictionary) -> float:
	var realm: Dictionary = state.realm
	var value := Xoshiro128.new(int(state.seed) ^ ((int(realm.rolls) * 40503 + 977) & 0x7fffffff), 4).randf()
	realm.rolls = int(realm.rolls) + 1
	return value


## 해당 회차의 계절 날씨를 미리 읽는다. 실제 전환과 같은 시드식을 쓰며 난수 카운터를 소비하지 않는다.
static func season_weather(state: Dictionary, content: Dictionary, season: int) -> Dictionary:
	if not enabled(state) or not content.has("realm"): return {}
	var index := clampi(season,0,3)
	var table: Array = content.realm.weather[SEASONS[index]]
	var total := 0
	for item in table: total += int(item.weight)
	if total <= 0: return {}
	var pick := Xoshiro128.new(int(state.seed) ^ (index * 7919 + 131), 1).randi_range(0, total - 1)
	for item in table:
		pick -= int(item.weight)
		if pick < 0: return item.duplicate(true)
	return {}


static func _roll_weather(state: Dictionary, content: Dictionary, season: int) -> void:
	var item := season_weather(state,content,season)
	if item.is_empty(): return
	state.realm.weather = str(item.id)
	state.realm.crop = float(state.realm.crop) * float(item.get("crop",1.0))


static func attraction(state: Dictionary) -> float:
	return (float(state.mood) - 50.0) * 0.4 + (float(state.village) - 50.0) * 0.3 + clampf(WeekSim.food_weeks(state) - 8.0, -10, 10) + 4.0 * int(state.realm.rank)


static func _invite_migrants(state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	var free := int(WeekSim.capacity(state, content, "housing")) - int(state.pop)
	var pull := attraction(state)
	if pull < -5:
		_news(state, report, "warn", "이주 희망자들이 소문을 듣고 발길을 돌렸습니다. 민심과 비축이 낮습니다.")
		return
	if free < 3:
		_news(state, report, "warn", "이주 희망자가 왔지만 빈집이 없어 돌아갔습니다. 움집 구역이 필요합니다.")
		return
	var size := mini(free, clampi(int(content.realm.immigration.base) + int(pull / 3.0), 4, int(content.realm.immigration.max)))
	var id := "RV_MIG_S" if size < 8 else "RV_MIG_M" if size < 12 else "RV_MIG_L"
	state.realm.queue.append({"id":id, "week":int(state.week), "migrants":size})


static func _maybe_raid(state: Dictionary, content: Dictionary, week: int) -> void:
	var realm: Dictionary = state.realm
	var data: Dictionary = content.realm.threat
	if week < int(data.start_week) + 2 or week < int(realm.raid_after) or week >= 51: return
	for item in realm.queue:
		if content.events[item.id].get("kind", "") == "threat": return
	var chance := clampf(float(data.raid_base) + (50.0 - float(state.security)) / 300.0 + float(realm.threat) / 250.0, 0.01, 0.3)
	if _roll(state) >= chance: return
	realm.queue.append({"id":"RV_WOLVES" if week + 1 >= 40 else "RV_RAID", "week":int(state.week)})
	realm.raid_after = week + int(data.raid_gap)
	realm.tally.raids = int(realm.tally.raids) + 1


static func rank_progress(state: Dictionary, content: Dictionary) -> Dictionary:
	var ranks: Array = content.realm.ranks
	var current := int(state.realm.rank) if enabled(state) else 0
	var result := {"rank":current, "name":str(ranks[current].name), "next":"", "checks":[], "ready":false}
	if current + 1 >= ranks.size(): return result
	var goal: Dictionary = ranks[current + 1]
	var checks: Array = []
	checks.append({"text":"주민 %d / %d명" % [state.pop, goal.pop], "done":int(state.pop) >= int(goal.pop)})
	for id in goal.get("requires", []):
		checks.append({"text":str(content.facilities[id].name), "done":int(state.facilities.get(id, 0)) > 0})
	if goal.has("any"):
		var names: Array[String] = []
		var any := false
		for id in goal.any:
			names.append(str(content.facilities[id].name))
			any = any or int(state.facilities.get(id, 0)) > 0
		checks.append({"text":" 또는 ".join(names), "done":any})
	if goal.has("security"):
		checks.append({"text":"치안 %d / %d" % [state.security, goal.security], "done":float(state.security) >= float(goal.security)})
	if goal.get("housing", false):
		checks.append({"text":"주거 충족", "done":WeekSim.capacity(state, content, "housing") >= float(state.pop)})
	if goal.get("water", false):
		checks.append({"text":"물 충족", "done":WeekSim.capacity(state, content, "water") >= float(state.pop)})
	result.next = str(goal.name)
	result.checks = checks
	result.ready = checks.all(func(item): return item.done)
	return result


static func _check_rank(state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	var progress := rank_progress(state, content)
	if not progress.ready: return
	state.realm.rank = int(state.realm.rank) + 1
	var goal: Dictionary = content.realm.ranks[int(state.realm.rank)]
	var gained := {}
	for key in goal.get("reward", {}): gained[key] = float(goal.reward[key])
	_apply_plain(state, gained, int(report.week), "rank")
	_news(state, report, "good", "%s(으)로 승격했습니다! %s" % [goal.name, changes_text(gained)])
	var news: Dictionary = state.realm.news.back()
	news["kind"] = "rank"
	news["rank"] = int(state.realm.rank)
	news["week"] = int(report.week)


## ---------- 사건 ----------

static func eligible(state: Dictionary, content: Dictionary) -> Array:
	var out: Array = []
	var week := int(state.week)
	var season := WeekSim.season_of(WeekSim.week_of_year(week))
	var ids: Array = content.events.keys()
	ids.sort()
	for id in ids:
		var event: Dictionary = content.events[id]
		if event.get("fantasy_only",false) and not FantasyFrontiers.enabled(state): continue
		if event.get("plus_only",false) and not CrisisDirector.enabled(state): continue
		if not event.get("realm", false) or not event.has("pool"): continue
		var pool: Dictionary = event.pool
		if week < int(pool.get("min", 1)) or week > int(pool.get("max", 52)): continue
		if pool.has("seasons") and not pool.seasons.any(func(item): return int(item) == season): continue
		if pool.get("once", false) and id in state.seen_events: continue
		if pool.has("facility") and int(state.facilities.get(pool.facility, 0)) <= 0: continue
		# 같은 사건이 연달아 나오지 않게 한다.
		if not state.seen_events.is_empty() and state.seen_events.back() == id: continue
		out.append({"id":id, "weight":int(pool.get("weight", 1))})
	return out


## 미결 사건이 없을 때 예정된 사건이나 무작위 사건을 올린다.
static func schedule(state: Dictionary, content: Dictionary) -> void:
	if not enabled(state) or state.active_event != "" or state.status != "active": return
	var realm: Dictionary = state.realm
	var week := int(state.week)
	for index in realm.queue.size():
		if int(realm.queue[index].week) <= week:
			var item: Dictionary = realm.queue[index]
			state.active_event = str(item.id)
			if item.has("migrants"):
				realm["migrant_offer"] = {"event":str(item.id), "count":int(item.migrants)}
			realm.queue.remove_at(index)
			return
	if week < int(realm.next_event) or week > 51: return
	if _roll(state) >= float(content.realm.event.chance): return
	var pool := eligible(state, content)
	var total := 0
	for item in pool: total += int(item.weight)
	if total <= 0: return
	var pick := int(_roll(state) * total)
	for item in pool:
		pick -= int(item.weight)
		if pick < 0:
			state.active_event = str(item.id)
			break
	realm.next_event = week + int(content.realm.event.gap) + int(_roll(state) * (int(content.realm.event.gap_spread) + 1))
	realm.tally.events = int(realm.tally.events) + 1


## 표시·검증·결제가 같은 이주 인원과 비용을 사용한다. 공통 사건 정의는 수정하지 않는다.
## 인원이 저장되지 않은 구 회차 사건은 기존 6/10/14명 정의를 그대로 읽는다.
static func event_definition(state: Dictionary, content: Dictionary, event_id: String) -> Dictionary:
	var event: Dictionary = content.events.get(event_id, {})
	var offer: Dictionary = state.get("realm", {}).get("migrant_offer", {}) if enabled(state) else {}
	if event_id not in MIGRANT_EVENTS or offer.get("event", "") != event_id: return event
	var count := int(offer.count)
	var out: Dictionary = event.duplicate(true)
	out.title = ("이주 행렬 %d명" if count >= 12 else "이주 희망자 %d명") % count
	out.body = "이주민 %d명이 정착을 신청했습니다. 한 사람당 빈집 한 자리, 정착금 0.2금, 공공 식량 4가 필요합니다." % count
	for index in out.options.size():
		var option: Dictionary = out.options[index]
		if int(option.get("effects", {}).get("pop", 0)) > 0:
			var accepted := count if index == 0 else maxi(1, int(floor(float(count) / 2.0)))
			option.effects.pop = accepted
			option.requires_housing = accepted
			option.cost.money = accepted * 20
			option.cost.food = accepted * 4
			option.label = "모두 받아들인다 (%d명)" % accepted if index == 0 else "%d명만 받아들인다" % accepted
		elif index == 1 and event_id == "RV_MIG_S":
			option.cost.food = count * 2
	return out


static func option_error(state: Dictionary, content: Dictionary, option: Dictionary) -> String:
	var fantasy_error := FantasyFrontiers.option_error(state,content,option)
	if not fantasy_error.is_empty(): return fantasy_error
	if not enabled(state): return ""
	var need: Dictionary = option.get("requires", {})
	if need.has("facility") and int(state.facilities.get(need.facility, 0)) <= 0:
		return "%s 건설 후 선택할 수 있습니다." % content.facilities[need.facility].name
	if need.has("stat") and float(state[need.stat[0]]) < float(need.stat[1]):
		return "%s %d 이상 필요 (현재 %d)" % [NAMES.get(need.stat[0], need.stat[0]), need.stat[1], state[need.stat[0]]]
	if need.has("policy") and need.policy not in state.realm.policies:
		return "정책 ‘%s’ 시행 중에만 선택할 수 있습니다." % content.realm.policies[need.policy].name
	if need.has("relic_family"):
		var equipped: Array = state.realm.get("sanctuary", {}).get("equipped", [])
		var relics: Dictionary = content.get("village_relics", {}).get("relics", {})
		if not equipped.any(func(id): return relics.get(id, {}).get("category", "") == str(need.relic_family)):
			var category: Dictionary = content.get("village_relics", {}).get("categories", {}).get(need.relic_family, {})
			return "%s 성물을 성소에 장착해야 합니다." % str(category.get("name", need.relic_family))
	if need.has("perk_family"):
		var spec: Dictionary = need.perk_family
		var count := int(ChronicleRules.family_counts(content,state).get(spec.id,0))
		if count < int(spec.count): return "%s 특전 %d개가 필요합니다. (현재 %d개)" % [content.chronicle.families[spec.id].name,int(spec.count),count]
	return ""


static func option_requirements_text(content: Dictionary, option: Dictionary) -> String:
	var need: Dictionary = option.get("requires", {})
	var parts: Array[String] = []
	if need.has("facility"): parts.append(str(content.facilities[need.facility].name))
	if need.has("stat"): parts.append("%s %d 이상" % [NAMES.get(need.stat[0], need.stat[0]), need.stat[1]])
	if need.has("policy"): parts.append(str(content.realm.policies[need.policy].name))
	if need.has("relic_family"): parts.append("%s 성물 장착" % content.village_relics.categories[need.relic_family].name)
	if need.has("perk_family"): parts.append("%s 특전 %d개" % [content.chronicle.families[need.perk_family.id].name,int(need.perk_family.count)])
	return " · ".join(parts)


static func chance_of(state: Dictionary, option: Dictionary) -> float:
	var spec: Dictionary = option.get("chance", {})
	if spec.is_empty(): return 1.0
	var p := float(spec.base)
	if spec.has("stat"): p += (float(state[spec.stat]) - 50.0) * float(spec.get("per", 0.0))
	for id in spec.get("facility", {}):
		if int(state.facilities.get(id, 0)) > 0: p += float(spec.facility[id])
	for id in spec.get("policy", {}):
		if enabled(state) and id in state.realm.policies: p += float(spec.policy[id])
	return clampf(p, 0.05, 0.95)


## 선택의 실제 결과를 확정한다. effects는 호출자가 일반 규칙으로 적용할 사본이며,
## 여기서 확률 결과를 합치고 영지 전용 키(위협·수확·영구 배율·깃발)를 처리해 지운다.
static func resolve(state: Dictionary, content: Dictionary, event_id: String, option: Dictionary, effects: Dictionary) -> void:
	if not enabled(state): return
	var realm: Dictionary = state.realm
	var event: Dictionary = event_definition(state, content, event_id)
	var outcome := {"event":event_id, "title":str(event.title), "choice":str(option.label), "week":int(state.week),
		"text":"", "rolled":false, "win":false, "chance":1.0, "changes":{}}
	if option.has("chance"):
		outcome.chance = chance_of(state, option)
		outcome.rolled = true
		outcome.win = _roll(state) < float(outcome.chance)
		var branch: Dictionary = option.chance.win if outcome.win else option.chance.lose
		outcome.text = str(branch.get("text", ""))
		for key in branch.get("effects", {}):
			if branch.effects[key] is float or branch.effects[key] is int:
				effects[key] = float(effects.get(key, 0.0)) + float(branch.effects[key])
			else:
				effects[key] = branch.effects[key]
	var changes: Dictionary = outcome.changes
	if effects.has("threat"):
		var before := float(realm.threat)
		realm.threat = clampf(before + float(effects.threat), 0, float(content.realm.threat.max))
		changes["threat"] = float(realm.threat) - before
		effects.erase("threat")
	if effects.has("flag"):
		realm.flags.append(str(effects.flag))
		effects.erase("flag")
	if effects.has("crop"):
		realm.crop = float(realm.crop) * (1.0 + float(effects.crop))
		changes["crop"] = float(effects.crop)
		effects.erase("crop")
	if effects.has("perm"):
		for key in effects.perm:
			realm.perm[key] = float(realm.perm.get(key, 1.0)) * float(effects.perm[key])
			changes["perm:" + str(key)] = float(effects.perm[key])
		effects.erase("perm")
	# 잃는 것은 가진 만큼만. 음수 재고를 만들지 않고, 예약한 공사 자재는 건드리지 않는다.
	var held := WeekSim.reserved(state, content)
	for key in RESOURCES + ["money"]:
		if float(effects.get(key, 0.0)) < 0:
			effects[key] = -minf(-float(effects[key]), maxf(0.0, float(state.public[key]) - float(held.get(key, 0.0))))
	if float(effects.get("pop", 0.0)) < 0:
		effects["pop"] = -mini(-int(effects.pop), maxi(0, int(state.pop) - 1))
		realm.tally.lost = int(realm.tally.lost) - int(effects.pop)
	elif float(effects.get("pop", 0.0)) > 0:
		realm.tally.immigrants = int(realm.tally.immigrants) + int(effects.pop)
	if effects.has("trade_discount"):
		effects["trade_discount"] = minf(float(effects.trade_discount), 0.5 - float(state.trade_discount))
	for key in effects:
		if not is_zero_approx(float(effects[key])): changes[key] = float(effects[key])
	if option.has("followup"):
		var scheduled := {"id":str(option.followup.id), "week":int(state.week) + int(option.followup.delay)}
		realm.queue.append(scheduled)
		outcome["followup"] = scheduled.duplicate(true)
	realm.outcome = outcome
	if realm.get("migrant_offer", {}).get("event", "") == event_id: realm.erase("migrant_offer")


## 비용과 효과가 실제 적용되고 통계 상한까지 처리된 뒤 한 번 기록한다. 난수를 다시 뽑지 않는다.
static func finalize_outcome(before: Dictionary, state: Dictionary, costs: Dictionary) -> void:
	if not enabled(state) or before.is_empty() or state.realm.outcome.is_empty(): return
	state.realm.outcome = RealmFeedback.build(before,state,state.realm.outcome,costs)


static func _apply_plain(state: Dictionary, amounts: Dictionary, week: int, source: String) -> void:
	for key in amounts:
		var value := float(amounts[key])
		if key == "money":
			state.public.money = int(state.public.money) + int(value)
			WeekSim._ledger(state, week, source, "money", int(value))
		elif key in RESOURCES:
			state.public[key] += value
			WeekSim._ledger(state, week, source, key, value)
		elif key in STATS:
			state[key] = clampf(float(state[key]) + value, 0, 100)


## 효과 사전을 사람이 읽는 한 줄로 만든다. 화면과 소식이 같은 문구를 쓴다.
static func changes_text(changes: Dictionary) -> String:
	var parts: Array[String] = []
	for key in changes:
		var value := float(changes[key])
		if is_zero_approx(value): continue
		var id := str(key)
		if id == "money": parts.append("금고 %+.0f금" % (value / 100.0) if is_equal_approx(value / 100.0, roundf(value / 100.0)) else "금고 %+.2f금" % (value / 100.0))
		elif id == "crop": parts.append("올해 수확 %+.0f%%" % (value * 100.0))
		elif id == "trade_discount": parts.append("운송료 %+.0f%%" % (-value * 100.0))
		elif id.begins_with("perm:"): parts.append("%s %+.0f%% (남은 통치 내내)" % [MOD_NAMES.get(id.trim_prefix("perm:"), id), (value - 1.0) * 100.0])
		elif id == "pop": parts.append("주민 %+d명" % int(value))
		else: parts.append("%s %+.0f" % [NAMES.get(id, id), value])
	return " · ".join(parts)


## 선택지의 확정 효과(비용 제외)를 미리 보여 주는 문구.
static func option_text(option: Dictionary) -> String:
	var shown := {}
	for key in option.get("effects", {}):
		if key == "perm":
			for item in option.effects.perm: shown["perm:" + str(item)] = option.effects.perm[item]
		elif key != "flag": shown[key] = option.effects[key]
	var text := changes_text(shown)
	var fantasy := FantasyFrontiers.option_text(option)
	return text + (" · " if not text.is_empty() and not fantasy.is_empty() else "") + fantasy


## ---------- 정책 ----------

static func policy_slots(state: Dictionary) -> int:
	if not enabled(state): return 0
	return 1 + (1 if int(state.facilities.get("B63", 0)) > 0 else 0) + (1 if int(state.realm.rank) >= 1 else 0)


static func policy_error(state: Dictionary, content: Dictionary, id: String, enable: bool) -> String:
	if not enabled(state) or state.status != "active": return "진행 중인 통치가 없습니다."
	if not content.realm.policies.has(id): return "알 수 없는 정책입니다."
	var realm: Dictionary = state.realm
	if enable == (id in realm.policies): return "이미 그렇게 정해져 있습니다."
	if int(state.week) < int(realm.policy_next): return "포고는 %d주 뒤에 다시 바꿀 수 있습니다." % (int(realm.policy_next) - int(state.week))
	if not enable: return ""
	var need := str(content.realm.policies[id].get("requires", ""))
	if need != "" and int(state.facilities.get(need, 0)) <= 0: return "%s 건설 후 시행할 수 있습니다." % content.facilities[need].name
	if realm.policies.size() >= policy_slots(state): return "정책 칸이 가득 찼습니다. 서기관실과 촌락 승격으로 칸이 늘어납니다."
	for other in realm.policies:
		if [id, other] in [["tax_relief", "tax_levy"], ["tax_levy", "tax_relief"]]: return "감면과 징수는 함께 시행할 수 없습니다."
	return ""


static func set_policy(state: Dictionary, content: Dictionary, id: String, enable: bool) -> String:
	var error := policy_error(state, content, id, enable)
	if error != "": return error
	if enable: state.realm.policies.append(id)
	else: state.realm.policies.erase(id)
	state.realm.policy_next = int(state.week) + int(content.realm.policy_cooldown)
	refresh(state, content)
	return ""


## ---------- 교역 ----------

static func price(state: Dictionary, content: Dictionary, asset: String) -> float:
	if not enabled(state): return 1.0
	return float(content.realm.prices[asset][WeekSim.season_of(WeekSim.week_of_year(clampi(int(state.week), 1, 52)))])


static func delivery(state: Dictionary) -> int:
	return 1 if enabled(state) and int(state.facilities.get("B52", 0)) > 0 else 2


static func carts(state: Dictionary) -> int:
	return 4 if enabled(state) and int(state.facilities.get("B52", 0)) > 0 else 3


## ---------- 결산 ----------

static func score(state: Dictionary, content: Dictionary, success: bool) -> Dictionary:
	if not enabled(state): return {}
	var realm: Dictionary = state.realm
	var lines: Array = []
	@warning_ignore("integer_division")
	var growth := clampi((int(state.pop) - 80) / 5, 0, 8)
	lines.append({"text":"주민 %d명으로 성장" % state.pop, "points":growth})
	var rank_points := 0
	for index in range(1, int(realm.rank) + 1): rank_points += int(content.realm.ranks[index].points)
	lines.append({"text":"영지 등급 · %s" % content.realm.ranks[int(realm.rank)].name, "points":rank_points})
	var kinds := 0
	for id in state.facilities:
		if int(state.facilities[id]) > 0 and content.facilities[id].grade != "T": kinds += 1
	@warning_ignore("integer_division")
	var variety := mini(6, kinds / 3)
	lines.append({"text":"시설 %d종 운영" % kinds, "points":variety})
	var defended := mini(3, realm.flags.count("raid_won"))
	lines.append({"text":"습격 격퇴 %d회" % realm.flags.count("raid_won"), "points":defended})
	var care := (2 if float(state.mood) >= 60 else 0) + (2 if float(state.health) >= 60 else 0)
	lines.append({"text":"민심 %d · 건강 %d" % [state.mood, state.health], "points":care})
	var total := growth + rank_points + variety + defended + care
	var grade := "D"
	var title := "미완의 통치"
	for row in content.realm.grades:
		var fits: bool = (success and total >= int(row.points)) if row.success else (not success and int(state.week) - 1 >= int(row.get("weeks", 0)))
		if fits:
			grade = str(row.grade)
			title = str(row.title)
			break
	# 13주 미만에는 공훈을 지급하지 않는다. 상세 행도 실제 지급 합계와 일치시킨다.
	if int(state.week) <= 13:
		total = 0
		for line in lines: line.points = 0
	return {"points":total, "grade":grade, "title":title, "lines":lines}


## ---------- 저장 검증 ----------

static func valid(state: Dictionary, content: Dictionary) -> bool:
	if not state.has("realm"): return true
	var realm: Variant = state.realm
	if not realm is Dictionary or not realm.get("enabled") is bool or not content.has("realm"): return false
	for key in ["version", "labor_base", "crop", "threat", "unrest", "sick", "next_event", "raid_after", "rolls", "rank", "policy_next"]:
		var value: Variant = realm.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
	if int(realm.version) != 1 or int(realm.rank) >= content.realm.ranks.size() or float(realm.labor_base) > 1: return false
	for key in ["mods", "adds", "targets", "perm", "tally", "outcome"]:
		if not realm.get(key) is Dictionary: return false
	for key in ["policies", "queue", "flags", "news"]:
		if not realm.get(key) is Array: return false
	for group in [realm.mods, realm.perm]:
		for value in group.values():
			if not (value is int or value is float) or float(value) <= 0: return false
	for key in ["immigrants", "lost", "raids", "events"]:
		if not (realm.tally.get(key) is int or realm.tally.get(key) is float): return false
	if not realm.get("weather") is String or weather_def(state, content).is_empty(): return false
	for id in realm.policies:
		if not id is String or not content.realm.policies.has(id): return false
	for item in realm.queue:
		if not item is Dictionary or not content.events.has(item.get("id", "")): return false
		if not (item.get("week") is int or item.get("week") is float): return false
		if item.has("migrants") and (item.id not in MIGRANT_EVENTS or not _valid_migrant_count(item.migrants, content)): return false
	if realm.has("migrant_offer"):
		var offer: Variant = realm.migrant_offer
		if not offer is Dictionary or offer.get("event", "") not in MIGRANT_EVENTS: return false
		if offer.event != state.active_event or not _valid_migrant_count(offer.get("count"), content): return false
	for item in realm.flags:
		if not item is String: return false
	for item in realm.news:
		if not item is Dictionary or not item.get("text") is String or not item.get("level") is String: return false
	return true


static func _valid_migrant_count(value: Variant, content: Dictionary) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 3 and float(value) <= float(content.realm.immigration.max)
