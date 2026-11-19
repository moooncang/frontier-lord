extends SceneTree
## Six milestones must follow real play, never create rewards or perform economic actions.

var checks := 0
var failures := 0
var content: Dictionary

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ONBOARDING FAIL: ", message)

func _init() -> void:
	content = Content.load_all()
	_initial_sequence()
	_skip_resume()
	_existing_restart()
	_other_project_detour()
	_order_and_invalid_receipt()
	_no_economic_mutations()
	_schema()
	print("ONBOARDING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _session() -> GameSession:
	var session := GameSession.new(content)
	session.start_run(61427, "settler", {"region":"river", "candidate":1, "relics":["seeds","seal"], "tutorial":false, "cabinet":true, "campaign":true})
	session.state.erase("onboarding")
	return session

func _choose(session: GameSession) -> void:
	_check(session.choose_perk(str(session.state.perk_offer[0])), "real perk chosen")

func _step(state: Dictionary, expected: int, message: String) -> void:
	var item := Onboarding.current(state)
	_check(item.step == expected, message + " (step %d)" % item.step)
	_check(Onboarding.valid(state), "valid progress: " + message)

func _baseline(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("onboarding")
	return result

func _initial_sequence() -> void:
	var session := _session()
	var before := session.state.duplicate(true)
	Onboarding.setup(session.state)
	_check(_baseline(session.state) == before, "setup does not mutate economy or legacy tutorial")
	_step(session.state, 0, "first perk is the first actual action")
	_check(Onboarding.current(session.state).target_id == "PerkChoicesArea", "any perk is allowed, no forced first card")
	var duplicate := session.state.duplicate(true)
	Onboarding.setup(session.state)
	_check(session.state == duplicate, "setup is idempotent")
	_choose(session)
	Onboarding.sync(session.state)
	_step(session.state, 1, "perk unlocks farm approval")
	_check(CabinetActions.start_project(session, "B13") == "", "real two-plot project approved")
	Onboarding.sync(session.state)
	_step(session.state, 2, "approval waits for real time progression")
	_check(Onboarding.current(session.state).target_id == "NextWeek", "one consistent advance control")
	var waiting_save: Dictionary = JSON.parse_string(JSON.stringify(session.state))
	Onboarding.sync(waiting_save)
	_check(Onboarding.current(waiting_save).step == 2 and Onboarding.valid(waiting_save), "pending construction tutorial resumes before its first advance")
	_check(session.advance().advanced, "first real week processed")
	Onboarding.sync(session.state)
	_step(session.state, 3, "first week requires explicit result review")
	var review_save: Dictionary = JSON.parse_string(JSON.stringify(session.state))
	Onboarding.sync(review_save)
	_check(Onboarding.current(review_save).step == 3 and review_save.onboarding.reviewed_week == 0, "loading an unread receipt cannot acknowledge it")
	_check(session.state.facilities.B13 == 5, "tutorial did not accelerate construction")
	for event in ["next", "next_development", "policy_selected", "turn_details_opened"]:
		_check(not Onboarding.acknowledge(session.state, event), "unrelated or premature action rejected: " + event)
	_step(session.state, 3, "opening a result is not acknowledging it")
	_check(Onboarding.acknowledge(session.state, "turn_details_closed"), "closing actual result is explicit review")
	_step(session.state, 4, "review prompts second construction week")
	var reviewed_save: Dictionary = JSON.parse_string(JSON.stringify(session.state))
	Onboarding.sync(reviewed_save)
	_check(Onboarding.current(reviewed_save).step == 4 and reviewed_save.onboarding.reviewed_week == 1, "explicit review survives save round trip")
	_check(session.advance().advanced, "second real week processed")
	Onboarding.sync(session.state)
	_step(session.state, 5, "six farms unlock the independent choice")
	_check(Onboarding.current(session.state).target_id == "PolicyChoices", "last step points at operating choices")
	_check(Onboarding.acknowledge(session.state, "policy_selected"), "actual policy choice completes guidance")
	_step(session.state, 6, "tutorial complete")
	_check(Onboarding.current(session.state).completed and not Onboarding.current(session.state).active, "completion hides action guidance")
	var complete := session.state.duplicate(true)
	Onboarding.sync(session.state)
	Onboarding.setup(session.state)
	_check(not Onboarding.acknowledge(session.state, "policy_selected") and session.state == complete, "completion is stable with no duplicate benefit")
	var path := "res://tests/output/onboarding_%d" % Time.get_ticks_usec()
	var store := SaveStore.new(path)
	_check(store.write(session.bundle()) == "", "completed progress saves with real run")
	var loaded := store.read()
	_check(loaded.ok and Onboarding.valid(loaded.bundle.state) and loaded.bundle.state.onboarding.step == 6, "completed progress survives save round trip")

func _skip_resume() -> void:
	var session := _session()
	Onboarding.setup(session.state)
	_choose(session)
	Onboarding.sync(session.state)
	Onboarding.skip(session.state)
	_step(session.state, 1, "skip keeps exact progress")
	_check(not Onboarding.current(session.state).active and Onboarding.current(session.state).skipped, "skip hides guidance")
	_check(CabinetActions.start_project(session, "B13") == "", "player can develop while guidance is skipped")
	_check(session.advance().advanced and session.advance().advanced, "player can advance independently while skipped")
	Onboarding.sync(session.state)
	_step(session.state, 1, "sync does not silently resume skipped guidance")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(session.state))
	_check(Onboarding.valid(serialized), "skipped progress accepts JSON whole-number floats")
	Onboarding.resume(serialized)
	_step(serialized, 3, "resume recognizes actual work but still requires a result review")
	_check(Onboarding.acknowledge(serialized, "turn_details_closed"), "resumed review is explicit")
	_step(serialized, 5, "already completed farm work needs no duplicate construction")
	_check(Onboarding.acknowledge(serialized, "next_development"), "next development also completes last step")
	_step(serialized, 6, "alternative final action completes guidance")

func _existing_restart() -> void:
	var session := _session()
	_choose(session)
	_check(CabinetActions.start_project(session, "B13") == "", "existing save fixture starts project")
	session.advance()
	session.advance()
	var state := session.state
	var before := _baseline(state)
	Onboarding.restart(state)
	_check(_baseline(state) == before, "relearn does not remove farms or grant new perks")
	_step(state, 2, "existing developed estate starts with a new actual week")
	_check(state.onboarding.project_week == state.week and not Onboarding.acknowledge(state, "turn_details_closed"), "old receipt cannot satisfy newly restarted guidance")
	session.advance()
	Onboarding.sync(state)
	_step(state, 3, "new week creates a fresh result for returning player")
	_check(Onboarding.acknowledge(state, "turn_details_closed"), "returning player explicitly reviews result")
	_step(state, 5, "completed farms are recognized after fresh review")
	Onboarding.skip(state)
	Onboarding.setup(state)
	_check(Onboarding.current(state).skipped, "loading/setup respects returning player's skip choice")
	Onboarding.restart(state)
	_step(state, 2, "restart resets learning anchors without resetting the estate")
	var legacy := GameSession.new(content)
	legacy.start_run(9876, "settler")
	legacy.state.facilities.B13 = 6
	Onboarding.restart(legacy.state)
	_step(legacy.state, 2, "non-chronicle saves do not wait forever for an unavailable first perk")
	var finished := state.duplicate(true)
	finished.status = "finalized"
	var finished_before := finished.duplicate(true)
	Onboarding.sync(finished)
	_check(not Onboarding.current(finished).active and finished == finished_before, "ended runs do not show or advance guidance")

func _order_and_invalid_receipt() -> void:
	var session := _session()
	Onboarding.setup(session.state)
	for event in ["turn_details_closed", "policy_selected", "next_development", "next", "", "skip"]:
		_check(not Onboarding.acknowledge(session.state, event), "cannot bypass initial action: " + event)
	_step(session.state, 0, "wrong events do not skip perk selection")
	_choose(session)
	Onboarding.sync(session.state)
	Onboarding.acknowledge(session.state, "turn_details_closed")
	_step(session.state, 1, "review event cannot replace approval")
	_check(CabinetActions.start_project(session, "B13") == "", "ordered action fixture approved")
	Onboarding.sync(session.state)
	var baseline := session.state.duplicate(true)
	for receipt in [{}, {"valid":false,"week":1}, {"valid":1,"week":1}, {"valid":"true","week":1}, {"valid":true,"week":0}, {"valid":true,"week":1.5}, {"valid":true,"week":2}, {"valid":true,"week":"1"}]:
		var trial := baseline.duplicate(true)
		trial.last_receipt = receipt
		Onboarding.sync(trial)
		_check(Onboarding.current(trial).step == 2 and not Onboarding.acknowledge(trial, "turn_details_closed"), "missing, invalid or future receipt cannot replace real week")
	var invalid := baseline.duplicate(true)
	invalid.onboarding.step = 3
	invalid.last_receipt = {"valid":false,"week":1}
	_check(not Onboarding.acknowledge(invalid, "turn_details_closed"), "result close rejects a non-completed receipt")

func _other_project_detour() -> void:
	var session := _session()
	Onboarding.setup(session.state)
	_choose(session)
	Onboarding.sync(session.state)
	_check(CabinetActions.start_project(session, "B25") == "", "player can choose a different real project first")
	var before := session.state.duplicate(true)
	var lesson := Onboarding.sync(session.state)
	_check(lesson.step == 1 and lesson.target_id == "NextWeek" and "공사" in lesson.title, "guide points to real time control while another project occupies development")
	_check(_baseline(session.state) == _baseline(before), "detour guidance never cancels or replaces real construction")
	_check(session.advance().advanced, "other construction actually progresses")
	Onboarding.sync(session.state)
	_check(session.state.facilities.B25 == 1 and session.state.facilities.B13 == 4, "detour does not fabricate farm progress")
	_check(Onboarding.current(session.state).step == 1 and Onboarding.current(session.state).target_id == "FocusAction", "after other project completes guide returns to farm approval")
	_check(CabinetActions.start_project(session, "B13") == "", "player can then approve the intended farm")
	Onboarding.sync(session.state)
	_step(session.state, 2, "tutorial continues normally after a real detour")

func _no_economic_mutations() -> void:
	var session := _session()
	var baseline := session.state.duplicate(true)
	var profile := session.profile.duplicate(true)
	Onboarding.setup(session.state, false)
	_check(not Onboarding.current(session.state).enabled, "explicit disabled setup remains disabled")
	for i in 30:
		Onboarding.current(session.state)
		Onboarding.sync(session.state)
		Onboarding.resume(session.state)
		Onboarding.skip(session.state)
		Onboarding.restart(session.state)
		Onboarding.acknowledge(session.state, "policy_selected")
	_check(_baseline(session.state) == baseline and session.profile == profile, "repeated guide actions never change resources, labor, rng, rewards or legacy tutorial")
	var untouched := session.state.duplicate(true)
	Onboarding.current(session.state)
	Onboarding.valid(session.state)
	_check(session.state == untouched, "read APIs are pure")
	var empty := {}
	Onboarding.setup(empty)
	Onboarding.restart(empty)
	Onboarding.resume(empty)
	_check(empty.is_empty() and not Onboarding.current(empty).active, "menu without a run is untouched")
	var absent := baseline.duplicate(true)
	Onboarding.sync(absent)
	Onboarding.skip(absent)
	_check(absent == baseline and Onboarding.valid(absent), "legacy absence is valid and does not opt in automatically")

func _schema() -> void:
	var session := _session()
	Onboarding.setup(session.state)
	var good := session.state.duplicate(true)
	var bad_values := {"version":[0,2,1.5,"1",true,null], "enabled":[0,1,"true",null], "skipped":[0,1,"false",null],
		"step":[-1,7,0.5,"0",false,null,INF,NAN], "started_week":[0,2,1.1,"1",true,null],
		"project_week":[-1,1,0.5,"0",false,null], "reviewed_week":[-1,1,0.5,"0",false,null]}
	for key in bad_values:
		for value in bad_values[key]:
			var trial := good.duplicate(true)
			trial.onboarding[key] = value
			_check(not Onboarding.valid(trial), "rejects malformed " + key + ": " + str(value))
	for key in Onboarding.FIELDS:
		var trial := good.duplicate(true)
		trial.onboarding.erase(key)
		_check(not Onboarding.valid(trial), "missing guide field rejected: " + key)
	for wrong in [null, true, [], "tutorial", 1]:
		var trial := good.duplicate(true)
		trial.onboarding = wrong
		var before := trial.duplicate(true)
		_check(not Onboarding.valid(trial) and not Onboarding.current(trial).active, "invalid guide container rejected")
		Onboarding.setup(trial)
		Onboarding.sync(trial)
		_check(trial == before, "malformed existing progress is not silently rewritten")
	var unexpected := good.duplicate(true)
	unexpected.onboarding.reward = 500
	_check(not Onboarding.valid(unexpected), "unknown guide fields are rejected")
	var future := good.duplicate(true)
	future.week = 3
	future.onboarding.step = 4
	future.onboarding.project_week = 1
	future.onboarding.reviewed_week = 3
	_check(not Onboarding.valid(future), "review cannot be stamped against an unfinished future week")
	future.onboarding.reviewed_week = 0
	_check(not Onboarding.valid(future), "review cannot precede actual construction")
	future.onboarding.reviewed_week = 2
	_check(Onboarding.valid(future), "a completed reviewed week is accepted")
	for step in [2,3,4,5,6]:
		var trial := good.duplicate(true)
		trial.onboarding.step = step
		_check(not Onboarding.valid(trial), "advanced progress requires its actual anchors: %d" % step)
	var repair := good.duplicate(true)
	repair.onboarding = "broken"
	Onboarding.restart(repair)
	_check(Onboarding.valid(repair) and Onboarding.current(repair).step == 0, "explicit restart can repair malformed guide metadata")
