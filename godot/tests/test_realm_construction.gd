extends SceneTree
## 우선순위 선택은 실제 FIFO 완공 시점을 바꾸고 조회·실패는 저장 상태를 바꾸지 않는다.

var checks := 0
var failures := 0
var content: Dictionary
const CONFIG := {"region":"forest", "candidate":0, "relics":["seeds", "axe"], "tutorial":false,
	"cabinet":true, "campaign":true, "workcrew":true, "realm":true}


func _init() -> void:
	content = Content.load_all()
	_test_order_priority()
	_test_live_priority()
	_test_atomic_errors()
	_test_duplicate_identity()
	_test_efficiency_and_seasons()
	_test_no_jobs_and_end()
	print("REALM CONSTRUCTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("REALM CONSTRUCTION FAIL: ", label)


func _new() -> GameSession:
	var game := GameSession.new(content)
	game.start_run(61427, "settler", CONFIG)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _queue_three() -> GameSession:
	var game := _new()
	for id in ["B22", "B25", "B16"]:
		_check(CabinetActions.start_project(game, id) == "", "queue three distinct facilities " + id)
	return game


func _test_order_priority() -> void:
	var game := _new()
	_check(CabinetActions.start_project(game, "B13") == "", "queue two initial farms")
	_check(CabinetActions.start_project(game, "B16") == "", "queue fishery behind farms")
	var before: Dictionary = game.state.duplicate(true)
	var profile: Dictionary = game.profile.duplicate(true)
	var definitions: Dictionary = content.duplicate(true)
	var preview := CabinetActions.project_preview(game)
	_check(preview.error == "" and preview.rows.size() == 3, "all three reservations have preview rows")
	_check(preview.rows[0].id == "B13" and preview.rows[0].eta == 1 and preview.rows[0].work_next == 8, "first farm receives this week's actual eight work")
	_check(preview.rows[1].eta == 2 and preview.rows[2].eta == 3, "duplicate farm and trailing fishery have distinct ETAs")
	_check(preview.rows[0].kind == "order" and not preview.rows[0].can_promote and preview.rows[2].can_promote, "reservation controls use original order indices")
	_check(preview.work_this_week == 8 and preview.build_workers == 8 and preview.total_work == 24, "preview separates worker count from total queued work")
	_check(preview == CabinetActions.project_preview(game), "repeated preview is deterministic")
	_check(game.state == before and game.profile == profile and content == definitions, "preview does not pay, reserve, roll random numbers or mutate definitions")
	_check(CabinetActions.promote_order(game, 2) == "", "move the fishery to the first reservation")
	_check(game.state.orders == ["B16", "B13", "B13"], "reservation priority is stable for other orders")
	before.orders = ["B16", "B13", "B13"]
	_check(game.state == before, "reservation priority spends neither resources nor time")
	preview = CabinetActions.project_preview(game)
	_check(preview.rows[0].id == "B16" and preview.rows[0].eta == 1 and preview.rows[2].eta == 3, "reservation priority changes which facility opens first")
	var report := game.advance()
	_check(report.advanced and int(game.state.facilities.get("B16", 0)) == 1 and int(game.state.facilities.B13) == 4, "actual first week completes selected fishery instead of a farm")
	_check(game.state.projects.size() == 2 and game.state.projects[0].id == "B13", "remaining duplicate farm projects retain real engine order")
	_check(SaveStore.valid(game.bundle()), "priority and completion remain save compatible")


func _test_live_priority() -> void:
	var game := _queue_three()
	_check(game.advance().advanced, "start all three real construction sites")
	_check(game.state.projects.size() == 3 and int(game.state.projects[0].work_left) == 16, "first granary is partly complete before reprioritizing")
	var before: Dictionary = game.state.duplicate(true)
	var objects: Array = game.state.projects.duplicate(true)
	var normal := CabinetActions.project_preview(game)
	_check(normal.rows[0].id == "B22" and normal.rows[0].work_next == 8 and normal.rows[2].work_next == 0, "normal FIFO puts all work into the granary")
	_check(CabinetActions.promote_project(game, 2) == "", "promote an already paid fishery")
	_check(game.state.projects == [objects[2], objects[0], objects[1]], "priority preserves progress, total work and each project's escrow")
	before.projects = [objects[2], objects[0], objects[1]]
	_check(game.state == before, "active project priority is an atomic ordering change only")
	var preview := CabinetActions.project_preview(game)
	_check(preview.rows[0].id == "B16" and preview.rows[0].work_next == 8 and preview.rows[0].remaining_next == 0, "selected fishery now receives this week's eight work")
	_check(preview.rows[0].eta == 1 and preview.rows[0].completion_week == 2, "predicted completion week refers to the week being played")
	_check(preview.rows[1].work_next == 0 and preview.rows[1].remaining_next == 16, "unselected granary pauses without losing progress")
	_check(game.advance().advanced and int(game.state.facilities.get("B16", 0)) == 1, "actual second week opens prioritized fishery")
	_check(int(game.state.facilities.get("B22", 0)) == 0 and int(game.state.projects[0].work_left) == 16, "real work matches the preview's deferred granary")
	# A new reservation follows all paid sites; reservation controls never hide that boundary.
	_check(CabinetActions.start_project(game, "B13") != "", "two-farm bundle cannot exceed the three-site limit")
	_check(CabinetActions.start_project(game, "B14") == "", "single new site can use the third slot")
	preview = CabinetActions.project_preview(game)
	_check(preview.rows[2].kind == "order" and preview.rows[2].index == 0 and not preview.rows[2].can_promote, "first pending reservation remains behind paid projects")
	_check(CabinetActions.promote_order(game, 0) == "" and game.state.projects[0].id == "B22", "promoting the first reservation never bypasses active sites")
	_check(SaveStore.valid(game.bundle()), "mixed active and reserved priorities pass real save validation")


func _test_atomic_errors() -> void:
	var game := _queue_three()
	var before: Dictionary = game.state.duplicate(true)
	for index in [-1, 3, 100]:
		_check(CabinetActions.promote_order(game, index) != "" and game.state == before, "bad reservation index is atomic %d" % index)
		_check(CabinetActions.promote_project(game, index) != "" and game.state == before, "bad active index is atomic %d" % index)
	game.state.public.wood = 0
	before = game.state.duplicate(true)
	_check(CabinetActions.promote_order(game, 2) != "" and game.state == before, "invalid reservations do not partly reorder or reassign")
	_check(CabinetActions.project_preview(game).error != "" and game.state == before, "invalid reservations produce a read-only error")
	game.state.status = "retired"
	before = game.state.duplicate(true)
	_check(CabinetActions.promote_order(game, 1) != "" and game.state == before, "finished run cannot change priorities")
	_check(CabinetActions.promote_order(null, 0) != "", "missing session returns a usable error")
	game = _new()
	game.state.erase("realm")
	before = game.state.duplicate(true)
	_check(CabinetActions.promote_order(game, 0) != "" and game.state == before, "old rules are not silently converted to realm planning")


func _test_duplicate_identity() -> void:
	var game := _new()
	game.state.meta_snapshot.append("M04")
	game.state.first_survey = false
	_check(CabinetActions.start_project(game, "B13") == "", "queue duplicate farms with first-survey discount")
	var before: Dictionary = game.state.duplicate(true)
	var preview := CabinetActions.project_preview(game)
	_check(preview.rows[0].work_total == 7 and preview.rows[1].work_total == 8, "only the actual first farm uses the survey discount")
	_check(preview.rows[0].work_next == 7 and preview.rows[1].work_next == 1, "leftover work flows to the second duplicate project")
	_check(game.state == before and not game.state.first_survey, "preview does not consume the first-survey privilege")
	_check(game.advance().advanced, "actual discounted farm week advances")
	_check(game.state.first_survey and game.state.projects.size() == 1 and game.state.projects[0].work_left == 7, "actual engine matches both duplicate preview rows")


func _test_efficiency_and_seasons() -> void:
	var game := _queue_three()
	game.advance()
	game.state.public.money = 0
	game.state.arrears_wage = 100000
	game.state.unpaid_weeks = 8
	var preview := CabinetActions.project_preview(game)
	_check(preview.build_workers == 8 and preview.work_this_week == 4, "unpaid labor is eight workers but only four effective work")
	var trial: Dictionary = game.state.duplicate(true)
	CabinetRules.reassign(trial, content)
	WeekSim.process_week(trial, content)
	_check(int(trial.projects[0].work_left) == int(preview.rows[0].remaining_next), "inefficient construction preview matches WeekSim directly")
	game = _new()
	game.state.week = 3
	game.state.pop = 30
	game.state.health = 60
	game.state.realm.labor_base = 0.5
	RealmRules.refresh(game.state, content)
	_check(CabinetActions.start_project(game, "B13") == "", "reserve farms during a full seasonal farming assignment")
	preview = CabinetActions.project_preview(game)
	_check(preview.work_this_week == 0 and preview.rows[0].eta == 5 and preview.rows[1].eta == 6, "seasonal sowing stalls now but correctly predicts later completion")
	_check(preview.rows[0].work_next == 0 and "대기" in preview.rows[0].status, "seasonally blocked row does not claim present progress")
	var predicted: Array = preview.rows.duplicate(true)
	for step in 6:
		CabinetRules.reassign(game.state, content)
		var start: int = int(game.state.facilities.B13)
		WeekSim.process_week(game.state, content)
		if game.state.facilities.B13 > start:
			var row: Dictionary = predicted[int(game.state.facilities.B13) - 5]
			_check(row.eta == step + 1 and row.completion_week == int(game.state.week) - 1, "seasonal predicted completion matches actual economy at step %d" % step)


func _test_no_jobs_and_end() -> void:
	var game := _new()
	var before: Dictionary = game.state.duplicate(true)
	var preview := CabinetActions.project_preview(game)
	_check(preview.rows.is_empty() and preview.error == "" and preview.total_work == 0 and game.state == before, "empty construction ledger is a pure empty result")
	_check(CabinetActions.project_preview(null).error != "", "preview handles an absent session")
	game.state.week = 52
	_check(CabinetActions.start_project(game, "B22") == "", "reserve a real site in the last week")
	preview = CabinetActions.project_preview(game)
	_check(preview.rows[0].eta == -1 and preview.rows[0].completion_week == -1 and "회차 종료" in preview.rows[0].eta_text, "preview never promises completion after the run ends")
	game.state.week = 10
	game.state.pop = 1
	preview = CabinetActions.project_preview(game)
	_check(preview.work_this_week == 0 and preview.rows[0].eta == -1 and "대기" in preview.rows[0].status, "zero available workforce shows a real stalled project")
