extends SceneTree
## 출발 환경의 공개·재현성·스냅샷 검증·실제 경제 배율·52주 비교.

var checks := 0
var failures := 0
var content: Dictionary
var combinations := {}
const CONFIG := {"region":"forest", "candidate":0, "relics":["seeds","axe"], "tutorial":false,
	"cabinet":true,"campaign":true,"workcrew":true,"realm":true,"modifiers":true}
const BUILD_ORDER := ["B13","B22","B17","B25","B16","B14","B67","B01","B27","B49","B57","B14","B19","B33","B21","B11","B63","B71","B26","B20","B52","B59"]


func _init() -> void:
	content = Content.load_all()
	_test_preview()
	_test_setup_and_neutrality()
	_test_validation()
	_test_economy()
	_test_save()
	_test_runs()
	print("EXPEDITION MODIFIERS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("EXPEDITION MODIFIERS FAIL: ",message)


func _new(run_seed: int = 61427, modifiers: bool = true, region: String = "forest") -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config.modifiers = modifiers
	config.region = region
	game.start_run(run_seed,"settler",config)
	return game


func _seed_for(id: String) -> int:
	for seed_value in combinations.values():
		for row in ExpeditionModifiers.preview(content,int(seed_value)):
			if row.id == id: return int(seed_value)
	return -1


func _test_preview() -> void:
	var definitions: Dictionary = content.duplicate(true)
	var before := _new().state.duplicate(true)
	for seed_value in 128:
		var first := ExpeditionModifiers.preview(content,seed_value)
		_check(first.size() == 2,"two visible conditions for seed %d" % seed_value)
		if first.size() != 2: continue
		_check(first[0].kind == "opportunity" and first[1].kind == "constraint" and first[0].id != first[1].id,"one opportunity and one constraint for seed %d" % seed_value)
		_check(first == ExpeditionModifiers.preview(content,seed_value),"repeatable independent draw %d" % seed_value)
		var key: String = first[0].id + "+" + first[1].id
		if not combinations.has(key): combinations[key] = seed_value
		first[0].bonuses.clear()
		_check(not ExpeditionModifiers.preview(content,seed_value)[0].bonuses.is_empty(),"caller cannot mutate definitions through preview")
	_check(combinations.size() == 9,"all nine opportunity/constraint combinations occur")
	_check(content == definitions and _new().state == before,"preview never changes content or another random stream")
	_check(ExpeditionModifiers.preview({},1).is_empty(),"missing definitions do not generate invented effects")


func _test_setup_and_neutrality() -> void:
	var plain := _new(61427,false)
	var before: Dictionary = plain.state.duplicate(true)
	_check(not ExpeditionModifiers.setup(plain.state,content,{"realm":true,"modifiers":false}) and plain.state == before,"explicit false leaves all old state untouched")
	_check(not ExpeditionModifiers.setup(plain.state,content,{"realm":true}) and plain.state == before,"missing flag leaves all old state untouched")
	_check(not ExpeditionModifiers.setup(plain.state,content,{"modifiers":true}) and plain.state == before,"modifier flag cannot migrate a non-realm setup")
	_check(ExpeditionModifiers.valid(plain.state,content) and ExpeditionModifiers.bonuses(plain.state).is_empty(),"old save without field is valid and neutral")
	var config := CONFIG.duplicate(true)
	config.erase("modifiers")
	var legacy := GameSession.new(content)
	legacy.start_run(61427,"settler",config)
	_check(legacy.state == plain.state,"missing and explicit false configurations give identical whole states")
	_check(ExpeditionModifiers.setup(plain.state,content,CONFIG),"explicit setup stores the environment")
	before["expedition_modifiers"] = plain.state.expedition_modifiers.duplicate(true)
	_check(plain.state == before,"setup only stores a snapshot, without changing resources, RNG or base bonuses")
	RealmRules.refresh(plain.state,content)
	before = plain.state.duplicate(true)
	for attempt in 5:
		_check(ExpeditionModifiers.setup(plain.state,content,CONFIG),"repeat setup is accepted")
		RealmRules.refresh(plain.state,content)
	_check(plain.state == before,"repeat setup and refresh never compound environment effects")
	var integrated := _new()
	_check(integrated.state == plain.state,"real GameSession setup matches the explicit one-time environment setup")
	_check(ExpeditionModifiers.overview(integrated.state,content) == ExpeditionModifiers.preview(content,int(integrated.state.seed)),"running conditions exactly match the pre-run display")
	var effects := ExpeditionModifiers.bonuses(integrated.state)
	effects.clear()
	_check(not ExpeditionModifiers.bonuses(integrated.state).is_empty(),"bonus query returns a defensive copy")
	_check(SaveStore.valid(integrated.bundle()),"real integrated state passes SaveStore validation")
	var offer := CabinetActions.offer(integrated,"B13")
	_check(offer.eta == 2 and offer.count == 2,"starting environment preserves the two-week tutorial farm plan")


func _test_validation() -> void:
	var state := _new().state
	_check(ExpeditionModifiers.valid(state,content),"native snapshot is valid")
	_check(ExpeditionModifiers.valid(JSON.parse_string(JSON.stringify(state)),content),"JSON numeric types remain valid")
	var malformed: Array = [null,[],1,"invalid",{}, {"enabled":true}]
	for value in malformed:
		var broken: Dictionary = state.duplicate(true)
		broken.expedition_modifiers = value
		_check(not ExpeditionModifiers.valid(broken,content),"invalid snapshot type/shape rejected: " + str(value))
	for value in [false,"true",1,null]:
		var broken: Dictionary = state.duplicate(true)
		broken.expedition_modifiers.enabled = value
		_check(not ExpeditionModifiers.valid(broken,content),"invalid activation flag rejected")
	for value in [-1,0,1.5,2,INF,NAN,"1"]:
		var broken: Dictionary = state.duplicate(true)
		broken.expedition_modifiers.version = value
		_check(not ExpeditionModifiers.valid(broken,content),"invalid version rejected")
	for value in [[],["missing","lean_soil"],[state.expedition_modifiers.ids[0],state.expedition_modifiers.ids[0]],[state.expedition_modifiers.ids[1],state.expedition_modifiers.ids[0]],1,"wild_food"]:
		var broken: Dictionary = state.duplicate(true)
		broken.expedition_modifiers.ids = value
		_check(not ExpeditionModifiers.valid(broken,content),"unknown/duplicate/reversed or malformed identity rejected")
	var effect: String = str(state.expedition_modifiers.bonuses.keys()[0])
	for value in [-1,0,0.1,2.0,INF,-INF,NAN,"1.2",true,[],{}]:
		var broken: Dictionary = state.duplicate(true)
		broken.expedition_modifiers.bonuses[effect] = value
		_check(not ExpeditionModifiers.valid(broken,content),"invalid numeric multiplier rejected")
	for value in [null,[],"invalid",{}, {"cheat":1.2}]:
		var broken: Dictionary = state.duplicate(true)
		broken.expedition_modifiers.bonuses = value
		_check(not ExpeditionModifiers.valid(broken,content),"malformed effect map rejected")
	var changed: Dictionary = state.duplicate(true)
	changed.expedition_modifiers.bonuses[effect] += 0.01
	_check(not ExpeditionModifiers.valid(changed,content),"plausible but incorrect snapshot multiplier rejected")
	var bundle := _new().bundle()
	bundle.state.expedition_modifiers.ids[0] = "missing"
	_check(not SaveStore.valid(bundle),"SaveStore enforces environment validation")


func _source(state: Dictionary, source: String, asset: String) -> float:
	var total := 0.0
	for row in state.ledger:
		if row.src == source and row.asset == asset: total += float(row.qty)
	return total


func _economy_fixture(game: GameSession, condition: String) -> void:
	var s := game.state
	s.active_event = ""
	s.perk_offer = []
	s.ledger = []
	s.week = 10
	s.public.food = 1000.0
	s.resident.food = 1000.0
	s.public.fuel = 1000.0
	s.public.tools = 100.0
	s.facilities.B25 = 1
	# Existing regional/character/perk-like effects must multiply once, not be replaced.
	s.bonuses.gather = 0.77
	s.bonuses.logging = 1.4
	s.bonuses.harvest = 0.63
	s.bonuses.buy = 0.9
	s.bonuses.heating = 1.5
	if condition == "lean_soil":
		s.week = 33
		s.plots_sown = 4
		s.sow_f_sum = 1.0
	elif condition == "long_cold": s.week = 40
	elif condition == "damp_store": s.facilities.B17 = 0
	RealmRules.refresh(s,content)
	CabinetRules.reassign(s,content)


func _test_economy() -> void:
	var expected := {"wild_food":["gather","food",1.2],"old_forest":["logging","wood",1.25],
		"lean_soil":["harvest","food",0.85],"long_cold":["heating","fuel",1.2],"damp_store":["spoil","food",1.35]}
	for id in content.modifiers.definitions:
		var seed_value := _seed_for(id)
		_check(seed_value >= 0,"condition has an actual seed " + id)
		var plain := _new(seed_value,false)
		var altered := _new(seed_value,true)
		_economy_fixture(plain,id)
		_economy_fixture(altered,id)
		_check(plain.state.bonuses == altered.state.bonuses,"environment preserves existing base bonus products " + id)
		for key in ExpeditionModifiers.bonuses(altered.state):
			_check(is_equal_approx(WeekSim.bonus(altered.state,key),WeekSim.bonus(plain.state,key)*float(ExpeditionModifiers.bonuses(altered.state)[key])),"exact bonus stacking " + id + "/" + key)
		if id == "caravan_route":
			var base_goods := int(round(100 * GameSession.RESOURCE_PRICES.tools * 1.1 * WeekSim.bonus(plain.state,"buy")))
			var reduced_goods := int(round(100 * GameSession.RESOURCE_PRICES.tools * 1.1 * WeekSim.bonus(plain.state,"buy") * 0.85))
			_check(altered.trade_quote("tools",100,true)-plain.trade_quote("tools",100,true) == reduced_goods-base_goods,"discount affects actual goods quote while freight remains unchanged")
			_check(altered.trade_quote("wood",40,false) == plain.trade_quote("wood",40,false),"buying condition never inflates sale price")
		_check(WeekSim.process_week(plain.state,content).advanced and WeekSim.process_week(altered.state,content).advanced,"real economic week advances " + id)
		if expected.has(id):
			var rule: Array = expected[id]
			var baseline := _source(plain.state,rule[0],rule[1])
			var actual := _source(altered.state,rule[0],rule[1])
			_check(not is_zero_approx(baseline) and is_equal_approx(actual,baseline*float(rule[2])),"actual ledger effect matches displayed multiplier " + id + " %.4f -> %.4f" % [baseline,actual])
		_check(SaveStore.valid(altered.bundle()),"modified economic week remains saveable " + id)


func _test_save() -> void:
	var game := _new()
	var store := SaveStore.new("res://tests/output/modifiers_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "","environment writes through the actual save store")
	var loaded := store.read()
	_check(loaded.ok,"environment reloads through the actual save store")
	if not loaded.ok: return
	var resumed := GameSession.new(content)
	resumed.state = loaded.bundle.state
	resumed.profile = loaded.bundle.profile
	var before: Dictionary = resumed.state.duplicate(true)
	_check(ExpeditionModifiers.setup(resumed.state,content,CONFIG) and resumed.state == before,"resuming never redraws or reapplies a snapshot")
	RealmRules.refresh(resumed.state,content)
	RealmRules.refresh(game.state,content)
	# SaveStore 정상화는 1.0을 정수 1로 바꾸므로 배율은 숫자로 비교한다.
	_check(_same_effects(resumed.state.realm.mods,game.state.realm.mods) and _same_effects(resumed.state.bonuses,game.state.bonuses),"loaded and uninterrupted rule multipliers match")
	_check(ExpeditionModifiers.overview(resumed.state,content) == ExpeditionModifiers.overview(game.state,content),"loaded conditions still match the pre-run promise")
	_check(store.write(resumed.bundle()) == "","loaded native state can save again")
	for current in [game,resumed]:
		current.choose_perk(str(current.state.perk_offer[0]))
		_check(current.advance().advanced,"saved and uninterrupted sessions both advance")
	for account in ["public","resident"]:
		_check(_same_effects(game.state[account],resumed.state[account]),"actual post-load economy matches uninterrupted play " + account)
	_check(game.state.week == resumed.state.week and game.state.realm.rolls == resumed.state.realm.rolls,"loading preserves week and event random sequence")


func _same_effects(first: Dictionary, second: Dictionary) -> bool:
	if first.size() != second.size(): return false
	for key in first:
		if not second.has(key) or not is_equal_approx(float(first[key]),float(second[key])): return false
	return true


func _resolve(game: GameSession) -> void:
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	if game.state.active_event == "": return
	var s := game.state
	var event: Dictionary = content.events[s.active_event]
	for index in event.options.size():
		var option: Dictionary = event.options[index]
		if game.option_error(option) != "": continue
		if option.has("chance") and RealmRules.chance_of(s,option) < 0.5 and index < event.options.size()-1: continue
		if float(option.get("cost",{}).get("money",0)) > float(s.public.money)*0.4: continue
		if float(option.get("cost",{}).get("food",0)) > 0 and WeekSim.food_weeks(s) < 6: continue
		if event.get("immigration",false) and option.has("requires_housing") and (WeekSim.food_weeks(s) < 9 or int(s.week) > 30): continue
		if game.choose_event(index) == "": return
	for index in event.options.size():
		var option: Dictionary = event.options[index]
		if option.get("cost",{}).is_empty() and not option.has("requires_housing") and game.option_error(option) == "":
			game.choose_event(index)
			return


func _operate(game: GameSession) -> void:
	var s := game.state
	var reserve := 1500 if int(s.week) < 20 else 2500
	if s.trial == "audit": reserve += 1200 if int(s.week) >= 40 else 3200
	if s.orders.size()+s.projects.size() < 2:
		for id in BUILD_ORDER:
			if float(s.public.money)-Constants.GRADE_COST[content.facilities[id].grade].gold*100*(2 if id == "B13" else 1) < reserve: continue
			if id == "B13" and int(s.facilities.get("B13",0)) >= 8: continue
			var count := 2 if id in ["B17","B14"] else 1
			if id != "B13" and int(s.facilities.get(id,0))+s.orders.count(id)+s.projects.filter(func(p):return p.id == id).size() >= count: continue
			if id == "B01" and WeekSim.capacity(s,content,"housing")-s.pop > 14: continue
			if CabinetActions.start_project(game,id) == "": break
	var policy := "build" if not s.orders.is_empty() or not s.projects.is_empty() else "balanced"
	var fuel_goal: float = s.pop*0.1*13*WeekSim.bonus(s,"heating")*1.6
	if int(s.week) >= 22 and int(s.facilities.get("B25",0)) > 0 and s.public.fuel < fuel_goal: policy = "winter"
	if WorkcrewRules.select(s,content,policy) != "": WorkcrewRules.select(s,content,"balanced")
	var food_floor := 7.0 if int(s.week) < 40 else 14.5
	if s.trial == "rot" and int(s.week) >= 34: food_floor = 16.0
	if WeekSim.food_weeks(s) < food_floor and s.shipments.size() < 2 and s.public.money > reserve*0.5: CabinetActions.buy_supply(game,"food")
	if int(s.week) >= 30 and s.public.fuel < fuel_goal*0.6 and not s.shipments.any(func(x):return x.asset == "fuel"): CabinetActions.buy_supply(game,"fuel")
	if s.public.stone < 10 and s.public.money > 3000 and not s.shipments.any(func(x):return x.asset == "stone"): CabinetActions.buy_supply(game,"stone")
	if s.public.tools < 3 and s.public.money > 2500 and not s.shipments.any(func(x):return x.asset == "tools"): CabinetActions.buy_supply(game,"tools")
	var wanted := "militia" if s.security < 42 else "relief" if s.mood < 45 and s.public.food > 400 else ""
	if wanted != "" and wanted not in s.realm.policies and s.realm.policies.size() < RealmRules.policy_slots(s): RealmRules.set_policy(s,content,wanted,true)


func _play(game: GameSession) -> Dictionary:
	var guard := 0
	var lowest := WeekSim.food_weeks(game.state)
	while game.state.status == "active" and guard < 100:
		guard += 1
		_resolve(game)
		_operate(game)
		var report := game.advance()
		_check(report.advanced,"ordinary policy can advance seed %d week %d" % [game.state.seed,game.state.week])
		if not report.advanced: break
		lowest = minf(lowest,WeekSim.food_weeks(game.state))
		_check(game.state.public.money >= 0 and game.state.public.food >= -0.0001 and game.state.resident.food >= -0.0001 and game.state.public.tools >= -0.0001,"no negative resource balance from environment")
		if int(report.week)%13 == 0: _check(SaveStore.valid(game.bundle()),"quarter state is saveable with environment")
	_check(game.state.status == "finalized" and guard < 100,"ordinary policy terminates without a softlock")
	return {"success":game.state.result.get("success",false),"lowest":lowest,"food":WeekSim.food_weeks(game.state),"money":game.state.public.money,"points":game.state.result.get("points",0)}


func _test_runs() -> void:
	var baseline_wins := 0
	var altered_wins := 0
	var runs := 0
	for key in combinations:
		var seed_value := int(combinations[key])
		for region in ["forest","river","highland"]:
			var baseline := _play(_new(seed_value,false,region))
			var altered := _play(_new(seed_value,true,region))
			baseline_wins += int(baseline.success)
			altered_wins += int(altered.success)
			runs += 1
			print("MODIFIER RUN %s seed=%d %s | baseline=%s food=%.1f low=%.1f | altered=%s food=%.1f low=%.1f treasury=%.2fg" % [region,seed_value,key,baseline.success,baseline.food,baseline.lowest,altered.success,altered.food,altered.lowest,float(altered.money)/100.0])
	print("MODIFIER BALANCE: same ordinary policy baseline %d/%d wins; environmental conditions %d/%d wins. No victory quota asserted." % [baseline_wins,runs,altered_wins,runs])
