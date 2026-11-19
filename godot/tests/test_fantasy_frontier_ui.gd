extends "res://tests/test_realm_playflow.gd"
## Actual discovery -> adoption -> construction flow. Save files and native windows are isolated.

var expected_size := Vector2i(1280,720)

func _resolution(value: Vector2i) -> void:
	root.mode = Window.MODE_WINDOWED
	root.unresizable = true
	root.size = value
	expected_size = value
	await _frames(15)
	_check(root.size == value,"actual fantasy viewport: "+str(value))

func _shot(tag: String) -> void:
	await _frames(10)
	_check(root.size == expected_size,"fantasy screenshot keeps the requested viewport: "+tag)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and picture.get_size() == expected_size,"native fantasy image dimensions: "+tag)
	if picture != null: _check(picture.save_png("res://tests/output/fantasy_ui_"+tag+".png") == OK,"saved "+tag)

func _open_changes() -> void:
	await _click("MoreActions")
	await _click("more_fantasy_frontier")
	_check(screen.page == "fantasy_frontier" and _visible("FantasyFrontierPage"),"actual command menu opens the frontier overview")

func _path(id: String) -> Dictionary:
	for row in FantasyFrontiers.overview(screen.session.state,screen.session.content).paths:
		if row.id == id: return row
	return {}

func _fantasy_option(action: String = "") -> int:
	if screen.session.state.active_event == "": return -1
	var event: Dictionary = RealmRules.event_definition(screen.session.state,screen.session.content,screen.session.state.active_event)
	for index in event.options.size():
		var payload: Dictionary = event.options[index].get("fantasy",{})
		if not payload.is_empty() and (action == "" or payload.get("action") == action): return index
	return -1

func _run() -> void:
	await _resolution(Vector2i(1280,720))
	await _fresh("fantasy_frontiers")
	await _start(false)
	await _settle()
	var view: Dictionary = FantasyFrontiers.overview(screen.session.state,screen.session.content)
	_check(view.enabled and view.paths.size() == 6 and view.selected.is_empty(),"new UI run enables six discoverable directions without silently adopting one")
	await _open_changes()
	_check(_control("FantasyPathScroll").find_children("fantasy_path_*","Button",true,false).size() == 6,"all six directions can be inspected")
	for id in ["FantasyBenefit","FantasyTradeoff","FantasyConstructionCost","FantasyGoSite","BackEstate"]:
		_check(_inside(_control(id)),"essential meaning and fixed actions fit at 720p: "+id)
	_check((_control("FantasyGoSite") as BaseButton).disabled,"unadopted directions cannot create a construction order")
	var week_before: int = screen.session.state.week
	var focus := root.gui_get_focus_owner()
	if focus != null: focus.release_focus()
	await _key(KEY_SPACE)
	_check(int(screen.session.state.week) == week_before,"reading growth directions cannot accidentally advance a week with Space")
	var before := JSON.stringify(screen.session.state)
	for path in view.paths:
		await _reveal("fantasy_path_"+str(path.id))
		await _click("fantasy_path_"+str(path.id))
		for building in path.buildings:
			await _click("fantasy_building_"+str(building.id))
			var art := _control("FantasyBuildingArt") as TextureRect
			_check(art != null and art.texture != null,"dedicated building has its actual pixel asset: "+str(building.id))
			_check(_inside(_control("FantasyConstructionCost")) and _inside(_control("FantasyGoSite")),"each building preserves fixed cost and action at 720p: "+str(building.id))
	await _reveal("fantasy_path_astral")
	var scroll := _control("FantasyPathScroll") as ScrollContainer
	var previous_scroll := scroll.scroll_vertical
	await _click("fantasy_path_astral")
	_check((_control("FantasyPathScroll") as ScrollContainer).scroll_vertical == previous_scroll,"inspecting a lower direction preserves the exact list scroll")
	_check(JSON.stringify(screen.session.state) == before,"inspection leaves all economic and random state unchanged")
	await _shot("01_undiscovered_720")
	await _click("BackEstate")
	await _click("build_B13")
	for attempt in 12:
		if _fantasy_option("accept") >= 0:
			if _visible("EventChoices"): break
			if not screen.session.state.perk_offer.is_empty():
				await _click("perk_"+str(screen.session.state.perk_offer[0]))
			elif _visible("AcknowledgeOutcome"): await _click("AcknowledgeOutcome")
			else: await _click("NextWeek")
			continue
		await _settle()
		if screen.session.state.status != "active": break
		await _click("NextWeek")
	var accept := _fantasy_option("accept")
	_check(accept >= 0,"real weekly progression reaches the first discovery choice")
	if accept < 0: await _finish(); return
	var event: Dictionary = RealmRules.event_definition(screen.session.state,screen.session.content,screen.session.state.active_event)
	var path_id: String = event.options[accept].fantasy.path
	var description := FantasyFrontiers.option_text(event.options[accept],screen.session.content)
	_check(not description.is_empty() and _text(_control("EventChoices")).contains(description),"adoption consequences are disclosed before choosing the event")
	await _reveal("event_option_%d" % accept)
	await _shot("02_discovery_event_720")
	await _click("event_option_%d" % accept)
	_check(_path(path_id).selected,"the actual event selection adopts the chosen direction")
	if _visible("AcknowledgeOutcome"):
		await _shot("03_adoption_result_720")
		await _click("AcknowledgeOutcome")
	await _settle()
	await _open_changes()
	await _reveal("fantasy_path_"+path_id)
	await _click("fantasy_path_"+path_id)
	var path := _path(path_id)
	var first_id: String = path.buildings[0].id
	await _click("fantasy_building_"+first_id)
	_check(_inside(_control("FantasyGoSite")) and not (_control("FantasyGoSite") as BaseButton).disabled,"adopted direction opens its actual construction site")
	_check(_inside(_control("FantasyNext")) and _inside(_control("FantasyProgress")),"next discovery condition and real completion count are visible before scrolling")
	_check(_text(_control("FantasyProgress")).contains("완공 0/3"),"adoption is distinguished from finished buildings")
	await _shot("04_adopted_direction_720")
	var stocks: Dictionary = screen.session.state.public.duplicate(true)
	await _click("FantasyGoSite")
	_check(screen.page == "build" and screen.active_district == "fantasy" and _visible("district_fantasy"),"new district is reachable only after adoption")
	_check(screen.selected_lot == first_id and _inside(_control("build_"+first_id)),"site selection exposes the exact permitted building and approval")
	var quote := CabinetActions.offer(screen.session,first_id)
	_check(quote.error == "" and _same_costs(quote.cost,path.buildings[0].cost),"frontier page uses the same real construction costs as approval")
	await _shot("05_site_720")
	await _click("build_"+first_id)
	_check(screen.session.state.orders.has(first_id) and screen.session.state.public == stocks,"approval reserves the permitted building without paying or granting its effect early")
	for attempt in 8:
		if int(screen.session.state.facilities.get(first_id,0)) > 0: break
		await _settle()
		await _click("NextWeek")
	await _settle()
	_check(int(screen.session.state.facilities.get(first_id,0)) == 1,"actual workers and weeks complete the first dedicated building")
	path = _path(path_id)
	_check(path.background_stage == 1 and path.buildings[0].built,"scenery progress follows real completion exactly once")
	_check(SaveStore.valid(screen.session.bundle()),"frontier discovery and construction remain saveable")
	await _click("side_tab_growth")
	_check(_inside(_control("OpenFantasyFrontier")),"growth pane keeps one clear frontier entry point")
	await _click("OpenFantasyFrontier")
	_check(_text(_control("FantasyOperation_"+first_id)).contains("다음 주"),"new production building distinguishes completion from its first operating week")
	await _shot("06_completed_720")
	await _click("BackEstate")
	for attempt in 6:
		if _fantasy_option("branch") >= 0 and _visible("EventChoices"): break
		await _settle()
		await _click("NextWeek")
	var branch_index := _fantasy_option("branch")
	_check(branch_index >= 0,"finishing a real building reaches the operating branch choice")
	if branch_index >= 0:
		var branch_event: Dictionary = RealmRules.event_definition(screen.session.state,screen.session.content,screen.session.state.active_event)
		var branch: String = branch_event.options[branch_index].fantasy.branch
		await _reveal("event_option_%d" % branch_index)
		await _shot("09_branch_event_720")
		await _click("event_option_%d" % branch_index)
		if _visible("AcknowledgeOutcome"): await _click("AcknowledgeOutcome")
		await _settle()
		_check(_path(path_id).branch == branch,"actual branch selection is reflected in the public overview")
	await _open_changes()
	await _reveal("fantasy_path_"+path_id)
	await _click("fantasy_path_"+path_id)
	if branch_index >= 0:
		_check(_inside(_control("FantasyBranchEffect")) and _text(_control("FantasyBranchEffect")) == str(_path(path_id).branch_text),"currently applied branch modifiers are visible and match the rules")
		await _shot("10_branch_active_720")
	await _resolution(Vector2i(1440,900))
	await _shot("07_completed_900")
	await _click("FantasyGoSite")
	await _shot("08_district_900")
	await _legacy()
	await _finish()

func _same_costs(a: Dictionary,b: Dictionary) -> bool:
	for key in ["money","wood","stone","tools","iron"]:
		if not is_equal_approx(float(a.get(key,0)),float(b.get(key,0))): return false
	return true

func _legacy() -> void:
	await _resolution(Vector2i(1280,720))
	await _fresh("fantasy_legacy")
	screen.session.start_run(61427,"settler",{"region":"forest","candidate":0,"relics":[],"realm":true,"cabinet":true,"campaign":true,"workcrew":true,"onboarding":false})
	screen.session.choose_perk(str(screen.session.state.perk_offer[0]))
	screen._go("estate")
	await _frames()
	await _click("nav_build")
	_check(not _visible("district_fantasy"),"legacy save gains no unexpected fantasy district")
	await _click("MoreActions")
	await _click("more_fantasy_frontier")
	_check(_visible("FantasyLegacy") and not _visible("FantasyGoSite"),"legacy route explains compatibility without exposing disabled progression")
	_check(not screen.session.state.has("fantasy") and SaveStore.valid(screen.session.bundle()),"inspecting legacy explanation never opts the old save into new rules")

func _finish() -> void:
	print("FANTASY FRONTIER UI: %d checks, %d failures" % [checks,failures])
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await _frames()
	quit(1 if failures > 0 else 0)
