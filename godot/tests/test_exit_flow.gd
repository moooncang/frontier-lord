extends SceneTree
## Real UI and save paths; only the final process-exit side effect is replaced.

class ExitProbe:
	extends "res://ui/expedition_ui.gd"
	var exit_count := 0
	func _finish_quit() -> void:
		exit_count += 1

var screen: Control
var checks := 0
var failures := 0
var saved_directory := ""

func _init() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EXIT FLOW FAIL: ", message)

func _frames(count: int = 5) -> void:
	for i in count: await process_frame

func _control(id: String) -> Control:
	return screen.find_child(id, true, false) as Control

func _visible(id: String) -> bool:
	var control := _control(id)
	return control != null and control.is_visible_in_tree()

func _press(id: String) -> void:
	var button := _control(id) as Button
	_check(button != null and button.is_visible_in_tree(), "actual button is visible: " + id)
	if button == null: return
	_check(not button.disabled, "actual button is enabled: " + id)
	_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "actual button is inside viewport: " + id)
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
	await _frames()

func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event)
	await _frames()

func _new_screen() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		await _frames()
	saved_directory = "res://tests/output/exit_flow_%d" % Time.get_ticks_usec()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.set_script(ExitProbe)
	screen.save_directory = saved_directory
	root.add_child(screen)
	await _frames()
	_check(screen.session != null and not screen.load_blocked, "isolated real UI initializes")
	_check(not auto_accept_quit, "window close is handled through the application's save flow")
	# Persist week one, then leave an actual completed week unsaved to verify exit behavior.
	screen.session.start_run(61427, "settler", {"region":"river", "candidate":1, "relics":["seeds","seal"], "tutorial":false, "cabinet":true, "campaign":true, "workcrew":true, "onboarding":false})
	_check(screen.session.choose_perk(str(screen.session.state.perk_offer[0])), "exit fixture chooses its real initial perk")
	_check(screen._save(), "baseline saved in isolated directory")
	_check(screen.session.advance().advanced, "fixture has real unsaved progress")
	screen.page = "menu"
	screen._render()
	await _frames()
	_check(screen.session.state.week == 2 and SaveStore.new(saved_directory).read().bundle.state.week == 1, "fixture separates current progress from previous save")

func _block_save_directory() -> void:
	var path := saved_directory + "_is_a_file"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "create isolated filesystem failure fixture")
	if file != null:
		file.store_string("This test file intentionally occupies the requested save directory.")
		file.close()
	screen.store.directory = path

func _prompt() -> void:
	_check(screen.quit_prompt_open and _visible("QuitSaveFailure"), "failed save leaves a visible recovery choice")
	var visible_prompts := 0
	for node in screen.find_children("QuitSaveFailure", "", true, false):
		if node is Control and node.is_visible_in_tree(): visible_prompts += 1
	_check(visible_prompts == 1, "only one failure prompt exists")
	for id in ["RetryQuit", "CancelQuit", "DiscardQuit"]:
		var button := _control(id) as Button
		_check(button != null and button.is_visible_in_tree() and not button.disabled, "recovery action is available: " + id)
		if button != null: _check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "recovery action is visible without scrolling: " + id)
	_check(screen.exit_count == 0, "failure never exits without a player choice")

func _shot(id: String) -> void:
	await _frames(8)
	var dialog := _control("QuitSaveFailure")
	_check(dialog != null and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(dialog.get_global_rect()), "exit recovery fits " + id)
	if dialog != null:
		for label in dialog.find_children("*", "Label", true, false):
			_check(label.get_theme_font_size("font_size") >= 18, "exit recovery remains readable")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		_check(picture.save_png("res://tests/output/exit_" + id + ".png") == OK, "saved recovery screenshot " + id)

func _normal_button_exit() -> void:
	await _new_screen()
	var sequence: int = screen.store.sequence
	await _press("QuitGame")
	_check(screen.exit_count == 1 and not screen.quit_prompt_open, "title exit button saves and reaches actual exit hook")
	var saved: Dictionary = SaveStore.new(saved_directory).read()
	_check(saved.ok and saved.bundle.state.week == 2 and screen.store.sequence == sequence + 1, "exit persists latest unsaved week before finishing")
	screen._request_quit()
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	screen._retry_quit()
	_check(screen.exit_count == 1 and screen.store.sequence == sequence + 1, "repeated requests while finalizing do not save or exit twice")

func _retry_flow() -> void:
	await _new_screen()
	var sequence: int = screen.store.sequence
	_block_save_directory()
	await _press("QuitGame")
	_prompt()
	_check(screen.store.sequence == sequence, "failed write does not claim a saved generation")
	await _shot("failure_720")
	# Neither repeated close requests nor ordinary redraws should stack or erase recovery.
	for i in 3:
		screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		screen._request_quit()
	await _frames()
	screen._render()
	await _frames()
	_prompt()
	await _press("RetryQuit")
	_prompt()
	_check(screen.store.sequence == sequence, "retry with unchanged failure stays recoverable")
	screen.store.directory = saved_directory
	await _press("RetryQuit")
	var saved: Dictionary = SaveStore.new(saved_directory).read()
	_check(screen.exit_count == 1 and not screen.quit_prompt_open and not _visible("QuitSaveFailure"), "successful retry closes prompt and finishes exit")
	_check(saved.ok and saved.bundle.state.week == 2 and screen.store.sequence == sequence + 1, "retry writes actual pending progress once")

func _cancel_and_window_close() -> void:
	await _new_screen()
	screen._go("estate")
	await _frames()
	_block_save_directory()
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	_prompt()
	var week: int = screen.session.state.week
	_control("RetryQuit").grab_focus()
	await _key(KEY_SPACE)
	await _key(KEY_ENTER)
	_check(screen.quit_prompt_open and screen.exit_count == 0, "keyboard retry stays recoverable while the save failure persists")
	await _press("nav_build")
	_check(screen.session.state.week == week and screen.page == "estate", "recovery blocks keyboard time progression and background pointer navigation")
	root.size = Vector2i(1440, 900)
	await _frames()
	await _shot("failure_900")
	await _key(KEY_ESCAPE)
	_check(screen.exit_count == 0 and not screen.quit_prompt_open and not _visible("QuitSaveFailure"), "cancel returns to the live game")
	screen.store.directory = saved_directory
	await _press("NextWeek")
	_check(screen.session.state.week == week + 1, "cancel restores normal gameplay")
	var sequence: int = screen.store.sequence
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	_check(screen.exit_count == 1 and screen.store.sequence == sequence + 1, "window close uses the same save-and-exit path after cancellation")

func _discard_flow() -> void:
	root.size = Vector2i(1280, 720)
	await _new_screen()
	var sequence: int = screen.store.sequence
	var slot := saved_directory.path_join("slot_%d.json" % (sequence % 2))
	var original := FileAccess.get_file_as_string(slot)
	_block_save_directory()
	screen.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	_prompt()
	await _press("DiscardQuit")
	_check(screen.exit_count == 1 and not screen.quit_prompt_open, "explicit discard always allows exit after a failed save")
	_check(screen.store.sequence == sequence and FileAccess.get_file_as_string(slot) == original, "discard does not overwrite the last good save")
	var saved: Dictionary = SaveStore.new(saved_directory).read()
	_check(saved.ok and saved.bundle.state.week == 1, "discard retains previous saved progress exactly")

func _invalid_state_recovery() -> void:
	await _new_screen()
	screen.session.profile.points = -1
	screen._request_quit()
	await _frames()
	_prompt()
	await _press("CancelQuit")
	_check(screen.exit_count == 0, "invalid-state save failure can be cancelled")
	screen.session.profile.points = 0
	screen._request_quit()
	await _frames()
	_check(screen.exit_count == 1 and SaveStore.new(saved_directory).read().bundle.state.week == 2, "corrected state can save and exit after a validation failure")

func _blocked_load_exit() -> void:
	screen.queue_free()
	await _frames()
	saved_directory = "res://tests/output/exit_corrupt_%d" % Time.get_ticks_usec()
	_check(DirAccess.make_dir_recursive_absolute(saved_directory) == OK, "create isolated corrupt-load fixture")
	var path := saved_directory.path_join("slot_0.json")
	var broken := "Intentionally invalid save fixture; preserve these bytes."
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(broken)
	file.close()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.set_script(ExitProbe)
	screen.save_directory = saved_directory
	root.add_child(screen)
	await _frames()
	_check(screen.load_blocked and screen.session.state.is_empty(), "damaged load cannot create a playable unsaved run")
	await _press("QuitGame")
	_check(screen.exit_count == 1 and not screen.quit_prompt_open, "damaged load still permits leaving the application")
	_check(FileAccess.get_file_as_string(path) == broken, "leaving a damaged-load screen does not overwrite its files")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _normal_button_exit()
	await _retry_flow()
	await _cancel_and_window_close()
	await _discard_flow()
	await _invalid_state_recovery()
	await _blocked_load_exit()
	print("EXIT FLOW: %d checks, %d failures" % [checks, failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
