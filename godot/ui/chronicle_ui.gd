extends "res://ui/game_ui.gd"
## 회차: 준비 → 선택 → 운영 → 시련 → 기록 → 다음 부임.

const NAV := {"estate":"영지 현황", "build":"건설·노동", "trade":"교역", "people":"인물", "boons":"특전·특성", "ledger":"장부", "archive":"가문 강화"}
var pixel_ready := false
var draft_seed := 61427
var draft_region := "forest"
var draft_candidate := 0
var draft_relics: Array = ["seeds", "axe"]
var prepare_step := 0
var tutorial_enabled := true
var selected_person := "CH01"
var construction_tab := "facilities"
var facility_group := "기반"
var report_expanded := false
var show_unavailable_jobs := false

func _heading(parent: Node, text: String, large: bool = false, color: Color = GameTheme.TEXT) -> Label:
	var label := _label(parent, text, 28 if large else 19, color)
	label.add_theme_font_override("font", PixelTheme.heading_font())
	return label

func _label(parent: Node, text: String, px: int = 18, color: Color = GameTheme.TEXT) -> Label:
	return super._label(parent, text, maxi(16, px), color)

func _card(parent: Node, title: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := _box(panel)
	if title != "": _heading(box, title, false, GameTheme.GOLD)
	return box

func _primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", PixelTheme.frame(Color("b88b45"), GameTheme.GOLD, 12))
	button.add_theme_stylebox_override("hover", PixelTheme.frame(Color("d7ad63"), GameTheme.TEXT, 12))
	button.add_theme_stylebox_override("pressed", PixelTheme.frame(Color("9f793d"), GameTheme.GOLD, 12))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, GameTheme.BG)

func _go(target: String) -> void:
	page = target
	if target == "boons" and ChronicleRules.active(session.state):
		session.state.tutorial_build_seen = true
		_sync_tutorial()
		_save()
	_render()

func _is_active() -> bool:
	return not session.state.is_empty() and session.state.status == "active"

func _pending() -> bool:
	return _is_active() and (not session.state.perk_offer.is_empty() or session.state.active_event != "" or not session.state.get("contract_offer", []).is_empty())

func _render() -> void:
	if not pixel_ready:
		theme = PixelTheme.create(assets.body_font())
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pixel_ready = true
	if is_instance_valid(main_scroll): scroll_positions[rendered_page] = main_scroll.scroll_vertical
	main_scroll = null
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: shell.add_theme_constant_override("margin_" + side, 20)
	add_child(shell)
	var root := _box(shell)
	root.size_flags_vertical = SIZE_EXPAND_FILL
	forecast = WeekSim.forecast(session.state, session.content) if _is_active() and page not in ["menu", "prepare"] else {}
	if page == "menu":
		_menu(root)
	elif page == "prepare":
		_prepare(root)
	else:
		_header(root)
		if _is_active(): _tutorial(root)
		var nav := _row(root)
		for id in NAV:
			if session.state.is_empty() and id != "archive": continue
			var button := _button(nav, NAV[id], func(): _go(id), false, "nav_" + id)
			button.size_flags_horizontal = SIZE_EXPAND_FILL
			if page == id: button.add_theme_stylebox_override("normal", PixelTheme.frame(Color("34382c"), GameTheme.TEAL, 12))
		var area := _scroll(root)
		main_scroll = area.get_parent()
		main_scroll.name = "PageScroll"
		main_scroll.follow_focus = page != "estate"
		match page:
			"estate": _estate(area)
			"build": _construction(area)
			"trade": _market(area)
			"people": _people(area)
			"boons": _boons(area)
			"ledger": _ledger(area)
			"archive": _archive(area)
			"result": _result(area)
	var footer := _row(root)
	notice_label = _label(footer, notice if notice != "" else "자동 저장 사용 중", 16, GameTheme.MUTED)
	notice_label.max_lines_visible = 1
	notice_label.tooltip_text = notice_label.text
	rendered_page = page
	_restore_scroll.call_deferred(page, int(scroll_positions.get(page, 0)))

func _menu(root: VBoxContainer) -> void:
	var top := _row(root)
	_heading(top, "영지 경영 로그라이트", false, GameTheme.MUTED)
	var body := _row(root)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	var left := _box(body, 1.6)
	left.size_flags_vertical = SIZE_SHRINK_CENTER
	_landscape(left, 0)
	var right := _box(body)
	right.custom_minimum_size.x = 350
	right.size_flags_vertical = SIZE_SHRINK_CENTER
	_heading(right, "변경의 신임 영주가 되었다", true, GameTheme.TEXT)
	_label(right, "52주 동안 영지를 운영하고 겨울 시련을 통과하세요.", 19)
	_label(right, "지역·영주 특성·부임 물자를 선택합니다. 회차 종료 후 획득한 공훈으로 가문 강화를 구매할 수 있습니다.", 17, GameTheme.MUTED)
	if _is_active():
		var resume := _button(right, "%d주 회차 이어 하기" % session.state.week, _continue, load_blocked, "ContinueRun")
		_primary(resume)
		_label(right, "새 부임은 현재 회차를 결산한 뒤 가능합니다.", 14, GameTheme.MUTED)
		if not ChronicleRules.active(session.state):
			_label(right, "이전 저장은 기존 규칙으로 이어집니다. 지역·장비·시련은 새 회차부터 적용됩니다.", 14, GameTheme.TEAL)
		_button(right, "회차 종료", _ask_retire, load_blocked, "RetireRun")
	else:
		_primary(_button(right, "새 게임", _open_prepare, load_blocked, "NewRun"))
		if not session.state.is_empty(): _button(right, "지난 회차 결산", func(): _go("result"))
	_button(right, "가문 강화 · %d 공훈" % session.profile.points, func(): _go("archive"), false, "OpenArchive")
	_button(right, "플레이 안내", _help, false, "OpenHelp")
	_label(right, "자동 저장 · 새 회차에서는 특전과 자원이 초기화됩니다.", 16, GameTheme.MUTED)
	var gallery := _row(root)
	gallery.add_theme_constant_override("separation", 8)
	for id in session.content.chronicle.characters: _face(gallery, id, 48)

func _open_prepare() -> void:
	if _is_active(): return
	draft_seed = int(Time.get_unix_time_from_system()) & 0x7fffffff
	prepare_step = 0
	tutorial_enabled = not session.profile.get("tutorial_done", false)
	_go("prepare")

func _prepare(root: Node) -> void:
	var top := _row(root)
	_heading(top, "새 게임 설정", true, GameTheme.GOLD)
	_button(top, "돌아가기", func(): _go("menu"))
	var steps := _row(root)
	for i in 3:
		var button := _button(steps, ["01  지역·시련", "02  영주 선택", "03  부임 물자"][i], func(): prepare_step = i; _render())
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		if prepare_step == i: _primary(button)
	var area := _scroll(root)
	main_scroll = area.get_parent()
	main_scroll.name = "PageScroll"
	var data: Dictionary = session.content.chronicle
	match prepare_step:
		0:
			_label(area, "시작 지역 선택", 22)
			var cards := _row(area)
			for id in data.regions:
				var region: Dictionary = data.regions[id]
				var box := _card(cards, region.name)
				_landscape(box, {"forest": 0, "river": 1, "highland": 2}[id], 120)
				_heading(box, region.subtitle)
				_label(box, region.description, 16)
				var pick := _button(box, "선택됨" if draft_region == id else "선택", func(): draft_region = id; _render(), false, "region_" + id)
				if draft_region == id: _primary(pick)
			var seed_row := _row(area)
			_tag(seed_row, "시드", GameTheme.MUTED)
			seed_input = LineEdit.new()
			seed_input.name = "SeedInput"
			seed_input.text = str(draft_seed)
			seed_input.custom_minimum_size.x = 180
			seed_row.add_child(seed_input)
			_button(seed_row, "적용", func():
				if seed_input.text.is_valid_int(): draft_seed = absi(int(seed_input.text)); _render()
				else: _message("시드는 숫자로 입력하세요.")
			)
			_button(seed_row, "부임 조건 새로고침", func(): draft_seed = (draft_seed * 1664525 + 1013904223) & 0x7fffffff; _render())
			_label(area, "같은 시드은 같은 영주 후보·특전 추첨·겨울 시련을 만듭니다. 선택과 운영에 따라 결과는 달라집니다.", 14, GameTheme.MUTED)
			var trial: Dictionary = data.trials[ChronicleRules.trial_for(data, draft_seed)]
			var warning := _card(area, "예고된 겨울 시련 · " + trial.name)
			_label(warning, trial.description, 16, GameTheme.WARN)
		1:
			_label(area, "영주 선택 · 장점 2개 + 단점 1개", 22)
			var cards := _row(area)
			var choices := ChronicleRules.candidates(data, draft_seed)
			for i in 3:
				var candidate: Dictionary = choices[i]
				var origin: Dictionary = session.content.progression.origins[candidate.origin]
				var box := _card(cards, origin.name)
				_heading(box, ["개척", "통치", "풍요"][i], true, GameTheme.TEAL)
				_label(box, origin.description, 16, GameTheme.MUTED)
				for id in candidate.traits:
					var lord_trait: Dictionary = data.traits[id]
					_heading(box, lord_trait.name, false, GameTheme.WARN if lord_trait.get("flaw", false) else GameTheme.GOOD)
					_label(box, lord_trait.description)
				var pick := _button(box, "선택됨" if draft_candidate == i else "선택", func(): draft_candidate = i; _render(), false, "candidate_%d" % i)
				if draft_candidate == i: _primary(pick)
		2:
			var budget := 4 if "M20" in session.profile.upgrades else 3
			_heading(area, "부임 물자 비용  %d / %d" % [_relic_cost(), budget], true)
			_label(area, "한도 안에서 부임 물자를 선택하세요. 구매한 가문 강화도 적용됩니다.", 16, GameTheme.MUTED)
			var grid := GridContainer.new()
			grid.columns = 3
			area.add_child(grid)
			for id in data.relics:
				var relic: Dictionary = data.relics[id]
				var box := _card(grid, relic.name)
				_label(box, relic.description)
				var chosen: bool = id in draft_relics
				var pick := _button(box, ("제거" if chosen else "추가") + " · 비용 %d" % relic.cost, func():
					if id in draft_relics: draft_relics.erase(id)
					else: draft_relics.append(id)
					_render(), not chosen and _relic_cost() + int(relic.cost) > budget, "relic_" + id)
				if chosen: _primary(pick)
			var check := CheckButton.new()
			check.text = "튜토리얼 사용"
			check.button_pressed = tutorial_enabled
			check.toggled.connect(func(on): tutorial_enabled = on)
			area.add_child(check)
			_label(area, "회차 중 특전·재고·관계는 새 부임 때 초기화됩니다. 공훈·가문 강화·발견한 특전은 남습니다.", 16, GameTheme.TEAL)
	var controls := _row(root)
	_label(controls, "%s · 시드 %d" % [data.regions[draft_region].name, draft_seed], 14, GameTheme.MUTED)
	if prepare_step > 0: _button(controls, "이전", func(): prepare_step -= 1; _render())
	if prepare_step < 2:
		_primary(_button(controls, "다음 선택", func(): prepare_step += 1; scroll_positions.prepare = 0; _render(), false, "PrepareNext"))
	else:
		_primary(_button(controls, "게임 시작", _start, load_blocked, "StartRun"))

func _relic_cost() -> int:
	var cost := 0
	for id in draft_relics: cost += int(session.content.chronicle.relics[id].cost)
	return cost

func _start() -> void:
	if _is_active() or load_blocked: return
	session.start_run(draft_seed, "settler", {"region": draft_region, "candidate": draft_candidate, "relics": draft_relics, "tutorial": tutorial_enabled})
	page = "estate"
	scroll_positions.clear()
	_changed("특전 1개를 선택하세요.")

func _header(root: Node) -> void:
	var bar := _card(root)
	bar.get_parent().name = "StatusHeader"
	bar.get_parent().add_theme_stylebox_override("panel", PixelTheme.frame(GameTheme.PANEL, GameTheme.BORDER, 10))
	var row := _row(bar)
	if session.state.is_empty():
		_heading(row, "가문 강화", true)
		_button(row, "메인 메뉴", func(): _go("menu"))
		return
	var s := session.state
	var season := mini(3, int((int(s.week) - 1) / 13))
	var date := _heading(row, "%d회차  ·  %s %d주 / 52주" % [session.profile.runs, ["봄", "여름", "가을", "겨울"][season], mini(52, s.week)])
	date.name = "HeaderBrand"
	date.autowrap_mode = TextServer.AUTOWRAP_OFF
	date.tooltip_text = "시드 %d · %s" % [s.seed, session.content.progression.origins[s.origin].name]
	_button(row, "도움말", _help, false, "HeaderHelp")
	_button(row, "메뉴", func(): _go("menu"), false, "MainMenu")
	if _is_active():
		var action := _button(row, "선택 필요" if _pending() else "다음 주", _open_decision if _pending() else func(): _advance(1), false, "NextWeek")
		action.custom_minimum_size.x = 150
		_primary(action)
	var resources := _row(bar)
	for item in [["money", "금고", _money(s.public.money)], ["food", "식량", "%.1f주" % WeekSim.food_weeks(s)], ["pop", "주민", "%d명" % s.pop], ["wood", "목재", "%.0f" % s.public.wood], ["stone", "석재", "%.0f" % s.public.stone], ["tools", "도구", "%.0f" % s.public.tools], ["fuel", "장작", "%.0f" % s.public.fuel], ["mood", "민심", "%d" % s.mood]]:
		var chip := _row(resources)
		chip.add_theme_constant_override("separation", 5)
		_icon(chip, item[0], 20)
		var value_label := _tag(chip, item[1] + " " + item[2], GameTheme.TEXT, 16)
		if item[0] == "food":
			value_label.tooltip_text = "정상 배급 기준 잔여 식량. 공공 %.0f + 주민 %.0f. 인구가 늘면 버틸 수 있는 주수가 줄어듭니다." % [s.public.food, s.resident.food]
		elif item[0] == "money":
			value_label.tooltip_text = "공공 금고입니다. 주민 자금 %s는 별도 계정입니다." % _money(s.resident.money)
		else: value_label.tooltip_text = "현재 " + item[1] + ": " + item[2]

func _face(parent: Node, id: String, width: int = 96) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.name = "Portrait_" + id
	portrait.texture = assets.texture("portrait_" + id)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(width, width * 4 / 3)
	portrait.size_flags_horizontal = SIZE_SHRINK_CENTER
	portrait.size_flags_vertical = SIZE_SHRINK_BEGIN
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.tooltip_text = session.content.chronicle.characters.get(id, {}).get("name", "")
	parent.add_child(portrait)
	return portrait

func _estate(parent: Node) -> void:
	if session.state.is_empty(): return
	var s := session.state
	var current := mini(3, int((int(s.week) - 1) / 13))
	if _pending():
		_decisions(parent)
		return
	var road := _row(parent)
	for i in 4:
		var season_box := _card(road)
		season_box.get_parent().add_theme_stylebox_override("panel", PixelTheme.frame(GameTheme.PANEL, GameTheme.BORDER, 8))
		var text: String = ["봄  1–13주", "여름  14–26주", "가을  27–39주", "겨울  40–52주"][i]
		_label(season_box, ("진행 중 · " if i == current else "") + text, 16, GameTheme.SEASON[i] if i == current else GameTheme.MUTED)
	var columns := _row(parent)
	var left := _box(columns, 1.05)
	var right := _box(columns)
	var scene := _card(left, session.content.chronicle.regions.get(s.get("region", "forest"), {}).get("name", "영지"))
	_landscape(scene, current, 160)
	_label(scene, "건강 %d  ·  치안 %d  ·  주거 %d / %d명" % [s.health, s.security, WeekSim.capacity(s, session.content, "housing"), s.pop], 16, GameTheme.MUTED)
	_objectives(right)
	var tasks := _actionable_alerts()
	var alert_box := _card(right, "확인할 항목")
	for task in tasks.slice(0, 2):
		var line := _row(alert_box)
		var words := _box(line)
		_label(words, task.title, 18, GameTheme.level_color(task.level))
		_label(words, task.detail, 16, GameTheme.MUTED)
		var button := _button(line, task.action, func():
			if task.has("tab"): construction_tab = task.tab
			_go(task.page)
		)
		button.size_flags_vertical = SIZE_SHRINK_CENTER
	if tasks.is_empty(): _label(alert_box, "현재 긴급 경고가 없습니다.", 17, GameTheme.MUTED)
	if ChronicleRules.active(s):
		var trial: Dictionary = session.content.chronicle.trials[s.trial]
		var winter := _card(right, "겨울 시련 · " + trial.name)
		_label(winter, trial.description, 16, GameTheme.TEXT)
		if not s.contract.is_empty():
			var mission: Dictionary = session.content.chronicle.missions[s.contract.id]
			_label(winter, "%d주 계약: %s · 현재 %.1f / %.1f" % [s.contract.deadline, mission.name, ChronicleRules.value(s, mission.target), mission.threshold], 16, GameTheme.TEAL)
	var actions := _row(left)
	_button(actions, "다음 선택까지 진행", func(): _advance(13), busy, "AdvanceUntilChoice")
	_button(actions, "주간 보고", func(): _go("ledger"))
	if not s.history.is_empty():
		var last: Dictionary = s.history.back()
		_label(left, "%d주 완료 · %s" % [last.week, " / ".join(last.notes.slice(-2))], 16, GameTheme.MUTED)

func _objectives(parent: Node) -> void:
	var box := _card(parent, "회차 성공 조건 · 52주 종료 시 평가")
	for goal in session.state.goals.values():
		var row := _row(box)
		_label(row, ("완료  " if goal.done else "미달성  ") + goal.detail, 17, GameTheme.GOOD if goal.done else GameTheme.TEXT)
		_tag(row, goal.status, GameTheme.GOOD if goal.done else GameTheme.MUTED, 16)
	_label(box, "위 조건 3개와 겨울 시련을 모두 달성하면 성공합니다." if ChronicleRules.active(session.state) else "이전 규칙의 회차입니다. 위 조건 3개를 달성하면 성공합니다.", 16, GameTheme.MUTED)

func _actionable_alerts() -> Array:
	var s := session.state
	var tasks: Array = []
	var food := WeekSim.food_weeks(s)
	if food < 8:
		tasks.append({"title": "식량 %.1f주분" % food, "detail": "구매한 식량은 2주 뒤 도착합니다.", "action": "교역", "page": "trade", "level": "bad" if food < 4 else "warn"})
	if (not s.orders.is_empty() or not s.projects.is_empty()) and s.assign.build == 0:
		tasks.append({"title": "건설 인력 없음", "detail": "인력을 배치해야 공사가 진행됩니다.", "action": "인력 배치", "page": "build", "tab": "labor", "level": "warn"})
	if WeekSim.capacity(s, session.content, "housing") < s.pop:
		tasks.append({"title": "주거 부족", "detail": "움집 구역을 추가로 건설하세요.", "action": "건설", "page": "build", "tab": "facilities", "level": "bad"})
	if int(s.week) >= 27:
		var heat: float = WeekSim.bonus(s, "heating")
		if s.get("trial", "") == "frost" and not s.get("trial_started", false): heat *= 1.5
		var required: float = s.pop * 0.1 * mini(13, 53 - int(s.week)) * heat
		if s.public.fuel < required:
			tasks.append({"title": "장작 부족 · %.0f / %.0f" % [s.public.fuel, required], "detail": "벌목소에서 가공하거나 교역으로 구매하세요.", "action": "교역", "page": "trade", "level": "warn"})
	if tasks.is_empty():
		if not s.goals.farms.done:
			tasks.append({"title": "농지 확장", "detail": "현재 %d / 목표 6구획" % s.facilities.get("B13", 0), "action": "건설", "page": "build", "tab": "facilities", "level": "info"})
		elif not s.goals.storage.done:
			tasks.append({"title": "곡물 곳간 건설", "detail": "식량 저장량을 늘리고 보관 손실을 줄입니다.", "action": "건설", "page": "build", "tab": "facilities", "level": "info"})
	return tasks

func _decisions(parent: Node) -> void:
	var s := session.state
	if not s.perk_offer.is_empty():
		_heading(parent, "특전 선택", true, GameTheme.GOLD)
		_label(parent, "1개를 선택하세요. 같은 계열 2장·4장을 모으면 특전 세트 효과가 이번 통치에 적용됩니다. 다음 부임에서는 다시 선택합니다.", 16, GameTheme.MUTED)
		var counts := ChronicleRules.family_counts(session.content, s)
		var cards := _row(parent)
		for id in s.perk_offer:
			var perk: Dictionary = session.content.progression.perks[id]
			var family: Dictionary = session.content.chronicle.families[perk.family]
			var box := _card(cards)
			box.custom_minimum_size.y = 275
			_heading(box, family.name + "  /  특전", false, Color(family.color))
			_heading(box, perk.name, true)
			_label(box, perk.description, 18, GameTheme.TEXT)
			_label(box, "%s %d → %d장\n%s" % [family.name, counts[perk.family], counts[perk.family] + 1, family.description], 14, Color(family.color))
			var space := Control.new()
			space.size_flags_vertical = SIZE_EXPAND_FILL
			box.add_child(space)
			_primary(_button(box, "선택", func(): session.choose_perk(id); _sync_tutorial(); _changed("특전을 획득했습니다."), false, "perk_" + id))
		var bottom := _row(parent)
		_label(bottom, "선택한 특전 %d개 · 이번 회차에만 적용" % s.perks.size(), 14, GameTheme.MUTED)
		_button(bottom, "후보 새로고침 · %d회" % s.refreshes, func(): session.refresh_perks(); _changed("특전 후보를 새로고침했습니다."), s.refreshes <= 0, "RefreshPerks")
	elif s.active_event != "":
		var event: Dictionary = RealmRules.event_definition(s,session.content,s.active_event)
		var box := _card(parent, "사건 선택")
		var row := _row(box)
		_face(row, event.get("portrait", "CH01"), 192)
		var text := _box(row)
		_heading(text, event.speaker, false, GameTheme.GOLD)
		_heading(text, event.title, true)
		_label(text, event.body, 18)
		for i in event.options.size():
			var option: Dictionary = event.options[i]
			var error := session.option_error(option)
			var pick := _button(text, option.label, func(): _resolve(i), error != "", "event_option_%d" % i)
			pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_label(text, option.hint if error == "" else error, 14, GameTheme.MUTED if error == "" else GameTheme.WARN)
	elif not s.get("contract_offer", []).is_empty():
		_heading(parent, "계절 계약 선택", true, GameTheme.GOLD)
		_label(parent, "준비 비용을 먼저 내고 계절 마지막 주에 목표를 평가합니다. 달성하면 물자와 공훈 3점을 얻습니다.", 16, GameTheme.MUTED)
		var cards := _row(parent)
		for id in s.contract_offer:
			var mission: Dictionary = session.content.chronicle.missions[id]
			var box := _card(cards, mission.name)
			box.add_theme_constant_override("separation", 8)
			box.get_parent().add_theme_stylebox_override("panel", PixelTheme.frame(GameTheme.PANEL, GameTheme.BORDER, 12))
			_face(box, mission.character, 96)
			_label(box, mission.description, 18)
			_label(box, "준비: %s\n보상: %s + 공훈 3" % [_resources_text(mission.cost), _resources_text(mission.reward)], 14, GameTheme.TEAL)
			var error := ChronicleRules.contract_error(session.content, s, id)
			_button(box, "수락" if error == "" else "준비 물자 부족", func(): session.choose_contract(id); _changed("계약을 수락했습니다."), error != "", "contract_" + id)
		_button(parent, "건너뛰기 · 비용·보상 없음", func(): session.choose_contract("skip"); _changed("이번 계약을 건너뛰었습니다."), false, "SkipContract")

func _resources_text(resources: Dictionary) -> String:
	var parts: Array = []
	for key in resources:
		parts.append(_money(resources[key]) if key == "money" else "%s %d" % [RESOURCES.get(key, key), resources[key]])
	return " · ".join(parts) if not parts.is_empty() else "없음"

func _construction(parent: Node) -> void:
	var title := _row(parent)
	_heading(title, "건설·노동", true)
	for entry in [["facilities", "시설 건설"], ["labor", "노동 배치"], ["queue", "공사 현황"]]:
		var button := _button(title, entry[1], func(): construction_tab = entry[0]; scroll_positions.build = 0; _render(), false, "build_tab_" + entry[0])
		if construction_tab == entry[0]: _primary(button)
	var s := session.state
	if construction_tab == "labor":
		var labor := _card(parent, "농사는 자동으로 먼저 배치됩니다")
		_label(labor, "농사 → 채집 → 건설 → 생산 순으로 인력이 배치됩니다. 농사 인원은 자동으로 확보됩니다.", 16, GameTheme.MUTED)
		labor_summary = _label(labor, "", 18)
		labor_actual = _label(labor, "", 14, GameTheme.TEAL)
		labor_fields.clear()
		var presets := _row(labor)
		_button(presets, "건설 우선 배치", func(): _labor_preset({"gather": 8, "build": 8}), not _is_active(), "BuildPreset")
		_button(presets, "장작 생산 배치", func(): _labor_preset({"gather": 8, "logging": 2, "fuel": 2}), not _is_active(), "WinterPreset")
		_label(labor, "건설 우선: 채집 8·건설 8 / 장작 생산: 채집 8·벌목 2·장작 2. 작업장과 진행 중인 공사가 필요합니다.", 14, GameTheme.MUTED)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("v_separation", 8)
		labor.add_child(grid)
		for heading in ["작업", "요청 인원", "실제 배치", "상태"]:
			_heading(grid, heading, false, GameTheme.MUTED)
		for id in JOBS:
			var cap := _job_cap(id)
			if cap <= 0 and s.assign.get(id, 0) == 0 and not show_unavailable_jobs: continue
			var name_label := _label(grid, JOBS[id], 18)
			name_label.custom_minimum_size.x = 150
			var input := SpinBox.new()
			input.name = "job_" + id
			input.custom_minimum_size.x = 180
			input.max_value = floor(s.pop * s.labor_ratio)
			input.value = s.assign.get(id, 0)
			input.editable = _is_active()
			input.value_changed.connect(func(value):
				if not _is_active(): return
				var previous_step := ChronicleRules.tutorial_step(s)
				s.assign[id] = int(value)
				_sync_tutorial()
				_save()
				_refresh_labor_preview()
				_message("인력 배치를 저장했습니다.")
				if previous_step != ChronicleRules.tutorial_step(s): _render.call_deferred()
			)
			grid.add_child(input)
			labor_fields[id] = _label(grid, "", 17, GameTheme.TEAL)
			labor_fields[id].custom_minimum_size.x = 170
			_label(grid, "작업장 없음" if cap <= 0 else "배치 한도 %d명" % cap, 16, GameTheme.MUTED)
		_button(labor, "사용할 수 없는 작업 접기" if show_unavailable_jobs else "사용할 수 없는 작업 보기", func(): show_unavailable_jobs = not show_unavailable_jobs; _render())
		_refresh_labor_preview()
		return
	if construction_tab == "queue":
		var queue := _card(parent, "예약과 공사")
		_label(queue, "다음 주에 자재와 공사비를 결제합니다. 공사는 건설 인력이 있어야 진행됩니다.", 16, GameTheme.MUTED)
		for i in s.orders.size():
			var row := _row(queue)
			_label(row, "착공 대기 · " + session.content.facilities[s.orders[i]].name)
			_button(row, "예약 취소", func(): s.orders.remove_at(i); _changed("예약을 취소했습니다."), not _is_active())
		for i in s.projects.size():
			var project: Dictionary = s.projects[i]
			_heading(queue, session.content.facilities[project.id].name)
			_bar(queue, 1.0 - project.work_left / maxf(1, project.work_total), "info")
			_label(queue, "남은 작업 %d인주 · 보관 잔금 %s" % [project.work_left, _money(project.escrow)], 14)
			_button(queue, "공사 취소 · 잔여 자원 반환", func(): WeekSim.cancel_project(s, session.content, i); _changed("공사를 취소하고 반환액을 기록했습니다."), not _is_active())
		if s.orders.is_empty() and s.projects.is_empty(): _label(queue, "현재 진행 중인 공사는 없습니다.", 18)
		return
	var filters := _row(parent)
	for group in ["기반", "생산", "생활"]:
		var button := _button(filters, group, func(): facility_group = group; _render())
		if group == facility_group: _primary(button)
	_label(filters, "예약 %d건 · 공사 %d건 · 건설 요청 %d명" % [s.orders.size(), s.projects.size(), s.assign.build], 14, GameTheme.TEAL)
	var cards := GridContainer.new()
	cards.columns = 3
	parent.add_child(cards)
	for id in session.content.facilities:
		var facility: Dictionary = session.content.facilities[id]
		if facility.grade == "T": continue
		var group := "기반" if id in ["B13", "B22", "B17", "B05"] else ("생산" if id in ["B25", "B27", "B14", "B19", "B49"] else "생활")
		if group != facility_group: continue
		var cost: Dictionary = Constants.GRADE_COST[facility.grade]
		var box := _card(cards, facility.name)
		_label(box, _facility_hint(id), 16)
		_label(box, "보유 %d · 작업량 %d인주" % [s.facilities.get(id, 0), cost.work], 14, GameTheme.MUTED)
		_label(box, "%d금 · 목재 %d · 석재 %d · 도구 %d" % [cost.gold, cost.wood, cost.stone, cost.tools], 14, GameTheme.TEAL)
		var error := _build_error(id)
		var pick := _button(box, "착공 예약", func(): _command_build(id), error != "", "build_" + id)
		pick.tooltip_text = error
		if error != "": _label(box, error, 14, GameTheme.WARN)

func _labor_preset(assignments: Dictionary) -> void:
	if not _is_active(): return
	for id in JOBS: session.state.assign[id] = assignments.get(id, 0)
	_sync_tutorial()
	_changed("노동 배치를 바꿨습니다. 실제 배치 인원을 확인하세요.")

func _people(parent: Node) -> void:
	var head := _row(parent)
	_heading(head, "인물", true)
	_tag(head, "이번 주 접견 %d회 남음" % session.state.actions, GameTheme.GOLD)
	var data: Dictionary = session.content.chronicle.characters
	var columns := _row(parent)
	var gallery_area := _box(columns, 1.35)
	var gallery := GridContainer.new()
	gallery.columns = 4
	gallery_area.add_child(gallery)
	for id in data:
		var box := _card(gallery)
		_face(box, id, 96)
		var button := _button(box, data[id].name.split(" ")[0], func(): selected_person = id; _render(), false, "person_" + id)
		if id == selected_person: _primary(button)
	var person: Dictionary = data[selected_person]
	var panel := _card(columns)
	panel.size_flags_stretch_ratio = 1.0
	panel.get_parent().size_flags_vertical = SIZE_SHRINK_BEGIN
	_face(panel, selected_person, 192)
	var info := _box(panel)
	_heading(info, person.name, true, GameTheme.GOLD)
	_label(info, "%s · %s" % [person.role, person.age], 16, GameTheme.TEAL)
	_label(info, "“%s”" % person.quote, 20)
	_label(info, person.appearance, 14, GameTheme.MUTED)
	var locked: bool = not _is_active() or not ChronicleRules.active(session.state) or session.state.actions <= 0 or "council_" + selected_person in session.state.actions_used
	_primary(_button(info, "%s · %s · 일정 1회" % [person.action, person.benefit], func():
		var error := session.council_visit(selected_person)
		if error == "": _sync_tutorial(); _changed(person.name + "와의 접견을 마쳤습니다.")
		else: _message(error)
	, locked, "CouncilVisit"))
	_label(info, "접견 효과는 이번 회차에 적용됩니다. 같은 인물은 한 주에 한 번 만날 수 있습니다.", 14, GameTheme.MUTED)

func _boons(parent: Node) -> void:
	var s := session.state
	_heading(parent, "보유 특전·특성", true, GameTheme.GOLD)
	if not ChronicleRules.active(s):
		_label(parent, "이전 규칙의 회차입니다. 특전 조합 보너스와 부임 물자는 새 게임부터 적용됩니다.", 17, GameTheme.WARN)
	var counts := ChronicleRules.family_counts(session.content, s)
	var families := _row(parent)
	for id in session.content.chronicle.families:
		var family: Dictionary = session.content.chronicle.families[id]
		var box := _card(families)
		_heading(box, "%s  %d장" % [family.name, counts[id]], false, Color(family.color))
		_bar(box, counts[id] / 4.0, "info")
		_label(box, family.description, 14)
		var tier_text := "4장 효과 발동" if counts[id] >= 4 else ("2장 효과 발동" if counts[id] >= 2 else "2장부터 조합 발동")
		_label(box, tier_text if ChronicleRules.active(s) else "새 게임부터 조합 적용", 16, GameTheme.TEAL if counts[id] >= 2 and ChronicleRules.active(s) else GameTheme.MUTED)
	if ChronicleRules.active(s):
		var setup := _card(parent, "영주 특성·부임 물자")
		var traits: Array = []
		for id in s.traits: traits.append(session.content.chronicle.traits[id].name + " · " + session.content.chronicle.traits[id].description)
		_label(setup, " / ".join(traits), 16)
		var relics: Array = []
		for id in s.relics: relics.append(session.content.chronicle.relics[id].name + " · " + session.content.chronicle.relics[id].description)
		_label(setup, "부임 물자: " + " / ".join(relics), 14, GameTheme.GOLD)
	var grid := GridContainer.new()
	grid.columns = 3
	parent.add_child(grid)
	for id in s.perks:
		var perk: Dictionary = session.content.progression.perks[id]
		var card := _card(grid, perk.name)
		_label(card, perk.description)
		_label(card, session.content.chronicle.families[perk.family].name, 14, GameTheme.TEAL)
	if s.perks.is_empty(): _label(parent, "아직 선택한 특전이 없습니다.", 18)
	_label(parent, "특전 선택: 시작 / 6 / 13 / 20 / 26 / 33 / 39 / 46주 종료 · 중복 없는 24종 중 매번 3장 제시", 14, GameTheme.MUTED)
	if ChronicleRules.active(s):
		var effects := _card(parent, "현재 적용된 운영 효과")
		var names := {"harvest":"수확", "sow_labor":"파종 노동", "seed":"종자 소모", "gather":"채집", "logging":"벌목", "tool_use":"도구 소모", "maintenance":"유지비", "wages":"공공 급여", "buy":"구매가", "storage":"저장 용량", "heating":"난방 소비", "tax":"수금률", "trust":"면담 신뢰", "winter_gather":"겨울 채집"}
		var parts: Array = []
		for key in s.bonuses:
			var amount: float = s.bonuses[key]
			if key in ChronicleRules.ADDITIVE:
				parts.append("%s +%s" % [names.get(key, key), ("%.0f" % amount if key == "trust" else "%.0f%%p" % (amount * 100))])
			else: parts.append("%s %+.0f%%" % [names.get(key, key), (amount - 1) * 100])
		_label(effects, " · ".join(parts), 16, GameTheme.TEAL)

func _archive(parent: Node) -> void:
	_heading(parent, "가문 강화", true, GameTheme.GOLD)
	var intro := _card(parent, "%d 공훈 · 영구 성장" % session.profile.points)
	_label(intro, "13주를 채운 회차부터 보상이 생깁니다. 계절 생존 +2, 계약 성공 +3, 기본 과업마다 +6, 겨울 시련 +6. 공훈을 사용해 강화 항목을 구매하세요.", 16)
	_label(intro, "가문 강화는 다음 부임부터 적용됩니다. 현재 회차의 특전과 물자는 다음 회차로 옮겨지지 않습니다.", 14, GameTheme.TEAL)
	var grid := GridContainer.new()
	grid.columns = 3
	parent.add_child(grid)
	for id in session.content.progression.upgrades:
		var item: Dictionary = session.content.progression.upgrades[id]
		var box := _card(grid, item.name)
		_label(box, item.description)
		var owned: bool = id in session.profile.upgrades
		var prerequisite: bool = item.requires != "" and item.requires not in session.profile.upgrades
		if prerequisite: _label(box, "선행: " + session.content.progression.upgrades[item.requires].name, 14, GameTheme.MUTED)
		_button(box, "구매 완료" if owned else "구매 · %d 공훈" % item.cost, func(): _upgrade(id), owned or prerequisite or session.profile.points < item.cost or load_blocked, "upgrade_" + id)
	var discovered: Array = session.profile.get("discoveries", [])
	var codex := _card(parent, "발견한 특전  %d / %d" % [discovered.size(), session.content.progression.perks.size()])
	var names: Array = []
	for id in discovered: names.append(session.content.progression.perks[id].name)
	_label(codex, " · ".join(names) if not names.is_empty() else "부임 중 특전을 선택하면 이곳에 기록됩니다.", 14, GameTheme.MUTED)
	var history := _card(parent, "최근 회차")
	for item in session.profile.get("chronicles", []).slice(-5):
		_label(history, "%d주 · %s · %s · +%d점 · 특전 %d개 · 시드 %d" % [item.week, session.content.chronicle.regions[item.region].name, "시련 극복" if item.success else item.reason, item.points, item.perks.size(), item.seed], 14)
	_button(parent, "새 게임" if not _is_active() else "게임으로 돌아가기", _open_prepare if not _is_active() else _continue, load_blocked)

func _result(parent: Node) -> void:
	if session.state.is_empty(): return
	var s := session.state
	var result: Dictionary = s.result
	_heading(parent, "회차 성공" if result.success else "회차 종료", true, GameTheme.GOLD)
	var row := _row(parent)
	var left := _card(row, "%d주의 통치 · %s" % [result.week, result.reason])
	_landscape(left, mini(3, int((int(s.week) - 1) / 13)), 180)
	_label(left, "주민 %d명 · 식량 %.1f주분 · 건강 %d\n이번 회차에서 선택한 특전 %d개" % [s.pop, WeekSim.food_weeks(s), s.health, s.perks.size()], 16)
	var right := _card(row, "획득 보상")
	_heading(right, "+%d 공훈" % result.points, true, GameTheme.TEAL)
	_label(right, "과업 %d · 완주 %d · 첫 기록 %d\n계절 생존 %d · 계약 %d · 겨울 시련 %d" % [result.objective_points, result.completion_points, result.first_points, result.get("season_points", 0), result.get("contract_points", 0), result.get("trial_points", 0)], 16)
	if ChronicleRules.active(s):
		var trial: Dictionary = session.content.chronicle.trials[s.trial]
		_label(right, "시련: %s · %s" % [trial.name, "극복" if result.get("trial_passed", false) else "미달성"], 18, GameTheme.GOLD)
		_label(right, trial.description, 14, GameTheme.MUTED)
		if not result.success:
			_label(right, "미달성 목표", 18, GameTheme.TEAL)
			for goal in s.goals.values():
				if not goal.done: _label(right, "• " + goal.detail + " · " + goal.status, 14)
			if not result.get("trial_passed", false): _label(right, "• 시련의 목표를 부임 단계부터 준비하세요.", 14)
	_primary(_button(right, "가문 강화 구매", func(): _go("archive"), false, "ResultArchive"))
	_button(right, "다시 시작", _open_prepare, false, "ResultRestart")
	_label(right, "보상은 한 번만 지급됩니다. 특전·재고·관계는 다음 부임에서 초기화됩니다.", 14, GameTheme.MUTED)

func _sync_tutorial() -> void:
	if not ChronicleRules.active(session.state): return
	if ChronicleRules.tutorial_step(session.state) >= 7:
		session.profile.tutorial_done = true
		session.state.tutorial.enabled = false

func _tutorial(parent: Node) -> void:
	var step := ChronicleRules.tutorial_step(session.state)
	if step < 0 or step >= 7: return
	var titles := ["특전 선택", "사건 선택", "농지 2개 건설", "건설 인력 배치", "2주 진행", "인물 접견", "특전 확인"]
	var bodies := ["세 카드 중 하나를 고르십시오. 같은 계열은 2장부터 추가 효과가 생깁니다.", "사건의 선택 아래에 비용과 결과가 있습니다. 준비가 부족하면 비용 없는 대안을 고를 수 있습니다.", "농지 6구획이 기본 목표입니다. 건설에서 농지 두 구획을 예약하십시오.", "예약만으로 공사가 끝나지는 않습니다. 노동 배치에서 건설 인력을 8명으로 정하십시오.", "다음 주 버튼으로 2주를 보내십시오. 결산 뒤 공사와 식량이 실제로 바뀝니다.", "인물 화면에서 한 명을 접견하십시오. 주마다 접견 기회가 2회 주어집니다.", "특전·특성에서 조합과 현재 효과를 확인하십시오. 이제 계절 계약과 겨울을 준비할 차례입니다."]
	var box := _card(parent)
	box.get_parent().name = "TutorialCard"
	box.get_parent().add_theme_stylebox_override("panel", PixelTheme.frame(Color("26312b"), GameTheme.TEAL, 12))
	var row := _row(box)
	_face(row, "CH01", 48)
	var words := _box(row)
	_heading(words, "튜토리얼  %d / 7 · %s" % [step + 1, titles[step]], false, GameTheme.TEAL)
	_label(words, bodies[step], 16)
	var actions := _row(row)
	actions.size_flags_horizontal = 0
	actions.size_flags_vertical = SIZE_SHRINK_CENTER
	_button(actions, "해당 화면", func(): _tutorial_route(step), false, "TutorialAction")
	_button(actions, "접기", func(): session.state.tutorial.enabled = false; _changed("안내를 접었습니다. 메뉴의 플레이 안내에서 다시 켤 수 있습니다."), false, "SkipTutorial")

func _tutorial_route(step: int) -> void:
	match step:
		0, 1: _open_decision()
		2: construction_tab = "facilities"; facility_group = "기반"; _go("build")
		3: construction_tab = "labor"; _go("build")
		4: _advance(1)
		5: _go("people")
		6: _go("boons")

func _help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "플레이 방법"
	dialog.dialog_text = "1. 지역·영주·부임 물자를 골라 52주의 회차를 시작합니다.\n2. 특전과 사건을 선택한 뒤 건설·교역·접견을 진행합니다.\n3. 건설은 예약 후 노동 인력이 있어야 진행됩니다.\n4. 농사는 자동 배치되며, 33~36주에 수확합니다.\n5. 같은 계열 특전 2장·4장으로 조합을 만드세요.\n6. 계절 계약과 예고된 겨울 시련을 준비하세요.\n7. 회차 종료 후 공훈으로 다음 부임을 강화합니다.\n\n식량 수치는 정상 배급 기준입니다. 영구 성장은 다음 회차부터 적용됩니다."
	dialog.ok_button_text = "확인"
	if ChronicleRules.active(session.state) and _is_active():
		dialog.add_button("튜토리얼 다시 켜기", false, "tutorial")
		dialog.custom_action.connect(func(_id): session.state.tutorial = {"enabled": true, "step": 0}; _go("estate"); _save(); dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(700, 420))

func _changed(message: String) -> void:
	_sync_tutorial()
	super._changed(message)

func _advance(count: int) -> void:
	await super._advance(count)
	_sync_tutorial()
	if not load_blocked: _save()
	_render()

func _market(parent: Node) -> void:
	super._market(parent)


