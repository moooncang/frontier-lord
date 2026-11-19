extends SceneTree
## Production realm UI: pointer/keyboard input, clipped hit areas, tutorial and feedback.
## Save fixtures live under tests/output; this test never reads the player's saves.

class ExitProbe:
	extends "res://ui/realm_ui.gd"
	var exit_count := 0
	func _finish_quit() -> void:
		exit_count += 1

var screen: Control
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("REALM PLAYFLOW FAIL: ", message)
	return ok

func _frames(count: int = 6) -> void:
	for frame in count: await process_frame

func _control(id: String) -> Control:
	return screen.find_child(id, true, false) as Control

func _visible(id: String) -> bool:
	var item := _control(id)
	return item != null and item.is_visible_in_tree()

func _inside(item: Control) -> bool:
	if item == null or not item.is_visible_in_tree(): return false
	var rect := item.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(rect): return false
	var parent := item.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents and not parent.get_global_rect().grow(1).encloses(rect): return false
		parent = parent.get_parent()
	return true

func _text(item: Node) -> String:
	if item == null: return ""
	var lines: Array[String] = []
	if item is Label or item is Button: lines.append(item.text)
	for child in item.get_children(): lines.append(_text(child))
	return "\n".join(lines)

func _pointer(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
	await _frames()

func _navigate_to_action(id: String) -> void:
	if is_instance_valid(screen.current_modal): return
	if id in ["nav_policy","nav_boons","nav_people","nav_sanctuary"] and not _visible(id):
		await _click("MoreActions")
	elif id == "BackEstate" and not _visible(id) and screen.page == "build":
		await _click("nav_estate")
	elif id.begins_with("lot_") or id.begins_with("build_") or id == "RelicShrine":
		var facility := id.trim_prefix("lot_").trim_prefix("build_")
		var district := "civic" if id == "RelicShrine" else RealmBoard.district_for(facility)
		if screen.page != "build": await _click("nav_build")
		if screen.active_district != district: await _click("district_"+district)
		if id == "RelicShrine": return
		if not _visible("lot_"+facility): await _click("MapPlansToggle")
		if id.begins_with("build_") and screen.selected_lot != facility: await _click("lot_"+facility)


func _click(id: String) -> bool:
	await _navigate_to_action(id)
	if id == "BackEstate" and screen.page == "estate" and not _visible(id): return true
	var button := _control(id) as BaseButton
	if not _check(button != null, "button exists: " + id): return false
	if not _check(_inside(button), "pointer can reach unclipped button: " + id): return false
	if not _check(not button.disabled, "button is enabled: " + id): return false
	await _pointer(button.get_global_rect().get_center())
	return true

func _reveal(id: String) -> void:
	await _navigate_to_action(id)
	var item := _control(id)
	if item == null: return
	var parent := item.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(item)
		parent = parent.get_parent()
	await _frames()

func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event)
	await _frames()

func _shot(tag: String) -> void:
	await _frames(8)
	if screen.page == "estate" and screen.selected_lot == "" and screen.side_page == "overview" and not is_instance_valid(screen.current_modal):
		_overview_bounds(tag)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty(), "rendered " + tag)
	if picture != null and not picture.is_empty():
		_check(picture.save_png("res://tests/output/realm_playflow_" + tag + ".png") == OK, "saved screenshot " + tag)

func _overview_bounds(tag: String) -> void:
	var dock := _control("RunDock")
	if dock == null: return
	var bottom: float = dock.get_parent().get_global_rect().position.y - 4.0
	for id in ["OperatingWorkspace","OfficeDesk"]:
		var workspace := _control(id)
		if workspace == null: continue
		var frame: Rect2 = workspace.get_parent().get_global_rect()
		for item in workspace.find_children("*", "Control", true, false):
			if not (item is Label or item is BaseButton) or not item.is_visible_in_tree(): continue
			var rect: Rect2 = item.get_global_rect()
			_check(frame.grow(1).encloses(rect) and rect.end.y <= bottom, "overview text/action stays above the dock and inside its panel [%s]: %s" % [tag, item.name])
	var toast := _control("ActionNotice")
	if toast != null:
		_check(toast.size.y <= 90,"action notice stays compact")
		for id in ["WorkcrewArea","OfficeConstruction","TurnDetails","NextWeek"]:
			var action := _control(id)
			if action != null: _check(not toast.get_global_rect().intersects(action.get_global_rect()),"action notice leaves operating control uncovered: "+id)

func _guide(step: int) -> bool:
	await _frames(8)
	var lesson: Dictionary = screen._tutorial_lesson()
	var expected: bool = _check(lesson.active and int(lesson.step) == step, "tutorial stage %d is active" % step)
	_check(_visible("TutorialCoach"), "tutorial coach remains present at stage %d" % step)
	_check(_inside(_control(str(lesson.target_id))), "tutorial target is within viewport and scroll clip at stage %d: %s" % [step, lesson.target_id])
	if step > 0:
		var coach := _control("TutorialCoach")
		var target := _control(str(lesson.target_id))
		if coach != null and target != null:
			_check(not coach.get_parent().get_global_rect().intersects(target.get_global_rect()), "coach does not cover its target at stage %d" % step)
	return expected

func _fresh(tag: String, exit_probe: bool = false) -> void:
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	if exit_probe: screen.set_script(ExitProbe)
	screen.save_directory = "res://tests/output/realm_playflow_%s_%d" % [tag, Time.get_ticks_usec()]
	root.add_child(screen)
	await _frames()
	if exit_probe:
		_check(screen.get_script().get_base_script().resource_path == "res://ui/realm_ui.gd", "exit probe keeps the production realm input/controller and replaces only process exit")
	else:
		_check(screen.get_script().resource_path == "res://ui/main.gd" and screen.get_script().get_base_script().resource_path == "res://ui/realm_ui.gd", "test exercises the production realm controller")

func _start(guide: bool) -> void:
	await _click("NewRun")
	screen.draft_seed = 61427
	screen.guide_enabled = guide
	await _click("PrepareNext")
	await _click("PrepareNext")
	await _click("StartRun")
	_check(RealmRules.enabled(screen.session.state), "real new-run setup enables realm rules")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _fresh("guided")
	await _start(true)
	await _guide(0)
	await _shot("01_perk_720")
	var offers: Array = screen.session.state.perk_offer
	if offers.is_empty():
		await _finish()
		return
	await _click("perk_" + str(offers[mini(1, offers.size() - 1)]))
	if "--board-only" in OS.get_cmdline_user_args():
		await _board_contract()
		await _finish()
		return
	await _guide(1)
	await _shot("02_start_720")
	await _click("lot_B16")
	await _guide(1)
	_check(screen._tutorial_lesson().target_id == "CloseLot", "tutorial guides back from an unrelated selected facility")
	await _shot("02_detour_lot_720")
	await _click("CloseLot")
	await _click("side_tab_growth")
	await _guide(1)
	_check(screen._tutorial_lesson().target_id == "nav_build", "tutorial guides back to construction from the growth detour")
	await _click("nav_build")
	await _guide(1)
	await _guided_construction()
	await _plans_and_tabs()
	await _board_contract()
	await _growth_unlock()
	await _catalog_quote()
	await _modal_decisions()
	await _exit_recovery()
	await _finish()

func _guided_construction() -> void:
	var state: Dictionary = screen.session.state
	_check(_visible("LotPanel") and screen.page == "build", "approval tutorial selects the actual farm site")
	var stock: Dictionary = state.public.duplicate(true)
	await _click("build_B13")
	_check(state.orders.count("B13") == 2 and state.public == stock, "approval reserves two farms without charging before the week")
	await _guide(2)
	await _shot("03_reserved_720")
	var sequence: int = screen.store.sequence
	await _click("NextWeek")
	_check(int(state.week) == 2 and screen.store.sequence > sequence, "real week action advances and writes a new save generation")
	_check(SaveStore.valid(screen.session.bundle()), "first construction week remains saveable")
	await _guide(3)
	_check(_visible("WeekResult") and _inside(_control("TurnDetails")), "weekly result and details action are immediately reachable")
	await _shot("04_first_result_720")
	var before_review := JSON.stringify(state)
	await _click("TurnDetails")
	_check(_visible("CloseTurnDetails") and Onboarding.current(state).step == 3, "opening the receipt does not falsely complete result review")
	var week: int = state.week
	await _key(KEY_SPACE)
	await _click("nav_build")
	_check(int(state.week) == week and screen.page == "estate" and _visible("CloseTurnDetails"), "receipt blocks time shortcuts and background navigation")
	await _shot("05_receipt_720")
	await _click("ReceiptBreakdown")
	_check(_visible("CloseTurnDetails") and Onboarding.current(state).step == 3, "opening the full ledger keeps the current result review pending")
	await _shot("05_receipt_breakdown_720")
	await _click("CloseTurnDetails")
	_check(Onboarding.current(state).step >= 4, "closing the actual receipt acknowledges review")
	var economic_before: Dictionary = JSON.parse_string(before_review)
	economic_before.erase("onboarding")
	var economic_after: Dictionary = JSON.parse_string(JSON.stringify(state))
	economic_after.erase("onboarding")
	_check(economic_before == economic_after, "review acknowledgement does not grant resources or run time")
	if int(state.facilities.get("B13", 0)) < 6:
		await _guide(4)
		await _click("NextWeek")
	_check(int(state.facilities.get("B13", 0)) == 6, "following the tutorial completes both planned farms")
	await _guide(5)
	_check(_text(_control("WeekResult")).contains("완공"), "farm completion has persistent visible feedback")
	await _shot("06_complete_720")
	var policy: String = "food" if state.workcrew.policy != "food" else "balanced"
	var balance: Dictionary = state.public.duplicate(true)
	await _click("crew_" + policy)
	_check(Onboarding.current(state).completed and not _visible("TutorialCoach"), "a real operating choice completes all six tutorial stages")
	_check(state.workcrew.policy == policy and state.public == balance, "policy choice takes effect as a plan without granting resources")

func _plans_and_tabs() -> void:
	await _click("nav_build")
	await _click("district_food")
	var board: RealmBoard = screen.realm_board
	_check(not board.show_plans and board.lots.size() == 22, "settled view keeps the full model without showing every future building")
	_check(_visible("lot_B13") and not _visible("lot_B19"), "built farms are visible and locked future buildings are hidden")
	var open: Button = board.lots.B16
	_check(open.visible and not open.get_node("Art").visible and not open.get_node("Plate").visible and open.get_node("Chip").visible, "an open lot is a small build marker on terrain")
	await _click("MapPlansToggle")
	_check(screen.realm_board.show_plans and _visible("lot_B19") and screen.realm_board.lots.B16.get_node("Art").visible, "plan toggle reveals future facility art and locked lots")
	await _shot("07_plans_720")
	await _click("lot_B19")
	_check(_visible("LotPanel") and _text(_control("LotPanel")).contains("잠김"), "actual locked-lot click explains the unlock condition")
	await _click("CloseLot")
	await _click("MapPlansToggle")
	_check(not screen.realm_board.show_plans and not _visible("lot_B19"), "closing plans restores the settled view")
	await _click("nav_estate")
	for tab in ["overview", "projects", "growth"]:
		await _click("side_tab_" + tab)
		await _shot("08_tab_%s_720" % tab)
	await _click("side_tab_overview")
	for id in ["WorkcrewArea", "WeekResult", "TurnDetails", "NextWeek"]:
		_check(_inside(_control(id)), "overview essential area is unclipped at 720: " + id)
	root.size = Vector2i(1440, 900)
	await _frames(10)
	for id in ["WorkcrewArea", "WeekResult", "TurnDetails", "NextWeek"]:
		_check(_inside(_control(id)), "overview essential area is unclipped at 900: " + id)
	await _shot("09_overview_900")
	await _click("side_tab_projects")
	await _shot("10_projects_900")
	await _click("side_tab_growth")
	await _shot("11_growth_900")
	await _click("side_tab_overview")
	root.size = Vector2i(1280, 720)
	await _frames(10)

func _board_contract() -> void:
	var fixture := RealmBoard.new()
	fixture.position = Vector2(28, 152)
	fixture.size = Vector2(788, 478)
	root.add_child(fixture)
	var state: Dictionary = screen.session.state
	var original := JSON.stringify(state)
	var chosen := {"id":""}
	fixture.lot_selected.connect(func(id: String): chosen.id = id)
	fixture.configure(screen.assets, state, screen.session.content, "B19", false)
	await _frames()
	_check(fixture.lots.B19.visible and fixture.lots.B19.get_node("Art").visible, "selected locked lot remains visible without plan mode")
	await _pointer(fixture.lots.B19.get_global_rect().get_center())
	_check(fixture.lots.B19.disabled and chosen.id == "", "noninteractive board blocks actual selection")
	fixture.configure(screen.assets, state, screen.session.content, "B19", true)
	await _frames()
	await _pointer(fixture.lots.B19.get_global_rect().get_center())
	_check(chosen.id == "B19", "interactive board emits selection through an actual click")
	fixture.flash_lot("B13")
	await _frames()
	_check(fixture.lots.B13.get_node_or_null("CompletionFlash") != null, "completion pulse starts on the actual built lot")
	fixture.flash_lot("B13")
	await _frames()
	_check(fixture.lots.B13.find_children("CompletionFlash", "Panel", false, false).size() == 1, "repeated pulse replaces its predecessor")
	await create_timer(1.1).timeout
	_check(fixture.lots.B13.get_node_or_null("CompletionFlash") == null, "completion pulse clears itself after one second")
	_check(JSON.stringify(state) == original, "map visibility, selection and pulse never mutate the run")
	root.remove_child(fixture)
	fixture.queue_free()
	await _frames()

func _catalog_quote() -> void:
	await _fresh("catalog")
	await _start(false)
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	await _click("nav_build")
	await _reveal("build_B13")
	var button := _control("build_B13")
	var card := button.get_parent() if button != null else null
	var copy := _text(card)
	var offer := CabinetActions.offer(screen.session, "B13")
	_check(int(offer.count) == 2 and copy.contains("8금") and copy.contains("목재 16") and copy.contains("도구 2"), "first catalog farm offer exposes the full two-plot cost")
	_check(copy.contains("2구획") or copy.contains("×2") or copy.contains("2개"), "catalog states the quantity that the button will reserve")
	await _shot("12_catalog_quote_720")
	var stock: Dictionary = screen.session.state.public.duplicate(true)
	await _click("build_B13")
	_check(screen.session.state.orders.count("B13") == 2 and screen.session.state.public == stock, "catalog approval matches quoted quantity and delays payment")
	var held := RealmRules.held(screen.session.state, screen.session.content)
	_check(int(held.money) == int(offer.cost.money) and int(held.wood) == int(offer.cost.wood) and int(held.tools) == int(offer.cost.tools), "actual reserved costs equal the visible quote")
	await _click("nav_build")
	await _reveal("build_B16")
	await _click("build_B16")
	await _click("side_tab_projects")
	await _reveal("promote_order_2")
	await _click("promote_order_2")
	_check(screen.session.state.orders.size() == 3 and screen.session.state.orders[0] == "B16" and screen.session.state.orders.count("B13") == 2, "priority action moves the selected reservation first without losing or duplicating projects")
	var saved: Dictionary = SaveStore.new(screen.store.directory).read()
	_check(saved.ok and saved.bundle.state.orders[0] == "B16", "chosen construction priority persists in the real save")
	_check(SaveStore.valid(screen.session.bundle()), "catalog and priority changes preserve valid saves")

func _settle() -> void:
	for attempt in 10:
		await _frames()
		var relics: Array = screen.session.state.get("realm", {}).get("sanctuary", {}).get("offer", [])
		if _visible("AcknowledgeOutcome"):
			await _click("AcknowledgeOutcome")
		elif _visible("RelicAcquiredContinue"):
			await _click("RelicAcquiredContinue")
		elif not relics.is_empty() and _visible("take_relic_" + str(relics[0])):
			await _click("take_relic_" + str(relics[0]))
		elif _visible("CloseSeasonResult"):
			await _click("CloseSeasonResult")
		elif not screen.session.state.perk_offer.is_empty():
			await _click("perk_" + str(screen.session.state.perk_offer[0]))
		elif screen.session.state.active_event != "":
			var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
			var selected := -1
			for index in event.options.size():
				if screen.session.option_error(event.options[index]) == "":
					selected = index
					break
			if not _check(selected >= 0, "pending event retains a usable choice"): return
			var id := "event_option_%d" % selected
			await _reveal(id)
			await _click(id)
		elif not screen.session.state.get("contract_offer", []).is_empty():
			await _click("SkipContract")
		else: return
	_check(false, "pending decisions settle within ten real actions")

func _growth_unlock() -> void:
	_check(not _visible("lot_B27"), "quarry is hidden until its prerequisite is built")
	await _click("lot_B25")
	await _click("build_B25")
	await _click("crew_build")
	for attempt in 3:
		if int(screen.session.state.facilities.get("B25", 0)) > 0: break
		await _click("NextWeek")
		await _settle()
	_check(int(screen.session.state.facilities.get("B25", 0)) == 1, "actual labor and week progression complete the logging camp")
	await _click("nav_build")
	await _click("district_industry")
	_check(_visible("lot_B27") and RealmBoard.lot_kind(screen.session.state, screen.session.content, "B27") == "open", "completing the logging camp unlocks a new quarry marker on the map")
	await _click("MapPlansToggle")
	_check(screen.realm_board.lots.B27.get_node("Art").visible, "unlocked facility art can be inspected in plan mode")
	await _shot("12_unlocked_720")
	await _click("MapPlansToggle")

func _exit_recovery() -> void:
	await _fresh("exit", true)
	await _start(false)
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	var directory: String = screen.store.directory
	var blocked := directory + "_is_a_file"
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	if not _check(file != null, "isolated save-failure fixture opens"): return
	file.store_string("save failure fixture")
	file.close()
	screen.store.directory = blocked
	var week: int = screen.session.state.week
	var sequence: int = screen.store.sequence
	await _click("RunHelp")
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	_check(_visible("QuitSaveFailure") and screen.quit_prompt_open and screen.exit_count == 0, "window close on the real realm controller offers recovery after a failed save")
	for id in ["RetryQuit", "CancelQuit", "DiscardQuit"]:
		_check(_inside(_control(id)), "exit recovery action is fully visible: " + id)
	await _shot("13_exit_failure_720")
	await _click("CancelQuit")
	_check(not screen.quit_prompt_open and _visible("CloseHelp") and screen.exit_count == 0, "cancel closes only the exit prompt and preserves the preexisting help modal")
	await _key(KEY_ESCAPE)
	_check(not _visible("CloseHelp"), "help can be closed normally after cancelling exit")
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	_control("RetryQuit").grab_focus()
	await _key(KEY_SPACE)
	await _key(KEY_ENTER)
	await _click("nav_build")
	await _key(KEY_B)
	_check(screen.quit_prompt_open and screen.page == "estate" and int(screen.session.state.week) == week, "failed-save recovery blocks realm B shortcut, week shortcuts, and background mouse actions")
	_check(screen.store.sequence == sequence and screen.exit_count == 0, "failed retries do not claim a saved generation or exit")
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(screen.find_children("QuitSaveFailure", "", true, false).size() == 1, "repeated window close never stacks exit prompts")
	root.size = Vector2i(1440, 900)
	await _frames()
	await _shot("14_exit_failure_900")
	await _key(KEY_ESCAPE)
	_check(not screen.quit_prompt_open and screen.exit_count == 0, "Escape returns to the realm without discarding or exiting")
	screen.store.directory = directory
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	_check(screen.exit_count == 1 and screen.store.sequence == sequence + 1 and not screen.quit_prompt_open, "restored storage saves and reaches the exit hook exactly once")
	var saved: Dictionary = SaveStore.new(directory).read()
	_check(saved.ok and int(saved.bundle.state.week) == week, "successful realm window-close persists the current run")
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(screen.exit_count == 1 and screen.store.sequence == sequence + 1, "duplicate finalized requests do not save or exit twice")

func _modal_decisions() -> void:
	screen.session.state.active_event = "RV_RAID"
	screen.decision_hidden = false
	screen._go("estate")
	await _frames()
	_check(_visible("EventChoices"), "a real realm threat opens its choice modal")
	var week: int = screen.session.state.week
	# Space on a focused choice intentionally confirms that choice. Release it here
	# to exercise the background time shortcut instead of the modal's own action.
	var focused := root.gui_get_focus_owner()
	if focused != null: focused.release_focus()
	await _key(KEY_SPACE)
	await _key(KEY_B)
	await _click("MoreActions")
	_check(int(screen.session.state.week) == week and screen.page == "estate" and _visible("EventChoices"), "event modal blocks background keyboard and pointer commands")
	await _shot("13_event_720")
	await _reveal("event_option_1")
	await _click("event_option_1")
	_check(_visible("OutcomeVerdict") and _visible("AcknowledgeOutcome"), "chance selection shows its actual outcome before play resumes")
	await _key(KEY_B)
	await _click("nav_build")
	_check(screen.page == "estate" and _visible("AcknowledgeOutcome"), "outcome blocks background navigation")
	await _shot("13_outcome_720")
	await _key(KEY_ESCAPE)
	_check(not _visible("AcknowledgeOutcome") and int(screen.session.state.week) == week, "Escape acknowledges the outcome without advancing time")
	_check(SaveStore.valid(screen.session.bundle()), "event decision and result stay saveable")

func _finish() -> void:
	print("REALM PLAYFLOW: %d checks, %d failures" % [checks, failures])
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await _frames()
	quit(1 if failures > 0 else 0)
