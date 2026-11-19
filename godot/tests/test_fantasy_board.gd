extends "res://tests/test_district_board.gd"
## Presentation fixtures adopt real offers, then vary completed construction for visual assertions.
## Economic legality and real construction are covered separately by fantasy_frontiers/replay.

func _new_for(path: String) -> GameSession:
	for seed_value in range(1,100):
		var game := GameSession.new(Content.load_all())
		game.start_run(seed_value,"settler",{"realm":true,"cabinet":true,"workcrew":true,"village_relics":true,"fantasy":true})
		if str(game.state.fantasy.plan[0].id) != path: continue
		for key in game.state.public: game.state.public[key] = 5000.0
		game.state.public.money = 100000
		game.state.resident.food = 5000.0
		game.state.resident.money = 100000
		return game
	return null

func _settle_choices(game: GameSession) -> void:
	for attempt in 30:
		if not game.state.perk_offer.is_empty():
			game.choose_perk(str(game.state.perk_offer[0]))
			continue
		var offers: Array = game.state.get("realm",{}).get("sanctuary",{}).get("offer",[])
		if not offers.is_empty():
			game.choose_relic(str(offers[0]))
			continue
		if str(game.state.active_event) == "": break
		var event := RealmRules.event_definition(game.state,game.content,str(game.state.active_event))
		var choice := -1
		for index in event.options.size():
			if game.option_error(event.options[index]) == "": choice = index; break
		check(choice >= 0,"fixture event has an available decision")
		if choice < 0: break
		check(game.choose_event(choice) == "","fixture uses real event adoption")

func _reach_paths(game: GameSession, count: int) -> void:
	for attempt in 28:
		_settle_choices(game)
		if FantasyFrontiers.overview(game.state,game.content).selected.size() >= count: return
		game.advance()
	check(false,"reached requested covenant count")

func _board_snapshot() -> Dictionary:
	var picture := {}
	for id in board.lots:
		var button: Button = board.lots[id]
		if button.visible: picture[id] = button.get_rect()
	return picture

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.unresizable = true
	root.size = Vector2i(1280,720)
	var data := Content.load_all()
	var bank := AssetBank.new(data.assets)
	var background := ColorRect.new()
	background.color = Color("172124")
	background.size = Vector2(root.size)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	board = RealmBoard.new()
	board.position = Vector2(26,30)
	board.size = Vector2(1228,650)
	board.theme = RealmTheme.create(bank.body_font())
	board.lot_selected.connect(func(id: String): clicks.append(id))
	root.add_child(board)
	for path in RealmBoard.FANTASY_LOTS:
		session = _new_for(path)
		check(session != null,"seed can discover "+path)
		if session == null: continue
		_reach_paths(session,1)
		var ids: Array = RealmBoard.FANTASY_LOTS[path]
		board.show_plans = true
		board.configure(bank,session.state,data,str(ids[0]),true)
		await frames()
		check(board.district == "fantasy","selected new building enters its own district")
		check(board.lots.size() == 25,"only three adopted path plots are added")
		check(board.district_lots() == ids,"one covenant occupies one coherent row")
		check(not board.backdrop.resource_path.contains("fantasy_v1"),"adoption alone does not claim the landscape was rebuilt")
		check(board.secondary_backdrop == null,"one covenant needs no second terrain")
		session.state.facilities[ids[0]] = 1
		board.configure(bank,session.state,data,str(ids[0]),true)
		await frames()
		check(board.backdrop.resource_path.ends_with("district_"+path+".png"),"first completed building transforms its landscape")
		check(board.fantasy_stages[path] == 1,"one complete building gives exactly one visual stage")
		for id in ids: session.state.facilities[id] = 1
		var original := JSON.stringify(session.state)
		board.configure(bank,session.state,data,str(ids[2]),true)
		await frames()
		check(board.fantasy_stages[path] == 3,"three completed buildings give the final landscape stage")
		for id in ids:
			var button: Button = board.lots[id]
			check(button.visible and Rect2(Vector2.ZERO,board.size).encloses(button.get_rect()),"new plot and nameplate remain inside the board: "+id)
			var art: TextureRect = button.get_node("Art")
			check(art.texture is AtlasTexture and art.texture.resource_path.contains("fantasy_v1"),"dedicated independent pixel art: "+id)
			check(button.get_node("Plate").text == data.facilities[id].name,"correct Korean building name: "+id)
			var previous := clicks.size()
			await pointer(button.get_global_rect().get_center())
			check(clicks.size() == previous+1 and clicks.back() == id,"real pointer selects correct new facility: "+id)
		await shot("fantasy_"+path+"_720")
		board.set_district(str(RealmBoard.FANTASY_DISTRICTS[path]))
		await frames()
		check(board.backdrop.resource_path.ends_with("district_"+path+".png"),"final development also transforms its related ordinary district")
		check(JSON.stringify(session.state) == original,"drawing never changes resources, progression or random state")
	# Two paths have separate rows and matching terrain regions.
	session = _new_for("grove")
	_reach_paths(session,2)
	var chosen: Array = FantasyFrontiers.overview(session.state,data).selected
	for path in chosen:
		for id in RealmBoard.FANTASY_LOTS[path]: session.state.facilities[id] = 1
	root.size = Vector2i(1440,900)
	background.size = Vector2(root.size)
	board.size = Vector2(1388,820)
	board.configure(bank,session.state,data,str(RealmBoard.FANTASY_LOTS[chosen[0]][0]),true)
	await frames(15)
	check(board.lots.size() == 28 and board.district_lots().size() == 6,"two adopted paths create exactly six specialty plots")
	check(board.secondary_backdrop != null and board.secondary_backdrop.resource_path.ends_with("district_"+str(chosen[1])+".png"),"second path has its own independent terrain")
	var areas := _board_snapshot()
	for id in areas:
		for other in areas:
			if other != id: check(not areas[id].intersects(areas[other]),"building hitboxes never overlap")
	await shot("fantasy_dual_900")
	# Limited inputs produce a real partial-operation report, which the map must disclose.
	for key in ["wood","stone","tools","fuel"]: session.state.public[key] = 0.1
	var production := RealmRules.produce(session.state,data,int(session.state.week),0,50,1.0)
	session.state.labor_report["realm_operations"] = production.operations
	session.state.labor_report["realm_by"] = production.by
	board.configure(bank,session.state,data,"",true)
	await frames()
	var partial := false
	for id in production.operations:
		var operation: Dictionary = production.operations[id]
		if operation.status != "operating" or operation.missing.is_empty(): continue
		partial = true
		check(board.lots[id].get_node("Chip").text == "재료 부족 · 일부 가동","partial production is not presented as full operation")
		check(board.lots[id].tooltip_text.contains("직전 주 부족 재료"),"the affected building explains the actual missing inputs")
	check(partial,"real production supplies a material-limited fixture")
	# Reusing the same node for a legacy save clears all old fantasy plots.
	var legacy := GameSession.new(data)
	legacy.start_run(61427,"settler",{"realm":true,"cabinet":true})
	var before := JSON.stringify(legacy.state)
	board.configure(bank,legacy.state,data,"",true)
	await frames()
	check(board.district == "civic" and board.lots.size() == 22,"reused board removes the previous run's special plots")
	board.set_district("fantasy")
	check(board.district == "civic","legacy run cannot enter a phantom district")
	check(JSON.stringify(legacy.state) == before,"legacy save is not upgraded through rendering")
	print("FANTASY BOARD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
