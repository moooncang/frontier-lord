extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary
const CONFIG := {"region":"forest","candidate":0,"relics":["seeds","axe"],"tutorial":false,"cabinet":true,"campaign":true,"workcrew":true,"realm":true,"village_relics":true}


func _init() -> void:
	content = Content.load_all()
	_test_catalog_and_legacy()
	_test_drafts_and_inventory()
	_test_events_and_rank()
	_test_real_week_rewards()
	_test_passive_costs()
	_test_saved_validation()
	_test_last_week_promotion()
	_test_full_runs()
	print("VILLAGE RELICS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("VILLAGE RELICS FAIL: ",message)


func _new(seed_value: int = 61427, on: bool = true) -> GameSession:
	var game := GameSession.new(content.duplicate(true))
	var config := CONFIG.duplicate(true)
	config.village_relics = on
	game.start_run(seed_value,"settler",config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	_clear(game)
	return game


func _clear(game: GameSession) -> void:
	game.state.active_event = ""
	game.state.perk_offer = []
	game.state.birth_rate = 0.0
	game.state.death_rate = 0.0


func _own(game: GameSession, ids: Array) -> void:
	game.state.realm.sanctuary.owned = ids.duplicate()
	game.state.realm.sanctuary.equipped = ids.slice(0,3)
	RealmRules.refresh(game.state,game.content)


func _triggered(game: GameSession, id: String) -> bool:
	return game.state.realm.sanctuary.last_result.get("triggered",[]).any(func(row): return row.id == id)


func _test_catalog_and_legacy() -> void:
	var data := VillageRelics.definitions()
	_check(data.relics.size() == 48 and data.categories.size() == 3 and data.slots == 3,"catalog defines 48 relics, 3 families and 3 equipped slots")
	for category in data.categories:
		_check(data.relics.values().filter(func(row): return row.category == category).size() == 16,"each family has four original and twelve expansion relics")
	var legacy := _new(61427,false)
	var before: Dictionary = legacy.state.duplicate(true)
	_check(not VillageRelics.setup(legacy.state,legacy.content,{}) and legacy.state == before,"legacy state is untouched without explicit opt-in")
	_check(VillageRelics.valid(legacy.state,legacy.content) and VillageRelics.profile_valid(legacy.profile,legacy.content) and SaveStore.valid(legacy.bundle()),"old saves without sanctuary or discoveries remain valid")
	_check(VillageRelics.bonuses(legacy.state,legacy.content).mods.is_empty(),"old runs receive no passive effect")
	legacy.state.week = 4
	legacy.state.seen_events = legacy.content.events.keys().filter(func(id): return not legacy.content.events[id].get("relic_only",false))
	legacy._schedule_event()
	_check(legacy.state.active_event == "" or not legacy.content.events[legacy.state.active_event].get("relic_only",false),"old runs never schedule new fixed relic events")
	var empty := _new()
	var neutral := _new(61427,false)
	_check(empty.advance().advanced and neutral.advance().advanced,"both neutral comparison runs advance")
	for key in ["public","resident","facilities","pop","mood","health","security","bonuses","assign"]:
		_check(empty.state[key] == neutral.state[key],"enabled empty sanctuary does not alter actual economy: "+key)
	_check(empty.state.realm.rolls == neutral.state.realm.rolls,"empty sanctuary does not consume event RNG")


func _test_drafts_and_inventory() -> void:
	var game := _new()
	var twin := _new()
	var original: Dictionary = game.state.duplicate(true)
	_check(VillageRelics.request_offer(game.state,game.content,"test:first") == "","first discovery opens a relic draft")
	VillageRelics.request_offer(twin.state,twin.content,"test:first")
	_check(game.state.realm.sanctuary.offer.size() == 3 and game.state.realm.sanctuary.offer == twin.state.realm.sanctuary.offer,"same seed gives the same three unique choices")
	_check(game.state.realm.rolls == original.realm.rolls and game.state.drafts == original.drafts,"relic draft has an independent stream from events and perks")
	var pending: Dictionary = game.state.duplicate(true)
	_check(not game.advance().advanced and game.state == pending,"unclaimed relic blocks weekly time and economic mutation")
	_check(VillageRelics.request_offer(game.state,game.content,"test:first") != "" and game.state == pending,"duplicate discovery source never rerolls or queues a second payment")
	for index in 10:
		var view := VillageRelics.overview(game.state,game.content)
		view.offer[0].name = "changed view"
	_check(game.state == pending,"repeated views and edits to returned rows cannot change offers")
	_check(VillageRelics.request_offer(game.state,game.content,"test:second") == "" and game.state.realm.sanctuary.queue == ["test:second"],"a second reward queues behind the current draft")
	var first := str(game.state.realm.sanctuary.offer[0])
	var balances: Dictionary = game.state.public.duplicate(true)
	_check(game.choose_relic(first) == "" and first in game.state.realm.sanctuary.equipped and first in game.profile.relic_discoveries,"choice grants ownership, a free slot and permanent discovery")
	_check(game.state.public == balances and first not in game.state.realm.sanctuary.offer,"acquisition grants no instant resources and excludes owned relics from the next offer")
	for index in range(2,13):
		if game.state.realm.sanctuary.offer.is_empty(): VillageRelics.request_offer(game.state,game.content,"test:%d" % index)
		var id := str(game.state.realm.sanctuary.offer[0])
		_check(game.choose_relic(id) == "","each subsequent discovery selects an unowned relic")
		_check(game.state.realm.sanctuary.owned.size() == index and game.state.realm.sanctuary.equipped.size() == mini(3,index),"inventory grows while equipment remains capped at three")
	_check(game.profile.relic_discoveries.size() == 12 and VillageRelics.offer_error(game.state,game.content) != "","all relics are discoverable once and exhausted pools cannot charge for another draft")
	var blocked: Dictionary = game.state.duplicate(true)
	var stored := str(game.state.realm.sanctuary.owned[3])
	_check(game.equip_relic(stored) != "" and game.state == blocked,"full equipment requires an explicit replacement")
	var replaced := str(game.state.realm.sanctuary.equipped[0])
	var economy: Dictionary = game.state.public.duplicate(true)
	_check(game.equip_relic(stored,replaced) == "" and replaced in game.state.realm.sanctuary.owned and replaced not in game.state.realm.sanctuary.equipped,"replacement preserves the old relic in inventory")
	var bonuses: Dictionary = game.state.realm.mods.duplicate(true)
	for index in 12:
		game.unequip_relic(stored)
		game.equip_relic(stored)
	_check(game.state.public == economy and game.state.realm.mods == bonuses,"repeated equipment changes neither pay resources nor multiply cached bonuses")
	var profile: Dictionary = game.profile.duplicate(true)
	game.settle("은퇴")
	game.start_run(778,"settler",CONFIG)
	_check(game.state.realm.sanctuary.owned.is_empty() and game.profile.relic_discoveries == profile.relic_discoveries,"new run removes physical relics but preserves the discovery collection")


func _test_events_and_rank() -> void:
	var game := _new()
	game.state.active_event = "RS_RUINS"
	game.state.public.money = 199
	var blocked: Dictionary = game.state.duplicate(true)
	_check(game.choose_event(0) != "" and game.state == blocked,"unaffordable relic event cannot charge partially or create an offer")
	game.state.public.money = 12000
	var cash: int = game.state.public.money
	var tools: float = game.state.public.tools
	_check(game.choose_event(0) == "" and game.state.public.money == cash-200 and game.state.public.tools == tools-1,"real event charges its listed resources once")
	_check(game.state.realm.sanctuary.offer.size() == 3 and game.state.realm.outcome.relic_offer,"resolved event records the promised three-way relic choice")
	_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"pending event reward survives native and serialized save validation")
	var view := VillageRelics.overview(game.state,game.content)
	_check(game.choose_relic(str(view.offer[0].id)) == "" and SaveStore.valid(game.bundle()),"session wrapper chooses the displayed reward and saves its discovery")
	var alternative := _new()
	alternative.state.active_event = "RS_RUINS"
	var wood: float = alternative.state.public.wood
	_check(alternative.choose_event(1) == "" and alternative.state.public.wood == wood+18 and alternative.state.realm.sanctuary.offer.is_empty(),"instant-resource alternative does not also grant a relic")
	var ranked := _new()
	ranked.state.pop = 100
	ranked.state.facilities["B22"] = 1
	VillageRelics.request_offer(ranked.state,ranked.content,"event:test")
	var rank_before: Dictionary = ranked.state.duplicate(true)
	# Promotion and its reward can coincide with another draft in the same transaction.
	ranked.state.realm.sanctuary.offer = []
	ranked.state.realm.sanctuary.offer_source = ""
	_check(ranked.advance().advanced and ranked.state.realm.rank == 1 and "rank:1" in ranked.state.realm.sanctuary.sources,"first actual village promotion requests a relic reward")
	var source_count: int = ranked.state.realm.sanctuary.sources.size()
	_check(VillageRelics.request_offer(ranked.state,ranked.content,"rank:1") != "" and ranked.state.realm.sanctuary.sources.size() == source_count,"promotion source cannot pay a second relic")
	_check(rank_before.realm.rank == 0,"promotion fixture starts below the first rank")


func _test_real_week_rewards() -> void:
	var builders := _new()
	_own(builders,["C03","C04"])
	builders.state.workcrew.policy = "build"
	_check(builders.queue_build("B13") == "","relic construction test uses a real paid project")
	var before: Dictionary = builders.state.duplicate(true)
	var report := builders.advance()
	_check(report.advanced and _triggered(builders,"C03") and _triggered(builders,"C04"),"real eight-work farm completion triggers both construction relics")
	var result: Dictionary = builders.state.realm.sanctuary.last_result
	_check(result.totals == {"wood":6.0,"stone":4.0,"money":80.0},"construction effects pay exact public resources once per week")
	for asset in ["money","wood","stone"]:
		var row: Dictionary = builders.state.last_receipt.resource_rows.filter(func(item): return item.id == asset)[0]
		var relic_total := 0.0
		for flow in row.flows:
			if str(flow.source).begins_with("relic:"): relic_total += float(flow.amount)
		_check(is_equal_approx(relic_total,float(result.totals[asset])),"relic reward reconciles in the actual weekly ledger without concealing separately unlogged construction materials: "+asset)
	var paid: Dictionary = builders.state.duplicate(true)
	_check(VillageRelics.after_week(before,builders.state,builders.content,report).triggered.is_empty() and builders.state == paid,"repeated weekly callback cannot pay a reward twice")
	_check(SaveStore.valid(builders.bundle()),"actual triggered weekly receipt remains saveable")
	_clear(builders)
	builders.advance()
	_check(not _triggered(builders,"C03") and not _triggered(builders,"C04"),"idle construction week does not reuse the previous completion")
	var food := _new()
	_own(food,["F04"])
	food.state.facilities.B17 = 2
	food.state.workcrew.policy = "food"
	food.advance()
	_check(_triggered(food,"F04") and food.state.realm.sanctuary.last_result.totals.get("food",0) == 10,"food crew with actual production receives the stated ration reward: %s / %s" % [food.state.realm.sanctuary.last_result,food.state.ledger])
	var no_food := _new()
	_own(no_food,["F04"])
	no_food.state.workcrew.policy = "food"
	no_food.state.facilities.erase("B17")
	no_food.advance()
	_check(not _triggered(no_food,"F04"),"selecting food work without actual food production pays nothing")
	var slow := _new()
	_own(slow,["C04"])
	slow.state.workcrew.policy = "build"
	slow.state.unpaid_weeks = 8
	slow.state.arrears_wage = 1000000
	slow.queue_build("B13")
	slow.advance()
	_check(slow.state.last_receipt.development.actual_workers == 8 and slow.state.last_receipt.development.work_done == 4 and not _triggered(slow,"C04"),"unpaid-wage efficiency reduces actual work: eight assigned workers do not earn the eight-work reward")
	var guarded := _new()
	_own(guarded,["G03"])
	guarded.state.security = 65
	guarded.state.realm.threat = 1.0
	guarded.advance()
	_check(_triggered(guarded,"G03") and guarded.state.realm.sanctuary.last_result.totals.threat == -1.0 and guarded.state.realm.threat == 0,"threat reward clamps to the actual remaining threat")
	for ration in [1.0,0.75]:
		var winter := _new()
		_own(winter,["G04"])
		winter.state.week = 40
		winter.state.ration = ration
		winter.state.health = 60
		winter.state.public.fuel = 200
		winter.advance()
		_check(_triggered(winter,"G04") == (ration == 1.0),"winter care requires full normal rations, not merely full reduced rations")
	var cold := _new()
	_own(cold,["G04"])
	cold.state.week = 40
	cold.state.public.fuel = 0
	cold.state.health = 60
	cold.advance()
	_check(not _triggered(cold,"G04") and cold.state.heat_fill == 0,"no burned fuel means no winter-care reward")
	var evidence := _new()
	_own(evidence,["G04"])
	evidence.state.week = 40
	evidence.state.public.fuel = 100
	var winter_before: Dictionary = evidence.state.duplicate(true)
	var winter_report := WeekSim.process_week(evidence.state,evidence.content)
	_check(evidence.state.ledger.any(func(row): return row.src == "heating" and row.qty < 0),"winter trigger fixture includes actual heating consumption")
	for row in evidence.state.ledger:
		if row.src == "heating": row.qty = 0.0
	var forged := VillageRelics.after_week(winter_before,evidence.state,evidence.content,winter_report)
	_check(forged.triggered.is_empty(),"a cached full-heating flag without consumed fuel cannot satisfy the winter trigger")


func _test_passive_costs() -> void:
	var game := _new()
	_own(game,["F01","F02","G01"])
	var mods := VillageRelics.bonuses(game.state,game.content)
	_check(mods.mods.harvest == 1.2 and mods.mods.wages == 1.1 and mods.mods.heating == .75 and mods.mods.maintenance == 1.1,"strong relics include their real wage and maintenance costs")
	_check(mods.sets == ["abundance"] and mods.mods.storage == 1.15,"two matching equipped relics activate exactly one family set")
	var before: Dictionary = game.state.realm.perm.duplicate(true)
	for index in 20: RealmRules.refresh(game.state,game.content)
	_check(game.state.realm.perm == before and is_equal_approx(WeekSim.bonus(game.state,"harvest")/WeekSim.raw_bonus(game.state,"harvest"),float(game.state.realm.crop)*1.2),"repeated refresh does not accumulate permanent relic effects")
	_test_first_relic_wage_cost()
	var hammer := _new()
	_own(hammer,["C01"])
	hammer.state.workcrew.policy = "food"
	hammer.queue_build("B22")
	hammer.advance()
	_check(hammer.state.projects.size() == 1 and hammer.state.projects[0].work_total == int(ceil(float(Constants.GRADE_COST["B"].work)*.85)),"hammer reduces actual new-project work rather than only preview text")


func _test_first_relic_wage_cost() -> void:
	var seed_value := 1
	for candidate in range(1,100):
		var probe := _new(candidate)
		VillageRelics.request_offer(probe.state,probe.content,"probe")
		if "F01" in probe.state.realm.sanctuary.offer:
			seed_value = candidate
			break
	var game := _new(seed_value)
	ExpeditionModifiers.setup(game.state,game.content,{"modifiers":true,"realm":true})
	RealmRules.refresh(game.state,game.content)
	_check(ExpeditionModifiers.enabled(game.state),"first-discovery cost test uses the new expedition opportunity and constraint")
	_check(game.queue_build("B13") == "" and game.queue_build("B13") == "","initial real stock can fund the two-farm expansion")
	for week in range(1,4):
		if not game.state.active_event.is_empty():
			var event := RealmRules.event_definition(game.state,game.content,str(game.state.active_event))
			for index in event.options.size():
				if game.option_error(event.options[index]) == "":
					game.choose_event(index)
					break
		_check(game.advance().advanced,"actual early-game week advances toward first ruins discovery")
	_check(game.state.week == 4 and game.state.active_event == "RS_RUINS" and int(game.state.facilities.B13) == 6,"first relic event follows the actual farm expansion and first sowing")
	var money: int = game.state.public.money
	var tools: float = game.state.public.tools
	_check(game.choose_event(0) == "" and game.state.public.money == money-200 and game.state.public.tools == tools-1,"real four-week budget pays the two-gold and one-tool ruins cost")
	_check("F01" in game.state.realm.sanctuary.offer and game.choose_relic("F01") == "","bronze sickle is acquired through its actual week-four event offer")
	_check(game.queue_build("B22") == "","remaining early stock can still fund the granary after relic acquisition")
	var control := GameSession.new(game.content.duplicate(true))
	control.state = game.state.duplicate(true)
	control.profile = game.profile.duplicate(true)
	control.unequip_relic("F01")
	var ledger_start: int = game.state.ledger.size()
	var old_fraction := float(game.state.money_res)
	_check(game.advance().advanced and control.advance().advanced,"both equipped and unequipped controls complete the real fourth week")
	var paid := 0.0
	var base_paid := 0.0
	for row in game.state.ledger.slice(ledger_start):
		if row.src == "wages": paid -= float(row.qty)
	for row in control.state.ledger.slice(ledger_start):
		if row.src == "wages": base_paid -= float(row.qty)
	var workers: int = game.state.labor_report.build
	var expected := floorf(old_fraction+float(workers)*Constants.PUBLIC_WORKER_ANNUAL_WAGE/52.0*WeekSim.raw_bonus(game.state,"wages")*1.1)
	_check(workers > 0 and paid == expected and paid > base_paid,"F01 wage penalty is paid in the actual week-four construction ledger, after its acquisition")
	_check(game.state.facilities == control.state.facilities and game.state.projects == control.state.projects,"wage comparison keeps actual work and construction outcomes identical")
	_check(SaveStore.valid(game.bundle()),"actual first relic plus expedition modifiers and wage penalty stays saveable")


func _test_saved_validation() -> void:
	var game := _new()
	_own(game,["F01","C02","G04"])
	_check(VillageRelics.valid(game.state,game.content),"ordinary equipped state is valid")
	for bad in [["F01","F01"],["F01","C02","G04","F03"],["MISSING"]]:
		var broken: Dictionary = game.state.duplicate(true)
		broken.realm.sanctuary.equipped = bad
		_check(not VillageRelics.valid(broken,game.content),"duplicate, excessive or unknown equipped relics are rejected")
	var offered: Dictionary = game.state.duplicate(true)
	offered.realm.sanctuary.offer = ["F01"]
	offered.realm.sanctuary.offer_source = "test"
	offered.realm.sanctuary.sources = ["test"]
	_check(not VillageRelics.valid(offered,game.content),"saved offers cannot contain already owned relics")
	var bad_week: Dictionary = game.state.duplicate(true)
	bad_week.realm.sanctuary.last_week = 999
	_check(not VillageRelics.valid(bad_week,game.content),"future paid-week markers are rejected")
	_check(not VillageRelics.profile_valid({"relic_discoveries":["F01","F01"]},content) and not VillageRelics.profile_valid({"relic_discoveries":["BAD"]},content),"permanent discovery collection rejects unknown and duplicate IDs")


func _test_last_week_promotion() -> void:
	for week in [51,52]:
		var game := _new()
		game.state.week = week
		game.state.pop = 100
		game.state.facilities["B22"] = 1
		game.state.facilities.B13 = 6
		game.state.public.food = 3000.0
		game.state.public.fuel = 300.0
		game.state.health = 60.0
		game.state.realm.weather = str(RealmRules.season_weather(game.state,game.content,3).id)
		_own(game,["G04"])
		game.profile["relic_discoveries"] = ["G04"]
		var report := game.advance()
		_check(report.advanced and game.state.realm.rank == 1,"late-season promotion happens through a real completed week")
		_check(game.state.realm.sanctuary.last_result.week == week and _triggered(game,"G04"),"last-week ordinary relic effects still pay before settlement")
		if week == 51:
			_check(game.state.status == "active" and game.state.realm.sanctuary.offer.size() == 3 and "rank:1" in game.state.realm.sanctuary.sources,"week 51 promotion still offers a selectable reward for the remaining week")
			_check(game.choose_relic(str(game.state.realm.sanctuary.offer[0])) == "","a penultimate-week promotion reward is actually selectable")
		else:
			_check(game.state.week == 53 and game.state.status == "finalized" and game.state.result.week == 52,"final-week promotion immediately reaches the normal final result")
			_check(game.state.realm.sanctuary.offer.is_empty() and game.state.realm.sanctuary.queue.is_empty() and game.state.realm.sanctuary.offer_source == "","final result contains no unselectable pending relic draft or queued reward")
			_check("rank:1" not in game.state.realm.sanctuary.sources and game.state.realm.sanctuary.owned == ["G04"] and game.profile.relic_discoveries == ["G04"],"ending the run does not fabricate a relic acquisition or permanent discovery")
			var rank_money := 0.0
			for entry in game.state.ledger:
				if entry.src == "rank" and entry.asset == "money": rank_money += float(entry.qty)
			_check(rank_money == float(game.content.realm.ranks[1].reward.money) and game.state.result.realm_lines[1].points == game.content.realm.ranks[1].points,"final-week promotion retains its actual money and final-score reward")
			var before: Dictionary = game.bundle()
			_check(game.choose_relic("F01") != "" and game.bundle() == before,"finished runs cannot consume or invent a post-settlement relic")
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"late-promotion result remains valid across native save and reload")


func _test_full_runs() -> void:
	for seed_value in [61427,88001,4711]:
		var game := _new(seed_value)
		game.state.public.money = 100000
		game.state.public.food = 10000.0
		game.state.public.fuel = 1000.0
		game.state.public.wood = 1000.0
		game.state.public.stone = 1000.0
		game.state.facilities["B22"] = 1
		game.state.facilities["B01"] = 1
		game.state.facilities.B06 = 2
		game.state.facilities.B17 = 2
		game.state.workcrew.policy = "food"
		for step in 52:
			if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
			if not game.state.active_event.is_empty():
				var event := RealmRules.event_definition(game.state,game.content,str(game.state.active_event))
				var choice := -1
				for index in event.options.size():
					if game.option_error(event.options[index]) == "":
						choice = index
						break
				_check(choice >= 0 and game.choose_event(choice) == "","annual smoke has a real affordable event choice")
			while not game.state.realm.sanctuary.offer.is_empty():
				var offer: Array = game.state.realm.sanctuary.offer
				var picked := str(offer[0])
				for id in offer:
					if id == "F04" or id == "G04": picked = str(id)
				_check(game.choose_relic(picked) == "","annual smoke resolves queued relic choices")
			if game.state.realm.sanctuary.owned.size() > 3:
				var equipped: Array = game.state.realm.sanctuary.equipped
				var stored: Array = game.state.realm.sanctuary.owned.filter(func(id): return id not in equipped)
				if not stored.is_empty(): game.equip_relic(str(stored[0]),str(equipped[0]))
			var report := game.advance()
			_check(report.advanced,"annual smoke advances a week after resolving all rewards")
			if not report.advanced: break
			_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"weekly live and serialized relic saves remain valid through changing events and weather")
			_check(game.state.realm.sanctuary.last_week == report.week,"weekly relic settlement follows the exact completed week")
		_check(game.state.week == 53 and game.state.status == "finalized","annual relic smoke reaches an actual finalized run")
		_check(["RS_RUINS","RS_MERCHANT","RS_FOUNDATION","RS_PILGRIM"].all(func(id): return id in game.state.seen_events),"all four relic events remain reachable during the actual event schedule")
		_check(game.state.realm.sanctuary.owned.size() >= 4 and game.profile.relic_discoveries.size() == game.state.realm.sanctuary.owned.size(),"annual event acquisitions are unique and recorded permanently")
