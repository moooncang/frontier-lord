extends SceneTree

var content: Dictionary
var checks := 0
var failures := 0

func _init() -> void:
	content = Content.load_all()
	_check(content.has("campaign"), "campaign content is part of the production content bundle")
	if not content.has("campaign"):
		content.campaign = JSON.parse_string(FileAccess.get_file_as_string("res://content/campaign.json"))
	_test_inactive_and_setup()
	_test_quarters_and_overview()
	_test_validation()
	_test_actual_settlement()
	_test_legacy_cabinet_advisor()
	for region in ["forest", "river", "highland"]: _simulate(region)
	var trial_seeds := {}
	for seed_value in range(1,129):
		var trial := ChronicleRules.trial_for(content.chronicle,seed_value)
		if not trial_seeds.has(trial): trial_seeds[trial] = seed_value
		if trial_seeds.size() == 3: break
	_check(trial_seeds.size() == 3, "additional smoke seeds cover every winter trial")
	for trial in trial_seeds: _simulate("forest",int(trial_seeds[trial]),false)
	_simulate("river",int(trial_seeds.rot),false,1)
	_simulate("highland",int(trial_seeds.rot),false,2)
	print("CAMPAIGN DIRECTOR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CAMPAIGN FAIL: ", label)


func _fresh(campaign: bool = true) -> GameSession:
	var game := GameSession.new(content)
	game.start_run(61427, "settler", {"region":"forest", "candidate":0, "relics":[], "tutorial":false, "cabinet":true, "campaign":campaign})
	return game


func _report(week: int) -> Dictionary:
	return {"advanced":true, "week":week, "notes":[]}


func _test_inactive_and_setup() -> void:
	var game := _fresh(false)
	var before: Dictionary = game.state.duplicate(true)
	var report := _report(1)
	_check(not CampaignDirector.setup(game.state, content, {}), "missing campaign flag does not enable new rules")
	_check(CampaignDirector.after_week(game.state, content, report).is_empty(), "legacy weekly hook is a no-op")
	_check(not CampaignDirector.overview(game.state, content).enabled, "legacy overview is inactive")
	_check(CampaignDirector.take_reward(game.state, content, 0) != "", "legacy reward action cannot invent a campaign")
	_check(game.state == before and report == _report(1), "all inactive campaign APIs preserve state and report")
	_check(CampaignDirector.valid(game.state, content), "legacy saves remain valid without campaign fields")
	var harvest := WeekSim.bonus(game.state, "harvest")
	var gather := WeekSim.bonus(game.state, "gather")
	_check(CampaignDirector.setup(game.state, content, {"campaign":true}), "explicit setup enables campaign")
	var balance: Dictionary = content.campaign.balance
	_check(is_equal_approx(WeekSim.bonus(game.state,"harvest"),harvest*float(balance.harvest)) and is_equal_approx(WeekSim.bonus(game.state,"gather"),gather*float(balance.gather)), "campaign multiplies existing region and trait production without replacing it")
	before = game.state.duplicate(true)
	_check(CampaignDirector.setup(game.state,content,{"campaign":true}) and game.state == before, "repeated setup never applies the production penalty twice")
	_check(CampaignDirector.valid(game.state,content), "new campaign state validates")
	var view := CampaignDirector.overview(game.state,content)
	_check(view.title == "농지 6구획 확보" and view.deadline == 13 and view.objective.current == 4, "first visible goal is specific and measurable")
	_check(view.timeline.size() == 3 and view.timeline[0].week == 3 and view.chapters.size() == 4, "future timeline is bounded and preserves all four chapter markers")
	_check(game.state == before, "overview is read only")
	var paused := {"advanced":false,"week":1,"notes":["blocked"]}
	_check(CampaignDirector.after_week(game.state,content,paused).is_empty() and game.state == before, "blocked turns never create seasonal progress")


func _spring_success() -> GameSession:
	var game := _fresh()
	game.state.facilities.B13 = 6
	game.state.week = 14
	CampaignDirector.after_week(game.state,content,_report(13))
	return game


func _test_quarters_and_overview() -> void:
	var game := _fresh()
	_check(CampaignDirector.enabled(game.state), "real start_run campaign:true calls campaign setup")
	game.state.facilities.B13 = 6
	game.state.week = 14
	var wood: float = game.state.public.wood
	var tools: float = game.state.public.tools
	var report := _report(13)
	var result := CampaignDirector.after_week(game.state,content,report)
	_check(result.success and result.claimed and game.state.campaign.points == 3, "spring goal pays its material reward and banks growth points automatically")
	_check(game.state.public.wood == wood+16 and game.state.public.tools == tools+2, "spring material reward matches displayed definition")
	_check(game.state.ledger.any(func(entry): return entry.src == "campaign_reward" and entry.w == 13), "season reward is present in real resource ledger")
	var before: Dictionary = game.state.duplicate(true)
	_check(CampaignDirector.after_week(game.state,content,report).is_empty() and game.state == before, "replaying completed week cannot pay its reward twice")
	_check(CampaignDirector.take_reward(game.state,content,0) != "" and game.state == before, "manual claim after automatic payment is idempotent")
	var view := CampaignDirector.overview(game.state,content)
	_check(view.season == "여름" and view.title == "곡물 곳간 완공" and view.chapters[0].status == "passed", "season transition shows one new objective and previous result")
	_check(view.summary.size() <= 3 and "공훈 +3" in view.summary[0], "weekly outcome remains bounded and states actual reward")
	game.state.week = 27
	game.state.public.money = 100
	game.state.mood = 2
	result = CampaignDirector.after_week(game.state,content,_report(26))
	_check(not result.success and game.state.status == "active", "missed summer goal does not end the run")
	_check(game.state.public.money == 0 and game.state.mood == 0 and result.penalty.money == -100, "penalties clamp to actual available money and mood")
	_check(game.state.campaign.points == 3 and CampaignDirector.valid(game.state,content), "failure leaves prior earned points intact and save valid")
	game = _fresh()
	game.state.week = 27
	game.state.trial = "frost"
	game.state.trial_started = false
	game.state.bonuses.heating = .75
	view = CampaignDirector.overview(game.state,content)
	_check(view.objective.target == 117, "autumn target anticipates future frost multiplier and existing fuel efficiency")
	game.state.week = 40
	game.state.trial_started = true
	game.state.bonuses.heating = 1.125
	game.state.public.fuel = 117
	result = CampaignDirector.after_week(game.state,content,_report(39))
	_check(result.success and game.state.campaign.points == 4, "winter pressure applied by engine is not counted twice at autumn evaluation")
	game = _fresh()
	game.state.week = 53
	game.state.trial = "frost"
	game.state.health = 60
	game.state.facilities.B13 = 6
	game.state.facilities.B22 = 1
	game.state.ration = .75
	game.state.public.food = game.state.pop * 13 - 1
	game.state.resident.food = 0
	_check(not CampaignDirector.overview(game.state,content).met, "final normal-ration stock requirement cannot be bypassed by ration cuts")
	game.state.public.food += 1
	_check(CampaignDirector.overview(game.state,content).met, "final goal retains three original objectives and winter trial")
	result = CampaignDirector.after_week(game.state,content,_report(52))
	_check(result.success and game.state.campaign.points == 6, "final seasonal success records its fixed reward")


func _test_validation() -> void:
	var game := _spring_success()
	var valid_state: Dictionary = game.state.duplicate(true)
	_check(CampaignDirector.valid(valid_state,content), "completed season snapshot is valid")
	var record: Dictionary = valid_state.campaign.records[0]
	var cases := [
		{"path":["campaign"],"value":[]},
		{"path":["campaign","enabled"],"value":1},
		{"path":["campaign","version"],"value":2},
		{"path":["campaign","last_week"],"value":53},
		{"path":["campaign","last_week"],"value":-1},
		{"path":["campaign","last_week"],"value":13.5},
		{"path":["campaign","last_week"],"value":12},
		{"path":["campaign","points"],"value":99},
		{"path":["campaign","points"],"value":"3"},
		{"path":["campaign","balance"],"value":{"harvest":.56,"gather":.55}},
		{"path":["campaign","balance"],"value":[]},
		{"path":["campaign","summary"],"value":["1","2","3","4"]},
		{"path":["campaign","summary"],"value":[123]},
		{"path":["campaign","records"],"value":{}},
		{"path":["campaign","records"],"value":[record,record]},
		{"path":["campaign","records"],"value":[record,record,record,record,record]},
		{"path":["campaign","records",0],"value":1},
		{"path":["campaign","records",0,"index"],"value":4},
		{"path":["campaign","records",0,"id"],"value":"unknown"},
		{"path":["campaign","records",0,"week"],"value":26},
		{"path":["campaign","records",0,"week"],"value":13.5},
		{"path":["campaign","records",0,"reward"],"value":{"wood":999,"tools":2}},
		{"path":["campaign","records",0,"points"],"value":100},
		{"path":["campaign","records",0,"claimed"],"value":"true"},
		{"path":["campaign","records",0,"claimed"],"value":false},
		{"path":["campaign","records",0,"success"],"value":1},
		{"path":["campaign","records",0,"penalty"],"value":{"money":-100}},
		{"path":["campaign","records",0,"message"],"value":[]}
	]
	for item in cases:
		var broken: Dictionary = valid_state.duplicate(true)
		var node: Variant = broken
		for offset in item.path.size()-1: node = node[item.path[offset]]
		node[item.path[-1]] = item.value
		_check(not CampaignDirector.valid(broken,content), "reject corrupt campaign field " + str(item.path))
	_check(game.state == valid_state, "validation never mutates the source snapshot")
	game = _fresh()
	game.state.week = 14
	CampaignDirector.after_week(game.state,content,_report(13))
	_check(CampaignDirector.valid(game.state,content), "valid failed-season penalty also round-trips")
	game.state.campaign.records[0].penalty.money = 1
	_check(not CampaignDirector.valid(game.state,content), "failure cannot contain positive or fabricated resource rewards")


func _resolve(game: GameSession) -> bool:
	if not game.state.perk_offer.is_empty() and not game.choose_perk(str(game.state.perk_offer[0])): return false
	if game.state.active_event != "":
		var event: Dictionary = content.events[game.state.active_event]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if option.get("cost", {}).is_empty() and not option.has("requires_housing"):
				if game.choose_event(index) != "": return false
				break
	if not game.state.contract_offer.is_empty() and game.choose_contract("skip") != "": return false
	return game.state.active_event == "" and game.state.perk_offer.is_empty()


func _test_actual_settlement() -> void:
	var game := _fresh()
	_check(CabinetActions.start_project(game,"B13") == "", "real campaign begins with farm project")
	for week in 13:
		_check(_resolve(game), "real campaign decisions resolve before turn")
		var report := game.advance()
		_check(report.advanced, "real campaign turn executes")
	_check(game.state.week == 14 and game.state.campaign.points == 3, "actual advance evaluates spring at the 13-week boundary")
	var store := SaveStore.new("res://tests/output/campaign_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "", "real campaign state passes SaveStore write validation")
	var loaded := store.read()
	_check(loaded.ok, "saved seasonal result can be loaded")
	if not loaded.ok: return
	var restored := GameSession.new(content)
	restored.state = loaded.bundle.state
	restored.profile = loaded.bundle.profile
	_check(SaveStore.valid(restored.bundle()) and store.write(restored.bundle()) == "", "loaded normal-ration campaign remains valid and can be saved again")
	var before: Dictionary = restored.state.duplicate(true)
	_check(CampaignDirector.after_week(restored.state,content,_report(13)).is_empty() and restored.state == before, "loaded reward marker prevents repeated payout")
	var result := game.settle("은퇴")
	_check(result.get("campaign_points",-1) == 3, "retiring after thirteen weeks includes earned seasonal growth points")
	var points: int = int(game.profile.points)
	_check(game.settle("은퇴") == result and game.profile.points == points, "settlement pays seasonal growth once")
	_check(restored.settle("은퇴").points == result.points, "saved and uninterrupted retirement pay the same growth")
	game = _fresh()
	_resolve(game)
	game.advance()
	_check(game.settle("은퇴").get("campaign_points",-1) == 0, "early retirement does not grant seasonal growth")


func _test_legacy_cabinet_advisor() -> void:
	var game := GameSession.new(content)
	game.start_run(9876,"settler")
	_check(not ChronicleRules.active(game.state) and not game.state.has("council_visits"), "legacy fixture has neither chronicle rules nor advisor visit fields")
	var store := SaveStore.new("res://tests/output/campaign_legacy_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "", "pre-chronicle run can still be saved before conversion")
	var loaded := store.read()
	_check(loaded.ok, "pre-chronicle save can still be read")
	if not loaded.ok: return
	game.state = loaded.bundle.state
	game.profile = loaded.bundle.profile
	_check(SaveStore.valid(game.bundle()), "normalized normal-ration legacy save remains valid after reading")
	var harvest := WeekSim.bonus(game.state,"harvest")
	var gather := WeekSim.bonus(game.state,"gather")
	# Match the continuation path: opt into automatic labor, preserve old economy,
	# and dismiss the obsolete introductory construction letter without a reward.
	CabinetRules.setup(game.state)
	CabinetRules.reassign(game.state,content)
	if game.state.active_event == "EV01":
		game.state.seen_events.append("EV01")
		game.state.active_event = ""
	_check(CabinetActions.set_advisor(game,"CH12") == "", "converted legacy run accepts the weekly security advisor")
	var security: float = game.state.security
	var report := game.advance()
	_check(report.advanced and game.state.week == 2, "converted legacy run can advance normally")
	_check(game.state.security == security + 4 and int(game.state.cabinet.advisor_week) == 1, "legacy advisor grants exactly four security on the completed week")
	_check(game.state.get("council_visits",[]) == ["CH12"], "missing legacy visit collection is initialized once")
	_check(not CampaignDirector.enabled(game.state) and WeekSim.bonus(game.state,"harvest") == harvest and WeekSim.bonus(game.state,"gather") == gather, "legacy continuation never silently applies campaign production rules")
	var save_error := store.write(game.bundle())
	_check(save_error == "", "converted legacy advisor state passes save validation")
	if save_error != "": return
	loaded = store.read()
	_check(loaded.ok, "converted legacy advisor state reloads")
	if not loaded.ok: return
	game.state = loaded.bundle.state
	game.profile = loaded.bundle.profile
	security = game.state.security
	_check(CabinetActions.set_advisor(game,"CH12") == "" and game.state.security == security, "legacy reload and reselection do not repay the old week")
	report = game.advance()
	_check(report.advanced and game.state.security == security + 4 and int(game.state.cabinet.advisor_week) == 2, "legacy advisor continues exactly once on the next week after reload")
	_check(game.state.council_visits == ["CH12"] and SaveStore.valid(game.bundle()), "legacy visit history stays unique and the resumed state remains valid")


func _simulate(region: String, seed_value: int = 61427, reference_policy: bool = true, candidate: int = 0) -> void:
	var game := GameSession.new(content)
	game.start_run(seed_value, "settler", {"region":region,"candidate":candidate,"relics":["seeds","axe"],"tutorial":false,"cabinet":true,"campaign":true})
	CabinetActions.set_advisor(game, "CH03")
	var buys := 0
	var lowest := 99.0
	var lowest_week := 1
	var steps := 0
	while game.state.status == "active" and steps < 53:
		steps += 1
		if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
		if game.state.active_event != "":
			var event: Dictionary = content.events[game.state.active_event]
			for index in event.options.size():
				var option: Dictionary = event.options[index]
				if option.get("cost", {}).is_empty() and not option.has("requires_housing"):
					game.choose_event(index)
					break
		if not game.state.contract_offer.is_empty(): game.choose_contract("skip")
		var week: int = int(game.state.week)
		var focus := "food" if WeekSim.food_weeks(game.state) < 5.0 else "winter" if week >= 27 and game.state.public.fuel < game.state.pop * 2 else "balanced"
		CabinetRules.set_focus(game.state, content, focus)
		if game.state.orders.is_empty() and game.state.projects.is_empty():
			for target in [{"id":"B13","count":6},{"id":"B22","count":1},{"id":"B25","count":1},{"id":"B17","count":2},{"id":"B14","count":1}]:
				if int(game.state.facilities.get(target.id,0)) >= int(target.count): continue
				if CabinetActions.offer(game,target.id).error == "": CabinetActions.start_project(game,target.id)
				break
		var needed := ""
		if WeekSim.food_weeks(game.state) < 4: needed = "food"
		elif week >= 37 and game.state.public.fuel < game.state.pop * .6: needed = "fuel"
		elif game.state.public.tools < 2: needed = "tools"
		elif game.state.public.wood < 20 and game.state.facilities.get("B25",0) == 0: needed = "wood"
		if needed != "" and not game.state.shipments.any(func(s): return s.buy and s.asset == needed):
			for package in CabinetActions.supplies(game):
				if package.asset == needed and package.error == "":
					if CabinetActions.buy_supply(game,needed) == "": buys += 1
					break
		var report := game.advance()
		_check(report.advanced, "campaign smoke has no deadlock " + region + " week " + str(week))
		if not report.advanced: break
		_check(CampaignDirector.valid(game.state,content) and SaveStore.valid(game.bundle()), "campaign state remains valid after real weekly processing seed=%d region=%s week=%d" % [seed_value,region,week])
		if WeekSim.food_weeks(game.state) < lowest:
			lowest = WeekSim.food_weeks(game.state)
			lowest_week = int(game.state.week)
	_check(game.state.status == "finalized" and steps <= 52, "campaign smoke reaches a natural ending without deadlock")
	_check(game.state.campaign.records.size() == int((int(game.state.week)-1)/13.0), "every completed season is evaluated exactly once")
	if reference_policy:
		_check(game.state.week == 53, "reference policy completes the full year")
		_check(WeekSim.food_weeks(game.state) >= 12 and WeekSim.food_weeks(game.state) <= 22, "production calibration leaves 12-22 weeks reserve for the calibrated reference seed (%.1f)" % WeekSim.food_weeks(game.state))
	_check(game.state.result.get("campaign_points",-1) == game.state.campaign.points, "final settlement includes all banked seasonal growth")
	var missed: Array[String] = []
	for goal in game.state.goals.values():
		if not goal.done: missed.append(str(goal.title))
	if not ChronicleRules.trial_passed(content,game.state): missed.append("겨울 시련")
	print("CAMPAIGN SMOKE seed=",seed_value," ",region," candidate=",candidate," trial=",game.state.trial," week=",game.state.week," final=",snappedf(WeekSim.food_weeks(game.state),.1)," lowest=",snappedf(lowest,.1),"@",lowest_week," buys=",buys," gold=",game.state.public.money/100.0," health=",snappedf(game.state.health,.1)," win=",game.state.result.get("success",false)," seasons=",game.state.campaign.points," missed=",missed)
