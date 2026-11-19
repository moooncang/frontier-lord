extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CABINET FAIL: ", message)


func _state() -> Dictionary:
	return RunState.new_run(content.charters.C01, 9876)


func _init() -> void:
	content = Content.load_all()
	_test_opt_in()
	_test_two_farms()
	_test_focus_and_farm_priority()
	_test_supply()
	_test_materials_and_atomic_failure()
	print("CABINET RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_opt_in() -> void:
	var state := _state()
	state.assign.build = 3
	var before := state.duplicate(true)
	var off := CabinetRules.reassign(state, content)
	_check(not off.enabled and not off.changed and state == before, "old run without cabinet is unchanged")
	var denied := CabinetRules.set_focus(state, content, "winter")
	_check(denied.blocked and state == before, "focus does not implicitly enable cabinet")
	state.cabinet = {"enabled":false, "focus":"food", "advisor":"CH12"}
	before = state.duplicate(true)
	CabinetRules.reassign(state, content)
	_check(state == before, "explicitly disabled cabinet is unchanged")
	CabinetRules.setup(state)
	_check(CabinetRules.enabled(state) and state.cabinet.focus == "food" and state.cabinet.advisor == "CH12", "explicit setup enables existing run and preserves selections")
	_check(state.assign == before.assign and state.public == before.public and state.trust == before.trust and state.actions == before.actions, "setup does not spend resources, change labor or apply advisor effect")
	before = state.duplicate(true)
	CabinetRules.setup(state)
	_check(state == before, "setup is idempotent")
	var invalid := CabinetRules.set_focus(state, content, "unknown")
	_check(invalid.blocked and state == before, "unknown priority rejects without mutation")
	var fresh := _state()
	CabinetRules.setup(fresh)
	_check(fresh.cabinet == {"enabled":true, "focus":"balanced", "advisor":"CH01"}, "new cabinet has agreed defaults")
	var quiet := CabinetRules.reassign(fresh, content)
	_check(quiet.assign.build == 0 and quiet.work_remaining == 0 and quiet.idle == 36, "no project means no builders and visible idle workers")
	_check("진행할 공사가 없습니다." in quiet.notes, "no-project result is explicit")


func _test_two_farms() -> void:
	for discounted in [false, true]:
		var state := _state()
		if discounted: state.meta_snapshot = ["M04"]
		state.orders = ["B13", "B13"]
		CabinetRules.setup(state)
		var before := state.duplicate(true)
		var data_before := content.duplicate(true)
		var plan := CabinetRules.reassign(state, content)
		_check(plan.assign.build == 8 and plan.work_remaining == (15 if discounted else 16), "exact queued farm work including first-only M04")
		var expected := before.duplicate(true)
		expected.assign = state.assign.duplicate(true)
		_check(state == expected and content == data_before, "planning only changes assignment; original orders, resources and content survive")
		var repeat := CabinetRules.reassign(state, content)
		_check(not repeat.changed and repeat.assign == plan.assign, "repeated planning is stable")
		var first := WeekSim.process_week(state, content)
		_check(first.advanced and state.week == 2 and state.facilities.B13 == 5, "first actual week completes one farm")
		_check(state.labor_report.build == 8 and state.labor_report.gather == 8, "engine executes automatic construction and gathering")
		plan = CabinetRules.reassign(state, content)
		var second := WeekSim.process_week(state, content)
		_check(second.advanced and state.week == 3 and state.facilities.B13 == 6 and state.projects.is_empty(), "two farms finish before week-three sowing")
		_check(state.public.money < before.public.money - 800, "real construction prices plus recurring expenses are paid")
		CabinetRules.reassign(state, content)
		WeekSim.process_week(state, content)
		_check(state.plots_sown == 6 and state.labor_report.farm == 24, "all six completed farms enter actual sowing")


func _test_focus_and_farm_priority() -> void:
	var base := _state()
	base.week = 7
	base.pop = 40
	base.facilities.B17 = 2
	base.facilities.B14 = 1
	base.facilities.B25 = 1
	base.orders = ["B13"]
	CabinetRules.setup(base)
	var food := base.duplicate(true)
	var food_plan := CabinetRules.set_focus(food, content, "food")
	var building := base.duplicate(true)
	var build_plan := CabinetRules.set_focus(building, content, "build")
	_check(food_plan.assign.gather > build_plan.assign.gather and food_plan.assign.build < build_plan.assign.build, "food and construction priorities differ under scarce labor")
	_check(build_plan.assign.build == 8 and build_plan.assign.gather == 8, "construction retains base food workers")
	for state in [food, building]:
		var plan := CabinetRules.reassign(state, content)
		var request_total := 0
		for amount in state.assign.values(): request_total += int(amount)
		_check(request_total + int(plan.farm) + int(plan.idle) == int(plan.available), "all available people accounted once")
		WeekSim.process_week(state, content)
		var agrees := int(state.labor_report.farm) == int(plan.farm)
		for job in CabinetRules.JOBS: agrees = agrees and int(state.labor_report[job]) == int(plan.assign[job])
		_check(agrees, "engine allocation agrees with plan despite its fixed labor order")
	var sowing := _state()
	sowing.week = 3
	sowing.pop = 20
	sowing.orders = ["B13"]
	CabinetRules.setup(sowing)
	var sow_plan := CabinetRules.set_focus(sowing, content, "build")
	_check(sow_plan.farm == 11 and sow_plan.assign.build == 0 and sow_plan.assign.gather == 0 and sow_plan.idle == 0, "agriculture keeps absolute priority in low-population sowing")
	WeekSim.process_week(sowing, content)
	_check(sowing.labor_report.farm == 11 and sowing.labor_report.build == 0, "real sowing workers are never diverted to construction")


func _test_supply() -> void:
	var state := _state()
	state.week = 40
	state.facilities.B25 = 1
	state.facilities.B14 = 1
	state.facilities.B27 = 1
	state.public.wood = 0.0
	CabinetRules.setup(state)
	var plan := CabinetRules.set_focus(state, content, "winter")
	_check(plan.assign.gather == 0 and plan.assign.garden == 0, "unproductive winter food jobs are not staffed")
	_check(plan.assign.logging + plan.assign.fuel <= 4 and plan.assign.logging > 0 and plan.assign.fuel > 0, "logging and fuel share mill capacity and both get workers")
	WeekSim.process_week(state, content)
	var fuel_made := 0.0
	for entry in state.ledger:
		if entry.asset == "fuel" and entry.src == "fuel": fuel_made += entry.qty
	_check(fuel_made > 0 and state.public.wood > 0 and state.public.stone > 20, "real logging supplies same-week fuel while quarry produces stone")
	var spring := _state()
	spring.facilities.B14 = 1
	spring.facilities.B25 = 1
	CabinetRules.setup(spring)
	CabinetRules.reassign(spring, content)
	WeekSim.process_week(spring, content)
	var sources := []
	for entry in spring.ledger:
		if entry.qty > 0: sources.append(entry.src)
	_check("gather" in sources and "garden" in sources and "logging" in sources, "balanced spring policy runs built food and material facilities")
	var bare := _state()
	bare.week = 40
	bare.facilities.B25 = 1
	bare.facilities.B27 = 1
	bare.public.wood = 0
	bare.public.tools = 0
	CabinetRules.setup(bare)
	plan = CabinetRules.set_focus(bare, content, "winter")
	_check(plan.assign.logging == 0 and plan.assign.quarry == 0 and plan.assign.fuel == 0, "no tools or wood means no empty production shifts")
	bare.public.wood = 12
	plan = CabinetRules.reassign(bare, content)
	_check(plan.assign.fuel == 4 and plan.assign.logging == 0, "stored wood can become fuel without tools")
	bare.bonuses.winter_gather = .25
	plan = CabinetRules.reassign(bare, content)
	_check(plan.assign.gather == 8, "winter gathering perk enables useful gathering")


func _test_materials_and_atomic_failure() -> void:
	var state := _state()
	state.facilities.B25 = 1
	state.public.tools = 1
	state.orders = ["B13"]
	CabinetRules.setup(state)
	var plan := CabinetRules.reassign(state, content)
	_check(plan.assign.build == 8 and plan.assign.logging == 0 and state.public.tools == 1, "construction-reserved tools are excluded from production without spending them early")
	state.public.money = 0
	state.assign.build = 7
	var before := state.duplicate(true)
	plan = CabinetRules.reassign(state, content)
	_check(plan.blocked and not plan.errors.is_empty() and state == before, "unaffordable queue leaves all live state unchanged")
	plan = CabinetRules.set_focus(state, content, "winter")
	_check(plan.blocked and state == before, "rejected focus change rolls back its selection as well")
	state.status = "finalized"
	before = state.duplicate(true)
	plan = CabinetRules.reassign(state, content)
	_check(plan.blocked and state == before, "finalized run cannot change assignments")
