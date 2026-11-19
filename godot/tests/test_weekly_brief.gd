extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("WEEKLY BRIEF FAIL: ", label)

func _new() -> GameSession:
	var game := GameSession.new(content)
	game.start_run(1234, "settler", {"region":"forest", "candidate":0, "relics":[], "tutorial":false})
	return game

func _init() -> void:
	content = Content.load_all()
	_test_read_only_preview()
	_test_history_and_ledger()
	_test_construction_and_priorities()
	_test_order_sequence()
	print("WEEKLY BRIEF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_read_only_preview() -> void:
	var game := _new()
	game.state.assign.build = 8
	_check(game.queue_build("B13") == "", "queue real construction")
	var saved: Dictionary = game.state.duplicate(true)
	var data_copy: Dictionary = content.duplicate(true)
	var report := WeeklyBrief.build(game.state, content)
	_check(game.state == saved, "report leaves full source state unchanged")
	_check(content == data_copy, "report leaves content unchanged")
	_check(report == WeeklyBrief.build(game.state, content), "repeat reports are deterministic")
	var expected: Dictionary = saved.duplicate(true)
	var simulated := WeekSim.process_week(expected, content)
	_check(report.preview.available and simulated.advanced, "valid plan has economic preview")
	_check(report.preview.money == expected.public.money, "preview includes full reservation cash deduction")
	_check(is_equal_approx(report.preview.food, WeekSim.total_food(expected)), "preview matches actual economic food result")
	_check(report.preview.labor == expected.labor_report, "preview uses actual labor priorities")
	_check(report.preview.notes == simulated.notes, "construction results visible in preview")
	_check(not report.metrics.money.has_delta, "no invented initial cash baseline")
	_check(report.calendar.harvest_in == 32 and report.calendar.winter_in == 39, "calendar countdown")
	_check(report.preview.scope.contains("교역 도착") and report.preview.scope.contains("겨울 시련"), "preview limitations disclosed")
	_check(game.state.perk_offer == saved.perk_offer and game.state.active_event == saved.active_event, "preview does not consume pending decisions")

func _test_history_and_ledger() -> void:
	var game := _new()
	game.state.week = 3
	game.state.history = [{"week":1,"money":10000,"food":1600.0,"pop":80,"notes":[]}, {"week":2,"money":9400,"food":1500.0,"pop":82,"notes":["수레 도착"]}]
	game.state.public.money = 9200
	game.state.ledger = [
		{"w":1,"src":"harvest","asset":"food","qty":999},
		{"w":2,"src":"gather","asset":"food","qty":10},
		{"w":2,"src":"harvest","asset":"food","qty":15},
		{"w":2,"src":"consume","asset":"food","qty":-8},
		{"w":2,"src":"spoil","asset":"food","qty":-1},
		{"w":2,"src":"spoil","asset":"food","qty":-1},
		{"w":2,"src":"seed","asset":"food","qty":-3},
		{"w":2,"src":"event","asset":"food","qty":4},
		{"w":2,"src":"trade_depart","asset":"food","qty":-5},
		{"w":2,"src":"transfer","asset":"food","qty":0,"amount":300,"from":"public","to":"resident"},
		{"w":2,"src":"tax","asset":"money","qty":999},
		{"w":3,"src":"trade_arrival","asset":"food","qty":200}
	]
	var report := WeeklyBrief.build(game.state, content)
	_check(report.metrics.money.has_delta and report.metrics.money.delta == -600, "completed-week cash change excludes current choices")
	_check(report.metrics.money.current_delta == -200, "current choices tracked separately")
	_check(report.metrics.food.delta == -100 and report.metrics.pop.delta == 2, "food and population changes use historical balances")
	var food: Dictionary = report.report.food
	_check(food.production == 25 and food.consumption == 8, "production and consumption from correct week")
	_check(food.spoilage == 2 and food.seeds == 3, "both account spoilage entries aggregate")
	_check(food.other_in == 4 and food.other_out == 5, "non-production flows separate")
	_check(food.net == 11, "signed ledger reconciles")
	_check(food.transferred == 300 and not food.by_source.has("transfer"), "account transfer excluded from supply change")
	_check(not food.by_source.has("trade_arrival"), "next-week arrivals not mixed into last-week production")
	_check(food.by_source.spoil == -2, "raw source sum preserved")
	_check(report.report.notes == ["수레 도착"], "actual weekly notes retained")
	game.state.history = [game.state.history[0]]
	report = WeeklyBrief.build(game.state, content)
	_check(report.report.has_previous and not report.metrics.money.has_delta, "first completed week exists without fabricated change")

func _test_construction_and_priorities() -> void:
	var game := _new()
	game.state.week = 3
	game.state.pop = 40
	game.state.assign.build = 8
	_check(game.queue_build("B22") == "", "real project queued")
	var report := WeeklyBrief.build(game.state, content)
	_check(report.construction.requested_workers == 8 and report.construction.actual_workers == 0, "farm and gathering priority can leave requested builders idle")
	_check(report.construction.remaining_work == 24 and report.construction.queued.size() == 1, "queued work counted before payment")
	_check(report.priorities.any(func(item): return item.id == "construction_labor"), "labor stall produces actionable warning")
	game.state.public.food = 0
	game.state.resident.food = 0
	game.state.facilities.B17 = 0
	report = WeeklyBrief.build(game.state, content)
	_check(report.priorities[0].id == "food_critical", "survival risk precedes development goals")
	_check(report.priorities.size() <= 3 and report.priorities[0].page == "trade", "bounded priorities include destination")
	game.state.public.money = 0
	report = WeeklyBrief.build(game.state, content)
	_check(not report.preview.available and not report.preview.blocked_reasons.is_empty(), "unaffordable plan does not predict advancement")
	_check(report.construction.actual_workers == 0, "blocked plan cannot pretend construction progress")
	game = _new()
	game.state.week = 40
	game.state.public.fuel = 0
	report = WeeklyBrief.build(game.state, content)
	_check(report.priorities[0].id == "heating_critical", "winter fuel is immediate risk")
	_check(report.calendar.winter_active and report.calendar.harvest_in == -1, "calendar identifies winter and finished harvest")
	game.state.week = 53
	game.state.status = "finalized"
	report = WeeklyBrief.build(game.state, content)
	_check(not report.preview.available, "finished run has no economic forecast")

func _test_order_sequence() -> void:
	var game := _new()
	game.state.assign.build = 8
	game.state.meta_snapshot = ["M04"]
	_check(game.queue_build("B13") == "" and game.queue_build("B13") == "", "queue two discounted-farm candidates")
	var report := WeeklyBrief.build(game.state, content)
	_check(report.construction.queued[0].work_total == 7 and report.construction.queued[1].work_total == 8, "first farm discount counted once")
	_check(report.construction.queued[0].next_work == 7 and report.construction.queued[1].next_work == 1, "queued projects share labor in order")
	_check(report.construction.queued[0].completes_this_week and not report.construction.queued[1].completes_this_week, "completion predicted from allocated work")
	game.state.projects = [{"id":"B01", "work_left":3, "work_total":8, "escrow":120}]
	report = WeeklyBrief.build(game.state, content)
	_check(report.construction.projects[0].next_work == 3 and report.construction.queued[0].next_work == 5, "existing project receives labor before new order")
	_check(report.construction.remaining_work == 18 and report.construction.work_this_week == 8, "total work includes old and queued projects")
