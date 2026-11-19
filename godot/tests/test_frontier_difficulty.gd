extends "res://tests/test_seasonal_investments.gd"


func _init() -> void:
	content = Content.load_all()
	_test_difficulty_unlocks()
	_test_difficulty_economy()
	_test_difficulty_rewards()
	_test_difficulty_saves()
	_test_difficulty_years()
	print("FRONTIER DIFFICULTY: %d checks, %d failures" % [assertions,failures])
	quit(1 if failures else 0)


func _profile_for_level(level: int) -> Dictionary:
	var profile := {"version":1,"points":0,"upgrades":[],"receipts":{},"runs":0}
	for cleared in level:
		profile.receipts["fixture:%d" % cleared] = {"reason":"완주","success":true,"week":52,"difficulty_level":cleared,"difficulty_points":cleared*2}
	return profile


func _difficulty(level: int, seed_value: int = 61427, support: bool = false) -> GameSession:
	var game := GameSession.new(content)
	game.profile = _profile_for_level(level)
	var config := CONFIG.duplicate(true)
	config["escalation"] = true
	config["village_relics"] = true
	config["seasonal_support"] = support
	config["difficulty"] = level
	game.start_run(seed_value,"settler",config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _test_difficulty_unlocks() -> void:
	_check(FrontierDifficulty.data_errors(content.frontier_difficulty).is_empty(),"all five difficulty rules use actual consumed modifiers")
	var old := {"receipts":{"old":{"reason":"완주","success":true,"week":52}}}
	_check(FrontierDifficulty.unlocked(old) == 1,"old successful 52-week receipt migrates to difficulty one without spending or changing it")
	for bad in [{"reason":"은퇴","success":true,"week":52},{"reason":"완주","success":false,"week":52},{"reason":"완주","success":true,"week":51}]:
		_check(FrontierDifficulty.unlocked({"receipts":{"old":bad}}) == 0,"retirement, failed objectives or short runs do not unlock harder starts")
	for level in range(6):
		var profile := _profile_for_level(level)
		var before := profile.duplicate(true)
		var view := FrontierDifficulty.overview(profile,content)
		_check(view.unlocked == level and view.levels.size() == 6 and view.levels[level].rules.size() == level,"sequential successful clears expose cumulative rules for difficulty %d" % level)
		_check(profile == before,"difficulty inspection never changes profile")
	var requested := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config["difficulty"] = 5
	requested.start_run(61427,"settler",config)
	_check(requested.state.frontier_difficulty.level == 0,"forged locked start config is clamped to the legitimately unlocked level")
	var existing := _new()
	var state := existing.state.duplicate(true)
	_check(not FrontierDifficulty.setup(existing.state,existing.profile,content,{}) and existing.state == state,"old run is byte-for-byte neutral without explicit opt-in")
	_check(SaveStore.valid(existing.bundle()),"old run remains saveable")
	var zero := _difficulty(0)
	var legacy := _new()
	var clean := zero.state.duplicate(true)
	clean.erase("frontier_difficulty")
	_check(clean == legacy.state,"difficulty zero preserves the exact old starting economy and RNG")
	var bad: Dictionary = content.frontier_difficulty.duplicate(true)
	bad.rules[0].mods = {"not_consumed":1.1}
	_check(not FrontierDifficulty.data_errors(bad).is_empty(),"unused difficulty modifier rejected")


func _test_difficulty_economy() -> void:
	for level in range(1,6):
		var game := _difficulty(level)
		_economic_setup(game)
		game.state.week = 46 if level == 4 else 20
		RealmRules.refresh(game.state,content)
		var baseline: Dictionary = game.state.duplicate(true)
		baseline.erase("frontier_difficulty")
		RealmRules.refresh(baseline,content)
		var before: Dictionary = game.state.duplicate(true)
		for repeat in 5: RealmRules.refresh(game.state,content)
		_check(before == game.state,"refresh never stacks difficulty penalties repeatedly")
		var controls := GameSession.new(content)
		controls.state = baseline
		_check(game.trade_quote("tools",10,true) > controls.trade_quote("tools",10,true),"difficulty one increases actual purchase quotes")
		var start: int = game.state.ledger.size()
		var report := WeekSim.process_week(game.state,content)
		var control := WeekSim.process_week(baseline,content)
		_check(report.advanced and control.advanced,"difficulty A/B uses actual weekly processing")
		if level >= 2: _check(_flow(game.state,"maintenance","money",start) < _flow(baseline,"maintenance","money",start),"difficulty two increases actual upkeep payments")
		if level >= 3: _check(_flow(game.state,"logging","tools",start) < _flow(baseline,"logging","tools",start),"difficulty three increases real tool inputs")
		if level == 4: _check(_flow(game.state,"heating","fuel",start) < _flow(baseline,"heating","fuel",start),"difficulty four increases actual winter fuel use")
		if level == 5:
			RealmRules.after_week(game.state,content,report)
			RealmRules.after_week(baseline,content,control)
			_check(game.state.realm.threat > baseline.realm.threat,"difficulty five increases actual threat growth")
		_check(TurnReceipt.valid(TurnReceipt.build(before,game.state,report)),"difficulty economy produces a coherent actual receipt")


func _test_difficulty_rewards() -> void:
	for level in range(6):
		for completed in [12,13,52]:
			var game := _difficulty(level)
			game.state.week = completed+1
			var base := GameSession.new(content)
			base.state = game.state.duplicate(true)
			base.state.erase("frontier_difficulty")
			base.profile = game.profile.duplicate(true)
			var result := game.settle("은퇴")
			var plain := base.settle("은퇴")
			var expected := level*2 if completed >= 13 else 0
			_check(result.difficulty_points == expected and result.points == plain.points+expected,"only eligible runs receive exactly the displayed additional merit")
			var points: int = game.profile.points
			game.settle("완주")
			_check(game.profile.points == points,"repeated settlement cannot duplicate difficulty merit")
			_check(FrontierDifficulty.unlocked(game.profile) == level,"retirement never counts as clearing the selected level")
	var game := _difficulty(1)
	_economic_setup(game)
	game.state.week = 53
	game.state.facilities.B13 = 6
	game.state.public.food = 100000.0
	game.state.trial = "frost"
	game.state.heat_fill = 1.0
	var result := game.settle("완주")
	_check(result.success and FrontierDifficulty.unlocked(game.profile) == 2,"actual successful settlement unlocks the next level")
	_check(result.difficulty_level == 1 and result.difficulty_points == 2,"result records selected challenge independently of seasonal pressure")


func _test_difficulty_saves() -> void:
	var game := _difficulty(5)
	var original := game.state.duplicate(true)
	game.profile.receipts.clear()
	_check(FrontierDifficulty.setup(game.state,game.profile,content,{"difficulty":0}) and game.state == original,"existing challenge snapshot cannot change when profile or config changes")
	_check(SaveStore.valid(game.bundle()),"active challenge uses its starting unlock snapshot, not a mutable current profile")
	var store := SaveStore.new("res://tests/output/difficulty_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "","challenge writes to an isolated save")
	var saved := store.read()
	_check(saved.ok and saved.bundle.state.frontier_difficulty == game.state.frontier_difficulty,"challenge and unlock snapshot survive JSON reload")
	for kind in ["too_high","locked","bad_version","nan","forged_receipt"]:
		var broken := game.bundle()
		match kind:
			"too_high": broken.state.frontier_difficulty.level = 6
			"locked": broken.state.frontier_difficulty.unlocked_at_start = 0
			"bad_version": broken.state.frontier_difficulty.version = 2
			"nan": broken.state.frontier_difficulty.level = NAN
			"forged_receipt": broken.profile.receipts["bad"] = {"difficulty_level":2,"difficulty_points":999,"week":52}
		_check(not SaveStore.valid(broken),"invalid difficulty save rejected: "+kind)


func _test_difficulty_years() -> void:
	for pair in [[0,61427],[5,61427],[5,27],[5,88001]]:
		var game := _difficulty(pair[0],pair[1],true)
		var outcome := _play(game,true)
		print("DIFFICULTY RUN level=%d seed=%d week=%d success=%s pop=%d gold=%d supports=%d" % [pair[0],pair[1],outcome.week,outcome.success,outcome.pop,outcome.money,game.state.seasonal_support.decisions.size()])
		_check(game.state.status == "finalized" and game.state.week == 53,"actual operator completes yearly simulation without forcing a victory")
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"highest-difficulty actual final state remains saveable")
		_check(game.state.result.difficulty_points == int(pair[0])*2,"actual final merit matches selected level")
