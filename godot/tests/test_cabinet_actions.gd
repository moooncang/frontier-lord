extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary


func _init() -> void:
	content = Content.load_all()
	_test_atomic_project()
	_test_farm_completion()
	_test_seasonal_eta()
	_test_supplies()
	_test_advisor()
	_test_integrated_advisor_and_save()
	_test_integrated_news_and_contracts()
	_test_full_run_smoke()
	print("CABINET ACTIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CABINET ACTIONS FAIL: ", label)


func _new() -> GameSession:
	var game := GameSession.new(content)
	game.start_run(1234, "settler", {"region":"forest", "candidate":0, "relics":[], "tutorial":false})
	CabinetRules.setup(game.state)
	return game


func _test_atomic_project() -> void:
	var game := _new()
	game.state.public.wood = 8
	game.state.assign.logging = 3
	var before: Dictionary = game.state.duplicate(true)
	var profile: Dictionary = game.profile.duplicate(true)
	var data: Dictionary = content.duplicate(true)
	var preview := CabinetActions.offer(game, "B13")
	_check(preview.count == 2 and preview.error != "", "farm bundle rejected when only one farm is affordable")
	_check(preview.error == "목재 부족", "shortage uses a short localized resource name")
	_check(game.state == before and game.profile == profile and game.content == data, "failed offer is entirely read only")
	_check(CabinetActions.start_project(game, "B13") != "", "second farm failure rejects whole bundle")
	_check(game.state == before and game.profile == profile, "failed bundle restores orders, labor, resources and all other state")
	_check(CabinetActions.start_project(game, "missing") != "" and game.state == before, "unknown project rejected without changes")
	_check(CabinetActions.offer(game, "missing").error != "", "unknown offer reports reason")
	game = _new()
	_check(CabinetActions.start_project(game, "B22") == "", "one granary project may be reserved")
	before = game.state.duplicate(true)
	_check(CabinetActions.start_project(game, "B25") == "진행 중인 공사를 먼저 끝내세요", "second queued project blocked")
	_check(game.state == before, "queued project block is atomic")
	WeekSim.process_week(game.state, content)
	before = game.state.duplicate(true)
	_check(not game.state.projects.is_empty(), "granary really remains under construction")
	_check(CabinetActions.start_project(game, "B25") != "" and game.state == before, "active construction blocks a new project")


func _test_farm_completion() -> void:
	var game := _new()
	var before: Dictionary = game.state.duplicate(true)
	var preview := CabinetActions.offer(game, "B13")
	_check(preview.error == "" and preview.count == 2, "initial farm bundle contains exactly two plots")
	_check(preview.cost == {"money":800,"wood":16,"stone":0,"tools":2,"iron":0}, "bundle uses full grade costs")
	_check(preview.eta == 2 and preview.eta_text == "약 2주", "first farms predict two weeks with automatic workers")
	_check(preview == CabinetActions.offer(game, "B13") and game.state == before, "eta is deterministic and consumes no state, event or random stream")
	_check(CabinetActions.start_project(game, "B13") == "", "first farm bundle starts")
	_check(game.state.orders == ["B13", "B13"] and game.state.assign.build == 8, "bundle commits reservations and automatic construction assignment")
	_check(game.state.public == before.public and game.state.week == before.week, "starting reserves but does not pay or advance")
	for step in 2:
		CabinetRules.reassign(game.state, content)
		var report := WeekSim.process_week(game.state, content)
		_check(report.advanced, "economic construction week %d advances" % (step + 1))
	_check(game.state.week == 3 and game.state.facilities.B13 == 6, "real automatic labor completes two farms before sowing")
	_check(game.state.orders.is_empty() and game.state.projects.is_empty(), "completed bundle leaves no unfinished jobs")
	_check(game.state.public.wood == before.public.wood - 16, "actual farm materials match quoted total")
	game.state.facilities.B13 = 5
	_check(CabinetActions.offer(game, "B13").count == 1, "one missing plot produces a one-plot offer")
	game.state.facilities.B13 = 0
	_check(CabinetActions.offer(game, "B13").count == 2, "farm catch-up never exceeds two plots")
	game.state.facilities.B13 = 6
	_check(CabinetActions.offer(game, "B13").count == 1, "further farm growth remains one plot")


func _test_seasonal_eta() -> void:
	var game := _new()
	game.state.week = 3
	game.state.pop = 40
	var preview := CabinetActions.offer(game, "B13")
	_check(preview.eta == 6, "sowing labor postpones construction until weeks seven and eight")
	_check("농사" in preview.eta_text, "seasonal labor stall includes a reason")
	game = _new()
	game.state.pop = 1
	preview = CabinetActions.offer(game, "B13")
	_check(preview.eta == -1 and "주민" in preview.eta_text, "zero construction workforce gives unknown completion with cause")
	game = _new()
	game.state.week = 52
	preview = CabinetActions.offer(game, "B22")
	_check(preview.eta == -1 and "회차 종료" in preview.eta_text, "eta does not promise completion after the run ends")


func _test_supplies() -> void:
	var game := _new()
	var before: Dictionary = game.state.duplicate(true)
	var packages := CabinetActions.supplies(game)
	_check(packages.size() == 5 and game.state == before, "five package quotes are read only")
	var quantities := {"food":160, "wood":40, "stone":40, "tools":4, "fuel":120}
	for package in packages:
		_check(package.quantity == quantities[package.asset], "correct package quantity " + package.asset)
		_check(package.price == game.trade_quote(package.asset, package.quantity, true), "actual price including modifiers " + package.asset)
		_check(package.arrival == 3 and package.error == "", "available package arrives in two weeks " + package.asset)
	game.state.bonuses.buy = 0.8
	game.state.trade_discount = 0.25
	var food: Dictionary = CabinetActions.supplies(game)[0]
	var cash: int = game.state.public.money
	var stock: float = game.state.public.food
	_check(CabinetActions.buy_supply(game, "food") == "", "package uses real trade action")
	_check(game.state.public.money == cash - food.price and game.state.public.food == stock, "discounted purchase prepays without early delivery")
	_check(game.state.shipments[0].arrival == food.arrival, "shipment arrival matches displayed quote")
	game.state.week = 2
	game._arrive()
	_check(game.state.public.food == stock and game.state.shipments.size() == 1, "package does not arrive one week early")
	game.state.week = 3
	game._arrive()
	_check(game.state.public.food == stock + 160 and game.state.shipments.is_empty(), "correct package arrives after two weeks")
	game.state.pop = 400
	_check(CabinetActions.supplies(game)[0].quantity == 200, "food order respects maximum quantity")
	game.state.pop = 0
	_check(CabinetActions.supplies(game)[0].quantity == 1, "food order respects minimum quantity")
	game.state.public.money = 0
	before = game.state.duplicate(true)
	_check(CabinetActions.supplies(game)[0].error != "" and CabinetActions.buy_supply(game, "food") != "", "budget error blocks package purchase")
	_check(game.state == before, "failed package purchase changes nothing")
	game = _new()
	for index in 3: _check(CabinetActions.buy_supply(game, "tools") == "", "fill real cart %d" % index)
	before = game.state.duplicate(true)
	_check("수레" in CabinetActions.supplies(game)[0].error, "full carts produce explicit error")
	_check(CabinetActions.buy_supply(game, "wood") != "" and game.state == before, "fourth cart is not purchased")
	_check(CabinetActions.buy_supply(game, "missing") != "" and game.state == before, "unknown supply changes nothing")


func _test_advisor() -> void:
	var game := _new()
	var before: Dictionary = game.state.duplicate(true)
	_check(CabinetActions.set_advisor(game, "missing") != "" and game.state == before, "invalid advisor preserves full state")
	_check(CabinetActions.set_advisor(game, "CH03") == "", "known advisor may be appointed")
	before.cabinet.advisor = "CH03"
	_check(game.state == before, "appointment changes only selected advisor, without effects or schedule use")
	var priest := CabinetActions.advisor_definition(game, "CH03")
	_check(priest.amount == 3 and priest.effect == "health" and "매주" in priest.benefit, "advisor definition explains weekly benefit")
	game.state.bonuses.trust = 2
	_check(CabinetActions.advisor_definition(game, "CH01").amount == 6, "advisor trust display includes current perk bonus")


func _integrated(cabinet: bool = true, seed_value: int = 1234, region: String = "forest") -> GameSession:
	var game := GameSession.new(content)
	game.start_run(seed_value, "settler", {"region":region, "candidate":0, "relics":["seeds", "axe"], "tutorial":false, "cabinet":cabinet})
	return game


func _test_integrated_advisor_and_save() -> void:
	var game := _integrated()
	var legacy := _integrated(false)
	_check(CabinetRules.enabled(game.state) and int(game.state.cabinet.advisor_week) == 0, "real cabinet start enables rules and starts with no advisor payout")
	_check(game.state.active_event == "" and "EV01" in game.state.seen_events, "cabinet start absorbs introductory event into development")
	_check(legacy.state.active_event == "EV01" and not CabinetRules.enabled(legacy.state), "legacy chronicle still starts with introductory event")
	_check(game.state.mood == legacy.state.mood and game.state.trust == legacy.state.trust and game.state.village == legacy.state.village, "skipping introductory letter invents no choice bonuses")
	_check(not game.state.perk_offer.is_empty(), "cabinet initial perk remains a real pending decision")
	_check(CabinetActions.set_advisor(game, "CH12") == "", "appoint actual security advisor before first turn")
	var before: Dictionary = game.state.duplicate(true)
	var blocked := game.advance()
	_check(not blocked.advanced and game.state == before, "pending perk blocks full advance without advisor, labor or time mutations")
	_check(game.choose_perk(str(game.state.perk_offer[0])), "resolve actual initial cabinet perk")
	var security: float = game.state.security
	var health: float = game.state.health
	var actions: int = int(game.state.actions)
	for id in ["CH02", "CH03", "CH12"]: _check(CabinetActions.set_advisor(game, id) == "", "change advisor before turn " + id)
	_check(game.state.security == security and game.state.health == health and game.state.actions == actions, "same-week appointments apply no immediate bonus or action charge")
	var report := game.advance()
	_check(report.advanced and game.state.week == 2, "actual cabinet turn advances one week")
	_check(game.state.security == security + 4 and int(game.state.cabinet.advisor_week) == 1, "CH12 grants exactly four security once for week one")
	_check(game.state.actions == 2 and game.state.actions_used.is_empty(), "next week refreshes normal schedule after advisor visit")
	var store := SaveStore.new("res://tests/output/cabinet_actions_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "", "integrated cabinet state writes through real SaveStore")
	var loaded := store.read()
	_check(loaded.ok, "integrated cabinet snapshot passes load validation")
	if not loaded.ok: return
	var restored := GameSession.new(content)
	restored.state = loaded.bundle.state
	restored.profile = loaded.bundle.profile
	_check(restored.state.cabinet.advisor == "CH12" and int(restored.state.cabinet.advisor_week) == 1, "advisor identity and paid week survive serialization")
	_check(restored.state.security == game.state.security, "loading adds no duplicate advisor bonus")
	security = restored.state.security
	CabinetActions.advisor_definition(restored, "CH12")
	CabinetActions.offer(restored, "B13")
	for id in ["CH02", "CH12"]: CabinetActions.set_advisor(restored, id)
	_check(restored.state.security == security and int(restored.state.cabinet.advisor_week) == 1, "queries and post-load reselection cannot repay the previous week")
	var uninterrupted := game.advance()
	var resumed := restored.advance()
	_check(uninterrupted.advanced and resumed.advanced, "both original and restored sessions continue")
	_check(restored.state.security == security + 4 and restored.state.security == game.state.security, "restored session grants only the new week's four security")
	_check(int(restored.state.cabinet.advisor_week) == 2 and restored.state.week == 3, "advisor marker follows completed week after reload")


func _test_integrated_news_and_contracts() -> void:
	var game := _integrated()
	_check(_resolve_pending(game), "resolve cabinet initial decisions for news test")
	CabinetActions.set_advisor(game, "CH12")
	game.state.week = 39
	game.state.seen_events = []
	for id in content.events:
		if id != "EV14": game.state.seen_events.append(id)
	var trust: float = game.state.trust
	var report := game.advance()
	_check(report.advanced and game.state.week == 40, "actual advance reaches royal inspection week")
	_check(game.state.active_event == "" and "EV14" in game.state.seen_events, "no-cost royal inspection becomes news without a blocking modal")
	_check(game.state.trust == trust + 4 and "+4" in str(game.state.cabinet.get("news", "")), "royal inspection grants its actual trust reward and states it in news")
	trust = game.state.trust
	game._schedule_event()
	_check(game.state.trust == trust, "already reported inspection is not rewarded twice")
	for cabinet in [true, false]:
		game = _integrated(cabinet)
		var steps := 0
		while game.state.week < 7 and steps < 10:
			steps += 1
			if not _resolve_pending(game): break
			var progressed := game.advance()
			_check(progressed.advanced, "contract boundary advances week %d cabinet=%s" % [game.state.week, cabinet])
			if not progressed.advanced: break
		_check(game.state.week == 7 and not game.state.perk_offer.is_empty(), "both modes retain first seasonal perk at week seven")
		_check(game.state.contract_offer.is_empty() if cabinet else game.state.contract_offer.size() == 3, "season contract suppressed only in cabinet mode")


func _resolve_pending(game: GameSession) -> bool:
	if not game.state.perk_offer.is_empty():
		if not game.choose_perk(str(game.state.perk_offer[0])): return false
	if game.state.active_event != "":
		var event: Dictionary = content.events[game.state.active_event]
		var selected := -1
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if option.get("cost", {}).is_empty() and not option.has("requires_housing"):
				selected = index
				break
		if selected < 0 or game.choose_event(selected) != "": return false
	if not game.state.get("contract_offer", []).is_empty():
		if game.choose_contract("skip") != "": return false
	return true


func _test_full_run_smoke() -> void:
	for region in ["forest", "river", "highland"]:
		var game := _integrated(true, 61427, region)
		CabinetActions.set_advisor(game, "CH03")
		var steps := 0
		var waiting := 0
		while game.state.status == "active" and steps < 60:
			steps += 1
			var week: int = int(game.state.week)
			var resolved := _resolve_pending(game)
			_check(resolved, "smoke decision resolves %s week %d" % [region, week])
			if not resolved: break
			_check(game.state.contract_offer.is_empty(), "cabinet smoke never creates hidden contract obligations")
			var focus := "food" if WeekSim.food_weeks(game.state) < 5.0 else "winter" if week >= 27 and game.state.public.fuel < game.state.pop * 2 else "balanced"
			var allocation := CabinetRules.set_focus(game.state, content, focus)
			_check(not allocation.blocked, "simple focus policy remains executable")
			if game.state.orders.is_empty() and game.state.projects.is_empty():
				for target in [{"id":"B13", "count":6}, {"id":"B22", "count":1}, {"id":"B25", "count":1}, {"id":"B17", "count":2}, {"id":"B14", "count":1}]:
					if int(game.state.facilities.get(target.id, 0)) >= int(target.count): continue
					var offer := CabinetActions.offer(game, target.id)
					if offer.error == "": _check(CabinetActions.start_project(game, target.id) == "", "smoke starts affordable project")
					break
			var needed := ""
			if WeekSim.food_weeks(game.state) < 4: needed = "food"
			elif week >= 37 and game.state.public.fuel < game.state.pop * .6: needed = "fuel"
			elif game.state.public.tools < 2: needed = "tools"
			elif game.state.public.wood < 20 and game.state.facilities.get("B25", 0) == 0: needed = "wood"
			if needed != "" and not game.state.shipments.any(func(shipment): return shipment.buy and shipment.asset == needed):
				for package in CabinetActions.supplies(game):
					if package.asset == needed and package.error == "":
						_check(CabinetActions.buy_supply(game, needed) == "", "smoke buys affordable needed package")
						break
			var report := game.advance()
			_check(report.advanced, "smoke no turn deadlock %s week %d: %s" % [region, week, str(report.notes)])
			if not report.advanced: break
			if not game.state.projects.is_empty() and int(game.state.labor_report.build) == 0: waiting += 1
			_check(game.state.week == week + 1, "smoke one command always advances exactly one week")
			_check(SaveStore.valid(game.bundle()), "smoke full state remains saveable")
			var nonnegative := true
			for quantity in game.state.public.values():
				if not is_finite(float(quantity)) or float(quantity) < -0.00001: nonnegative = false
			_check(nonnegative, "smoke resource pools stay finite and nonnegative")
		_check(game.state.status == "finalized", "smoke reaches a natural ending without getting stuck " + region)
		_check(steps <= 52, "smoke terminates within one complete run")
		print("CABINET SMOKE: %s · week %d · %s · success=%s · food %.1fw · treasury %.2fg · idle construction %dw" % [region, game.state.week, game.state.status, game.state.result.get("success", false), WeekSim.food_weeks(game.state), game.state.public.money / 100.0, waiting])
