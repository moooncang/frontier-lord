extends Control
## 화면은 명령만 발행한다. 경제·결산·저장은 별도 모듈이다.

const JOBS := {"gather":"채집", "build":"건설", "logging":"벌목", "quarry":"채석", "garden":"채소밭", "fuel":"장작 가공", "milling":"제분"}
const RESOURCES := {"food":"식량", "wood":"목재", "stone":"석재", "tools":"도구", "fuel":"장작"}
const PAGES := {"estate":"영지 전경", "build":"건설과 노동", "trade":"여울 교역소", "people":"사람과 통치", "ledger":"장부와 기록", "archive":"가문 강화"}

@export var save_directory := "user://saves"
var session: GameSession
var store: SaveStore
var assets: AssetBank
var shell: MarginContainer
var page := "menu"
var notice := ""
var advance_error := ""
var busy := false
var load_blocked := false
var quit_prompt_open := false
var quit_error := ""
var quit_layer: CanvasLayer
var quit_finalizing := false
var seed_input: LineEdit
var origin_pick: OptionButton
var notice_label: Label
var forecast: Dictionary = {}
var main_scroll: ScrollContainer
var rendered_page := ""
var scroll_positions: Dictionary = {}
var report_open := false
var trade_quantities: Dictionary = {}
var labor_summary: Label
var labor_actual: Label
var labor_fields: Dictionary = {}


func _ready() -> void:
	var data := Content.load_all()
	var errors := Content.validate(data)
	if not errors.is_empty():
		push_error(str(errors))
		return
	session = GameSession.new(data)
	store = SaveStore.new(save_directory)
	assets = AssetBank.new(data.assets)
	theme = GameTheme.create(assets.body_font())
	var saved := store.read()
	if saved.ok:
		session.profile = saved.bundle.profile
		session.state = saved.bundle.state
		if saved.recovered:
			notice = "이전의 정상 저장에서 기록을 복구했습니다."
	elif saved.get("found", false):
		notice = saved.error
		load_blocked = true
	_render()
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()


func _request_quit() -> void:
	if quit_finalizing or quit_prompt_open: return
	# Failed loads have no new playable state to write over the existing files.
	if session == null or load_blocked:
		_complete_quit()
		return
	if _save():
		_complete_quit()
		return
	quit_error = notice
	quit_prompt_open = true
	_exit_failure_dialog()


func _retry_quit() -> void:
	if not quit_prompt_open or quit_finalizing: return
	if _save():
		_complete_quit()
	else:
		quit_error = notice
		var error_label := quit_layer.find_child("QuitSaveError",true,false) as Label
		if error_label != null: error_label.text = quit_error


func _cancel_quit() -> void:
	_clear_quit_prompt()


func _discard_and_quit() -> void:
	# Only the explicitly labelled button takes this path. Existing slots remain intact.
	if quit_prompt_open: _complete_quit()


func _complete_quit() -> void:
	if quit_finalizing: return
	quit_finalizing = true
	_clear_quit_prompt()
	_finish_quit()


func _finish_quit() -> void:
	get_tree().quit()


func _clear_quit_prompt() -> void:
	quit_prompt_open = false
	quit_error = ""
	if is_instance_valid(quit_layer):
		remove_child(quit_layer)
		quit_layer.queue_free()
	quit_layer = null


func _handle_quit_input(event: InputEvent) -> bool:
	if not quit_prompt_open: return quit_finalizing
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel_quit()
		get_viewport().set_input_as_handled()
	# Return before gameplay shortcuts; GUI focus/keyboard navigation still works.
	return true


func _exit_failure_dialog() -> void:
	if is_instance_valid(quit_layer): return
	quit_layer = CanvasLayer.new()
	quit_layer.name = "QuitOverlay"
	quit_layer.layer = 100
	add_child(quit_layer)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,.8)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = MOUSE_FILTER_STOP
	quit_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	quit_layer.add_child(center)
	var frame := PanelContainer.new()
	frame.name = "QuitSaveFailure"
	frame.theme = theme
	frame.custom_minimum_size.x = 660
	if assets != null:
		frame.add_theme_stylebox_override("panel",SpritePanelStyle.make(assets.texture("ui_frame_paper"),TycoonTheme.PAPER,26))
	else:
		frame.add_theme_stylebox_override("panel",TycoonTheme.panel(TycoonTheme.PAPER,TycoonTheme.LINE,26))
	center.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	frame.add_child(column)
	_label(column,"저장하지 못했습니다",27,TycoonTheme.INK)
	_label(column,quit_error,20,TycoonTheme.BAD).name = "QuitSaveError"
	_label(column,"저장하지 않고 종료하면 마지막 저장 이후의 진행을 잃습니다.\n기존 저장 파일은 그대로 남습니다.",20,TycoonTheme.INK)
	var retry := _exit_button(column,"다시 저장하고 종료",_retry_quit,"RetryQuit")
	retry.theme_type_variation = "PrimaryButton"
	var discard := _exit_button(column,"저장하지 않고 종료",_discard_and_quit,"DiscardQuit")
	var cancel := _exit_button(column,"계속 플레이",_cancel_quit,"CancelQuit")
	var actions: Array[Button] = [retry,discard,cancel]
	for index in actions.size():
		var button: Button = actions[index]
		var previous: NodePath = actions[(index+actions.size()-1)%actions.size()].get_path()
		var following: NodePath = actions[(index+1)%actions.size()].get_path()
		button.focus_previous = previous
		button.focus_next = following
		button.focus_neighbor_top = previous
		button.focus_neighbor_bottom = following
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()
	cancel.grab_focus.call_deferred()


func _exit_button(parent: Node, caption: String, action: Callable, id: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size",20)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, px: int = 16, color: Color = GameTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", maxi(px, 14))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable, disabled: bool = false, id: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled or busy
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 40
	if id != "":
		button.name = id
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _box(parent: Node, ratio: float = 1.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = ratio
	parent.add_child(box)
	return box


func _card(parent: Node, title: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := _box(panel)
	if title != "":
		_label(box, title, 18, GameTheme.GOLD)
	return box


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(row)
	return row


func _scroll(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return _box(scroll)


func _money(value: float) -> String:
	return "%d금" % int(value / 100) if int(value) % 100 == 0 else "%.2f금" % (value / 100.0)


func _icon(parent: Node, key: String, px: int = 24) -> void:
	var texture := assets.texture("icon_" + key) if key != "" else null
	if texture == null:
		return
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(px, px)
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.size_flags_vertical = SIZE_SHRINK_CENTER
	parent.add_child(image)


func _bar(parent: Node, ratio: float, level: String = "") -> void:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.add_theme_stylebox_override("background", GameTheme.panel(GameTheme.BG, GameTheme.BG, 4, 0, 0))
	bar.add_theme_stylebox_override("fill", GameTheme.panel(GameTheme.level_color(level), GameTheme.level_color(level), 4, 0, 0))
	parent.add_child(bar)


func _tag(parent: Node, text: String, color: Color = GameTheme.TEXT, px: int = 15) -> Label:
	var label := _label(parent, text, px, color)
	label.size_flags_horizontal = 0
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _food_level(weeks: float) -> String:
	# 02번 4절: 4주 미만 위기, 4~8 불안, 8~26 보통, 26 이상 안정
	return "bad" if weeks < 4 else ("warn" if weeks < 8 else ("good" if weeks >= 26 else ""))


func _score_level(value: float) -> String:
	return "bad" if value < 40 else ("warn" if value < 55 else "good")


## 06번 2절: 주 시작 화면의 중요 변화. 경보는 원인·시점·대응을 한 문장에 담는다.
func _alerts() -> Array:
	var s := session.state
	var out: Array = []
	var wy := WeekSim.week_of_year(int(s.week))
	var fw := WeekSim.food_weeks(s)
	if fw < 4:
		out.append(["bad", "식량이 %.1f주분뿐입니다. 구휼·수레 구매·배급 조정 중 하나가 필요합니다." % fw])
	elif fw < 8:
		out.append(["warn", "식량 비축 %.1f주분. 수확(33~36주)까지 버틸 수 있는지 아래 전망을 확인하세요." % fw])
	if not forecast.is_empty() and forecast.lowest < 8 and forecast.lowest < fw - 0.05:
		out.append(["bad" if forecast.lowest < 4 else "warn", "지금 배치 그대로면 %d주에 식량이 %.1f주분까지 줄어듭니다." % [forecast.lowest_week, forecast.lowest]])
	var fuel_need: float = s.pop * 0.1 * 13
	fuel_need *= WeekSim.bonus(s, "heating")
	if s.get("chronicle", false) and s.get("trial", "") == "frost" and not s.get("trial_started", false):
		fuel_need *= 1.5
	if wy < 40 and s.public.fuel < fuel_need:
		out.append(["warn", "겨울 난방에 장작 %.0f이 필요한데 %.0f뿐입니다. 겨울까지 %d주 (벌목소 장작 가공 또는 교역)." % [fuel_need, s.public.fuel, 40 - wy]])
	elif wy >= 40 and s.public.fuel <= 0:
		out.append(["bad", "난방 장작이 없습니다. 겨울 동안 건강이 계속 떨어집니다."])
	if (not s.projects.is_empty() or not s.orders.is_empty()) and int(s.assign.build) == 0:
		out.append(["warn", "예약·진행 중인 공사가 있는데 건설 인력이 0명입니다. 건설과 노동에서 배치하세요."])
	var labor := int(floor(s.pop * s.labor_ratio))
	var sow := WeekSim.farm_demand(s, maxi(wy, 3))
	if wy <= 6 and sow > labor:
		out.append(["warn", "파종(3~6주)에 %d명이 필요한데 가용 노동이 %d명입니다. 일부 농지가 올해 수확을 놓칩니다." % [sow, labor]])
	if s.arrears_wage + s.arrears_tax > 0:
		out.append(["bad", "미지급 %s. 4주 이상 이어지면 공공 작업 효율이 떨어집니다." % _money(s.arrears_wage + s.arrears_tax)])
	var housing := WeekSim.capacity(s, session.content, "housing")
	if housing < s.pop:
		out.append(["bad", "주거가 %d명분 부족합니다. 움집 구역을 지으세요." % int(s.pop - housing)])
	if s.active_event != "":
		out.append(["info", "이번 주 결정이 기다립니다. 선택 전에는 다음 주로 갈 수 없습니다."])
	if not s.perk_offer.is_empty():
		out.append(["info", "특전 후보 3장이 열려 있습니다. 하나를 고르면 진행합니다."])
	return out


func _render() -> void:
	if is_instance_valid(main_scroll):
		scroll_positions[rendered_page] = main_scroll.scroll_vertical
	main_scroll = null
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		shell.add_theme_constant_override("margin_" + side, 24)
	add_child(shell)
	forecast = {}
	if page != "menu" and not session.state.is_empty() and session.state.status == "active":
		forecast = WeekSim.forecast(session.state, session.content)
	var root := _box(shell)
	root.size_flags_vertical = SIZE_EXPAND_FILL
	if page == "menu":
		_menu(root)
	else:
		_header(root)
		var body := _row(root)
		body.size_flags_vertical = SIZE_EXPAND_FILL
		_sidebar(body)
		var area := _scroll(body)
		main_scroll = area.get_parent()
		main_scroll.name = "PageScroll"
		main_scroll.follow_focus = page != "estate"
		match page:
			"estate": _estate(area)
			"build": _construction(area)
			"trade": _market(area)
			"people": _people(area)
			"ledger": _ledger(area)
			"archive": _archive(area)
			"result": _result(area)
	var footer := _row(root)
	footer.name = "Footer"
	notice_label = _label(footer, notice if notice != "" else "변경의 기록 / 첫 겨울의 회차", 13, GameTheme.MUTED)
	notice_label.size_flags_horizontal = SIZE_EXPAND_FILL
	notice_label.max_lines_visible = 2
	notice_label.tooltip_text = notice
	var version_label := _label(footer, "변경의 신임 영주가 되었다 · 1차 플레이 빌드", 13, GameTheme.MUTED)
	version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	version_label.size_flags_horizontal = SIZE_SHRINK_END
	rendered_page = page
	_restore_scroll.call_deferred(page, int(scroll_positions.get(page, 0)))


func _restore_scroll(target: String, position: int) -> void:
	if page == target and is_instance_valid(main_scroll):
		main_scroll.scroll_vertical = position


func _primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", GameTheme.panel(GameTheme.GOLD, GameTheme.GOLD, 2, 2))
	button.add_theme_stylebox_override("hover", GameTheme.panel(Color("f2d493"), GameTheme.TEXT, 2, 2))
	button.add_theme_stylebox_override("pressed", GameTheme.panel(Color("c3974c"), GameTheme.GOLD, 2, 2))
	button.add_theme_color_override("font_color", GameTheme.BG)
	button.add_theme_color_override("font_hover_color", GameTheme.BG)
	button.add_theme_color_override("font_pressed_color", GameTheme.BG)


func _open_decision() -> void:
	page = "estate"
	scroll_positions[page] = 0
	_render()
	_focus_decision.call_deferred()


func _focus_decision() -> void:
	var target := find_child("event_option_0", true, false) as Button
	if target == null:
		for id in session.state.perk_offer:
			target = find_child("perk_" + str(id), true, false) as Button
			if target != null:
				break
	if target != null:
		target.grab_focus()
	if is_instance_valid(main_scroll):
		main_scroll.scroll_vertical = 0


func _landscape(parent: Node, season: int, min_height: float = 240.0) -> void:
	var frame := AspectRatioContainer.new()
	frame.ratio = 16.0 / 9.0
	frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	frame.size_flags_horizontal = SIZE_EXPAND_FILL
	frame.custom_minimum_size.y = min_height
	frame.resized.connect(func():
		var height := roundf(frame.size.x / frame.ratio)
		if height > 0 and absf(frame.custom_minimum_size.y - height) > 1:
			frame.custom_minimum_size.y = height
	)
	parent.add_child(frame)
	var view := EstateView.new()
	view.name = "SettlementView"
	view.season = season
	view.backdrop = assets.texture("settlement_" + ["spring", "summer", "autumn", "winter"][season])
	frame.add_child(view)


func _menu(root: VBoxContainer) -> void:
	_label(root, "E R N   /   CHRONICLES OF THE FRONTIER", 14, GameTheme.GOLD)
	_label(root, "변경의 신임 영주가 되었다", 48)
	_label(root, "작은 영지에 남기는, 서로 다른 회차의 기록", 19, GameTheme.MUTED)
	var columns := _row(root)
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	var left := _box(columns, 1.6)
	_landscape(left, 0, 320)
	_label(left, "한 번의 겨울이 지나도, 배운 것은 남습니다.", 24, GameTheme.GOLD)
	_label(left, "밭을 일구고, 곳간을 채우고, 사람들의 목소리에 답하세요.\n52주의 첫 회차를 마치면 기록으로 다음 부임을 준비할 수 있습니다.", 17)
	var right := _card(columns, "새로운 회차")
	right.custom_minimum_size.x = 370
	_label(right, "빈 땅의 인장", 26)
	_label(right, "하사받은 에른 변경 · 주민 80명 · 첫해 봄\n목표: 농지 6구획 / 정식 곳간 / 식량 13주", 16, GameTheme.MUTED)
	_label(right, "영주의 출신", 14, GameTheme.GOLD)
	origin_pick = OptionButton.new()
	for id in session.content.progression.origins:
		origin_pick.add_item(session.content.progression.origins[id].name)
		origin_pick.set_item_metadata(origin_pick.item_count - 1, id)
	right.add_child(origin_pick)
	var detail := _label(right, session.content.progression.origins.settler.description, 15)
	origin_pick.item_selected.connect(func(index): detail.text = session.content.progression.origins[origin_pick.get_item_metadata(index)].description)
	_label(right, "세계의 씨앗", 14, GameTheme.GOLD)
	seed_input = LineEdit.new()
	seed_input.text = str(randi_range(100000, 999999))
	seed_input.max_length = 9
	seed_input.placeholder_text = "같은 숫자로 같은 세계를 다시 시작합니다"
	right.add_child(seed_input)
	var ongoing: bool = not session.state.is_empty() and session.state.status == "active"
	if ongoing:
		origin_pick.disabled = true
		seed_input.text = str(session.state.seed)
		seed_input.editable = false
		for i in origin_pick.item_count:
			if origin_pick.get_item_metadata(i) == session.state.origin:
				origin_pick.select(i)
		detail.text = "저장된 %d주차 회차를 이어갑니다. 출신과 씨앗은 이 회차 동안 유지됩니다." % session.state.week
	_primary(_button(right, "현재 회차 이어 하기" if ongoing else "이 기록으로 부임", _continue if ongoing else _start, load_blocked, "start_run"))
	_button(right, "가문 강화 · %d 공훈" % session.profile.points, func(): page = "archive"; _render(), load_blocked)
	if not session.state.is_empty() and session.state.status == "finalized":
		_button(right, "지난 회차 돌아보기", func(): page = "result"; _render())
	_label(right, "선택과 진행은 자동 저장됩니다.\n가문 강화는 다음 회차부터 적용됩니다.", 14, GameTheme.MUTED)


func _start() -> void:
	if not seed_input.text.is_valid_int():
		_message("세계의 씨앗에는 숫자를 입력해 주세요.")
		return
	session.start_run(int(seed_input.text), str(origin_pick.get_item_metadata(origin_pick.selected)))
	page = "estate"
	notice = "첫 결정을 선택하고, 농지와 곳간을 준비하세요."
	_save()
	_render()


func _continue() -> void:
	page = "estate"
	_render()


func _header(root: Node) -> void:
	var top := _row(root)
	var title := _box(top)
	_label(title, "변경의 신임 영주가 되었다 / 에른 변경", 23)
	if not session.state.is_empty():
		var s := session.state
		var wy := WeekSim.week_of_year(int(s.week))
		var date_text := "%d년 %s %d주" % [WeekSim.year_of(int(s.week)), WeekSim.SEASON_NAMES[WeekSim.season_of(wy)], (wy - 1) % 13 + 1]
		if s.status == "finalized":
			date_text = "%d주의 회차 · 기록 종료" % s.result.week
		var season_color: Color = GameTheme.SEASON[WeekSim.season_of(wy)] if s.status == "active" else GameTheme.MUTED
		var sub := _row(title)
		_tag(sub, date_text, season_color, 17)
		_tag(sub, "· %s · 씨앗 %d" % ["개척지" if WeekSim.stage(s, session.content) == 1 else "촌락", s.seed], GameTheme.MUTED, 14)
	else:
		_label(title, "다음 회차를 위한 기록", 14, GameTheme.MUTED)
	_button(top, "첫 화면", func(): page = "menu"; _render())
	_button(top, "기록 저장", func(): _save(); _message(notice), load_blocked)
	if not session.state.is_empty() and session.state.status == "active":
		var pending: bool = session.state.active_event != "" or not session.state.perk_offer.is_empty()
		_primary(_button(top, "결정 확인 →" if pending else "다음 주 →", _open_decision if pending else func(): _advance(1), false, "next_week"))
		var auto := _button(top, "계절 보내기", func(): _advance(13 - (WeekSim.week_of_year(int(session.state.week)) - 1) % 13), pending, "auto_season")
		auto.tooltip_text = "결정·특전을 먼저 선택하세요." if pending else "이번 계절 말까지 진행합니다. 사건·특전·식량 위기에서 멈춥니다."
		if busy:
			var stop := _button(top, "중단", func(): busy = false)
			stop.disabled = false
	if not session.state.is_empty():
		var stats := _row(root)
		var s := session.state
		var fw := WeekSim.food_weeks(s)
		var owed: int = s.arrears_wage + s.arrears_tax
		var housing := WeekSim.capacity(s, session.content, "housing")
		var later := "13주 뒤 %s" % _money(forecast.money) if not forecast.is_empty() else "공사 예약액 제외"
		_stat(stats, "금고", _money(s.public.money), later + (" · 체불 " + _money(owed) if owed > 0 else ""), "bad" if owed > 0 else ("warn" if s.public.money < 2000 else ""), "money")
		var food_hint := "공공 %.0f / 주민 %.0f" % [s.public.food, s.resident.food]
		if not forecast.is_empty():
			food_hint = "13주 뒤 %.1f주분 · " % forecast.food_weeks + food_hint
		_stat(stats, "식량 비축", "%.1f주분" % fw, food_hint, _food_level(minf(fw, forecast.get("lowest", fw))), "food", minf(1.0, fw / 26.0))
		_stat(stats, "주민", "%d명" % s.pop, "가용 노동 %d · 주거 %.0f · 식수 %.0f" % [int(floor(s.pop * s.labor_ratio)), housing, WeekSim.capacity(s, session.content, "water")], "bad" if housing < s.pop else "", "pop", s.pop / maxf(1.0, housing))
		_stat(stats, "민심 / 건강", "%d / %d" % [s.mood, s.health], "치안 %d · 촌락 태도 %d" % [s.security, s.village], _score_level(minf(s.mood, s.health)), "mood", minf(s.mood, s.health) / 100.0)
		_stat(stats, "개인 일정", "%d / 2" % s.actions, "공훈 %d · 특전 %d개" % [session.profile.points, s.perks.size()], "", "schedule")


func _stat(parent: Node, title: String, value: String, hint: String, level: String = "", icon: String = "", ratio: float = -1.0) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	if level != "":
		panel.add_theme_stylebox_override("panel", GameTheme.panel(GameTheme.PANEL, GameTheme.level_color(level), 8, 2))
	parent.add_child(panel)
	var box := _box(panel)
	var head := _row(box)
	_icon(head, icon, 22)
	_label(head, title, 14, GameTheme.MUTED)
	_label(box, value, 26, GameTheme.level_color(level) if level != "" else GameTheme.GOLD)
	if ratio >= 0.0:
		_bar(box, ratio, level)
	var detail := _label(box, hint, 14, GameTheme.MUTED)
	detail.name = icon + "Hint"
	detail.max_lines_visible = 1
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.tooltip_text = title + " · " + value + "\n" + hint + "\n전망은 현재 배치 기준이며 미래 사건·교역 도착은 제외합니다."


func _sidebar(parent: Node) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 174
	parent.add_child(box)
	for id in PAGES:
		var button := _button(box, PAGES[id], func(): page = id; _render(), session.state.is_empty() and id != "archive", "nav_" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if page == id:
			button.add_theme_stylebox_override("normal", GameTheme.panel(GameTheme.RAISED, GameTheme.GOLD, 8, 2))
			button.add_theme_color_override("font_color", GameTheme.GOLD)
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(spacer)
	if not session.state.is_empty() and session.state.status == "active":
		_button(box, "회차를 마치기", _ask_retire)
	_label(box, "종료 후 공훈으로\n가문 강화를 구매합니다.", 13, GameTheme.MUTED)


func _estate(parent: Node) -> void:
	var s := session.state
	var alerts := _alerts()
	var status := _row(parent)
	_label(status, "첫 겨울의 기록", 24, GameTheme.GOLD)
	_tag(status, "%d / 52주" % mini(52, int(s.week)), GameTheme.MUTED)
	var row := _row(parent)
	var left := _box(row, 1.5)
	var box := _card(left)
	_landscape(box, WeekSim.season_of(WeekSim.week_of_year(mini(52, int(s.week)))) )
	var chips := _row(box)
	for pair in [["wood", "목재", s.public.wood], ["stone", "석재", s.public.stone], ["tools", "도구", s.public.tools], ["fuel", "장작", s.public.fuel]]:
		var chip := _row(chips)
		_icon(chip, pair[0], 24)
		_label(chip, "%s %.0f" % [pair[1], pair[2]], 15, GameTheme.BAD if pair[2] <= 0 else GameTheme.TEXT)
	_label(box, "작황 전망 %.0f%% · 농지 %d구획 · 주거 %.0f명 · 식수 %.0f명" % [s.weather*100,s.facilities.get("B13",0),WeekSim.capacity(s,session.content,"housing"),WeekSim.capacity(s,session.content,"water")],14,GameTheme.MUTED)
	var report := _card(left, "집무실 보고")
	if s.status == "active":
		if int(s.week) <= 2:
			_label(report,"첫 준비 · 농지 2구획 추가 → 건설 8명 배치 → 2주 진행",15,GameTheme.INFO)
		if not alerts.is_empty():
			_label(report,alerts[0][1],15,GameTheme.level_color(alerts[0][0]))
		else:
			_label(report,"급한 경보가 없습니다. 다음 계절을 준비하세요.",15,GameTheme.GOOD)
		var quick := _row(report)
		_button(quick,"건설·인력 확인",func(): page="build"; _render())
		_button(quick,"교역 주문",func(): page="trade"; _render())
		_button(report,("▾ 상세 보고 접기" if report_open else "▸ 상세 보고 · 경보 %d건" % alerts.size()),func(): report_open = not report_open; _render(),false,"toggle_report")
		if report_open:
			for alert in alerts.slice(1):
				_label(report,alert[1],14,GameTheme.level_color(alert[0]))
			if not forecast.is_empty():
				_label(report,"13주 전망 · 식량 %.1f주분 / 금고 %s / 장작 %.0f\n현재 노동 배치 기준. 미래 사건·교역 도착 제외." % [forecast.food_weeks,_money(forecast.money),forecast.fuel],14,GameTheme.MUTED)
			if not s.history.is_empty():
				var last: Dictionary = s.history.back()
				_label(report,"%d주 결산\n%s" % [last.week,"\n".join(last.notes)],14,GameTheme.MUTED)
	_goals(left)
	var right := _box(row)
	right.custom_minimum_size.x=340
	_decisions(right)


func _portrait(parent: Node,id: String) -> void:
	var texture := assets.texture("portrait_"+id)
	if texture==null:
		return
	var image:=TextureRect.new()
	image.texture=texture
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size=Vector2(96,128)
	image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	image.size_flags_horizontal=SIZE_SHRINK_CENTER
	parent.add_child(image)


func _decisions(parent: Node) -> void:
	var s:=session.state
	if s.status=="finalized":
		var box:=_card(parent,"회차의 기록이 완성되었습니다")
		_button(box,"결산과 유산 확인",func(): page="result"; _render())
	elif s.active_event!="":
		var event: Dictionary=RealmRules.event_definition(s,session.content,s.active_event)
		var box:=_card(parent,"이번 주의 결정")
		var speaker_row := _row(box)
		_portrait(speaker_row,event.get("portrait",""))
		var introduction := _box(speaker_row)
		_label(introduction,event.speaker,14,GameTheme.GOLD)
		_label(introduction,event.title,22)
		_label(box,event.body,15)
		for i in event.options.size():
			var option: Dictionary=event.options[i]
			var error:=session.option_error(option)
			var choice:=_button(box,option.label,func(): _resolve(i),error!="","event_option_%d"%i)
			choice.custom_minimum_size.y=46
			_label(box,option.hint if error=="" else error,13,GameTheme.MUTED if error=="" else GameTheme.RED)
	elif not s.perk_offer.is_empty():
		var box:=_card(parent,"회차가 남긴 배움")
		_label(box,"이번 회차에 함께할 특전을 선택하세요.")
		for id in s.perk_offer:
			var perk: Dictionary=session.content.progression.perks[id]
			_button(box,perk.name+" / "+perk.tag,func(): session.choose_perk(id); _changed("새 특전이 적용되었습니다."),false,"perk_"+id)
			_label(box,perk.description,14,GameTheme.MUTED)
		_button(box,"새 후보 보기 · %d회 남음"%s.refreshes,func(): session.refresh_perks(); _changed("후보를 다시 살폈습니다."),s.refreshes<=0)
	else:
		var box:=_card(parent,"다음 결정을 준비하며")
		_label(box,"지금은 급한 안건이 없습니다. 영지를 정비하거나 다음 주로 진행할 수 있습니다.")
		_label(box,"자동 진행은 사건, 특전, 식량 위기에서 멈춥니다.",14,GameTheme.MUTED)


func _goals(parent: Node) -> void:
	var box:=_card(parent,"첫 회차의 약속")
	for goal in session.state.goals.values():
		var head := _row(box)
		_label(head,("✓ " if goal.done else "○ ")+goal.title,16,GameTheme.GOOD if goal.done else GameTheme.TEXT)
		_tag(head,goal.get("status",""),GameTheme.GOOD if goal.done else GameTheme.MUTED,14)
		_bar(box,goal.get("progress",1.0 if goal.done else 0.0),"good" if goal.done else "warn")
		_label(box,goal.detail,14,GameTheme.MUTED)
	_label(box,"52주 종료 때 세 약속을 지키면 완주 보상을 받습니다.",13,GameTheme.GOLD)


func _construction(parent: Node) -> void:
	_label(parent,"손을 모아, 땅을 바꾸는 일",27)
	var labor:=_card(parent,"주간 노동 배치")
	_label(labor,"농사 우선, 남은 인력은 채집 → 건설 → 벌목 → 채석 → 채소 → 장작 → 제분 순입니다. 없는 작업장과 끝난 공사는 노동을 쓰지 않습니다.",14,GameTheme.MUTED)
	var s:=session.state
	var available:=int(floor(s.pop*s.labor_ratio))
	labor_summary = _label(labor,"",17)
	labor_summary.name = "LaborSummary"
	labor_actual = _label(labor,"",14,GameTheme.TEAL)
	labor_actual.name = "LaborActual"
	labor_fields.clear()
	var grid:=GridContainer.new()
	grid.columns=4
	labor.add_child(grid)
	for id in JOBS:
		var field:=_box(grid)
		var cap:=_job_cap(id)
		var head:=_row(field)
		_label(head,JOBS[id],15)
		_tag(head,"작업장 없음" if cap<=0 else "최대 %d명"%cap,GameTheme.BAD if cap<=0 and int(s.assign.get(id,0))>0 else GameTheme.MUTED,14)
		var input:=SpinBox.new()
		input.name="job_"+id
		input.max_value=available
		input.step=1
		input.value=session.state.assign.get(id,0)
		input.editable=session.state.status=="active" and not busy
		input.value_changed.connect(func(value): session.state.assign[id]=int(value); _save(); _refresh_labor_preview(); _message(notice))
		field.add_child(input)
		labor_fields[id] = _label(field,"",14,GameTheme.MUTED)
	_refresh_labor_preview()
	if session.state.has("labor_report"):
		var last: Dictionary=session.state.labor_report
		_label(labor,"직전 실제 배치 · 농사 %d / 채집 %d / 건설 %d / 벌목 %d / 채석 %d / 장작 %d"%[last.farm,last.gather,last.build,last.logging,last.quarry,last.fuel],13,GameTheme.TEAL)
	var queue:=_card(parent,"예약 명령과 진행 사업")
	_label(queue,"예약 중인 자원은 다른 착공에 사용할 수 없습니다. 다음 주 시작에 자재와 공사비가 결제됩니다.",14,GameTheme.MUTED)
	for i in session.state.orders.size():
		var row:=_row(queue)
		_label(row,"착공 예정 · "+session.content.facilities[session.state.orders[i]].name)
		_button(row,"예약 해제",func(): session.state.orders.remove_at(i); _changed("명령을 해제했습니다."),session.state.status!="active")
	for i in session.state.projects.size():
		var project: Dictionary=session.state.projects[i]
		var row:=_row(queue)
		_label(row,"%s · 남은 작업 %d인주 · 잔금 %s"%[session.content.facilities[project.id].name,project.work_left,_money(project.escrow)])
		_button(row,"취소·잔여 반환",func(): WeekSim.cancel_project(session.state,session.content,i); _changed("잔여 자재·잔금과 사용 자재 30%를 돌려받았습니다."),session.state.status!="active")
	if session.state.orders.is_empty() and session.state.projects.is_empty():
		_label(queue,"시설을 예약하고 건설 인력을 배치하세요.",14,GameTheme.MUTED)
	var cards:=GridContainer.new()
	cards.columns=2
	parent.add_child(cards)
	for id in session.content.facilities:
		var facility: Dictionary=session.content.facilities[id]
		if facility.grade=="T":
			continue
		var cost: Dictionary=Constants.GRADE_COST[facility.grade]
		var box:=_card(cards,facility.name)
		_label(box,"보유 %d · %s"%[session.state.facilities.get(id,0),_facility_hint(id)],14,GameTheme.MUTED)
		var costs:=_row(box)
		for pair in [["money","%d금"%cost.gold,cost.gold*Constants.COPPER_PER_GOLD],["wood","목재 %d"%cost.wood,cost.wood],["stone","석재 %d"%cost.stone,cost.stone],["tools","도구 %d"%cost.tools,cost.tools]]:
			var short: bool=session.state.public[pair[0]]<pair[2]
			_tag(costs,pair[1],GameTheme.BAD if short else GameTheme.TEXT,15)
		_label(box,"작업량 %d인주 · 노동 급여 별도 · 빨간 항목은 부족한 자재"%cost.work,14,GameTheme.MUTED)
		var error := _build_error(id)
		var build := _button(box,"착공 예약" if error == "" else "건설 조건 확인",func(): _command_build(id),error != "","build_"+id)
		build.tooltip_text = error if error != "" else "자재와 공사비를 예약합니다. 별도 건설 인력이 필요합니다."
		if error != "":
			_label(box,error,14,GameTheme.WARN)


func _build_error(id: String) -> String:
	if session.state.status != "active":
		return "종료된 회차입니다."
	var trial: Dictionary = session.state.duplicate(true)
	trial.orders.append(id)
	var errors := WeekSim.validate_orders(trial, session.content)
	if errors.is_empty():
		return ""
	var reason := str(errors[0])
	for key in {"money":"금고", "wood":"목재", "stone":"석재", "tools":"도구", "iron":"철"}:
		reason = reason.replace(key,{"money":"금고", "wood":"목재", "stone":"석재", "tools":"도구", "iron":"철"}[key])
	return reason


func _refresh_labor_preview() -> void:
	if not is_instance_valid(labor_summary):
		return
	var trial: Dictionary = session.state.duplicate(true)
	WeekSim.process_week(trial, session.content)
	var actual: Dictionary = trial.get("labor_report", {})
	if actual.is_empty():
		labor_summary.text = "예약한 공사 조건을 먼저 확인하세요."
		return
	var used := int(actual.farm)
	var requested := 0
	for id in JOBS:
		used += int(actual.get(id,0))
		requested += int(session.state.assign.get(id,0))
		if labor_fields.has(id) and is_instance_valid(labor_fields[id]):
			labor_fields[id].text = "이번 주 실제 %d명" % actual.get(id,0)
	var idle := maxi(0,int(actual.available)-used)
	labor_summary.text = "가용 %d명 · 농사 %d명 · 공공 작업 %d명 · 유휴 인력 %d명" % [actual.available,actual.farm,used-int(actual.farm),idle]
	labor_actual.text = "요청 %d명 → 실제 %d명. 작업장 한도와 농사 우선순위를 반영합니다." % [requested,used-int(actual.farm)]
	forecast = WeekSim.forecast(session.state,session.content)
	var money_hint := find_child("moneyHint",true,false) as Label
	var food_hint := find_child("foodHint",true,false) as Label
	if money_hint != null:
		money_hint.text = "13주 뒤 " + _money(forecast.money)
	if food_hint != null:
		food_hint.text = "13주 뒤 %.1f주분" % forecast.food_weeks


func _job_cap(id: String) -> int:
	var f: Dictionary=session.state.facilities
	match id:
		"gather": return 8*int(f.get("B17",0))
		"logging","fuel": return 4*int(f.get("B25",0))
		"quarry": return 4*int(f.get("B27",0))
		"garden": return 4*int(f.get("B14",0))
		"milling": return 3*int(f.get("B19",0))
		"build":
			var work:=0
			for p in session.state.projects:
				work+=int(p.work_left)
			for id_value in session.state.orders:
				work += int(Constants.GRADE_COST[session.content.facilities[id_value].grade].work)
			return work
	return 0


func _facility_hint(id: String) -> String:
	return {"B01":"주거 +40명","B06":"식수 +100명","B13":"연 수확 기본 540","B14":"봄~가을 채소 생산","B17":"지역 최대 2단지","B19":"제분 노동으로 보존 개선","B22":"저장량 +12,000","B25":"벌목·장작 작업장","B27":"석재 생산","B49":"운송료 절감","B59":"구휼과 건강 지원","B63":"수금률 개선"}.get(id,"")


func _market(parent: Node) -> void:
	_label(parent,"교역",27)
	_label(parent,"2주 운송 · 구매는 선불, 판매 대금은 도착 후 수령 · 운송료 포함\n공공 재고만 거래합니다. 수량을 바꾸면 가격이 즉시 갱신됩니다.",15,GameTheme.MUTED)
	var shipments:=_card(parent,"수레 %d / 3대 운행 중" % session.state.shipments.size())
	if session.state.shipments.is_empty():
		_label(shipments,"수레가 준비되어 있습니다. 아래에서 품목과 수량을 고르세요.",14,GameTheme.MUTED)
	for shipment in session.state.shipments:
		_label(shipments,"%s · %s %d · %d주 뒤 %s (%d주차)"%["구매" if shipment.buy else "판매",RESOURCES[shipment.asset],shipment.quantity,maxi(0,shipment.arrival-session.state.week),"물자 도착" if shipment.buy else "대금 수령",shipment.arrival],15)
	var grid:=GridContainer.new()
	grid.columns=2
	parent.add_child(grid)
	for id in RESOURCES:
		var quantity: int=int(trade_quantities.get(id,{"food":200,"wood":40,"stone":40,"tools":8,"fuel":120}[id]))
		var box:=_card(grid)
		var head := _row(box)
		_icon(head,id,24)
		_label(head,RESOURCES[id],20,GameTheme.GOLD)
		_tag(head,"공공 %.0f" % session.state.public[id],GameTheme.MUTED,14)
		var amount := _row(box)
		_label(amount,"주문 수량",15)
		var input := SpinBox.new()
		input.name = "quantity_" + id
		input.min_value = 1
		input.max_value = 200
		input.value = quantity
		input.editable = session.state.status == "active" and not busy
		amount.add_child(input)
		var row:=_row(box)
		var buy := _button(row,"",func(): _command_trade(id,int(input.value),true),false,"buy_"+id)
		var sell := _button(row,"",func(): _command_trade(id,int(input.value),false),false,"sell_"+id)
		var reason := _label(box,"",14,GameTheme.MUTED)
		reason.name = "trade_reason_" + id
		input.value_changed.connect(func(value): trade_quantities[id]=int(value); _refresh_quote(id,int(value),buy,sell,reason))
		_refresh_quote(id,quantity,buy,sell,reason)


func _refresh_quote(id: String, quantity: int, buy: Button, sell: Button, reason: Label) -> void:
	var buy_price := session.trade_quote(id,quantity,true)
	var sell_price := session.trade_quote(id,quantity,false)
	var full: bool = session.state.shipments.size() >= 3
	var inactive: bool = session.state.status != "active" or busy
	var buy_reason := ""
	var sell_reason := ""
	if inactive:
		buy_reason = "현재 거래할 수 없습니다."
		sell_reason = buy_reason
	elif full:
		buy_reason = "수레 3대가 모두 운행 중입니다."
		sell_reason = buy_reason
	else:
		if session.state.public.money < buy_price:
			buy_reason = "금고 부족"
		if sell_price < 0:
			sell_reason = "판매량이 적어 운송료를 충당할 수 없습니다."
		elif session.state.public[id] < quantity:
			sell_reason = "공공 재고 부족"
	buy.text = "구매 " + _money(buy_price)
	sell.text = "판매 " + (_money(sell_price) if sell_price >= 0 else "수량 부족")
	buy.disabled = buy_reason != ""
	sell.disabled = sell_reason != ""
	buy.tooltip_text = buy_reason if buy_reason != "" else "%d주차에 물자가 도착합니다." % (session.state.week+2)
	sell.tooltip_text = sell_reason if sell_reason != "" else "%d주차에 대금을 받습니다." % (session.state.week+2)
	var reasons: Array[String] = []
	if buy_reason != "": reasons.append("구매: " + buy_reason)
	if sell_reason != "" and sell_reason != buy_reason: reasons.append("판매: " + sell_reason)
	reason.text = " / ".join(reasons) if not reasons.is_empty() else "%d주차 도착 · 남은 수레 %d대" % [session.state.week+2,3-session.state.shipments.size()]


func _people(parent: Node) -> void:
	_label(parent,"같은 땅에서 다른 내일을 꿈꾸는 사람들",26)
	var row:=_row(parent)
	var odile:=_card(row,"오딜 · 영지의 기록 담당")
	_portrait(odile,"CH01")
	_label(odile,"신뢰 %d / 100"%session.state.trust,26,GameTheme.GOLD)
	_label(odile,"“숫자는 늘 맞게 적겠습니다. 그 숫자를 어떤 삶으로 바꿀지는 함께 고민해야겠지요.”",17)
	_button(odile,"면담 · 일정 1",func(): _activity("talk"),not _can_activity("talk"))
	var village:=_card(row,"촌락 · 이곳에 뿌리내린 사람들")
	_portrait(village,"CH09")
	_label(village,"태도 %d / 100"%session.state.village,26,GameTheme.TEAL)
	_label(village,"바라는 것: 식량, 예측 가능한 세금, 안전한 집.",17)
	_button(village,"영지 순시 · 일정 1",func(): _activity("visit"),not _can_activity("visit"))
	_button(village,"식량 구휼 · 40식량 / 일정 1",func(): _activity("relief"),not _can_activity("relief"))
	var ration:=_card(parent,"식량 배급 방침")
	_label(ration,"배급을 줄이면 비축은 오래가지만 민심과 건강이 나빠집니다.",15,GameTheme.MUTED)
	var choices:=_row(ration)
	for ratio in [1.0,0.9,0.75]:
		var caption: String={1.0:"정상 배급",0.9:"절약 배급",0.75:"비상 배급"}[ratio]
		_button(choices,("✓ " if session.state.ration==ratio else "")+caption,func(): session.state.ration=ratio; _changed("배급 방침을 변경했습니다."),session.state.status!="active")
	var perks:=_card(parent,"이번 회차의 특전")
	for id in session.state.perks:
		_label(perks,session.content.progression.perks[id].name+" — "+session.content.progression.perks[id].description)
	if session.state.perks.is_empty():
		_label(perks,"계절을 마치면 새로운 배움을 선택할 수 있습니다.",15,GameTheme.MUTED)


func _can_activity(id: String) -> bool:
	return session.state.status=="active" and session.state.actions>0 and id not in session.state.actions_used


func _ledger(parent: Node) -> void:
	_label(parent,"장부는 원인을 기억합니다",27)
	var summary:=_card(parent,"공공과 주민의 살림")
	var escrow := 0
	for project in session.state.projects:
		escrow += int(project.escrow)
	_label(summary,"진행 공사에 보관된 예약 잔금 " + _money(escrow),16,GameTheme.GOLD)
	_label(summary,"공공 금고 %s / 주민 운전자금 %s\n미지급 비용 %s / 주민 체납 %s\n올해 실제 세수 평가액 %s / 첫해 공납 면제"%[_money(session.state.public.money),_money(session.state.resident.money),_money(session.state.arrears_wage),_money(session.state.arrears_tax),_money(session.state.tax_year)])
	var history:=_card(parent,"최근 주간 기록")
	for item in session.state.history.slice(-12):
		_label(history,"%02d주   주민 %d명   식량 %.0f   금고 %s"%[item.week,item.pop,item.food,_money(item.money)],14)
	var book:=_card(parent,"최근 원장 · 이전과 소비는 구별됩니다")
	var names: Dictionary={"seed":"종자 사용","harvest":"수확","gather":"채집","consume":"주민 소비","spoil":"보관 손실","construction":"공사 지출","wages":"공공 급여","maintenance":"시설 유지","tax":"세금","logging":"벌목","quarry":"채석","fuel":"장작 가공","heating":"난방","garden":"채소 생산","trade_buy":"교역 구매","trade_depart":"판매 출하","trade_arrival":"물자 도착","trade_sale":"교역 대금","event":"사건 수입","event_cost":"사건 비용"}
	for entry in session.state.ledger.slice(-30):
		var text: String="%02d주 · %s · %s %+.2f"%[entry.w,names.get(entry.src,entry.src),RESOURCES.get(entry.asset,"동화" if entry.asset=="money" else entry.asset),entry.qty]
		if entry.src=="transfer":
			text="%02d주 · 계정 이전 · %s → %s · %.1f"%[entry.w,"공공" if entry.from=="public" else "주민","공공" if entry.to=="public" else "주민",entry.amount]
		_label(book,text,14,GameTheme.MUTED)


func _archive(parent: Node) -> void:
	_label(parent,"가문 강화",32)
	_label(parent,"%d 공훈 · 완성한 기록 %d개"%[session.profile.points,session.profile.receipts.size()],22,GameTheme.GOLD)
	_label(parent,"기억한 일은 다음 회차의 준비가 됩니다. 업그레이드는 다음 부임에 적용됩니다.",16,GameTheme.MUTED)
	var grid:=GridContainer.new()
	grid.columns=2
	parent.add_child(grid)
	for id in session.content.progression.upgrades:
		var upgrade: Dictionary=session.content.progression.upgrades[id]
		var box:=_card(grid,upgrade.name)
		_label(box,upgrade.description)
		var owned: bool=id in session.profile.upgrades
		var prerequisite: bool=upgrade.requires!="" and upgrade.requires not in session.profile.upgrades
		if prerequisite:
			_label(box,"선행: "+session.content.progression.upgrades[upgrade.requires].name,13,GameTheme.MUTED)
		_button(box,"익힌 기록" if owned else "%d 공훈으로 익히기"%upgrade.cost,func(): _upgrade(id),owned or prerequisite or session.profile.points<upgrade.cost or load_blocked)
	_button(parent,"부임 준비로 돌아가기",func(): page="menu"; _render())


func _result(parent: Node) -> void:
	if session.state.is_empty() or session.state.result.is_empty():
		_label(parent,"아직 완성한 회차가 없습니다.",24)
		return
	var result: Dictionary=session.state.result
	_label(parent,"첫 겨울을 넘긴 영주" if result.success else "미완의 회차도 기록이 됩니다",34,GameTheme.GOLD)
	_label(parent,"%d주의 기록 · %s · 주민 %d명 · 식량 %.0f"%[result.week,result.reason,session.state.pop,WeekSim.total_food(session.state)],19)
	var box:=_card(parent,"이번 회차가 남긴 유산")
	_label(box,"+%d 공훈"%result.points,40,GameTheme.TEAL)
	_label(box,"과업 %d개: %d점\n완주: %d점\n첫 기록: %d점\n보상은 한 번만 지급됩니다."%[result.objectives,result.objective_points,result.completion_points,result.first_points],17)
	_goals(parent)
	var row:=_row(parent)
	_button(row,"서고에서 다음 회차 준비",func(): page="archive"; _render())
	_button(row,"새로운 영주로 시작",func(): page="menu"; _render())
	_button(row,"지난 장부 돌아보기",func(): page="ledger"; _render())


func _advance(count: int) -> void:
	if busy:
		return
	advance_error = ""
	busy=true
	for i in count:
		if not busy:
			break
		var report:=session.advance()
		if not report.advanced:
			advance_error=" / ".join(report.notes)
			notice=advance_error
			if session.state.active_event!="" or not session.state.perk_offer.is_empty():
				page="estate"
			break
		var saved:=_save()
		if saved:
			notice="%d주를 마쳤습니다."%report.week
		else:
			advance_error=notice
		if session.state.status=="finalized":
			page="result"
		elif report.stop:
			page="estate"
		_render()
		await get_tree().process_frame
		if report.stop or not saved:
			break
	busy=false
	_render()
	if page == "estate" and (session.state.active_event != "" or not session.state.perk_offer.is_empty()):
		_focus_decision.call_deferred()


func _resolve(index: int) -> void:
	var error:=session.choose_event(index)
	if error!="":
		_message(error)
	else:
		_changed("선택을 적용했습니다.")


func _command_build(id: String) -> void:
	var error:=session.queue_build(id)
	if error=="":
		_changed("착공을 예약했습니다. 건설 인력을 배치하세요.")
	else:
		_message(error)


func _command_trade(id: String,quantity: int,buying: bool) -> void:
	var error:=session.trade(id,quantity,buying)
	if error=="":
		_changed("교역 수레를 예약했습니다. 2주 뒤 도착합니다.")
	else:
		_message(error)


func _activity(id: String) -> void:
	var error:=session.activity(id)
	if error=="":
		_changed("영주의 일정을 마쳤습니다.")
	else:
		_message(error)


func _upgrade(id: String) -> void:
	var error:=session.buy_upgrade(id)
	if error=="":
		_changed("가문 강화를 구매했습니다. 다음 회차부터 적용됩니다.")
	else:
		_message(error)


func _ask_retire() -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title="현재 회차를 종료할까요?"
	dialog.dialog_text="현재 회차를 마치고 달성한 과업만큼 공훈을 받습니다.\n13주를 채우기 전에는 공훈을 받지 않습니다."
	dialog.ok_button_text="회차 결산"
	dialog.cancel_button_text="계속 통치"
	dialog.confirmed.connect(func(): session.settle("은퇴"); page="result"; _changed("회차를 종료했습니다."); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(500,180))


func _save() -> bool:
	if load_blocked:
		return false
	var error:=store.write(session.bundle())
	notice="저장 완료" if error=="" else error
	return error==""


func _changed(message: String) -> void:
	if _save():
		notice=message
	_render()


func _message(message: String) -> void:
	notice=message
	if is_instance_valid(notice_label):
		notice_label.text=message
