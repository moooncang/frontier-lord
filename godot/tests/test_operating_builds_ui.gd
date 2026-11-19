extends "res://tests/test_realm_playflow.gd"
## Production pointer flows. Large inventories are explicit isolated layout fixtures; selections and weekly work use real commands.

var build_row: Dictionary
var family_perks: Array = []
var filler_relics: Array = []


func _resolution(dimensions: Vector2i) -> void:
	# Native render tests must not inherit a maximized window from the desktop.
	root.mode = Window.MODE_WINDOWED
	root.unresizable = true
	root.size = dimensions
	if DisplayServer.get_name() != "headless": root.position = Vector2i(40,40)
	await _frames(20)
	_check(root.size == dimensions,"native viewport matches requested resolution: " + str(dimensions))


func _shot(tag: String) -> void:
	await _frames(10)
	var expected := Vector2i(1440,900) if tag.ends_with("_900") else Vector2i(1280,720)
	_check(root.size == expected,"screenshot viewport matches its resolution label: " + tag + " " + str(root.size))
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty(),"rendered operating builds: " + tag)
	if picture != null: _check(picture.get_size() == expected,"actual image pixels match requested resolution: " + tag)
	if picture != null and not picture.is_empty(): _check(picture.save_png("res://tests/output/operating_"+tag+".png") == OK,"saved operating build screen: " + tag)


func _run() -> void:
	await _resolution(Vector2i(1280,720))
	await _fresh("operating_builds")
	await _start(false)
	await _settle()
	var rows := OperatingBuilds.overview(screen.session.state,screen.session.content)
	if not _check(rows.size() == 12,"all twelve real operating combinations are loaded"): await _finish(); return
	_check(VillageRelics.definitions().relics.size() == 48 and screen.session.content.progression.perks.size() == 96,"production catalogs contain 48 relics and 96 perks")
	build_row = rows[0]
	family_perks = screen.session.content.progression.perks.keys().filter(func(id): return screen.session.content.progression.perks[id].family == build_row.family)
	var connected: Array = []
	for item in rows: connected.append_array(item.relics)
	filler_relics = VillageRelics.definitions().relics.keys().filter(func(id): return id not in connected)
	# The fixture supplies a collection to inspect; the player still uses actual buttons for every tested command.
	var state: Dictionary = screen.session.state
	state.perks = [family_perks[0]]
	state.synergies = []
	state.realm.sanctuary.owned = VillageRelics.definitions().relics.keys()
	state.realm.sanctuary.equipped = [build_row.relics[0],filler_relics[0],filler_relics[1]]
	screen.session.profile.relic_discoveries = VillageRelics.definitions().relics.keys()
	RealmRules.refresh(state,screen.session.content)
	screen._side("growth")
	await _frames(12)
	_check(_inside(_control("OpenOperatingBuilds")),"growth tab exposes one readable combination entry point")
	await _click("OpenOperatingBuilds")
	_check(_control("OperatingBuildListScroll").find_children("operating_build_*","Button",true,false).size() == 12,"twelve combinations appear in the scrollable list")
	_check(_text(_control("OperatingBuildDetail")).contains("특전 1/2") and _text(_control("OperatingBuildDetail")).contains("1개 이상"),"detail distinguishes one of two alternative relics from two required perks")
	_check(_inside(_control("OperatingBuildEffect")) and _inside(_control("OperatingBuildProgress")),"actual combination benefit, cost and current progress are visible before scrolling")
	for id in ["BuildGoSanctuary","BuildGoPerks","BackEstate"]: _check(_inside(_control(id)),"combination actions remain fixed and visible at 720p: " + id)
	var before := JSON.stringify(state)
	await _shot("01_requirements_720")
	_check(JSON.stringify(state) == before,"opening and rendering combinations never mutate game state")
	var last: Dictionary = rows[-1]
	await _reveal("operating_build_"+str(last.id))
	var prior_scroll: int = (_control("OperatingBuildListScroll") as ScrollContainer).scroll_vertical
	await _click("operating_build_"+str(last.id))
	_check(prior_scroll > 0 and (_control("OperatingBuildListScroll") as ScrollContainer).scroll_vertical == prior_scroll,"selecting the final combination preserves list scroll")
	await _shot("02_last_combination_720")
	await _click("BackEstate")
	await _perk_activation()
	await _replacement_preview()
	await _catalog_filters()
	await _three_build_layout()
	await _actual_week_and_result()
	print("OPERATING BUILDS UI: %d checks, %d failures" % [checks,failures])
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)


func _perk_activation() -> void:
	var candidates: Array = [family_perks[1],family_perks[2],family_perks[3]]
	screen.session.state.perk_offer = candidates
	screen.decision_hidden = false
	screen._render()
	await _frames(12)
	for id in candidates:
		_check(_inside(_control("perk_"+str(id))),"three perk actions fit below their scrollable effects: " + str(id))
		_check(_inside(_control("PerkBuildImpact_"+str(id))) and _text(_control("PerkBuildImpact_"+str(id))).contains("선택 시 활성"),"automatic activation is visible without scrolling before choosing: " + str(id))
		_check(_text(_control("PerkBuildRoutes_"+str(id))).contains(str(build_row.name)) and _text(_control("PerkBuildRoutes_"+str(id))).contains("선택 시 활성"),"candidate names the contributed build and automatic activation: " + str(id))
	await _shot("03_perk_activation_720")
	await _click("perk_"+str(candidates[0]))
	_check(build_row.id in OperatingBuilds.active(screen.session.state,screen.session.content),"actual second-perk click activates the one-relic combination")
	await _click("side_tab_growth")
	_check(_text(_control("OperatingWorkspace")).contains(str(build_row.name)),"growth summary lists the actual active build")
	await _shot("04_growth_active_720")


func _replacement_preview() -> void:
	await _click("OpenOperatingBuilds")
	await _click("BuildGoSanctuary")
	screen.relic_collection = false
	screen.relic_family_filter = ""
	screen.selected_relic = str(filler_relics[2])
	screen._render()
	await _frames(12)
	var old_id: String = build_row.relics[0]
	var preview := _control("BuildChangePreview_"+old_id)
	_check(preview != null and preview.text.contains("해제") and preview.text.contains(str(build_row.name)),"replacement preview identifies the combination that will switch off")
	_check(_inside(_control("FixedBuildChangePreview")),"equipment change exposes lost combinations without scrolling")
	for id in screen.session.state.realm.sanctuary.equipped:
		_check(_inside(_control("replace_relic_"+str(id))),"replacement controls remain fixed below scrollable detail at 720p")
	await _reveal("BuildChangePreview_"+old_id)
	await _shot("05_replace_preview_720")
	await _click("replace_relic_"+old_id)
	_check(build_row.id not in OperatingBuilds.active(screen.session.state,screen.session.content),"real replacement removes the previewed build")
	screen.selected_relic = old_id
	screen._render()
	await _frames()
	await _reveal("BuildChangePreview_"+str(filler_relics[2]))
	_check(_text(_control("BuildChangePreview_"+str(filler_relics[2]))).contains("활성"),"putting the linked relic back previews activation")
	await _click("replace_relic_"+str(filler_relics[2]))
	_check(build_row.id in OperatingBuilds.active(screen.session.state,screen.session.content),"replacement reapplies the build without another approval step")
	_check(SaveStore.valid(screen.session.bundle()),"actual equipment and new combinations remain saveable")


func _catalog_filters() -> void:
	if not screen.relic_collection: await _click("RelicCollection")
	await _click("relic_filter_guard")
	_check(_control("RelicInventory").find_children("relic_pick_*","Button",true,false).size() == 16,"48-item codex narrows to sixteen guard relics")
	await _reveal("relic_pick_G16")
	var previous: int = (_control("RelicInventoryScroll") as ScrollContainer).scroll_vertical
	await _click("relic_pick_G16")
	_check(previous > 0 and (_control("RelicInventoryScroll") as ScrollContainer).scroll_vertical == previous,"selecting a lower filtered relic preserves exact scroll: %d → %d" % [previous,(_control("RelicInventoryScroll") as ScrollContainer).scroll_vertical])
	_check(_text(_control("RelicDetail")).contains(str(VillageRelics.definitions().relics.G16.name)),"last new relic has readable real details")
	await _shot("06_relic_filter_720")
	await _click("relic_filter_craft")
	await _click("relic_filter_guard")
	_check((_control("RelicInventoryScroll") as ScrollContainer).scroll_vertical == previous,"each relic family retains its own list position")
	await _resolution(Vector2i(1440,900))
	await _shot("07_relic_filter_900")
	await _click("SanctuaryBuilds")
	await _click("BuildGoPerks")
	if not screen.boon_catalog: await _click("PerkCatalogToggle")
	await _click("perk_filter_industry")
	var ids: Array = screen.session.content.progression.perks.keys().filter(func(id): return screen.session.content.progression.perks[id].family == "industry")
	_check(_control("PerkListScroll").find_children("perk_browse_*","Button",true,false).size() == 24,"96 perks narrow to twenty-four entries in one family")
	await _reveal("perk_browse_"+str(ids[-1]))
	previous = (_control("PerkListScroll") as ScrollContainer).scroll_vertical
	await _click("perk_browse_"+str(ids[-1]))
	_check(previous > 0 and (_control("PerkListScroll") as ScrollContainer).scroll_vertical == previous,"last perk selection preserves list position")
	_check(_text(_control("PerkCatalogDetail")).contains(ConciseCopy.perk_brief(str(ids[-1]),screen.session.content.progression.perks[ids[-1]])),"selected catalog perk retains every actual gain and downside")
	_check(_inside(_control("PerkOperatingBuilds")),"catalog keeps a fixed return to operating combinations")
	await _shot("08_perk_catalog_900")
	await _resolution(Vector2i(1280,720))
	await _shot("09_perk_catalog_720")
	await _click("PerkOperatingBuilds")
	_check(_inside(_control("OperatingBuildDetail")),"combination detail fits after a resize and navigation roundtrip")
	await _shot("10_combinations_720")


func _three_build_layout() -> void:
	var state: Dictionary = screen.session.state
	var builds: Dictionary = OperatingBuilds.definitions(screen.session.content).builds
	state.perks = screen.session.content.progression.perks.keys()
	state.realm.sanctuary.equipped = [builds.harvest_trade.relics[0],builds.timber_trade.relics[0],builds.garrison.relics[0]]
	screen.selected_relic = builds.winter_hearth.relics[0]
	screen.relic_collection = false
	screen.relic_family_filter = ""
	RealmRules.refresh(state,screen.session.content)
	screen._go("sanctuary")
	await _frames(12)
	_check(OperatingBuilds.active(state,screen.session.content).size() == 3,"three equipment slots can support three different real combinations")
	_check(_inside(_control("FixedBuildChangePreview")),"three simultaneous replace/remove previews remain visible at 720p")
	for id in state.realm.sanctuary.equipped: _check(_inside(_control("replace_relic_"+str(id))),"every replacement action fits with three active combinations: " + str(id))
	var effects := _control("RelicEffectScroll").get_parent() as ScrollContainer
	_check(effects.size.y >= 48,"three active combinations leave usable effect scrolling space: %dpx" % effects.size.y)
	await _shot("10b_three_build_replace_720")


func _actual_week_and_result() -> void:
	# One direct fixture establishes a logging estate; its resource conversion is then produced by a real NextWeek click.
	var game: GameSession = screen.session
	var timber: Dictionary = OperatingBuilds.definitions(game.content).builds.timber_trade
	var perks: Array = game.content.progression.perks.keys().filter(func(id): return game.content.progression.perks[id].family == timber.family)
	game.state.perks = [perks[0],perks[1]]
	game.state.realm.sanctuary.equipped = [timber.relics[0]]
	game.state.facilities.B25 = 1
	game.state.public.money = 20000
	game.state.public.wood = 200.0
	game.state.public.tools = 30.0
	game.state.public.food = 3000.0
	game.state.resident.food = 3000.0
	game.state.orders = []
	game.state.projects = []
	game.state.active_event = ""
	game.state.perk_offer = []
	WorkcrewRules.select(game.state,game.content,"balanced")
	RealmRules.refresh(game.state,game.content)
	screen._go("estate")
	await _frames()
	await _click("NextWeek")
	await _settle()
	var rows: Array = game.state.realm.sanctuary.last_result.get("builds",[])
	_check(rows.any(func(row): return row.id == "timber_trade"),"real completed week triggers the logging conversion")
	_check(game.state.ledger.any(func(row): return row.src == "build:timber_trade" and row.asset == "wood" and float(row.qty) < 0),"actual build result is backed by a paid resource ledger entry")
	await _click("TurnDetails")
	await _reveal("OperatingBuildResult_timber_trade")
	_check(_inside(_control("OperatingBuildResult_timber_trade")) and _text(_control("OperatingBuildResult_timber_trade")).contains("목재 -12"),"weekly receipt exposes actual consumed material and received reward")
	await _shot("11_weekly_conversion_720")
	await _key(KEY_ESCAPE)
	game.settle("은퇴")
	screen._go("result")
	await _frames(12)
	await _reveal("FinalBuild_timber_trade")
	_check(_inside(_control("FinalBuild_timber_trade")),"settlement lists the final active operating combination")
	await _shot("12_result_build_720")
	await _resolution(Vector2i(1440,900))
	await _reveal("FinalBuild_timber_trade")
	_check(_inside(_control("FinalBuild_timber_trade")),"settlement combination is readable after resizing to 900p")
	await _shot("13_result_build_900")
