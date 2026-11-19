extends "res://ui/world_ui.gd"
## 플레이의 기본 단위는 주간 보고 → 계획 수정 → 한 주 운영이다.

const SECTIONS := [["estate", "주간 보고"], ["build", "개발·노동"], ["trade", "교역"], ["people", "인물 접견"], ["boons", "특전·특성"], ["ledger", "수입·지출"], ["journey", "회차 목표"]]
var brief: Dictionary = {}
var last_turn: Dictionary = {}
var receipt: Dictionary = {}
var report_status: Label
var paper_ready := false

func _ink(color: Color) -> Color:
	if color == TycoonTheme.NAV_TEXT: return color
	if color == GameTheme.TEXT: return TycoonTheme.INK
	if color == GameTheme.MUTED: return TycoonTheme.MUTED
	if color in [GameTheme.GOLD, GameTheme.TEAL, GameTheme.INFO]: return TycoonTheme.ACCENT
	if color == GameTheme.GOOD: return TycoonTheme.GOOD
	if color == GameTheme.WARN: return TycoonTheme.WARN
	if color in [GameTheme.BAD, GameTheme.RED]: return TycoonTheme.BAD
	return color.darkened(.5) if color.get_luminance() > .45 else color

func _label(parent: Node, text: String, px: int = 20, color: Color = GameTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", maxi(18, px))
	label.add_theme_color_override("font_color", _ink(color))
	label.add_theme_constant_override("line_spacing", 5)
	parent.add_child(label)
	return label

func _heading(parent: Node, text: String, large: bool = false, color: Color = GameTheme.TEXT) -> Label:
	var label := _label(parent, text, 32 if large else 22, color)
	label.add_theme_font_override("font", PixelTheme.heading_font())
	return label

func _primary(button: Button) -> void:
	button.theme_type_variation = "PrimaryButton"

func _quiet(button: Button) -> Button:
	button.theme_type_variation = "QuietButton"
	return button

func _icon(_parent: Node, _key: String, _px: int = 24) -> void:
	pass

func _card(parent: Node, title: String = "") -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", TycoonTheme.panel(Color.TRANSPARENT, TycoonTheme.LINE, 14))
	parent.add_child(frame)
	var box := _box(frame)
	if title != "": _heading(box, title)
	return box

func _rule(parent: Node) -> void:
	parent.add_child(HSeparator.new())

func _bar(parent: Node, ratio: float, _level: String = "") -> void:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0, 1)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	parent.add_child(bar)

func _paper(rect: Rect2, inset: int = 0, color: Color = TycoonTheme.PAPER) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", TycoonTheme.panel(color, Color.TRANSPARENT, inset))
	interface.add_child(panel)
	_place(panel, rect)
	return _box(panel)

func _render() -> void:
	if not paper_ready:
		theme = TycoonTheme.create(assets.body_font())
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paper_ready = true
		pixel_ready = true
	if is_instance_valid(main_scroll): scroll_positions[rendered_page] = main_scroll.scroll_vertical
	main_scroll = null
	current_modal = null
	if not is_instance_valid(board):
		board = EstateBoard.new()
		board.name = "EstateWorld"
		board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		board.site_selected.connect(_select_site)
		add_child(board)
	board.visible = page == "world"
	if board.visible:
		board.season = mini(3, int((int(session.state.get("week", 1)) - 1) / 13))
		board.backdrop = assets.texture("terrain_" + ["spring", "summer", "autumn", "winter"][board.season])
		board.configure(assets, session.state, _is_active())
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shell.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(shell)
	interface = Control.new()
	interface.name = "StewardInterface"
	interface.mouse_filter = MOUSE_FILTER_IGNORE
	shell.add_child(interface)
	if page != "world":
		var background := TextureRect.new()
		background.name = "StudyBackdrop"
		background.texture = assets.texture("study")
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		background.mouse_filter = MOUSE_FILTER_IGNORE
		interface.add_child(background)
	brief = WeeklyBrief.build(session.state, session.content) if not session.state.is_empty() else {}
	forecast = WeekSim.forecast(session.state, session.content) if _is_active() else {}
	if page == "menu":
		_reading_menu()
	elif page == "prepare":
		var content := _window("", Vector2(minf(1120, size.x - 80), size.y - 64), false)
		_prepare(content)
	else:
		_study_hud()
		_navigation()
		var left := 60.0
		var width := size.x - left * 2
		if page != "world":
			var book := JournalFrame.new()
			book.name = "OpenLedger"
			interface.add_child(book)
			_place(book, Rect2(26, 148, size.x - 52, size.y - 156))
		_reading_header(Rect2(left, 174, width, 34))
		var body := _paper(Rect2(left, 222, width, size.y - 330))
		body.get_parent().name = "ReadingSurface"
		if page == "world": body.get_parent().visible = false
		match page:
			"estate": _weekly_report(body)
			"build": _development(body)
			"trade": _reading_market(body)
			"people": _people(body)
			"boons": _boons(body)
			"ledger": _accounts(_window_scroll(body))
			"journey": _journey(_window_scroll(body))
			"archive": _archive(body)
			"result": _result(_window_scroll(body))
		_reading_footer(Rect2(left, size.y - 92, width, 58))
		if _is_active():
			var key := _decision_identity()
			if key != decision_key:
				decision_hidden = false
				decision_key = key
			if _pending() and not decision_hidden: _decision_popup()
	if help_open: _help_popup()
	# 항목 식별에 텍스트를 쓴다. 작은 버튼 아이콘은 이 화면에서 제거한다.
	for button in interface.find_children("*", "Button", true, false): button.icon = null
	rendered_page = page
	_restore_scroll.call_deferred(page, int(scroll_positions.get(page, 0)))

func _reading_menu() -> void:
	var height := minf(620, size.y - 96)
	var box := _paper(Rect2(64, (size.y - height) * .5, 475, height), 30, TycoonTheme.NAV)
	box.get_parent().add_theme_stylebox_override("panel", TycoonTheme.panel(TycoonTheme.NAV, Color("a87945"), 30))
	_label(box, "영지 경영 · 로그라이트", 18, TycoonTheme.NAV_TEXT)
	var title := _heading(box, "변경의\n신임 영주가 되었다", true, TycoonTheme.NAV_TEXT)
	title.add_theme_font_size_override("font_size", 38)
	_label(box, "52주 동안 영지를 개발하고\n식량을 비축해 겨울을 넘기세요.", 20, TycoonTheme.NAV_TEXT)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	box.add_child(gap)
	if _is_active():
		_label(box, "%d회차 · %d주 · 주민 %d명" % [session.profile.runs, session.state.week, session.state.pop], 20, TycoonTheme.NAV_TEXT)
		_primary(_button(box, "통치 이어 하기", _continue, load_blocked, "ContinueRun"))
	else:
		_primary(_button(box, "새 회차 준비", _open_prepare, load_blocked, "NewRun"))
		if not session.state.is_empty(): _button(box, "지난 회차 결산", func(): _go("result"))
	_button(box, "가문 강화 · %d 공훈" % session.profile.points, func(): _go("archive"), false, "OpenArchive")
	_button(box, "플레이 안내", _help, false, "OpenHelp")
	_button(box, "게임 종료", _quit_game, false, "QuitGame")
	_label(box, "공훈과 가문 강화는\n다음 회차에도 이어집니다.", 18, TycoonTheme.NAV_TEXT)

func _navigation() -> void:
	var holder := _paper(Rect2(44, 100, size.x - 88, 48), 0, Color.TRANSPARENT)
	holder.get_parent().name = "JournalTabs"
	var nav := _row(holder)
	nav.add_theme_constant_override("separation", 4)
	for entry in SECTIONS:
		if session.state.is_empty(): continue
		var button := _button(nav, entry[1], func(): _go(entry[0]), false, "nav_" + entry[0])
		button.theme_type_variation = "NavigationButton"
		if page == entry[0]: button.add_theme_stylebox_override("normal", theme.get_stylebox("pressed", "NavigationButton"))
	var stretch := Control.new()
	stretch.size_flags_horizontal = SIZE_EXPAND_FILL
	nav.add_child(stretch)
	for entry in [["world", "전경"], ["archive", "가문 강화"], ["menu", "메뉴"]]:
		if session.state.is_empty() and entry[0] == "world": continue
		var button := _button(nav, entry[1], func(): _go(entry[0]), false, "nav_" + entry[0])
		button.theme_type_variation = "NavigationButton"
		if page == entry[0]: button.add_theme_stylebox_override("normal", theme.get_stylebox("pressed", "NavigationButton"))

func _study_hud() -> void:
	var box := _paper(Rect2(30, 20, size.x - 60, 64), 12, TycoonTheme.NAV)
	box.get_parent().name = "EstateStatus"
	box.get_parent().add_theme_stylebox_override("panel", TycoonTheme.panel(TycoonTheme.NAV, Color("a87945"), 12))
	var row := _row(box)
	row.add_theme_constant_override("separation", 24)
	_heading(row, "영주 집무실", false, TycoonTheme.NAV_TEXT)
	if session.state.is_empty(): return
	var s := session.state
	for text in ["%s %d주" % [["봄","여름","가을","겨울"][mini(3, int((int(s.week) - 1) / 13))], mini(52, s.week)], "금고 " + _money(s.public.money), "식량 %.1f주" % WeekSim.food_weeks(s), "주민 %d명" % s.pop, "민심 %d" % s.mood]:
		_tag(row, text, TycoonTheme.NAV_TEXT, 20)

func _reading_header(rect: Rect2) -> void:
	var box := _paper(rect)
	box.get_parent().name = "StatusHeader"
	var heading := _row(box)
	_heading(heading, {"estate":"이번 주 보고", "build":"영지 개발", "trade":"교역 계약", "people":"인물 접견", "boons":"특전과 운영 효과", "ledger":"수입·지출 장부", "journey":"회차 목표", "archive":"다음 회차 준비", "result":"회차 결산", "world":"영지 전경"}.get(page, "영지 집무실"), true)
	_tag(heading, "%d회차 · 52주 통치" % session.profile.runs, GameTheme.MUTED, 18)
	var help_button := _quiet(_button(heading, "도움말", _help, false, "HeaderHelp"))
	help_button.custom_minimum_size.y = 30

func _reading_footer(rect: Rect2) -> void:
	var box := _paper(rect)
	var row := _row(box)
	var copy := _box(row)
	copy.add_theme_constant_override("separation", 2)
	report_status = _label(copy, notice if notice != "" and notice != "저장 완료" else "변경한 계획은 자동 저장됩니다.", 18, GameTheme.MUTED)
	report_status.max_lines_visible = 1
	notice_label = report_status
	if _is_active():
		var button := _button(row, "대기 중인 결정 확인" if _pending() else "이번 주 진행  →", _open_decision if _pending() else func(): _advance(1), busy, "NextWeek")
		button.custom_minimum_size = Vector2(230, 52)
		button.tooltip_text = "Space · 한 주만 진행합니다."
		_primary(button)
	else: _quiet(_button(row, "메인 메뉴", func(): _go("menu")))

func _weekly_report(parent: Node) -> void:
	var columns := _row(parent)
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 30)
	var reading := _window_scroll(columns)
	reading.get_parent().name = "ReportScroll"
	reading.size_flags_stretch_ratio = 2.0
	var divider := VSeparator.new()
	columns.add_child(divider)
	var plan_scroll := ScrollContainer.new()
	plan_scroll.custom_minimum_size.x = 300
	plan_scroll.size_flags_horizontal = 0
	plan_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	plan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(plan_scroll)
	var plan := _box(plan_scroll)
	plan.name = "WeekPlan"
	var s := session.state
	if not receipt.is_empty():
		_heading(reading, "결정 완료 · " + receipt.choice, false, GameTheme.TEAL)
		_label(reading, " · ".join(receipt.changes) if not receipt.changes.is_empty() else receipt.hint, 19, GameTheme.TEAL)
		_rule(reading)
	_tutorial_note(reading)
	if not s.history.is_empty():
		_heading(reading, "%d주 운영 결과" % s.history.back().week)
		if brief.metrics.money.has_delta:
			_label(reading, "전주 말 대비  금고 %+.2f금 · 식량 %+.0f · 주민 %+d명" % [brief.metrics.money.delta / 100.0, brief.metrics.food.delta, brief.metrics.pop.delta], 21)
		elif not last_turn.is_empty() and int(last_turn.week) == int(s.history.back().week):
			_label(reading, "시간 진행 중 변화  금고 %+.2f금 · 식량 %+.0f · 주민 %+d명" % [last_turn.money / 100.0, last_turn.food, last_turn.pop], 21)
		var food: Dictionary = brief.report.food
		_label(reading, "식량 생산 +%.0f, 주민 소비 −%.0f, 보관 손실 −%.0f, 종자 사용 −%.0f입니다." % [food.production, food.consumption, food.spoilage, food.seeds], 20)
		var notes: Array = s.history.back().notes
		for text in notes.slice(-2): _label(reading, str(text), 18, GameTheme.MUTED)
		_rule(reading)
	_heading(reading, "지금 확인할 문제")
	for priority in brief.priorities.slice(0, 3):
		var section := _box(reading)
		section.add_theme_constant_override("separation", 5)
		var title_color: Color = GameTheme.BAD if priority.severity == "danger" else GameTheme.TEXT
		_heading(section, priority.title, false, title_color)
		_label(section, priority.body, 19)
		var row := _row(section)
		var link := _quiet(_button(row, priority.action + "  →", func():
			if priority.get("tab", "") != "": construction_tab = priority.tab
			if priority.get("facility", "") != "": selected_facility = priority.facility
			_go(priority.page)
		))
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rule(reading)
	if brief.priorities.is_empty(): _label(reading, "현재 긴급한 부족은 없습니다. 저장 시설과 겨울 준비 상태를 확인하세요.", 20)
	if s.history.is_empty():
		_heading(reading, "올해 통치 목표")
		_label(reading, "농지 6구획·곡물 곳간 1개·정상 배급 식량 13주분을 확보하고 겨울 시련을 통과해야 합니다.", 20)
	_heading(plan, "이번 주 실행 계획")
	_label(plan, "공사 예약 %d건 · 진행 %d건" % [s.orders.size(), s.projects.size()], 20)
	for id in s.orders: _label(plan, "예약  " + session.content.facilities[id].name, 18)
	if brief.preview.available:
		_label(plan, "건설 요청 %d명 → 배치 예상 %d명" % [s.assign.build, brief.preview.labor.get("build", 0)], 19, GameTheme.TEAL)
	else: _label(plan, "공사 조건을 먼저 확인해야 합니다.", 19, GameTheme.WARN)
	if s.orders.is_empty() and s.projects.is_empty(): _label(plan, "예정된 공사가 없습니다.", 18, GameTheme.MUTED)
	for shipment in s.shipments:
		_label(plan, "%s %d · %d주에 %s" % [RESOURCES[shipment.asset], shipment.quantity, shipment.arrival, "도착" if shipment.buy else "판매 대금 수령"], 18)
	if s.shipments.is_empty(): _label(plan, "운송 중인 교역 수레가 없습니다.", 18, GameTheme.MUTED)
	_quiet(_button(plan, "개발·노동 계획 수정", func(): _go("build")))
	_rule(plan)
	_heading(plan, "한 주 운영 후 예상")
	if brief.preview.available:
		_label(plan, "금고  " + _money(brief.preview.money), 22)
		_label(plan, "식량  %.1f주분" % brief.preview.food_weeks, 22)
		_label(plan, "식량 생산 +%.0f / 소비 −%.0f" % [brief.preview.food_flow.production, brief.preview.food_flow.consumption], 18)
		_label(plan, "경제 계산만 반영합니다. 사건·수레 도착·계약·시련의 효과와 민심·건강 결산은 제외합니다.", 18, GameTheme.MUTED).tooltip_text = brief.preview.scope
	else:
		_label(plan, " / ".join(brief.preview.blocked_reasons), 19, GameTheme.WARN)
	_rule(plan)
	_label(plan, _next_reward_text(), 18, GameTheme.TEAL)
	if ChronicleRules.active(s):
		var trial: Dictionary = session.content.chronicle.trials[s.trial]
		_label(plan, "겨울 시련 · " + trial.name, 19)
		_label(plan, trial.description, 18, GameTheme.MUTED)

func _tutorial_note(parent: Node) -> void:
	var step := ChronicleRules.tutorial_step(session.state)
	if step < 0 or step >= 7: return
	var actions := _row(parent)
	actions.name = "TutorialCard"
	var lines := ["특전은 회차 동안 적용되는 운영 효과입니다. 3개 중 1개를 고르세요.", "서신을 읽고 비용과 효과를 비교해 결정하세요.", "개발 계획에서 농지 2구획을 추가로 예약하세요.", "예약한 공사를 진행하려면 건설 인력 8명을 배치하세요.", "한 주씩 두 번 진행하면 농지 공사가 완료됩니다.", "인물을 접견해 영지 상태를 개선하세요. 주마다 2회 가능합니다.", "특전 화면에서 현재 조합과 합산 운영 효과를 확인하세요."]
	_label(actions, "첫 통치 %d / 7  ·  " % (step + 1) + lines[step], 19, GameTheme.TEAL)
	_quiet(_button(actions, "안내 이동", func(): _tutorial_route(step), false, "TutorialAction"))
	_quiet(_button(actions, "접기", func(): session.state.tutorial.enabled = false; _changed("안내를 접었습니다."), false, "SkipTutorial"))
	_rule(parent)

func _development(parent: Node) -> void:
	var tabs := _row(parent)
	for entry in [["facilities", "시설 계획"], ["labor", "인력 배치"], ["ration", "식량 배급"], ["queue", "예약·공사 현황"]]:
		var button := _quiet(_button(tabs, entry[1], func(): construction_tab = entry[0]; _render(), false, "build_tab_" + entry[0]))
		if construction_tab == entry[0]: button.add_theme_stylebox_override("normal", theme.get_stylebox("pressed", "QuietButton"))
	_rule(parent)
	if construction_tab == "labor":
		_labor_window(parent)
		return
	if construction_tab == "ration":
		_ration_policy(_window_scroll(parent))
		return
	if construction_tab == "queue":
		_construction_queue(_window_scroll(parent))
		return
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 26)
	var catalogue := _scroll(row)
	catalogue.get_parent().custom_minimum_size.x = 238
	catalogue.get_parent().size_flags_horizontal = 0
	for id in session.content.facilities:
		var facility: Dictionary = session.content.facilities[id]
		if facility.grade == "T": continue
		var button := _quiet(_button(catalogue, facility.name + "  %d" % session.state.facilities.get(id, 0), func(): selected_facility = id; _render(), false, "facility_" + id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if selected_facility == id: button.add_theme_stylebox_override("normal", theme.get_stylebox("pressed", "QuietButton"))
	row.add_child(VSeparator.new())
	var detail_panel := _box(row)
	detail_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var details := _scroll(detail_panel)
	var id := selected_facility
	var facility: Dictionary = session.content.facilities[id]
	var cost: Dictionary = Constants.GRADE_COST[facility.grade]
	var facility_head := _row(details)
	var facility_words := _box(facility_head)
	_heading(facility_words, facility.name, true)
	_label(facility_words, _facility_hint(id), 20, GameTheme.TEAL)
	for building in EstateBoard.BUILDINGS:
		if building[0] == id:
			var illustration := TextureRect.new()
			illustration.texture = assets.texture("building_" + building[1])
			illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			illustration.custom_minimum_size = Vector2(80, 80)
			illustration.mouse_filter = MOUSE_FILTER_IGNORE
			facility_head.add_child(illustration)
	_label(details, _purpose(id), 20)
	_rule(details)
	var table := GridContainer.new()
	table.columns = 3
	table.add_theme_constant_override("h_separation", 38)
	table.add_theme_constant_override("v_separation", 8)
	details.add_child(table)
	var available: Dictionary = session.state.public.duplicate(true)
	for queued_id in session.state.orders:
		var reserved: Dictionary = Constants.GRADE_COST[session.content.facilities[queued_id].grade]
		available.money -= reserved.gold * 100
		for resource in ["wood", "stone", "tools", "iron"]: available[resource] -= reserved[resource]
	for text in ["필요 자원", "착공 비용", "예약분 제외 보유"]: _label(table, text, 18, GameTheme.MUTED)
	for item in [["금고", _money(cost.gold * 100), _money(available.money)], ["목재", str(cost.wood), "%.0f" % available.wood], ["석재", str(cost.stone), "%.0f" % available.stone], ["도구", str(cost.tools), "%.0f" % available.tools]]:
		for text in item: _label(table, text, 20)
	_rule(details)
	var workload := int(cost.work)
	if id == "B13" and "M04" in session.state.get("meta_snapshot", []) and not session.state.get("first_survey", false) and not "B13" in session.state.orders: workload = int(ceil(workload * .85))
	_label(details, "필요 노동 %d인주 · 건설 요청 %d명" % [workload, session.state.assign.build], 20)
	_label(details, "다음 주에 자원과 공사비를 결제합니다. 인력은 농사·채집 뒤 배치되므로 인원을 요청해도 실제 배치가 줄 수 있습니다.", 18, GameTheme.MUTED)
	if session.state.assign.build == 0: _label(details, "건설 인력이 0명이라 예약만으로는 공사가 진행되지 않습니다.", 19, GameTheme.WARN)
	var error := _build_error(id)
	_rule(detail_panel)
	_label(detail_panel, "착공 비용  %s · 목재 %d · 석재 %d · 도구 %d" % [_money(cost.gold * 100), cost.wood, cost.stone, cost.tools], 18)
	_label(detail_panel, "예약 후 가용  %s · 목재 %.0f · 석재 %.0f · 도구 %.0f" % [_money(available.money - cost.gold * 100), available.wood - cost.wood, available.stone - cost.stone, available.tools - cost.tools], 18, GameTheme.MUTED if error == "" else GameTheme.WARN)
	var actions := _row(detail_panel)
	_primary(_button(actions, "착공 예약", func(): _command_build(id), error != "", "build_" + id))
	_quiet(_button(actions, "인력 배치 확인", func(): construction_tab = "labor"; _render()))
	if error != "": _label(detail_panel, error, 18, GameTheme.WARN)

func _purpose(id: String) -> String:
	return {"B13":"곡물을 생산해 겨울 식량을 확보합니다. 3주 파종 전에 완공한 농지가 올해 수확에 포함됩니다.", "B22":"식량을 안전하게 보관합니다. 보관 한도를 넘으면 추가 손실이 발생합니다.", "B01":"주거 부족을 해소하고 이민자를 받을 공간을 확보합니다.", "B06":"주민에게 식수를 공급해 건강 악화를 줄입니다.", "B17":"봄부터 가을까지 식량을 채집합니다. 수확 전 식량을 보충하는 수단입니다.", "B25":"목재를 생산하고 겨울용 장작을 가공할 수 있게 합니다.", "B14":"봄부터 가을까지 추가 식량을 생산합니다.", "B19":"곡물을 제분해 보관 상태를 개선합니다.", "B27":"건설에 필요한 석재를 직접 생산합니다.", "B49":"교역 운송료를 줄입니다.", "B59":"주민의 건강과 구휼을 지원합니다.", "B63":"행정 수용량을 늘려 수금 효율을 개선합니다."}.get(id, "")

func _labor_window(parent: Node) -> void:
	var body := _window_scroll(parent)
	_lesson_line(body)
	labor_summary = _heading(body, "")
	labor_actual = _label(body, "", 19, GameTheme.TEAL)
	labor_fields.clear()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for text in ["작업", "요청 인원", "배치 예상", "작업장 한도"]: _label(grid, text, 18, GameTheme.MUTED)
	for id in JOBS:
		var cap := _job_cap(id)
		if cap <= 0 and session.state.assign.get(id, 0) == 0 and id != "build" and not show_unavailable_jobs: continue
		_label(grid, JOBS[id], 20).custom_minimum_size.x = 130
		var input := SpinBox.new()
		input.name = "job_" + id
		input.custom_minimum_size.x = 145
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
		labor_fields[id].custom_minimum_size.x = 160
		_label(grid, "%d명" % cap if cap > 0 else "공사 없음" if id == "build" else "작업장 없음", 20, GameTheme.MUTED)
	var presets := _row(body)
	_button(presets, "채집 8명 · 건설 8명 배치", func(): _labor_preset({"gather":8, "build":8}), not _is_active(), "BuildPreset")
	_quiet(_button(presets, "벌목·장작 가공 배치", func(): _labor_preset({"gather":8, "logging":2, "fuel":2}), not _is_active(), "WinterPreset"))
	_label(body, "농사 → 채집 → 건설 → 생산 순으로 배치합니다. 벌목과 장작 가공은 벌목소 인원을 함께 사용합니다.", 18, GameTheme.MUTED)
	_quiet(_button(body, "작업장 없는 항목 접기" if show_unavailable_jobs else "모든 작업 보기", func(): show_unavailable_jobs = not show_unavailable_jobs; _render()))
	_refresh_labor_preview()

func _refresh_labor_preview() -> void:
	super._refresh_labor_preview()
	if is_instance_valid(labor_actual): labor_actual.text = labor_actual.text.replace("실제", "배치 예상")
	for label in labor_fields.values():
		if is_instance_valid(label): label.text = label.text.replace("이번 주 실제 ", "")

func _lesson_line(parent: Node) -> void:
	var step := ChronicleRules.tutorial_step(session.state)
	if step < 2 or step >= 7: return
	var lines := {2:"농지 2구획을 예약한 뒤 인력을 배치하세요.",3:"건설 인력 8명을 배치하세요.",4:"한 주씩 두 번 진행해 공사를 완료하세요.",5:"인물을 한 명 접견하세요.",6:"현재 특전과 합산 효과를 확인하세요."}
	var row := _row(parent)
	_label(row, "첫 통치 안내 %d / 7  ·  " % (step + 1) + lines[step], 18, GameTheme.TEAL)
	_quiet(_button(row, "안내 이동", func(): _tutorial_route(step), false, "TutorialAction"))

func _ration_policy(parent: Node) -> void:
	_heading(parent, "주민 식량 배급")
	_label(parent, "배급을 줄이면 식량을 아낄 수 있지만 민심과 건강이 악화됩니다. 현재 재고와 2주 뒤 도착할 구매 물자를 함께 고려하세요.", 21)
	_label(parent, "현재 식량 %.0f · 정상 배급 주당 %.0f · 현재 배급 주당 %.0f" % [WeekSim.total_food(session.state), session.state.pop * Constants.FOOD_PER_PERSON_WEEK, session.state.pop * Constants.FOOD_PER_PERSON_WEEK * session.state.ration], 20)
	_rule(parent)
	for item in [[1.0,"정상 배급","민심과 건강을 유지하는 기본 배급량입니다."],[0.9,"10% 절약 배급","식량 소비가 줄고 민심과 건강에 불이익이 생깁니다."],[0.75,"25% 비상 배급","심각한 식량 부족에 대응합니다. 민심과 건강의 손실이 더 큽니다."]]:
		var row := _row(parent)
		var words := _box(row)
		_heading(words, item[1] + (" · 적용 중" if is_equal_approx(session.state.ration, item[0]) else ""))
		_label(words, item[2], 19)
		_button(row, "적용", func(): session.state.ration = item[0]; _changed(item[1] + "으로 변경했습니다."), not _is_active() or is_equal_approx(session.state.ration, item[0]), "ration_%d" % int(item[0] * 100))
		_rule(parent)
	_label(parent, "52주 식량 목표는 배급을 줄여도 바뀌지 않습니다. 정상 배급 기준 13주분을 확보해야 합니다.", 19, GameTheme.MUTED)

func _next_reward_text() -> String:
	var s := session.state
	if not _is_active(): return "회차 종료 · 공훈과 가문 강화는 다음 회차에 유지됩니다"
	if _pending(): return "결정 대기 · 선택을 마치면 한 주를 진행할 수 있습니다"
	for week in (ChronicleRules.DRAFT_WEEKS if ChronicleRules.active(s) else GameSession.DRAFT_WEEKS):
		if int(s.week) <= week: return "다음 특전까지 %d주 · 보유 %d / %d개" % [week + 1 - int(s.week), s.perks.size(), 8 if ChronicleRules.active(s) else 4]
	return "최종 평가까지 %d주" % maxi(0, 53 - int(s.week))

func _journey(parent: Node) -> void:
	_label(parent, "한 회차는 52주입니다. 겨울 평가를 통과하도록 시설과 비축을 준비하세요. 계절을 버티거나 계약을 달성하면 다음 회차에 사용할 공훈이 쌓입니다.", 21)
	_heading(parent, "52주 종료 시 평가")
	for goal in session.state.goals.values():
		var row := _row(parent)
		_label(row, goal.detail, 20)
		_tag(row, goal.status, GameTheme.GOOD if goal.done else GameTheme.WARN, 20)
	if ChronicleRules.active(session.state):
		var trial: Dictionary = session.content.chronicle.trials[session.state.trial]
		_rule(parent)
		_heading(parent, "겨울 시련 · " + trial.name)
		_label(parent, trial.description, 21)
		_label(parent, "40주부터 적용됩니다. 기본 목표와 시련 목표를 모두 달성해야 이번 회차에 성공합니다.", 19, GameTheme.MUTED)
		if not session.state.contract.is_empty():
			var contract: Dictionary = session.state.contract
			var mission: Dictionary = session.content.chronicle.missions[contract.id]
			_rule(parent)
			_heading(parent, "진행 중인 계약 · " + mission.name)
			_label(parent, "%d주 평가 · 현재 %.1f / 목표 %.1f\n%s" % [contract.deadline, ChronicleRules.value(session.state, mission.target), mission.threshold, mission.description], 20)
	_rule(parent)
	_heading(parent, "특전과 다음 회차")
	_label(parent, _next_reward_text(), 21, GameTheme.TEAL)
	_label(parent, "특전·영주 특성·부임 물자는 이번 회차의 운영 방식을 바꿉니다. 공훈으로 산 가문 강화는 다음 회차의 시작 조건을 바꿉니다.", 20)
	_label(parent, "13주 생존 이후 보상 지급 · 계절 생존 +2 · 계약 +3 · 기본 목표당 +6 · 시련 +6 공훈", 18, GameTheme.MUTED)
	_quiet(_button(parent, "현재 회차를 끝내고 결산", _ask_retire, not _is_active(), "RetireRun"))

func _help_popup() -> void:
	_shade(interface, .72)
	var content := _window("플레이 안내", Vector2(minf(900, size.x - 80), minf(640, size.y - 80)), false, true)
	current_modal = content.get_parent()
	var reading := _scroll(content)
	_heading(reading, "보고를 읽고 이번 주 계획을 정합니다")
	_label(reading, "주간 보고에서 지난주 결과와 부족 원인을 읽으세요. 오른쪽에는 예약 공사·운송과 한 주 운영 후의 경제 예상이 표시됩니다.", 20)
	_heading(reading, "개발과 노동은 함께 계획합니다")
	_label(reading, "시설을 예약한 뒤 건설 인력을 배치하세요. 다음 주 진행 시 착공 비용을 결제합니다. 농사와 채집이 우선하므로 요청 인원과 배치 예상은 다를 수 있습니다.", 20)
	_heading(reading, "서신·특전·계약은 결정 후 진행합니다")
	_label(reading, "도착한 서신은 비용과 효과를 비교해 결정하세요. 보고서를 먼저 확인해도 선택은 유지됩니다. 처리 결과는 주간 보고에 남습니다.", 20)
	_label(reading, "Space · 한 주 진행   /   F · 대기 중인 결정   /   Esc · 창 닫기·보고로 돌아가기", 18, GameTheme.MUTED)
	_label(reading, "52주마다 회차가 끝납니다. 공훈·가문 강화·발견 기록은 남고, 물자·특전·관계는 다시 시작합니다.", 19)
	var row := _row(content)
	if _is_active() and ChronicleRules.active(session.state):
		_quiet(_button(row, "첫 통치 안내 다시 켜기", func(): help_open = false; session.state.tutorial = {"enabled":true,"step":0}; _go("estate"); _save(), false, "ReplayTutorial"))
	_primary(_button(row, "닫기", func(): help_open = false; _render(), false, "CloseHelp"))

func _construction_queue(parent: Node) -> void:
	_heading(parent, "착공 예약 · 아직 결제하지 않음")
	for i in session.state.orders.size():
		var row := _row(parent)
		_label(row, session.content.facilities[session.state.orders[i]].name, 20)
		_quiet(_button(row, "예약 취소", func(): session.state.orders.remove_at(i); _changed("착공 예약을 취소했습니다.")))
	if session.state.orders.is_empty(): _label(parent, "예약된 시설이 없습니다.", 19, GameTheme.MUTED)
	_rule(parent)
	_heading(parent, "진행 중인 공사 · 자원 결제 완료")
	for i in session.state.projects.size():
		var project: Dictionary = session.state.projects[i]
		_heading(parent, session.content.facilities[project.id].name)
		_label(parent, "남은 작업 %d / %d인주 · 보관된 공사비 %s" % [project.work_left, project.work_total, _money(project.escrow)], 20)
		_bar(parent, 1.0 - project.work_left / maxf(1, project.work_total), "info")
		_quiet(_button(parent, "공사 취소 · 잔여 자원 반환", func(): WeekSim.cancel_project(session.state, session.content, i); _changed("공사를 취소하고 잔여 자원을 반환했습니다.")))
	if session.state.projects.is_empty(): _label(parent, "진행 중인 공사가 없습니다.", 19, GameTheme.MUTED)

func _reading_market(parent: Node) -> void:
	_label(parent, "부족한 물자를 주문하거나 공공 재고를 판매합니다. 운송에는 2주가 걸립니다.", 20)
	_rule(parent)
	_market(parent)

func _market(parent: Node) -> void:
	StewardScreens.market(self, parent)

func _people(parent: Node) -> void:
	if ChronicleRules.tutorial_step(session.state) == 5: _lesson_line(parent)
	StewardScreens.people(self, parent)

func _boons(parent: Node) -> void:
	StewardScreens.boons(self, parent)

func _archive(parent: Node) -> void:
	StewardScreens.archive(self, parent)

func _accounts(parent: Node) -> void:
	_heading(parent, "공공 금고와 주민 자금")
	_label(parent, "공공 %s / 주민 %s · 미지급 급여 %s · 체납 세금 %s" % [_money(session.state.public.money), _money(session.state.resident.money), _money(session.state.arrears_wage), _money(session.state.arrears_tax)], 20)
	_rule(parent)
	_heading(parent, "최근 주간 잔액")
	for record in session.state.history.slice(-8):
		_label(parent, "%d주 종료  ·  금고 %s  ·  식량 %.0f  ·  주민 %d명" % [record.week, _money(record.money), record.food, record.pop], 20)
	_rule(parent)
	_heading(parent, "최근 거래 내역")
	var names := {"seed":"파종 종자", "harvest":"수확", "gather":"채집", "consume":"주민 소비", "spoil":"보관 손실", "construction":"공사비", "wages":"공공 급여", "maintenance":"유지비", "tax":"세금", "logging":"벌목", "quarry":"채석", "fuel":"장작 가공", "heating":"난방", "garden":"채소 생산", "trade_buy":"교역 구매", "trade_depart":"판매 출하", "trade_arrival":"교역 도착", "trade_sale":"판매 대금", "event":"사건 수입", "event_cost":"사건 지출"}
	for entry in session.state.ledger.slice(-24):
		if entry.src == "transfer": continue
		_label(parent, "%d주 · %s · %s %s" % [entry.w, names.get(entry.src, entry.src), RESOURCES.get(entry.asset, "금고"), "%+.2f금" % (entry.qty / 100.0) if entry.asset == "money" else "%+.1f" % entry.qty], 19)

func _window(title: String, dimensions: Vector2, closable: bool = true, modal: bool = false) -> VBoxContainer:
	var cover := JournalFrame.new()
	interface.add_child(cover)
	_place(cover, Rect2((size - dimensions) * .5 - Vector2(16, 10), dimensions + Vector2(32, 26)))
	var frame := PanelContainer.new()
	frame.name = "DecisionModal" if modal else "ManagementWindow"
	frame.add_theme_stylebox_override("panel", TycoonTheme.panel(Color.TRANSPARENT, Color.TRANSPARENT, 22))
	interface.add_child(frame)
	_place(frame, Rect2((size - dimensions) * .5, dimensions))
	var content := _box(frame)
	content.add_theme_constant_override("separation", 16)
	if title != "":
		var row := _row(content)
		_heading(row, title)
		if closable: _quiet(_button(row, "닫기", func(): _go("estate"), false, "CloseWindow"))
		_rule(content)
	return content

func _decision_popup() -> void:
	_shade(interface, .72).name = "DecisionBlocker"
	var s := session.state
	var content := _window("운영 특전 선택" if not s.perk_offer.is_empty() else "영주에게 도착한 서신" if s.active_event != "" else "계절 계약 제안", Vector2(minf(1020, size.x - 100), minf(640, size.y - 72)), false, true)
	current_modal = content.get_parent()
	var top := _row(content)
	_label(top, "%d주 · 결정을 기다리고 있습니다" % s.week, 18, GameTheme.MUTED)
	_quiet(_button(top, "보고서 먼저 확인", func(): decision_hidden = true; page = "estate"; _render(), false, "InspectEstate"))
	if not s.perk_offer.is_empty(): _perk_choices(content)
	elif s.active_event != "": _event_choices(content)
	else: _contract_choices(content)
	_focus_decision.call_deferred()

func _event_choices(parent: Node) -> void:
	var event: Dictionary = RealmRules.event_definition(session.state,session.content,session.state.active_event)
	var sender := _row(parent)
	_face(sender, event.get("portrait", "CH01"), 66)
	var title := _box(sender)
	_label(title, event.speaker + "의 보고", 18, GameTheme.MUTED)
	_heading(title, event.title, true)
	_label(parent, event.body, 22)
	_rule(parent)
	var choices := _scroll(parent)
	choices.get_parent().name = "EventOptionsScroll"
	for i in event.options.size():
		var option: Dictionary = event.options[i]
		var error := session.option_error(option)
		var row := _row(choices)
		var words := _box(row)
		_heading(words, option.label)
		_label(words, option.hint, 20, GameTheme.TEAL)
		if error != "": _label(words, error, 18, GameTheme.WARN)
		_button(row, "결정", func(): _resolve(i), error != "", "event_option_%d" % i).custom_minimum_size.x = 100
		_rule(choices)

func _perk_choices(parent: Node) -> void:
	_label(parent, "이번 통치에 적용할 효과를 하나 고르세요. 같은 계열 2개·4개를 모으면 추가 효과가 생깁니다.", 21)
	var choices := _scroll(parent)
	var counts := ChronicleRules.family_counts(session.content, session.state)
	for id in session.state.perk_offer:
		var perk: Dictionary = session.content.progression.perks[id]
		var family: Dictionary = session.content.chronicle.families[perk.family]
		var row := _row(choices)
		var words := _box(row)
		_heading(words, perk.name)
		_label(words, perk.description, 21, GameTheme.TEAL)
		_label(words, "%s %d → %d개 · %s" % [family.name, counts[perk.family], counts[perk.family] + 1, family.description], 18, GameTheme.MUTED)
		_button(row, "채택", func(): session.choose_perk(id); _changed(perk.name + "을 적용했습니다."), false, "perk_" + id).custom_minimum_size.x = 100
		_rule(choices)
	_quiet(_button(parent, "후보 새로고침 · 남은 교환 %d회" % session.state.refreshes, func(): session.refresh_perks(); _changed("특전 후보를 교환했습니다."), session.state.refreshes <= 0, "RefreshPerks"))

func _contract_choices(parent: Node) -> void:
	_label(parent, "준비 비용을 먼저 내고 계절 말에 목표를 평가합니다. 달성하면 물자와 공훈 3점을 받습니다.", 20)
	var choices := _scroll(parent)
	for id in session.state.contract_offer:
		var mission: Dictionary = session.content.chronicle.missions[id]
		var row := _row(choices)
		var words := _box(row)
		_heading(words, mission.name)
		_label(words, mission.description, 20)
		_label(words, "준비: %s  /  보상: %s + 공훈 3" % [_resources_text(mission.cost), _resources_text(mission.reward)], 19, GameTheme.TEAL)
		var error := ChronicleRules.contract_error(session.content, session.state, id)
		_button(row, "수락", func(): session.choose_contract(id); _changed("계약을 수락했습니다."), error != "", "contract_" + id).custom_minimum_size.x = 100
		if error != "": _label(words, error, 18, GameTheme.WARN)
		_rule(choices)
	_quiet(_button(parent, "이번 계약은 받지 않음 · 비용 없음", func(): session.choose_contract("skip"); _changed("계약을 받지 않았습니다."), false, "SkipContract"))

func _resolve(index: int) -> void:
	# 선택 결과는 다음 보고에 영수증으로 남겨 확인창을 연달아 요구하지 않는다.
	super._resolve(index)
	if not decision_result.is_empty():
		receipt = decision_result.duplicate(true)
		decision_result.clear()
		page = "estate"
		_render()

func _advance(_count: int) -> void:
	if busy: return
	if _pending(): _open_decision(); return
	var before := session.state.duplicate(true)
	receipt.clear()
	await super._advance(1)
	if int(session.state.week) > int(before.week):
		last_turn = {"week":session.state.history.back().week, "money":session.state.public.money - before.public.money, "food":WeekSim.total_food(session.state) - WeekSim.total_food(before), "pop":session.state.pop - before.pop}
	if _is_active(): page = "estate"
	_render()

func _command_build(id: String) -> void:
	var error := session.queue_build(id)
	if error != "": _message(error); return
	_changed(session.content.facilities[id].name + " 착공 예약 · 다음 주에 비용이 결제됩니다.")

func _result(parent: Node) -> void:
	var result: Dictionary = session.state.result
	_heading(parent, "52주 통치에 성공했습니다" if result.success else "이번 회차를 마쳤습니다", true)
	_label(parent, "%d주 운영 · %s · 주민 %d명 · 식량 %.1f주분" % [result.week, result.reason, session.state.pop, WeekSim.food_weeks(session.state)], 21)
	_rule(parent)
	_heading(parent, "공훈 +%d" % result.points, true, GameTheme.TEAL)
	_label(parent, "기본 목표 %d점 · 계절 생존 %d점 · 계약 %d점 · 겨울 시련 %d점\n완주 %d점 · 첫 회차 기록 %d점" % [result.objective_points, result.get("season_points", 0), result.get("contract_points", 0), result.get("trial_points", 0), result.completion_points, result.first_points], 20)
	_label(parent, "공훈·가문 강화·발견 기록은 남습니다. 물자·특전·관계는 새 회차에서 다시 시작합니다.", 20)
	var actions := _row(parent)
	_primary(_button(actions, "가문 강화로 다음 회차 준비", func(): _go("archive"), false, "ResultArchive"))
	_button(actions, "새 회차 준비", _open_prepare, false, "ResultRestart")

func _message(message: String) -> void:
	notice = message
	if is_instance_valid(report_status): report_status.text = message

func _input(event: InputEvent) -> void:
	if _handle_quit_input(event): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event.keycode == KEY_ESCAPE:
		if help_open: help_open = false; _render()
		elif _pending() and not decision_hidden: decision_hidden = true; page = "estate"; _render()
		elif page not in ["menu", "prepare", "estate"]: _go("estate")
		else: return
	elif is_instance_valid(current_modal): return
	elif page in ["menu", "prepare", "result"]: return
	elif event.keycode == KEY_SPACE and _is_active(): _advance(1)
	elif event.keycode == KEY_F and _pending(): _open_decision()
	else: return
	get_viewport().set_input_as_handled()
