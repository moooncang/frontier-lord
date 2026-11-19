extends SceneTree
## 같은 Scene/버튼 신호를 사용하는 UI 통합 테스트. 렌더러가 있으면 PNG도 저장한다.

var failures := 0
var checks := 0
var screen: Control


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("UI FAIL: ", message)


func _frames(count: int = 4) -> void:
	for i in count:
		await process_frame


func _click(name_value: String) -> void:
	var button := screen.find_child(name_value, true, false) as Button
	_check(button != null, "button exists " + name_value)
	if button != null:
		_check(not button.disabled, "button enabled " + name_value)
		button.pressed.emit()
	await _frames()


func _shot(name_value: String) -> void:
	await _frames()
	_check(screen.shell.size.x <= 1441, "shell width bounded on " + name_value)
	var footer := screen.find_child("Footer", true, false) as Control
	_check(footer != null and footer.size.y < 50, "footer remains horizontal on " + name_value)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image != null and not image.is_empty(), "rendered " + name_value)
		if image != null and not image.is_empty():
			image.save_png("res://tests/output/" + name_value + ".png")


func _run() -> void:
	screen = load("res://ui/main.tscn").instantiate()
	# 기존 저장/명령 화면의 회귀 검증. 현재 진입 화면은 test_chronicle_ui에서 검증한다.
	screen.set_script(load("res://ui/game_ui.gd"))
	screen.save_directory = "res://tests/output/ui_%d" % Time.get_ticks_usec()
	root.add_child(screen)
	await _frames()
	_check(screen.session != null, "session initialized")
	for key in screen.assets.paths:
		if key == "font_body": continue
		_check(screen.assets.texture(key) != null, "delivered asset loads " + key)
	await _shot("01_menu")
	var menu_view := screen.find_child("SettlementView",true,false) as EstateView
	_check(menu_view.size.y <= (menu_view.get_parent() as Control).size.y+1, "menu image stays inside layout slot")
	_check(menu_view.global_position.y > 120, "menu image does not overlap title")
	screen.seed_input.text = "12345"
	await _click("start_run")
	_check(screen.session.state.week == 1, "new run at week one")
	var auto := screen.find_child("auto_season", true, false) as Button
	_check(auto.disabled, "automatic advance is disabled during unresolved decision")
	await _click("nav_build")
	await _click("next_week")
	_check(screen.page == "estate" and screen.session.state.week == 1, "pending decision action navigates without advancing time")
	_check(screen.main_scroll.scroll_vertical == 0, "decision navigation keeps portrait and title visible")
	var landscape := screen.find_child("SettlementView",true,false) as EstateView
	_check(landscape != null and landscape.backdrop != null, "real seasonal background connected")
	_check(landscape.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pixel background uses nearest filtering")
	_check(absf(landscape.size.x / landscape.size.y - 16.0/9.0) < 0.02, "background preserves 16:9 composition")
	_check(landscape.size.y <= (landscape.get_parent() as Control).size.y+1, "estate image stays inside layout slot")
	await _shot("02_estate")
	await _click("event_option_0")
	await _click("nav_build")
	await _click("build_B13")
	await _click("build_B13")
	screen.main_scroll.scroll_vertical = 250
	await _frames()
	var previous_scroll: int = screen.main_scroll.scroll_vertical
	await _click("build_B22")
	_check(abs(screen.main_scroll.scroll_vertical - previous_scroll) < 3, "build action preserves scroll position")
	screen.main_scroll.scroll_vertical = 0
	var workforce := screen.find_child("job_build", true, false) as SpinBox
	_check(workforce != null, "construction labor field")
	workforce.value = 8
	_check(screen.session.state.assign.build == 8, "labor field updates state")
	_check(screen.labor_fields.build.text.contains("8명"), "labor preview updates immediately after editing")
	_check(screen.labor_fields.fuel.text.contains("0명"), "preview does not allocate labor to absent workshop")
	await _shot("03_construction")
	await _click("next_week")
	await _click("next_week")
	_check(screen.session.state.facilities.B13 == 6, "button orders construct two fields")
	await _click("nav_trade")
	var quantity := screen.find_child("quantity_food",true,false) as SpinBox
	quantity.value = 50
	var buy := screen.find_child("buy_food",true,false) as Button
	_check(buy.text.contains(screen._money(screen.session.trade_quote("food",50,true))), "trade price updates on quantity change")
	var before_money: int = screen.session.state.public.money
	await _click("buy_food")
	_check(screen.session.state.shipments.back().quantity == 50, "trade uses selected quantity")
	_check(screen.session.state.public.money == before_money-screen.session.trade_quote("food",50,true), "selected trade charges displayed price")
	await _click("buy_food")
	await _click("buy_food")
	_check((screen.find_child("buy_food",true,false) as Button).disabled, "full carts disable purchases")
	_check((screen.find_child("trade_reason_food",true,false) as Label).text.contains("수레 3대"), "full carts explain why transaction is blocked")
	await _shot("04_trade")
	await _click("nav_people")
	await _shot("05_people")
	await _click("nav_ledger")
	await _shot("06_ledger")
	await _click("nav_archive")
	await _shot("07_archive")
	await _click("nav_estate")
	await _click("auto_season")
	await _frames(20)
	_check(screen.session.state.week == 9 and screen.session.state.active_event == "EV02", "auto-run stops at new event")
	_check(not screen.busy, "auto-run releases controls")
	var saved: Dictionary = screen.store.read()
	_check(saved.ok and saved.bundle.state.week == 9, "UI autosave contains latest turn")
	# 작은 지원 창에서도 동일 씬의 레이아웃을 검증한다.
	root.size = Vector2i(1280, 720)
	await _shot("08_compact")
	_check(screen.shell.get_combined_minimum_size().x <= 1280, "compact layout minimum width")
	for target_page in ["build","trade","people"]:
		await _click("nav_"+target_page)
		await _shot("compact_"+target_page)
		_check(screen.shell.get_combined_minimum_size().x <= 1280, "compact page width " + target_page)
	await _click("nav_estate")
	root.size = Vector2i(1440, 900)
	# 일반 게임 서비스로 남은 치세를 진행하여 결산 화면까지 렌더링한다.
	var guard := 0
	while screen.session.state.status == "active" and guard < 70:
		guard += 1
		if screen.session.state.active_event != "":
			var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
			for i in event.options.size():
				if event.options[i].get("cost", {}).is_empty() and not event.options[i].has("requires_housing"):
					screen._resolve(i)
					break
		if not screen.session.state.perk_offer.is_empty():
			screen.session.choose_perk(screen.session.state.perk_offer[0])
		await screen._advance(13)
	_check(screen.session.state.status == "finalized", "UI reaches real conclusion")
	await _shot("09_conclusion")
	# 에셋 manifest는 실제 Godot Texture2D 리소스를 연결할 수 있다.
	var texture := GradientTexture2D.new()
	texture.gradient = Gradient.new()
	var texture_path := "res://tests/output/asset_probe.tres"
	_check(ResourceSaver.save(texture, texture_path) == OK, "write texture fixture")
	var bank := AssetBank.new({"probe": texture_path})
	_check(bank.texture("probe") != null and bank.texture("absent") == null, "asset load and missing fallback")
	var view := EstateView.new()
	view.backdrop = bank.texture("probe")
	screen.add_child(view)
	view.size = Vector2(500, 290)
	await _frames()
	view.queue_free()
	print("UI: %d checks, %d failures" % [checks, failures])
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
