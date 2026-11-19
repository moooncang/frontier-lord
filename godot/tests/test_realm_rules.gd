extends SceneTree
## 영지 규칙(2차 규칙 묶음)의 규칙·재현성·저장·실제 52주 주행 검사.
## 실행: godot --headless --path . -s tests/test_realm_rules.gd

var failures := 0
var assertions := 0
var content: Dictionary

const CONFIG := {"region":"forest", "candidate":0, "relics":["seeds", "axe"], "tutorial":false,
	"cabinet":true, "campaign":true, "workcrew":true, "realm":true}
const BUILD_ORDER := ["B13", "B22", "B17", "B25", "B16", "B14", "B67", "B01", "B27", "B49", "B57", "B14", "B19", "B33", "B21", "B11", "B63", "B71", "B26", "B20", "B52", "B59"]


func _init() -> void:
	content = Content.load_all()
	_check(Content.validate(content).is_empty(), "content validation " + str(Content.validate(content)))
	_test_setup()
	_test_building_rules()
	_test_stat_consequences()
	_test_production()
	_test_policies()
	_test_events()
	_test_trade()
	_test_runs()
	print("REALM RULES: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)


func _new(seed_value: int = 61427, region: String = "forest", realm: bool = true) -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config.region = region
	config.realm = realm
	game.start_run(seed_value, "settler", config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _test_setup() -> void:
	var game := _new()
	var s := game.state
	_check(RealmRules.enabled(s) and RealmRules.valid(s, content), "realm enabled and valid on a new run")
	_check("EV02" in s.seen_events and "EV04" in s.seen_events, "scripted immigration replaced by attraction-based migrants")
	_check(not RealmRules.weather_def(s, content).is_empty(), "spring weather rolled")
	_check(SaveStore.valid(game.bundle()), "fresh realm run passes save validation")
	var legacy := _new(61427, "forest", false)
	_check(not RealmRules.enabled(legacy.state) and not legacy.state.has("realm"), "runs without the flag keep the old rules")
	_check(legacy.queue_build("B16") != "", "realm-only facility rejected in an old-rules run")
	_check(legacy.queue_build("B27") != "", "old-rules stage gate still enforced")
	var twin := _new()
	_check(twin.state == game.state, "same seed and config build the same starting state")


func _test_building_rules() -> void:
	var game := _new()
	var s := game.state
	_check(CabinetActions.start_project(game, "B19") != "", "mill needs a granary first")
	_check(CabinetActions.start_project(game, "B71") != "", "watchtower needs a palisade first")
	_check(CabinetActions.start_project(game, "B13") == "", "farm pair queued")
	_check(s.orders.size() == 2, "farm expansion reserves two plots")
	_check(CabinetActions.start_project(game, "B16") == "", "a second site can run in parallel")
	_check(CabinetActions.start_project(game, "B25") != "", "fourth simultaneous site rejected")
	s.facilities["B16"] = 1
	s.orders = []
	_check(CabinetActions.start_project(game, "B16") != "", "fishery limited to one")
	s.facilities["B25"] = 1
	_check(CabinetActions.start_project(game, "B27") == "", "quarry unlocked by a logging camp, not by population")
	var plain := _new()
	plain.state.public.stone = 100
	plain.state.public.wood = 200
	plain.state.orders = ["B22"]
	plain.advance()
	var normal := int(plain.state.projects[0].work_total)
	var quick := _new()
	quick.state.public.stone = 100
	quick.state.public.wood = 200
	quick.state.facilities["B26"] = 1
	quick.state.orders = ["B22"]
	quick.advance()
	_check(int(quick.state.projects[0].work_total) == int(ceil(normal * 0.75)), "sawmill cuts construction work by a quarter")


func _test_stat_consequences() -> void:
	var game := _new()
	var s := game.state
	var base_gather := WeekSim.bonus(s, "gather")
	s.mood = 80
	RealmRules.refresh(s, content)
	_check(WeekSim.bonus(s, "gather") > base_gather, "high mood raises gathering")
	s.mood = 30
	RealmRules.refresh(s, content)
	_check(WeekSim.bonus(s, "gather") < base_gather, "low mood lowers gathering")
	_check(is_equal_approx(WeekSim.raw_bonus(s, "gather"), float(s.bonuses.get("gather", 1.0))), "weekly modifiers are never written into saved bonuses")
	s.mood = 55
	var base_labor: float = s.realm.labor_base
	s.health = 80
	RealmRules.refresh(s, content)
	_check(s.labor_ratio > base_labor, "good health adds workers")
	s.health = 35
	RealmRules.refresh(s, content)
	_check(s.labor_ratio < base_labor, "poor health removes workers")
	s.health = 60
	s.trust = 90
	RealmRules.refresh(s, content)
	_check(WeekSim.bonus(s, "tax", 0.0) > 0.0, "trust improves tax collection")
	s.guild = 20
	RealmRules.refresh(s, content)
	var dear := game.trade_quote("tools", 4, true)
	s.guild = 85
	RealmRules.refresh(s, content)
	_check(game.trade_quote("tools", 4, true) < dear, "merchant favour lowers prices")
	# 민심이 3주 연속 바닥이면 이탈
	var unrest := _new()
	unrest.state.village = 0
	unrest.state.ration = 0.75
	var before: int = unrest.state.pop
	for i in 6:
		unrest.state.mood = 20
		_resolve_free(unrest)
		unrest.advance()
	_check(unrest.state.pop < before and unrest.state.realm.tally.lost > 0, "sustained unrest makes residents leave")
	var perk := _new()
	var raw := WeekSim.raw_bonus(perk.state, "harvest")
	perk.state.realm.crop = 1.2
	RealmRules.refresh(perk.state, content)
	perk.state.perk_offer = ["P53"]
	perk.choose_perk("P53")
	_check(is_equal_approx(WeekSim.raw_bonus(perk.state, "harvest"), raw * 1.06), "perks stack on the saved value, not on weather")


func _test_production() -> void:
	var game := _new()
	_resolve_free(game)
	var control := _new()
	_resolve_free(control)
	game.state.facilities["B16"] = 1
	game.advance()
	control.advance()
	_check(WeekSim.total_food(game.state) > WeekSim.total_food(control.state) + 10, "fishery feeds residents with spare labor")
	_check(game.state.labor_report.get("realm", 0) == 4, "fishery staffed by four residents")
	var smith := _new()
	_resolve_free(smith)
	smith.state.facilities["B33"] = 1
	smith.state.public.stone = 20
	var tools: float = smith.state.public.tools
	var stone: float = smith.state.public.stone
	smith.advance()
	_check(smith.state.public.tools > tools and smith.state.public.stone < stone, "smithy turns wood and stone into tools")
	var starved := _new()
	_resolve_free(starved)
	starved.state.facilities["B33"] = 1
	starved.state.public.stone = 0
	tools = starved.state.public.tools
	starved.advance()
	_check(is_equal_approx(starved.state.public.tools, tools), "smithy idles without stone and creates nothing")
	var market := _new()
	_resolve_free(market)
	market.state.facilities["B49"] = 1
	var money: int = market.state.public.money
	market.advance()
	_check(market.state.ledger.any(func(e): return e.src == "market_fee" and e.qty > 0), "market collects a weekly toll")
	_check(TurnReceipt.valid(market.state.last_receipt), "turn receipt stays valid with realm ledger sources")
	_check(money >= 0, "money sanity")


func _test_policies() -> void:
	var game := _new()
	var s := game.state
	_check(RealmRules.policy_slots(s) == 1, "one policy slot at start")
	_check(RealmRules.set_policy(s, content, "open_market", true) != "", "open market needs a market")
	_check(RealmRules.set_policy(s, content, "militia", true) == "", "first edict accepted")
	_check(RealmRules.target(s, "security") >= 14 and s.labor_ratio < s.realm.labor_base, "militia raises security target and costs labor")
	_check(RealmRules.set_policy(s, content, "militia", false) != "", "edict change blocked during cooldown")
	s.week = 10
	_check(RealmRules.set_policy(s, content, "relief", true) != "", "second edict blocked by slot count")
	s.facilities["B63"] = 1
	_check(RealmRules.set_policy(s, content, "relief", true) == "", "scribe office opens a second slot")
	s.week = 1
	var relief := _new()
	_resolve_free(relief)
	RealmRules.set_policy(relief.state, content, "relief", true)
	var public_food: float = relief.state.public.food
	var total := WeekSim.total_food(relief.state)
	relief.advance()
	_check(relief.state.public.food < public_food - 5, "public relief moves public food to residents every week")
	_check(WeekSim.total_food(relief.state) < total, "relief is a transfer, consumption still applies once")
	var levy := _new()
	RealmRules.set_policy(levy.state, content, "tax_relief", true)
	levy.state.week = 20
	_check(RealmRules.policy_error(levy.state, content, "tax_levy", true) != "", "relief and levy are exclusive")
	_check(SaveStore.valid(relief.bundle()), "state with an active policy saves")


func _test_events() -> void:
	var game := _new()
	var s := game.state
	_resolve_free(game)
	s.active_event = "RV_FEVER"
	var fever: Dictionary = content.events.RV_FEVER
	_check(game.option_error(fever.options[0]) != "", "clinic option locked without a clinic")
	s.facilities["B57"] = 1
	_check(game.option_error(fever.options[0]) == "", "clinic option unlocked by the clinic")
	var health: float = s.health
	_check(game.choose_event(0) == "", "event resolves")
	_check(s.health > health and s.realm.outcome.event == "RV_FEVER", "outcome recorded with applied effects")
	# 확률 결과는 같은 저장에서 같은 결과
	var a := _new(777)
	var b := _new(777)
	for run in [a, b]:
		_resolve_free(run)
		run.state.active_event = "RV_RAID"
		run.choose_event(1)
	_check(a.state == b.state, "chance outcomes reproduce from the same state")
	_check(a.state.realm.outcome.rolled and a.state.realm.outcome.chance > 0.05, "chance outcome reports its odds")
	# 손실은 가진 만큼만
	var poor := _new()
	_resolve_free(poor)
	poor.state.public.food = 10
	poor.state.public.wood = 5
	poor.state.security = 0
	poor.state.active_event = "RV_RAID"
	var wins := 0
	for attempt in 12:
		var trial := GameSession.new(content)
		trial.state = poor.state.duplicate(true)
		trial.profile = poor.profile.duplicate(true)
		trial.state.realm.rolls = attempt
		trial.choose_event(1)
		if trial.state.realm.outcome.win: wins += 1
		_check(trial.state.public.food >= 0 and trial.state.public.wood >= 0 and trial.state.pop >= 1, "raid losses never go below zero")
		_check(SaveStore.valid(trial.bundle()), "post-raid state is saveable")
	_check(wins < 12, "a defenceless estate loses some raids")
	var strong := 0
	for attempt in 12:
		var trial := GameSession.new(content)
		trial.state = poor.state.duplicate(true)
		trial.profile = poor.profile.duplicate(true)
		trial.state.security = 90
		trial.state.facilities["B67"] = 1
		trial.state.realm.rolls = attempt
		trial.choose_event(1)
		if trial.state.realm.outcome.win: strong += 1
	_check(strong > wins, "security and a palisade win more raids")
	# 금화 보상은 공공 금고로
	var rich := _new()
	_resolve_free(rich)
	rich.state.active_event = "RV_ROYAL"
	var money: int = rich.state.public.money
	rich.choose_event(1)
	_check(rich.state.public.money == money + 700 and not rich.state.has("money"), "gold rewards reach the public treasury")
	# 후속 사건
	var chain := _new()
	_resolve_free(chain)
	chain.state.active_event = "RV_SURVEY"
	chain.choose_event(0)
	_check(chain.state.realm.queue.any(func(item): return item.id == "RV_SURVEY_DONE"), "follow-up event queued")
	chain.state.week = int(chain.state.week) + 4
	_until(chain, "RV_SURVEY_DONE")
	_check(chain.state.active_event == "RV_SURVEY_DONE", "queued follow-up fires on its week")
	var crop: float = chain.state.realm.crop
	chain.choose_event(0)
	_check(chain.state.realm.crop > crop and WeekSim.bonus(chain.state, "harvest") > WeekSim.raw_bonus(chain.state, "harvest") * 0.99, "survey result raises this year's harvest")
	# 이주: 빈집이 있어야 온다
	var crowded := _new()
	_resolve_free(crowded)
	crowded.state.pop = 100
	crowded.state.week = 9
	crowded.advance()
	_check(not crowded.state.realm.queue.any(func(item): return str(item.id).begins_with("RV_MIG")) and not str(crowded.state.active_event).begins_with("RV_MIG"), "no migrants without free housing")
	var roomy := _new()
	_resolve_free(roomy)
	roomy.state.facilities["B01"] = 1
	roomy.state.mood = 70
	roomy.state.week = 9
	roomy.advance()
	_until(roomy, "RV_MIG")
	_check(str(roomy.state.active_event).begins_with("RV_MIG"), "migrants arrive when there is room and the estate is attractive")
	var pop: int = roomy.state.pop
	_check(roomy.choose_event(0) == "", "migrants accepted")
	_check(roomy.state.pop > pop and roomy.state.realm.tally.immigrants == roomy.state.pop - pop, "accepted migrants join and are tallied")


func _test_trade() -> void:
	var game := _new()
	_resolve_free(game)
	_check(game.trade("wood", 40, false) != "", "selling needs a market")
	game.state.facilities["B49"] = 1
	_check(game.trade("wood", 40, false) == "", "market enables selling")
	_check(int(game.state.shipments[0].arrival) == int(game.state.week) + 2, "two-week delivery by default")
	game.state.facilities["B52"] = 1
	game.trade("stone", 40, true)
	_check(int(game.state.shipments[1].arrival) == int(game.state.week) + 1, "cart depot delivers in one week")
	var spring := game.trade_quote("fuel", 120, true)
	game.state.week = 45
	_check(game.trade_quote("fuel", 120, true) > spring, "firewood costs more in winter")


## 날짜가 정해진 이야기 사건이 먼저 뜰 수 있으므로, 원하는 사건이 올라올 때까지 무료 선택으로 넘긴다.
func _until(game: GameSession, prefix: String) -> void:
	for attempt in 6:
		game._schedule_event()
		if str(game.state.active_event).begins_with(prefix): return
		_resolve_free(game)


## ---------- 실제 52주 주행 ----------

func _resolve_free(game: GameSession) -> void:
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	if game.state.active_event == "": return
	var event: Dictionary = content.events[game.state.active_event]
	for i in event.options.size():
		var option: Dictionary = event.options[i]
		if option.get("cost", {}).is_empty() and not option.has("requires_housing") and game.option_error(option) == "":
			game.choose_event(i)
			return


## 생각 있는 영주: 가능한 가장 적극적인 선택을 하되 승산 낮은 싸움은 피한다.
func _resolve_smart(game: GameSession) -> void:
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	if game.state.active_event == "": return
	var event: Dictionary = content.events[game.state.active_event]
	var s := game.state
	for i in event.options.size():
		var option: Dictionary = event.options[i]
		if game.option_error(option) != "": continue
		if option.has("chance") and RealmRules.chance_of(s, option) < 0.5 and i < event.options.size() - 1: continue
		if float(option.get("cost", {}).get("money", 0)) > float(s.public.money) * 0.4: continue
		if float(option.get("cost", {}).get("food", 0)) > 0 and WeekSim.food_weeks(s) < 6: continue
		if event.get("immigration", false) and option.has("requires_housing") and (WeekSim.food_weeks(s) < 9 or int(s.week) > 30): continue
		if game.choose_event(i) == "": return
	_resolve_free(game)


func _play(game: GameSession, smart: bool) -> Dictionary:
	var lowest := 99.0
	var built := 0
	var guard := 0
	while game.state.status == "active" and guard < 200:
		guard += 1
		if smart: _resolve_smart(game)
		else: _resolve_free(game)
		var s := game.state
		if smart:
			var sites: int = s.orders.size() + s.projects.size()
			var reserve := 1500 if int(s.week) < 20 else 2500
			if s.trial == "audit": reserve += 1200 if int(s.week) >= 40 else 3200
			if sites < 2:
				for id in BUILD_ORDER:
					if float(s.public.money) - Constants.GRADE_COST[content.facilities[id].grade].gold * 100 * (2 if id == "B13" else 1) < reserve: continue
					if id == "B13" and int(s.facilities.get("B13", 0)) >= 8: continue
					var wanted_count := 2 if id in ["B17", "B14"] else 1
					if id != "B13" and int(s.facilities.get(id, 0)) + s.orders.count(id) + s.projects.filter(func(p): return p.id == id).size() >= wanted_count: continue
					if id == "B01" and WeekSim.capacity(s, content, "housing") - s.pop > 14: continue
					if CabinetActions.start_project(game, id) == "":
						built += 1
						break
			var policy := "build" if not s.orders.is_empty() or not s.projects.is_empty() else "balanced"
			var fuel_goal: float = s.pop * 0.1 * 13 * WeekSim.bonus(s, "heating") * 1.6
			if int(s.week) >= 22 and int(s.facilities.get("B25", 0)) > 0 and s.public.fuel < fuel_goal: policy = "winter"
			if WorkcrewRules.select(s, content, policy) != "": WorkcrewRules.select(s, content, "balanced")
			var food_floor := 7.0 if int(s.week) < 36 else 14.5
			if s.trial == "rot" and int(s.week) >= 34: food_floor = 16.0
			# 수확이 줄어든 변경에서는 가을부터 남는 돈으로 연말 식량을 사 둔다. 감찰 시련이면 금고 10금은 남긴다.
			var keep := 1300.0 if s.trial == "audit" else 300.0
			if WeekSim.food_weeks(s) < food_floor and s.shipments.size() < 2 and s.public.money > (keep if int(s.week) >= 36 else reserve * 0.5): CabinetActions.buy_supply(game, "food")
			if int(s.week) >= 30 and s.public.fuel < fuel_goal * 0.6 and not s.shipments.any(func(x): return x.asset == "fuel"): CabinetActions.buy_supply(game, "fuel")
			if s.public.stone < 10 and s.public.money > 3000 and not s.shipments.any(func(x): return x.asset == "stone"): CabinetActions.buy_supply(game, "stone")
			if s.public.tools < 3 and s.public.money > 2500 and not s.shipments.any(func(x): return x.asset == "tools"): CabinetActions.buy_supply(game, "tools")
			var wanted := "militia" if s.security < 42 else "relief" if s.mood < 45 and s.public.food > 400 else ""
			if wanted != "" and wanted not in s.realm.policies and s.realm.policies.size() < RealmRules.policy_slots(s):
				RealmRules.set_policy(s, content, wanted, true)
		var report := game.advance()
		if not report.advanced:
			_check(false, "advance blocked at week %d: %s" % [s.week, str(report.notes)])
			break
		lowest = minf(lowest, WeekSim.food_weeks(game.state))
		_check(game.state.public.money >= 0 and game.state.public.food >= -0.0001 and game.state.resident.food >= -0.0001 and game.state.public.tools >= -0.0001 and game.state.public.wood >= -0.0001 and game.state.public.stone >= -0.0001, "stocks never negative (week %d)" % report.week)
		if int(report.week) % 13 == 0: _check(SaveStore.valid(game.bundle()), "state saveable at week %d" % report.week)
	_check(guard < 200, "run terminates")
	var result: Dictionary = game.state.result
	return {"success":result.get("success", false), "grade":result.get("grade", "?"), "points":result.get("points", 0),
		"realm_points":result.get("realm_points", 0), "pop":game.state.pop, "lowest":lowest, "built":built,
		"events":game.state.seen_events.size(), "raids":game.state.realm.tally.raids, "rank":game.state.realm.rank,
		"mood":int(game.state.mood), "health":int(game.state.health), "security":int(game.state.security),
		"money":int(game.state.public.money / 100), "week":result.get("week", 0), "reason":result.get("reason", ""),
		"why":"%s/%s/%s/%s %s" % ["F" if game.state.goals.farms.done else "f", "G" if game.state.goals.storage.done else "g", "S" if game.state.goals.food.done else "s", "T" if result.get("trial_passed", false) else "t", game.state.trial]}


func _test_runs() -> void:
	var first := _new(61427)
	var second := _new(61427)
	var outcome_a := _play(first, true)
	var outcome_b := _play(second, true)
	_check(first.state == second.state, "a full 52-week realm run reproduces from seed and decisions")
	_check(outcome_a == outcome_b, "run summary reproduces")
	_check(first.state.status == "finalized" and first.state.result.has("grade"), "run settles with a grade")
	_check(SaveStore.valid(first.bundle()), "finalized realm run is saveable")
	var broken := first.bundle()
	broken.state.realm.weather = "nonexistent"
	_check(not SaveStore.valid(broken), "unknown weather rejected by save validation")
	broken = first.bundle()
	broken.state.realm.policies = ["nonexistent"]
	_check(not SaveStore.valid(broken), "unknown policy rejected by save validation")
	var smart_wins := 0
	var passive_wins := 0
	var total := 0
	var events := 0
	for region in ["forest", "river", "highland"]:
		for seed_value in [61427, 1203, 88001, 4711, 990133, 27, 555555, 31337]:
			total += 1
			var smart := _play(_new(seed_value, region), true)
			var passive := _play(_new(seed_value, region), false)
			if smart.success: smart_wins += 1
			if passive.success: passive_wins += 1
			events += int(smart.events)
			print("%-8s %-7d  적극 %s %s pop %d 최저 %.1f주 사건 %d 습격 %d 등급 %d 민%d 건%d 치%d 금%d 점수 %d(+%d) | 방치 %s %s pop %d 최저 %.1f주" % [region, seed_value,
				("성공" if smart.success else "실패") + " " + smart.why, smart.grade, smart.pop, smart.lowest, smart.events, smart.raids, smart.rank, smart.mood, smart.health, smart.security, smart.money, smart.points, smart.realm_points,
				"성공" if passive.success else "실패", passive.grade, passive.pop, passive.lowest])
	print("적극 운영 성공 %d / %d · 방치 운영 성공 %d / %d · 회차당 사건 평균 %.1f" % [smart_wins, total, passive_wins, total, float(events) / total])
	# 2026-11-19 수확·채집 45%로 낮춘 뒤의 기준. 이 봇은 장터 판매를 쓰지 않으므로 절반을 넘기면 된다.
	_check(smart_wins >= int(total * 0.5), "an engaged ruler survives the first year at least half the time (%d/%d)" % [smart_wins, total])
	_check(passive_wins <= int(total * 0.34), "doing nothing usually fails (%d/%d)" % [passive_wins, total])
	_check(float(events) / total >= 16, "a run sees a steady stream of decisions")
