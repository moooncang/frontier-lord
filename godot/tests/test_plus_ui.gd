extends "res://tests/test_realm_playflow.gd"
## Production pointer navigation through advance warnings, crisis checks and rising pressure.


func _shot(tag: String) -> void:
	await _frames(8)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty(),"rendered plus screen "+tag)
	if picture != null and not picture.is_empty():
		_check(picture.save_png("res://tests/output/plus_"+tag+".png") == OK,"saved plus screen "+tag)


func _until(week: int) -> void:
	for guard in 55:
		await _settle()
		if int(screen.session.state.week) >= week or screen.session.state.status != "active": return
		var before := int(screen.session.state.week)
		await _click("NextWeek")
		if not _check(int(screen.session.state.week)>before,"actual next-week click advances while preparing for crisis"): return


func _wheel_to_end(scroller: ScrollContainer) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = scroller.get_global_rect().get_center()
	root.push_input(motion)
	for tick in 18:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await _frames(2)
	await _frames()


func _same_saved_value(actual: Variant, expected: Variant, path: String = "escalation") -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		var delta := absf(float(actual) - float(expected))
		if delta > 0: print("PLUS UI JSON numeric delta ", path, ": ", delta)
		return delta <= 0.00000001
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key in expected:
			if not actual.has(key) or not _same_saved_value(actual[key], expected[key], path + "." + str(key)): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index in expected.size():
			if not _same_saved_value(actual[index], expected[index], path + "[%d]" % index): return false
		return true
	return actual == expected


func _run() -> void:
	root.size = Vector2i(1280,720)
	await _fresh("plus_ui")
	await _click("NewRun")
	screen.draft_seed = 61427
	screen.guide_enabled = false
	await _click("PrepareNext")
	await _click("PrepareNext")
	_check(_inside(_control("PressureSetupHint")) and _inside(_control("StartRun")),"pressure explanation and start action fit on preparation page at 720p")
	await _shot("01_prepare_720")
	await _click("StartRun")
	await _settle()
	_check(CrisisDirector.enabled(screen.session.state),"production new run enables staged pressure and crises")
	_check(screen.session.content.progression.perks.size() == 96,"96 perks are loaded into production content")
	_check(VillageRelics.available_ids(screen.session.state,screen.session.content).size() == 48,"new production run can discover all 48 relics")
	_check(_inside(_control("OpenCrisis")) and _inside(_control("nav_build")),"map header keeps crisis and building controls reachable at 720p")
	await _click("OpenCrisis")
	_check(screen.page == "crises" and _visible("PressureTimeline"),"map control opens crisis preparation")
	_check(_text(_control("CurrentCrisis")).contains("8주") and not _visible("CrisisCountdown"),"unannounced crisis exposes only timing")
	for id in ["Crisis_build","Crisis_trade","Crisis_policy","BackEstate"]:
		_check(_inside(_control(id)),"crisis route action fits at 720p: "+id)
	await _shot("02_unannounced_720")
	await _click("Crisis_build")
	_check(screen.page == "build","crisis facility action opens real construction")
	await _click("BackEstate")
	await _click("side_tab_projects")
	await _click("FocusAction")
	await _click("build_B13")
	await _until(8)
	var info := CrisisDirector.overview(screen.session.state,screen.session.content)
	_check(not info.current.is_empty() and info.current.deadline == 12,"first crisis is actually announced after seven turns")
	await _shot("03_map_warning_720")
	await _click("OpenCrisis")
	var before := JSON.stringify(screen.session.state)
	await _frames(12)
	_check(JSON.stringify(screen.session.state) == before,"crisis presentation does not spend resources or consume random state")
	_check(_visible("CrisisCountdown") and _inside(_control("CrisisCountdown")),"announced deadline is visible without scrolling")
	_check(_text(_control("CrisisRequirements")).contains(str(info.current.checks[0].text)),"real requirement numbers match the simulation overview")
	_check(_text(_control("CrisisConsequences")).contains("극복 보상") and _text(_control("CrisisConsequences")).contains("미달 피해"),"success and failure consequences are disclosed")
	_check(_inside(_control("CrisisConsequences")), "success and failure consequences are visible without scrolling at 720p")
	await _shot("04_active_crisis_720")
	var requirements := _control("CrisisRequirements").get_parent() as ScrollContainer
	await _wheel_to_end(requirements)
	for label in _control("CrisisConsequences").find_children("*", "Label", true, false):
		_check(_inside(label), "real mouse wheel leaves every consequence label visible in its fixed pane")
	for id in ["Crisis_build", "Crisis_trade", "Crisis_policy"]:
		_check(_inside(_control(id)), "scrolling crisis details leaves the preparation action fixed: " + id)
	await _shot("04_crisis_scrolled_720")
	await _click("Crisis_trade")
	_check(screen.page == "trade","crisis supply action opens real purchases: " + str(screen.page))
	await _click("BackEstate")
	await _click("OpenCrisis")
	await _click("Crisis_policy")
	_check(screen.page == "policy","crisis policy action opens real decrees")
	await _click("BackEstate")
	await _until(14)
	info = CrisisDirector.overview(screen.session.state,screen.session.content)
	_check(info.records.size()==1 and int(info.records[0].week)==12,"first crisis resolves once on its advertised deadline")
	_check(int(info.pressure.index)==1,"second pressure phase starts at week fourteen")
	await _click("OpenCrisis")
	_check(_text(_control("PressureTimeline")).contains("급여 +6%"),"pressure page displays the active wage increase")
	_check(_text(_control("CrisisHistory")).contains(str(info.records[0].name)),"actual crisis result remains visible after resolution")
	await _shot("05_resolution_pressure_720")
	_check(SaveStore.valid(screen.session.bundle()),"resolved crisis and stepped pressure state remain saveable")
	await _click("BackEstate")
	await _until(18)
	await _click("OpenCrisis")
	root.size = Vector2i(1440,900)
	await _frames(12)
	for id in ["CurrentCrisis","PressureTimeline","Crisis_build","Crisis_trade","Crisis_policy"]:
		_check(_inside(_control(id)),"crisis page remains inside 900p viewport: "+id)
	await _shot("06_second_crisis_900")
	var signature: Dictionary = screen.session.state.escalation.duplicate(true)
	var save_path: String = screen.save_directory
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	await _click("ContinueRun")
	_check(_same_saved_value(screen.session.state.escalation, signature),"continue preserves crisis metadata and numeric records within JSON precision")
	for key in ["active", "plan"]:
		_check(JSON.stringify(SaveStore._normalize(screen.session.state.escalation[key])) == JSON.stringify(SaveStore._normalize(signature[key])), "announced targets and seeded plan retain their exact serialized values: " + key)
	await _settle()
	await _click("OpenCrisis")
	_check(_visible("CrisisCountdown"),"announced crisis remains actionable after restart")
	print("PLUS UI: %d checks, %d failures" % [checks,failures])
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
