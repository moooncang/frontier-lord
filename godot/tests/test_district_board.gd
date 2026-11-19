extends SceneTree
## 실제 지구 전환·포인터·독립 도트 자산·읽기 전용 렌더링 검사.
var checks := 0
var failures := 0
var board: RealmBoard
var session: GameSession
var clicks: Array = []

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DISTRICT BOARD FAIL: ",message)

func frames(n: int = 4) -> void:
	for i in n: await process_frame

func pointer(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	root.push_input(move,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
		await process_frame

func shot(name_value: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	check(frame.get_size() == root.size,"native screenshot size")
	frame.save_png("res://tests/output/district_"+name_value+".png")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var content := Content.load_all()
	session = GameSession.new(content)
	session.start_run(61427,"settler",{"realm":true,"village_relics":true,"cabinet":true})
	var bank := AssetBank.new(content.assets)
	var backdrop := ColorRect.new()
	backdrop.color = Color("172124")
	backdrop.size = Vector2(1280,720)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	board = RealmBoard.new()
	board.position = Vector2(26,30)
	board.size = Vector2(820,500)
	board.theme = RealmTheme.create(bank.body_font())
	board.lot_selected.connect(func(id: String): clicks.append(id))
	root.add_child(board)
	for id in content.facilities:
		if id.begins_with("B"): session.state.facilities[id] = 1
	session.state.projects.clear()
	session.state.orders.clear()
	var unchanged := JSON.stringify(session.state)
	board.configure(bank,session.state,content,"",true)
	await frames()
	check(board.lots.size() == 22,"full facility model retained")
	for district in RealmBoard.DISTRICTS:
		board.set_district(district)
		await frames()
		var visible_count := 0
		for id in board.lots:
			var button: Button = board.lots[id]
			var expected: bool = RealmBoard.district_for(id) == district
			check(button.visible == expected,"only current district is interactive: "+id)
			if not expected: continue
			visible_count += 1
			check(Rect2(Vector2.ZERO,board.size).encloses(button.get_rect()),"lot inside scene: "+id)
			check(button.get_node("Art").texture is AtlasTexture,"dedicated composable sprite: "+id)
			check(button.get_node("Art").texture.resource_path.begins_with("res://assets/frontier_v2/"),"new sprite asset: "+id)
			var previous := clicks.size()
			await pointer(board.get_lot_rect(id).get_center())
			check(clicks.size() == previous+1 and clicks.back() == id,"real pointer resolves correct building: "+id)
		check(visible_count <= 6,"at most six facility plots per district")
		check(board.shrine.visible == (district == "civic"),"shrine belongs to village district")
		await shot(district+"_720")
	board.configure(bank,session.state,content,"B33",false)
	await frames()
	check(board.district == "industry","direct facility selection opens its district")
	var previous := clicks.size()
	await pointer(board.get_lot_rect("B33").get_center())
	check(clicks.size() == previous,"disabled board blocks commands")
	check(JSON.stringify(session.state) == unchanged,"rendering and pointer never alter economic state")
	var fresh := GameSession.new(content)
	fresh.start_run(61427,"settler",{"realm":true,"village_relics":true,"cabinet":true})
	board.configure(bank,fresh.state,content,"B22",true)
	await frames()
	check(board.lots.B22.get_node("Art").texture.resource_path.ends_with("building_t_granary.tres"),"temporary storage has a real temporary sprite")
	check(not board.lots.B19.visible,"locked facilities stay hidden")
	board.show_plans = true
	board.configure(bank,fresh.state,content,"B22",true)
	await frames()
	check(board.lots.B19.visible,"plan inspection reveals locked future facility")
	root.size = Vector2i(1440,900)
	backdrop.size = Vector2(root.size)
	board.size = Vector2(980,650)
	await frames()
	await shot("plans_900")
	for item in [[27,"autumn"],[40,"winter"]]:
		fresh.state.week = item[0]
		board.configure(bank,fresh.state,content,"B22",true)
		await frames()
		check(board.backdrop.resource_path.ends_with("district_"+item[1]+".png"),"season uses dedicated aligned terrain")
		if int(item[0]) == 40:
			check(board.lots.B13.get_node("Art").texture.resource_path.ends_with("building_farm_winter.tres"),"winter farm shows harvested stubble, not standing grain")
			check(board.lots.B14.get_node("Art").texture.resource_path.ends_with("building_garden_winter.tres"),"winter garden shows dormant beds")
		await shot(str(item[1])+"_900")
	print("DISTRICT BOARD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
