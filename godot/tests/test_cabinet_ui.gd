extends SceneTree
## Preserve the compact cabinet interface independently of the expedition production UI.

var screen: Control
var failures := 0
var checks := 0

func _init() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CABINET UI FAIL: ", message)

func _frames(count: int = 5) -> void:
	for i in count: await process_frame

func _control(id: String) -> Control:
	return screen.find_child(id, true, false) as Control

func _visible(id: String) -> bool:
	var item := _control(id)
	return item != null and item.is_visible_in_tree()

func _fully_visible(id: String) -> bool:
	var item := _control(id)
	if item == null or not item.is_visible_in_tree(): return false
	var rect := item.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(rect): return false
	var ancestor: Node = item.get_parent()
	while ancestor != screen.interface and ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().grow(1).encloses(rect): return false
		ancestor = ancestor.get_parent()
	return true

func _click(id: String) -> void:
	var button := _control(id) as Button
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

func _extra(id: String) -> void:
	if not _visible(id): await _click("MoreDesk")
	_check(_visible(id), "secondary action available through records " + id)
	await _click(id)

func _shot(id: String) -> void:
	await _frames(8)
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size)).grow(1)
	var overflow: Array[String] = []
	for name in ["StudyBackdrop", "OpenLedger", "JournalTabs", "EstateStatus", "StatusHeader", "ReadingSurface", "DecisionModal", "ManagementWindow"]:
		var panel := _control(name)
		if panel != null and panel.is_visible_in_tree() and not viewport.encloses(panel.get_global_rect()):
			overflow.append(name + " " + str(panel.get_global_rect()))
	for scroll in screen.interface.find_children("*", "ScrollContainer", true, false):
		if not scroll.is_visible_in_tree(): continue
		for child in scroll.get_children():
			if child is Control and not child is ScrollBar and child.size.x > scroll.size.x + 1:
				overflow.append(str(child.get_path()) + " horizontal overflow")
	_check(overflow.is_empty(), "layout fits " + id + ": " + "; ".join(overflow))
	var small: Array[String] = []
	for label in screen.interface.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.get_theme_font_size("font_size") < 18:
			small.append(label.text.left(30))
	_check(small.is_empty(), "readable native type " + id + ": " + "; ".join(small))
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "no whole-window text shrinking " + id)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		_check(shot != null, "rendered " + id)
		_check(shot.save_png("res://tests/output/cabinet_" + id + ".png") == OK, "screenshot saved " + id)
		print("CABINET SCREENSHOT: ", id)

func _check_week_view() -> void:
	var tabs := _control("JournalTabs")
	var destinations: Array[String] = []
	if tabs != null:
		for button in tabs.find_children("nav_*", "Button", true, false):
			if button.is_visible_in_tree() and button.name != "nav_menu": destinations.append(str(button.name))
	destinations.sort()
	_check(destinations == ["nav_boons", "nav_build", "nav_estate"], "only three primary destinations")
	_check(_fully_visible("MoreDesk"), "records accessible without crowding main menu")
	for name in ["CabinetFocus", "CabinetResults", "CabinetProjects", "FocusAction", "NextWeek"]:
		_check(_fully_visible(name), "weekly decision visible without scrolling " + name)
	var body := _control("ReadingSurface")
	var visible_scrollers := 0
	if body != null:
		for scroll in body.find_children("*", "ScrollContainer", true, false):
			if scroll.is_visible_in_tree(): visible_scrollers += 1
	_check(visible_scrollers == 0, "main decision fits on one spread without scroll panes")
	_check(not _visible("job_gather") and not _visible("job_build"), "no routine workforce entry on main")
	_check(not _visible("nav_ledger") and not _visible("nav_people") and not _visible("nav_trade"), "advanced work remains behind records")

func _resolve_free_event() -> void:
	var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
	for i in event.options.size():
		if event.options[i].get("cost", {}).is_empty() and not event.options[i].has("requires_housing"):
			await _click("event_option_%d" % i)
			return
	_check(false, "event offers a free fallback")

func _check_legacy_continue() -> void:
	var legacy := GameSession.new(screen.session.content)
	legacy.start_run(77119, "settler", {"region":"forest", "candidate":0, "relics":[], "tutorial":false})
	legacy.choose_perk(legacy.state.perk_offer[0])
	legacy.choose_event(0)
	legacy.state.assign.gather = 2
	legacy.state.assign.build = 0
	var assignment: Dictionary = legacy.state.assign.duplicate(true)
	var legacy_path := "res://tests/output/cabinet_legacy_%d" % Time.get_ticks_usec()
	var old_store := SaveStore.new(legacy_path)
	_check(old_store.write(legacy.bundle()) == "", "legacy save fixture is valid")
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/cabinet_ui.gd"))
	screen.save_directory = legacy_path
	root.add_child(screen)
	await _frames()
	_check(not screen.load_blocked, "production main accepts earlier saves")
	_check(not screen.session.state.get("cabinet", {}).get("enabled", false), "loading does not silently opt old saves into automatic labor")
	_check(screen.session.state.assign == assignment, "load preserves earlier manual workforce plan")
	var old_resources: Dictionary = screen.session.state.public.duplicate(true)
	var old_facilities: Dictionary = screen.session.state.facilities.duplicate(true)
	await _click("ContinueRun")
	_check(screen.page == "estate" and screen.session.state.week == 1, "old save continues into the current UI")
	_check(screen.session.state.get("cabinet", {}).get("enabled", false), "continuing explicitly adopts automatic administration")
	_check(screen.session.state.public == old_resources and screen.session.state.facilities == old_facilities, "adopting automatic labor preserves existing resources and development")
	await _shot("11_legacy_continue_720")
	await _click("NextWeek")
	_check(screen.session.state.week == 2 and screen.session.state.assign.gather == 8, "continued legacy save can progress with automatic labor")
	_check(screen.store.read().ok, "old save remains readable after current UI saves it")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/cabinet_ui.gd"))
	screen.save_directory = "res://tests/output/cabinet_ui_%d" % Time.get_ticks_usec()
	root.add_child(screen)
	await _frames()
	var cabinet_entrypoint: bool = screen.get_script().resource_path == "res://ui/cabinet_ui.gd"
	_check(cabinet_entrypoint, "compact cabinet regression is explicitly pinned")
	if not cabinet_entrypoint:
		quit(1)
		return
	if screen.session == null:
		_check(false, "main initializes session")
		quit(1)
		return
	await _shot("01_menu_720")
	await _click("NewRun")
	_check(screen.page == "estate" and screen.session.state.get("week", -1) == 1, "one click starts the run without preparation forms")
	if screen.session.state.is_empty():
		quit(1)
		return
	_check(screen.session.state.get("cabinet", {}).get("enabled", false), "new run enables automatic administration")
	_check(not screen.session.state.perk_offer.is_empty(), "first strategic choice is a perk")
	if screen.session.state.perk_offer.is_empty():
		quit(1)
		return
	_check(screen.session.state.active_event != "EV01", "introductory objective is not a second event decision")
	_check(not _visible("PrepareNext") and not _visible("StartRun"), "preparation controls are skipped")
	await _shot("02_initial_perk_720")
	var build := _control("nav_build")
	await _mouse_click(build.get_global_rect().get_center())
	_check(screen.page == "estate", "required choice blocks actual background navigation")
	await _click("InspectEstate")
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == 1 and _visible("DecisionModal"), "unresolved perk prevents time passing")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	_check(screen.session.state.active_event == "" and not _visible("DecisionModal"), "perk leads straight to first weekly decision")
	_check_week_view()
	await _shot("03_first_week_720")
	var money_before: int = screen.session.state.public.money
	var farms_before: int = screen.session.state.facilities.B13
	await _mouse_click(_control("FocusAction").get_global_rect().get_center())
	_check(screen.session.state.orders.count("B13") == 2, "one farm expansion reserves both plots")
	_check(screen.session.state.assign.build == 8, "construction labor assigned automatically")
	_check(screen.session.state.public.money == money_before, "reserved works pay when the week runs")
	_check(screen.session.state.facilities.B13 == farms_before, "reservation is not instant construction")
	await _shot("04_farm_plan_720")
	await _click("NextWeek")
	_check(screen.session.state.week == 2 and screen.session.state.history.size() == 1, "one action advances exactly one week")
	_check(screen.session.state.public.money < money_before, "real construction expenses are charged")
	var work_bars := _control("CabinetProjects").find_children("*", "ProgressBar", true, false)
	_check(work_bars.size() == 1 and work_bars[0].value > 0.0 and work_bars[0].value < work_bars[0].max_value, "partly completed two-plot project shows progress instead of restarting at zero")
	await _shot("05_week_result_720")
	await _click("NextWeek")
	_check(screen.session.state.week == 3 and screen.session.state.facilities.B13 == 6, "automatic labor completes the first objective by week three")
	_check_week_view()
	await _shot("06_farms_complete_720")
	await _click("nav_build")
	_check(not _visible("job_build") and not _visible("job_gather"), "development does not require workforce editing")
	_check(screen.interface.find_children("build_*", "Button", true, false).size() == 3, "development starts with three relevant projects")
	await _shot("07_development_720")
	await _click("AllProjects")
	_check(screen.interface.find_children("build_*", "Button", true, false).size() == 12, "all twelve facilities remain available on demand")
	await _shot("all_projects_720")
	await _click("AllProjects")
	await _click("nav_boons")
	await _shot("08_boons_720")
	await _click("BoonDetails")
	_check(_visible("owned_" + str(screen.session.state.perks[0])), "detailed trait and combination view remains accessible")
	await _shot("boon_details_720")
	await _click("BoonDetails")
	await _click("nav_estate")
	await _click("MoreDesk")
	await _shot("09_records_720")
	await _click("CloseDesk")
	_check_week_view()
	var advisor_security: float = screen.session.state.security
	for destination in ["nav_people", "nav_trade", "nav_ledger", "nav_journey", "nav_archive"]:
		await _extra(destination)
		await _shot("records_" + destination.trim_prefix("nav_") + "_720")
		if destination == "nav_people":
			var actions_before: int = screen.session.state.actions
			await _click("advisor_CH12")
			_check(screen.session.state.cabinet.advisor == "CH12", "advisor appointment persists")
			_check(screen.session.state.security == advisor_security and screen.session.state.actions == actions_before, "appointing advisor does not grant instant benefits or spend an action")
			screen._render()
			await _frames()
			_check(screen.session.state.security == advisor_security, "redrawing advisor screen cannot repeat the benefit")
			await _click("AllAdvisors")
			_check(_visible("advisor_CH03"), "all regular characters remain accessible")
			await _shot("all_advisors_720")
			await _click("AllAdvisors")
		if destination == "nav_trade":
			var quantity: int = clampi(int(screen.session.state.pop) * 2, 1, 200)
			var price: int = screen.session.trade_quote("food", quantity, true)
			var money: int = screen.session.state.public.money
			var stock: float = screen.session.state.public.food
			await _click("supply_food")
			_check(screen.session.state.public.money == money - price, "quick purchase charges exact quoted price")
			_check(screen.session.state.public.food == stock, "quick purchase does not deliver early")
			_check(screen.session.state.shipments.size() == 1, "one purchase creates one cart")
			var cart: Dictionary = screen.session.state.shipments[0]
			_check(cart.asset == "food" and cart.quantity == quantity and cart.arrival == 5, "food package records correct amount and two-week arrival")
			await _click("SupplyDetails")
			_check(_visible("quantity_food"), "manual trade quantity remains available on demand")
			await _shot("trade_details_720")
			await _click("SupplyDetails")
		await _click("nav_estate")
	root.size = Vector2i(1440, 900)
	for destination in ["estate", "build", "boons"]:
		screen._go(destination)
		await _shot("wide_" + destination)
	# A later character event still pauses the run and resolves into the main report.
	screen._go("estate")
	await screen._advance(13)
	await _frames()
	_check(screen.session.state.week == 4, "large legacy advance requests remain one week")
	_check(screen.session.state.security == minf(100, advisor_security + 4), "appointed advisor grants exactly one weekly benefit")
	_check(screen.session.state.cabinet.advisor_week == 3, "advisor benefit is stamped against the processed week")
	var security_after_week: float = screen.session.state.security
	screen._render()
	await _frames()
	_check(screen.session.state.security == security_after_week, "weekly report redraw does not grant a second benefit")
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.active_event == "EV09", "later substantive event remains a decision")
	_check(screen.session.state.shipments.is_empty(), "quick purchase arrives at promised week")
	root.size = Vector2i(1280, 720)
	await _shot("10_event_720")
	await _resolve_free_event()
	_check(not _visible("AcknowledgeDecision") and not _visible("DecisionModal"), "event outcome does not require another confirmation")
	await screen._advance(1)
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == 7 and not screen.session.state.perk_offer.is_empty(), "later weeks still award a new roguelite choice")
	_check(screen.session.state.contract_offer.is_empty(), "simplified run avoids a second contract interruption")
	await _shot("12_second_perk_720")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	_check(screen.session.state.perks.size() == 2 and not _visible("DecisionModal"), "new perk is adopted and returns directly to play")
	_check(screen.store.read().ok, "automatic plan and UI actions produce a valid save")
	await _check_legacy_continue()
	print("CABINET UI: %d checks, %d failures" % [checks, failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
