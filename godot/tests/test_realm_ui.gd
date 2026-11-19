extends SceneTree
## 실제 메인 씬(지도 중심 운영 화면)을 버튼 신호로 조작한다. 렌더러가 있으면 PNG도 저장한다.
## 실행: godot --path . -s tests/test_realm_ui.gd   (헤드리스는 --headless 추가)

var screen: Control
var failures := 0
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("REALM UI FAIL: ", message)


func _frames(count: int = 5) -> void:
	for i in count: await process_frame


func _control(id: String) -> Control:
	return screen.find_child(id, true, false) as Control


func _visible(id: String) -> bool:
	var item := _control(id)
	return item != null and item.is_visible_in_tree()


func _text(id: String) -> String:
	var item := _control(id)
	var lines: Array[String] = []
	if item != null:
		for label in item.find_children("*", "Label", true, false): lines.append(label.text)
		for button in item.find_children("*", "Button", true, false): lines.append(button.text)
	return "\n".join(lines)


func _click(id: String) -> void:
	if not is_instance_valid(screen.current_modal):
		if id in ["nav_policy","nav_boons","nav_people","nav_sanctuary"] and not _visible(id): await _click("MoreActions")
		if id.begins_with("lot_") or id.begins_with("build_"):
			var facility := id.trim_prefix("lot_").trim_prefix("build_")
			var district := RealmBoard.district_for(facility)
			if screen.page != "build": await _click("nav_build")
			if screen.active_district != district: await _click("district_"+district)
			if not _visible("lot_"+facility): await _click("MapPlansToggle")
			if id.begins_with("build_") and screen.selected_lot != facility: await _click("lot_"+facility)
	var button := _control(id) as Button
	_check(button != null and button.is_visible_in_tree(), "visible " + id)
	if button != null:
		_check(not button.disabled, "enabled " + id)
		if not button.disabled: button.pressed.emit()
	await _frames()


func _inside(id: String) -> bool:
	var item := _control(id)
	return item != null and item.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(root.size)).grow(1).encloses(item.get_global_rect())


func _shot(name_value: String) -> void:
	await _frames(8)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty(), "rendered " + name_value)
	if image != null and not image.is_empty(): image.save_png("res://tests/output/realm_" + name_value + ".png")


## 뜬 결정을 모두 처리한다. 특전은 첫 후보, 사건은 조건이 맞는 마지막(가장 조심스러운) 선택.
func _settle() -> void:
	for attempt in 8:
		await _frames(2)
		var relics: Array = screen.session.state.get("realm", {}).get("sanctuary", {}).get("offer", [])
		if _visible("AcknowledgeOutcome"):
			await _click("AcknowledgeOutcome")
		elif _visible("RelicAcquiredContinue"):
			await _click("RelicAcquiredContinue")
		elif not relics.is_empty() and _visible("take_relic_" + str(relics[0])):
			await _click("take_relic_" + str(relics[0]))
		elif _visible("CloseSeasonResult"):
			await _click("CloseSeasonResult")
		elif not screen.session.state.perk_offer.is_empty():
			await _click("perk_" + str(screen.session.state.perk_offer[0]))
		elif screen.session.state.active_event != "":
			var event: Dictionary = screen.session.content.events[screen.session.state.active_event]
			var chosen := -1
			for index in range(event.options.size() - 1, -1, -1):
				if screen.session.option_error(event.options[index]) == "":
					chosen = index
					break
			_check(chosen >= 0, "every event keeps one selectable option: " + str(screen.session.state.active_event))
			if chosen < 0: return
			await _click("event_option_%d" % chosen)
		else:
			return


func _weeks(count: int) -> void:
	for i in count:
		await _settle()
		if screen.session.state.status != "active": return
		await _click("NextWeek")
	await _settle()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	screen = load("res://ui/main.tscn").instantiate()
	screen.save_directory = "res://tests/output/realm_ui_%d" % Time.get_ticks_usec()
	root.add_child(screen)
	await _frames()
	_check(screen.get_script().resource_path == "res://ui/main.gd" and screen.get_script().get_base_script().resource_path == "res://ui/realm_ui.gd", "production scene runs the realm UI")
	if screen.session == null:
		quit(1)
		return
	screen.guide_enabled = false
	_check(_visible("TitleHub"), "title screen")
	await _click("NewRun")
	screen.draft_seed = 61427
	screen.guide_enabled = false
	await _click("PrepareNext")
	await _click("PrepareNext")
	await _click("StartRun")
	var s: Dictionary = screen.session.state
	_check(RealmRules.enabled(s), "a new run from the real UI uses the realm rules")
	_check(_visible("PerkChoicesArea"), "first perk choice opens")
	await _shot("01_first_perk_720")
	await _settle()

	# ---- 운영 화면: 지도, HUD, 옆 패널 ----
	_check(_visible("OfficeDesk") and not _visible("RealmBoard") and _visible("CampaignHUD") and _visible("RunDock"), "office, HUD and dock are the operating screen")
	for id in ["CampaignHUD", "SeasonTrack", "EstatePlayfield", "OperatingWorkspace", "RunDock", "NextWeek", "side_tab_overview", "side_tab_projects", "side_tab_growth"]:
		_check(_inside(id), "inside the window at 1280x720: " + id)
	_check(_visible("WorkcrewArea") and _visible("WeekResult") and not _visible("FocusAction"), "default overview keeps the work crew and weekly result visible without mixing in the project catalog")
	_check(not screen.show_build_plans, "the map starts with future construction outlines hidden")
	_check(not _visible("lot_B19"), "locked future facilities stay off the default estate map")
	_check(RealmBoard.lot_kind(s, screen.session.content, "B13") == "built" and RealmBoard.lot_kind(s, screen.session.content, "B22") == "temp", "starting farms are built and the granary lot shows the temporary store")
	_check(RealmBoard.lot_kind(s, screen.session.content, "B16") == "open" and RealmBoard.lot_kind(s, screen.session.content, "B19") == "locked", "open and locked lots are told apart")
	_check(_text("CampaignHUD").contains("치안") and _text("CampaignHUD").contains("건강") and (_text("CampaignHUD") + _text("SeasonTrack")).contains("석재"), "security, health and materials are always visible")
	_check(_text("RealmNews") != "" or _text("WeekResult") != "", "overview has a usable weekly summary")
	await _shot("02_estate_720")
	await _click("side_tab_growth")
	_check(not _visible("FocusAction") and not _visible("WorkcrewArea"), "growth tab has a distinct role instead of repeating operational controls")
	_check(_text("OperatingWorkspace").contains("승격") or _text("OperatingWorkspace").contains("촌락"), "growth tab explains the next settlement milestone")
	await _click("side_tab_overview")
	_check(_visible("WorkcrewArea") and _visible("WeekResult"), "returning to overview restores the weekly operating controls")

	# ---- 별도 지구에서 터를 눌러 건설 ----
	await _click("nav_build")
	await _click("district_food")
	await _click("MapPlansToggle")
	_check(screen.realm_board.lots.size() == 22 and _visible("lot_B19"), "show-all toggle exposes all 22 future lots including locked ones")
	await _click("lot_B16")
	_check(_visible("LotPanel") and _text("LotPanel").contains("어장") and _visible("build_B16"), "clicking an open lot shows cost and an approve button")
	await _shot("03_lot_selected_720")
	await _click("lot_B19")
	_check(_text("LotPanel").contains("곡물 곳간") and not _visible("build_B19"), "a locked lot explains what it needs")
	await _click("CloseLot")
	await _click("side_tab_projects")
	_check(_inside("FocusAction"), "recommended development action stays inside the projects tab")
	await _click("FocusAction")
	await _click("build_B13")
	_check(s.orders.count("B13") == 2, "recommended farm expansion queues two plots")
	await _click("lot_B16")
	await _click("build_B16")
	await _click("side_tab_projects")
	_check(s.orders.size() == 3 and _text("DevelopmentProcess").contains("어장"), "a second project runs in parallel and is listed")
	_check(_text("DevelopmentProcess").contains("이번 주") and _visible("promote_order_2"), "project rows show predicted work and an actual priority action")
	var construction_cash: float = s.public.money
	await _click("promote_order_2")
	_check(s.orders == ["B16", "B13", "B13"] and s.public.money == construction_cash and int(s.week) == 1, "priority button moves the fishery first without paying or advancing time")
	await _shot("04_projects_queued_720")
	await _click("side_tab_overview")
	await _click("crew_build")
	_check(s.workcrew.policy == "build", "work crew policy switches from the side panel")
	var money: float = s.public.money
	await _click("NextWeek")
	_check(int(s.week) == 2 and s.public.money < money and s.projects.size() >= 1, "advancing pays for and starts construction")
	_check(int(s.facilities.get("B16",0)) == 1 and int(s.facilities.B13) == 5, "actual completion follows the priority selected in the UI")
	_check(_visible("TurnDetails") and _text("WeekResult").contains("결산"), "last week's result appears in the side panel")
	_check(screen.page == "estate" and _text("WeekResult").contains("완공"), "completion remains visible in the office receipt")
	await _shot("05_after_week_720")
	await _click("TurnDetails")
	_check(_visible("CloseTurnDetails"), "detailed receipt opens")
	await _click("CloseTurnDetails")
	await _weeks(2)
	_check(int(s.facilities.get("B13", 0)) == 6 and int(s.facilities.get("B16", 0)) == 1, "farms and the fishery are completed")
	_check(RealmBoard.lot_kind(s, screen.session.content, "B16") == "built", "the completed fishery is shown as built")

	# ---- 건설 목록 ----
	await _click("nav_build")
	await _click("lot_B33")
	_check(_text("LotPanel").contains("대장간") and not _visible("build_B33"), "locked smithy has an explanation and no false approval action")
	await _click("lot_B22")
	_check(_visible("build_B22"), "granary approval is offered at its actual site")
	await _shot("06_build_catalog_720")
	await _click("build_B22")
	_check(screen.page == "estate" and s.orders.has("B22"), "approving from the catalog returns to the map")

	# ---- 포고 ----
	await _click("nav_policy")
	_check(_visible("policy_militia") and _control("policy_open_market").disabled, "policies listed; market policy locked without a market")
	await _shot("07_policies_720")
	await _click("policy_militia")
	_check("militia" in s.realm.policies and RealmRules.target(s, "security") >= 14, "enacting a policy changes the rules at once")
	_check(_control("policy_relief").disabled, "single slot and cooldown block a second policy")
	await _click("ration_90")
	_check(is_equal_approx(float(s.ration), 0.9), "ration control lives with the policies")
	await _click("ration_100")

	# ---- 물자 ----
	await _click("nav_trade")
	_check(_visible("supply_food") and not _visible("sell_wood"), "buying is open; selling waits for a market")
	await _shot("08_trade_720")
	await _click("nav_estate")

	# ---- 사건: 확률과 결과 ----
	await _settle()
	s.active_event = "RV_RAID"
	screen.decision_hidden = false
	screen._render()
	await _frames()
	_check(_visible("EventChoices") and _text("EventChoices").contains("성공 확률"), "threat event shows its odds before choosing")
	_check(_control("event_option_2").disabled, "mercenary option locked by merchant favour")
	await _shot("09_event_raid_720")
	await _click("event_option_1")
	_check(_visible("AcknowledgeOutcome") and _visible("OutcomeVerdict"), "chance outcome is shown after the choice")
	await _shot("10_event_outcome_720")
	await _click("AcknowledgeOutcome")
	_check(not _visible("DecisionBlocker"), "outcome popup closes")
	_check(SaveStore.valid(screen.session.bundle()), "state stays saveable after UI actions")

	# ---- 큰 화면, 여름, 여러 시설 ----
	root.size = Vector2i(1440, 900)
	await _frames()
	for id in ["B25", "B67", "B49", "B01", "B57", "B27", "B33"]: s.facilities[id] = 1
	s.public.stone = 60
	s.week = 20
	s.realm.weather = "summer_monsoon"
	RealmRules.refresh(s, screen.session.content)
	screen.selected_lot = ""
	screen._render()
	await _frames()
	for id in ["CampaignHUD", "SeasonTrack", "EstatePlayfield", "OperatingWorkspace", "RunDock", "NextWeek"]:
		_check(_inside(id), "inside the window at 1440x900: " + id)
	await _shot("11_estate_grown_900")
	await _click("nav_trade")
	_check(_visible("sell_wood"), "market enables the sell cards")
	await _click("nav_estate")
	await _weeks(3)
	await _shot("12_estate_after_weeks_900")

	# ---- 겨울과 결산 ----
	root.size = Vector2i(1280, 720)
	await _frames()
	var guard := 0
	while s.status == "active" and guard < 60:
		guard += 1
		await _weeks(1)
		if int(s.week) == 42: await _shot("13_winter_720")
	_check(s.status == "finalized" and s.result.has("grade"), "the run reaches a graded conclusion through the UI")
	_check(screen.page == "result" and _visible("GradeStamp"), "result screen shows the grade")
	await _shot("14_result_720")
	_check(SaveStore.valid(screen.session.bundle()), "finalized run is saveable")
	await _tutorial_run()
	await _legacy_run()
	print("REALM UI: %d checks, %d failures" % [checks, failures])
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)


func _fresh(tag: String) -> void:
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.save_directory = "res://tests/output/realm_ui_%s_%d" % [tag, Time.get_ticks_usec()]
	root.add_child(screen)
	await _frames()


## 실제 조작 안내가 새 화면의 버튼을 가리키고, 조작에 따라 넘어간다.
func _tutorial_run() -> void:
	await _fresh("guide")
	await _click("NewRun")
	screen.draft_seed = 61427
	screen.guide_enabled = true
	await _click("PrepareNext")
	await _click("PrepareNext")
	await _click("StartRun")
	_check(_visible("TutorialCoach"), "tutorial starts inside the first perk choice")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	await _frames(8)
	_check(Onboarding.current(screen.session.state).step == 1, "tutorial moves to approving the farm")
	_check(_visible("TutorialHighlight") and _visible("TutorialCoach") and _visible("nav_build"), "coach first guides from office to construction")
	var coach := _control("TutorialCoach")
	var target := _control("nav_build")
	_check(coach != null and target != null and not coach.get_parent().get_global_rect().intersects(target.get_global_rect()), "coach box does not cover the highlighted button")
	await _shot("15_tutorial_720")
	await _click("nav_build")
	await _click("build_B13")
	await _frames(8)
	_check(Onboarding.current(screen.session.state).step == 2, "approving the farm advances the tutorial")
	await _click("NextWeek")
	await _frames(8)
	_check(Onboarding.current(screen.session.state).step == 3 and _visible("TurnDetails"), "after a week the tutorial points at the result details")
	await _click("SkipTutorial")
	_check(not _visible("TutorialCoach"), "tutorial can be skipped")


## 예전 규칙으로 진행 중이던 저장도 새 화면에서 이어서 할 수 있다.
func _legacy_run() -> void:
	await _fresh("legacy")
	screen.session.start_run(61427, "settler", {"region":"forest", "candidate":0, "relics":["seeds", "axe"], "tutorial":false, "cabinet":true, "campaign":true, "workcrew":true})
	screen.session.choose_perk(str(screen.session.state.perk_offer[0]))
	screen.page = "estate"
	screen._render()
	await _frames()
	var s: Dictionary = screen.session.state
	_check(not RealmRules.enabled(s) and _visible("OfficeDesk") and _visible("side_tab_projects"), "an old-rules run renders on the map screen")
	_check(RealmBoard.lot_kind(s, screen.session.content, "B16") == "locked" and RealmBoard.lot_kind(s, screen.session.content, "B27") == "locked", "old-rules run keeps its own unlock rules on the map")
	await _click("nav_policy")
	_check(not _visible("policy_militia") and _visible("ration_90"), "policies are hidden for an old-rules run; rations remain")
	await _click("nav_build")
	await _click("lot_B22")
	_check(_visible("build_B22") and not _visible("build_B33"), "legacy site allows only its original valid construction")
	await _click("nav_estate")
	await _click("side_tab_projects")
	_check(_visible("FocusAction"), "old-rules recommended construction remains reachable in the projects tab")
	await _click("FocusAction")
	await _click("build_B13")
	await _click("side_tab_overview")
	await _click("NextWeek")
	_check(int(s.week) == 2 and SaveStore.valid(screen.session.bundle()), "old-rules run advances and saves from the new screen")
