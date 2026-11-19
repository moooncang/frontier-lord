extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary
const CONFIG := {"region":"forest","candidate":0,"relics":["seeds","axe"],"tutorial":false,"cabinet":true,"campaign":true,"workcrew":true,"realm":true}


func _init() -> void:
	content = Content.load_all()
	_test_paid_and_clamped()
	_test_net_and_zero_net()
	_test_protected_and_unavailable()
	_test_chance_and_modifiers()
	_test_purity_and_legacy()
	_test_weekly()
	_test_early_settlement()
	_test_winter_notice()
	_test_relief_delivery()
	_test_housing_sized_migrants()
	print("REALM FEEDBACK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("REALM FEEDBACK FAIL: ",message)


func _new(seed_value: int = 61427) -> GameSession:
	var game := GameSession.new(content.duplicate(true))
	game.start_run(seed_value,"settler",CONFIG)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	game.state.active_event = ""
	return game


func _event(game: GameSession, id: String, option: int) -> void:
	game.state.active_event = id
	_check(game.choose_event(option) == "","actual event resolves: " + id)
	_check(SaveStore.valid(game.bundle()),"native event result remains saveable: " + id)
	_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"event result survives JSON serialization: " + id)


func _row(game: GameSession, id: String) -> Dictionary:
	for row in RealmFeedback.outcome_lines(game.state,game.content):
		if row.id == id: return row
	return {}


func _custom(game: GameSession, option: Dictionary) -> void:
	game.content.events["RV_FEEDBACK_TEST"] = {"title":"결과 검증","week":999,"realm":true,"options":[option]}
	game.state.active_event = "RV_FEEDBACK_TEST"
	_check(game.choose_event(0) == "","synthetic boundary event uses the actual resolver")


func _test_paid_and_clamped() -> void:
	var game := _new()
	game.state.guild = 99.0
	var before: Dictionary = game.state.duplicate(true)
	_event(game,"RV_MERCHANT",0)
	var out: Dictionary = game.state.realm.outcome
	_check(out.feedback_version == 1 and out.costs.money == 300 and out.changes.money == -300,"merchant receipt includes its actual copper payment")
	_check(out.effects.tools == 4 and out.effects.guild == 1 and not out.effects.has("money"),"actual received effect respects the stat ceiling")
	_check(out.before.money == before.public.money and out.after.money == game.state.public.money,"receipt records actual before and after balances")
	var row := _row(game,"money")
	_check(row.measured and row.cost_text == "−3금" and row.net_text == "−3금" and row.effect_text == "","money row separates paid cost from delivered benefit")
	_check(_row(game,"guild").net_text == "+1" and _row(game,"tools").effect_text == "+4","stat and resource rows display their applied amounts")
	_check(game.state.week == before.week and game.state.realm.rolls == before.realm.rolls,"non-random event does not advance time or RNG")
	var finished: Dictionary = game.state.duplicate(true)
	_check(game.choose_event(0) != "" and game.state == finished,"repeating a resolved event neither pays nor awards twice")
	var festival := _new()
	festival.state.mood = 95.0
	festival.state.village = 99.0
	_event(festival,"RV_FESTIVAL",0)
	var feast: Dictionary = festival.state.realm.outcome
	_check(feast.costs.money == 300 and feast.costs.food == 80,"multi-resource costs remain visible in the result")
	_check(feast.changes.mood == 5 and feast.changes.village == 1 and feast.changes.food == -80,"festival result shows capped gains and food spent")
	var migrant := _new()
	migrant.state.meta_snapshot.append("M13")
	migrant.state.first_immigrant = false
	_event(migrant,"RV_MIG_S",0)
	_check(migrant.state.realm.outcome.costs.money == 96 and migrant.state.realm.outcome.costs.food == 24,"result uses the actual discounted price rather than the event's nominal cost")
	_check(_row(migrant,"pop").net_text == "+6명","accepted population is an explicit outcome row")


func _test_net_and_zero_net() -> void:
	var game := _new()
	game.state.public.food = 100.0
	_custom(game,{"label":"교환","cost":{"food":10},"effects":{"food":6,"health":-100}})
	var row := _row(game,"food")
	_check(row.before == 100 and row.after == 96 and row.cost == 10 and row.effect == 6 and row.delta == -4,"same-resource exchange distinguishes expense, gross effect and net change")
	_check(row.cost_text == "−10" and row.effect_text == "+6" and row.net_text == "−4","same-resource row reconciles visibly")
	_check(_row(game,"health").after == 0 and _row(game,"health").delta == -_row(game,"health").before,"stat floor records only health actually lost")
	var neutral := _new()
	_custom(neutral,{"label":"그대로 돌려받는다","cost":{"food":10},"effects":{"food":10}})
	var same := _row(neutral,"food")
	_check(not same.is_empty() and same.delta == 0 and same.cost == 10 and same.effect == 10,"zero-net exchange still exposes the paid and received amounts")
	var resident := _new()
	var private_before: float = resident.state.resident.food
	_custom(resident,{"label":"주민에게","cost":{"food":10},"effects":{"resident_food":10}})
	_check(_row(resident,"food").delta == -10 and _row(resident,"resident_food").delta == 10,"public spending and resident food receipt are not combined incorrectly")
	_check(resident.state.resident.food == private_before+10,"private food row corresponds to the actual resident account")


func _test_protected_and_unavailable() -> void:
	var game := _new()
	game.state.public.money = 900
	_check(CabinetActions.start_project(game,"B13") == "","reserve the real two-farm project")
	game.state.active_event = "RV_MERCHANT"
	var before: Dictionary = game.state.duplicate(true)
	_check(game.choose_event(0) != "" and game.state == before,"event payment cannot consume reserved construction money or replace an outcome")
	game.state.active_event = "RV_FEVER"
	before = game.state.duplicate(true)
	_check(game.choose_event(0) != "" and game.state == before,"missing facility rejects the choice before any reward, cost or RNG mutation")
	game.state.public.wood = 20.0
	_custom(game,{"label":"자재 손실","effects":{"wood":-100}})
	_check(game.state.public.wood == 16 and _row(game,"wood").delta == -4,"involuntary loss preserves reserved wood and reports only the available loss")
	_check(not game.state.realm.outcome.costs.has("wood") and game.state.realm.outcome.effects.wood == -4,"loss is an event effect, not a fabricated payment")


func _test_chance_and_modifiers() -> void:
	var wins := 0
	var losses := 0
	for seed_value in range(100,112):
		var a := _new(seed_value)
		var b := _new(seed_value)
		a.state.security = 50.0
		b.state.security = 50.0
		var rolls: int = a.state.realm.rolls
		_event(a,"RV_RAID",1)
		b.state.active_event = "RV_RAID"
		b.choose_event(1)
		_check(a.state == b.state,"measured feedback preserves seeded chance determinism")
		_check(a.state.realm.rolls == rolls+1,"chance resolution rolls exactly once including feedback")
		if a.state.realm.outcome.win: wins += 1
		else: losses += 1
		for row in RealmFeedback.outcome_lines(a.state,a.content):
			_check(is_equal_approx(row.after-row.before,row.delta) and is_equal_approx(row.effect-row.cost,row.delta),"chance outcome's gross amounts reconcile to its actual balances")
	_check(wins > 0 and losses > 0,"chance coverage contains both successful defense and actual losses")
	var mapped := _new()
	_event(mapped,"RV_SURVEY_DONE",1)
	_event(mapped,"RV_SURVEY_DONE",1)
	var gather := _row(mapped,"perm:gather")
	_check(is_equal_approx(gather.before,1.1) and is_equal_approx(gather.after,1.21) and gather.net_text == "+10%","stacked permanent multiplier reports a relative gain while retaining exact multipliers")
	var crop_before: float = mapped.state.realm.crop
	_event(mapped,"RV_SURVEY_DONE",0)
	_check(is_equal_approx(_row(mapped,"crop").before,crop_before) and _row(mapped,"crop").net_text == "+8%","crop effect is expressed relative to its previous multiplier")
	var discount := _new()
	discount.state.trade_discount = 0.48
	_custom(discount,{"label":"운송료 교섭","effects":{"trade_discount":0.1}})
	_check(is_equal_approx(discount.state.trade_discount,0.5) and _row(discount,"trade_discount").net_text == "+2%p","discount cap is reflected in percentage points")


func _test_purity_and_legacy() -> void:
	var game := _new()
	_event(game,"RV_MERCHANT",0)
	var before: Dictionary = game.state.duplicate(true)
	var definitions: Dictionary = game.content.duplicate(true)
	for iteration in 4:
		var rows := RealmFeedback.outcome_lines(game.state,game.content)
		if not rows.is_empty(): rows[0].after = -999
		RealmFeedback.weekly(game.state,game.content)
	_check(game.state == before and game.content == definitions,"repeated feedback formatting and caller edits preserve live state, definitions and RNG")
	var old: Dictionary = game.state.duplicate(true)
	for key in ["feedback_version","costs","effects","before","after"]: old.realm.outcome.erase(key)
	var rows := RealmFeedback.outcome_lines(old,game.content)
	_check(not rows.is_empty() and rows.all(func(row): return not row.measured and row.net_text == ""),"old saved effect records are explicitly unmeasured rather than invented actual balances")
	_check(SaveStore.valid({"version":1,"state":old,"profile":game.profile}),"existing outcome saves remain compatible")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(game.state))
	_check(RealmFeedback.outcome_lines(restored,game.content) == RealmFeedback.outcome_lines(game.state,game.content),"actual cost and outcome rows round-trip through JSON")


func _test_weekly() -> void:
	var game := _new()
	game.state.pop = 100
	game.state.facilities["B06"] = 1
	_check(CabinetActions.start_project(game,"B22") == "","granary construction starts through the real command")
	_check(WorkcrewRules.select(game.state,game.content,"build") == "","construction workforce selected")
	for iteration in 4:
		if int(game.state.facilities.get("B22",0)) > 0: break
		game.state.active_event = ""
		game.state.perk_offer = []
		_check(game.advance().advanced,"completion feedback derives from an actual processed week")
	var before: Dictionary = game.state.duplicate(true)
	var report := RealmFeedback.weekly(game.state,game.content)
	_check(report.week == game.state.week-1 and report.completed == [{"id":"B22","name":"곡물 곳간","count":1}],"weekly model identifies the actual newly completed facility")
	var ids: Array = report.unlocked.map(func(item): return item.id)
	_check(ids == ["B19","B21","B49"],"granary completion reveals only the three newly met dependencies")
	_check(report.promoted and report.rank_name == "촌락","actual promotion is identified by structured weekly metadata")
	_check(game.state.realm.news.any(func(item): return item.get("kind","") == "rank" and int(item.get("week",0)) == report.week),"promotion keeps its triggering completed week")
	_check(SaveStore.valid(game.bundle()),"optional news metadata remains compatible with save validation")
	report.completed[0].count = 999
	report.news.clear()
	_check(game.state == before,"weekly presentation cannot mutate completed buildings, news, economy or time")
	var second: Dictionary = game.state.duplicate(true)
	second.facilities.B22 = 2
	_check(RealmFeedback.weekly(second,game.content).unlocked.is_empty(),"a second copy of an already unlocking facility grants no duplicate unlock")
	var owned: Dictionary = game.state.duplicate(true)
	owned.facilities["B19"] = 1
	_check(not RealmFeedback.weekly(owned,game.content).unlocked.any(func(item): return item.id == "B19"),"already owned facilities are not advertised as newly unlocked")
	var stale: Dictionary = game.state.duplicate(true)
	stale.week += 1
	_check(RealmFeedback.weekly(stale,game.content).week == 0,"stale receipt is not presented as the last completed week")
	_check(RealmFeedback.weekly({},content).completed.is_empty(),"no fabricated completion before the first week")
	game.state.active_event = ""
	game.state.perk_offer = []
	game.advance()
	_check(not RealmFeedback.weekly(game.state,game.content).promoted,"next week does not repeat the previous promotion announcement")


func _test_early_settlement() -> void:
	var early := _new()
	early.state.mood = 90
	early.state.health = 90
	var result := early.settle("은퇴")
	_check(result.points == 0 and result.realm_points == 0 and early.profile.points == 0,"early retirement awards no growth points")
	_check(result.realm_lines.all(func(line): return line.points == 0),"early retirement detail rows match the actual zero payment")
	var mature := _new()
	mature.state.week = 14
	mature.state.mood = 90
	mature.state.health = 90
	var paid := mature.settle("은퇴")
	var sum := 0
	for line in paid.realm_lines: sum += int(line.points)
	_check(paid.realm_points >= 4 and paid.realm_points == sum,"eligible retirement retains the actual growth breakdown")
	var points: int = mature.profile.points
	_check(mature.settle("은퇴") == paid and mature.profile.points == points,"reading or repeating settlement never pays growth twice")


func _test_winter_notice() -> void:
	var game := _new()
	for seed_value in range(1,100):
		game.state.seed = seed_value
		if RealmRules.season_weather(game.state,game.content,3).id == "winter_bitter": break
	_check(RealmRules.season_weather(game.state,game.content,3).id == "winter_bitter","test exercises a winter whose heating multiplier used to appear only at the deadline")
	game.state.week = 27
	game.state.trial = "frost"
	game.state.trial_started = false
	game.state.realm.weather = "autumn_frost"
	game.state.bonuses.heating = 0.75
	game.state.realm.perm.heating = 0.8
	game.state.realm.policies = ["hygiene"]
	game.content.realm.policies.hygiene.mods = {"heating":0.9}
	game.state.facilities["B57"] = 1
	game.content.facilities.B57.mods = {"heating":0.95}
	RealmRules.refresh(game.state,game.content)
	var expected := int(ceil(float(game.state.pop)*0.1*13.0*0.75*0.8*0.9*0.95*1.25*1.5))
	var definitions: Dictionary = game.content.duplicate(true)
	for week in range(27,40):
		game.state.week = week
		var before: Dictionary = game.state.duplicate(true)
		var weather := RealmRules.season_weather(game.state,game.content,3)
		var target: float = CampaignDirector.overview(game.state,game.content).objective.target
		_check(target == expected,"week %d uses the same known winter target including current efficiency, policies, facility and frost trial" % week)
		weather.mods.heating = 999
		weather.name = "not shared"
		_check(game.state == before and game.content == definitions,"forecast calls and returned dictionary edits cannot change live weather, RNG, economy or definitions")
	var population_target: float = CampaignDirector.overview(game.state,game.content).objective.target
	game.state.pop += 10
	_check(CampaignDirector.overview(game.state,game.content).objective.target > population_target,"winter forecast still updates when actual residents need more heating")
	game.state.pop -= 10
	game.state.birth_rate = 0
	game.state.death_rate = 0
	game.state.public.fuel = expected
	game.state.active_event = ""
	game.state.perk_offer = []
	var rolls: int = game.state.realm.rolls
	var weather_copy: Dictionary = game.state.duplicate(true)
	RealmRules._roll_weather(weather_copy,game.content,3)
	_check(weather_copy.realm.weather == "winter_bitter" and weather_copy.realm.rolls == rolls,"actual seasonal roll uses the same forecast without consuming event RNG")
	var report := game.advance()
	_check(report.advanced and game.state.week == 40 and game.state.realm.weather == "winter_bitter","actual 39th week activates the forecast winter")
	_check(game.state.trial_started and is_equal_approx(game.state.bonuses.heating,1.125),"actual frost trial applies its multiplier once")
	var goal := CampaignDirector._objective(game.state,game.content,game.content.campaign.phases[2])
	_check(goal.target == expected and goal.met,"deadline evaluation keeps the announced target after weather and frost activation")
	_check(game.state.campaign.records.back().success and game.state.campaign.records.back().points == 4,"stocking exactly the announced amount earns the actual autumn reward")
	_check(SaveStore.valid(game.bundle()),"forecast-corrected deadline result remains saveable")
	var legacy := _new()
	legacy.state.erase("realm")
	legacy.state.week = 27
	legacy.state.trial = "frost"
	legacy.state.trial_started = false
	legacy.state.bonuses.heating = 0.75
	_check(CampaignDirector.overview(legacy.state,legacy.content).objective.target == 117,"legacy campaign keeps its original fuel requirement without realm weather")


func _test_relief_delivery() -> void:
	for fill in [0.0, 0.5, 1.0]:
		var game := _new()
		game.state.week = 2
		game.state.mood = 60.0
		game.state.health = 60.0
		game.state.birth_rate = 0.0
		game.state.death_rate = 0.0
		game.state.resident.food = 2000.0
		var need := float(game.state.pop) * 0.08
		game.state.public.food = need * fill
		RealmRules.refresh(game.state,game.content)
		var base_mood := RealmRules.target(game.state,"mood")
		var base_health := RealmRules.target(game.state,"health")
		var control := GameSession.new(game.content.duplicate(true))
		control.state = game.state.duplicate(true)
		control.profile = game.profile.duplicate(true)
		game.state.realm.policies = ["relief"]
		RealmRules.refresh(game.state,game.content)
		_check(is_equal_approx(RealmRules.target(game.state,"mood")-base_mood,7.0*fill),"relief forecast mood target matches affordable food fraction %.1f" % fill)
		_check(is_equal_approx(RealmRules.target(game.state,"health")-base_health,3.0*fill),"relief forecast health target matches affordable food fraction %.1f" % fill)
		var delivery: Dictionary = game.state.duplicate(true)
		var food := WeekSim.total_food(delivery)
		var resident := float(delivery.resident.food)
		var rolls: int = delivery.realm.rolls
		RealmRules.produce(delivery,game.content,2,0,0,1.0)
		_check(is_equal_approx(delivery.public.food,0.0) and is_equal_approx(delivery.resident.food-resident,need*fill),"relief transfers only the available public food %.1f" % fill)
		_check(is_equal_approx(WeekSim.total_food(delivery),food) and delivery.realm.rolls == rolls,"relief is a conserved transfer without an extra RNG roll")
		_check(is_equal_approx(RealmRules.target(delivery,"mood")-base_mood,7.0*fill) and is_equal_approx(RealmRules.target(delivery,"health")-base_health,3.0*fill),"completed delivery retains actual fulfillment for wellbeing, even after public stock reaches zero")
		var before: Dictionary = game.state.duplicate(true)
		WeekSim.forecast(game.state,game.content,2)
		_check(game.state == before,"forecasting relief cannot consume the live stock or grant live stats")
		_check(game.advance().advanced and control.advance().advanced,"relief comparison uses actual complete weeks")
		_check(is_equal_approx(float(game.state.mood)-float(control.state.mood),7.0*0.15*fill),"actual mood gain scales with delivery %.1f rather than granting a free full bonus" % fill)
		_check(is_equal_approx(float(game.state.health)-float(control.state.health),3.0*0.1*fill),"actual health gain scales with delivery %.1f" % fill)
		_check(SaveStore.valid(game.bundle()),"relief delivery remains saveable without new required fields")
		game.state.active_event = ""
		game.state.perk_offer = []
		control.state = game.state.duplicate(true)
		control.state.realm.policies = []
		RealmRules.refresh(control.state,control.content)
		_check(game.advance().advanced and control.advance().advanced,"empty-stock week after relief still advances")
		_check(is_equal_approx(game.state.mood,control.state.mood) and is_equal_approx(game.state.health,control.state.health),"a previous funded week does not carry a free relief effect into the next empty-stock week")


func _test_housing_sized_migrants() -> void:
	for free in [0,2,3,4,5,6,9,10,11,13,14,20]:
		var game := _new()
		game.state.mood = 100.0
		game.state.village = 100.0
		game.state.resident.food = 4000.0
		game.state.pop = int(WeekSim.capacity(game.state,game.content,"housing")) - free
		game.state.realm.queue = []
		var definitions: Dictionary = game.content.duplicate(true)
		var report := {"week":9,"notes":[]}
		var rolls: int = game.state.realm.rolls
		RealmRules._invite_migrants(game.state,game.content,report)
		if free < 3:
			_check(game.state.realm.queue.is_empty() and not report.notes.is_empty(),"fewer than three vacancies produces a housing notice rather than an impossible event")
			continue
		var count := mini(free,14)
		_check(game.state.realm.queue.size() == 1 and game.state.realm.queue[0].migrants == count,"new migration group fits %d available housing places" % free)
		_check(SaveStore.valid(game.bundle()),"pending variable-size migration survives native validation")
		RealmRules.schedule(game.state,game.content)
		var before: Dictionary = game.state.duplicate(true)
		var event := RealmRules.event_definition(game.state,game.content,str(game.state.active_event))
		var option: Dictionary = event.options[0]
		_check(str(count) + "명" in event.title and str(count) + "명" in event.body,"migration title and body show the actual offered group")
		_check(option.effects.pop == count and option.requires_housing == count and option.cost.money == count*20 and option.cost.food == count*4,"migration effects, housing and per-person settlement costs match the displayed offer")
		_check(game.option_error(option) == "","a proposal with %d housing vacancies can actually be accepted" % free)
		_check(game.state == before and game.content == definitions and game.state.realm.rolls == rolls,"reading variable offers leaves economy, RNG and shared event definitions unchanged")
		_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"active variable migration offer survives JSON serialization")
		var restored := GameSession.new(game.content.duplicate(true))
		restored.state = JSON.parse_string(JSON.stringify(game.state))
		restored.profile = JSON.parse_string(JSON.stringify(game.profile))
		_check(RealmRules.event_definition(restored.state,restored.content,str(restored.state.active_event)) == event,"restored active event preserves the same group and price")
		var people: int = restored.state.pop
		var money: float = restored.state.public.money
		var food: float = restored.state.public.food
		_check(restored.choose_event(0) == "","actual resolver accepts a housing-sized group")
		_check(restored.state.pop == people+count and is_equal_approx(money-restored.state.public.money,count*20) and is_equal_approx(food-restored.state.public.food,count*4),"actual delivered residents and paid amounts match the shown offer")
		_check(restored.state.pop <= WeekSim.capacity(restored.state,restored.content,"housing") and restored.state.realm.tally.immigrants == count,"accepting the full group cannot overfill housing and records the actual migrant count")
		_check(restored.state.realm.outcome.title == event.title and restored.state.realm.outcome.changes.pop == count and not restored.state.realm.has("migrant_offer"),"receipt retains the exact offer title and consumes its temporary metadata")
		var resolved: Dictionary = restored.state.duplicate(true)
		_check(restored.choose_event(0) != "" and restored.state == resolved,"repeating the acceptance neither charges nor grants residents twice")
		_check(SaveStore.valid(restored.bundle()),"accepted variable-size migration remains saveable")
		if free in [3,9,13]:
			var alternative := GameSession.new(game.content.duplicate(true))
			alternative.state = before.duplicate(true)
			alternative.profile = game.profile.duplicate(true)
			var expected := maxi(1,int(floor(float(count)/2.0))) if count >= 8 else 0
			_check(alternative.choose_event(1) == "","variable migration alternate option resolves")
			_check(alternative.state.pop == int(before.pop)+expected,"partial acceptance uses the displayed rounded group; small-group relief admits nobody")
			var paid: Dictionary = alternative.state.realm.outcome.costs
			_check(paid.food == (count*2 if count < 8 else expected*4),"partial acceptance and food-only relief charge their actual group size")
	var legacy := _new()
	legacy.state.active_event = "RV_MIG_S"
	_check(RealmRules.event_definition(legacy.state,legacy.content,"RV_MIG_S").options[0].effects.pop == 6,"old saved migration events without group metadata retain their original offer")
	for invalid in [0,2,3.5,15,"4",NAN]:
		legacy.state.realm["migrant_offer"] = {"event":"RV_MIG_S","count":invalid}
		_check(not RealmRules.valid(legacy.state,legacy.content),"invalid saved group counts are rejected: %s" % str(invalid))
	var protected := _new()
	protected.state.pop = int(WeekSim.capacity(protected.state,protected.content,"housing")) - 3
	protected.state.mood = 100.0
	protected.state.village = 100.0
	protected.state.resident.food = 4000.0
	protected.state.public.food = 12.0
	RealmRules._invite_migrants(protected.state,protected.content,{"notes":[]})
	RealmRules.schedule(protected.state,protected.content)
	protected.state.orders = ["B13"]
	var held := WeekSim.reserved(protected.state,protected.content)
	protected.state.public.money = int(held.money)+59
	var blocked: Dictionary = protected.state.duplicate(true)
	var offer := RealmRules.event_definition(protected.state,protected.content,str(protected.state.active_event))
	_check("예약" in protected.option_error(offer.options[0]),"dynamic per-person price still protects reserved construction funds")
	_check(protected.choose_event(0) != "" and protected.state == blocked,"unaffordable variable-size acceptance leaves stock, population, offer and RNG unchanged")
	protected.state.orders = []
	protected.state.meta_snapshot.append("M13")
	protected.state.public.money = 48
	_check(protected.event_cost(offer.options[0]).money == 48 and protected.option_error(offer.options[0]) == "","first-immigrant discount applies to the adjusted three-person cost")
	_check(protected.choose_event(0) == "" and protected.state.realm.outcome.costs.money == 48 and protected.state.public.money == 0,"actual dynamic acceptance pays the displayed discounted amount exactly")
	_check(SaveStore.valid(protected.bundle()),"discounted dynamic migration remains saveable")
