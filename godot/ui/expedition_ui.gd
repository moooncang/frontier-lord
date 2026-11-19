extends "res://ui/cabinet_ui.gd"
## 부임 준비, 영구 성장, 계절 운영을 독립 화면으로 연결한다.

var selected_talent := "LF01"
var setup_relic := "seeds"
var campaign_board: EstateBoard
var show_season_result := false
var receipt_open := false
var seen_season_count := 0
var guide_enabled := true
var management_open := false
var tutorial_layer: Control
var boon_family_filter := ""
var boon_catalog := false
var boon_scroll_positions := {}
var house_branch := "finance"
var house_scroll_positions := {}
var house_setup_tab := "doctrines"
var selected_house_option := ""
var house_return := "archive"
var draft_difficulty := 0
const CREAM := Color("f3e6c9")
const DARK := Color("202c30")
const GOLD := Color("d7b367")

func _render() -> void:
	if session == null: return
	if is_instance_valid(interface):
		var house_list := interface.find_child("HouseListScroll",true,false) as ScrollContainer
		if house_list != null: house_scroll_positions[str(house_list.get_meta("scroll_key",""))] = house_list.scroll_vertical
		var list := interface.find_child("PerkListScroll",true,false) as ScrollContainer
		if list != null: boon_scroll_positions[str(list.get_meta("scroll_key",""))] = list.scroll_vertical
	Onboarding.sync(session.state)
	LegacyPath.ensure(session.profile)
	if is_instance_valid(main_scroll): scroll_positions[rendered_page] = main_scroll.scroll_vertical
	main_scroll = null
	current_modal = null
	if is_instance_valid(board): board.visible = false
	if is_instance_valid(shell):
		remove_child(shell)
		shell.queue_free()
	theme = RealmTheme.create(assets.body_font())
	texture_filter = TEXTURE_FILTER_NEAREST
	paper_ready = true
	pixel_ready = true
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shell.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(shell)
	interface = Control.new()
	interface.name = "ExpeditionInterface"
	interface.mouse_filter = MOUSE_FILTER_IGNORE
	shell.add_child(interface)
	var bg := TextureRect.new()
	bg.texture = assets.texture("hub_manor")
	if bg.texture == null: bg.texture = assets.texture("title_frontier")
	if bg.texture == null: bg.texture = assets.texture("study")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	interface.add_child(bg)
	if page not in ["menu","estate"]: _shade(interface, .68).mouse_filter = MOUSE_FILTER_IGNORE
	elif page == "estate": _shade(interface, .16).mouse_filter = MOUSE_FILTER_IGNORE
	brief = WeeklyBrief.build(session.state, session.content) if not session.state.is_empty() else {}
	forecast = WeekSim.forecast(session.state, session.content) if _is_active() else {}
	match page:
		"menu": _title_hub()
		"prepare": _expedition_setup()
		"archive": _talent_board()
		"legacy_setup": HouseScreens.preparation_page(self)
		"frontier_setup": SeasonSupportScreens.difficulty_page(self)
		"catalog": _catalog_screen()
		"result": _run_results()
		_: _campaign_screen()
	if help_open: _help_popup()
	elif receipt_open and not is_instance_valid(current_modal): _turn_receipt_popup()
	elif management_open and not is_instance_valid(current_modal): _management_menu()
	if _is_active() and page in ["estate","build"] and not help_open and not receipt_open and not management_open:
		_tutorial_overlay.call_deferred(interface)
	rendered_page = page
	_restore_scroll.call_deferred(page, int(scroll_positions.get(page, 0)))

func _plate(rect: Rect2, dark: bool = false, inset: int = 18) -> VBoxContainer:
	var box := _paper(rect, inset, DARK if dark else CREAM)
	box.get_parent().add_theme_stylebox_override("panel", _sprite_style("ui_frame_slate" if dark else "ui_frame_paper",DARK if dark else CREAM,inset))
	box.add_theme_constant_override("separation", 10)
	return box

func _sprite_style(key: String, fill: Color, inset: int) -> StyleBox:
	return RealmTheme.surface(fill,inset)

func _card(parent: Node, title: String = "") -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel",_sprite_style("ui_frame_paper",CREAM,16))
	parent.add_child(frame)
	var box := _box(frame)
	box.add_theme_constant_override("separation",8)
	if title != "": _heading(box,title)
	return box

func _spacer(parent: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _art(parent: Node, key: String, dimensions: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = assets.texture(key)
	art.custom_minimum_size = dimensions
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art

func _window(title: String, dimensions: Vector2, closable: bool = true, modal: bool = false) -> VBoxContainer:
	var box := _plate(Rect2((size-dimensions)*.5,dimensions),false,24)
	box.get_parent().name = "DecisionModal" if modal else "ManagementWindow"
	if title != "":
		var row := _row(box)
		_heading(row,title)
		if closable: _button(row,"닫기",func(): _go("estate"),false,"CloseWindow")
		_rule(box)
	return box

func _title_hub() -> void:
	var box := _plate(Rect2(48,40,430,size.y-80),true,24)
	box.get_parent().name = "TitleHub"
	_label(box,"영주관",20,TycoonTheme.NAV_TEXT)
	var title := _label(box,"변경의 신임\n영주가 되었다",36,TycoonTheme.NAV_TEXT)
	title.add_theme_font_override("font",PixelTheme.heading_font())
	_label(box,"다음 통치를 준비하는 곳",18,TycoonTheme.NAV_TEXT)
	_spacer(box)
	if _is_active():
		_label(box,"진행 중 · %d회차 %d주\n주민 %d명 · 식량 %.1f주분" % [session.profile.runs,session.state.week,session.state.pop,WeekSim.food_weeks(session.state)],19,TycoonTheme.NAV_TEXT)
		_primary(_button(box,"집무실로 · 통치 이어 하기",_continue,load_blocked,"ContinueRun"))
		_button(box,"이번 통치 끝내기",_ask_retire,load_blocked,"EndRun").tooltip_text = "지금까지의 성과로 결산하고 통치를 마칩니다. 되돌릴 수 없습니다."
	else:
		_primary(_button(box,"새 영지에 부임",_open_prepare,load_blocked,"NewRun"))
	_button(box,"가문 강화 · 공훈 %d" % session.profile.points,func(): _go("archive"),false,"OpenArchive")
	_button(box,"발견과 통치 기록",func(): _go("catalog"),false,"OpenCodex")
	var row := _row(box)
	_button(row,"플레이 안내",_help,false,"OpenHelp").size_flags_horizontal = SIZE_EXPAND_FILL
	_button(row,"종료",_quit_game,false,"QuitGame")
	if load_blocked: _label(box,notice,18,TycoonTheme.NAV_TEXT)
	var plaque := _plate(Rect2(size.x-380,size.y-132,332,84),true,12)
	_label(plaque,"52주 · 네 계절의 통치",22,TycoonTheme.NAV_TEXT)
	_label(plaque,"개발하고 비축해 겨울을 넘기세요",18,TycoonTheme.NAV_TEXT)

func _open_prepare() -> void:
	if _is_active() or load_blocked: return
	draft_seed = int(Time.get_unix_time_from_system()) & 0x7fffffff
	draft_candidate = 0
	draft_region = "forest"
	draft_relics = ["seeds", "axe"]
	prepare_step = 0
	guide_enabled = not session.profile.get("onboarding_complete",false)
	page = "prepare"
	_render()

func _start() -> void:
	if _is_active() or load_blocked: return
	var budget := LegacyPath.equipment_budget(session.profile)
	if _relic_cost() > budget: return
	session.start_run(draft_seed, "settler", _run_config())
	page = "estate"
	seen_season_count = 0
	development_result.clear()
	last_turn.clear()
	receipt.clear()
	scroll_positions.clear()
	_changed("첫 특전을 고른 뒤 농지를 개발하세요.")

func _run_config() -> Dictionary:
	return {"region":draft_region,"candidate":draft_candidate,"relics":draft_relics,"tutorial":false,"cabinet":true,"campaign":true,"workcrew":true,"onboarding":guide_enabled,"difficulty":draft_difficulty,"seasonal_support":true}

func _coach_rect(step: int) -> Rect2:
	return Rect2(48,190,minf(500,size.x*.42),252) if step == 5 else Rect2(size.x-432,190,380,252)

func _expedition_setup() -> void:
	var outer := _plate(Rect2(40, 28, size.x - 80, size.y - 56), false, 22)
	outer.name = "ExpeditionSetup"
	var heading := _row(outer)
	_heading(heading, "새 통치 준비", true)
	_button(heading, "메뉴", func(): _go("menu"), false, "SetupCancel")
	var steps := _row(outer)
	for i in 3:
		var pick := _button(steps, ["1  영주", "2  영지", "3  부임 물자"][i], func(): prepare_step = i; _render(), false, "SetupStep%d" % i)
		pick.size_flags_horizontal = SIZE_EXPAND_FILL
		if prepare_step == i: _primary(pick)
	var area := _row(outer)
	area.size_flags_vertical = SIZE_EXPAND_FILL
	area.add_theme_constant_override("separation", 22)
	var choices := _box(area, 1.7)
	choices.name = "SetupChoices"
	var detail := _card(area)
	detail.get_parent().size_flags_stretch_ratio = 1.0
	detail.get_parent().custom_minimum_size.x = 340
	detail.name = "SetupDetail"
	var data: Dictionary = session.content.chronicle
	var candidates := ChronicleRules.candidates(data, draft_seed)
	var selected: Dictionary = candidates[draft_candidate]
	match prepare_step:
		0:
			_label(choices, "영주마다 장점 둘, 단점 하나가 있습니다.", 20)
			var cards := _row(choices)
			cards.size_flags_vertical = SIZE_EXPAND_FILL
			for i in 3:
				var candidate: Dictionary = candidates[i]
				var card := _card(cards)
				# 초상이 카드의 남는 높이를 채운다.
				_art(card, "lord_" + candidate.origin, Vector2(96, 160)).size_flags_vertical = SIZE_EXPAND_FILL
				_heading(card, session.content.progression.origins[candidate.origin].name)
				# 고르기 전에 비교할 수 있게 장점과 약점을 카드에 바로 적는다.
				for id in candidate.traits:
					var t: Dictionary = data.traits[id]
					var mark := _label(card, ("－ " if t.get("flaw",false) else "＋ ") + str(t.name) + ("" if size.y < 860 else " · " + str(t.description)), 18, GameTheme.WARN if t.get("flaw",false) else GameTheme.GOOD)
					mark.autowrap_mode = TextServer.AUTOWRAP_OFF
					mark.clip_text = true
					mark.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					mark.tooltip_text = "%s · %s" % [t.name, t.description]
				var pick := _button(card, "선택됨" if i == draft_candidate else "선택", func(): draft_candidate = i; _render(), false, "candidate_%d" % i)
				if i == draft_candidate: _primary(pick)
			_heading(detail, session.content.progression.origins[selected.origin].name, true)
			_label(detail, session.content.progression.origins[selected.origin].description, 19)
			_rule(detail)
			for id in selected.traits:
				var t: Dictionary = data.traits[id]
				_label(detail, ("약점 · " if t.get("flaw",false) else "장점 · ") + t.name, 20, GameTheme.WARN if t.get("flaw",false) else GameTheme.GOOD)
				_label(detail, t.description, 19)
		1:
			_label(choices, "지역의 이점과 올해의 겨울 시련을 확인하세요.", 20)
			for id in data.regions:
				var region: Dictionary = data.regions[id]
				var card := _card(choices)
				# 세 카드가 남는 높이를 나눠 갖고, 지역 효과를 카드에서 바로 비교한다.
				card.get_parent().size_flags_vertical = SIZE_EXPAND_FILL
				var row := _row(card)
				row.size_flags_vertical = SIZE_EXPAND_FILL
				_art(row, "building_" + {"forest":"logging","river":"market","highland":"quarry"}[id], Vector2(72, 64) if size.y < 860 else Vector2(112, 104))
				var words := _box(row)
				words.alignment = BoxContainer.ALIGNMENT_CENTER
				_heading(words, region.name)
				_label(words, region.subtitle, 18, GameTheme.MUTED)
				var regional: bool = bool(_run_config().get("regional", false))
				var perks := _label(row, str(CampaignDirector.region_view(session.content, id).description) if regional else str(region.description), 18, GameTheme.GOOD)
				perks.size_flags_stretch_ratio = 1.4
				perks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				var pick := _button(row, "선택됨" if draft_region == id else "선택", func(): draft_region = id; _render(), false, "region_" + id)
				pick.size_flags_vertical = SIZE_SHRINK_CENTER
				if draft_region == id: _primary(pick)
			var reading := _scroll(detail)
			reading.name = "RegionDetailText"
			_heading(reading, data.regions[draft_region].name, true)
			if bool(_run_config().get("regional", false)):
				var local: Dictionary = CampaignDirector.region_view(session.content, draft_region)
				_label(reading, str(local.description), 21)
				_label(reading, str(local.hint), 19, GameTheme.MUTED).name = "RegionHint"
				_label(reading, "계절 목표\n" + "\n".join(local.goals), 19, GameTheme.GOOD).name = "RegionGoals"
			else:
				_label(reading, data.regions[draft_region].description, 21)
			_rule(reading)
			var trial: Dictionary = data.trials[ChronicleRules.trial_for(data, draft_seed)]
			_heading(reading, "겨울 시련 · " + trial.name)
			_label(reading, trial.description, 19, GameTheme.WARN)
			_setup_environment(reading)
			SeasonSupportScreens.prepare(self,detail)
			_button(detail, "부임 조건 새로고침", func(): draft_seed = (draft_seed * 1664525 + 1013904223) & 0x7fffffff; _render(), false, "RerollWorld")
		2:
			var budget := LegacyPath.equipment_budget(session.profile)
			_heading(choices, "물자 예산  %d / %d" % [_relic_cost(), budget])
			var grid := GridContainer.new()
			grid.columns = 2
			grid.size_flags_vertical = SIZE_EXPAND_FILL
			choices.add_child(grid)
			for id in data.relics:
				var relic: Dictionary = data.relics[id]
				var chosen: bool = id in draft_relics
				var button := _button(grid, ("✓ " if chosen else "") + relic.name + "   %d점\n" % relic.cost + relic.description, func():
					if id in draft_relics: draft_relics.erase(id)
					else: draft_relics.append(id)
					_render(), not chosen and _relic_cost() + int(relic.cost) > budget, "relic_" + id)
				button.size_flags_horizontal = SIZE_EXPAND_FILL
				button.size_flags_vertical = SIZE_EXPAND_FILL
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				if chosen: _primary(button)
			_heading(detail, "부임 확인", false)
			_label(detail, session.content.progression.origins[selected.origin].name + " · " + data.regions[draft_region].name, 20)
			_rule(detail)
			_label(detail, "52주 통치 · 첫 목표는 13주까지 " + (str(CampaignDirector.phases({"region":draft_region, "campaign":{"regional":true}}, session.content)[0].title) if bool(_run_config().get("regional", false)) else "농지 6구획"), 19)
			HouseScreens.setup_summary(self,detail)
			_setup_pressure(detail)
			detail.tooltip_text = session.content.campaign.condition
			var guide := CheckButton.new()
			guide.name = "EnableTutorial"
			guide.text = "실제 조작 튜토리얼"
			guide.button_pressed = guide_enabled
			guide.toggled.connect(func(on): guide_enabled = on)
			detail.add_child(guide)
	var footer := _row(outer)
	_label(footer, "%s · %s" % [session.content.progression.origins[selected.origin].name, data.regions[draft_region].name], 18, GameTheme.MUTED)
	if prepare_step > 0: _button(footer, "이전", func(): prepare_step -= 1; _render(), false, "PrepareBack")
	if prepare_step < 2: _primary(_button(footer, "다음  →", func(): prepare_step += 1; _render(), false, "PrepareNext"))
	else: _primary(_button(footer, "통치 시작  →", _start, load_blocked, "StartRun"))

func _setup_environment(_parent: Node) -> void:
	pass

func _setup_pressure(_parent: Node) -> void:
	pass

func _talent_ranks() -> int:
	var total := 0
	for rank in session.profile.get("legacy_talents",{}).values(): total += int(rank)
	return total

func _talent_board() -> void:
	HouseScreens.page(self)

func _restore_house_scroll(scroll: ScrollContainer, position_value: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll) and scroll.is_inside_tree(): scroll.scroll_vertical = position_value

func _open_house_preparation(return_page: String) -> void:
	house_return = return_page
	_go("legacy_setup")

func _open_house_talent(id: String) -> void:
	selected_talent = id
	house_branch = str(LegacyPath.definitions().talents[id].branch)
	_go("archive")

func _select_house_doctrine(id: String, replace_id: String = "") -> void:
	var error := session.set_legacy_doctrine(id,replace_id)
	if error != "": _message(error); return
	_changed("다음 부임의 가문 방침을 선택했습니다.")

func _remove_house_doctrine(id: String) -> void:
	var error := session.remove_legacy_doctrine(id)
	if error != "": _message(error); return
	_changed("가문 방침 선택을 해제했습니다.")

func _set_house_preparation(key: String, value: String) -> void:
	var error := session.set_legacy_preparation(key,value)
	if error != "": _message(error); return
	_changed("다음 부임에 사용할 선택을 저장했습니다.")

func _buy_talent() -> void:
	var error := session.buy_talent(selected_talent)
	_changed(error if error != "" else "가문 특성을 강화했습니다.")

func _refund_talents() -> void:
	var refunded := session.refund_talents()
	_changed("%d 공훈을 돌려받았습니다." % refunded)

func _talent_effect(talent: Dictionary, rank: int) -> String:
	var parts: Array[String] = []
	for key in talent.resources:
		var value: float = float(talent.resources[key])*rank
		parts.append(("금고 " + _money(value)) if key == "money" else "%s +%d" % [RESOURCES.get(key,key),value])
	for key in talent.bonuses:
		var names := {"maintenance":"유지비","buy":"구매가","gather":"채집","harvest":"수확","heating":"장작 소모","storage":"저장량","wages":"공공 급여"}
		parts.append("%s %+.0f%%" % [names.get(key,key),float(talent.bonuses[key])*rank*100])
	return " · ".join(parts)

func _catalog_screen() -> void:
	var box := _plate(Rect2(40,28,size.x-80,size.y-56))
	var row := _row(box)
	_heading(row,"발견과 통치 기록",true)
	_button(row,"가문 강화",func(): _go("archive"))
	_button(row,"메뉴",func(): _go("menu"))
	_archive(_window_scroll(box))

func _campaign_screen() -> void:
	if session.state.is_empty():
		page = "menu"
		_title_hub()
		return
	_campaign_hud()
	_season_track()
	if page == "estate":
		_estate_playfield()
	elif page == "world": _world_overview()
	else:
		var box := _plate(Rect2(28,170,size.x-56,size.y-264),false,16)
		var row := _row(box)
		_heading(row, {"build":"영지 개발", "trade":"물자 주문", "people":"보좌관 임명", "boons":"이번 회차의 특전", "ledger":"상세 장부", "journey":"계절 목표와 시련"}.get(page,"영지 관리"),true)
		_button(row,"영지로 돌아가기",func(): _go("estate"),false,"BackEstate")
		match page:
			"build": _development(box)
			"trade": _reading_market(box)
			"people": _people(box)
			"boons": _boons(box)
			"ledger": _accounts(_window_scroll(box))
			"journey": _journey(_window_scroll(box))
	_run_dock()
	if _is_active():
		var key := _decision_identity()
		if key != decision_key:
			decision_hidden = false
			decision_key = key
		if _pending() and not decision_hidden: _decision_popup()
		elif show_season_result: _season_result_popup()

func _campaign_hud() -> void:
	var box := _plate(Rect2(28,16,size.x-56,84),true,10)
	box.name = "CampaignHUD"
	var row := _row(box)
	row.add_theme_constant_override("separation",20)
	var s := session.state
	var week := mini(52,int(s.week))
	var date := _box(row)
	date.add_theme_constant_override("separation",0)
	_label(date,["봄","여름","가을","겨울"][mini(3,int((week-1)/13))] + " · %d회차" % session.profile.runs,18,TycoonTheme.NAV_TEXT)
	_label(date,"%d / 52주" % week,28,TycoonTheme.NAV_TEXT)
	var food_stock := WeekSim.food_weeks(s)
	var health_alert: bool = float(s.health) < 50
	for item in [["금고",_money(s.public.money),float(s.public.money) < 1000],["식량 비축" if food_stock >= 4 else "식량 · 부족","%.1f주" % food_stock,food_stock < 4],["장작","%d개" % s.public.fuel,week >= 27 and float(s.public.fuel) < float(s.pop)*.1*maxi(1,53-maxi(40,week))],["건강 · 위험" if health_alert else "민심","%d / 100" % (s.health if health_alert else s.mood),health_alert or float(s.mood) < 35]]:
		var tile := _box(row)
		tile.add_theme_constant_override("separation",0)
		_label(tile,item[0],18,TycoonTheme.NAV_TEXT)
		var number := _label(tile,item[1],28,Color("f4b486") if item[2] else TycoonTheme.NAV_TEXT)
		number.add_theme_font_override("font",PixelTheme.heading_font())
		tile.tooltip_text = "주민 %d명 · 민심 %d · 건강 %d" % [s.pop,s.mood,s.health]
	_button(row,"도움말",_help,false,"RunHelp")
	_button(row,"메뉴",func(): _go("menu"),false,"nav_menu")

func _season_track() -> void:
	var box := _plate(Rect2(28,110,size.x-56,46),true,8)
	box.name = "SeasonTrack"
	var row := _row(box)
	row.name = "SeasonObjective"
	row.add_theme_constant_override("separation",18)
	var overview := CampaignDirector.overview(session.state,session.content)
	if overview.enabled:
		var short_goal: String = ["농지 확대","곳간 확보","장작 비축","겨울 평가"][overview.index]
		_heading(row,"%s 목표 · %s" % [overview.season,short_goal],false,TycoonTheme.NAV_TEXT)
		_label(row,"%d / %d%s" % [overview.objective.current,overview.objective.target,["구획","개","개","달성"][overview.index]],22,TycoonTheme.NAV_TEXT)
		_label(row,"%d주 남음" % overview.weeks_left,18,TycoonTheme.NAV_TEXT)
		if not overview.timeline.is_empty():
			var moment: Dictionary = overview.timeline[0]
			_label(row,moment.label + (" · 이번 주" if moment.remaining == 0 else " · %d주 뒤" % moment.remaining),18,TycoonTheme.NAV_TEXT)
		box.tooltip_text = "보상 · " + overview.reward_text + "\n미달 · " + overview.penalty_text
	else:
		_label(row,"첫 겨울 평가까지 %d주" % maxi(0,53-int(session.state.week)),21,TycoonTheme.NAV_TEXT)

func _estate_playfield() -> void:
	OperatingDashboard.render(self)

func _world_overview() -> void:
	var frame := Panel.new()
	frame.name = "EstatePlayfield"
	frame.add_theme_stylebox_override("panel",TycoonTheme.panel(DARK,GOLD,0))
	interface.add_child(frame)
	_place(frame,Rect2(28,160,size.x-56,size.y-294))
	campaign_board = EstateBoard.new()
	campaign_board.name = "Settlement"
	campaign_board.compact = true
	campaign_board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	frame.add_child(campaign_board)
	campaign_board.season = mini(3,int((int(session.state.week)-1)/13))
	campaign_board.backdrop = assets.texture("terrain_"+["spring","summer","autumn","winter"][campaign_board.season])
	campaign_board.site_selected.connect(_select_site)
	campaign_board.configure(assets,session.state,_is_active())

func _run_dock() -> void:
	var dock := _plate(Rect2(28,size.y-78,size.x-56,58),true,5)
	dock.name = "RunDock"
	var row := _row(dock)
	if page != "estate": _button(row,"운영으로",func(): _go("estate"),false,"nav_estate")
	for entry in [["build","개발"],["trade","물자"],["boons","특전"]]:
		var button := _button(row,entry[1],func(): _go(entry[0]),false,"nav_"+entry[0])
		button.custom_minimum_size.x = 110
		if page == entry[0]: _primary(button)
	_button(row,"기록 · 관리",func(): management_open = true; _render(),false,"MoreActions")
	_spacer(row)
	var next := _button(row,"결정 먼저 확인" if _pending() else "이 계획으로 1주 진행  →",_open_decision if _pending() else func(): _advance(1),busy or not _is_active(),"NextWeek")
	next.custom_minimum_size.x = 280
	next.tooltip_text = "Space · 선택한 작업 배정으로 한 주를 진행합니다."
	_primary(next)

func _run_results() -> void:
	var box := _plate(Rect2(44,36,size.x-88,size.y-72),false,24)
	box.name = "RunResults"
	var header := _row(box)
	_heading(header,"통치 결산",true)
	_button(header,"메뉴",func(): _go("menu"))
	var detail := _window_scroll(box)
	_result(detail)
	if CampaignDirector.enabled(session.state):
		_label(detail,"계절 목표 추가 보상 · %d 공훈" % session.state.result.get("campaign_points",0),21,GameTheme.GOOD)
		for record in session.state.campaign.records:
			_label(detail,record.message,19)

func _workcrew_panel(parent: Node) -> void:
	var panel := _box(parent)
	panel.name = "PolicyChoices"
	panel.add_theme_constant_override("separation",6)
	_heading(panel,"직영 작업반 배정")
	if not WorkcrewRules.enabled(session.state):
		_label(panel,"기존 회차 · 자동 배치",20,GameTheme.MUTED)
		_label(panel,"시설 개발을 선택하며 운영을 계속할 수 있습니다.",19)
		_button(panel,"다음 개발 선택",func(): _ack_tutorial("next_development"); _go("build"),false,"crew_legacy")
		return
	var options := WorkcrewRules.choices(session.state,session.content)
	_label(panel,"한 주 뒤 변화 · 공사 예상",18,GameTheme.MUTED)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.add_child(grid)
	var lesson := Onboarding.current(session.state)
	var locked: bool = lesson.active and lesson.step < 5
	for option in options:
		var copy: String = "%s\n식량 %+.0f · 공사 %d\n목재 %+.0f · 장작 %+.0f" % [option.name,option.deltas.food,option.work,option.deltas.wood,option.deltas.fuel]
		if not option.available:
			var reason: String = "공사 예약 필요" if option.id == "build" else "벌목소 건설 필요" if option.id == "winter" and int(session.state.facilities.get("B25",0)) == 0 else "목재·인력 확보 필요" if option.id == "winter" else "이번 주 식량 작업 없음"
			copy = option.name + "\n" + reason
		var button := _button(grid,copy,func(): _choose_workcrew(option.id),not option.available or locked,"crew_"+option.id)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(180,84)
		button.add_theme_font_size_override("font_size",18)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = option.description + "\n" + option.scope + ("\n" + option.error if not option.available else "")
		if option.selected: _primary(button)
	for option in options:
		if option.selected:
			var staff := _label(panel,"농사 %d명 · 직영 작업 %d / %d명" % [option.allocation.farm,option.allocation.crew,option.budget],18,GameTheme.MUTED)
			staff.tooltip_text = "농사에 먼저 배정한 뒤 최대 20명을 직영 작업에 사용합니다. 남는 인력은 주민 생업을 유지합니다."

func _choose_workcrew(id: String) -> void:
	var error := WorkcrewRules.select(session.state,session.content,id)
	if error != "": _message(error); return
	var lesson := Onboarding.current(session.state)
	_ack_tutorial("policy_selected",false)
	_changed("작업 배정을 바꿨습니다. 한 주 진행 시 적용됩니다.")
	if lesson.active and lesson.step == 5:
		_message("안내 완료 · 이제 계절 목표에 맞춰 개발과 작업 배정을 선택하세요.")

func _management_menu() -> void:
	_shade(interface,.7).name = "DecisionBlocker"
	var box := _window("기록 · 관리",Vector2(720,420),false,true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind","management")
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for item in [["people","보좌관"],["journey","목표와 시련"],["ledger","상세 장부"],["world","영지 전경"],["archive","가문 강화"],["catalog","발견 · 통치 기록"]]:
		_button(grid,item[1],func(): management_open = false; _go(item[0]),false,"more_"+item[0]).size_flags_horizontal = SIZE_EXPAND_FILL
	_spacer(box)
	_button(box,"닫기",func(): management_open = false; _render(),false,"CloseManagement")

func _continue() -> void:
	if _is_active() and not session.state.has("onboarding"):
		Onboarding.setup(session.state,not session.profile.get("onboarding_complete",false))
	super._continue()
	_sync_onboarding()
	_save()

func _sync_onboarding() -> void:
	var lesson := Onboarding.sync(session.state)
	if lesson.completed: session.profile.onboarding_complete = true

func _changed(message: String) -> void:
	_sync_onboarding()
	super._changed(message)

func _ack_tutorial(event: String, redraw: bool = true) -> void:
	if Onboarding.acknowledge(session.state,event):
		_sync_onboarding()
		_save()
	if redraw: _render()

func _begin_tutorial(restart: bool = false) -> void:
	help_open = false
	if not _is_active():
		_open_prepare()
		guide_enabled = true
		return
	if restart: Onboarding.restart(session.state)
	else: Onboarding.resume(session.state)
	page = "estate"
	decision_hidden = false
	_save()
	_render()

func _skip_tutorial() -> void:
	Onboarding.skip(session.state)
	_save()
	_render()

func _tutorial_lesson() -> Dictionary:
	return Onboarding.current(session.state)

func _tutorial_overlay(canvas: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(canvas) or canvas != interface or not _is_active(): return
	var lesson := _tutorial_lesson()
	if not lesson.active or lesson.step == 0 or is_instance_valid(current_modal): return
	if is_instance_valid(tutorial_layer): tutorial_layer.queue_free()
	tutorial_layer = Control.new()
	tutorial_layer.name = "TutorialLayer"
	tutorial_layer.mouse_filter = MOUSE_FILTER_IGNORE
	interface.add_child(tutorial_layer)
	var target := interface.find_child(lesson.target_id,true,false) as Control
	if target == null or not target.is_visible_in_tree(): return
	var ancestor := target.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(target)
		ancestor = ancestor.get_parent()
	await get_tree().process_frame
	if not is_instance_valid(canvas) or canvas != interface or not is_instance_valid(target): return
	var rect := target.get_global_rect().grow(5)
	var focus := Panel.new()
	focus.name = "TutorialHighlight"
	focus.mouse_filter = MOUSE_FILTER_IGNORE
	var frame := TycoonTheme.panel(Color.TRANSPARENT,GOLD,0)
	frame.set_border_width_all(3)
	focus.add_theme_stylebox_override("panel",frame)
	tutorial_layer.add_child(focus)
	_place(focus,rect)
	var coach := _plate(_coach_rect(int(lesson.step)),true,20)
	coach.name = "TutorialCoach"
	var old_parent := coach.get_parent()
	interface.remove_child(old_parent)
	tutorial_layer.add_child(old_parent)
	_label(coach,"따라하기  %d / %d" % [lesson.step+1,lesson.total],18,TycoonTheme.NAV_TEXT)
	_heading(coach,lesson.title,false,TycoonTheme.NAV_TEXT)
	_label(coach,lesson.body,20,TycoonTheme.NAV_TEXT)
	_spacer(coach)
	_button(coach,"안내 건너뛰기",_skip_tutorial,false,"SkipTutorial")

func _turn_receipt_popup() -> void:
	var turn: Dictionary = session.state.get("last_receipt",{})
	if not turn.get("valid",false): return
	_shade(interface,.75).name = "DecisionBlocker"
	var box := _window("%d주 운영 결과" % turn.week,Vector2(1000,minf(620,size.y-64)),false,true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind","receipt")
	var detail := _scroll(box)
	_label(detail,"한 주 진행 직전 → 처리 완료 직후 · 식량은 공공과 주민의 합계입니다.",18,GameTheme.MUTED)
	for resource in turn.resource_rows:
		var row := _row(detail)
		var money: bool = resource.id == "money"
		_heading(row,resource.label)
		_label(row,(_money(resource.before)+" → "+_money(resource.after)) if money else "%.0f → %.0f" % [resource.before,resource.after],21)
		_label(row,"%+.2f금" % (resource.delta/100.0) if money else "%+.0f" % resource.delta,22,GameTheme.GOOD if resource.delta >= 0 else GameTheme.WARN)
		if money:
			_label(detail,"유입 %s · 지출 %s" % [_money(resource.income),_money(resource.expense)],18,GameTheme.MUTED)
		elif resource.id == "food":
			_label(detail,"생산 +%.0f · 주민 소비 −%.0f · 보관 손실 −%.0f · 종자 −%.0f" % [resource.production,resource.consumption,resource.spoilage,resource.seeds],18,GameTheme.MUTED)
		for flow in resource.flows:
			_label(detail,flow.label + "  " + ("%+.2f금" % (flow.amount/100.0) if money else "%+.0f" % flow.amount),18,GameTheme.MUTED)
		if not resource.fully_explained: _label(detail,"기타 재고 변화 %+.0f" % resource.unclassified_delta,18,GameTheme.MUTED)
		_rule(detail)
	_label(detail,"건설 작업 %d 완료 · 남은 작업 %d" % [turn.development.work_done,turn.development.remaining_work],20)
	for note in turn.notes: _label(detail,str(note),19)
	_primary(_button(box,"결과 확인 · 운영으로",_close_turn_details,false,"CloseTurnDetails"))

func _close_turn_details() -> void:
	receipt_open = false
	_ack_tutorial("turn_details_closed")

func _message(message: String) -> void:
	notice = message
	if not is_instance_valid(interface): return
	var previous := interface.get_node_or_null("ActionNotice")
	if previous != null: previous.queue_free()
	var toast := _plate(Rect2(48,size.y-164,minf(760,size.x-96),64),true,14)
	toast.get_parent().name = "ActionNotice"
	var display := message
	for asset in ["money","food","wood","stone","tools","fuel","iron"]:
		display = display.replace(asset,TurnReceipt.LABELS[asset])
	for id in session.content.facilities:
		display = display.replace(id,str(session.content.facilities[id].name))
	_label(toast,display,20,TycoonTheme.NAV_TEXT)
	var reference: WeakRef = weakref(toast.get_parent())
	get_tree().create_timer(4).timeout.connect(func():
		var frame: Variant = reference.get_ref()
		if is_instance_valid(frame): frame.queue_free())

func _focus_item() -> Dictionary:
	var item := super._focus_item()
	if CampaignDirector.enabled(session.state) and int(session.state.week) in range(27,40):
		var overview := CampaignDirector.overview(session.state,session.content)
		if not overview.met and item.get("kind") == "page" and item.get("page") != "build": return item
		if not overview.met and session.state.orders.is_empty() and session.state.projects.is_empty():
			return {"kind":"page","title":"겨울 장작을 더 준비하세요","body":overview.objective.detail,"action":"장작 주문 확인","page":"trade"}
	return item

func _journey(parent: Node) -> void:
	if not CampaignDirector.enabled(session.state):
		super._journey(parent)
		return
	var overview := CampaignDirector.overview(session.state,session.content)
	_label(parent,"계절 목표의 물자는 즉시 지급됩니다. 확보한 공훈은 회차 결산 때 받습니다.",20)
	for chapter in overview.chapters:
		var phase: Dictionary = CampaignDirector.phases(session.state,session.content)[chapter.index]
		var status: String = {"passed":"달성","failed":"미달","current":"진행 중","upcoming":"예정","missed":"평가 종료"}.get(chapter.status,"")
		var card := _card(parent)
		var row := _row(card)
		_heading(row,"%s · %d주 평가" % [chapter.season,chapter.deadline])
		_label(row,status,20,GameTheme.GOOD if chapter.status == "passed" else GameTheme.MUTED)
		_label(card,chapter.title,22)
		_label(card,"보상 · " + CampaignDirector._amounts(phase.reward) + " · 공훈 +%d" % phase.points,19,GameTheme.GOOD)
		_label(card,"미달 · " + CampaignDirector._amounts(phase.penalty),18,GameTheme.MUTED)
	_heading(parent,"52주 최종 평가")
	for goal in session.state.goals.values(): _label(parent,goal.detail + " · " + goal.status,20,GameTheme.GOOD if goal.done else GameTheme.WARN)
	var trial: Dictionary = session.content.chronicle.trials[session.state.trial]
	_heading(parent,"겨울 시련 · " + trial.name)
	_label(parent,trial.description,21)
	_label(parent,"현재 " + ("건강 %d" % session.state.health if session.state.trial == "frost" else "금고 " + _money(session.state.public.money) if session.state.trial == "audit" else "식량 %.1f주" % WeekSim.food_weeks(session.state)),20)
	_button(parent,"현재 회차를 끝내고 결산",_ask_retire,not _is_active(),"RetireRun")

func _go(target: String) -> void:
	receipt_open = false
	management_open = false
	if target == "build": _ack_tutorial("next_development",false)
	super._go(target)

func _development(parent: Node) -> void:
	if session.state.orders.is_empty() and session.state.projects.is_empty():
		super._development(parent)
		return
	var row := _row(parent)
	_project_status(_box(row))
	var actions := _box(row)
	_heading(actions,"진행 중인 개발")
	_label(actions,"아래 ‘한 주 진행’으로 공사를 진행하세요.",20)
	_button(actions,"작업반 배정 확인",func(): _go("estate"),false,"ReturnToWorkcrew")
	_quiet(_button(actions,"공사 상세 · 취소",func(): detail_open = not detail_open; _render(),false,"ProjectDetails"))
	if detail_open: _construction_queue(_scroll(parent))

func _boons(parent: Node) -> void:
	var top := _row(parent)
	_label(top,_next_reward_text(),20,GameTheme.TEAL)
	_button(top,"보유 특전" if boon_catalog else "전체 특전 %d종" % session.content.progression.perks.size(),func(): boon_catalog = not boon_catalog; _render(),false,"PerkCatalogToggle")
	_button(top,"특성·장비 상세" if not detail_open else "특전 조합",func(): detail_open = not detail_open; _render(),false,"BoonDetails")
	if detail_open:
		StewardScreens.boons(self,parent)
		return
	var filters := _row(parent)
	for entry in [["","전체"],["agriculture","농업"],["provisions","보존"],["industry","생산"],["court","행정"]]:
		var button := _button(filters,entry[1],func(): boon_family_filter = entry[0]; _render(),false,"perk_filter_"+str(entry[0]))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",18)
		if boon_family_filter == entry[0]: _primary(button)
	var body := _row(parent)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	var list := _scroll(body)
	var scroll := list.get_parent() as ScrollContainer
	scroll.name = "PerkListScroll"
	scroll.custom_minimum_size.x = 300
	scroll.size_flags_horizontal = SIZE_FILL
	var key := ("catalog" if boon_catalog else "owned")+":"+boon_family_filter
	scroll.set_meta("scroll_key",key)
	_restore_perk_scroll.call_deferred(scroll,int(boon_scroll_positions.get(key,0)))
	var ids: Array = session.content.progression.perks.keys() if boon_catalog else session.state.perks
	ids = ids.filter(func(id): return boon_family_filter == "" or session.content.progression.perks[id].family == boon_family_filter)
	if selected_perk not in ids: selected_perk = "" if ids.is_empty() else str(ids[0])
	for id in ids:
		var perk: Dictionary = session.content.progression.perks[id]
		var button := _button(list,("✓ " if id in session.state.perks else "")+str(perk.name),func(): selected_perk = id; _render(),false,"perk_browse_"+str(id))
		button.add_theme_font_size_override("font_size",18)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(perk.name)
		if selected_perk == id: _primary(button)
	var detail := _card(body)
	detail.name = "PerkCatalogDetail"
	if selected_perk == "":
		_heading(detail,"아직 모은 특전이 없습니다")
		_label(detail,"선택한 계열의 특전은 다음 후보에서 모을 수 있습니다. 전체 목록에서 효과와 운영 조합을 확인하세요.",20)
		return
	var perk: Dictionary = session.content.progression.perks[selected_perk]
	_heading(detail,str(perk.name),true)
	_label(detail,"이번 통치에 적용 중" if selected_perk in session.state.perks else "미보유 · 후보로 나오면 선택할 수 있습니다",18,GameTheme.GOOD if selected_perk in session.state.perks else GameTheme.MUTED)
	var area := _scroll(detail)
	_label(area,ConciseCopy.perk_brief(selected_perk,perk),22,GameTheme.TEAL)
	var counts := ChronicleRules.family_counts(session.content,session.state)
	var family: Dictionary = session.content.chronicle.families[perk.family]
	_heading(area,"%s · %d개 보유" % [family.name,counts[perk.family]]).name = "FamilyProgress"
	_label(area,family.description.replace("2장:","2개 ·").replace(" / 4장:","\n4개 ·"),18)
	RelicScreens.perk_routes(self,area,selected_perk)
	if CrisisDirector.enabled(session.state) and VillageRelics.enabled(session.state):
		_button(detail,"운영 조합 확인",func(): _go("operating_builds"),false,"PerkOperatingBuilds")


func _restore_perk_scroll(scroll: ScrollContainer, position_value: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll) and scroll.is_inside_tree(): scroll.scroll_vertical = position_value

func _decision_popup() -> void:
	_shade(interface,.72).name = "DecisionBlocker"
	var s := session.state
	var height := minf(680,size.y-64) if s.perk_offer.is_empty() and s.active_event != "" else minf(600,size.y-80)
	var box := _window("이번 통치를 바꿀 특전" if not s.perk_offer.is_empty() else "영주님의 결정",Vector2(minf(1060,size.x-90),height),false,true)
	current_modal = box.get_parent()
	var lesson := Onboarding.current(s)
	if lesson.active and lesson.step == 0:
		var guide := _row(box)
		guide.name = "TutorialCoach"
		_label(guide,"따라하기 1 / 6 · 특전 하나를 선택하세요",20,GameTheme.TEAL)
		_button(guide,"안내 건너뛰기",_skip_tutorial,false,"SkipTutorial")
	if not s.perk_offer.is_empty(): _perk_choices(box)
	elif s.active_event != "": _event_choices(box)
	else: _contract_choices(box)
	_quiet(_button(box,"영지 상태 확인",func(): decision_hidden = true; _render(),false,"InspectEstate"))
	_focus_decision.call_deferred()

func _perk_choices(parent: Node) -> void:
	var counts := ChronicleRules.family_counts(session.content,session.state)
	var row := _row(parent)
	row.name = "PerkChoicesArea"
	row.size_flags_vertical = SIZE_EXPAND_FILL
	for id in session.state.perk_offer:
		var perk: Dictionary = session.content.progression.perks[id]
		var card := _card(row)
		var family: Dictionary = session.content.chronicle.families[perk.family]
		var head := _row(card)
		_art(head,"building_"+{"agriculture":"farm","provisions":"storage","industry":"logging","court":"admin"}[perk.family],Vector2(56,56))
		_label(head,family.name + " 계열",19,GameTheme.MUTED)
		_heading(card,perk.name)
		RelicScreens.perk_impact(self,card,str(id))
		var detail := _scroll(card)
		detail.name = "PerkChoiceDetail_"+str(id)
		_label(detail,ConciseCopy.perk_brief(id,perk),21,GameTheme.TEAL)
		_rule(detail)
		_label(detail,"%s  %d → %d개" % [family.name,counts[perk.family],counts[perk.family]+1],18)
		_bar(detail,float(counts[perk.family]+1)/4)
		var synergy := _label(detail,"2개 · 4개를 모으면 추가 효과",18,GameTheme.MUTED)
		synergy.tooltip_text = family.description
		if counts[perk.family] in [1,3]: _label(detail,"이번 선택으로 특전 세트 발동",18,GameTheme.GOOD)
		RelicScreens.perk_routes(self,detail,str(id),true)
		_primary(_button(card,"선택",func(): session.choose_perk(id); _changed("특전을 선택했습니다."),false,"perk_"+id))
		var banishes: int = int(session.state.get("legacy_setup",{}).get("perk_banishes",0))
		if banishes > 0:
			var banish := _quiet(_button(card,"이번 통치에서 제외 · %d회" % banishes,func(): _banish_house_perk(str(id)),false,"banish_perk_"+str(id)))
			banish.custom_minimum_size.y = 32
			banish.add_theme_font_size_override("font_size",18)
			banish.tooltip_text = "이 특전은 이번 통치의 후보에서 제외됩니다. 나머지 두 후보를 유지하고 새 후보 하나를 받습니다."
	_quiet(_button(parent,"후보 새로고침 · %d회 남음" % session.state.refreshes,func(): session.refresh_perks(); _changed("후보를 바꿨습니다."),session.state.refreshes <= 0,"RefreshPerks"))

func _banish_house_perk(id: String) -> void:
	var error := session.banish_perk(id)
	if error != "": _message(error); return
	_changed("이 특전을 이번 통치의 후보에서 제외했습니다.")

func _refresh_house_relics() -> void:
	var error := session.refresh_relics()
	if error != "": _message(error); return
	_changed("성물 후보를 새로고침했습니다.")

func _advance(count: int) -> void:
	if busy: return
	var lesson := Onboarding.current(session.state)
	if lesson.active and lesson.step == 3 and not _pending():
		receipt_open = true
		_render()
		return
	var previous: int = session.state.get("campaign",{}).get("records",[]).size()
	await super._advance(count)
	_sync_onboarding()
	_save()
	var current: int = session.state.get("campaign",{}).get("records",[]).size()
	if current > previous and _is_active():
		show_season_result = true
	_render()
	if advance_error != "": _message(advance_error)

func _season_result_popup() -> void:
	if not CampaignDirector.enabled(session.state) or session.state.campaign.records.is_empty(): return
	_shade(interface,.7).name = "DecisionBlocker"
	var record: Dictionary = session.state.campaign.records.back()
	var box := _window(record.season + " 평가",Vector2(780,420),false,true)
	current_modal = box.get_parent()
	current_modal.set_meta("kind","season")
	_heading(box,"계절 목표 달성" if record.success else "계절 목표 미달",true)
	_label(box,record.title,24)
	_label(box,record.message,22,GameTheme.GOOD if record.success else GameTheme.WARN)
	_label(box,"물자는 반영되었습니다. 확보한 공훈은 통치 결산 때 지급됩니다." if record.success else "다음 계절에도 통치를 계속할 수 있습니다.",19)
	_spacer(box)
	_primary(_button(box,"다음 계절 준비  →",func(): show_season_result = false; _render(),false,"CloseSeasonResult"))

func _help_popup() -> void:
	_shade(interface,.7)
	var box := _window("플레이 안내",Vector2(900,560),false,true)
	current_modal = box.get_parent()
	_heading(box,"개발 승인  →  인력 배정  →  한 주 진행")
	_label(box,"진행 후 아래 결과 띠에서 지출·식량·완공을 확인하세요.",21)
	_rule(box)
	var row := _row(box)
	for entry in [["이번 통치","13주마다 계절 목표 평가\n같은 계열 특전 2개·4개로 강화"],["다음 통치","52주 운영 후 공훈 결산\n가문 강화하고 새 조합으로 재시작"]]:
		var column := _box(row)
		_heading(column,entry[0])
		_label(column,entry[1],20)
	_spacer(box)
	var lesson := Onboarding.current(session.state)
	if _is_active() and lesson.skipped and not lesson.completed:
		_primary(_button(box,"멈춘 단계부터 따라하기",func(): _begin_tutorial(),false,"ContinueTutorial"))
	_primary(_button(box,"실제 조작으로 다시 배우기" if _is_active() else "튜토리얼로 새 통치 준비",func(): _begin_tutorial(true),false,"StartTutorial"))
	_primary(_button(box,"닫기",func(): help_open = false; _render(),false,"CloseHelp"))

func _input(event: InputEvent) -> void:
	if _handle_quit_input(event): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var shown: String = str(current_modal.get_meta("kind","")) if is_instance_valid(current_modal) else ""
	if event.keycode == KEY_ESCAPE and shown in ["receipt","season","management"] and not help_open:
		match shown:
			"receipt":
				receipt_open = false
				_ack_tutorial("turn_details_closed",false)
			"season": show_season_result = false
			"management": management_open = false
		_render()
		get_viewport().set_input_as_handled()
		return
	if page in ["menu","prepare","archive","legacy_setup","frontier_setup","catalog","result"]:
		if event.keycode == KEY_ESCAPE:
			if help_open: help_open = false; _render()
			elif page == "legacy_setup": _go(house_return)
			elif page == "frontier_setup": _go("prepare")
			elif page != "menu": _go("menu")
			get_viewport().set_input_as_handled()
		return
	super._input(event)
