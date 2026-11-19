extends "res://tests/test_house_ui.gd"
## New-run difficulty and all four optional seasonal investments through real main UI buttons.


func _shot(tag: String) -> void:
	await _frames(10)
	_check(root.size == expected_size,"support screenshot viewport: "+tag)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and picture.get_size() == expected_size,"support screenshot pixels: "+tag)
	if picture != null: _check(picture.save_png("res://tests/output/support_"+tag+".png") == OK,"saved support screenshot: "+tag)


func _run() -> void:
	await _resolution(Vector2i(1280,720))
	await _fresh("season_support_ui")
	await _click("NewRun")
	screen.guide_enabled = false
	screen.draft_seed = 61427
	await _click("PrepareNext")
	await _reveal("OpenFrontierDifficulty")
	await _click("OpenFrontierDifficulty")
	_check(_control("FrontierLevels").find_children("difficulty_*","Button",true,false).size() == 6,"all six difficulty levels can be inspected")
	await _click("difficulty_5")
	_check(_control("ConfirmFrontierDifficulty").disabled and screen.draft_difficulty == 0,"locked difficulty can be read without selecting it")
	_check(_text(_control("FrontierRuleText")).split("\n").size() >= 5,"highest difficulty exposes all five cumulative rules")
	for id in ["FrontierRuleText","FrontierReward","FrontierLocked","ConfirmFrontierDifficulty"]: _check(_inside(_control(id)),"difficulty detail remains readable at 720p: "+id)
	await _shot("01_difficulty_locked_720")
	await _resolution(Vector2i(1440,900))
	await _shot("02_difficulty_900")
	# A completed legacy receipt is a deliberate fixture: it unlocks level one without rewriting purchases.
	screen.session.profile.receipts["support_old_completion"] = {"reason":"완주","success":true,"week":52,"points":20}
	screen._render()
	await _frames()
	await _click("difficulty_1")
	await _click("ConfirmFrontierDifficulty")
	_check(screen.page == "prepare" and screen.prepare_step == 1 and screen.draft_difficulty == 1,"confirmation preserves preparation step and selects an unlocked difficulty")
	await _resolution(Vector2i(1280,720))
	await _click("PrepareNext")
	await _click("StartRun")
	await _settle()
	_check(FrontierDifficulty.current(screen.session.state,screen.session.content).level == 1 and SeasonalInvestments.enabled(screen.session.state),"actual new-run configuration freezes difficulty and enables seasonal support")
	# Plenty of stores keeps this UI test independent of economy balance and event resource losses.
	await _until(7)
	_check(_inside(_control("OpenSeasonSupport")),"optional seasonal offer is reachable from the operating screen")
	var week: int = screen.session.state.week
	await _click("NextWeek")
	await _settle()
	_check(screen.session.state.week == week+1 and not screen.session.state.seasonal_support.offer.is_empty(),"an unanswered seasonal offer does not block time")
	await _click("OpenSeasonSupport")
	await _offer_bounds("spring")
	await _shot("03_spring_720")
	var stores: Dictionary = screen.session.state.public.duplicate(true)
	screen.session.state.public.food = 0.0
	screen._render()
	await _frames()
	_check(_control("buy_support_SS01").disabled and _visible("SupportError_SS01"),"insufficient public food disables purchase and explains the missing resource")
	await _shot("04_shortage_720")
	screen.session.state.public = stores
	screen._render()
	await _frames()
	var before: Dictionary = screen.session.state.public.duplicate(true)
	var gather := WeekSim.bonus(screen.session.state,"gather")
	await _click("buy_support_SS01")
	_check(is_equal_approx(screen.session.state.public.food,before.food-48) and screen.session.state.public.money == before.money,"actual spring purchase pays its exact public cost once")
	_check(is_equal_approx(WeekSim.bonus(screen.session.state,"gather"),gather*1.35),"selected support changes the live production multiplier")
	_check(_control("buy_support_SS01") == null and screen.session.state.seasonal_support.decisions.size() == 1,"purchased support cannot be bought a second time")
	_check(_inside(_control("ActiveSupportDuration")),"active support shows its expiration")
	await _shot("05_active_720")
	await _reload_active()
	await _until(14)
	_check(screen.session.state.seasonal_support.active.is_empty(),"spring support expires after processing week thirteen")
	await _until(20)
	await _click("OpenSeasonSupport")
	await _offer_bounds("summer")
	await _resolution(Vector2i(1440,900))
	await _shot("06_summer_900")
	before = screen.session.state.public.duplicate(true)
	await _click("DeclineSeasonSupport")
	_check(screen.page == "estate" and screen.session.state.public == before and screen.session.state.seasonal_support.decisions[-1].id == "","real decline closes the offer without charging stores")
	await _until(33)
	await _resolution(Vector2i(1280,720))
	await _click("OpenSeasonSupport")
	await _offer_bounds("autumn")
	await _shot("07_autumn_720")
	await _click("CloseSeasonSupport")
	await _until(37)
	await _click("OpenSeasonSupport")
	_check(_control("buy_support_SS07").disabled and _text(_control("SupportError_SS07")).contains("수확"),"late autumn cannot sell a support effect after its last useful harvest")
	await _click("DeclineSeasonSupport")
	await _until(46)
	await _click("OpenSeasonSupport")
	await _offer_bounds("winter")
	_check(_text(_control("SupportStores")).contains("장작"),"winter support shows available fuel before a fuel purchase")
	await _shot("08_winter_720")
	await _click("buy_support_SS10")
	_check(screen.session.state.seasonal_support.active.id == "SS10","winter support is actually purchasable")
	await _click("CloseSeasonSupport")
	await _until(53)
	screen._go("result")
	await _frames()
	_check(screen.session.state.result.difficulty_level == 1 and screen.session.state.result.difficulty_points == 2,"difficulty bonus is recorded in actual end-of-run settlement")
	_check(_inside(_control("DifficultyResult")) and _inside(_control("NextFrontierGoal")),"settlement shows difficulty reward and a concrete next goal")
	await _shot("09_result_720")
	print("SEASON SUPPORT UI: %d checks, %d failures" % [checks,failures])
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)


func _offer_bounds(context: String) -> void:
	var view := SeasonalInvestments.overview(screen.session.state,screen.session.content)
	_check(view.offer.size() == 3,"season offers exactly three choices: "+context)
	for item in view.offer:
		for prefix in ["SupportCost_","SupportUntil_","buy_support_"]:
			_check(_inside(_control(prefix+item.id)),"fixed support cost/duration/action is inside viewport: "+context+" / "+prefix)
		var art := _control("SupportArt_"+item.id) as TextureRect
		_check(art != null and art.texture != null,"support has its result building image: "+item.id)
		_check(_inside(art),"support building image fits card: "+item.id)
	_check(_inside(_control("DeclineSeasonSupport")) and _inside(_control("CloseSeasonSupport")),"support remains optional with reachable back/decline actions")


func _until(target_week: int) -> void:
	if screen.page != "estate": screen._go("estate"); await _frames()
	while screen.session.state.week < target_week and screen.session.state.status == "active":
		var state: Dictionary = screen.session.state
		state.public.money = 100000
		state.public.food = 5000.0
		state.public.fuel = 1000.0
		state.public.tools = 100.0
		state.public.wood = 1000.0
		state.public.stone = 1000.0
		# Real UI time input keeps modal priority, feedback, and autosave in this integration path.
		await _click("NextWeek")
		await _settle()
	_check(screen.session.state.week == target_week,"real week input reaches support boundary %d" % target_week)


func _reload_active() -> void:
	var chosen: Dictionary = screen.session.state.seasonal_support.duplicate(true)
	var resources: Dictionary = screen.session.state.public.duplicate(true)
	var directory: String = screen.save_directory
	_check(SaveStore.valid(screen.session.bundle()) and screen.store.read().ok,"support purchase produced a readable valid save")
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.save_directory = directory
	root.add_child(screen)
	await _frames(12)
	await _click("ContinueRun")
	await _settle()
	_check(SaveStore._normalize(screen.session.state.seasonal_support) == SaveStore._normalize(chosen),"reload restores exact support choice and duration")
	for asset in resources:
		_check(is_equal_approx(float(screen.session.state.public[asset]),float(resources[asset])),"reload cannot charge or award support stores again: "+str(asset))
