extends SceneTree

var content: Dictionary
var checks := 0
var failures := 0


func _init() -> void:
	content = Content.load_all()
	if not content.has("workcrew"): content.workcrew = JSON.parse_string(FileAccess.get_file_as_string("res://content/workcrew.json"))
	_test_opt_in_and_validation()
	_test_first_project_choices()
	_test_real_allocation_and_preview()
	_test_farm_and_material_limits()
	_test_selection_atomicity()
	_test_integrated_save()
	for region in ["forest","river","highland"]:
		_smoke(region,false)
		_smoke(region,true)
	print("WORKCREW RULES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("WORKCREW FAIL: ",label)


func _base() -> Dictionary:
	var state := RunState.new_run(content.charters.C01,9876)
	WorkcrewRules.setup(state,{"campaign":true,"workcrew":true})
	return state


func _test_opt_in_and_validation() -> void:
	var state := RunState.new_run(content.charters.C01,9876)
	var before := state.duplicate(true)
	_check(WorkcrewRules.valid(state) and not WorkcrewRules.enabled(state),"missing new fields preserve valid old saves")
	_check(not WorkcrewRules.setup(state,{"campaign":true}) and state == before,"old campaign flag alone cannot opt into new labor limits")
	_check(not WorkcrewRules.setup(state,{"workcrew":true}) and state == before,"workcrew requires explicit new campaign flag")
	_check(not WorkcrewRules.allocate(state,content).enabled and state == before,"disabled allocation is a full no-op")
	_check(WorkcrewRules.choices(state,content).is_empty() and state == before,"disabled preview creates no state")
	_check(WorkcrewRules.select(state,content,"food") != "" and state == before,"selection never silently converts old saves")
	_check(WorkcrewRules.setup(state,{"campaign":true,"workcrew":true}) and state.workcrew.policy == "balanced","new campaign starts on balanced policy")
	before = state.duplicate(true)
	_check(WorkcrewRules.setup(state,{"campaign":true,"workcrew":true}) and state == before,"repeated setup changes nothing")
	for value in [[],{"enabled":1,"version":1,"policy":"balanced"},{"enabled":true,"version":1.5,"policy":"balanced"},{"enabled":true,"version":1,"policy":"unknown"}]:
		var broken := state.duplicate(true)
		broken.workcrew = value
		_check(not WorkcrewRules.valid(broken),"reject malformed workcrew snapshot " + str(value))
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(state))
	_check(WorkcrewRules.valid(loaded),"JSON numeric versions remain valid")
	state.workcrew.enabled = false
	before = state.duplicate(true)
	_check(not WorkcrewRules.setup(state,{"campaign":true,"workcrew":true}) and state == before,"explicitly disabled old crew is not overwritten")


func _test_first_project_choices() -> void:
	var state := _base()
	state.orders = ["B13","B13"]
	var before := state.duplicate(true)
	var choices := WorkcrewRules.choices(state,content)
	_check(state == before and choices.size() == 4,"first comparison is read-only and has four real policies")
	var by_id := {}
	for choice in choices: by_id[choice.id] = choice
	_check(by_id.balanced.work == 8 and by_id.balanced.completed_count == 1,"balanced starts one farm per week")
	_check(by_id.build.work == 16 and by_id.build.completed_count == 2,"construction focus completes both initial farms in one actual week")
	_check(by_id.food.work == 4 and by_id.food.completed_count == 0,"food focus postpones the first farm completion")
	_check(by_id.food.production.food > by_id.balanced.production.food and by_id.balanced.production.food > by_id.build.production.food,"initial policies make a measurable food versus construction tradeoff")
	_check(not by_id.winter.available and "벌목소" in by_id.winter.error,"firewood cannot imply production before its building exists")
	for index in 2:
		WorkcrewRules.allocate(state,content)
		WeekSim.process_week(state,content)
	_check(state.week == 3 and state.facilities.B13 == 6 and state.projects.is_empty(),"default tutorial still completes both farms before sowing")
	WorkcrewRules.allocate(state,content)
	WeekSim.process_week(state,content)
	_check(state.plots_sown == 6,"default tutorial actually sows all six farms")
	state = before.duplicate(true)
	WorkcrewRules.select(state,content,"food")
	for index in 3:
		WorkcrewRules.allocate(state,content)
		WeekSim.process_week(state,content)
	_check(state.facilities.B13 == 5 and state.plots_sown == 5,"sustained food priority really delays the second farm beyond first sowing")


func _test_real_allocation_and_preview() -> void:
	var state := _base()
	state.week = 10
	state.facilities.B13 = 6
	state.facilities.B17 = 2
	state.facilities.B14 = 1
	state.facilities.B25 = 1
	state.orders = ["B22"]
	var before := state.duplicate(true)
	var definitions_before := content.duplicate(true)
	var choices := WorkcrewRules.choices(state,content)
	for choice in choices:
		var trial := state.duplicate(true)
		_check(WorkcrewRules.select(trial,content,choice.id) == "","offered midgame policy is executable " + choice.id)
		var allocation := WorkcrewRules.allocate(trial,content)
		_check(allocation.budget == 20 and allocation.farm == 6 and allocation.reserved == 18,"twenty-person public crew preserves agriculture and resident employment")
		_check(allocation.crew + allocation.idle == allocation.budget,"crew accounting conserves the actual budget")
		var report := WeekSim.process_week(trial,content)
		_check(report.advanced,"preview counterpart actually progresses")
		for job in WorkcrewRules.JOBS:
			_check(trial.labor_report[job] == allocation.assign[job] and choice.workers[job] == trial.labor_report[job],"engine and preview use the exact requested workers " + choice.id + "/" + job)
		for asset in choice.deltas:
			var actual: float = WeekSim.total_food(trial)-WeekSim.total_food(state) if asset == "food" else trial.public[asset]-state.public[asset]
			_check(is_equal_approx(actual,choice.deltas[asset]),"preview matches actual resource movement " + choice.id + "/" + asset)
	_check(state == before and content == definitions_before,"all comparisons preserve source state, definitions, ledger and RNG")
	var balanced: Dictionary = choices[0]
	var food: Dictionary = choices[1]
	var building: Dictionary = choices[2]
	var winter: Dictionary = choices[3]
	_check(food.production.food > balanced.production.food and building.work > balanced.work,"mature facilities preserve food versus time choices")
	_check(balanced.production.wood > winter.production.wood and winter.production.fuel > balanced.production.fuel,"same sawmill turns labor between timber and firewood")
	_check(winter.deltas.wood < 0 and winter.production.fuel > 0,"firewood consumes real wood instead of adding a free multiplier")


func _test_farm_and_material_limits() -> void:
	var state := _base()
	state.week = 3
	state.pop = 20
	state.orders = ["B13"]
	state.workcrew.policy = "build"
	var allocation := WorkcrewRules.allocate(state,content)
	_check(allocation.farm == 11 and allocation.budget == 0 and allocation.crew == 0,"sowing keeps all scarce labor ahead of the workcrew")
	WeekSim.process_week(state,content)
	_check(state.labor_report.farm == 11 and state.labor_report.build == 0,"engine confirms farm priority even under construction focus")
	state = _base()
	state.week = 40
	state.facilities.B25 = 1
	state.facilities.B14 = 1
	state.facilities.B27 = 1
	state.public.wood = 0
	state.public.tools = 0
	state.workcrew.policy = "winter"
	allocation = WorkcrewRules.allocate(state,content)
	_check(allocation.assign.fuel == 0 and allocation.assign.logging == 0 and allocation.assign.quarry == 0,"no materials means no fabricated timber, firewood or quarry work")
	_check(allocation.assign.gather == 0 and allocation.assign.garden == 0,"ordinary winter gathering and vegetable jobs remain unavailable")
	state.public.wood = 12
	allocation = WorkcrewRules.allocate(state,content)
	_check(allocation.assign.fuel == 4 and allocation.assign.logging == 0,"stored wood can become firewood without logging tools")
	WeekSim.process_week(state,content)
	_check(state.public.wood == 0 and state.public.fuel > 0,"real engine consumes the twelve wood and heats residents")
	state = _base()
	state.facilities.B25 = 1
	state.public.wood = 0
	state.workcrew.policy = "winter"
	allocation = WorkcrewRules.allocate(state,content)
	_check(allocation.assign.logging == 2 and allocation.assign.fuel == 2,"scarce timber splits one sawmill between replenishment and conversion")
	WeekSim.process_week(state,content)
	_check(state.public.fuel == 12 and state.public.wood >= 0,"same-week logging supplies exactly the actual partial firewood shift")


func _test_selection_atomicity() -> void:
	var state := _base()
	state.orders = ["B13"]
	state.public.wood = 0
	var before := state.duplicate(true)
	_check(WorkcrewRules.allocate(state,content).blocked and state == before,"invalid construction orders preserve original allocation and state")
	_check(WorkcrewRules.select(state,content,"food") != "" and state == before,"failed selection rolls back policy and workers together")
	_check(WorkcrewRules.select(state,content,"missing") != "" and state == before,"unknown policy changes nothing")
	var choices := WorkcrewRules.choices(state,content)
	_check(choices.all(func(choice): return not choice.available) and state == before,"blocked comparisons never purchase or remove queued work")
	state = _base()
	before = state.duplicate(true)
	_check(WorkcrewRules.select(state,content,"build") != "" and state == before,"construction focus without a project is explained instead of silently selecting")
	state.orders = ["B13"]
	before = state.duplicate(true)
	_check(WorkcrewRules.select(state,content,"build") == "","real queued project allows construction focus")
	before.workcrew.policy = "build"
	before.assign = state.assign.duplicate(true)
	_check(state == before,"successful selection changes only policy and labor request")


func _game(region: String = "forest") -> GameSession:
	var game := GameSession.new(content)
	game.start_run(61427,"settler",{"region":region,"candidate":0,"relics":["seeds","axe"],"tutorial":false,"cabinet":true,"campaign":true,"workcrew":true})
	return game


func _resolve(game: GameSession) -> bool:
	if not game.state.perk_offer.is_empty() and not game.choose_perk(str(game.state.perk_offer[0])): return false
	if game.state.active_event != "":
		var event: Dictionary = content.events[game.state.active_event]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if option.get("cost",{}).is_empty() and not option.has("requires_housing"):
				if game.choose_event(index) != "": return false
				break
	if not game.state.contract_offer.is_empty() and game.choose_contract("skip") != "": return false
	return game.state.active_event == "" and game.state.perk_offer.is_empty()


func _test_integrated_save() -> void:
	var game := _game()
	_check(WorkcrewRules.enabled(game.state),"real new run opts into workcrew rules")
	if not WorkcrewRules.enabled(game.state): return
	_check(CabinetActions.start_project(game,"B13") == "","integrated project uses new routed labor planning")
	_check(CabinetRules.reassign(game.state,content).get("budget",-1) == 20,"CabinetRules routes to new public crew allocation")
	_check(WorkcrewRules.select(game.state,content,"build") == "","integrated player can accelerate first construction")
	_check(_resolve(game),"resolve actual first perk")
	var before := game.state.duplicate(true)
	var choices := WorkcrewRules.choices(game.state,content)
	_check(game.state == before,"integrated comparison cannot apply advisor, events, seasonal rewards or meta progression")
	var preview: Dictionary = choices[2]
	var report := game.advance()
	_check(report.advanced and game.state.facilities.B13 == 6 and game.state.week == 2,"actual advance honors accelerated crew rather than overwriting it with legacy allocation")
	_check(game.state.last_receipt.development.work_done == preview.work,"receipt reports the same actual work as selected preview")
	var store := SaveStore.new("res://tests/output/workcrew_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "","new workcrew state passes actual save validation")
	var loaded := store.read()
	_check(loaded.ok,"new workcrew run can be read")
	if not loaded.ok: return
	_check(WorkcrewRules.valid(loaded.bundle.state) and SaveStore.valid(loaded.bundle),"normalized workcrew snapshot remains valid")
	_check(loaded.bundle.state.workcrew.policy == "build","load preserves the selected policy")
	for asset in game.state.public:
		_check(is_equal_approx(float(loaded.bundle.state.public[asset]),float(game.state.public[asset])),"load preserves resource quantity without replaying work or costs " + asset)


func _smoke(region: String, adaptive: bool) -> void:
	var game := _game(region)
	if not WorkcrewRules.enabled(game.state): return
	CabinetActions.set_advisor(game,"CH03")
	var weeks := 0
	var buys := 0
	var modes := {}
	var lowest := 99.0
	while game.state.status == "active" and weeks < 53:
		_check(_resolve(game),"smoke decisions resolve without fabricated outcomes")
		if game.state.orders.is_empty() and game.state.projects.is_empty():
			for target in [{"id":"B13","count":6},{"id":"B22","count":1},{"id":"B25","count":1},{"id":"B17","count":2},{"id":"B14","count":1}]:
				if int(game.state.facilities.get(target.id,0)) >= target.count: continue
				if CabinetActions.offer(game,target.id).error == "": CabinetActions.start_project(game,target.id)
				break
		var policy := "balanced"
		if adaptive and int(game.state.week) > 2:
			var winter_target := float(game.state.pop) * .1 * 13 * (1.5 if game.state.trial == "frost" else 1.0)
			if int(game.state.week) >= 27 and game.state.public.fuel < winter_target and game.state.facilities.get("B25",0) > 0:
				policy = "winter"
			elif not game.state.orders.is_empty() or not game.state.projects.is_empty():
				policy = "food" if WeekSim.food_weeks(game.state) < 8 else "build"
			elif game.state.public.wood < 40 and game.state.facilities.get("B25",0) > 0:
				policy = "balanced"
			else:
				policy = "food"
		if WorkcrewRules.select(game.state,content,policy) != "": WorkcrewRules.select(game.state,content,"balanced")
		modes[game.state.workcrew.policy] = int(modes.get(game.state.workcrew.policy,0)) + 1
		var need := ""
		if WeekSim.food_weeks(game.state) < 3: need = "food"
		elif game.state.public.tools < 1: need = "tools"
		elif game.state.public.wood < 16 and game.state.facilities.get("B25",0) == 0: need = "wood"
		if need != "" and not game.state.shipments.any(func(shipment): return shipment.buy and shipment.asset == need):
			if CabinetActions.buy_supply(game,need) == "": buys += 1
		var report := game.advance()
		_check(report.advanced,"real workcrew campaign advances " + region + " week=" + str(game.state.week))
		if not report.advanced: break
		weeks += 1
		_check(WorkcrewRules.valid(game.state) and SaveStore.valid(game.bundle()),"real workcrew turn remains saveable")
		lowest = minf(lowest,WeekSim.food_weeks(game.state))
	_check(game.state.status == "finalized" and weeks <= 52,"policy reaches a natural ending without deadlock")
	var missed: Array[String] = []
	for goal in game.state.goals.values():
		if not goal.done: missed.append(str(goal.title))
	print("WORKCREW SMOKE ",region," adaptive=",adaptive," weeks=",weeks," win=",game.state.result.get("success",false)," stock=",snappedf(WeekSim.food_weeks(game.state),.1)," min=",snappedf(lowest,.1)," health=",snappedf(game.state.health,.1)," season_points=",game.state.campaign.points," buys=",buys," modes=",modes," missed=",missed)
