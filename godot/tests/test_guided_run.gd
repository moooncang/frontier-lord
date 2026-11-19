extends "res://tests/test_expedition_ui.gd"
## The default tutorial advances only through real choices, construction and reviewed results.

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("GUIDED RUN FAIL: ", message)

func _shot(id: String) -> void:
	await super._shot("guided_" + id)

func _action(id: String) -> void:
	var button := _control(id) as Button
	_check(button != null and _fully_visible(id), "real pointer target is visible: " + id)
	if button == null: return
	_check(not button.disabled, "real pointer target is enabled: " + id)
	var week: int = screen.session.state.week
	var sequence: int = screen.store.sequence
	await _mouse_click(button.get_global_rect().get_center())
	if int(screen.session.state.week) > week:
		_check(SaveStore.valid(screen.session.bundle()) and screen.store.sequence > sequence, "guided actual week is persisted")

func _step(expected: int, message: String) -> void:
	var guide := Onboarding.current(screen.session.state)
	_check(guide.step == expected and Onboarding.valid(screen.session.state), message + " (step %d)" % guide.step)
	if guide.active:
		if guide.step == 0:
			_check(_fully_visible("PerkChoicesArea") and _fully_visible("SkipTutorial") and "따라하기 1 / 6" in _text("DecisionModal"), "first step is explained inline with the actual perk choices")
		else: _check(_fully_visible("TutorialCoach"), "visible one-step coach: " + message)
		if not _visible("DecisionModal"):
			_check(_fully_visible(guide.target_id), "current tutorial action is visible: " + guide.target_id)
	else:
		_check(not _visible("TutorialCoach"), "inactive guide leaves no coach overlay")

func _without_guide() -> Dictionary:
	var state: Dictionary = screen.session.state.duplicate(true)
	state.erase("onboarding")
	return state

func _reload() -> void:
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	_check(not screen.load_blocked, "guided save reloads normally")
	await _click("ContinueRun")

func _other_project_detour() -> void:
	root.size = Vector2i(1280, 720)
	screen.queue_free()
	await _frames()
	save_path = "res://tests/output/guided_detour_%d" % Time.get_ticks_usec()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	await _click("NewRun")
	screen.draft_seed = 61427
	screen._render()
	await _frames()
	await _click("candidate_1")
	await _click("PrepareNext")
	await _click("PrepareNext")
	await _click("StartRun")
	await _action("perk_" + str(screen.session.state.perk_offer[0]))
	_step(1, "detour starts before farm approval")
	await _click("nav_build")
	if not _visible("build_B25"): await _click("AllProjects")
	var button := _control("build_B25")
	if button != null:
		var ancestor: Node = button.get_parent()
		while ancestor != screen.interface and ancestor != null:
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
			ancestor = ancestor.get_parent()
		await _frames()
	await _action("build_B25")
	if screen.page != "estate": await _click("BackEstate")
	_step(1, "a different active project leaves the tutorial recoverable")
	_check(Onboarding.current(screen.session.state).target_id == "NextWeek" and _visible("SkipTutorial"), "detour coach points at completing real work and still permits skipping")
	await _shot("11_other_construction_720")
	await _action("NextWeek")
	_check(screen.session.state.facilities.B25 == 1 and screen.session.state.facilities.B13 == 4, "other facility completes without fabricated tutorial farm progress")
	_step(1, "completed detour returns to farm development guidance")
	await _action("FocusAction")
	_check(screen.page == "build", "player can choose a farm after the detour")
	if screen.all_projects: await _click("AllProjects")
	await _action("build_B13")
	if screen.page != "estate": await _click("BackEstate")
	_step(2, "real farm approval resumes the intended tutorial sequence")
	await _shot("12_detour_recovered_720")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	save_path = "res://tests/output/guided_run_%d" % Time.get_ticks_usec()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	_check(screen.guide_enabled, "new players receive actual-action guidance by default")
	await _click("NewRun")
	screen.draft_seed = 61427
	screen._render()
	await _frames()
	await _click("candidate_1")
	await _click("PrepareNext")
	await _click("region_river")
	await _click("PrepareNext")
	await _click("StartRun")
	_step(0, "first action is the player's own perk choice")
	_check(Onboarding.current(screen.session.state).target_id == "PerkChoicesArea", "guide points at all available perks")
	await _shot("01_first_choice_720")
	var chosen: String = screen.session.state.perk_offer[1]
	await _action("perk_" + chosen)
	_check(chosen in screen.session.state.perks, "player can choose a card other than the first")
	_step(1, "perk choice unlocks real development approval")
	await _shot("02_approve_720")
	var before_skip := _without_guide()
	await _click("SkipTutorial")
	_check(_without_guide() == before_skip and screen.session.state.onboarding.skipped, "skipping changes guide metadata only")
	await _reload()
	_check(screen.session.state.onboarding.skipped and not _visible("TutorialCoach"), "skip survives save and continue")
	await _click("RunHelp")
	await _click("ContinueTutorial")
	_step(1, "resume returns to uncompleted development approval")
	var money: float = screen.session.state.public.money
	await _action("FocusAction")
	_check(screen.session.state.orders.count("B13") == 2 and screen.session.state.public.money == money, "guided approval reserves actual work without charging early")
	_step(2, "approved plan waits for a week to actually pass")
	_check(not _visible("ProjectAdvance"), "tutorial uses the same single time control as ordinary play")
	await _shot("03_advance_720")
	await _action("NextWeek")
	_check(screen.session.state.week == 2 and screen.session.state.facilities.B13 == 5, "first tutorial advance performs one real construction week")
	_step(3, "actual results require deliberate inspection")
	await _shot("04_review_720")
	await _action("TurnDetails")
	_check(Onboarding.current(screen.session.state).step == 3, "opening result alone does not mark it reviewed")
	await _shot("05_details_720")
	var before_review := _without_guide()
	await _action("CloseTurnDetails")
	_check(_without_guide() == before_review, "result acknowledgement does not run the economy again")
	_step(4, "closing reviewed result unlocks the completion step")
	await _shot("06_complete_farms_720")
	await _action("NextWeek")
	_check(screen.session.state.week == 3 and screen.session.state.facilities.B13 == 6, "two actual weeks complete the two-plot project")
	_step(5, "completed farms invite an independent operating choice")
	await _shot("07_policy_720")
	var policy_button := ""
	for button in screen.interface.find_children("crew_*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and str(button.name) != "crew_" + str(screen.session.state.workcrew.policy):
			policy_button = str(button.name)
			break
	_check(policy_button != "", "player has an available operating policy choice")
	var public_before: Dictionary = screen.session.state.public.duplicate(true)
	if policy_button != "": await _action(policy_button)
	_step(6, "real operating choice finishes guidance")
	_check(screen.session.profile.points == 0 and screen.session.state.week == 3 and _same_amounts(screen.session.state.public, public_before), "tutorial completion grants no fabricated resources, points or time")
	await _reload()
	_step(6, "completed guidance does not restart on continue")
	root.size = Vector2i(1440, 900)
	screen._render()
	await _frames()
	await _click("RunHelp")
	await _click("StartTutorial")
	_step(2, "relearn recognizes completed farms and asks for a fresh week")
	_check(screen.session.state.facilities.B13 == 6 and screen.session.state.week == 3, "relearn preserves the existing estate")
	await _shot("08_relearn_900")
	await _click("TurnDetails")
	await _click("CloseTurnDetails")
	_step(2, "old stored receipt cannot satisfy the fresh-week requirement")
	await _click("NextWeek")
	_step(3, "fresh week creates new results for relearning")
	await _click("TurnDetails")
	await _click("CloseTurnDetails")
	_step(5, "relearn does not ask to rebuild already finished farms")
	await _shot("09_returning_policy_900")
	await _click("DevelopmentList")
	_check(screen.page == "build", "next development opens real project choices")
	_step(6, "next development is an alternative final tutorial action")
	_check(screen.store.read().ok and SaveStore.valid(screen.session.bundle()), "guided and relearned progress remains saveable")
	# An older save with no guide metadata opts in only when the player asks to learn.
	screen.session.state.erase("onboarding")
	_check(screen.store.write(screen.session.bundle()) == "", "legacy no-guide save fixture is valid")
	await _reload()
	_check(not Onboarding.current(screen.session.state).active and not _visible("TutorialCoach"), "an experienced player's older save does not automatically restart onboarding")
	await _click("RunHelp")
	await _click("StartTutorial")
	_step(2, "legacy player can opt into the real-action tutorial")
	await _shot("10_legacy_learn_900")
	await _other_project_detour()
	print("GUIDED RUN: %d checks, %d failures" % [checks, failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
