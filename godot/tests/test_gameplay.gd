extends SceneTree

var failures := 0
var assertions := 0
var content: Dictionary


func _init() -> void:
	content = Content.load_all()
	_check(Content.validate(content).is_empty(), "content validation")
	_test_loop()
	_test_commands()
	_test_trade()
	_test_saving()
	_test_support_facilities()
	print("GAMEPLAY: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)


func _new(seed_value: int = 12345) -> GameSession:
	var game := GameSession.new(content)
	game.start_run(seed_value, "settler")
	return game


func _resolve(game: GameSession) -> void:
	if game.state.active_event != "":
		var event: Dictionary = content.events[game.state.active_event]
		# 항상 자금·주거 조건 없이 가능한 선택을 사용한다.
		for i in event.options.size():
			var option: Dictionary = event.options[i]
			if option.get("cost", {}).is_empty() and not option.has("requires_housing"):
				_check(game.choose_event(i) == "", "resolve " + event.title)
				break
	if not game.state.perk_offer.is_empty():
		_check(game.choose_perk(str(game.state.perk_offer[0])), "pick offered perk")


func _prepare(game: GameSession) -> void:
	_resolve(game)
	for id in ["B13", "B13", "B22", "B25"]:
		_check(game.queue_build(id) == "", "queue " + id)
	game.state.assign.build = 8
	game.state.assign.logging = 4


func _play(game: GameSession, until_week: int = 53) -> void:
	var guard := 0
	while game.state.status == "active" and game.state.week < until_week and guard < 100:
		guard += 1
		_resolve(game)
		if game.state.week >= 37:
			game.state.assign.logging = 0
			game.state.assign.fuel = 4 if game.state.public.fuel < 120 else 0
		var report := game.advance()
		_check(report.advanced, "advance at week " + str(game.state.week))
		if not report.advanced:
			break
		_check(game.state.public.money >= 0 and game.state.public.food >= -0.00001 and game.state.resident.food >= -0.00001, "nonnegative stocks")
	_check(guard < 100, "loop terminates")


func _test_loop() -> void:
	var game := _new()
	var before := game.state.duplicate(true)
	_check(not game.advance().advanced and before == game.state, "event blocks time without mutation")
	_prepare(game)
	_play(game)
	_check(game.state.status == "finalized", "52 weeks produce a conclusion")
	_check(game.state.result.success, "guided first winter can succeed")
	_check(game.state.seen_events.size() == 8, "all eight events reached")
	_check(game.state.perks.size() == 3, "three seasonal perk drafts")
	var earned: int = game.profile.points
	game.settle("완주")
	_check(earned == game.profile.points, "reopening conclusion does not duplicate points")
	var current_cash: int = game.state.public.money
	_check(game.buy_upgrade("M01") == "", "purchase permanent upgrade")
	_check(game.state.public.money == current_cash, "upgrade does not mutate current run")
	_check(game.buy_upgrade("M01") != "", "no duplicate upgrade")
	game.start_run(12345, "settler")
	_check(game.state.public.money == 12600, "permanent upgrade applies next run")
	_check(game.state.perks.is_empty() and game.state.seen_events.is_empty(), "run-only progress resets")
	_check(game.profile.points == earned - 8, "remaining meta balance survives restart")
	var first := _new(999)
	var second := _new(999)
	_prepare(first)
	_prepare(second)
	_play(first, 15)
	_play(second, 15)
	_check(first.state == second.state, "same seed and commands reproduce state")
	var short := _new()
	short.settle("은퇴")
	_check(short.profile.points == 0 and short.profile.receipts.is_empty(), "early restart does not farm or consume first bonus")
	print("Guided run earned ", earned, " points; replay and restart verified")


func _test_commands() -> void:
	var game := _new()
	_resolve(game)
	_check(game.queue_build("T_GRANARY") != "", "temporary facilities cannot be built for free")
	_check(game.queue_build("B27") != "", "stage unlock enforced")
	game.state.public.money = 600
	_check(game.queue_build("B13") == "", "first funded command accepted")
	_check(game.queue_build("B13") != "", "cash is reserved across pending commands")
	game.state.assign.build = 0
	game.advance()
	_check(game.state.projects.size() == 1, "project started with held resources")
	_check(WeekSim.cancel_project(game.state, content, 0), "project cancellation")
	_check(game.state.public.wood == 100, "unused construction material returned fully")
	_check(game.state.public.money <= 520 and game.state.public.money > 500, "deposit retained; remainder refunded")
	var shortage := _new()
	_resolve(shortage)
	shortage.state.week = 3
	shortage.state.public.food = 0
	shortage.state.resident.food = 95
	shortage.advance()
	_check(shortage.state.plots_sown == 3, "only whole affordable plots are seeded")
	var capped := _new()
	_resolve(capped)
	_check(capped.queue_build("B17") == "", "second gathering site allowed")
	_check(capped.queue_build("B17") != "", "third gathering site rejected")


func _test_trade() -> void:
	var game := _new()
	_resolve(game)
	var cash: int = game.state.public.money
	var wood: float = game.state.public.wood
	var quote := game.trade_quote("wood", 40, true)
	_check(game.trade("wood", 40, true) == "", "purchase accepted")
	_check(game.state.public.money == cash - quote and game.state.public.wood == wood, "purchase paid but stock not instant")
	game.advance()
	_check(game.state.public.wood == wood, "not delivered after only one week")
	game.advance()
	_check(game.state.public.wood == wood + 40, "arrives after two weekly transitions")
	var sell_quote := game.trade_quote("wood", 40, false)
	_check(sell_quote < quote, "same-market roundtrip is not profitable")
	_check(game.trade("wood", 999, true) != "", "transport capacity enforced")


func _test_saving() -> void:
	var game := _new()
	_prepare(game)
	_play(game, 14)
	var path := "res://tests/output/save_%d" % Time.get_ticks_usec()
	var store := SaveStore.new(path)
	_check(store.write(game.bundle()) == "", "write whole profile and run")
	var loaded := store.read()
	_check(loaded.ok, "read valid snapshot")
	var restored := GameSession.new(content)
	restored.profile = loaded.bundle.profile
	restored.state = loaded.bundle.state
	_check(restored.state.perk_offer == game.state.perk_offer, "perk offer stable across save/load")
	_play(game)
	_play(restored)
	_check(game.state.result == restored.state.result, "save/reload preserves conclusion")
	_check(absf(game.state.public.money - restored.state.public.money) < 1 and absf(WeekSim.total_food(game.state) - WeekSim.total_food(restored.state)) < 0.00001, "save/reload preserves economy")
	_check(store.write(game.bundle()) == "", "second snapshot written")
	var damaged := FileAccess.open(path.path_join("slot_0.json"), FileAccess.WRITE)
	damaged.store_string("broken")
	damaged.close()
	var fallback := SaveStore.new(path).read()
	_check(fallback.ok and fallback.recovered and fallback.bundle.state.week == 14, "corrupt newest slot recovers previous valid snapshot")
	var bad := game.bundle()
	bad.state.public.money = -1
	_check(not SaveStore.valid(bad), "negative cash rejected by save validation")
	bad = game.bundle()
	bad.version = 999
	_check(not SaveStore.valid(bad), "unknown save schema rejected")
	bad = game.bundle()
	bad.state.erase("seed")
	_check(not SaveStore.valid(bad), "incomplete state rejected before UI access")
	bad = game.bundle()
	bad.state.facilities["B_UNKNOWN"] = 1
	_check(not SaveStore.valid(bad), "unknown content rejected")


func _test_support_facilities() -> void:
	var game := _new()
	_resolve(game)
	var quote := game.trade_quote("food", 200, true)
	game.state.facilities.B49 = 1
	_check(game.trade_quote("food", 200, true) < quote, "market facility reduces transport fee")
	game.state.facilities.B14 = 1
	game.state.assign.garden = 4
	var control := _new()
	_resolve(control)
	game.advance()
	control.advance()
	_check(WeekSim.total_food(game.state) > WeekSim.total_food(control.state), "vegetable labor produces food")
	var weak := _new()
	_resolve(weak)
	weak.state.public.food = 0
	weak.state.resident.food = 0
	weak.state.assign.gather = 0
	weak.state.week = 40
	for i in 5:
		_resolve(weak)
		weak.advance()
	_check(weak.state.pop < 80 and weak.state.famine_weeks >= 4, "continued famine causes population loss")
	var debt := _new()
	_resolve(debt)
	debt.state.facilities.B25 = 1
	debt.state.assign.logging = 4
	debt.state.public.money = 0
	for i in 5:
		debt.advance()
	_check(debt.state.arrears_wage > 0 and debt.state.unpaid_weeks == 5, "unpaid public costs accumulate explicitly")
	var owing: int = debt.state.arrears_wage
	debt.state.public.money = owing + 1000
	debt.advance()
	_check(debt.state.arrears_wage == 0 and debt.state.unpaid_weeks == 0, "new cash repays arrears and restores work")
