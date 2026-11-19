extends "res://ui/chronicle_ui.gd"
## 월드 → 관리 창 → 사건/보상 모달. 경제 상태와 저장 규칙은 기존 세션을 사용한다.

const DOCK := [["build", "건설", "tools", "1"], ["trade", "교역", "money", "2"], ["people", "접견", "pop", "3"], ["boons", "특전", "mood", "4"], ["journey", "회차", "schedule", "5"], ["archive", "가문 강화", "stone", "6"]]
var board: EstateBoard
var interface: Control
var decision_hidden := false
var decision_key := ""
var decision_result: Dictionary = {}
var selected_facility := "B13"
var selected_goods := "food"
var help_open := false
var current_modal: Control
var focus_return := ""
var toast_message := ""
var toast_expiry := 0
var selected_perk := ""
var selected_upgrade := "M01"

func _label(parent: Node, text: String, px: int = 20, color: Color = GameTheme.TEXT) -> Label:
	return super._label(parent, text, maxi(18, px), color)

func _heading(parent: Node, text: String, large: bool = false, color: Color = GameTheme.TEXT) -> Label:
	var label := _label(parent, text, 30 if large else 22, color)
	label.add_theme_font_override("font", PixelTheme.heading_font())
	return label

func _ready() -> void:
	super._ready()
	resized.connect(_resize_interface)

func _resize_interface() -> void:
	# 레이아웃 갱신은 폰트를 축소하지 않는다.
	if is_instance_valid(interface): _render.call_deferred()

func _render() -> void:
	if not pixel_ready:
		theme = PixelTheme.create(assets.body_font())
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pixel_ready = true
		theme.default_font_size = 20
		theme.set_font_size("font_size", "Button", 20)
		theme.set_color("font_disabled_color", "Button", Color("b7c2c5"))
	if is_instance_valid(main_scroll): scroll_positions[rendered_page] = main_scroll.scroll_vertical
	main_scroll = null
	current_modal = null
	if not is_instance_valid(board):
		board = EstateBoard.new()
		board.name = "EstateWorld"
		board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		board.site_selected.connect(_select_site)
		add_child(board)
	var season_index := mini(3, int((int(session.state.get("week", 1)) - 1) / 13))
	board.season = season_index
	board.backdrop = assets.texture("terrain_" + ["spring", "summer", "autumn", "winter"][season_index])
	board.configure(assets, session.state, _is_active() and page == "estate")
	board.fields = int(session.state.get("facilities", {}).get("B13", 4))
	board.construction_count = session.state.get("orders", []).size() + session.state.get("projects", []).size()
	board._place_markers.call_deferred()
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	shell = MarginContainer.new()
	shell.name = "WorldShell"
	shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shell.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(shell)
	interface = Control.new()
	interface.name = "WorldInterface"
	interface.mouse_filter = MOUSE_FILTER_IGNORE
	shell.add_child(interface)
	forecast = WeekSim.forecast(session.state, session.content) if _is_active() else {}
	if page == "menu":
		_world_menu()
	elif page == "prepare":
		_shade(interface, .55)
		var content := _window("새 회차 준비", Vector2(1120, minf(size.y - 64, 760)), false)
		_prepare(content)
	else:
		if page != "estate": _shade(interface, .35).mouse_filter = MOUSE_FILTER_IGNORE
		if not session.state.is_empty():
			_world_hud()
			_world_dock()
			if _is_active() and page == "estate": _tutorial_strip()
		if page == "estate":
			_world_objectives()
		else:
			var title: String = {"build":"영지 시설", "trade":"상인 조합 · 교역", "people":"집무실 · 인물 접견", "boons":"이번 회차 · 특전과 특성", "journey":"회차 진행", "ledger":"영지 장부", "archive":"가문 · 가문 강화", "result":"회차 결산"}.get(page, "영지")
			var content := _window(title, Vector2(minf(1160, size.x - 64), maxf(430, size.y - 250)))
			if _is_active(): _tutorial_inline(content)
			match page:
				"build": _construction(content)
				"trade": _market(content)
				"people": _people(content)
				"boons": _boons(content)
				"journey": _journey(_window_scroll(content))
				"ledger": _ledger(_window_scroll(content))
				"archive": _archive(content)
				"result": _result(_window_scroll(content))
		if _is_active():
			var key := _decision_identity()
			if key != decision_key:
				decision_hidden = false
				decision_key = key
			if not decision_result.is_empty(): _result_popup()
			elif _pending() and not decision_hidden: _decision_popup()
	if help_open: _help_popup()
	_toast()
	rendered_page = page
	_restore_scroll.call_deferred(page, int(scroll_positions.get(page, 0)))

func _shade(parent: Node, opacity: float) -> ColorRect:
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.06, opacity)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = MOUSE_FILTER_STOP
	parent.add_child(shade)
	return shade

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position.round()
	control.size = rect.size.round()

func _window(title: String, dimensions: Vector2, closable: bool = true, modal: bool = false) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.name = "DecisionModal" if modal else "ManagementWindow"
	frame.add_theme_stylebox_override("panel", PixelTheme.frame(Color("172429"), GameTheme.GOLD if modal else Color("9d9271"), 22))
	interface.add_child(frame)
	_place(frame, Rect2(Vector2((size.x - dimensions.x) * .5, (size.y - dimensions.y) * .5 - (16 if modal else 8)), dimensions))
	var content := _box(frame)
	content.add_theme_constant_override("separation", 16)
	var head := _row(content)
	_heading(head, title, false, GameTheme.GOLD)
	if closable:
		var close := _button(head, "닫기  Esc", func(): _go("estate" if not session.state.is_empty() else "menu"), false, "CloseWindow")
		close.add_theme_font_size_override("font_size", 16)
		close.custom_minimum_size.y = 32
	var line := HSeparator.new()
	content.add_child(line)
	return content

func _window_scroll(parent: Node) -> VBoxContainer:
	var area := _scroll(parent)
	main_scroll = area.get_parent()
	main_scroll.name = "WindowScroll"
	main_scroll.follow_focus = true
	return area

func _world_menu() -> void:
	var vignette := _shade(interface, .25)
	vignette.mouse_filter = MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelTheme.frame(Color("172429"), GameTheme.GOLD, 30))
	interface.add_child(panel)
	_place(panel, Rect2(60, maxf(60, (size.y - 600) * .5), 480, 590))
	var box := _box(panel)
	_label(box, "영지 경영 로그라이트", 17, GameTheme.TEAL)
	_heading(box, "변경의 신임 영주가 되었다", true)
	_label(box, "52주 동안 영지를 운영하고\n겨울 시련을 통과하세요.", 19, GameTheme.MUTED)
	var space := Control.new()
	space.custom_minimum_size.y = 12
	box.add_child(space)
	if _is_active():
		_primary(_button(box, "%d회차 · %d주 이어 하기" % [session.profile.runs, session.state.week], _continue, load_blocked, "ContinueRun"))
		_button(box, "현재 회차 종료", _ask_retire, load_blocked, "RetireRun")
	else:
		_primary(_button(box, "새 회차 시작", _open_prepare, load_blocked, "NewRun"))
		if not session.state.is_empty(): _button(box, "지난 회차 결산", func(): _go("result"))
	_button(box, "가문 강화  ·  %d 공훈" % session.profile.points, func(): _go("archive"), false, "OpenArchive")
	var menu_actions := _row(box)
	_button(menu_actions, "플레이 안내", _help, false, "OpenHelp").size_flags_horizontal = SIZE_EXPAND_FILL
	_button(menu_actions, "게임 종료", _quit_game, false, "QuitGame").size_flags_horizontal = SIZE_EXPAND_FILL
	_label(box, "지역과 영주 선택 → 특전 수집 → 겨울 시련\n→ 공훈 획득 → 가문 강화 → 새 회차", 16, GameTheme.TEAL)
	_label(box, "자동 저장 사용 중", 16, GameTheme.MUTED)

func _quit_game() -> void:
	_request_quit()

func _world_hud() -> void:
	var frame := PanelContainer.new()
	frame.name = "StatusHeader"
	frame.add_theme_stylebox_override("panel", PixelTheme.frame(Color("182629"), Color("887e60"), 12))
	interface.add_child(frame)
	_place(frame, Rect2(18, 14, size.x - 36, 92))
	var row := _row(frame)
	row.add_theme_constant_override("separation", 14)
	var s := session.state
	var date := _box(row)
	date.size_flags_horizontal = 0
	date.custom_minimum_size.x = 132
	date.add_theme_constant_override("separation", 0)
	var season := mini(3, int((int(s.week) - 1) / 13))
	var label := _heading(date, "%s  %d주" % [["봄", "여름", "가을", "겨울"][season], mini(52, s.week)])
	label.name = "HeaderBrand"
	_label(date, "%d회차  /  52주" % session.profile.runs, 16, GameTheme.MUTED)
	for item in [["money", _money(s.public.money), "금고"], ["food", "%.1f주" % WeekSim.food_weeks(s), "식량"], ["pop", "%d" % s.pop, "주민"], ["wood", "%.0f" % s.public.wood, "목재"], ["stone", "%.0f" % s.public.stone, "석재"], ["tools", "%.0f" % s.public.tools, "도구"], ["fuel", "%.0f" % s.public.fuel, "장작"]]:
		var chip := _row(row)
		chip.add_theme_constant_override("separation", 6)
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		_icon(chip, item[0], 28)
		var words := _box(chip)
		words.add_theme_constant_override("separation", 0)
		_label(words, item[2], 18, Color("d3ddd9"))
		var value := _tag(words, item[1], GameTheme.WARN if item[0] == "food" and WeekSim.food_weeks(s) < 8 else GameTheme.TEXT, 22)
		value.tooltip_text = item[2]
		chip.tooltip_text = item[2]
		if item[0] == "food": value.tooltip_text = "공공 %.0f + 주민 %.0f · 정상 배급 기준" % [s.public.food, s.resident.food]
	_button(row, "?", _help, false, "HeaderHelp")
	_button(row, "메뉴", func(): _go("menu"), false, "MainMenu")

func _world_dock() -> void:
	var holder := VBoxContainer.new()
	interface.add_child(holder)
	_place(holder, Rect2(18, size.y - 130, size.x - 36, 112))
	holder.add_theme_constant_override("separation", 6)
	var top := _row(holder)
	if ChronicleRules.active(session.state):
		var counts := ChronicleRules.family_counts(session.content, session.state)
		for id in counts:
			var family: Dictionary = session.content.chronicle.families[id]
			var chip := _button(top, "%s %d" % [family.name, counts[id]], func(): _go("boons"))
			chip.add_theme_font_size_override("font_size", 16)
			chip.add_theme_stylebox_override("normal", PixelTheme.frame(Color("172429"), Color(family.color).darkened(.35), 6))
			chip.custom_minimum_size = Vector2(88, 30)
			chip.tooltip_text = family.description
		var reward_panel := PanelContainer.new()
		reward_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		reward_panel.add_theme_stylebox_override("panel", PixelTheme.frame(Color("14252b"), Color("768a86"), 6))
		top.add_child(reward_panel)
		_label(reward_panel, _next_reward_text(), 18, GameTheme.TEXT)
	else: _label(top, "이전 저장의 운영 규칙으로 진행 중", 16, GameTheme.TEXT)
	var row := _row(holder)
	row.add_theme_constant_override("separation", 6)
	for entry in DOCK:
		var button := _button(row, "%s  %s" % [entry[3], entry[1]], func(): _go(entry[0]), false, "nav_" + entry[0])
		button.icon = assets.texture("icon_" + entry[2])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 26)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 55
		if page == entry[0]: _primary(button)
	_button(row, "영지", func(): _go("estate"), false, "nav_estate")
	if _is_active():
		var next := _button(row, "결정 확인  F" if _pending() else "다음 주  Space", _open_decision if _pending() else func(): _advance(1), false, "NextWeek")
		next.custom_minimum_size.x = 178
		_primary(next)

func _next_reward_text() -> String:
	var s := session.state
	if _pending(): return "결정 대기 · 선택을 마치면 시간을 진행할 수 있습니다"
	for week in ChronicleRules.DRAFT_WEEKS:
		if int(s.week) <= week: return "다음 특전까지 %d주  ·  보유 %d / 8개" % [week + 1 - int(s.week), s.perks.size()]
	return "최종 평가까지 %d주  ·  겨울 시련 진행 중" % maxi(0, 53 - int(s.week))

func _world_objectives() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelTheme.frame(Color("172429"), Color("887e60"), 14))
	interface.add_child(panel)
	_place(panel, Rect2(24, 120, 274, 0))
	var box := _box(panel)
	var goals_button := _button(box, "52주 목표 · 회차 정보", func(): _go("journey"), false, "OpenJourney")
	goals_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for id in session.state.goals:
		var goal: Dictionary = session.state.goals[id]
		var goal_text: String = {"farms":"농지  %d / 6구획" % session.state.facilities.get("B13", 0), "storage":"곳간  " + goal.status, "food":"식량  %.1f / 13주" % WeekSim.food_weeks(session.state)}[id]
		_label(box, ("✓  " if goal.done else "□  ") + goal_text, 19, GameTheme.GOOD if goal.done else GameTheme.TEXT)
	if ChronicleRules.active(session.state):
		var trial: Dictionary = session.content.chronicle.trials[session.state.trial]
		_label(box, "겨울 시련 · " + trial.name, 16, GameTheme.WARN)
		box.tooltip_text = trial.description
	var alerts := _actionable_alerts()
	if not alerts.is_empty() and alerts[0].level != "info":
		var alert: Dictionary = alerts[0]
		var action := _button(box, alert.title + "  ›", func():
			if alert.has("tab"): construction_tab = alert.tab
			_go(alert.page)
		)
		action.tooltip_text = alert.detail
		action.add_theme_color_override("font_color", GameTheme.WARN)
	panel.tooltip_text = "민심 %d · 건강 %d · 치안 %d\n주거 %d / %d명" % [session.state.mood, session.state.health, session.state.security, WeekSim.capacity(session.state, session.content, "housing"), session.state.pop]
	if _pending() and decision_hidden:
		var pending := _button(box, "대기 중인 결정 열기  F", _open_decision, false, "ReopenDecision")
		_primary(pending)

func _tutorial_strip() -> void:
	var step := ChronicleRules.tutorial_step(session.state)
	if step < 0 or step >= 7: return
	var panel := PanelContainer.new()
	panel.name = "TutorialCard"
	panel.add_theme_stylebox_override("panel", PixelTheme.frame(Color("1c3539"), GameTheme.TEAL, 12))
	interface.add_child(panel)
	# 짧은 안내만 표시하고 상세 설명은 도움말에 둔다.
	_place(panel, Rect2(24, 422, 274, 0))
	var box := _box(panel)
	box.add_theme_constant_override("separation", 6)
	_heading(box, "첫 통치  %d / 7" % (step + 1), false, GameTheme.TEAL)
	var instructions := ["특전 3개 중 1개를 선택하세요.", "사건의 비용과 결과를 확인하고 결정하세요.", "농지 2구획을 추가로 예약하세요.", "건설 인력 8명을 배치하세요.", "다음 주를 눌러 2주를 진행하세요.", "집무실에서 인물을 접견하세요.", "모은 특전과 특전 세트 효과를 확인하세요."]
	_label(box, instructions[step], 16)
	var row := _row(box)
	_button(row, "진행하기", func(): _tutorial_route(step), false, "TutorialAction")
	_button(row, "접기", func(): session.state.tutorial.enabled = false; _changed("안내를 접었습니다. 도움말에서 다시 켤 수 있습니다."), false, "SkipTutorial")

func _select_site(site: String) -> void:
	match site:
		"housing": selected_facility = "B01"; facility_group = "생활"; construction_tab = "facilities"; _go("build")
		"work": construction_tab = "labor"; _go("build")
		"storage": selected_facility = "B22"; facility_group = "기반"; construction_tab = "facilities"; _go("build")
		"council": _go("people")
		"farms": selected_facility = "B13"; facility_group = "기반"; construction_tab = "facilities"; _go("build")
		"trade": _go("trade")
		_:
			if session.content.facilities.has(site): selected_facility = site; construction_tab = "facilities"; _go("build")

func _tutorial_inline(parent: Node) -> void:
	var step := ChronicleRules.tutorial_step(session.state)
	if step < 0 or step >= 7: return
	var row := _row(parent)
	row.name = "TutorialCard"
	var instructions := ["특전 1개 선택", "사건 결정", "농지 2구획 예약", "건설 인력 8명 배치", "2주 진행", "인물 접견", "특전 확인"]
	_label(row, "첫 통치 %d/7  ·  %s" % [step + 1, instructions[step]], 17, GameTheme.TEAL)
	_button(row, "진행하기", func(): _tutorial_route(step), false, "TutorialAction")
	_button(row, "접기", func(): session.state.tutorial.enabled = false; _changed("안내를 접었습니다."), false, "SkipTutorial")

func _decision_identity() -> String:
	if not _pending(): return ""
	return str(session.state.week) + ":" + str(session.state.perk_offer) + ":" + str(session.state.active_event) + ":" + str(session.state.get("contract_offer", []))

func _open_decision() -> void:
	decision_hidden = false
	page = "estate"
	_render()

func _focus_decision() -> void:
	if is_instance_valid(current_modal):
		for node in current_modal.find_children("*", "Button", true, false):
			if not node.disabled: node.grab_focus(); return

func _decision_popup() -> void:
	var shade := _shade(interface, .78)
	shade.name = "DecisionBlocker"
	var s := session.state
	var title := "특전 선택" if not s.perk_offer.is_empty() else ("영주의 결정" if s.active_event != "" else "계절 계약")
	var content := _window(title, Vector2(minf(1080, size.x - 96), minf(570, size.y - 100)), false, true)
	current_modal = content.get_parent()
	var top := _row(content)
	_label(top, "%d주  ·  선택 전까지 시간 정지" % s.week, 16, GameTheme.MUTED)
	_button(top, "영지 확인 · 나중에 결정", func(): decision_hidden = true; page = "estate"; _render(), false, "InspectEstate")
	if not s.perk_offer.is_empty():
		_perk_choices(content)
	elif s.active_event != "":
		_event_choices(content)
	else:
		_contract_choices(content)
	_focus_decision.call_deferred()

func _perk_choices(parent: Node) -> void:
	var s := session.state
	_label(parent, "이번 회차에 적용할 특전을 1개 선택하세요. 같은 계열 2개·4개를 모으면 추가 효과가 생깁니다.", 17)
	var counts := ChronicleRules.family_counts(session.content, s)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	for id in s.perk_offer:
		var perk: Dictionary = session.content.progression.perks[id]
		var family: Dictionary = session.content.chronicle.families[perk.family]
		var box := _card(row)
		box.get_parent().add_theme_stylebox_override("panel", PixelTheme.frame(Color("203134"), Color(family.color), 18))
		var cap := _row(box)
		_icon(cap, {"agriculture":"food", "provisions":"fuel", "industry":"tools", "court":"mood"}[perk.family], 48)
		_heading(cap, family.name, false, Color(family.color))
		_heading(box, perk.name, true)
		_label(box, perk.description, 19)
		_label(box, "계열 보유  %d → %d개" % [counts[perk.family], counts[perk.family] + 1], 17, Color(family.color))
		var tier := int(counts[perk.family]) + 1
		_label(box, "특전 세트 효과 발동!" if tier in [2, 4] else "다음 세트까지 %d개" % ((2 if tier < 2 else 4) - tier) if tier < 4 else "4개 세트 적용 중", 16, GameTheme.GOLD if tier in [2, 4] else GameTheme.MUTED)
		var space := Control.new()
		space.size_flags_vertical = SIZE_EXPAND_FILL
		box.add_child(space)
		_primary(_button(box, "이 특전 획득", func(): session.choose_perk(id); _changed(perk.name + " 획득 · 이번 회차에 적용됩니다."), false, "perk_" + id))
	var bottom := _row(parent)
	_label(bottom, "보유 특전 %d개 / 이번 회차 최대 8개" % s.perks.size(), 16, GameTheme.MUTED)
	_button(bottom, "후보 교환 · %d회" % s.refreshes, func(): session.refresh_perks(); _changed("특전 후보를 교환했습니다."), s.refreshes <= 0, "RefreshPerks")

func _event_choices(parent: Node) -> void:
	var event: Dictionary = RealmRules.event_definition(session.state,session.content,session.state.active_event)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var person := _box(row)
	person.custom_minimum_size.x = 208
	person.size_flags_horizontal = 0
	_face(person, event.get("portrait", "CH01"), 192)
	_heading(person, event.speaker, false, GameTheme.GOLD)
	var words := _box(row)
	_heading(words, event.title, true)
	_label(words, event.body, 19)
	var choices := _scroll(words)
	choices.get_parent().name = "EventOptionsScroll"
	for i in event.options.size():
		var option: Dictionary = event.options[i]
		var error := session.option_error(option)
		var pick := _button(choices, "%d   %s" % [i + 1, option.label], func(): _resolve(i), error != "", "event_option_%d" % i)
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_label(choices, option.hint if error == "" else error, 16, GameTheme.TEAL if error == "" else GameTheme.WARN)
		pick.tooltip_text = option.hint

func _contract_choices(parent: Node) -> void:
	_label(parent, "계절 말까지 달성할 목표를 고르세요. 준비 비용을 먼저 내며, 성공하면 물자와 공훈 3점을 얻습니다.", 17)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	for id in session.state.contract_offer:
		var mission: Dictionary = session.content.chronicle.missions[id]
		var box := _card(row)
		var head := _row(box)
		_face(head, mission.character, 54)
		_heading(head, mission.name)
		_label(box, mission.description, 18)
		_label(box, "준비  " + _resources_text(mission.cost), 16, GameTheme.WARN)
		_label(box, "성공  " + _resources_text(mission.reward) + "\n공훈 +3", 16, GameTheme.TEAL)
		var spacer := Control.new()
		spacer.size_flags_vertical = SIZE_EXPAND_FILL
		box.add_child(spacer)
		var error := ChronicleRules.contract_error(session.content, session.state, id)
		_primary(_button(box, "계약 수락" if error == "" else "준비 물자 부족", func(): session.choose_contract(id); _changed("계약을 수락했습니다."), error != "", "contract_" + id))
	_button(parent, "이번에는 건너뛰기 · 비용과 보상 없음", func(): session.choose_contract("skip"); _changed("이번 계약을 건너뛰었습니다."), false, "SkipContract")

func _resolve(index: int) -> void:
	var event: Dictionary = RealmRules.event_definition(session.state,session.content,session.state.active_event)
	var before: Dictionary = session.state.duplicate(true)
	var error := session.choose_event(index)
	if error != "": _message(error); return
	var changes: Array[String] = []
	for key in ["money", "food", "wood", "stone", "tools", "fuel"]:
		var delta: float = session.state.public[key] - before.public[key]
		if not is_zero_approx(delta): changes.append(("금고 %+.2f금" % (delta / 100.0)) if key == "money" else RESOURCES[key] + " %+.0f" % delta)
	for key in ["mood", "health", "security", "trust", "pop", "village", "guild"]:
		var delta: float = session.state.get(key, 0) - before.get(key, 0)
		if not is_zero_approx(delta): changes.append({"mood":"민심", "health":"건강", "security":"치안", "trust":"오딜 신뢰", "pop":"주민", "village":"촌락 태도", "guild":"상인 조합"}[key] + " %+.0f" % delta)
	var resident_food: float = session.state.resident.food - before.resident.food
	if not is_zero_approx(resident_food): changes.append("주민 식량 %+.0f" % resident_food)
	var discount: float = session.state.get("trade_discount", 0.0) - before.get("trade_discount", 0.0)
	if not is_zero_approx(discount): changes.append("운송 수수료 -%.0f%%" % (discount * 100))
	decision_result = {"title":event.title, "speaker":event.speaker, "portrait":event.get("portrait", "CH01"), "choice":event.options[index].label, "hint":event.options[index].hint, "changes":changes}
	_changed("결정을 적용했습니다.")

func _result_popup() -> void:
	_shade(interface, .78).name = "DecisionBlocker"
	var content := _window("결정 결과", Vector2(780, 450), false, true)
	current_modal = content.get_parent()
	var row := _row(content)
	_face(row, decision_result.portrait, 144)
	var words := _box(row)
	_heading(words, decision_result.title, true)
	_label(words, "선택  " + decision_result.choice, 18, GameTheme.GOLD)
	_label(words, decision_result.hint, 18)
	_label(words, "실제 변화\n" + (" · ".join(decision_result.changes) if not decision_result.changes.is_empty() else "즉시 자원 변화 없음"), 19, GameTheme.TEAL)
	_primary(_button(content, "확인 · 계속하기", func(): decision_result.clear(); _render(), false, "AcknowledgeDecision"))
	_focus_decision.call_deferred()

func _construction(parent: Node) -> void:
	if construction_tab == "labor":
		_labor_window(parent)
		return
	if construction_tab == "queue":
		super._construction(_window_scroll(parent))
		return
	var tabs := _row(parent)
	for entry in [["facilities", "시설 건설"], ["labor", "노동 배치"], ["queue", "공사 현황"]]:
		var button := _button(tabs, entry[1], func(): construction_tab = entry[0]; _render(), false, "build_tab_" + entry[0])
		if construction_tab == entry[0]: _primary(button)
	_label(tabs, "예약 %d · 공사 %d" % [session.state.orders.size(), session.state.projects.size()], 16, GameTheme.MUTED)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var catalogue := _scroll(row)
	catalogue.get_parent().custom_minimum_size.x = 310
	catalogue.get_parent().size_flags_horizontal = 0
	for id in session.content.facilities:
		var facility: Dictionary = session.content.facilities[id]
		if facility.grade == "T": continue
		var button := _button(catalogue, "%s   ×%d" % [facility.name, session.state.facilities.get(id, 0)], func(): selected_facility = id; _render(), false, "facility_" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if selected_facility == id: _primary(button)
	var detail := _scroll(row)
	var facility: Dictionary = session.content.facilities[selected_facility]
	var cost: Dictionary = Constants.GRADE_COST[facility.grade]
	var preview_row := _row(detail)
	var picture := TextureRect.new()
	for item in EstateBoard.BUILDINGS:
		if item[0] == selected_facility: picture.texture = assets.texture("building_" + item[1]); break
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(128, 128)
	preview_row.add_child(picture)
	var words := _box(preview_row)
	_heading(words, facility.name, true)
	_label(words, _facility_hint(selected_facility), 20)
	_label(words, "보유 %d개 · 작업량 %d인주" % [session.state.facilities.get(selected_facility, 0), cost.work], 18, GameTheme.MUTED)
	var costrow := _row(detail)
	for item in [["money", "%d금" % cost.gold], ["wood", str(cost.wood)], ["stone", str(cost.stone)], ["tools", str(cost.tools)]]:
		var chip := _row(costrow)
		_icon(chip, item[0], 30)
		_tag(chip, item[1], GameTheme.GOLD, 18)
	_label(detail, "다음 주에 자재 결제 · 건설 인력이 필요합니다.", 18, GameTheme.MUTED)
	var error := _build_error(selected_facility)
	var build := _button(detail, "착공 예약" if error == "" else error, func(): _command_build(selected_facility), error != "", "build_" + selected_facility)
	_primary(build)
	_button(detail, "노동 인력 배치", func(): construction_tab = "labor"; _render())
	if session.state.assign.build == 0: _label(detail, "건설 요청 인원이 0명입니다. 예약 후 건설 인력을 배치하세요.", 17, GameTheme.WARN)
	for project in session.state.projects:
		if project.id == selected_facility:
			_bar(detail, 1.0 - project.work_left / maxf(1, project.work_total), "info")
			_label(detail, "진행 중 · 남은 작업 %d인주" % project.work_left, 16)

func _labor_window(parent: Node) -> void:
	var tabs := _row(parent)
	for entry in [["facilities", "시설 건설"], ["labor", "노동 배치"], ["queue", "공사 현황"]]:
		var button := _button(tabs, entry[1], func(): construction_tab = entry[0]; _render(), false, "build_tab_" + entry[0])
		if construction_tab == entry[0]: _primary(button)
	var body := _window_scroll(parent)
	labor_summary = _label(body, "", 20)
	labor_actual = _label(body, "", 18, GameTheme.TEAL)
	labor_fields.clear()
	var presets := _row(body)
	_button(presets, "건설 우선 · 8명", func(): _labor_preset({"gather":8, "build":8}), not _is_active(), "BuildPreset")
	_button(presets, "장작 생산 배치", func(): _labor_preset({"gather":8, "logging":2, "fuel":2}), not _is_active(), "WinterPreset")
	_label(body, "농사 인원은 자동 확보합니다. 남은 인력은 채집 → 건설 → 생산 순으로 배치됩니다.", 18, GameTheme.MUTED)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for text in ["작업", "요청", "실제 배치", "작업장 한도"]: _heading(grid, text)
	for id in JOBS:
		var cap := _job_cap(id)
		if cap <= 0 and session.state.assign.get(id, 0) == 0 and not show_unavailable_jobs: continue
		_label(grid, JOBS[id], 20).custom_minimum_size.x = 140
		var input := SpinBox.new()
		input.name = "job_" + id
		input.custom_minimum_size.x = 160
		input.max_value = floor(session.state.pop * session.state.labor_ratio)
		input.value = session.state.assign.get(id, 0)
		input.editable = _is_active()
		input.value_changed.connect(func(value):
			if not _is_active(): return
			var previous := ChronicleRules.tutorial_step(session.state)
			session.state.assign[id] = int(value)
			_sync_tutorial()
			_save()
			_refresh_labor_preview()
			if previous != ChronicleRules.tutorial_step(session.state): _render.call_deferred()
		)
		grid.add_child(input)
		labor_fields[id] = _label(grid, "", 20, GameTheme.TEAL)
		labor_fields[id].custom_minimum_size.x = 215
		_label(grid, "%d명" % cap if cap > 0 else "작업장 없음", 20, GameTheme.MUTED)
	_button(body, "없는 작업장 접기" if show_unavailable_jobs else "전체 작업 보기", func(): show_unavailable_jobs = not show_unavailable_jobs; _render())
	_refresh_labor_preview()

func _landscape(parent: Node, season_index: int, min_height: float = 240.0) -> void:
	var landscape := TextureRect.new()
	landscape.texture = assets.texture("terrain_" + ["spring", "summer", "autumn", "winter"][season_index])
	landscape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	landscape.custom_minimum_size.y = min_height
	landscape.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(landscape)

func _boons(parent: Node) -> void:
	var s := session.state
	var counts := ChronicleRules.family_counts(session.content, s)
	var families := _row(parent)
	for id in counts:
		var family: Dictionary = session.content.chronicle.families[id]
		var box := _box(families)
		_heading(box, "%s  %d / 4" % [family.name, counts[id]], false, Color(family.color))
		_bar(box, counts[id] / 4.0, "info")
		box.tooltip_text = family.description
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var inventory := _scroll(row)
	_heading(inventory, "획득한 특전  %d / 8" % s.perks.size())
	if selected_perk not in s.perks: selected_perk = "" if s.perks.is_empty() else s.perks[0]
	for id in s.perks:
		var perk: Dictionary = session.content.progression.perks[id]
		var button := _button(inventory, perk.name, func(): selected_perk = id; _render(), false, "owned_" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = assets.texture("icon_" + {"agriculture":"food", "provisions":"fuel", "industry":"tools", "court":"mood"}[perk.family])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		if selected_perk == id: _primary(button)
	if s.perks.is_empty(): _label(inventory, "아직 획득한 특전이 없습니다.", 20)
	var details := _scroll(row)
	if selected_perk != "":
		var perk: Dictionary = session.content.progression.perks[selected_perk]
		var family: Dictionary = session.content.chronicle.families[perk.family]
		_heading(details, perk.name, true)
		_label(details, perk.description, 22, GameTheme.TEAL)
		_label(details, family.name + " 계열 · " + family.description, 18)
		_label(details, "%d개 보유 · %s" % [counts[perk.family], "4개 세트 적용 중" if counts[perk.family] >= 4 else "2개 세트 적용 중" if counts[perk.family] >= 2 else "1개 더 모으면 특전 세트 효과"], 18, GameTheme.GOLD)
	if ChronicleRules.active(s):
		_heading(details, "영주 특성")
		for id in s.traits:
			var trait_data: Dictionary = session.content.chronicle.traits[id]
			_label(details, trait_data.name + " · " + trait_data.description, 18, GameTheme.WARN if trait_data.get("flaw", false) else GameTheme.TEXT)
		_heading(details, "부임 물자")
		for id in s.relics:
			var relic: Dictionary = session.content.chronicle.relics[id]
			_label(details, relic.name + " · " + relic.description, 18, GameTheme.TEAL)
		_heading(details, "현재 합산 효과")
		var effect_names := {"harvest":"수확", "sow_labor":"파종 노동", "seed":"종자 소모", "gather":"채집", "logging":"벌목", "tool_use":"도구 소모", "maintenance":"유지비", "wages":"공공 급여", "buy":"구매가", "storage":"저장 용량", "heating":"난방 소비", "tax":"수금률", "trust":"면담 신뢰", "winter_gather":"겨울 채집"}
		for key in s.bonuses:
			var amount: float = s.bonuses[key]
			var value := ("+%.0f" % amount if key == "trust" else "+%.0f%%p" % (amount * 100)) if key in ChronicleRules.ADDITIVE else "%+.0f%%" % ((amount - 1) * 100)
			_label(details, effect_names.get(key, key) + " " + value, 18, GameTheme.TEAL)
	else:
		_label(details, "이전 회차 규칙입니다. 특전 세트과 부임 물자는 새 회차부터 적용됩니다.", 18, GameTheme.WARN)
	_label(parent, "이번 회차에만 적용 · 다음 회차에서는 특전을 다시 수집합니다.", 18, GameTheme.MUTED)

func _archive(parent: Node) -> void:
	var head := _row(parent)
	_heading(head, "%d 공훈" % session.profile.points, true, GameTheme.GOLD)
	_label(head, "구매한 효과는 다음 회차부터 적용됩니다.", 18, GameTheme.TEAL)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var inventory := _scroll(row)
	for id in session.content.progression.upgrades:
		var upgrade: Dictionary = session.content.progression.upgrades[id]
		var button := _button(inventory, upgrade.name + (" · 보유" if id in session.profile.upgrades else " · %d점" % upgrade.cost), func(): selected_upgrade = id; _render(), false, "meta_" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if selected_upgrade == id: _primary(button)
	var detail := _scroll(row)
	var upgrade: Dictionary = session.content.progression.upgrades[selected_upgrade]
	_heading(detail, upgrade.name, true)
	_label(detail, upgrade.description, 22, GameTheme.TEAL)
	var owned: bool = selected_upgrade in session.profile.upgrades
	var prerequisite: bool = upgrade.requires != "" and upgrade.requires not in session.profile.upgrades
	if prerequisite: _label(detail, "먼저 구매: " + session.content.progression.upgrades[upgrade.requires].name, 18, GameTheme.WARN)
	_primary(_button(detail, "구매 완료" if owned else "구매 · %d 공훈" % upgrade.cost, func(): _upgrade(selected_upgrade), owned or prerequisite or session.profile.points < upgrade.cost or load_blocked, "upgrade_" + selected_upgrade))
	_heading(detail, "회차 기록")
	_label(detail, "발견한 특전 %d / 24개 · 완료한 회차 %d회" % [session.profile.get("discoveries", []).size(), session.profile.get("chronicles", []).size()], 18)
	for record in session.profile.get("chronicles", []).slice(-3):
		_label(detail, "%d주 · %s · 공훈 +%d" % [record.week, "성공" if record.success else record.reason, record.points], 18, GameTheme.MUTED)
	_label(parent, "13주 생존 이후 보상 지급 · 계절 생존 +2 · 계약 달성 +3 · 기본 목표당 +6 · 시련 달성 +6", 18, GameTheme.MUTED)
	_button(parent, "새 회차 준비" if not _is_active() else "영지로 돌아가기", _open_prepare if not _is_active() else _continue, load_blocked)

func _market(parent: Node) -> void:
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var stock := _box(row)
	stock.size_flags_horizontal = 0
	stock.custom_minimum_size.x = 290
	for id in RESOURCES:
		var button := _button(stock, "%s    %.0f" % [RESOURCES[id], session.state.public[id]], func(): selected_goods = id; _render(), false, "goods_" + id)
		button.icon = assets.texture("icon_" + id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == selected_goods: _primary(button)
	_label(stock, "공공 재고만 거래합니다.\n운송 기간 2주 · 수레 3대", 16, GameTheme.MUTED)
	var detail := _scroll(row)
	var id := selected_goods
	_heading(detail, RESOURCES[id] + " 거래", true)
	_label(detail, "구매는 선불입니다. 판매 대금은 수레가 도착하면 받습니다. 표시 가격에 운송료가 포함됩니다.", 18)
	var controls := _row(detail)
	_label(controls, "거래 수량", 18)
	var quantity := SpinBox.new()
	quantity.name = "quantity_" + id
	quantity.min_value = 1
	quantity.max_value = 200
	quantity.value = int(trade_quantities.get(id, {"food":200, "wood":40, "stone":40, "tools":8, "fuel":120}[id]))
	quantity.custom_minimum_size.x = 180
	quantity.editable = _is_active() and not busy
	controls.add_child(quantity)
	var buttons := _row(detail)
	var buy := _button(buttons, "", func(): _command_trade(id, int(quantity.value), true), false, "buy_" + id)
	var sell := _button(buttons, "", func(): _command_trade(id, int(quantity.value), false), false, "sell_" + id)
	_primary(buy)
	var reason := _label(detail, "", 17, GameTheme.TEAL)
	reason.name = "trade_reason_" + id
	quantity.value_changed.connect(func(value): trade_quantities[id] = int(value); _refresh_quote(id, int(value), buy, sell, reason))
	_refresh_quote(id, int(quantity.value), buy, sell, reason)
	_heading(detail, "운송 중  %d / 3대" % session.state.shipments.size())
	for shipment in session.state.shipments:
		_label(detail, "%s %d · %s · %d주 뒤 도착" % [RESOURCES[shipment.asset], shipment.quantity, "구매" if shipment.buy else "판매", maxi(0, shipment.arrival - session.state.week)], 17)
	if session.state.shipments.is_empty(): _label(detail, "운송 중인 수레가 없습니다.", 17, GameTheme.MUTED)

func _people(parent: Node) -> void:
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var roster := _scroll(row)
	roster.get_parent().custom_minimum_size.x = 310
	roster.get_parent().size_flags_horizontal = 0
	var data: Dictionary = session.content.chronicle.characters
	for id in data:
		var button := _button(roster, data[id].name, func(): selected_person = id; _render(), false, "person_" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = assets.texture("portrait_" + id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
		if selected_person == id: _primary(button)
	var detail := _scroll(row)
	var person: Dictionary = data[selected_person]
	var head := _row(detail)
	_face(head, selected_person, 144)
	var identity := _box(head)
	_heading(identity, person.name, true, GameTheme.GOLD)
	_label(identity, person.role + " · " + person.age, 17, GameTheme.TEAL)
	_label(identity, person.quote, 19)
	_label(detail, "이번 주 접견 %d회 남음" % session.state.actions, 17, GameTheme.MUTED)
	_label(detail, person.action + "  ·  " + person.benefit, 19, GameTheme.TEAL)
	var locked: bool = not _is_active() or not ChronicleRules.active(session.state) or session.state.actions <= 0 or "council_" + selected_person in session.state.actions_used
	_primary(_button(detail, "접견하기 · 일정 1회", func():
		var error := session.council_visit(selected_person)
		if error == "": _changed(person.name + " 접견 완료 · " + person.benefit)
		else: _message(error)
	, locked, "CouncilVisit"))
	_label(detail, "같은 인물은 한 주에 한 번 접견할 수 있습니다.", 16, GameTheme.MUTED)

func _journey(parent: Node) -> void:
	var s := session.state
	_heading(parent, "%d회차  /  %d주 진행 중" % [session.profile.runs, s.week], true)
	_label(parent, "특전은 이번 회차에만 적용됩니다. 계절을 버티고 계약을 달성해 공훈을 확보하세요.", 18)
	var road := _row(parent)
	for i in 4:
		var box := _card(road, ["봄", "여름", "가을", "겨울"][i])
		_label(box, "%d–%d주" % [i * 13 + 1, (i + 1) * 13], 18)
		_bar(box, clampf((float(s.week) - 1 - i * 13) / 13, 0, 1), "good")
		_label(box, "특전 2회\n계절 생존 +2점", 16, GameTheme.TEAL)
	_heading(parent, _next_reward_text(), false, GameTheme.GOLD)
	if ChronicleRules.active(s):
		var trial: Dictionary = session.content.chronicle.trials[s.trial]
		_label(parent, "40주 시련 시작 · " + trial.name + "\n" + trial.description, 18, GameTheme.WARN)
		if not s.contract.is_empty():
			var mission: Dictionary = session.content.chronicle.missions[s.contract.id]
			_label(parent, "진행 중인 계약 · %s\n%d주 평가 · 현재 %.1f / 목표 %.1f" % [mission.name, s.contract.deadline, ChronicleRules.value(s, mission.target), mission.threshold], 18, GameTheme.TEAL)
	_objectives(parent)
	var actions := _row(parent)
	_button(actions, "다음 결정까지 진행", func(): _advance(13), busy, "AdvanceUntilChoice")
	_button(actions, "주간 보고 · 장부", func(): _go("ledger"), false, "nav_ledger")
	_button(actions, "현재 회차 결산", _ask_retire, not _is_active(), "RetireRun")

func _go(target: String) -> void:
	focus_return = page
	if target == "estate" and _pending(): decision_hidden = true
	super._go(target)

func _advance(count: int) -> void:
	if not decision_result.is_empty(): return
	if _pending(): _open_decision(); return
	decision_hidden = false
	await super._advance(count)

func _help() -> void:
	help_open = true
	_render()

func _help_popup() -> void:
	_shade(interface, .78)
	var content := _window("플레이 안내", Vector2(850, 530), false, true)
	current_modal = content.get_parent()
	_label(content, "영지의 건물을 누르거나 아래 메뉴로 관리 창을 엽니다. 시설을 예약한 뒤 노동 인력을 배치하고, 다음 주로 진행하세요.", 19)
	_label(content, "회차마다 달라지는 것\n지역 · 영주 특성 · 부임 물자 · 특전 선택 · 계절 계약 · 겨울 시련\n\n다음 회차에도 남는 것\n공훈 · 가문 강화 · 발견한 특전 기록", 18, GameTheme.TEAL)
	_label(content, "Space 다음 주  /  1–6 관리 창  /  F 결정 확인  /  Esc 창 닫기\n사건이 발생하면 시간이 멈춥니다. 영지 상태를 확인한 뒤 결정을 다시 열 수 있습니다.", 17, GameTheme.MUTED)
	if _is_active() and ChronicleRules.active(session.state):
		_button(content, "튜토리얼 다시 켜기", func(): help_open = false; session.state.tutorial = {"enabled":true, "step":0}; _go("estate"); _save(), false, "ReplayTutorial")
	_primary(_button(content, "확인", func(): help_open = false; _render(), false, "CloseHelp"))

func _toast() -> void:
	if notice == "" or notice == "저장 완료": return
	if notice != toast_message:
		toast_message = notice
		toast_expiry = Time.get_ticks_msec() + 4500
	if Time.get_ticks_msec() > toast_expiry: return
	var toast := PanelContainer.new()
	toast.mouse_filter = MOUSE_FILTER_IGNORE
	toast.add_theme_stylebox_override("panel", PixelTheme.frame(Color("142326"), Color("587673"), 8))
	interface.add_child(toast)
	_place(toast, Rect2(430, size.y - 130, size.x - 450, 38))
	notice_label = _label(toast, notice, 16, GameTheme.TEAL)
	notice_label.mouse_filter = MOUSE_FILTER_IGNORE
	notice_label.max_lines_visible = 1
	notice_label.tooltip_text = notice
	# 모달의 선택 버튼을 가리지 않는다.
	toast.visible = not is_instance_valid(current_modal)
	var fade := create_tween().bind_node(toast)
	fade.tween_interval(maxf(.1, (toast_expiry - Time.get_ticks_msec()) / 1000.0))
	fade.tween_property(toast, "modulate:a", 0.0, .3)

func _input(event: InputEvent) -> void:
	if _handle_quit_input(event): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event.keycode == KEY_ESCAPE:
		if help_open: help_open = false; _render()
		elif not decision_result.is_empty(): decision_result.clear(); _render()
		elif _pending() and not decision_hidden: decision_hidden = true; page = "estate"; _render()
		elif page not in ["menu", "prepare", "estate"]: _go("estate")
		elif page == "estate": _go("menu")
		else: return
	elif is_instance_valid(current_modal): return
	elif page in ["menu", "prepare", "result"]: return
	elif event.keycode == KEY_SPACE and _is_active(): _advance(1)
	elif event.keycode == KEY_F and _pending(): _open_decision()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_6: _go(DOCK[event.keycode - KEY_1][0])
	else: return
	get_viewport().set_input_as_handled()
