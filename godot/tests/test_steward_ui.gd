extends SceneTree
## Preserve the journal UI independently; test_cabinet_ui exercises production main.

var screen: Control
var failures := 0
var checks := 0

func _init() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STEWARD UI FAIL: ", message)

func _frames(count: int = 5) -> void:
	for i in count: await process_frame

func _click(id: String) -> void:
	var button := screen.find_child(id, true, false) as Button
	_check(button != null, "exists " + id)
	if button != null:
		_check(not button.disabled, "enabled " + id)
		if not button.disabled: button.pressed.emit()
	await _frames()

func _mouse_click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
	await _frames()

func _has_text(value: String) -> bool:
	for label in screen.interface.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and value in label.text: return true
	return false

func _inside_scroll(control: Control) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor != screen.interface and ancestor != null:
		if ancestor is ScrollContainer: return true
		ancestor = ancestor.get_parent()
	return false

func _fully_visible(id: String) -> bool:
	var control := screen.find_child(id, true, false) as Control
	if control == null or not control.is_visible_in_tree(): return false
	var rect := control.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(rect): return false
	var ancestor: Node = control.get_parent()
	while ancestor != screen.interface and ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().grow(1).encloses(rect): return false
		ancestor = ancestor.get_parent()
	return true

func _shot(id: String) -> void:
	await _frames(8)
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size)).grow(1)
	var overflow: Array[String] = []
	for name in ["StudyBackdrop", "OpenLedger", "JournalTabs", "EstateStatus", "StatusHeader", "ReadingSurface", "DecisionModal", "ManagementWindow"]:
		var panel := screen.find_child(name, true, false) as Control
		if panel != null and panel.is_visible_in_tree() and not viewport.encloses(panel.get_global_rect()):
			overflow.append(name + " " + str(panel.get_global_rect()))
	# Scrollable text may extend vertically; its visible viewport and width must fit.
	for control in screen.interface.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree(): continue
		if control is ScrollContainer:
			if not _inside_scroll(control) and not viewport.encloses(control.get_global_rect()):
				overflow.append(str(control.get_path()) + " viewport")
			for child in control.get_children():
				if child is Control and not child is ScrollBar and child.size.x > control.size.x + 1:
					overflow.append(str(child.get_path()) + " horizontal " + str(child.size.x))
	_check(overflow.is_empty(), "layout fits " + id + ": " + "; ".join(overflow))
	var header := screen.find_child("StatusHeader", true, false) as Control
	var reading := screen.find_child("ReadingSurface", true, false) as Control
	var advance := screen.find_child("NextWeek", true, false) as Control
	if header != null and reading != null and reading.is_visible_in_tree():
		_check(header.get_global_rect().end.y <= reading.get_global_rect().position.y, "header clears reading surface " + id)
		if advance != null:
			_check(reading.get_global_rect().end.y <= advance.get_global_rect().position.y, "footer clears reading surface " + id)
	var small_type: Array[String] = []
	for label in screen.interface.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.get_theme_font_size("font_size") < 18:
			small_type.append(label.text.left(40))
	for field in screen.interface.find_children("*", "LineEdit", true, false):
		if field.is_visible_in_tree() and field.get_theme_font_size("font_size") < 18:
			small_type.append(str(field.name))
	_check(small_type.is_empty(), "native text at least 18px " + id + ": " + "; ".join(small_type))
	var icons: Array[String] = []
	var dock: Array[String] = []
	var tabs := screen.find_child("JournalTabs", true, false) as Control
	for button in screen.interface.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree(): continue
		if button.icon != null: icons.append(str(button.name))
		if str(button.name).begins_with("nav_"):
			if tabs == null or not tabs.get_global_rect().grow(1).encloses(button.get_global_rect()):
				dock.append(str(button.name))
	_check(icons.is_empty(), "text actions without icon clutter " + id + ": " + "; ".join(icons))
	_check(dock.is_empty(), "navigation stays in physical journal tabs " + id + ": " + "; ".join(dock))
	_check(screen.find_child("TextNavigation", true, false) == null, "no web-style sidebar " + id)
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "native text does not shrink " + id)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		_check(shot != null, "rendered " + id)
		_check(shot.save_png("res://tests/output/steward_" + id + ".png") == OK, "screenshot saved " + id)
		print("STEWARD SCREENSHOT: ", id)

func _resolve_free_event() -> void:
	var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
	for i in event.options.size():
		if event.options[i].get("cost", {}).is_empty() and not event.options[i].has("requires_housing"):
			await _click("event_option_%d" % i)
			return
	_check(false, "free event option exists")

func _run() -> void:
	root.size = Vector2i(1440, 900)
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/steward_ui.gd"))
	screen.save_directory = "res://tests/output/steward_ui_%d" % Time.get_ticks_usec()
	root.add_child(screen)
	await _frames()
	_check(screen.get_script().resource_path == "res://ui/steward_ui.gd", "journal UI regression entrypoint")
	_check(screen.paper_ready and screen.session != null, "reading UI initializes")
	if screen.session == null:
		quit(1)
		return
	_check(screen.theme.get_font("font", "Button") == PixelTheme.font(), "controls use the bundled pixel font, which also exists in browsers")
	_check(screen.theme.get_font_size("font_size", "Button") >= 19, "readable buttons")
	_check(screen.find_child("StudyBackdrop", true, false) != null, "pixel study frames game menu")
	await _shot("01_menu")
	await _click("NewRun")
	screen.draft_seed = 61427
	screen._render()
	await _shot("02_region")
	await _click("PrepareNext")
	await _shot("03_lord")
	await _click("candidate_1")
	await _click("PrepareNext")
	await _shot("04_relics")
	await _click("StartRun")
	_check(screen.session.state.chronicle and screen.session.state.week == 1, "new run begins at week one")
	_check(screen.find_child("OpenLedger", true, false) != null and screen.find_child("EstateStatus", true, false) != null, "estate HUD and journal frame gameplay")
	_check(not screen.session.state.perk_offer.is_empty(), "initial roguelite perk offer")
	_check(screen.find_child("DecisionBlocker", true, false) != null, "decision blocks background input")
	await _shot("05_perks")
	var blocked_button := screen.find_child("nav_build", true, false) as Button
	await _mouse_click(blocked_button.get_global_rect().get_center())
	_check(screen.page == "estate", "modal intercepts actual background mouse click")
	await _click("InspectEstate")
	_check(screen.find_child("DecisionModal", true, false) == null, "can read report before deciding")
	_check(_has_text("올해 통치 목표") and _has_text("지금 확인할 문제") and _has_text("3주 파종 전에"), "goals, concrete problem and its timing cause present")
	_check(_has_text("이번 주 실행 계획") and _has_text("한 주 운영 후 예상"), "plan and forecast present")
	_check(screen.find_child("TutorialCard", true, false) != null, "contextual tutorial present")
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == 1, "unresolved perk prevents advancing time")
	_check(screen.find_child("DecisionModal", true, false) != null, "advance reopens pending decision")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	_check(screen.session.state.active_event != "", "initial letter follows perk")
	await _shot("06_letter")
	await _resolve_free_event()
	_check(screen.page == "estate" and not screen.receipt.is_empty(), "event returns to report with receipt")
	_check(screen.find_child("AcknowledgeDecision", true, false) == null, "no redundant acknowledgement")
	_check(screen.find_child("DecisionModal", true, false) == null, "receipt does not obstruct report")
	_check(_has_text("결정 완료"), "actual decision outcome visible in report")
	await _shot("07_report")
	await _click("nav_build")
	await _click("facility_B13")
	var money_before: int = screen.session.state.public.money
	var farms_before: int = screen.session.state.facilities.B13
	await _click("build_B13")
	await _click("build_B13")
	_check(screen.session.state.orders.size() == 2, "two distinct farm reservations")
	_check(screen.session.state.public.money == money_before, "reservation does not spend until the week runs")
	_check(screen.session.state.facilities.B13 == farms_before, "reservation does not instantly construct")
	await _shot("08_development")
	await _click("build_tab_labor")
	await _click("BuildPreset")
	_check(screen.session.state.assign.build == 8, "construction workforce assigned")
	await _shot("09_labor")
	await _click("build_tab_queue")
	await _shot("10_queue")
	await _click("NextWeek")
	_check(screen.session.state.week == 2 and screen.session.state.history.size() == 1, "one action advances exactly one week")
	_check(screen.page == "estate" and screen.receipt.is_empty(), "week ends on fresh report")
	_check(screen.session.state.public.money < money_before, "construction charges real treasury")
	_check(not screen.last_turn.is_empty(), "actual week changes retained")
	await _shot("11_week_result")
	await _click("NextWeek")
	_check(screen.session.state.week == 3 and screen.session.state.facilities.B13 == 6, "labor completes reserved farms")
	await _click("nav_people")
	await _click("person_CH12")
	await _shot("12_people")
	await _click("CouncilVisit")
	for target in ["trade", "boons", "ledger", "journey", "archive"]:
		await _click("nav_" + target)
		await _shot("wide_" + target)
	# Smaller native window: every principal reading screen recomputes its layout.
	root.size = Vector2i(1280, 720)
	for target in ["estate", "build", "people", "trade", "boons", "ledger", "journey", "archive"]:
		screen._go(target)
		await _shot("compact_" + target)
	screen._go("build")
	await _click("build_tab_facilities")
	await _shot("compact_facilities")
	_check(_fully_visible("build_B13"), "compact construction action visible without scrolling")
	await _click("build_tab_labor")
	await _shot("compact_labor")
	_check(_fully_visible("job_gather") and _fully_visible("job_build"), "compact gathering and construction inputs visible without scrolling")
	await _click("build_tab_ration")
	for ratio in [90, 75, 100]:
		await _click("ration_%d" % ratio)
		_check(is_equal_approx(screen.session.state.ration, ratio / 100.0), "ration policy applied %d" % ratio)
		var saved: Dictionary = screen.store.read()
		_check(saved.ok, "ration policy autosave validates %d" % ratio)
		if saved.ok:
			_check(is_equal_approx(saved.bundle.state.ration, ratio / 100.0), "ration policy survives save %d" % ratio)
	_check(is_equal_approx(screen.session.state.ration, 1.0), "normal ration restored before advancing")
	await _shot("compact_ration")
	await _click("HeaderHelp")
	await _shot("compact_help")
	await _click("CloseHelp")
	# Even legacy callers asking for many weeks must only trigger one decision cycle.
	screen._go("estate")
	var week_before: int = screen.session.state.week
	await screen._advance(13)
	await _frames()
	_check(screen.session.state.week == week_before + 1, "large advance request is bounded to one week")
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == 5 and screen.session.state.active_event == "EV09", "scheduled character letter interrupts progression")
	await _shot("compact_letter")
	await _resolve_free_event()
	_check(not screen.receipt.is_empty(), "later decision also leaves a report receipt")
	await screen._advance(1)
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == 7 and not screen.session.state.perk_offer.is_empty(), "recurring perks make the run progress explicit")
	await _shot("compact_perks")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	await _shot("compact_contract")
	await _click("SkipContract")
	_check(screen.session.state.contract_offer.is_empty(), "contract may be declined")
	_check(screen.store.read().ok, "autosave readable after real interaction")
	# Settlement and permanent development continue to feed the next run.
	screen.session.settle("은퇴")
	screen._go("result")
	await _shot("compact_result")
	await _click("ResultArchive")
	await _shot("compact_permanent_upgrades")
	screen._go("result")
	await _click("ResultRestart")
	_check(screen.page == "prepare", "settlement returns to the next run")
	print("STEWARD UI: %d checks, %d failures" % [checks, failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
