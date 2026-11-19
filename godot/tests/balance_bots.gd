extends SceneTree
## 난이도 시험대. 세 가지 봇(무작위·순서만·계획)으로 52주를 12번씩 돌려 성공률과 여유를 잰다.
## 수치 변형은 메모리의 content에만 적용한다. 프로젝트 파일은 건드리지 않는다. 자동 테스트에는 포함되지 않는다.
## 실행: godot --headless --path . -s tests/balance_bots.gd -- base
## 변형: -- yield40+threat2 처럼 +로 묶는다. fast는 무작위 봇 생략, hl은 잿빛 구릉만, trace는 주별 기록.

const CONFIG := {"region":"forest", "candidate":0, "relics":["seeds", "axe"], "tutorial":false,
	"cabinet":true, "campaign":true, "workcrew":true, "realm":true, "village_relics":true, "modifiers":true,
	"escalation":true, "fantasy":true, "difficulty":0, "seasonal_support":true, "mandate":true, "regional":true, "people":true}
const BUILD_ORDER := ["B13", "B22", "B17", "B25", "B16", "B14", "B67", "B01", "B27", "B49", "B57", "B14", "B19", "B33", "B21", "B11", "B63", "B71", "B26", "B20", "B52", "B59"]
const SEEDS := [61427, 9041, 3317, 77003]
var content: Dictionary
var rng := RandomNumberGenerator.new()


func _init() -> void:
	var variant := "base"
	for arg in OS.get_cmdline_user_args():
		if arg not in ["fast", "hl"]: variant = arg
	content = Content.load_all()
	_apply(variant)
	print("VARIANT %s" % variant)
	for bot in ["first", "planner"] if "fast" in OS.get_cmdline_user_args() else ["naive", "first", "planner"]:
		var wins := 0
		var grades := {}
		var sums := {"lowest":0.0, "money":0.0, "seasons":0.0, "crises":0.0, "pop":0.0, "week":0.0}
		var runs := 0
		var reasons := {}
		var by_region := {}
		for region in (["highland"] if "hl" in OS.get_cmdline_user_args() else ["forest", "river", "highland"]):
			for seed_value in SEEDS:
				var row := _play(seed_value, region, bot)
				runs += 1
				wins += int(row.success)
				by_region[region] = int(by_region.get(region, 0)) + int(row.success)
				grades[row.grade] = int(grades.get(row.grade, 0)) + 1
				for key in sums: sums[key] += float(row[key])
				if not row.success: reasons[row.why] = int(reasons.get(row.why, 0)) + 1
		print("%-8s 성공 %2d/%d  등급 %s  최저식량 %.1f주  끝금고 %.0f금  계절목표 %.1f/4  위기 %.1f/4  주민 %.0f  끝난주 %.0f  실패사유 %s  지역 %s" % [bot, wins, runs, str(grades), sums.lowest / runs, sums.money / runs, sums.seasons / runs, sums.crises / runs, sums.pop / runs, sums.week / runs, str(reasons), str(by_region)])
	quit(0)


## 시험할 수치 묶음. 이름으로 고른다.
func _apply(variant: String) -> void:
	for part in variant.split("+"):
		match part:
			"base": pass
			"yield45": content.campaign.balance = {"harvest":0.45, "gather":0.45}
			"yield40": content.campaign.balance = {"harvest":0.40, "gather":0.40}
			"yield35": content.campaign.balance = {"harvest":0.35, "gather":0.35}
			"penalty2":
				for phase in content.campaign.phases:
					for key in phase.penalty: phase.penalty[key] = float(phase.penalty[key]) * 2.0
			"penalty3":
				for phase in content.campaign.phases:
					for key in phase.penalty: phase.penalty[key] = float(phase.penalty[key]) * 3.0
			"crisis2":
				for id in content.crises.definitions:
					for key in content.crises.definitions[id].penalty: content.crises.definitions[id].penalty[key] = float(content.crises.definitions[id].penalty[key]) * 2.0
			"threat2": content.realm.threat.growth = float(content.realm.threat.growth) * 2.0
			"events35": content.realm.event.chance = 0.35
			"harv90":
				for id in ["river", "highland"]: content.campaign.regions[id].bonuses.harvest = 0.9
			"harv100":
				for id in ["river", "highland"]: content.campaign.regions[id].bonuses.harvest = 1.0
			"mandate4": content.campaign.mandate.start = 4
			"hl1": content.campaign.regions.highland.bonuses = {"wages":1.0, "quarry":1.3, "harvest":0.8}
			"hl2": content.campaign.regions.highland.bonuses = {"wages":1.0, "quarry":1.3, "harvest":1.0}
			"hl3": content.campaign.regions.highland.bonuses = {"wages":1.0, "quarry":1.3, "harvest":0.9, "maintenance":0.8, "tool_use":0.7}
			"hlgoal": content.campaign.regions.highland.phases.erase("summer")
			"sell13": content.campaign.regions.highland.bonuses = {"wages":1.1, "quarry":1.3, "harvest":0.8, "sell":1.3}
			"sell15": content.campaign.regions.highland.bonuses = {"wages":1.1, "quarry":1.3, "harvest":0.8, "sell":1.5}
			"sell15q": content.campaign.regions.highland.bonuses = {"wages":1.1, "quarry":1.5, "harvest":0.8, "sell":1.5}
			"reward":
				content.campaign.regions.river.phases.spring["reward"] = {"money":600, "food":60}
				content.campaign.regions.river.phases.summer["reward"] = {"money":800, "tools":2}
				content.campaign.regions.highland.phases.spring["reward"] = {"money":600, "tools":2}
				content.campaign.regions.highland.phases.summer["reward"] = {"money":800, "stone":20}
			"reward2":
				content.campaign.regions.river.phases.spring["reward"] = {"money":1000, "food":80}
				content.campaign.regions.river.phases.summer["reward"] = {"money":1200, "tools":2}
				content.campaign.regions.highland.phases.spring["reward"] = {"money":1000, "tools":2}
				content.campaign.regions.highland.phases.summer["reward"] = {"money":1200, "stone":20}
			"yield50": content.campaign.balance = {"harvest":0.50, "gather":0.50}
			"threat15": content.realm.threat.growth = float(content.realm.threat.growth) * 1.5
			"halfgain":
				# 비용도 손해도 없이 이득만 주는 선택지의 이득을 절반으로
				for id in content.events:
					for option in content.events[id].options:
						if not option.get("cost", {}).is_empty() or option.has("chance"): continue
						var values: Array = option.effects.values().filter(func(v): return v is float or v is int)
						if values.is_empty() or values.any(func(v): return v < 0): continue
						for key in option.effects:
							if option.effects[key] is float or option.effects[key] is int: option.effects[key] = float(option.effects[key]) * 0.5
			_: print("unknown variant part: ", part)


func _pick_event(game: GameSession, bot: String) -> void:
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[rng.randi() % game.state.perk_offer.size() if bot == "naive" else 0]))
	if game.state.active_event == "": return
	var event: Dictionary = content.events[game.state.active_event]
	var s := game.state
	var order: Array = range(event.options.size())
	if bot == "naive":
		# 아무 선택지나 고른다
		for attempt in 12:
			if game.choose_event(order[rng.randi() % order.size()]) == "": return
	for i in order:
		var option: Dictionary = event.options[i]
		if game.option_error(option) != "": continue
		if bot == "planner":
			if option.has("chance") and RealmRules.chance_of(s, option) < 0.5 and i < event.options.size() - 1: continue
			if float(option.get("cost", {}).get("food", 0)) > 0 and WeekSim.food_weeks(s) < 6: continue
			if event.get("immigration", false) and option.has("requires_housing") and (WeekSim.food_weeks(s) < 9 or int(s.week) > 30): continue
		if float(option.get("cost", {}).get("money", 0)) > float(s.public.money) * 0.4: continue
		if game.choose_event(i) == "": return
	for i in order:
		if game.choose_event(i) == "": return


func _relics(game: GameSession) -> void:
	var offer: Array = game.state.realm.sanctuary.offer
	if offer.is_empty(): return
	var first: Variant = offer[0]
	game.choose_relic(str(first.id) if first is Dictionary else str(first))


func _play(seed_value: int, region: String, bot: String) -> Dictionary:
	rng.seed = seed_value * 31 + region.hash()
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config.region = region
	game.start_run(seed_value, "settler", config)
	var lowest := 99.0
	var guard := 0
	while game.state.status == "active" and guard < 200:
		guard += 1
		_pick_event(game, bot)
		_relics(game)
		_pick_event(game, bot)
		_relics(game)
		var s := game.state
		var sites: int = s.orders.size() + s.projects.size()
		if bot == "naive":
			# 지을 수 있는 것을 아무 순서로 하나 짓는다. 방침은 건드리지 않고 물자도 사지 않는다.
			if sites < 2:
				var ids: Array = content.facilities.keys()
				for attempt in 8:
					if CabinetActions.start_project(game, str(ids[rng.randi() % ids.size()])) == "": break
		else:
			var reserve := 1500 if int(s.week) < 20 else 2500
			if bot == "planner" and s.trial == "audit": reserve += 1200 if int(s.week) >= 40 else 3200
			if sites < 2:
				for id in {"river":["B22", "B13", "B49"], "highland":["B25", "B27", "B13", "B22", "B49", "B33"]}.get(region, []) + BUILD_ORDER:
					if float(s.public.money) - Constants.GRADE_COST[content.facilities[id].grade].gold * 100 * (2 if id == "B13" else 1) < reserve: continue
					if id == "B13" and int(s.facilities.get("B13", 0)) >= 8: continue
					var wanted := 2 if id in ["B17", "B14"] else 1
					if id != "B13" and int(s.facilities.get(id, 0)) + s.orders.count(id) + s.projects.filter(func(p): return p.id == id).size() >= wanted: continue
					if bot == "planner" and id == "B01" and WeekSim.capacity(s, content, "housing") - s.pop > 14: continue
					if CabinetActions.start_project(game, id) == "": break
			var policy := "build" if not s.orders.is_empty() or not s.projects.is_empty() else "balanced"
			var fuel_goal: float = s.pop * 0.1 * 13 * WeekSim.bonus(s, "heating") * 1.6
			if bot == "planner" and int(s.week) >= 22 and int(s.facilities.get("B25", 0)) > 0 and s.public.fuel < fuel_goal: policy = "winter"
			if WorkcrewRules.select(s, content, policy) != "": WorkcrewRules.select(s, content, "balanced")
			if bot == "first":
				if WeekSim.food_weeks(s) < 8.0 and s.shipments.size() < 2 and s.public.money > 1000: CabinetActions.buy_supply(game, "food")
			else:
				var food_floor := 7.0 if int(s.week) < 36 else 14.5
				if s.trial == "rot" and int(s.week) >= 34: food_floor = 16.0
				# 사람처럼: 가을부터는 연말 식량 목표를 보고 남는 돈으로 식량을 사 둔다
				var keep := 1300.0 if s.trial == "audit" else 300.0
				if WeekSim.food_weeks(s) < food_floor and s.shipments.size() < 2 and s.public.money > (keep if int(s.week) >= 36 else reserve * 0.5): CabinetActions.buy_supply(game, "food")
				if int(s.week) >= 30 and s.public.fuel < fuel_goal * 0.6 and not s.shipments.any(func(x): return x.asset == "fuel"): CabinetActions.buy_supply(game, "fuel")
				if s.public.stone < 10 and s.public.money > 3000 and not s.shipments.any(func(x): return x.asset == "stone"): CabinetActions.buy_supply(game, "stone")
				if s.public.tools < 3 and s.public.money > 2500 and not s.shipments.any(func(x): return x.asset == "tools"): CabinetActions.buy_supply(game, "tools")
				# 장터가 있으면 남는 석재와 도구를 내다 판다
				if int(s.facilities.get("B49", 0)) > 0:
					if float(s.public.stone) > 80: game.trade("stone", mini(200, int(s.public.stone) - 40), false)
					if float(s.public.tools) > 16: game.trade("tools", int(s.public.tools) - 10, false)
				var decree := "militia" if s.security < 42 else "relief" if s.mood < 45 and s.public.food > 400 else ""
				if decree != "" and decree not in s.realm.policies and s.realm.policies.size() < RealmRules.policy_slots(s): RealmRules.set_policy(s, content, decree, true)
		if "trace" in OS.get_cmdline_user_args() and bot == "planner" and (int(s.week) % 4 == 1 or int(s.week) >= 49):
			print("   %s %d w%02d 금고 %5.0f 식량 %5.0f(%.1f주) 장작 %4.0f 목재 %4.0f 석재 %3.0f 도구 %3.0f 주민 %d 농지 %d 시설 %s 공사 %s" % [region, seed_value, int(s.week), float(s.public.money) / 100.0, WeekSim.total_food(s), WeekSim.food_weeks(s), float(s.public.fuel), float(s.public.wood), float(s.public.stone), float(s.public.tools), int(s.pop), int(s.facilities.get("B13", 0)), str(s.facilities.keys().filter(func(k): return not str(k).begins_with("T_") and k != "B13")), str(s.orders + s.projects.map(func(p): return p.id))])
		var report := game.advance()
		if not report.advanced:
			print("  blocked %s %d week %d: %s" % [region, seed_value, int(s.week), str(report.notes)])
			break
		lowest = minf(lowest, WeekSim.food_weeks(game.state))
	var result: Dictionary = game.state.get("result", {})
	var st := game.state
	var why := "%s%s%s%s" % ["" if st.goals.farms.done else "농지 ", "" if st.goals.storage.done else "곳간 ", "" if st.goals.food.done else "식량 ", "" if result.get("trial_passed", false) else "시련(%s) " % st.trial]
	if str(result.get("reason", "")) != "완주": why = str(result.get("reason", "중단"))
	return {"success":bool(result.get("success", false)), "grade":str(result.get("grade", "?")), "lowest":lowest,
		"money":float(st.public.money) / 100.0, "pop":int(st.pop), "week":int(result.get("week", st.week)),
		"seasons":st.campaign.records.filter(func(r): return r.success).size(),
		"crises":st.escalation.records.filter(func(r): return r.success).size(), "why":why.strip_edges()}
