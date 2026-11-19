extends SceneTree

var screen: Control
var failures := 0
var checks := 0

func _init() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CHRONICLE UI FAIL: ", message)

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

func _shot(id: String) -> void:
	await _frames(8)
	_check(screen.shell.size.x <= root.size.x + 1, "bounded shell " + id)
	_check(screen.shell.size.y <= root.size.y + 1, "bounded vertical shell " + id)
	var header := screen.find_child("StatusHeader", true, false) as Control
	if header != null: _check(header.size.y < 125, "compact status header " + id)
	for window_name in ["ManagementWindow", "DecisionModal"]:
		var window := screen.find_child(window_name, true, false) as Control
		if window != null:
			_check(window.get_global_rect().end.x <= root.size.x and window.get_global_rect().end.y <= root.size.y, "window bounded " + id)
	_check(screen.board != null and screen.board.size == screen.size, "full viewport world " + id)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		_check(shot != null, "rendered " + id)
		shot.save_png("res://tests/output/chronicle_" + id + ".png")

func _run() -> void:
	root.size = Vector2i(1440, 900)
	screen = load("res://ui/main.tscn").instantiate()
	# Preserve coverage for the previous world UI independently of the actual main UI.
	screen.set_script(load("res://ui/world_ui.gd"))
	screen.save_directory = "res://tests/output/chronicle_ui_%d" % Time.get_ticks_usec()
	root.add_child(screen)
	await _frames()
	_check(screen.pixel_ready, "current pixel UI entrypoint")
	_check(ProjectSettings.get_setting("application/config/name") == "변경의 신임 영주가 되었다", "updated game title")
	_check(OS.get_user_data_dir().replace("\\", "/").ends_with("Godot/app_userdata/영주의 사계"), "renaming preserves previous save location")
	_check(screen.theme.get_font("font", "Button") is SystemFont, "normal controls use readable system font")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "resizing does not shrink text")
	for id in screen.session.content.chronicle.characters:
		_check(screen.assets.texture("portrait_" + id) != null, "canonical portrait " + id)
	for building in EstateBoard.BUILDINGS:
		var texture: Texture2D = screen.assets.texture("building_" + building[1])
		_check(texture != null, "separate building texture " + building[0])
		var pixels := texture.get_image()
		_check(pixels.detect_alpha() != Image.ALPHA_NONE, "building transparency " + building[0])
		_check(texture is AtlasTexture and pixels.get_width() == pixels.get_height(), "independent square sprite region " + building[0])
		var sprite: Sprite2D = screen.board.sprites[building[0]]
		var displayed: Vector2 = sprite.texture.get_size() * sprite.scale
		_check(displayed.x <= 180.1 and displayed.y <= 180.1, "new source resolution keeps the legacy scene footprint " + building[0])
	_check(screen.board.sprites.size() == 12, "independent building nodes")
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
	_check(screen.session.state.chronicle and screen.session.state.week == 1, "new run starts")
	_check(screen.find_child("TutorialCard", true, false) != null, "tutorial visible")
	await _shot("05_perks")
	_check(screen.find_child("DecisionBlocker", true, false) != null, "decisions block background input")
	var blocked_button: Button = screen.find_child("nav_build", true, false)
	await _mouse_click(blocked_button.get_global_rect().get_center())
	_check(screen.page == "estate", "modal actually intercepts mouse input behind it")
	await _click("InspectEstate")
	_check(screen.find_child("DecisionModal", true, false) == null, "can inspect world before deciding")
	var paused_week: int = screen.session.state.week
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == paused_week, "unresolved decision blocks time")
	_check(screen.find_child("DecisionModal", true, false) != null, "advance reopens required decision")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	await _shot("06_event")
	var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
	for i in event.options.size():
		if event.options[i].get("cost", {}).is_empty() and not event.options[i].has("requires_housing"):
			await _click("event_option_%d" % i)
			break
	await _shot("06b_event_result")
	await _click("AcknowledgeDecision")
	_check(not screen.board.sprites.B25.visible, "unbuilt lumber workshop absent")
	_check(screen.session.queue_build("B25") == "", "can queue modular workshop")
	screen._render()
	await _frames()
	_check(screen.board.sprites.B25.visible and screen.board.sprites.B25.modulate.a < 1, "construction preview appears on map")
	screen.session.state.orders.erase("B25")
	screen._render()
	await _frames()
	_check(not screen.board.sprites.B25.visible, "cancelled construction disappears")
	await _click("TutorialAction")
	_check(screen.page == "build", "tutorial routes to construction")
	await _click("build_B13")
	await _click("build_B13")
	await _click("TutorialAction")
	_check(screen.construction_tab == "labor", "tutorial routes to labor")
	await _click("BuildPreset")
	await _shot("07_labor")
	await _click("NextWeek")
	await _click("NextWeek")
	_check(screen.session.state.week == 3 and screen.session.state.facilities.B13 == 6, "real construction and time")
	await _click("TutorialAction")
	await _click("CouncilVisit")
	await _click("TutorialAction")
	_check(screen.session.profile.get("tutorial_done", false), "seven tutorial steps finish from real actions")
	await _shot("08_boons")
	await _click("nav_people")
	await _click("person_CH12")
	await _shot("09_people")
	await _click("nav_build")
	await _click("build_tab_facilities")
	await _click("facility_B22")
	await _click("build_B22")
	await _shot("10_build")
	await _click("nav_trade")
	await _shot("11_trade")
	await _click("nav_estate")
	var trade_site: Button = screen.find_child("site_trade", true, false)
	var trade_plate: Control = trade_site.get_node("Nameplate")
	await _mouse_click(trade_plate.get_global_rect().get_center())
	_check(screen.page == "trade", "world landmark opens trade")
	await _click("CloseWindow")
	await _shot("12_estate")
	await _click("nav_archive")
	await _shot("13_archive")
	# 작은 창에서도 레이아웃을 실제로 재계산한다.
	root.size = Vector2i(1280, 720)
	for target in ["estate", "build", "people", "trade", "boons", "archive"]:
		screen._go(target)
		await _shot("compact_" + target)
	# 자동 진행은 새 인물 사건과 계약 선택에서 각각 멈춘다.
	screen._go("estate")
	await screen._advance(13)
	await _frames()
	_check(screen.session.state.week == 5 and screen.session.state.active_event == "EV09", "auto advance stops at Agnes event")
	await _click("event_option_1")
	await _click("AcknowledgeDecision")
	await screen._advance(13)
	await _frames()
	_check(screen.session.state.week == 7, "auto advance stops at first draft and contract")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	await _shot("14_contract")
	await _click("SkipContract")
	_check(screen.session.state.contract_offer.is_empty(), "free contract alternative works")
	var store: SaveStore = screen.store
	_check(store.read().ok, "UI autosave readable")
	# 결과·영구 강화·재시작도 실제 버튼으로 확인한다.
	while screen.session.state.status == "active" and screen.session.state.week < 15:
		if screen.session.state.active_event != "":
			var pending: Dictionary = screen.session.content.events[screen.session.state.active_event]
			for i in pending.options.size():
				if pending.options[i].get("cost", {}).is_empty() and not pending.options[i].has("requires_housing"):
					screen.session.choose_event(i)
					break
		if not screen.session.state.perk_offer.is_empty(): screen.session.choose_perk(screen.session.state.perk_offer[0])
		await screen._advance(1)
	screen.session.settle("은퇴")
	screen._go("result")
	await _shot("15_result")
	await _click("ResultArchive")
	await _click("upgrade_M01")
	_check("M01" in screen.session.profile.upgrades, "buy permanent upgrade")
	screen._go("result")
	await _click("ResultRestart")
	_check(screen.page == "prepare", "loop returns to preparation")
	# 후기 지도에서도 모든 시설이 별도 노드로 보이며 표지판이 클릭 영역 안에 있다.
	screen.session.state.week = 40
	screen.session.state.status = "active"
	screen.session.state.active_event = ""
	screen.session.state.perk_offer = []
	screen.session.state.contract_offer = []
	screen.session.state.tutorial.enabled = false
	for building in EstateBoard.BUILDINGS: screen.session.state.facilities[building[0]] = 6 if building[0] == "B13" else 1
	screen.session._update_goals()
	screen.notice = ""
	screen._go("estate")
	await _frames()
	for i in EstateBoard.BUILDINGS.size():
		var entry: Array = EstateBoard.BUILDINGS[i]
		_check(screen.board.sprites[entry[0]].visible, "completed building visible " + entry[0])
		var marker: Button = screen.board.markers[i]
		var plate: Control = marker.get_node("Nameplate")
		_check(marker.get_global_rect().encloses(plate.get_global_rect()), "nameplate inside click region " + entry[0])
	await _shot("16_all_facilities_winter")
	print("CHRONICLE UI: %d checks, %d failures" % [checks, failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
