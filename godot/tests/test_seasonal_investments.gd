extends "res://tests/test_crisis_director.gd"
## Real economy and isolated saves only; never reads the running game's profile.


func _init() -> void:
	content = Content.load_all()
	_test_support_data()
	_test_support_lifecycle()
	_test_support_economy()
	_test_support_saves()
	_test_support_years()
	print("SEASONAL INVESTMENTS: %d checks, %d failures" % [assertions,failures])
	quit(1 if failures else 0)


func _supported(seed_value: int = 61427) -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config["seasonal_support"] = true
	config["escalation"] = true
	config["village_relics"] = true
	config["difficulty"] = 0
	game.start_run(seed_value,"settler",config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _opening(season: int) -> GameSession:
	var game := _supported()
	_clear(game)
	game.state.week = SeasonalInvestments.OPEN_WEEKS[season]-1
	for key in game.state.public: game.state.public[key] = 10000
	game.state.resident.food = 1000.0
	var report := game.advance()
	_check(report.advanced and SeasonalInvestments.overview(game.state,content).offer.size() == 3,"actual week opens three optional supports for season %d" % season)
	_clear(game)
	return game


func _economic_setup(game: GameSession) -> void:
	var s := game.state
	s.pop = 200
	s.birth_rate = 0.0
	s.death_rate = 0.0
	s.facilities = {"B01":5,"B06":3,"B13":2,"B14":1,"B17":1,"B22":1,"B25":1,"B27":1}
	s.assign = {"gather":8,"build":0,"logging":4,"quarry":4,"garden":4,"fuel":0,"milling":0}
	s.plots_sown = 2
	s.sow_f_sum = 4.0
	s.resident.food = 1500.0
	s.public.food = 3000.0
	s.public.money = 100000
	s.public.wood = 500.0
	s.public.stone = 500.0
	s.public.tools = 100.0
	s.public.fuel = 1000.0
	s.orders = []
	s.projects = []
	s.realm.threat = 10.0
	RealmRules.refresh(s,content)


func _flow(state: Dictionary, source: String, asset: String, start: int) -> float:
	var amount := 0.0
	for entry in state.ledger.slice(start):
		if entry.src == source and entry.asset == asset: amount += float(entry.qty)
	return amount


func _test_support_data() -> void:
	_check(Content.validate(content).is_empty(),"combined content validator accepts support and difficulty data")
	_check(content.seasonal_support.definitions.size() == 12,"exactly twelve distinct seasonal supports")
	for season in 4: _check(SeasonalInvestments._ids(content,season).size() == 3,"three definitions per season")
	for kind in ["unknown_mod","negative_cost","bad_season","missing_effect"]:
		var data: Dictionary = content.seasonal_support.duplicate(true)
		match kind:
			"unknown_mod": data.definitions.SS01.mods = {"fake":1.2}
			"negative_cost": data.definitions.SS01.cost.food = -1
			"bad_season": data.definitions.SS01.season = 9
			"missing_effect": data.definitions.SS01.mods = {}
		_check(not SeasonalInvestments.data_errors(data).is_empty(),"invalid seasonal definition rejected: "+kind)
	var old := _new()
	var before: Dictionary = old.state.duplicate(true)
	_check(not SeasonalInvestments.setup(old.state,content,{}) and old.state == before,"absent opt-in preserves old state exactly")
	_check(SeasonalInvestments.valid(old.state,content) and SeasonalInvestments.bonuses(old.state,content).mods.is_empty(),"old saves have no new effect")


func _test_support_lifecycle() -> void:
	for season in 4:
		var game := _opening(season)
		var snapshot := game.state.duplicate(true)
		for repeat in 5:
			var view := SeasonalInvestments.overview(game.state,content)
			view.offer[0].cost.money = 99999
		_check(game.state == snapshot,"viewing offers cannot alter economy or RNG")
		_check(SeasonalInvestments.setup(game.state,content,{"seasonal_support":true}) and game.state == snapshot,"setup cannot reset open or used offers")
		var id := str(game.state.seasonal_support.offer.ids[0])
		var cost: Dictionary = content.seasonal_support.definitions[id].cost
		var ledger_start: int = game.state.ledger.size()
		_check(game.choose_support(id) == "","choose supported option")
		for key in cost:
			_check(is_equal_approx(float(snapshot.public[key])-float(game.state.public[key]),float(cost[key])),"choice pays full declared cost once")
			_check(_flow(game.state,"support:"+id,str(key),ledger_start) == -float(cost[key]),"support cost is recorded in the actual ledger")
		_check(TurnReceipt.source_label("support:"+id).contains(str(content.seasonal_support.definitions[id].name)),"ledger label names the selected support")
		snapshot = game.state.duplicate(true)
		_check(game.choose_support(id) != "" and game.decline_support() != "" and game.state == snapshot,"cannot buy twice or turn paid decision into a skip")
		game.state.week = (season+1)*13
		_clear(game)
		game.state.realm.sanctuary.offer = []
		var report := game.advance()
		_check(report.advanced and game.state.seasonal_support.active.is_empty() and SeasonalInvestments.bonuses(game.state,content).mods.is_empty(),"support expires after its actual last week")
		snapshot = game.state.duplicate(true)
		SeasonalInvestments.after_week(snapshot,game.state,content,report)
		_check(game.state == snapshot,"repeated post-week processing cannot repeat or reopen support")
		_check(SaveStore.valid(game.bundle()),"expired support remains saveable even at final settlement")
	var unanswered := _opening(0)
	var first_report := unanswered.advance()
	_check(first_report.advanced and not unanswered.state.seasonal_support.offer.is_empty(),"unanswered support never blocks weekly progress")
	unanswered.state.week = 13
	_clear(unanswered)
	unanswered.advance()
	_check(unanswered.state.seasonal_support.offer.is_empty(),"unanswered offer expires at the season boundary")
	var skipped := _opening(0)
	var stock: Dictionary = skipped.state.public.duplicate(true)
	_check(skipped.decline_support() == "" and skipped.state.public == stock and skipped.state.seasonal_support.decisions[0].id == "","decline costs nothing and saves the seasonal token")
	var harvest := _opening(2)
	harvest.state.week = 37
	var before := harvest.state.duplicate(true)
	_check(harvest.choose_support("SS07") != "" and harvest.state == before,"expired harvest effect is never sold after week 36")
	var reserved := _opening(0)
	reserved.state.orders = ["B22"]
	var held := RealmRules.held(reserved.state,content)
	reserved.state.public.money = int(held.money)
	reserved.state.public.tools = float(held.tools)
	before = reserved.state.duplicate(true)
	_check(reserved.choose_support("SS02") != "" and reserved.state == before,"support cannot spend construction money or materials")


func _test_support_economy() -> void:
	for id in content.seasonal_support.definitions:
		var definition: Dictionary = content.seasonal_support.definitions[id]
		var game := _opening(int(definition.season))
		_economic_setup(game)
		_check(game.choose_support(id) == "","prepare economic A/B for "+str(id))
		# Both copies have already paid the same support cost; only the active effect differs.
		var supported: Dictionary = game.state.duplicate(true)
		var control: Dictionary = supported.duplicate(true)
		control.erase("seasonal_support")
		RealmRules.refresh(control,content)
		if id == "SS03":
			supported.orders = ["B22"]
			control.orders = ["B22"]
		var start: int = supported.ledger.size()
		var a := WeekSim.process_week(supported,content)
		var b := WeekSim.process_week(control,content)
		_check(a.advanced and b.advanced,"both real weekly economies advance")
		match id:
			"SS01": _check(_flow(supported,"gather","food",start) > _flow(control,"gather","food",start),"worker meals increase actual gathering")
			"SS02": _check(_flow(supported,"logging","tools",start) > _flow(control,"logging","tools",start) and _flow(supported,"maintenance","money",start) > _flow(control,"maintenance","money",start),"maintenance support reduces actual inputs and paid upkeep")
			"SS03": _check(supported.projects[0].work_total < control.projects[0].work_total and _flow(supported,"wages","money",start) > _flow(control,"wages","money",start),"construction support lowers new work requirement and actual payroll")
			"SS04": _check(_flow(supported,"garden","food",start) > _flow(control,"garden","food",start),"irrigation increases actual vegetable output")
			"SS05", "SS08": _check(_flow(supported,"logging","wood",start) > _flow(control,"logging","wood",start),"logging support increases actual lumber output")
			"SS06", "SS09": _check(_flow(supported,"spoil","food",start) > _flow(control,"spoil","food",start),"storage support reduces actual food loss")
			"SS07": _check(_flow(supported,"harvest","food",start) > _flow(control,"harvest","food",start),"autumn meals increase actual remaining harvest")
			"SS10":
				var ga := GameSession.new(content)
				var gb := GameSession.new(content)
				ga.state = supported
				gb.state = control
				ga._wellbeing()
				gb._wellbeing()
				_check(ga.state.health > gb.state.health and ga.state.mood > gb.state.mood,"shared meals change actual weekly health and morale convergence")
			"SS11": _check(_flow(supported,"heating","fuel",start) > _flow(control,"heating","fuel",start),"heating maintenance reduces actual winter fuel consumption")
			"SS12":
				RealmRules.after_week(supported,content,a)
				RealmRules.after_week(control,content,b)
				_check(supported.realm.threat < control.realm.threat and supported.security > control.security,"patrol supplies reduce actual threat growth and raise security convergence")
		_check(TurnReceipt.valid(TurnReceipt.build(game.state,supported,a)),"supported weekly changes form a valid actual receipt")
	var expiry := _opening(0)
	_economic_setup(expiry)
	expiry.choose_support("SS01")
	expiry.state.week = 13
	var trial: Dictionary = expiry.state.duplicate(true)
	WeekSim.process_week(trial,content)
	var second_start: int = trial.ledger.size()
	var plain: Dictionary = trial.duplicate(true)
	plain.erase("seasonal_support")
	RealmRules.refresh(plain,content)
	WeekSim.process_week(trial,content)
	WeekSim.process_week(plain,content)
	_check(is_equal_approx(_flow(trial,"gather","food",second_start),_flow(plain,"gather","food",second_start)),"multiweek economic forecast drops expired support without needing UI or session processing")


func _test_support_saves() -> void:
	var game := _opening(1)
	game.choose_support("SS04")
	_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"native and JSON support states validate")
	var store := SaveStore.new("res://tests/output/support_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "","support choice writes through real isolated SaveStore")
	var loaded := store.read()
	_check(loaded.ok and loaded.bundle.state.seasonal_support == SaveStore._normalize(game.state.seasonal_support),"paid cost and expiry survive actual normalized reload")
	_check(loaded.ok and store.write(loaded.bundle) == "","normalized support state can be saved again without repaying")
	for kind in ["repeat_season","unknown_id","false_cost","extended_duration","future_week","wrong_offer"]:
		var broken := game.bundle()
		match kind:
			"repeat_season": broken.state.seasonal_support.decisions.append(broken.state.seasonal_support.decisions[0].duplicate(true))
			"unknown_id": broken.state.seasonal_support.active.id = "bogus"
			"false_cost": broken.state.seasonal_support.decisions[0].cost.money = 0
			"extended_duration": broken.state.seasonal_support.active.until = 52
			"future_week": broken.state.seasonal_support.last_week = 52
			"wrong_offer": broken.state.seasonal_support.offer = {"season":1,"opened_week":20,"expires":26,"ids":["SS01","SS02","SS03"]}
		_check(not SaveStore.valid(broken),"corrupt seasonal save rejected: "+kind)


func _resolve_smart(game: GameSession) -> void:
	super._resolve_smart(game)
	var view := SeasonalInvestments.overview(game.state,content)
	if view.offer.is_empty(): return
	for row in view.offer:
		if row.error == "" and (not row.cost.has("food") or WeekSim.food_weeks(game.state) > 8):
			_check(game.choose_support(str(row.id)) == "","real operator chooses affordable seasonal support")
			return
	game.decline_support()


func _test_support_years() -> void:
	for seed_value in [61427,27]:
		var game := _supported(seed_value)
		var outcome := _play(game,true)
		print("SUPPORT RUN seed=%d week=%d success=%s choices=%d gold=%d" % [seed_value,outcome.week,outcome.success,game.state.seasonal_support.decisions.size(),outcome.money])
		_check(game.state.status == "finalized" and game.state.seasonal_support.decisions.size() == 4,"real yearly play processes every optional seasonal offer once")
		_check(game.state.seasonal_support.offer.is_empty() and game.state.seasonal_support.active.is_empty(),"finalized year leaves no pending support or effect")
		_check(SaveStore.valid(game.bundle()),"real yearly support result is saveable")
