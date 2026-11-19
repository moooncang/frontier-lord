extends "res://ui/expedition_ui.gd"
## 집무실에서 한 주를 운영하고, 별도 지구 현장에서 시설을 고른다.
## 규칙은 sim/realm_rules.gd, 지도는 ui/realm_board.gd가 맡는다. 여기서는 보여 주고 명령만 넘긴다.

const SIDE := 392.0
const TOP := 134.0
const LIT := Color("f3e7cd")
const LIT_MUTED := Color("ccd4cf")
const LIT_GOOD := Color("9fd48f")
const LIT_WARN := Color("f0c060")
const LIT_BAD := Color("f4a08a")
const SEASON_NAMES := ["봄", "여름", "가을", "겨울"]
const SEASON_COLORS := [Color("a8d98f"), Color("f0d27a"), Color("eda15f"), Color("a9cdf0")]
const TITLES := {"build":"영지 건설", "trade":"물자와 교역", "policy":"영주의 포고", "people":"보좌관 임명",
	"boons":"이번 통치의 특전", "ledger":"상세 장부", "journey":"계절 목표와 시련", "sanctuary":"마을 성소", "crises":"위기 대비와 운영 부담", "operating_builds":"운영 조합", "season_support":"계절 지원", "fantasy_frontier":"영지의 변화"}
const GROUPS := ["식량", "자재", "생활", "치안·행정"]
const POP_LOTS := {"harvest":"B13", "gather":"B17", "garden":"B14", "fishery":"B16", "logging":"B25", "fuel":"B25",
	"quarry":"B27", "smithy":"B33", "market_fee":"B49", "tax":"B63", "rank":"B63"}
const SELL_LOTS := {"wood":40, "stone":40, "fuel":120, "food":200}

var realm_board: RealmBoard
var active_district := "civic"
var selected_lot := ""
var outcome_open := false
var hud_before: Dictionary = {}
var outlook: Dictionary = {}
var side_page := "overview"
## 큰 창에서 집무실 책상에 더 싣는 줄 수. 소식과 지난주 기록.
var desk_alerts := 0
var desk_notes := 0
var show_build_plans := false
var receipt_breakdown := false
var crew_options: Array = []
var coached_step := -1
var selected_relic := ""
var relic_collection := false
var relic_reward := ""
var relic_scroll_positions := {}
var relic_family_filter := ""
var selected_operating_build := ""
var operating_build_scroll := 0
var selected_frontier := ""
var selected_frontier_building := ""
var fantasy_scroll_positions := {}


func _realm() -> bool:
	return not session.state.is_empty() and RealmRules.enabled(session.state)


func _run_config() -> Dictionary:
	var config := super._run_config()
	config["realm"] = true
	config["village_relics"] = true
	config["modifiers"] = true
	config["escalation"] = true
	config["fantasy"] = true
	config["mandate"] = true
	config["people"] = true
	config["regional"] = true
	return config


func _pending() -> bool:
	return super._pending() or (VillageRelics.enabled(session.state) and not session.state.realm.sanctuary.offer.is_empty())


func _decision_identity() -> String:
	var identity := super._decision_identity()
	if VillageRelics.enabled(session.state): identity += ":"+str(session.state.realm.sanctuary.offer)
	return identity


func _decision_popup() -> void:
	if VillageRelics.enabled(session.state) and not session.state.realm.sanctuary.offer.is_empty() and session.state.perk_offer.is_empty() and session.state.active_event == "":
		RelicScreens.offer(self)
	else: super._decision_popup()


func _take_relic(id: String) -> void:
	var error := session.choose_relic(id)
	if error != "": _message(error); return
	selected_relic = id
	relic_reward = id
	decision_hidden = false
	_changed("성물을 획득했습니다.")


func _equip_relic(id: String, replace_id: String = "") -> void:
	var error := session.equip_relic(id,replace_id)
	if error != "": _message(error); return
	_changed("성소의 성물 구성을 바꿨습니다.")


func _unequip_relic(id: String) -> void:
	var error := session.unequip_relic(id)
	if error != "": _message(error); return
	_changed("성물을 보관함으로 옮겼습니다.")


func _setup_environment(parent: Node) -> void:
	RelicScreens.environments(self,parent,true)


func _setup_pressure(parent: Node) -> void:
	_label(parent,"4번의 위기 평가 · 예고 후 대비\n14·27·40주에 운영 부담 상승",18,GameTheme.WARN).name = "PressureSetupHint"
	_label(parent,"왕실 신임 %d · 계절 목표나 위기 대비를 놓칠 때마다 1씩 줄고, 0이 되면 해임" % int(session.content.campaign.mandate.start),18,GameTheme.WARN).name = "MandateSetupHint"


func _catalog_screen() -> void:
	var box := _plate(Rect2(40,28,size.x-80,size.y-56))
	var row := _row(box)
	_heading(row,"발견과 통치 기록",true)
	_button(row,"성물 발견 도감",func(): relic_collection = true; _go("relic_codex"),false,"OpenRelicCodex")
	_button(row,"가문 강화",func(): _go("archive"))
	_button(row,"메뉴",func(): _go("menu"))
	_archive(_window_scroll(box))


func _coach_rect(_step: int) -> Rect2:
	return Rect2(46, TOP+32, 420, 230) if page == "estate" else Rect2(46, size.y-330, 420, 230)


func _exit_tree() -> void:
	if is_instance_valid(realm_board) and not realm_board.is_inside_tree(): realm_board.free()


func _render() -> void:
	if session == null: return
	if is_instance_valid(interface):
		var inventory := interface.find_child("RelicInventoryScroll",true,false) as ScrollContainer
		if inventory != null:
			relic_scroll_positions[str(inventory.get_meta("scroll_key","collection" if inventory.get_meta("collection",false) else "owned"))] = inventory.scroll_vertical
		var paths := interface.find_child("FantasyPathScroll",true,false) as ScrollContainer
		if paths != null: fantasy_scroll_positions["paths"] = paths.scroll_vertical
		var fantasy_detail := interface.find_child("FantasyDetailScroll",true,false) as ScrollContainer
		if fantasy_detail != null: fantasy_scroll_positions[str(fantasy_detail.get_meta("scroll_key",""))] = fantasy_detail.scroll_vertical
		var builds := interface.find_child("OperatingBuildListScroll",true,false) as ScrollContainer
		if builds != null: operating_build_scroll = builds.scroll_vertical
	# 지도는 화면을 다시 그려도 유지한다. 낡은 틀이 지워지기 전에 떼어 둔다.
	if is_instance_valid(realm_board) and realm_board.get_parent() != null:
		realm_board.get_parent().remove_child(realm_board)
	var lesson := Onboarding.current(session.state)
	if lesson.active and int(lesson.step) != coached_step:
		coached_step = int(lesson.step)
		selected_lot = ""
		if lesson.step == 1: side_page = "overview"
		elif lesson.step in [3, 5]: side_page = "overview"
	crew_options = WorkcrewRules.choices(session.state, session.content) if _is_active() and WorkcrewRules.enabled(session.state) else []
	super._render()


func _side(id: String) -> void:
	side_page = id
	selected_lot = ""
	if page != "build" or id == "growth": page = "estate"
	_render()


func _restore_relic_scroll(scroll: ScrollContainer, position_value: int) -> void:
	# 목록의 최소 크기와 스크롤 범위가 계산된 뒤 복원한다.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll) and scroll.is_inside_tree(): scroll.scroll_vertical = position_value


func _tutorial_lesson() -> Dictionary:
	var lesson := Onboarding.current(session.state)
	if not lesson.active or lesson.step == 0: return lesson
	if lesson.step == 1:
		if page != "build":
			lesson.target_id = "nav_build"
			lesson.body = "영지 둘러보기를 열어 농경지에 농지를 추가하세요."
		elif selected_lot != "" and selected_lot != "B13":
			lesson.target_id = "CloseLot"
			lesson.body = "시설 정보를 닫고 곡물 농지를 선택하세요."
		elif selected_lot == "B13": lesson.target_id = "build_B13"
		else:
			lesson.target_id = "FocusAction"
			lesson.body = "농경지의 곡물 농지 개발을 확인하세요."
	elif lesson.step in [3,5] and page != "estate":
		lesson.target_id = "nav_estate"
		lesson.body = "집무실에서 이번 주 결과와 작업반 계획을 확인하세요."
	elif lesson.step == 5 and side_page != "overview":
		lesson.target_id = "side_tab_overview"
		lesson.body = "이번 주 탭에서 작업반 방침을 선택하세요."
	return lesson


func _changed(message: String) -> void:
	super._changed(message)
	# 안내 중에는 실제 상태 변화가 승인 확인을 맡는다. 저장 오류는 항상 알린다.
	if not is_instance_valid(current_modal) and (not Onboarding.current(session.state).active or notice != message) and (page != "sanctuary" or notice != message): _message(notice)


func _message(message: String) -> void:
	notice = message
	if not is_instance_valid(interface): return
	var previous := interface.get_node_or_null("ActionNotice")
	if previous != null:
		interface.remove_child(previous)
		previous.queue_free()
	var area := Rect2(48,TOP+88,minf(620,size.x-SIDE-100),64) if page == "estate" else Rect2(48,size.y-164,minf(760,size.x-96),64)
	var toast := _plate(area,true,14)
	toast.get_parent().name = "ActionNotice"
	_label(toast,_plain(message),20,LIT)
	var frame := toast.get_parent() as Control
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	for child in frame.find_children("*","Control",true,false): child.mouse_filter = MOUSE_FILTER_IGNORE
	var reference: WeakRef = weakref(frame)
	get_tree().create_timer(4).timeout.connect(func():
		var current: Variant = reference.get_ref()
		if is_instance_valid(current): current.queue_free())


func _prioritize(kind: String, index: int) -> void:
	var error := CabinetActions.promote_project(session,index) if kind == "project" else CabinetActions.promote_order(session,index)
	if error != "": _message(error); return
	_changed("공사 순서를 바꿨습니다. 위쪽 공사부터 작업합니다.")


func _cancel_site(kind: String, index: int) -> void:
	if kind == "project":
		if index < 0 or index >= session.state.projects.size(): return
		WeekSim.cancel_project(session.state,session.content,index)
	else:
		if index < 0 or index >= session.state.orders.size(): return
		session.state.orders.remove_at(index)
	_changed("공사를 취소했습니다. 사용하지 않은 자재는 금고와 창고로 돌아갑니다.")


func _go(target: String) -> void:
	if target == "world": target = "build"
	if target != "build": selected_lot = ""
	if target == "build" and Onboarding.current(session.state).active and Onboarding.current(session.state).step == 1:
		active_district = "food"
		selected_lot = "B13"
		side_page = "overview"
	super._go(target)


## ---------- 밝은 글자(어두운 판 위) ----------

func _lit(parent: Node, text: String, px: int, color: Color = LIT, strong: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(px, 16))
	label.add_theme_color_override("font_color", color)
	if strong: label.add_theme_font_override("font", PixelTheme.heading_font())
	parent.add_child(label)
	return label


func _pic(parent: Node, key: String, px: int) -> void:
	var texture := assets.texture("icon_" + key)
	if texture == null: return
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(px, px)
	image.size_flags_vertical = SIZE_SHRINK_CENTER
	image.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(image)


func _meter(parent: Node, ratio: float, color: Color, height: int = 6) -> void:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", GameTheme.panel(Color(0, 0, 0, 0.35), Color.TRANSPARENT, 0, 0, 0))
	bar.add_theme_stylebox_override("fill", GameTheme.panel(color, color, 0, 0, 0))
	parent.add_child(bar)


func _lot_art(parent: Node, id: String, extent: int) -> void:
	var facility: Dictionary = session.content.facilities[id]
	var texture := assets.texture("building_" + str(facility.get("sprite", "")))
	if texture == null: texture = assets.texture("building_" + str(facility.get("fallback", "admin")))
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(extent, extent)
	art.size_flags_vertical = SIZE_SHRINK_BEGIN
	art.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(art)


func _level(value: float) -> Color:
	return LIT_BAD if value < 40 else LIT_WARN if value < 55 else LIT_GOOD


## ---------- 상단 ----------

func _snapshot() -> Dictionary:
	var s := session.state
	return {"week":int(s.week), "money":float(s.public.money), "food_weeks":WeekSim.food_weeks(s), "pop":int(s.pop),
		"mood":float(s.mood), "health":float(s.health), "security":float(s.security), "fuel":float(s.public.fuel),
		"wood":float(s.public.wood), "stone":float(s.public.stone), "tools":float(s.public.tools)}


func _delta(key: String, unit: String = "", scale: float = 1.0, digits: int = 0) -> String:
	if hud_before.is_empty() or int(hud_before.week) != int(session.state.week) - 1: return ""
	var change: float = (float(_snapshot()[key]) - float(hud_before[key])) / scale
	var shown := "%.*f" % [digits, absf(change)]
	if float(shown) == 0.0: return ""
	return ("▲" if change > 0 else "▼") + shown + unit


func _hud_tile(row: Node, icon: String, title: String, value: String, change: String, alert: bool, tip: String, ratio: float = -1.0, tone: Color = LIT_GOOD) -> void:
	var tile := _box(row)
	tile.add_theme_constant_override("separation", 0)
	tile.tooltip_text = tip
	tile.mouse_filter = MOUSE_FILTER_STOP
	var head := _row(tile)
	head.add_theme_constant_override("separation", 5)
	_pic(head, icon, 18)
	_lit(head, title, 15, LIT_BAD if alert else LIT_MUTED)
	var line := _row(tile)
	line.add_theme_constant_override("separation", 6)
	_lit(line, value, 24, LIT_BAD if alert else LIT, true)
	if change != "":
		var arrow := _lit(line, change, 14, LIT_GOOD if change.begins_with("▲") else LIT_BAD)
		arrow.size_flags_vertical = SIZE_SHRINK_END
	if ratio >= 0.0: _meter(tile, ratio, tone, 5)


func _campaign_hud() -> void:
	var box := _plate(Rect2(20, 8, size.x - 40, 72), true, 7)
	box.name = "CampaignHUD"
	var row := _row(box)
	row.add_theme_constant_override("separation", 10)
	var s := session.state
	var week := mini(52, int(s.week))
	@warning_ignore("integer_division")
	var season := mini(3, (week - 1) / 13)
	var date := _box(row)
	date.size_flags_stretch_ratio = 1.3
	date.add_theme_constant_override("separation", 1)
	var weather: Dictionary = RealmRules.weather_def(s, session.content) if _realm() else {}
	var sky := _lit(date, SEASON_NAMES[season] + (" · " + str(weather.name) if not weather.is_empty() else "") + " · %d회차" % session.profile.runs, 15, SEASON_COLORS[season])
	sky.clip_text = true
	_lit(date, "%d / 52주" % week, 24, LIT, true)
	_meter(date, week / 52.0, SEASON_COLORS[season], 5)
	date.tooltip_text = ("이번 계절 날씨 · %s\n%s" % [weather.name, weather.text]) if not weather.is_empty() else "네 계절 52주의 통치"
	date.mouse_filter = MOUSE_FILTER_STOP
	var food := WeekSim.food_weeks(s)
	var housing := WeekSim.capacity(s, session.content, "housing")
	var owed: int = int(s.arrears_wage) + int(s.arrears_tax)
	# 예약 공사까지 반영한 선택 방침의 한 주 예상. 고정 배치의 13주 외삽을 쓰지 않는다.
	var ahead := 1
	outlook = {"money":s.public.money,"food_weeks":food,"lowest":food,"lowest_week":week}
	for option in crew_options:
		if not option.selected: continue
		outlook.money = float(s.public.money)+float(option.deltas.money)
		outlook.food_weeks = (WeekSim.total_food(s)+float(option.deltas.food))/maxf(1.0,float(s.pop)*Constants.FOOD_PER_PERSON_WEEK*float(s.ration))
		outlook.lowest = minf(food,float(outlook.food_weeks))
	_hud_tile(row, "money", "금고", _money(s.public.money), _delta("money", "", 100.0, 1), float(s.public.money) < 1000 or owed > 0,
		"공공 금고 · %d주 뒤 작업 예상 %s%s\n%s" % [ahead, _money(outlook.get("money", s.public.money)), "\n미지급 " + _money(owed) if owed > 0 else "",WorkcrewRules.PREVIEW_SCOPE])
	_hud_tile(row, "food", "식량 비축" if food >= 4 else "식량 부족", "%.1f주" % food, _delta("food_weeks", "", 1.0, 1), food < 4,
		"공공 %.0f + 주민 %.0f\n선택 방침으로 %d주 뒤 %.1f주분\n%s" % [s.public.food, s.resident.food, ahead, outlook.get("food_weeks", food),WorkcrewRules.PREVIEW_SCOPE],
		food / 26.0, LIT_BAD if food < 4 else LIT_WARN if food < 8 else LIT_GOOD)
	_hud_tile(row, "pop", "주민", "%d명" % s.pop, _delta("pop"), housing < float(s.pop),
		"주거 %d명분 · 일할 수 있는 주민 %d명" % [int(housing), int(floor(float(s.pop) * float(s.labor_ratio)))], float(s.pop) / maxf(1.0, housing), LIT_WARN if housing - float(s.pop) < 4 else LIT_GOOD)
	_hud_tile(row, "mood", "민심", "%d" % s.mood, _delta("mood"), float(s.mood) < 40,
		"70 이상: 채집·벌목 +5%\n40 미만: -10% · 35 미만이 3주 이어지면 주민이 떠납니다", float(s.mood) / 100.0, _level(float(s.mood)))
	_hud_tile(row, "health", "건강", "%d" % s.health, _delta("health"), float(s.health) < 45,
		"70 이상: 일할 주민 +2%p\n45 미만: -5%p · 40 미만이 3주 이어지면 병으로 쓰러집니다", float(s.health) / 100.0, _level(float(s.health)))
	var threat: float = float(s.realm.threat) if _realm() else 0.0
	_hud_tile(row, "security", "치안", "%d" % s.security, _delta("security"), float(s.security) < 40,
		"습격을 막아 낼 확률과 직결됩니다.\n변경의 위협 %d / 60 · 위협이 쌓일수록 치안이 깎이고 습격이 잦아집니다" % int(threat), float(s.security) / 100.0, _level(float(s.security)))
	_button(row, "도움말", _help, false, "RunHelp")
	_button(row, "메뉴", func(): _go("menu"), false, "nav_menu")


func _season_track() -> void:
	var box := _plate(Rect2(20, 84, size.x - 40, 42), true, 3)
	box.name = "SeasonTrack"
	var row := _row(box)
	row.add_theme_constant_override("separation", 14)
	var s := session.state
	var held := RealmRules.held(s, session.content)
	var stock := _row(row)
	stock.name = "Materials"
	stock.size_flags_horizontal = SIZE_SHRINK_BEGIN
	stock.add_theme_constant_override("separation", 6)
	for item in [["wood", "목재"], ["stone", "석재"], ["tools", "도구"], ["fuel", "장작"]]:
		_pic(stock, item[0], 20)
		var amount: float = float(s.public[item[0]])
		var text := "%s %d" % [item[1], int(amount)]
		var chip := _lit(stock, text + "  ", 18, LIT_BAD if amount < 1 else LIT, true)
		chip.tooltip_text = "공공 재고 %d · 건설 예약 %d · 사용 가능 %d\n지난주 대비 %s" % [amount,held.get(item[0],0),amount-float(held.get(item[0],0)),_delta(item[0]) if _delta(item[0]) != "" else "변화 없음"]
		chip.mouse_filter = MOUSE_FILTER_STOP
	row.add_child(VSeparator.new())
	var goal := _row(row)
	goal.name = "SeasonObjective"
	goal.add_theme_constant_override("separation", 10)
	var overview := CampaignDirector.overview(s, session.content)
	if overview.enabled:
		var local: bool = str(CampaignDirector.phases(s, session.content)[overview.index].goal) == "facilities"
		var short_goal: String = str(overview.title) if local else ["농지 확대", "곳간 확보", "장작 비축", "겨울 평가"][overview.index]
		_lit(goal, "%s 목표 · %s" % [overview.season, short_goal], 18, LIT_GOOD if overview.met else LIT, true)
		_lit(goal, "%d / %d%s" % [overview.objective.current, overview.objective.target, "곳" if local else ["구획", "개", "개", "달성"][overview.index]], 18, LIT_GOOD if overview.met else LIT_WARN)
		_lit(goal, "%d주 남음" % overview.weeks_left, 16, LIT_MUTED)
		goal.tooltip_text = "달성 보상 · " + overview.reward_text + "\n미달 · " + overview.penalty_text
		goal.mouse_filter = MOUSE_FILTER_STOP
		if MandateRules.enabled(s):
			var trust := _lit(goal, "신임 %d/%d" % [s.mandate.value, s.mandate.max], 18, LIT_BAD if int(s.mandate.value) <= 1 else LIT_MUTED if int(s.mandate.value) >= int(s.mandate.max) else LIT_WARN, true)
			trust.name = "MandateChip"
			trust.tooltip_text = "왕실 신임 · 계절 목표를 놓치거나 위기 대비에 실패하면 1씩 줄어듭니다.\n0이 되면 그 주에 해임되어 통치가 끝납니다."
			trust.mouse_filter = MOUSE_FILTER_STOP
	else:
		_lit(goal, "첫 겨울 평가까지 %d주" % maxi(0, 53 - int(s.week)), 18)
	if _realm():
		var spacer := Control.new()
		spacer.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(spacer)
		var progress := RealmRules.rank_progress(s, session.content)
		var rank := _row(row)
		rank.name = "RankProgress"
		rank.size_flags_horizontal = SIZE_SHRINK_END
		if progress.next == "":
			_button(rank, progress.name,func(): _side("growth"),false,"OpenGrowth")
		else:
			var done: int = progress.checks.filter(func(item): return item.done).size()
			_button(rank, "%s %d/%d" % [progress.next,done,progress.checks.size()],func(): _side("growth"),false,"OpenGrowth")
			var lines: Array[String] = []
			for item in progress.checks: lines.append(("✓ " if item.done else "○ ") + str(item.text))
			rank.tooltip_text = "%s 승격 조건\n%s" % [progress.next, "\n".join(lines)]
			rank.mouse_filter = MOUSE_FILTER_STOP


## ---------- 화면 구성 ----------

func _campaign_screen() -> void:
	if page == "fantasy_frontier":
		var changes := _plate(Rect2(28,28,size.x-56,size.y-56),false,18)
		var heading := _row(changes)
		_heading(heading,"영지의 변화",true)
		_button(heading,"집무실로 돌아가기",func(): _go("estate"),false,"BackEstate")
		FantasyFrontierScreens.page(self,changes)
		return
	if page == "season_support":
		SeasonSupportScreens.page(self)
		return
	if page == "relic_codex":
		var codex := _plate(Rect2(28,28,size.x-56,size.y-56),false,18)
		var head := _row(codex)
		_heading(head,"성물 발견 도감",true)
		_button(head,"기록으로",func(): _go("catalog"),false,"RelicCodexBack")
		relic_collection = true
		RelicScreens.page(self,codex)
		return
	if session.state.is_empty():
		page = "menu"
		_title_hub()
		return
	_campaign_hud()
	_season_track()
	if page in ["estate", "world"]:
		_estate_playfield()
	elif page == "build":
		_district_playfield()
	else:
		var box := _plate(Rect2(28, TOP, size.x - 56, size.y - TOP - 88), false, 16)
		var row := _row(box)
		_heading(row, TITLES.get(page, "영지 관리"), true)
		_button(row, "영지로 돌아가기", func(): _go("estate"), false, "BackEstate")
		match page:
			"build": _development(box)
			"trade": _reading_market(box)
			"policy": _policy_page(box)
			"people": _people(box)
			"boons": _boons(box)
			"sanctuary": RelicScreens.page(self,box)
			"operating_builds": RelicScreens.builds_page(self,box)
			"crises": CrisisScreens.page(self,box)
			"ledger": _accounts(_window_scroll(box))
			"journey": _journey(_window_scroll(box))
	_run_dock()
	if _is_active():
		var key := _decision_identity()
		if key != decision_key:
			decision_hidden = false
			decision_key = key
		if outcome_open: _outcome_popup()
		elif relic_reward != "": RelicScreens.acquired(self,relic_reward)
		elif _pending() and not decision_hidden: _decision_popup()
		elif show_season_result: _season_result_popup()


func _estate_playfield() -> void:
	var left_width := size.x - 56 - SIDE - 18
	var scene := Control.new()
	scene.name = "EstatePlayfield"
	scene.mouse_filter = MOUSE_FILTER_IGNORE
	interface.add_child(scene)
	_place(scene,Rect2(28,TOP,left_width,size.y-TOP-88))
	var heading := _plate(Rect2(28,TOP,left_width,52),true,10)
	var title := _row(heading)
	_lit(title,"영지 집무실",22,LIT,true).size_flags_horizontal = SIZE_EXPAND_FILL
	SeasonSupportScreens.banner(self,title)
	CrisisScreens.map_status(self,title)
	# 큰 창에서만 책상에 줄을 더 싣는다. 실을 내용이 없으면 책상은 커지지 않는다.
	@warning_ignore("integer_division")
	var budget := int(clampf((size.y - 720.0) * 0.5, 0.0, 96.0)) / 30
	desk_alerts = mini(maxi(0, _realm_alerts().size() - 1), budget)
	desk_notes = mini(RealmPanels.week_notes(self).size(), budget - desk_alerts)
	var desk_height := 214.0 + 30.0 * (desk_alerts + desk_notes)
	var court := PeopleRules.court(session.state, session.content, int(left_width / 204.0))
	for position_index in court.size():
		var person: Dictionary = court[position_index]
		var card := _plate(Rect2(28 + position_index * 204, size.y - 88 - desk_height - 84, 196, 76), true, 8)
		card.name = "CourtCard_" + str(person.id)
		var line := _row(card)
		line.add_theme_constant_override("separation", 8)
		_face(line, str(person.id), 44)
		var words := _box(line)
		words.add_theme_constant_override("separation", 0)
		_lit(words, str(person.name), 18, LIT, true).clip_text = true
		_lit(words, str(person.mood), 18, LIT_GOOD if int(person.regard) > 0 else LIT_WARN if int(person.regard) < 0 else LIT_MUTED)
		card.get_parent().tooltip_text = "%s · %s\n%s\n호의가 %d번 쌓이면 보답하고, 서운함이 %d번 쌓이면 등을 돌립니다." % [person.name, person.role, person.memory, PeopleRules.LIMIT, PeopleRules.LIMIT]
	var desk := _plate(Rect2(28,size.y-88-desk_height,left_width,desk_height),false,16)
	desk.name = "OfficeDesk"
	desk.add_theme_constant_override("separation",6)
	_news_block(desk)
	_rule(desk)
	_last_week_block(desk)
	var side := _operation_sidebar()
	if side_page == "projects": _sites_block(_scroll(side))
	elif side_page == "growth":
		var growth := _scroll(side)
		FantasyFrontierScreens.summary(self,growth)
		RelicScreens.builds_summary(self,growth)
		RealmPanels.growth(self,growth)
	else: RealmPanels.office_plan(self,side)


## 앞으로 몇 주 안에 일어날 일. 가까운 순서로 돌려준다.
func _upcoming() -> Array:
	var s := session.state
	var week := int(s.week)
	var items: Array = []
	var overview := CampaignDirector.overview(s, session.content)
	for moment in overview.get("timeline", []): items.append([int(moment.remaining), str(moment.label)])
	for due in [13, 36]:
		if due >= week: items.append([due - week, "세금 수금"])
	if _realm():
		for visit in session.content.realm.immigration.weeks:
			if int(visit) >= week: items.append([int(visit) - week, "이주 희망자 방문"])
	items.sort_custom(func(a, b): return a[0] < b[0])
	var seen: Array = []
	var out: Array = []
	for item in items:
		if item[1] in seen: continue
		seen.append(item[1])
		out.append(item)
	return out


## '이번 주' 탭의 남는 자리를 채운다. used는 위쪽 내용이 이미 쓰는 높이다. 들어갈 만큼만 넣는다.
func _office_extras(parent: Node, used: float) -> void:
	var room := size.y - TOP - 88.0 - used
	var s := session.state
	var overview := CampaignDirector.overview(s, session.content)
	var coming := _upcoming()
	if room < 125 and room >= 44 and not coming.is_empty():
		_rule(parent)
		var soon := _label(parent, "다음 일정 · %s · %s" % [coming[0][1], "이번 주" if int(coming[0][0]) == 0 else "%d주 뒤" % int(coming[0][0])], 18, GameTheme.MUTED)
		soon.name = "OfficeUpcoming"
		soon.max_lines_visible = 1
		soon.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		room -= 44
	if room >= 125 and not coming.is_empty():
		_rule(parent)
		var list := _box(parent)
		list.name = "OfficeUpcoming"
		list.add_theme_constant_override("separation", 2)
		_heading(list, "다가오는 일")
		for item in coming.slice(0, 3):
			var line := _row(list)
			_label(line, str(item[1]), 18)
			var when := _label(line, "이번 주" if int(item[0]) == 0 else "%d주 뒤" % int(item[0]), 18, GameTheme.WARN if int(item[0]) <= 2 else GameTheme.MUTED)
			when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		room -= 125
	if room >= 100 and overview.enabled:
		_rule(parent)
		var goal := _box(parent)
		goal.name = "OfficeGoal"
		goal.add_theme_constant_override("separation", 2)
		_heading(goal, "%s 목표의 결과" % overview.season)
		var strike: String = " · 왕실 신임 -1" if MandateRules.enabled(s) and int(overview.index) < 3 else ""
		for entry in [["달성 · ", overview.reward_text, GameTheme.GOOD], ["미달 · ", str(overview.penalty_text) + strike, GameTheme.WARN]]:
			var outcome := _label(goal, str(entry[0]) + str(entry[1]), 18, entry[2])
			outcome.max_lines_visible = 1
			outcome.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			outcome.tooltip_text = str(entry[1])
		room -= 100
	if room >= 110 and _realm():
		var rank := RealmRules.rank_progress(s, session.content)
		if str(rank.next) != "":
			_rule(parent)
			var grade := _box(parent)
			grade.name = "OfficeRank"
			grade.add_theme_constant_override("separation", 2)
			_heading(grade, "%s → %s" % [rank.name, rank.next])
			var shown := 0
			for condition in rank.checks:
				if condition.done or shown >= 2: continue
				_label(grade, "○ " + str(condition.text), 18)
				shown += 1
			if shown == 0: _label(grade, "조건을 모두 갖췄습니다 · 다음 주에 승격", 18, GameTheme.GOOD)


func _operation_sidebar() -> VBoxContainer:
	var side := _plate(Rect2(size.x-28-SIDE,TOP,SIDE,size.y-TOP-88),false,14)
	side.name = "OperatingWorkspace"
	side.add_theme_constant_override("separation",8)
	var tabs := _row(side)
	for entry in [["overview","이번 주"],["projects","공사"],["growth","성장"]]:
		var button := _button(tabs,entry[1],func(): _side(entry[0]),false,"side_tab_"+entry[0])
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		if side_page == entry[0]: _primary(button)
	return side


func _district_playfield() -> void:
	if active_district == "fantasy" and FantasyFrontiers.overview(session.state,session.content).get("selected",[]).is_empty(): active_district = "civic"
	var height := size.y-TOP-88
	var width := size.x-56-SIDE-18
	var frame := Panel.new()
	frame.name = "DistrictPlayfield"
	frame.add_theme_stylebox_override("panel",RealmTheme.surface(DARK,0))
	interface.add_child(frame)
	_place(frame,Rect2(28,TOP,width,height))
	var head := HBoxContainer.new()
	frame.add_child(head)
	head.position = Vector2(8,7)
	head.size = Vector2(width-16,38)
	head.add_theme_constant_override("separation",6)
	var districts: Array = [["civic","마을"],["food","농경지"],["industry","작업장"],["defense","성벽"]]
	if not FantasyFrontiers.overview(session.state,session.content).get("selected",[]).is_empty(): districts.append(["fantasy","이계 지구"])
	for entry in districts:
		var button := _button(head,entry[1],func(): _change_district(entry[0]),false,"district_"+entry[0])
		button.add_theme_font_size_override("font_size",18)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 36
		if active_district == entry[0]: _primary(button)
	if not is_instance_valid(realm_board):
		realm_board = RealmBoard.new()
		realm_board.name = "RealmBoard"
		realm_board.lot_selected.connect(_select_lot)
		realm_board.shrine_selected.connect(func(): _go("sanctuary"))
	frame.add_child(realm_board)
	realm_board.position = Vector2(4,50)
	realm_board.size = Vector2(width-8,height-84)
	realm_board.show_plans = show_build_plans
	realm_board.set_district(active_district)
	realm_board.configure(assets,session.state,session.content,selected_lot,_is_active())
	var foot := HBoxContainer.new()
	frame.add_child(foot)
	foot.position = Vector2(10,height-32)
	foot.size = Vector2(width-20,28)
	var district_caption := "건물과 빈터를 선택해 개발합니다"
	if active_district == "fantasy":
		var names: Array[String] = []
		for path in FantasyFrontiers.overview(session.state,session.content).paths:
			if path.selected: names.append(str(path.name))
		district_caption = "이계 지구 · "+" / ".join(names)
	_lit(foot,district_caption,18,LIT_MUTED).size_flags_horizontal = SIZE_EXPAND_FILL
	var plans := _button(foot,"미해금 터 숨기기" if show_build_plans else "전체 터 보기",func(): show_build_plans = not show_build_plans; _render(),false,"MapPlansToggle")
	plans.add_theme_font_size_override("font_size",16)
	plans.custom_minimum_size.y = 28
	for state in ["normal","hover","pressed","disabled"]:
		var style := plans.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		plans.add_theme_stylebox_override(state,style)
	var side := _operation_sidebar()
	if selected_lot != "" and session.content.facilities.has(selected_lot): _lot_panel(side,selected_lot)
	elif side_page == "projects": _sites_block(_scroll(side))
	else:
		var plan := _scroll(side)
		_heading(plan,"건설 지구")
		_label(plan,"건물을 누르면 가동 상태와 추가 개발 비용을 확인할 수 있습니다.",19)
		_rule(plan)
		RealmPanels.construction(self,plan)


func _change_district(id: String) -> void:
	active_district = id
	selected_lot = ""
	side_page = "overview"
	_render()


func _select_lot(id: String) -> void:
	active_district = RealmBoard.district_for(id)
	selected_lot = "" if selected_lot == id else id
	page = "build"
	side_page = "overview"
	_render()


func _open_build_lot(id: String) -> void:
	active_district = RealmBoard.district_for(id)
	selected_lot = id
	side_page = "overview"
	page = "build"
	_render()


func _run_dock() -> void:
	var dock := _plate(Rect2(20,size.y-76,size.x-40,60),true,6)
	dock.name = "RunDock"
	var row := _row(dock)
	row.add_theme_constant_override("separation",10)
	for entry in [["estate","집무실"],["build","영지 둘러보기"],["trade","물자"]]:
		var button := _button(row,entry[1],func(): _go(entry[0]),false,"nav_"+entry[0])
		if page == entry[0]: _primary(button)
	_button(row,"통치·성장",func(): management_open = true; _render(),false,"MoreActions")
	_spacer(row)
	var next := _button(row,"결정 먼저 확인" if _pending() else "1주 진행 →",_open_decision if _pending() else func(): _advance(1),busy or not _is_active(),"NextWeek")
	next.custom_minimum_size.x = 240
	next.tooltip_text = "Space · 이번 주 계획으로 한 주를 진행하고 집무실에서 결과를 확인합니다."
	_primary(next)


func _management_menu() -> void:
	_shade(interface,.7)
	var box := _window("통치와 성장",Vector2(740,minf(540,size.y-80)),false,true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind","management")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(grid)
	for entry in [["policy","포고와 배급"],["people","보좌관"],["boons","특전"],["sanctuary","성물"],["journey","계절 목표"],["season_support","계절 지원"],["fantasy_frontier","영지의 변화"],["ledger","상세 장부"],["archive","가문 강화"],["catalog","발견·통치 기록"]]:
		var target: String = entry[0]
		var button := _button(grid,entry[1],func(): management_open = false; _go(target),false,"nav_"+target if target in ["policy","people","boons","sanctuary"] else "more_"+target)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.size_flags_vertical = SIZE_EXPAND_FILL
	var closing := _row(box)
	_button(closing,"닫기",func(): management_open = false; _render(),false,"CloseManagement").size_flags_horizontal = SIZE_EXPAND_FILL
	_quiet(_button(closing,"이번 통치 끝내기",func(): management_open = false; _render(); _ask_retire(),not _is_active(),"EndRunFromOffice"))


## ---------- 옆 패널: 이번 주 ----------

func _week_panel(parent: Node) -> void:
	RealmPanels.overview(self,parent)


func _realm_alerts() -> Array:
	var s := session.state
	var out: Array = []
	if not _is_active(): return out
	for error in WeekSim.validate_orders(s, session.content):
		out.append(["bad", "착공 불가 · %s. 아래 공사 목록에서 취소하거나 자재를 구하세요." % _plain(str(error))])
	if _realm():
		for item in s.realm.news: out.append([str(item.level), str(item.text)])
	out.append_array(CrisisScreens.alerts(s,session.content))
	if MandateRules.enabled(s) and int(s.mandate.value) == 1:
		out.append(["bad", "왕실 신임이 1 남았습니다. 계절 목표나 위기 대비를 한 번 더 놓치면 해임됩니다."])
	var week := int(s.week)
	var food := WeekSim.food_weeks(s)
	if food < 4: out.append(["bad", "식량이 %.1f주분뿐입니다. 물자 주문은 %d주 뒤 도착합니다." % [food, RealmRules.delivery(s)]])
	elif food < 8 or float(outlook.get("lowest", 99.0)) < 4: out.append(["warn", "식량 %.1f주분 · 지금 배치로는 %d주에 %.1f주분까지 줄어듭니다." % [food, outlook.get("lowest_week", week), outlook.get("lowest", food)]])
	var housing := WeekSim.capacity(s, session.content, "housing")
	if housing < float(s.pop): out.append(["bad", "주거가 %d명분 부족합니다. 움집 구역을 지으세요." % int(float(s.pop) - housing)])
	var heating := WeekSim.bonus(s, "heating")
	if s.get("trial", "") == "frost" and not s.get("trial_started", false): heating *= 1.5
	var fuel_need: float = float(s.pop) * 0.1 * heating * 13.0
	if week >= 27 and week < 40 and CampaignDirector.enabled(s): fuel_need = float(CampaignDirector.overview(s,session.content).objective.target)
	if week >= 22 and week < 40 and float(s.public.fuel) < fuel_need:
		out.append(["warn", "겨울 장작 %d / %d · 겨울까지 %d주. 벌목소의 장작 방침이나 물자 주문으로 채우세요." % [int(s.public.fuel), int(ceil(fuel_need)), 40 - week]])
	elif week >= 40 and float(s.public.fuel) < float(s.pop) * 0.1 * heating:
		out.append(["bad", "난방 장작이 떨어졌습니다. 건강이 매주 깎입니다."])
	if float(s.mood) < 40: out.append(["warn", "민심 %d · 35 미만이 3주 이어지면 주민이 떠납니다. 구휼·잔치·포고를 살펴보세요." % s.mood])
	if float(s.health) < 45: out.append(["warn", "건강 %d · 진료소, 위생 포고, 겨울 난방이 건강을 올립니다." % s.health])
	if _realm():
		if float(s.realm.threat) >= 25 and float(s.security) < 55:
			out.append(["warn", "변경의 위협 %d · 치안 %d. 목책·민병·용병으로 습격에 대비하세요." % [s.realm.threat, s.security]])
		for visit in session.content.realm.immigration.weeks:
			var ahead := int(visit) - week
			if ahead >= 0 and ahead <= 3:
				var free := int(housing) - int(s.pop)
				out.append(["info" if free >= 6 else "warn", "%s 이주 희망자가 옵니다 · 빈집 %d명분%s" % ["이번 주 말" if ahead == 0 else "%d주 뒤" % ahead, maxi(0, free), "" if free >= 6 else " (움집 구역을 지으면 더 받을 수 있습니다)"]])
	if week in [13, 36]: out.append(["info", "이번 주 말에 세금을 걷습니다."])
	if out.is_empty(): out.append(["good", "평온한 한 주입니다. 다음 계절을 준비하세요."])
	return out


func _plain(text: String) -> String:
	for asset in ["money", "food", "wood", "stone", "tools", "fuel", "iron"]:
		text = text.replace(asset, TurnReceipt.LABELS[asset])
	return text


func _news_block(parent: Node) -> void:
	var box := _box(parent)
	box.name = "RealmNews"
	box.add_theme_constant_override("separation",2)
	var alerts := _realm_alerts()
	var priority := {"bad":0,"warn":1,"good":2,"info":3}
	alerts.sort_custom(func(a,b): return priority.get(a[0],3) < priority.get(b[0],3))
	var head := _row(box)
	if CabinetRules.enabled(session.state):
		var advisor := str(session.state.cabinet.get("advisor","CH01"))
		_face(head,advisor,48)
		var person := CabinetActions.advisor_definition(session,advisor)
		if not person.is_empty():
			var identity := _box(head)
			identity.size_flags_horizontal = SIZE_SHRINK_BEGIN
			identity.custom_minimum_size.x = 132
			identity.add_theme_constant_override("separation",0)
			_label(identity,str(person.name),18)
			_label(identity,str(person.role),18,GameTheme.MUTED)
			identity.tooltip_text = str(person.benefit)+" · 주 진행 시 적용"
	var tones := {"bad":GameTheme.BAD,"warn":GameTheme.WARN,"good":GameTheme.GOOD,"info":GameTheme.TEAL}
	if not alerts.is_empty():
		var line := _label(head,str(alerts[0][1]),18,tones.get(alerts[0][0],GameTheme.TEXT))
		line.max_lines_visible = 2
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.tooltip_text = str(alerts[0][1])
	var all_news := _button(head,"소식",_news_popup,false,"AllNews")
	all_news.add_theme_font_size_override("font_size",16)
	all_news.custom_minimum_size.y = 32
	for index in range(1, 1 + mini(desk_alerts, alerts.size() - 1)):
		var extra := _label(box, ("■ " if alerts[index][0] == "bad" else "▲ " if alerts[index][0] == "warn" else "· ") + str(alerts[index][1]), 18, tones.get(alerts[index][0], GameTheme.TEXT))
		extra.max_lines_visible = 1
		extra.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		extra.tooltip_text = str(alerts[index][1])

func _news_popup() -> void:
	_shade(interface,0.7).name = "DecisionBlocker"
	var box := _window("영지 소식",Vector2(760,minf(560,size.y-80)),false,true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind","news")
	var area := _scroll(box)
	for item in _realm_alerts():
		_label(area,str(item[1]),20,GameTheme.BAD if item[0] == "bad" else GameTheme.TEXT)
		_rule(area)
	_primary(_button(box,"확인",_render,false,"CloseNews"))


func _sites_block(parent: Node) -> void:
	RealmPanels.construction(self,parent)


func _focus_item() -> Dictionary:
	var item := super._focus_item()
	if not _realm() or item.get("kind") == "build" or item.get("title") != "다음 개발을 고를 수 있습니다": return item
	var s := session.state
	var week := int(s.week)
	var free := WeekSim.capacity(s, session.content, "housing") - float(s.pop)
	var picks: Array = []
	if int(s.facilities.get("B25", 0)) == 0: picks.append(["B25", "벌목소가 필요합니다", "목재와 겨울 장작을 스스로 마련합니다.\n채석장·제재소도 벌목소가 있어야 열립니다."])
	if int(s.facilities.get("B16", 0)) == 0: picks.append(["B16", "여울에 어장을 놓읍시다", "작업반을 쓰지 않고 주민 4명이\n매주 식량 16을 건져 올립니다."])
	if float(s.realm.threat) >= 12 and int(s.facilities.get("B67", 0)) == 0: picks.append(["B67", "목책을 세울 때입니다", "변경의 위협이 쌓이고 있습니다.\n목책은 치안과 습격 방어 확률을 올립니다."])
	if free < 8 and week < 36: picks.append(["B01", "새 식구를 받을 집", "빈집이 %d명분뿐입니다.\n이주 희망자는 빈집이 있어야 머뭅니다." % int(maxf(0, free))])
	if int(s.facilities.get("B17", 0)) < 2: picks.append(["B17", "채집터를 하나 더", "남는 주민이 스스로 채집터를 채워\n봄~가을 식량을 늘립니다."])
	if int(s.facilities.get("B49", 0)) == 0 and int(s.facilities.get("B22", 0)) > 0: picks.append(["B49", "장터를 열 수 있습니다", "운송료가 줄고 매주 통행세가 들어옵니다.\n남는 물자도 팔 수 있게 됩니다."])
	for pick in picks:
		if RealmBoard.lock_reason(s, session.content, pick[0]) == "":
			return {"kind":"build", "title":pick[1], "body":pick[2], "action":"건설 승인", "facility":pick[0]}
	return item


func _workcrew_panel(parent: Node) -> void:
	var panel := _box(parent)
	panel.name = "PolicyChoices"
	panel.add_theme_constant_override("separation", 6)
	if not WorkcrewRules.enabled(session.state):
		_heading(panel, "작업반")
		_label(panel, "예전 규칙의 통치 · 인력은 자동 배치됩니다.", 18, GameTheme.MUTED)
		_button(panel, "다음 개발 선택", func(): _ack_tutorial("next_development"); _go("build"), false, "crew_legacy")
		return
	var options := crew_options
	var metric := "work"
	if session.state.orders.is_empty() and session.state.projects.is_empty() and int(session.state.facilities.get("B25",0)) > 0:
		metric = "fuel" if int(session.state.week) >= 27 or session.state.workcrew.policy == "winter" else "wood"
	var staff := ""
	for option in options:
		if option.selected: staff = "작업반 %d명" % option.allocation.crew
	var head := _row(panel)
	_heading(head, "작업반 방침")
	var note := _label(head, "식량 · "+{"work":"공사","fuel":"장작","wood":"목재"}[metric]+" 예상", 18, GameTheme.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.tooltip_text = staff+"\n농사에 먼저 배정하고, 최대 20명이 공공 작업을 합니다.\n남는 주민은 스스로 채집터·채소밭·어장 일을 합니다."
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",8)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.add_child(grid)
	var lesson := Onboarding.current(session.state)
	var locked: bool = lesson.active and lesson.step < 5
	for option in options:
		var copy: String = "%s%s\n식량 %+.0f · 공사 %d" % ["✓ " if option.selected else "", option.name, option.deltas.food, option.work]
		if metric != "work":
			copy = "%s%s\n식량 %+.0f · %s %+.0f" % ["✓ " if option.selected else "",option.name,option.deltas.food,"장작" if metric == "fuel" else "목재",option.deltas[metric]]
		if not option.available:
			copy = option.name + "\n" + ("공사가 있을 때" if option.id == "build" else "벌목소 필요" if option.id == "winter" and int(session.state.facilities.get("B25", 0)) == 0 else "목재·인력 부족" if option.id == "winter" else "지금은 일감 없음")
		var button := _button(grid, copy, func(): _choose_workcrew(option.id), not option.available or locked, "crew_" + option.id)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(150, 64)
		button.add_theme_font_size_override("font_size", 18)
		button.tooltip_text = option.description + "\n식량 %+.0f · 목재 %+.0f · 장작 %+.0f · 공사 %d\n" % [option.deltas.food,option.deltas.wood,option.deltas.fuel,option.work] + option.scope + ("\n" + option.error if not option.available else "")
		if option.selected: _primary(button)


func _last_week_block(parent: Node) -> void:
	RealmPanels.result_strip(self,parent)


func _cost_row(parent: Node, cost: Dictionary) -> void:
	var held := RealmRules.held(session.state, session.content)
	var row := _row(parent)
	row.name = "ProjectCosts"
	row.add_theme_constant_override("separation", 10)
	for asset in ["money", "wood", "stone", "tools"]:
		var need := float(cost.get(asset, 0))
		if need <= 0: continue
		var short: bool = float(session.state.public[asset]) - float(held.get(asset, 0)) < need
		var chip := _label(row, ("%s %s" % [TurnReceipt.LABELS[asset], _money(need) if asset == "money" else "%d" % int(need)]), 18, GameTheme.BAD if short else GameTheme.TEXT)
		chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
		chip.autowrap_mode = TextServer.AUTOWRAP_OFF


func _lot_panel(parent: Node, id: String) -> void:
	var s := session.state
	var facility: Dictionary = session.content.facilities[id]
	var kind := RealmBoard.lot_kind(s, session.content, id)
	var count := int(s.facilities.get(id, 0))
	var box := _box(parent)
	box.name = "LotPanel"
	box.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 7)
	var head := _row(box)
	_lot_art(head, id, 60)
	var words := _box(head)
	words.add_theme_constant_override("separation", 2)
	_heading(words, str(facility.name))
	var state_text: String = {"built":"보유 %d / %d" % [count, int(facility.get("max", 1))], "temp":"임시 시설", "site":"공사 중", "open":"지을 수 있음", "locked":"잠김"}[kind]
	_label(words, state_text, 18, GameTheme.MUTED)
	var close := _button(head, "닫기", func(): selected_lot = ""; _render(), false, "CloseLot")
	close.size_flags_horizontal = SIZE_SHRINK_END
	_quiet(close)
	var reading := _scroll(box)
	reading.name = "LotDescription"
	_label(reading, str(facility.get("effect", "")), 20, GameTheme.TEAL)
	if facility.has("jobs"):
		_label(reading, "남는 주민 %d명 배정%s" % [int(facility.jobs)," · 공공 급여 지급" if facility.get("account","public") == "public" else ""], 18, GameTheme.MUTED)
	if count > 0 and facility.get("fantasy",false): FantasyFrontierScreens.operation(self,reading,id)
	if kind == "temp": _label(reading, "현재 %s 사용 중. 건설하면 정식 시설로 바뀝니다." % RealmBoard.TEMP[id][1], 18, GameTheme.MUTED)
	if kind == "locked": _label(reading, RealmBoard.lock_reason(s, session.content, id), 18, GameTheme.WARN)
	for index in s.projects.size():
		if s.projects[index].id != id: continue
		_label(reading, "남은 작업 %d / %d" % [s.projects[index].work_left, s.projects[index].work_total], 18)
		_bar(reading, 1.0 - float(s.projects[index].work_left) / maxf(1.0, float(s.projects[index].work_total)))
	if s.orders.has(id): _label(reading, "승인됨 · 다음 주 비용을 치르고 착공합니다.", 18, GameTheme.TEAL)
	var links := {"B49":["trade", "물자 주문 · 판매"], "B52":["trade", "물자 주문"], "B63":["policy", "포고 정하기"], "B22":["trade", "식량 주문"], "B11":["people", "보좌관 만나기"]}
	if links.has(id) and (count > 0 or kind == "temp"):
		_button(reading, links[id][1], func(): _go(links[id][0]), false, "lot_link")
	if id == "B63" and kind == "temp": _label(reading, "서기관실: 포고 칸 +1 · 세금 증가", 18, GameTheme.MUTED)
	if kind != "locked" and _is_active() and CabinetRules.enabled(s):
		var offer := CabinetActions.offer(session, id)
		var limit_hit: bool = count + RealmBoard.sites(s, id) >= int(facility.get("max", 99)) and _realm()
		if not limit_hit:
			_rule(box)
			_cost_row(box, offer.cost)
			_label(box, "완공 예상 · " + str(offer.eta_text) if str(offer.error) == "" else str(offer.error), 18, GameTheme.MUTED if str(offer.error) == "" else GameTheme.WARN)
			_primary(_button(box, ("하나 더 건설" if count > 0 else "건설 승인") + (" ×%d" % int(offer.count) if int(offer.count) > 1 else ""), func(): _command_build(id), str(offer.error) != "", "build_" + id))


func _command_build(id: String) -> void:
	var error := CabinetActions.start_project(session, id)
	if error != "":
		_message(_plain(error))
		return
	page = "estate"
	selected_lot = ""
	receipt.clear()
	_changed("%s 승인 · 다음 주에 비용을 치르고 착공합니다." % session.content.facilities[id].name)


## ---------- 건설 목록 ----------

func _build_block(id: String) -> String:
	var s := session.state
	var reason := RealmBoard.lock_reason(s, session.content, id)
	if reason != "": return reason
	var count := CabinetActions._count(s, id)
	var sites: int = s.orders.size() + s.projects.size()
	if sites > 0 and sites + count > RealmRules.project_limit(s, session.content): return "공사 자리가 가득 찼습니다"
	var cost: Dictionary = Constants.GRADE_COST[session.content.facilities[id].grade]
	var held := RealmRules.held(s, session.content)
	var lacking: Array[String] = []
	if float(s.public.money) - float(held.get("money", 0)) < float(cost.gold) * 100 * count: lacking.append("금고")
	for asset in ["wood", "stone", "tools"]:
		if float(s.public[asset]) - float(held.get(asset, 0)) < float(cost[asset]) * count: lacking.append(str(TurnReceipt.LABELS[asset]))
	return "부족 · " + " ".join(lacking) if not lacking.is_empty() else ""


func _development(parent: Node) -> void:
	var s := session.state
	var top := _row(parent)
	var sites: int = s.orders.size() + s.projects.size()
	_label(top, "공사 %d / %d곳 진행 중 · 승인한 비용은 다음 주 착공 때 치릅니다. 빨간 글자는 모자란 자재입니다." % [sites, RealmRules.project_limit(s, session.content)], 18)
	var area := _window_scroll(parent)
	for group in GROUPS:
		_heading(area, group)
		var grid := GridContainer.new()
		grid.columns = 3 if size.x < 1400 else 4
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		area.add_child(grid)
		for id in session.content.facilities:
			var facility: Dictionary = session.content.facilities[id]
			if facility.grade == "T" or facility.get("group", "") != group: continue
			if facility.get("realm", false) and not _realm(): continue
			var count := int(s.facilities.get(id, 0))
			var building := RealmBoard.sites(s, id)
			var card := _card(grid)
			card.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
			var head := _row(card)
			_lot_art(head, id, 56)
			var words := _box(head)
			words.add_theme_constant_override("separation", 0)
			_heading(words, str(facility.name))
			_label(words, "보유 %d%s%s" % [count, " / %d" % int(facility.max) if _realm() and facility.has("max") else "", " · 공사 %d" % building if building > 0 else ""], 18, GameTheme.GOOD if count > 0 else GameTheme.MUTED)
			_label(card, str(facility.get("effect", "")), 18)
			var grade: Dictionary = Constants.GRADE_COST[facility.grade]
			var batch := CabinetActions._count(s,id)
			_cost_row(card, {"money":float(grade.gold) * 100 * batch, "wood":grade.wood * batch, "stone":grade.stone * batch, "tools":grade.tools * batch})
			var block := _build_block(id) if _is_active() else "종료된 통치"
			var start := _button(card, ("건설 승인 ×%d" % batch if batch > 1 else "건설 승인") if block == "" else block, func(): _command_build(id), block != "", "build_" + id)
			if block == "": _primary(start)


## ---------- 포고 ----------

func _policy_page(parent: Node) -> void:
	var s := session.state
	var area := _window_scroll(parent)
	if _realm():
		var realm: Dictionary = s.realm
		var wait := int(realm.policy_next) - int(s.week)
		_label(area, "포고 %d / %d칸 · %s · 서기관실과 촌락 승격으로 칸이 늘어납니다." % [realm.policies.size(), RealmRules.policy_slots(s), "지금 바꿀 수 있습니다" if wait <= 0 else "%d주 뒤에 다시 바꿀 수 있습니다" % wait], 20, GameTheme.TEAL)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		area.add_child(grid)
		for id in session.content.realm.policies:
			var policy: Dictionary = session.content.realm.policies[id]
			var active: bool = id in realm.policies
			var card := _card(grid)
			card.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
			var head := _row(card)
			_heading(head, ("● " if active else "") + str(policy.name), false, GameTheme.GOOD if active else GameTheme.TEXT)
			var tag := _label(head, str(policy.tag), 18, GameTheme.MUTED)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_label(card, "＋ " + str(policy.good), 18, GameTheme.GOOD)
			_label(card, "－ " + str(policy.bad), 18, GameTheme.WARN)
			var error := RealmRules.policy_error(s, session.content, id, not active)
			var toggle := _button(card, ("철회" if active else "시행") if error == "" else error, func():
				var failed := RealmRules.set_policy(session.state, session.content, id, not active)
				if failed == "": _changed("%s · %s" % [policy.name, "철회했습니다" if active else "시행합니다"])
				else: _message(failed)
			, error != "", "policy_" + id)
			if error == "" and not active: _primary(toggle)
	else:
		_label(area, "이 통치는 예전 규칙으로 진행 중이라 포고를 쓸 수 없습니다. 새 통치부터 사용할 수 있습니다.", 20, GameTheme.MUTED)
	_rule(area)
	_heading(area, "식량 배급")
	_label(area, "배급을 줄이면 식량은 아끼지만 민심과 건강이 내려갑니다. 연말 식량 목표는 정상 배급 기준입니다.", 18, GameTheme.MUTED)
	var rations := _row(area)
	for item in [[1.0, "정상 배급"], [0.9, "10% 절약"], [0.75, "25% 비상 배급"]]:
		var on := is_equal_approx(float(s.ration), float(item[0]))
		var pick := _button(rations, ("● " if on else "") + str(item[1]), func(): session.state.ration = item[0]; _changed(str(item[1]) + "(으)로 바꿨습니다."), not _is_active() or on, "ration_%d" % int(float(item[0]) * 100))
		pick.size_flags_horizontal = SIZE_EXPAND_FILL


## ---------- 물자와 교역 ----------

func _reading_market(parent: Node) -> void:
	var s := session.state
	var weeks := RealmRules.delivery(s)
	var note := "지금 결제 · %d주 뒤 도착 · 수레 %d / %d대 운행" % [weeks, s.shipments.size(), RealmRules.carts(s)]
	if _realm():
		var season := WeekSim.season_of(WeekSim.week_of_year(clampi(int(s.week), 1, 52)))
		var marks: Array[String] = []
		for asset in session.content.realm.prices:
			var rate := float(session.content.realm.prices[asset][season])
			if not is_equal_approx(rate, 1.0): marks.append("%s %s%d%%" % [RESOURCES[asset], "+" if rate > 1 else "", int(round((rate - 1.0) * 100))])
		if not marks.is_empty(): note += "\n%s 시세 · %s" % [SEASON_NAMES[season], " · ".join(marks)]
	_label(parent, note, 18, GameTheme.TEAL)
	var area := _window_scroll(parent)
	_heading(area, "사들이기")
	var grid := GridContainer.new()
	grid.columns = 5 if size.x >= 1400 else 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	area.add_child(grid)
	for package in CabinetActions.supplies(session):
		var card := _card(grid)
		card.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
		_heading(card, "%s %d" % [RESOURCES[package.asset], package.quantity])
		_label(card, "보유 %d · %d주 도착" % [int(s.public[package.asset]), package.arrival], 18, GameTheme.MUTED)
		var buy := _button(card, _money(package.price) if package.error == "" else str(package.error), func():
			var error := CabinetActions.buy_supply(session, package.asset)
			if error == "": _changed("%s %d 주문 · %d주 도착" % [RESOURCES[package.asset], package.quantity, package.arrival])
			else: _message(error)
		, package.error != "", "supply_" + package.asset)
		if package.error == "": _primary(buy)
	_heading(area, "내다 팔기")
	if _realm() and int(s.facilities.get("B49", 0)) <= 0:
		_label(area, "장터를 지으면 남는 물자를 팔 수 있습니다. 대금은 수레가 돌아올 때 들어옵니다.", 18, GameTheme.MUTED)
	else:
		var held := RealmRules.held(s, session.content)
		var sell_grid := GridContainer.new()
		sell_grid.columns = 4
		sell_grid.size_flags_horizontal = SIZE_EXPAND_FILL
		area.add_child(sell_grid)
		for asset in SELL_LOTS:
			var quantity: int = SELL_LOTS[asset]
			var quote := session.trade_quote(asset, quantity, false)
			var have := float(s.public[asset]) - float(held.get(asset, 0))
			var card := _card(sell_grid)
			card.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
			_heading(card, "%s %d" % [RESOURCES[asset], quantity])
			_label(card, "팔 수 있는 양 %d" % int(maxf(0, have)), 18, GameTheme.MUTED)
			var blocked := "운송료도 안 나옵니다" if quote <= 0 else "재고 부족" if have < quantity else "수레가 없습니다" if s.shipments.size() >= RealmRules.carts(s) else ""
			_button(card, "+" + _money(quote) if blocked == "" else blocked, func():
				var error := session.trade(asset, quantity, false)
				if error == "": _changed("%s %d 출하 · 대금은 %d주 뒤" % [RESOURCES[asset], quantity, weeks])
				else: _message(error)
			, blocked != "" or not _is_active(), "sell_" + asset)
	_heading(area, "길 위의 수레")
	if s.shipments.is_empty(): _label(area, "운행 중인 수레가 없습니다.", 18, GameTheme.MUTED)
	for shipment in s.shipments:
		_label(area, "%s %s %d · %d주 %s" % ["구매" if shipment.buy else "판매", RESOURCES[shipment.asset], shipment.quantity, shipment.arrival, "도착" if shipment.buy else "대금 수령"], 18)


## ---------- 사건과 결과 ----------

func _event_choices(parent: Node) -> void:
	var id: String = session.state.active_event
	var event: Dictionary = RealmRules.event_definition(session.state,session.content,id)
	var modern: bool = event.get("realm", false)
	var copy := {} if modern else ConciseCopy.event_brief(id, event)
	var top := _row(parent)
	top.add_theme_constant_override("separation", 18)
	_face(top, event.get("portrait", "CH01"), 96)
	var words := _box(top)
	words.add_theme_constant_override("separation", 4)
	var byline := _row(words)
	var tone := str(event.get("tone", ""))
	if tone != "":
		var category := _label(byline, "좋은 소식" if tone == "positive" else "문제 발생", 18, GameTheme.GOOD if tone == "positive" else GameTheme.BAD)
		category.name = "EventTone"
		category.size_flags_horizontal = SIZE_SHRINK_BEGIN
		category.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label(byline, str(event.get("speaker", "")), 18, GameTheme.MUTED)
	_heading(words, str(event.title) if modern else str(copy.title), true)
	_label(words, str(event.body) if modern else str(copy.body), 20)
	var visitor: Dictionary = PeopleRules.view(session.state, session.content, str(event.get("portrait", "")))
	if visitor.known:
		var memo := _label(words, "%s · 지금 사이 %s" % [visitor.memory, visitor.mood], 18, GameTheme.GOOD if int(visitor.regard) > 0 else GameTheme.WARN if int(visitor.regard) < 0 else GameTheme.MUTED)
		memo.name = "EventMemory"
	var choices := _scroll(parent)
	choices.name = "EventChoices"
	var held := RealmRules.held(session.state, session.content)
	for index in event.options.size():
		var option: Dictionary = event.options[index]
		var card := _card(choices)
		var row := _row(card)
		var text := _box(row)
		text.add_theme_constant_override("separation", 3)
		_heading(text, str(option.label) if modern else str(copy.options[index].label))
		var cost := session.event_cost(option)
		var line := _row(text)
		line.add_theme_constant_override("separation", 10)
		for asset in cost:
			var short: bool = float(session.state.public.get(asset, 0)) - float(held.get(asset, 0)) < float(cost[asset])
			var chip := _label(line, "−%s %s" % [TurnReceipt.LABELS.get(asset, asset), _money(cost[asset]) if asset == "money" else "%d" % int(cost[asset])], 18, GameTheme.BAD if short else GameTheme.WARN)
			chip.size_flags_horizontal = SIZE_SHRINK_BEGIN
			chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		var gains: String = RealmRules.option_text(option) if modern else str(copy.options[index].effect)
		if gains != "" and gains != "변화 없음": _label(line, gains, 18, GameTheme.TEXT)
		elif cost.is_empty() and not option.has("chance") and not option.has("relic_offer") and not option.has("followup"): _label(line, "피해 없음" if tone == "negative" else "변화 없음", 18, GameTheme.MUTED)
		var bond := PeopleRules.stance_text(session.state, session.content, event, index)
		if bond != "":
			var tie := _label(line, bond, 18, GameTheme.GOOD if PeopleRules.stance(event, index) > 0 else GameTheme.WARN)
			tie.name = "EventBond_%d" % index
			tie.size_flags_horizontal = SIZE_SHRINK_END
			tie.autowrap_mode = TextServer.AUTOWRAP_OFF
		if option.has("followup"):
			var next_event: Dictionary = session.content.events[option.followup.id]
			var due := int(session.state.week) + int(option.followup.delay)
			var delivery := _label(text, "%d주 뒤 (%d주) · %s" % [option.followup.delay, due, next_event.title], 18, GameTheme.TEAL)
			delivery.name = "EventFollowup_%d" % index
		if option.has("relic_offer"): _label(text,"성물 3개 제안 → 1개 선택",19,GameTheme.TEAL)
		if option.has("chance"):
			var odds := RealmRules.chance_of(session.state, option)
			var gamble := _row(text)
			var percent := _label(gamble, "성공 확률 %d%%" % int(round(odds * 100)), 18, GameTheme.GOOD if odds >= 0.6 else GameTheme.WARN if odds >= 0.4 else GameTheme.BAD)
			percent.size_flags_horizontal = SIZE_SHRINK_BEGIN
			percent.autowrap_mode = TextServer.AUTOWRAP_OFF
			_bar(gamble, odds)
			var win := RealmRules.changes_text(_flat(option.chance.win.get("effects", {})))
			var lose := RealmRules.changes_text(_flat(option.chance.lose.get("effects", {})))
			_label(text, "성공 · %s\n실패 · %s" % [win if win != "" else "피해 없음", lose if lose != "" else "변화 없음"], 18, GameTheme.MUTED)
		var error := session.option_error(option)
		if error != "": _label(text, _plain(error), 18, GameTheme.BAD)
		elif not option.get("requires", {}).is_empty():
			var requirement := _label(text, "활용 · " + RealmRules.option_requirements_text(session.content, option), 18, GameTheme.GOOD)
			requirement.name = "EventRequirement_%d" % index
		var decide := _button(row, "결정", func(): _resolve(index), error != "", "event_option_%d" % index)
		decide.custom_minimum_size.x = 96
		if error == "": _primary(decide)


func _flat(effects: Dictionary) -> Dictionary:
	var out := {}
	for key in effects:
		if key == "perm":
			for item in effects.perm: out["perm:" + str(item)] = effects.perm[item]
		elif key != "flag": out[key] = effects[key]
	return out


func _resolve(index: int) -> void:
	var error := session.choose_event(index)
	if error != "":
		_message(_plain(error))
		return
	receipt.clear()
	outcome_open = _realm() and not session.state.realm.outcome.is_empty() and int(session.state.realm.outcome.week) == int(session.state.week)
	page = "estate"
	_changed("결정을 적용했습니다.")


func _open_turn_report() -> void:
	receipt_breakdown = false
	receipt_open = true
	_render()


func _turn_receipt_popup() -> void:
	if receipt_breakdown:
		super._turn_receipt_popup()
		return
	var turn: Dictionary = session.state.get("last_receipt",{})
	if not turn.get("valid",false): return
	_shade(interface,0.75).name = "DecisionBlocker"
	var box := _window("%d주 결산" % turn.week,Vector2(minf(960,size.x-80),minf(600,size.y-64)),false,true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind","receipt")
	var area := _scroll(box)
	area.add_theme_constant_override("separation",12)
	var cards := _row(area)
	for item in turn.resource_rows:
		if item.id not in ["money","food"]: continue
		var card := _card(cards)
		_heading(card,item.label)
		_heading(card,"%+.2f금" % (float(item.delta)/100.0) if item.id == "money" else "%+.1f" % item.delta,true,GameTheme.GOOD if item.delta >= 0 else GameTheme.WARN)
		_label(card,(_money(item.before)+" → "+_money(item.after)) if item.id == "money" else "%.1f → %.1f" % [item.before,item.after],20)
		if item.id == "money":
			_label(card,"수입 %s · 지출 %s" % [_money(item.income),_money(item.expense)],18,GameTheme.MUTED)
		else:
			_label(card,"생산 +%.1f · 소비 −%.1f" % [item.production,item.consumption],18,GameTheme.MUTED)
			_label(card,"보관 손실 −%.1f · 종자 −%.1f" % [item.spoilage,item.seeds],17,GameTheme.MUTED)
	var materials := _row(area)
	for item in turn.resource_rows:
		if item.id not in ["wood","stone","tools","fuel"]: continue
		var words := _box(materials)
		_label(words,str(item.label),17,GameTheme.MUTED)
		_label(words,"%+.0f · 보유 %.0f" % [item.delta,item.after],20,GameTheme.GOOD if item.delta > 0 else GameTheme.TEXT)
	_rule(area)
	var feedback := RealmFeedback.weekly(session.state,session.content)
	for item in feedback.completed:
		var line := _row(area)
		_lot_art(line,item.id,48)
		_heading(line,"완공 · %s ×%d" % [item.name,item.count],false,GameTheme.GOOD)
	if feedback.completed.is_empty():
		_label(area,"공사 %d 작업 완료 · %d 작업 남음" % [turn.development.work_done,turn.development.remaining_work],20)
	if not feedback.unlocked.is_empty():
		var names: Array[String] = []
		for item in feedback.unlocked: names.append(item.name)
		_label(area,"새로 건설 가능 · "+" / ".join(names),20,GameTheme.TEAL)
	if feedback.promoted: _heading(area,feedback.rank_name+" 승격",false,GameTheme.GOOD)
	RelicScreens.triggers(self,area)
	var actions := _row(box)
	_button(actions,"전체 수입·지출",func(): receipt_breakdown = true; _render(),false,"ReceiptBreakdown")
	_primary(_button(actions,"결과 확인 · 운영으로",_close_turn_details,false,"CloseTurnDetails"))


func _outcome_popup() -> void:
	var outcome: Dictionary = session.state.realm.outcome
	_shade(interface, 0.72).name = "DecisionBlocker"
	var box := _window("결정의 결과", Vector2(minf(900, size.x - 80), minf(570, size.y - 80)), false, true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind", "outcome")
	var event: Dictionary = RealmRules.event_definition(session.state,session.content,outcome.event)
	var row := _row(box)
	row.add_theme_constant_override("separation", 18)
	_face(row, event.get("portrait", "CH01"), 110)
	var words := _box(row)
	_heading(words, str(outcome.title), true)
	_label(words, "선택 · " + str(outcome.choice), 20, GameTheme.MUTED)
	if outcome.rolled:
		var verdict := _heading(words, ("성공!" if outcome.win else "실패…") + "  (확률 %d%%)" % int(round(float(outcome.chance) * 100)), false, GameTheme.GOOD if outcome.win else GameTheme.BAD)
		verdict.name = "OutcomeVerdict"
		if str(outcome.text) != "": _label(words, str(outcome.text), 20)
	var area := _scroll(box)
	var lines := RealmFeedback.outcome_lines(session.state,session.content)
	if lines.is_empty(): _label(area,"자원과 영지 수치의 변화가 없습니다.",20,GameTheme.MUTED)
	for item in lines:
		var result := _row(area)
		_label(result,item.label,20)
		if item.measured:
			_label(result,item.before_text+" → "+item.after_text,20)
			var delta := _label(result,item.net_text,22,GameTheme.GOOD if item.favorable > 0 else GameTheme.BAD if item.favorable < 0 else GameTheme.MUTED)
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if item.cost > 0: _label(area,"지불 "+item.cost_text+(" · 효과 "+item.effect_text if item.effect_text != "" else ""),17,GameTheme.MUTED)
		else: _label(result,item.effect_text,20,GameTheme.MUTED)
		_rule(area)
	if outcome.has("followup"):
		var next_event: Dictionary = session.content.events.get(outcome.followup.id, {})
		var followup := _label(box, "%d주 예정 · %s" % [outcome.followup.week, next_event.get("title", "후속 보고")], 20, GameTheme.TEAL)
		followup.name = "OutcomeFollowup"
	var relic_pending: bool = VillageRelics.enabled(session.state) and not session.state.realm.sanctuary.offer.is_empty()
	if relic_pending: _label(box,"성물 제안을 확보했습니다. 세 개 중 하나를 선택하세요.",20,GameTheme.TEAL)
	_primary(_button(box, "성물 고르기" if relic_pending else "확인", func(): outcome_open = false; _render(), false, "AcknowledgeOutcome"))
	_focus_decision.call_deferred()


## ---------- 진행 ----------

func _advance(count: int) -> void:
	if busy: return
	var marker: int = session.state.ledger.size()
	var before := _snapshot()
	var week := int(session.state.week)
	await super._advance(count)
	if int(session.state.week) == week: return
	hud_before = before
	selected_lot = ""
	side_page = "overview"
	page = "estate" if session.state.status == "active" else "result"
	_render()
	_spawn_pops(session.state.ledger.slice(mini(marker, session.state.ledger.size())))
	if is_instance_valid(realm_board):
		for item in RealmFeedback.weekly(session.state,session.content).completed: realm_board.flash_lot(item.id)


## 지난주 원장을 시설 위의 수치로 띄운다. 무엇이 어디서 났는지 지도에서 바로 보인다.
func _spawn_pops(entries: Array) -> void:
	if not is_instance_valid(realm_board) or not realm_board.is_inside_tree() or page != "build": return
	var sums := {}
	for entry in entries:
		var source := str(entry.get("src", ""))
		if not POP_LOTS.has(source) or float(entry.get("qty", 0)) <= 0: continue
		var key := "%s|%s" % [POP_LOTS[source], entry.asset]
		sums[key] = float(sums.get(key, 0.0)) + float(entry.qty)
	var order := 0
	for key in sums:
		var parts: PackedStringArray = str(key).split("|")
		var amount: float = sums[key]
		var text := "+%.1f금" % (amount / 100.0) if parts[1] == "money" else "+%d %s" % [int(round(amount)), TurnReceipt.LABELS.get(parts[1], parts[1])]
		realm_board.pop(parts[0], text, true, order * 0.12)
		order += 1
	var eaten := 0.0
	for entry in entries:
		if entry.get("src", "") == "consume": eaten -= float(entry.qty)
	if eaten > 0: realm_board.pop("B01", "−%d 식량" % int(round(eaten)), false, order * 0.12)


## ---------- 결산과 도움말 ----------

func _run_results() -> void:
	var result: Dictionary = session.state.result
	if not result.has("grade"):
		super._run_results()
		return
	var box := _plate(Rect2(44, 36, size.x - 88, size.y - 72), false, 24)
	box.name = "RunResults"
	var header := _row(box)
	_heading(header, "통치 결산", true)
	_button(header, "메뉴", func(): _go("menu"))
	var body := _row(box)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 26)
	var stamp := _card(body)
	stamp.name = "GradeStamp"
	stamp.get_parent().size_flags_stretch_ratio = 0.7
	var letter := _heading(stamp, str(result.grade), true, GameTheme.GOOD if result.success else GameTheme.WARN)
	letter.add_theme_font_override("font", PixelTheme.font(true))
	letter.add_theme_font_size_override("font_size", 96)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _heading(stamp, str(result.grade_title))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(stamp, "%d주 · %s\n주민 %d명 · 식량 %.1f주분" % [result.week, result.reason, session.state.pop, WeekSim.food_weeks(session.state)], 20).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spacer(stamp)
	_heading(stamp, "공훈 +%d" % result.points, true, GameTheme.TEAL).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SeasonSupportScreens.result(self,stamp)
	var detail := _window_scroll(body)
	detail.get_parent().size_flags_stretch_ratio = 1.6
	_heading(detail, "연말 목표")
	for goal in session.state.goals.values():
		_label(detail, ("✓ " if goal.done else "✗ ") + "%s · %s" % [goal.detail, goal.status], 20, GameTheme.GOOD if goal.done else GameTheme.BAD)
	if result.has("trial_passed"):
		_label(detail, ("✓ " if result.trial_passed else "✗ ") + "겨울 시련 · " + str(session.content.chronicle.trials[session.state.trial].name), 20, GameTheme.GOOD if result.trial_passed else GameTheme.BAD)
	_rule(detail)
	_heading(detail, "영지의 성장  +%d" % result.get("realm_points", 0))
	for line in result.get("realm_lines", []):
		_label(detail, "%s  +%d" % [line.text, line.points], 20, GameTheme.TEXT if int(line.points) > 0 else GameTheme.MUTED)
	if VillageRelics.enabled(session.state):
		_rule(detail)
		_heading(detail,"이번 통치의 성물")
		for item in VillageRelics.overview(session.state,session.content).equipped:
			var relic_line := _row(detail)
			RelicScreens.image(self,relic_line,item.icon,48).size_flags_horizontal = SIZE_SHRINK_BEGIN
			_label(relic_line,item.name+" · "+item.text,19)
		_label(detail,"성물의 발견 기록은 다음 통치에도 남습니다.",18,GameTheme.MUTED)
	RelicScreens.environments(self,detail)
	RelicScreens.builds_results(self,detail)
	FantasyFrontierScreens.results(self,detail)
	CrisisScreens.results(self,detail)
	_rule(detail)
	_heading(detail, "공훈 내역")
	_label(detail, "기본 목표 %d · 계절 생존 %d · 겨울 시련 %d · 계절 목표 %d\n완주 %d · 첫 기록 %d · 영지의 성장 %d" % [result.objective_points, result.get("season_points", 0), result.get("trial_points", 0), result.get("campaign_points", 0), result.completion_points, result.first_points, result.get("realm_points", 0)], 20)
	var actions := _row(box)
	_primary(_button(actions, "가문 강화로 다음 통치 준비", func(): _go("archive"), false, "ResultArchive"))
	_button(actions, "새 통치 준비", _open_prepare, false, "ResultRestart")


func _help_popup() -> void:
	_shade(interface, 0.7)
	var box := _window("플레이 안내", Vector2(minf(960, size.x - 80), minf(600, size.y - 60)), false, true)
	current_modal = box.get_parent()
	var area := _scroll(box)
	for entry in [
		["한 주의 흐름", "집무실에서 방침을 정하고, 영지 둘러보기에서 터를 골라 건설을 승인합니다. ‘1주 진행’ 뒤 집무실에서 실제 결과를 확인하세요."],
		["사람과 일손", "농사가 먼저 일손을 가져가고, 작업반 20명이 공사·벌목·채석을 합니다. 남는 주민은 스스로 채집터·채소밭·어장에서 일합니다. 파종(3~6주)과 수확(33~36주)에는 일손이 모자랍니다."],
		["세 가지 수치", "민심은 일의 능률과 이탈, 건강은 일할 사람 수, 치안은 습격을 막을 확률입니다. 숫자에 마우스를 올리면 기준이 보입니다."],
		["사건과 습격", "2주에 한 번쯤 결정을 요구하는 일이 생깁니다. 시설과 포고가 있으면 더 좋은 선택지가 열립니다. 변경의 위협이 쌓이면 도적과 늑대가 옵니다."],
		["성장", "빈집을 마련하고 민심·식량 비축을 관리하면 9·22·35주에 이주민이 찾아옵니다. 주민 100명과 곳간을 갖추면 촌락으로 승격합니다."],
		["성물 세트", "유적·행상·순례 사건과 첫 촌락 승격에서 성물을 얻습니다. 성소에 3개까지 장착하고 같은 계열 2개로 성물 세트 효과를 냅니다. 발동형 성물은 실제 운영 조건을 채운 주에 보상합니다. 발견 도감은 다음 통치에도 남습니다."],
		["위기 대비", "집무실의 ‘위기 대비’에서 필요한 시설·비축량·마감 주를 확인합니다. 12종 중 네 위기가 회차마다 선정되고, 마감 4~6주 전에 예고합니다. 성공 보상과 미달 피해는 미리 공개됩니다."],
		["운영 부담", "14·27·40주에 물자값·급여·유지비·위협 증가량이 한 단계씩 높아집니다. 같은 단계가 매주 중첩되지는 않습니다. 다음 상승은 3주 전에 소식으로 안내합니다."],
		["목표 수치", "효과에 표시된 민심·건강·치안 목표 +N은 즉시 회복량이 아닙니다. 매주 상태가 향하는 기준을 높입니다."],
		["끝과 다음", "52주에 농지 6구획·곳간·식량 13주분과 겨울 시련을 모두 지키면 성공입니다. 성과는 등급과 공훈으로 남아 다음 통치를 돕습니다."]]:
		_heading(area, entry[0])
		_label(area, entry[1], 19)
	_label(area, "Space 1주 진행 · F 결정 열기 · B 건설 · Esc 닫기", 18, GameTheme.MUTED)
	var lesson := Onboarding.current(session.state)
	var row := _row(box)
	if _is_active() and lesson.skipped and not lesson.completed:
		_primary(_button(row, "멈춘 단계부터 따라하기", func(): _begin_tutorial(), false, "ContinueTutorial"))
	_button(row, "실제 조작으로 다시 배우기" if _is_active() else "튜토리얼로 새 통치 준비", func(): _begin_tutorial(true), false, "StartTutorial")
	_primary(_button(row, "닫기", func(): help_open = false; _render(), false, "CloseHelp"))


func _input(event: InputEvent) -> void:
	if _handle_quit_input(event): return
	if event is InputEventKey and event.pressed and not event.echo and not quit_prompt_open:
		var shown: String = str(current_modal.get_meta("kind", "")) if is_instance_valid(current_modal) else ""
		if shown == "relic_acquired" and event.keycode == KEY_ESCAPE:
			relic_reward = ""
			_render()
			get_viewport().set_input_as_handled()
			return
		if shown == "news" and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
			_render()
			get_viewport().set_input_as_handled()
			return
		if shown == "outcome" and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
			outcome_open = false
			_render()
			get_viewport().set_input_as_handled()
			return
		if not is_instance_valid(current_modal) and page == "fantasy_frontier":
			if event.keycode == KEY_ESCAPE:
				_go("estate")
				get_viewport().set_input_as_handled()
			return
		if not is_instance_valid(current_modal) and page == "season_support" and event.keycode == KEY_ESCAPE:
			_go("estate")
			get_viewport().set_input_as_handled()
			return
		if not is_instance_valid(current_modal) and page in ["estate","build"] and _is_active():
			if event.keycode == KEY_ESCAPE and selected_lot != "":
				selected_lot = ""
				_render()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_B:
				_go("build")
				get_viewport().set_input_as_handled()
				return
	super._input(event)

