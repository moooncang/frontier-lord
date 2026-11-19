extends "res://tests/test_realm_rules.gd"
## Reuses the existing real-economy operator, adding announced-crisis preparation.


func _init() -> void:
	content = Content.load_all()
	_test_compatibility_and_plan()
	_test_pressure_and_freeze()
	_test_actual_pressure_boundaries()
	_test_every_crisis()
	_test_reward_queue_and_final_week()
	_test_expanded_pool_contract()
	_test_full_crisis_runs()
	print("CRISIS DIRECTOR: %d checks, %d failures" % [assertions,failures])
	quit(1 if failures else 0)


func _new(seed_value: int = 61427, region: String = "forest", realm: bool = true) -> GameSession:
	var game := GameSession.new(content.duplicate(true))
	var config := CONFIG.duplicate(true)
	config.region = region
	config.realm = realm
	config["escalation"] = true
	config["village_relics"] = true
	game.start_run(seed_value,"settler",config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _clear(game: GameSession) -> void:
	game.state.active_event = ""
	game.state.perk_offer = []
	game.state.birth_rate = 0.0
	game.state.death_rate = 0.0


func _seed_for(id: String) -> int:
	for candidate in range(1,300):
		if CrisisDirector._plan(candidate,content.crises).any(func(row): return row.id == id): return candidate
	return -1


func _announced(id: String) -> GameSession:
	var game := _new(_seed_for(id))
	_clear(game)
	var planned: Dictionary = game.state.escalation.plan.filter(func(row): return row.id == id)[0]
	game.state.week = int(planned.announce)-1
	game.state.public.fuel = 200
	var report := game.advance()
	_check(report.advanced and game.state.escalation.active.id == id,"actual week opens the scheduled warning: "+id)
	return game


func _prepare_fixture(game: GameSession, succeeds: bool) -> void:
	var s := game.state
	_clear(game)
	s.week = int(s.escalation.active.deadline)
	for key in s.public:
		s.public[key] = 10000 if succeeds else 0
	s.resident.food = 5000.0 if succeeds else 0.0
	for key in ["mood","health","security","trust","village","guild"]: s[key] = 90.0 if succeeds else 20.0
	s.ration = 1.0
	s.arrears_wage = 0.0
	for id in ["B06","B22","B33","B57","B67","B49"]:
		if succeeds: s.facilities[id] = 2 if id == "B06" else 1
		else: s.facilities.erase(id)
	s.facilities["B01"] = 1
	RealmRules.refresh(s,game.content)


func _test_compatibility_and_plan() -> void:
	var old := GameSession.new(content.duplicate(true))
	old.start_run(61427,"settler",CONFIG)
	var copy: Dictionary = old.state.duplicate(true)
	_check(not CrisisDirector.setup(old.state,content,{}) and old.state == copy,"opt-out old run is byte-for-byte unchanged")
	_check(CrisisDirector.valid(old.state,content) and CrisisDirector.bonuses(old.state,content).is_empty(),"old save gets no pressure or crisis")
	_check(SaveStore.valid(old.bundle()),"legacy save validates with newly loaded content")
	var first := _new()
	var twin := _new()
	_check(first.state.escalation.plan == twin.state.escalation.plan and first.state.escalation.plan.size() == 4,"same seed selects four reproducible crises")
	var ids := []
	for planned in first.state.escalation.plan:
		ids.append(planned.id)
		_check(planned.deadline-planned.announce >= 2 and planned.announce >= 8 and planned.deadline < 52,"every crisis allows preparation and resolves before the final week")
	_check(ids.size() == 4 and first.state.realm.rolls == twin.state.realm.rolls,"crisis planning uses an independent RNG stream")
	var snapshot: Dictionary = first.state.duplicate(true)
	for count in 20:
		var view := CrisisDirector.overview(first.state,content)
		_check(view.current.is_empty() and not view.upcoming.has("id") and not view.upcoming.has("checks"),"unannounced future crisis identity and conditions remain hidden")
		view.pressure.mods["buy"] = 999
	_check(first.state == snapshot,"repeated views cannot mutate state, plan or economy")
	_check(CrisisDirector.setup(first.state,content,{"escalation":true}) and first.state == snapshot,"repeated setup never rerolls or resets a crisis")
	var corrupt: Dictionary = first.state.duplicate(true)
	corrupt.escalation.plan[0].id = "CR12"
	_check(not CrisisDirector.valid(corrupt,content),"forged saved seed plan is rejected")


func _test_pressure_and_freeze() -> void:
	var game := _new()
	var prices := []
	for week in [1,14,27,40]:
		game.state.week = week
		RealmRules.refresh(game.state,content)
		var mods := CrisisDirector.bonuses(game.state,content)
		prices.append(float(mods.get("buy",1.0)))
		var base: Dictionary = game.state.duplicate(true)
		base.erase("escalation")
		RealmRules.refresh(base,content)
		for key in ["buy","wages","maintenance"]:
			_check(is_equal_approx(WeekSim.bonus(game.state,key)/WeekSim.bonus(base,key),float(mods.get(key,1.0))),"pressure really multiplies the live economy at week %d: %s" % [week,key])
	_check(prices == [1.0,1.05,1.1,1.16],"later phases have strictly increasing price pressure")
	var native: Dictionary = game.state.bonuses.duplicate(true)
	for count in 20: RealmRules.refresh(game.state,content)
	_check(game.state.bonuses == native and is_equal_approx(RealmRules.mod(game.state,"threat_growth"),1.4),"refresh never accumulates pressure into permanent bonuses")
	var warn := _new()
	_clear(warn)
	warn.state.week = 10
	warn.advance()
	_check("demand" in warn.state.escalation.notices and CrisisDirector.overview(warn.state,content).next_pressure.remaining == 3,"phase increase is announced three full weeks ahead")
	var winter := _announced("CR10")
	var target: float = winter.state.escalation.active.checks[0].any[0].target
	winter.state.pop += 20
	winter.state.bonuses.heating = 4.0
	RealmRules.refresh(winter.state,content)
	_check(CrisisDirector.overview(winter.state,content).current.checks[0].target == target,"population and heating changes cannot move an already announced target")
	_check(CrisisDirector.valid(JSON.parse_string(JSON.stringify(winter.state))),"frozen target persists through serialized reload")


func _paid(state: Dictionary, source: String) -> float:
	var amount := 0.0
	for row in state.ledger:
		if row.src == source: amount -= float(row.qty)
	return amount


func _test_actual_pressure_boundaries() -> void:
	var grace := _new()
	_clear(grace)
	var neutral := GameSession.new(content.duplicate(true))
	neutral.state = grace.state.duplicate(true)
	neutral.state.erase("escalation")
	neutral.profile = grace.profile.duplicate(true)
	for week in range(1,8):
		grace.state.active_event = ""
		neutral.state.active_event = ""
		grace.state.perk_offer = []
		neutral.state.perk_offer = []
		_check(grace.advance().advanced and neutral.advance().advanced,"initial seven-week economic comparison advances")
		for key in ["public","resident","mood","health","security","pop","assign","facilities"]:
			_check(grace.state[key] == neutral.state[key],"pressure preserves initial week %d economy: %s" % [week,key])
	_check(not CrisisDirector.overview(grace.state,content).current.is_empty(),"only after the seven-week grace period does the first warning appear")
	for week in [13,14,26,27,39,40]:
		var on := _new()
		_clear(on)
		on.state.week = week
		on.state.public.money = 100000
		on.state.public.tools = 100.0
		on.state.public.fuel = 300.0
		on.state.money_res = 0.0
		on.state.facilities["B25"] = 1
		on.state.facilities["B27"] = 1
		on.state.assign = {"gather":0,"build":0,"logging":4,"quarry":4,"garden":0,"fuel":0,"milling":0}
		on.state.ledger = []
		var off: Dictionary = on.state.duplicate(true)
		off.erase("escalation")
		RealmRules.refresh(on.state,content)
		RealmRules.refresh(off,content)
		var factor := CrisisDirector.bonuses(on.state,content)
		var annual_value := 0.0
		for id in on.state.facilities: annual_value += float(Constants.GRADE_COST[content.facilities[id].grade].gold)*100.0*float(on.state.facilities[id])
		var wage_raw := 8.0*Constants.PUBLIC_WORKER_ANNUAL_WAGE/52.0*WeekSim.bonus(on.state,"wages")
		var maintenance_raw := annual_value*Constants.MAINTENANCE_RATE/52.0*WeekSim.bonus(on.state,"maintenance")
		var on_report := WeekSim.process_week(on.state,content)
		WeekSim.process_week(off,content)
		_check(_paid(on.state,"wages") == floorf(wage_raw) and _paid(on.state,"wages") >= _paid(off,"wages"),"week %d actual wage ledger includes the active phase factor" % week)
		_check(_paid(on.state,"maintenance") == floorf(maintenance_raw+wage_raw-floorf(wage_raw)),"week %d actual maintenance ledger includes pressure and shared fractional accounting" % week)
		RealmRules.after_week(on.state,content,on_report)
		RealmRules.after_week(off,content,on_report.duplicate(true))
		_check(is_equal_approx(on.state.realm.threat-off.realm.threat,1.5*(float(factor.get("threat_growth",1.0))-1.0)),"week %d threat growth uses that week's phase, not the following week's phase" % week)
		var buyer := _new()
		_clear(buyer)
		buyer.state.week = week
		RealmRules.refresh(buyer.state,content)
		var quote := buyer.trade_quote("tools",3,true)
		var money: int = buyer.state.public.money
		_check(buyer.trade("tools",3,true) == "" and money-buyer.state.public.money == quote,"week %d pressure-adjusted purchase quote is the exact amount paid" % week)


func _test_every_crisis() -> void:
	for id in content.crises.definitions:
		for success in [true,false]:
			var game := _announced(str(id))
			_prepare_fixture(game,success)
			var before: Dictionary = game.state.duplicate(true)
			var report := game.advance()
			_check(report.advanced and game.state.escalation.records.size() == 1,"deadline resolves a single record: "+id)
			var record: Dictionary = game.state.escalation.records[0]
			_check(record.success == success,"actual conditions determine expected outcome: %s success=%s" % [id,success])
			_check(record.week == before.week and game.state.escalation.active.is_empty(),"deadline consumes the active crisis without an extra modal")
			for key in record.effects:
				_check(float(record.effects[key]) >= 0 if success else float(record.effects[key]) <= 0,"record contains actual correctly signed reward or loss")
			for asset in game.state.public:
				_check(float(game.state.public[asset]) >= 0,"crisis cannot make any stock negative")
			_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"crisis outcome survives actual save validation")
			var settled: Dictionary = game.state.duplicate(true)
			_check(not CrisisDirector.after_week(before,game.state,content,report).resolved and game.state == settled,"repeated deadline callback cannot pay or damage twice")
			for row in game.state.last_receipt.resource_rows:
				var amount := 0.0
				for flow in row.flows:
					if str(flow.source).begins_with("crisis_"): amount += float(flow.amount)
				_check(is_equal_approx(amount,float(record.effects.get(row.id,0.0))),"actual crisis effects reconcile with weekly resource ledger")
	var held := _new()
	_clear(held)
	held.queue_build("B13")
	var reserved := WeekSim.reserved(held.state,content)
	held.state.public.money = int(reserved.money)+5
	held.state.public.wood = float(reserved.wood)+2
	var loss := CrisisDirector._apply(held.state,content,{"money":-700,"wood":-90},1,"crisis_penalty")
	_check(loss.money == -5 and loss.wood == -2 and held.state.public.money == reserved.money and held.state.public.wood == reserved.wood,"crisis losses protect money and materials already reserved for approved works")


func _test_reward_queue_and_final_week() -> void:
	var game := _announced("CR07")
	_prepare_fixture(game,true)
	var before: Dictionary = game.state.duplicate(true)
	var report := WeekSim.process_week(game.state,content)
	VillageRelics.request_offer(game.state,content,"simultaneous:reward")
	var existing: Array = game.state.realm.sanctuary.offer.duplicate()
	CrisisDirector.after_week(before,game.state,content,report)
	_check(game.state.realm.sanctuary.offer == existing and game.state.realm.sanctuary.queue.size() == 1,"crisis relic reward queues atomically behind an existing selection")
	var record: Dictionary = game.state.escalation.records.back()
	_check(record.relic and game.choose_relic(str(existing[0])) == "" and not game.state.realm.sanctuary.offer.is_empty(),"finishing earlier reward reveals the promised crisis relic")
	var final := _announced("CR11")
	_prepare_fixture(final,true)
	var custom: Dictionary = content.duplicate(true)
	custom.crises.windows[3].deadline = 52
	final.state.escalation.plan[3].deadline = 52
	final.state.escalation.active.deadline = 52
	final.state.week = 52
	var final_before: Dictionary = final.state.duplicate(true)
	var final_report := WeekSim.process_week(final.state,custom)
	CrisisDirector.after_week(final_before,final.state,custom,final_report)
	_check(final.state.realm.sanctuary.offer.is_empty() and final.state.escalation.records.back().effects.money == 300,"a final-week relic reward converts to cash instead of leaving an unselectable reward")
	var dead := _announced("CR07")
	_prepare_fixture(dead,true)
	dead.state.pop = 1
	dead.state.death_res = 1.0
	var dead_report := dead.advance()
	_check(dead_report.advanced and dead.state.pop == 0 and dead.state.status == "finalized","crisis success can coexist with actual final-population loss in the same week")
	_check(dead.state.escalation.records.back().success and not dead.state.escalation.records.back().relic and dead.state.realm.sanctuary.offer.is_empty(),"defeat converts its crisis relic instead of leaving a blocked choice")
	_check(SaveStore.valid(dead.bundle()),"defeated crisis result remains saveable")
	var saved: Dictionary = game.state.duplicate(true)
	saved.escalation.records[0].effects["money"] = 999999
	_check(not CrisisDirector.valid(saved,content),"saved result cannot claim more than the declared reward")
	saved = game.state.duplicate(true)
	saved.escalation.records[0].checks[0].alternatives[0].current = NAN
	_check(not CrisisDirector.valid(saved,content),"nonfinite saved requirement evidence is rejected")
	var negative := _new()
	negative.state.bonuses["tax"] = -.05
	negative.state.bonuses["trust"] = -2.0
	_check(SaveStore.valid(negative.bundle()),"legitimate negative additive perk costs remain saveable")
	negative.state.bonuses["gather"] = -.05
	_check(not SaveStore.valid(negative.bundle()),"negative multiplicative production modifiers remain rejected")
	negative.state.bonuses.erase("gather")
	negative.state.bonuses.tax = NAN
	_check(not SaveStore.valid(negative.bundle()),"signed additive exception still rejects nonfinite modifiers")


func _test_expanded_pool_contract() -> void:
	var sample := content.duplicate(true)
	sample.progression.perks = {
		"TEST_BASE":{"name":"base","effect":"gather","value":1.1},
		"TEST_PLUS":{"name":"plus","plus_only":true,"effect":"harvest","value":1.2,"extra_bonuses":{"wages":1.1,"tax":0.03}},
		"TEST_LATE":{"name":"late","plus_only":true,"pool_min_week":14,"effect":"heating","value":0.9},
		"TEST_EARLY":{"name":"early","plus_only":true,"pool_max_week":1,"effect":"seed","value":0.9}}
	var expanded := GameSession.new(sample)
	var config := CONFIG.duplicate(true)
	config["escalation"] = true
	expanded.start_run(1,"settler",config)
	_check("TEST_PLUS" in expanded.state.perk_offer and "TEST_LATE" not in expanded.state.perk_offer,"initial draft runs after escalation setup and respects late-availability filters")
	var wages := WeekSim.raw_bonus(expanded.state,"wages")
	var tax := WeekSim.raw_bonus(expanded.state,"tax",0)
	_check(expanded.choose_perk("TEST_PLUS") and is_equal_approx(WeekSim.raw_bonus(expanded.state,"wages"),wages*1.1) and is_equal_approx(WeekSim.raw_bonus(expanded.state,"tax",0),tax+.03),"compound perks apply multiplicative penalties and additive benefits exactly once")
	expanded.state.week = 14
	expanded._offer_perks()
	_check("TEST_LATE" in expanded.state.perk_offer and "TEST_EARLY" not in expanded.state.perk_offer,"later drafts exclude expired sowing perks")
	var legacy := GameSession.new(sample)
	legacy.start_run(1,"settler",CONFIG)
	_check(legacy.state.perk_offer == ["TEST_BASE"],"legacy runs do not receive expansion-only perks")
	sample.events["TEST_RANDOM"] = {"week":999,"realm":true,"plus_only":true,"pool":{"weight":1},"options":[{"label":"ok","effects":{}}]}
	sample.events["TEST_FIXED"] = {"week":1,"plus_only":true,"options":[{"label":"ok","effects":{}}]}
	legacy.state.active_event = ""
	legacy.state.seen_events = sample.events.keys().filter(func(id): return id != "TEST_FIXED")
	legacy._schedule_event()
	_check(legacy.state.active_event != "TEST_FIXED" and not RealmRules.eligible(legacy.state,sample).any(func(row): return row.id == "TEST_RANDOM"),"legacy runs filter both fixed and random expansion events")


func _resolve_smart(game: GameSession) -> void:
	super._resolve_smart(game)
	while VillageRelics.enabled(game.state) and not game.state.realm.sanctuary.offer.is_empty(): game.choose_relic(str(game.state.realm.sanctuary.offer[0]))
	var overview := CrisisDirector.overview(game.state,content)
	if not overview.current.is_empty():
		for check in game.state.escalation.active.checks:
			for condition in check.any:
				if condition.kind == "stat" and condition.get("key","") in ["health","security"]:
					var policy := "hygiene" if condition.key == "health" else "militia"
					if float(game.state[condition.key]) < float(condition.target) and policy not in game.state.realm.policies: RealmRules.set_policy(game.state,content,policy,true)
				if condition.kind == "resource" and condition.key in ["tools","fuel"] and CrisisDirector._value(game.state,content,condition) < float(condition.target):
					if not game.state.shipments.any(func(row): return row.asset == condition.key): CabinetActions.buy_supply(game,str(condition.key))
	var save_ok := SaveStore.valid(game.bundle())
	_check(save_ok,"live full-run crisis state remains saveable before each week")


func _test_full_crisis_runs() -> void:
	var successes := 0
	var total := 0
	var resolved := 0
	for seed_value in [61427,88001,4711,27]:
		var game := _new(seed_value)
		var result := _play(game,true)
		var prepared: int = game.state.escalation.records.filter(func(row): return row.success).size()
		print("CRISIS RUN seed=%d final=%s crises=%d/4 gold=%d food=%.1f" % [seed_value,result.success,prepared,result.money,WeekSim.food_weeks(game.state)])
		_check(game.state.week == 53 and game.state.status == "finalized" and game.state.escalation.records.size() == 4,"actual resource-limited run resolves all four announced crises and reaches the final result")
		_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"full-run final save survives serialized reload")
		successes += 1 if result.success else 0
		resolved += prepared
		total += 1
	_check(successes >= 2,"prepared play can still complete the first year under escalating costs")
	_check(resolved >= total*2,"announced preparation achieves at least half the crises in real resource-limited runs")
