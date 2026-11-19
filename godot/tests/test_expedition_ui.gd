extends SceneTree
## Production UI: choose a run, develop the estate, earn and spend permanent growth.

var screen: Control
var failures := 0
var checks := 0
var save_path := ""
var captured_event := false
var pixel_theme_checked := false

func _init() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EXPEDITION UI FAIL: ", message)

func _frames(count: int = 5) -> void:
	for i in count: await process_frame

func _control(id: String) -> Control:
	return screen.find_child(id, true, false) as Control

func _visible(id: String) -> bool:
	var item := _control(id)
	return item != null and item.is_visible_in_tree()

func _same_amounts(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for key in expected:
		if not actual.has(key) or not is_equal_approx(float(actual[key]), float(expected[key])): return false
	return true

func _text(id: String) -> String:
	var item := _control(id)
	var lines: Array[String] = []
	if item != null:
		for label in item.find_children("*", "Label", true, false): lines.append(label.text)
	return "\n".join(lines)

func _check_result_values() -> void:
	var panel := _control("FoodResult")
	if panel == null or not panel.is_visible_in_tree(): return
	var labels := panel.find_children("*", "Label", true, false)
	var food := {}
	for row in screen.session.state.get("last_receipt", {}).get("resource_rows", []):
		if row.id == "food": food = row
	_check(labels.size() == 3 and not food.is_empty(), "food result exposes amount and an actual receipt summary")
	if labels.size() != 3 or food.is_empty(): return
	_check(absf(float(labels[1].text.replace("−", "-")) - float(food.delta)) < 0.051, "displayed food delta equals actual weekly change")
	var numbers := RegEx.new()
	numbers.compile("[+−-][0-9]+(?:[.][0-9]+)?")
	var matches := numbers.search_all(labels[2].text)
	_check(matches.size() == 2, "food summary exposes total inflow and outflow")
	if matches.size() == 2:
		_check(absf(float(matches[0].get_string().replace("−", "-")) - float(food.income)) < 0.051 and absf(float(matches[1].get_string().replace("−", "-")) + float(food.expense)) < 0.051, "visible food inflow and outflow match the actual ledger totals")

func _fully_visible(id: String) -> bool:
	var item := _control(id)
	if item == null or not item.is_visible_in_tree(): return false
	var rect := item.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(rect): return false
	var ancestor: Node = item.get_parent()
	while ancestor != screen.interface and ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().grow(1).encloses(rect): return false
		ancestor = ancestor.get_parent()
	return true

func _click(id: String) -> void:
	var previous_week: int = screen.session.state.get("week", 0)
	var previous_sequence: int = screen.store.sequence
	var button := _control(id) as Button
	_check(button != null, "exists " + id)
	if button != null:
		_check(not button.disabled, "enabled " + id)
		if not button.disabled: button.pressed.emit()
	await _frames()
	if id in ["NextWeek", "ProjectAdvance"] and int(screen.session.state.get("week", 0)) > previous_week:
		_check(SaveStore.valid(screen.session.bundle()), "week %d result remains a valid save" % previous_week)
		_check(screen.store.sequence > previous_sequence, "week %d progress is committed to a newer save" % previous_week)
		if not SaveStore.valid(screen.session.bundle()):
			var diagnostic: Dictionary = screen.session.bundle()
			for key in ["last_receipt", "campaign", "cabinet", "legacy_snapshot"]:
				var copy: Dictionary = diagnostic.duplicate(true)
				copy.state.erase(key)
				if SaveStore.valid(copy): printerr("SAVE DIAGNOSTIC: invalid ", key, " at week ", previous_week)

func _navigate(destination: String) -> void:
	if destination in ["build", "trade", "boons"]:
		await _click("nav_" + destination)
	else:
		await _click("MoreActions")
		await _click("more_" + destination)

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

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	root.push_input(event)
	await _frames()

func _shot(id: String) -> void:
	await _frames(8)
	_check_result_values()
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size)).grow(1)
	var overflow: Array[String] = []
	for name in ["TitleHub", "ExpeditionSetup", "SetupChoices", "SetupDetail", "LegacyBoard", "TalentTree", "TalentDetail", "CampaignHUD", "SeasonTrack", "OperatingWorkspace", "SeasonObjective", "DevelopmentProcess", "ConstructionStages", "WeekResult", "PolicyChoices", "TutorialCoach", "EstatePlayfield", "RunDock", "DecisionModal", "ManagementWindow", "RunResults"]:
		var panel := _control(name)
		if panel != null and panel.is_visible_in_tree() and not viewport.encloses(panel.get_global_rect()):
			overflow.append(name + " " + str(panel.get_global_rect()))
	for scroll in screen.interface.find_children("*", "ScrollContainer", true, false):
		if not scroll.is_visible_in_tree(): continue
		for child in scroll.get_children():
			if child is Control and not child is ScrollBar and child.size.x > scroll.size.x + 1:
				overflow.append(str(child.get_path()) + " horizontal overflow")
	if _visible("RunDock"):
		var dock_top: float = _control("RunDock").get_parent().get_global_rect().position.y
		for child in screen.interface.get_children():
			if child is PanelContainer and child.is_visible_in_tree() and child.name not in ["DecisionModal", "ManagementWindow"] and child.position.y >= 160 and child.position.y < dock_top:
				if child.get_global_rect().end.y > dock_top:
					overflow.append(str(child.get_path()) + " body overlaps action bar: " + str(child.get_global_rect()))
	var modal := _control("DecisionModal")
	if modal != null and modal.is_visible_in_tree():
		for button in modal.find_children("*", "Button", true, false):
			var scrolled := false
			var parent: Node = button.get_parent()
			while parent != modal:
				if parent is ScrollContainer: scrolled = true
				parent = parent.get_parent()
			if not scrolled and not modal.get_global_rect().encloses(button.get_global_rect()):
				overflow.append(str(button.name) + " escapes modal")
	_check(overflow.is_empty(), "layout fits " + id + ": " + "; ".join(overflow))
	var small: Array[String] = []
	for label in screen.interface.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.get_theme_font_size("font_size") < 18:
			small.append(label.text.left(30))
	_check(small.is_empty(), "native type at least 18 px " + id + ": " + "; ".join(small))
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "no window-wide text shrinking " + id)
	_check_pixel_theme(id)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		_check(shot != null, "rendered " + id)
		_check(shot.save_png("res://tests/output/expedition_" + id + ".png") == OK, "saved " + id)
		print("EXPEDITION SCREENSHOT: ", id)

func _contrast(a: Color, b: Color) -> float:
	var first := a.srgb_to_linear().get_luminance()
	var second := b.srgb_to_linear().get_luminance()
	return (maxf(first,second)+0.05)/(minf(first,second)+0.05)

func _frame_fill(style: StyleBox, caption: String) -> Color:
	_check(style is StyleBoxTexture,"pixel frame uses a real texture: "+caption)
	if not style is StyleBoxTexture: return Color.TRANSPARENT
	var texture_style := style as StyleBoxTexture
	_check(texture_style.texture != null,"pixel frame texture is loaded: "+caption)
	if texture_style.texture == null: return Color.TRANSPARENT
	var pixels := texture_style.texture.get_image()
	_check(pixels != null and not pixels.is_empty(),"pixel frame exposes generated image data: "+caption)
	if pixels == null or pixels.is_empty(): return Color.TRANSPARENT
	var width := pixels.get_width()
	var height := pixels.get_height()
	_check(width >= 8 and height >= 8 and width <= 64 and height <= 64,"pixel frame is a compact source grid, not a blurred full-size panel: "+caption)
	var center := pixels.get_pixel(int(width/2.0),int(height/2.0))
	var rim := pixels.get_pixel(0,int(height/2.0))
	_check(center.a > .99 and rim.a > .99 and pixels.get_pixel(0,0).a < .01,"frame keeps an opaque fill and edge with stepped transparent corners: "+caption)
	_check(not center.is_equal_approx(rim),"frame boundary is visibly distinct from its fill: "+caption)
	var crisp := true
	for y in height:
		for x in width:
			var alpha := pixels.get_pixel(x,y).a
			if alpha > .01 and alpha < .99: crisp = false
	_check(crisp,"frame alpha has hard pixel edges: "+caption)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		var margin := texture_style.get_texture_margin(side)
		_check(margin >= 2 and margin < minf(width,height)*.5 and is_equal_approx(margin,roundf(margin)),"nine-slice preserves whole-pixel corner borders: "+caption+" "+str(side))
	return center

func _check_pixel_theme(page_id: String) -> void:
	for kind in ["Button","PrimaryButton"]:
		var current := screen.theme.get_stylebox("normal",kind) as StyleBoxTexture
		_check(current != null and current.texture != null,"pixel frame remains loaded on page "+page_id+" "+kind)
	if pixel_theme_checked: return
	pixel_theme_checked = true
	_check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"UI uses nearest texture filtering: "+page_id)
	var fills := {}
	for kind in ["Button","PrimaryButton","QuietButton","NavigationButton"]:
		var values := {}
		for state in ["normal","hover","pressed","disabled"]:
			var caption: String = page_id+" "+kind+" "+state
			var color := _frame_fill(screen.theme.get_stylebox(state,kind),caption)
			values[state] = color
			var font_key: String = {"normal":"font_color","hover":"font_hover_color","pressed":"font_pressed_color","disabled":"font_disabled_color"}[state]
			var ink := screen.theme.get_color(font_key,kind)
			_check(_contrast(ink,color) >= 4.5,"button text stays readable in this state: "+caption)
		fills[kind] = values
		_check(values.hover.get_luminance() > values.normal.get_luminance() and values.pressed.get_luminance() < values.normal.get_luminance(),"hover brightens and press darkens without hiding the label: "+page_id+" "+kind)
		_check(screen.theme.get_font_size("font_size",kind) >= 18,"button text keeps readable native size: "+page_id+" "+kind)
		var focus := screen.theme.get_stylebox("focus",kind) as StyleBoxFlat
		_check(focus != null and focus.bg_color.a < .01 and focus.border_color.a > .99 and focus.border_width_left >= 2,"keyboard focus is an outlined overlay: "+page_id+" "+kind)
		if focus != null: _check(_contrast(focus.border_color,values.normal) >= 3.0,"keyboard focus remains visible against the dark button: "+page_id+" "+kind)
	_check(not fills.Button.normal.is_equal_approx(fills.PrimaryButton.normal),"primary action is visibly distinct from secondary buttons: "+page_id)

func _playfield() -> void:
	for id in ["CampaignHUD", "SeasonTrack", "OperatingWorkspace", "DevelopmentProcess", "ConstructionStages", "WeekResult", "RunDock", "NextWeek", "MoreActions"]:
		_check(_fully_visible(id), "primary gameplay fits without scrolling: " + id)
	var dock_top: float = _control("RunDock").get_parent().get_global_rect().position.y
	for id in ["OperatingWorkspace", "DevelopmentProcess", "WeekResult"]:
		var panel := _control(id)
		if panel != null:
			_check(panel.get_parent().get_global_rect().end.y <= dock_top, "main panel does not overlap action bar: %s week %s %s at %s" % [id, screen.session.state.week, root.size, panel.get_parent().get_global_rect()])
			_check(panel.find_children("*", "ScrollContainer", true, false).is_empty(), "main panel requires no scroll: " + id)
	_check(not _visible("Settlement"), "decorative settlement does not replace development and results")
	_check("승인" in _text("ConstructionStages") and "공사" in _text("ConstructionStages") and "완공" in _text("ConstructionStages"), "construction sequence is explained in text")
	_check(_visible("TurnDetails") == bool(screen.session.state.get("last_receipt", {}).get("valid", false)), "details action exists only for an actual weekly result")
	_check(not _visible("job_build") and not _visible("job_gather"), "routine workforce controls are absent from gameplay")
	_check(not _visible("TextNavigation") and not _visible("JournalTabs"), "old journal navigation is absent")
	_check(not _visible("ProjectAdvance"), "time progression has one consistent button")
	_check(not _visible("nav_people") and not _visible("nav_journey") and not _visible("nav_ledger") and not _visible("nav_world"), "secondary management remains behind records")

func _resolve_decisions() -> void:
	for guard in 8:
		if not screen.session.state.perk_offer.is_empty():
			await _click("perk_" + str(screen.session.state.perk_offer[0]))
		elif screen.session.state.active_event != "":
			if not captured_event:
				_check(_fully_visible("DecisionModal"), "lord's event appears in a contained decision modal")
				await _shot("event_720")
				captured_event = true
			var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
			var picked := false
			for i in event.options.size():
				if event.options[i].get("cost", {}).is_empty() and not event.options[i].has("requires_housing"):
					await _click("event_option_%d" % i)
					picked = true
					break
			if not picked:
				_check(false, "event offers a free fallback")
				return
		elif _visible("CloseSeasonResult"):
			return
		else: return
	_check(false, "pending decisions finish within a bounded number of choices")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	save_path = "res://tests/output/expedition_ui_%d" % Time.get_ticks_usec()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.guide_enabled = false
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	# 실제 메인 화면은 realm_ui(집무실·건설 지구)이며 test_realm_ui가 검사한다. 여기서는 부임 화면의 호환 회귀를 본다.
	var entry: bool = screen.get_script().resource_path == "res://ui/expedition_ui.gd"
	_check(entry, "expedition UI regression entrypoint")
	if not entry or screen.session == null:
		quit(1)
		return
	_check(_visible("TitleHub") and not _visible("RunDock"), "title is distinct from play")
	await _shot("01_title_720")
	await _click("OpenArchive")
	_check(screen.interface.find_children("talent_*", "Button", true, false).size() == 8 and screen.interface.find_children("legacy_branch_*", "Button", true, false).size() == 6, "six house branches expose eight readable nodes at a time")
	_check(_control("BuyTalent").disabled and _control("RefundTalents").disabled, "new profile cannot buy or refund unavailable talents")
	await _shot("02_empty_legacy_720")
	await _click("LegacyBack")
	await _click("NewRun")
	_check(screen.page == "prepare" and screen.session.state.is_empty(), "new run opens preparation without creating a run")
	await _click("SetupCancel")
	_check(screen.page == "menu" and screen.session.profile.runs == 0, "cancel leaves no started run")
	await _click("NewRun")
	screen.draft_seed = 61427
	screen._render()
	await _frames()
	await _click("candidate_1")
	await _shot("03_choose_lord_720")
	await _click("PrepareNext")
	await _click("region_river")
	await _shot("04_choose_region_720")
	await _click("PrepareBack")
	_check(screen.draft_candidate == 1 and screen.draft_region == "river", "back preserves selected lord and region")
	await _click("PrepareNext")
	await _click("PrepareNext")
	_check(_control("relic_seal").disabled, "full equipment budget prevents an extra item")
	await _click("relic_axe")
	await _click("relic_seal")
	_check(screen.draft_relics == ["seeds", "seal"] and screen._relic_cost() == 3, "equipment can be exchanged within budget")
	await _shot("05_choose_gear_720")
	var expected: Dictionary = ChronicleRules.candidates(screen.session.content.chronicle, 61427)[1]
	screen.guide_enabled = false
	await _click("StartRun")
	_check(screen.session.state.origin == expected.origin and screen.session.state.traits == expected.traits, "selected lord and traits affect actual run")
	_check(screen.session.state.region == "river" and screen.session.state.relics == ["seeds", "seal"], "selected region and equipment reach simulation")
	_check(CampaignDirector.enabled(screen.session.state) and CabinetRules.enabled(screen.session.state), "new run enables seasonal campaign and automatic workers")
	_check(screen.session.state.week == 1 and not screen.session.state.perk_offer.is_empty(), "first strategic choice is a perk")
	_check(screen.session.state.active_event != "EV01", "no redundant introductory event after preparation")
	await _shot("06_first_perk_720")
	await _mouse_click(_control("nav_build").get_global_rect().get_center())
	_check(screen.page == "estate", "modal blocks actual background pointer navigation")
	await _click("InspectEstate")
	await _click("NextWeek")
	_check(screen.session.state.week == 1 and _visible("DecisionModal"), "unresolved choice blocks advancing time")
	await _resolve_decisions()
	_playfield()
	await _shot("07_estate_720")
	var money_before: int = screen.session.state.public.money
	await _mouse_click(_control("FocusAction").get_global_rect().get_center())
	_check(screen.session.state.orders.count("B13") == 2 and screen.session.state.assign.build == 8, "one farm action reserves two plots and automatic workers")
	_check(screen.session.state.public.money == money_before, "construction reservation does not charge early")
	_check("예약 완료" in _text("DevelopmentProcess") and _visible("NextWeek"), "approved plan explains its pending state and progression action")
	_playfield()
	await _shot("08_construction_720")
	var food_before: float = WeekSim.total_food(screen.session.state)
	await _click("NextWeek")
	_check(screen.session.state.week == 2 and screen.session.state.history.size() == 1, "one week button processes one actual week")
	var bars := _control("DevelopmentProcess").find_children("*", "ProgressBar", true, false)
	_check(bars.size() == 1 and bars[0].value > 0 and bars[0].value < bars[0].max_value, "combined project progress survives completion of its first plot")
	_check("남은 작업" in _text("DevelopmentProcess") and "금고" in _text("WeekResult") and "식량" in _text("WeekResult"), "work and weekly resource results remain readable together")
	var receipt: Dictionary = screen.session.state.last_receipt.duplicate(true)
	_check(receipt.valid and receipt.week == 1 and receipt.development.work_done == 8 and receipt.advisor.acted, "weekly result records actual construction and advisor action")
	for resource in receipt.resource_rows:
		if resource.id == "money": _check(resource.before == money_before and resource.after == screen.session.state.public.money and resource.delta == resource.after - money_before, "money result equals actual before and after")
		if resource.id == "food": _check(is_equal_approx(resource.before, food_before) and is_equal_approx(resource.after, WeekSim.total_food(screen.session.state)), "food result includes actual resident and public stocks")
	_playfield()
	await _shot("08b_work_result_720")
	await _click("TurnDetails")
	await _shot("08c_turn_details_720")
	await _key(KEY_SPACE)
	await _mouse_click(_control("nav_build").get_global_rect().get_center())
	_check(screen.session.state.week == 2 and screen.page == "estate", "weekly details block underlying keyboard and pointer actions")
	await _click("CloseTurnDetails")
	_check(not _visible("DecisionModal") and screen.session.state.last_receipt == receipt, "closing details does not repeat any simulation or reward")
	await _click("NextWeek")
	_check(screen.session.state.facilities.B13 == 6 and screen.session.state.week == 3, "first development completes after two weeks")
	_playfield()
	_check("현재 보유" in _text("DevelopmentProcess"), "completion explains the result in text")
	await _shot("09_farms_complete_720")
	await _click("FocusAction")
	_check(screen.page == "build" and screen.session.state.orders.is_empty(), "completed project routes to development choices without silently approving another project")
	await _click("BackEstate")
	await _navigate("world")
	_check(_fully_visible("Settlement") and not _visible("DevelopmentProcess"), "settlement is available as a secondary overview")
	_check(screen.campaign_board.sprites.size() == 12 and "×6" in screen.campaign_board.labels.B13.text, "secondary overview reflects the developed farm count")
	await _shot("09b_world_720")
	await _mouse_click(_control("site_trade").get_global_rect().get_center())
	_check(screen.page == "trade", "clicking the market opens supplies")
	await _click("BackEstate")
	for destination in ["build", "trade", "people", "boons", "ledger", "journey"]:
		await _navigate(destination)
		_check(screen.page == destination, "action bar opens " + destination)
		await _shot("10_" + destination + "_720")
		await _click("BackEstate")
	root.size = Vector2i(1440, 900)
	screen._render()
	await _shot("11_estate_900")
	_playfield()
	root.size = Vector2i(1280, 720)
	screen._render()
	await _frames()
	for guard in 20:
		if screen.session.state.week >= 14: break
		await _resolve_decisions()
		var previous: int = screen.session.state.week
		await _click("NextWeek")
		_check(screen.session.state.week == previous + 1, "campaign week advances once")
	_check(screen.session.state.week == 14, "play reaches first season evaluation")
	await _resolve_decisions()
	_check(_visible("CloseSeasonResult"), "season result is a visible acknowledgement")
	_check(screen.session.state.campaign.records.size() == 1 and screen.session.state.campaign.records[0].success, "completed farms satisfy spring objective")
	var season_points: int = screen.session.state.campaign.points
	_check(season_points > 0 and screen.session.profile.points == 0, "season growth is banked until run settlement")
	await _shot("12_season_result_720")
	await _mouse_click(_control("nav_build").get_global_rect().get_center())
	_check(screen.page == "estate", "season result blocks background pointer navigation")
	await _click("CloseSeasonResult")
	_check(screen.session.state.campaign.points == season_points and not _visible("DecisionModal"), "closing season result neither duplicates reward nor leaves a modal")
	await _navigate("journey")
	await _click("RetireRun")
	var dialogs := screen.find_children("*", "ConfirmationDialog", true, false)
	_check(dialogs.size() == 1 and screen.session.state.status == "active", "retirement asks confirmation before settlement")
	if dialogs.size() == 1: dialogs[0].confirmed.emit()
	await _frames()
	_check(screen.page == "result" and screen.session.state.status == "finalized", "confirming retirement opens result screen")
	var earned: int = screen.session.profile.points
	_check(earned >= 12 and screen.session.state.result.campaign_points == season_points, "actual settlement includes seasonal and legacy awards")
	await _shot("13_run_result_720")
	await _click("ResultArchive")
	await _click("talent_LF02")
	_check(_control("BuyTalent").disabled, "dependent talent requires its parent")
	await _click("talent_LF01")
	await _click("BuyTalent")
	_check(LegacyPath.rank(screen.session.profile, "LF01") == 1 and screen.session.profile.points == earned - 2, "talent purchase spends its displayed rank price")
	await _click("BuyTalent")
	await _click("BuyTalent")
	_check(LegacyPath.rank(screen.session.profile, "LF01") == 3 and screen.session.profile.points == earned - 12 and _control("BuyTalent").disabled, "three escalating ranks reach the visible cap")
	await _shot("14_legacy_max_rank_720")
	await _click("RefundTalents")
	_check(screen.session.profile.points == earned and screen.session.profile.legacy_talents.is_empty(), "free respec returns the actual full paid amount")
	await _click("BuyTalent")
	await _click("legacy_branch_agriculture")
	await _click("talent_LA01")
	await _click("BuyTalent")
	var talents: Dictionary = screen.session.profile.legacy_talents.duplicate(true)
	_check(talents == {"LF01":1, "LA01":1}, "player can choose a different permanent build")
	root.size = Vector2i(1440, 900)
	screen._render()
	await _shot("15_legacy_900")
	await _click("LegacyPrepare")
	screen.draft_seed = 77119
	screen._render()
	await _frames()
	await _shot("16_prepare_900")
	await _click("PrepareNext")
	await _click("PrepareNext")
	var baseline := GameSession.new(screen.session.content)
	baseline.profile = screen.session.profile.duplicate(true)
	baseline.profile.legacy_talents = {}
	baseline.start_run(screen.draft_seed, "settler", {"region":screen.draft_region, "candidate":screen.draft_candidate, "relics":screen.draft_relics, "tutorial":false, "cabinet":true, "campaign":true})
	screen.guide_enabled = false
	await _click("StartRun")
	_check(screen.session.profile.runs == 2 and screen.session.state.week == 1, "next run starts fresh")
	_check(screen.session.state.legacy_snapshot == talents, "new run records selected permanent ranks")
	_check(screen.session.state.public.money == baseline.state.public.money + 400 and screen.session.state.public.food == baseline.state.public.food + 80, "selected talents change real new-run resources by exact advertised amounts")
	var start_resources: Dictionary = screen.session.state.public.duplicate(true)
	screen._render()
	await _frames()
	_check(screen.session.state.public == start_resources, "rendering cannot reapply permanent bonuses")
	await _resolve_decisions()
	await _click("nav_menu")
	await _key(KEY_SPACE)
	_check(screen.session.state.week == 1, "title screen Space cannot advance an active run")
	await _shot("17_continue_title_900")
	await _click("OpenArchive")
	_check(_control("BuyTalent").disabled and _control("RefundTalents").disabled, "active run locks permanent purchases and respec")
	await _key(KEY_SPACE)
	_check(screen.session.state.week == 1, "meta screen Space cannot advance the active run")
	_check(screen.store.read().ok, "UI progression produces a valid persistent save")
	var saved_resources: Dictionary = screen.session.state.public.duplicate(true)
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.guide_enabled = false
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	_check(not screen.load_blocked and screen.session.state.legacy_snapshot == talents, "saved run and its permanent snapshot reload")
	await _click("ContinueRun")
	_check(_same_amounts(screen.session.state.public, saved_resources) and screen.session.state.week == 1, "continue preserves resources and never reapplies setup rewards")
	_playfield()
	await _shot("18_reloaded_estate_900")
	var sequence_before: int = screen.store.sequence
	await _click("NextWeek")
	_check(screen.session.state.week == 2 and screen.store.sequence > sequence_before, "loaded run advances and persists a newer save generation")
	var reloaded: Dictionary = screen.store.read()
	_check(reloaded.ok and reloaded.bundle.state.week == 2 and SaveStore.valid(reloaded.bundle), "post-load autosave is valid and contains the latest progress")
	print("EXPEDITION UI: %d checks, %d failures" % [checks, failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)
