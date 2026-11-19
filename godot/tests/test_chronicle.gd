extends SceneTree

var failures := 0
var checks := 0
var data: Dictionary

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CHRONICLE FAIL: ", message)

func _new(seed_value: int = 61427, region: String = "forest") -> GameSession:
	var game := GameSession.new(data)
	game.start_run(seed_value, "settler", {"region": region, "candidate": 0, "relics": ["seeds", "axe"], "tutorial": true})
	return game

func _resolve(game: GameSession) -> void:
	if not game.state.perk_offer.is_empty(): _check(game.choose_perk(game.state.perk_offer[0]), "pick perk")
	if game.state.active_event != "":
		var event: Dictionary = data.events[game.state.active_event]
		for i in event.options.size():
			if event.options[i].get("cost", {}).is_empty() and not event.options[i].has("requires_housing"):
				_check(game.choose_event(i) == "", "free event choice")
				break
	if not game.state.contract_offer.is_empty():
		var selected := false
		for id in game.state.contract_offer:
			if ChronicleRules.contract_error(data, game.state, id) == "":
				_check(game.choose_contract(id) == "", "choose contract")
				selected = true
				break
		if not selected: _check(game.choose_contract("skip") == "", "free contract alternative")

func _init() -> void:
	data = Content.load_all()
	var game := _new()
	var repeat := _new()
	_check(game.state == repeat.state, "seed reproducibility")
	_check(game.state.perk_offer.size() == 3, "starting draft")
	_check(game.state.traits.size() == 3 and game.state.relics.size() == 2, "traits and loadout applied")
	_check(not game.advance().advanced, "pending choice blocks time")
	_check(ChronicleRules.tutorial_step(game.state) == 0, "tutorial begins with perks")
	var original: Dictionary = game.state.duplicate(true)
	_check(not game.choose_perk("P_NOT_OFFERED") and game.state == original, "unoffered perk is atomic")
	_check(game.refresh_perks(), "refresh permitted")
	_check(not game.refresh_perks(), "refresh cannot exceed allowance")
	_resolve(game)
	_check(ChronicleRules.tutorial_step(game.state) == 2, "tutorial follows actual choices")
	for id in ["B13", "B13", "B22", "B25"]: _check(game.queue_build(id) == "", "initial build " + id)
	_check(ChronicleRules.tutorial_step(game.state) == 3, "tutorial sees queued farms")
	game.state.assign.build = 8
	game.state.assign.logging = 4
	_check(ChronicleRules.tutorial_step(game.state) == 4, "tutorial sees labor assignment")
	var seasonal := 0
	while game.state.status == "active" and game.state.week <= 52:
		_resolve(game)
		if game.state.week >= 37:
			game.state.assign.logging = 0
			game.state.assign.fuel = 4 if game.state.public.fuel < 160 else 0
		if game.state.actions > 0: game.council_visit("CH01")
		if game.state.actions > 0: game.council_visit("CH02")
		var report := game.advance()
		_check(report.advanced, "week advances")
		if not report.advanced: break
		_check(SaveStore.valid(game.bundle()), "save validates week " + str(game.state.week))
		if report.week in [13, 26, 39, 52]:
			seasonal += 1
			_check(report.stop, "season review stops auto")
	_check(seasonal == 4 and game.state.week == 53, "four seasons completed")
	_check(game.state.perks.size() == 8, "eight distinct drafts selected")
	_check(game.state.contract_results.size() == 4, "four contracts settled")
	_check(game.state.trial_started, "winter trial applied")
	var points: int = game.profile.points
	game.settle("완주")
	_check(game.profile.points == points and game.profile.chronicles.size() == 1, "settlement idempotent")
	_check(game.profile.discoveries.size() == 8, "discoveries persist")
	_check(game.buy_upgrade("M20") == "", "permanent loadout upgrade")
	game.start_run(914, "settler", {"region": "river", "candidate": 1, "relics": ["seeds", "lantern", "axe"]})
	_check(game.state.perks.is_empty() and game.state.relics == ["seeds", "lantern"], "reset perks, enforce upgraded relic budget")
	_check(game.profile.discoveries.size() == 8 and game.profile.chronicles.size() == 1, "next run keeps codex and history")
	var store := SaveStore.new("res://tests/output/chronicle_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "", "chronicle save writes")
	var restored: Dictionary = store.read().bundle
	FileAccess.open("res://tests/output/roundtrip_before.json", FileAccess.WRITE).store_string(JSON.stringify(game.bundle()))
	FileAccess.open("res://tests/output/roundtrip_after.json", FileAccess.WRITE).store_string(JSON.stringify(restored))
	_check(_equivalent(restored, game.bundle()), "chronicle save roundtrip")
	var corrupt := game.bundle()
	corrupt.state.trial = "unknown"
	_check(not SaveStore.valid(corrupt), "unknown trial rejected")
	corrupt = game.bundle()
	corrupt.state.tutorial = []
	_check(not SaveStore.valid(corrupt), "corrupt tutorial rejected")
	_test_synergies()
	_test_trials()
	print("CHRONICLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _equivalent(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _equivalent(a[i], b[i]): return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.000000001
	return a == b

func _test_synergies() -> void:
	var game := _new()
	var before := WeekSim.bonus(game.state, "harvest")
	for id in ["P01", "P50", "P51", "P52"]:
		game.state.perk_offer = [id]
		_check(game.choose_perk(id), "choose synergy component")
	_check(is_equal_approx(WeekSim.bonus(game.state, "harvest"), before * 1.08 * 1.08), "two-part synergy multiplies harvest once")
	_check("agriculture:4" in game.state.synergies, "four-part synergy unlocked")
	var effects: Dictionary = game.state.bonuses.duplicate(true)
	ChronicleRules.unlock_synergies(data, game.state)
	_check(effects == game.state.bonuses, "synergy cannot stack repeatedly")
	game.state.actions = 2
	_check(game.council_visit("CH02") == "", "canonical council action")
	_check(game.council_visit("CH02") != "", "same person once per week")
	_check(game.council_visit("CH03") == "" and game.council_visit("CH04") != "", "weekly action limit")

func _test_trials() -> void:
	for trial in ["frost", "rot", "audit"]:
		var game := _new()
		game.state.trial = trial
		game.state.week = 40
		var report := {"week": 39, "notes": []}
		var food := WeekSim.total_food(game.state)
		var cash: float = game.state.public.money
		ChronicleRules.after_week(data, game.state, report)
		match trial:
			"frost": _check(is_equal_approx(WeekSim.bonus(game.state, "heating"), 1.5), "cold changes heating consumption")
			"rot": _check(is_equal_approx(WeekSim.total_food(game.state), food * 0.85), "rot removes food")
			"audit": _check(is_equal_approx(game.state.public.money, maxf(0, cash - 2000)), "audit collects special tax")
		var state: Dictionary = game.state.duplicate(true)
		ChronicleRules.after_week(data, game.state, report)
		_check(state == game.state, "trial cannot apply twice")
