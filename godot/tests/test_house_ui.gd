extends "res://tests/test_realm_playflow.gd"
## Native pointer checks use isolated saves. Funding and unlocked catalogs below are explicit UI fixtures.

var expected_size := Vector2i(1280,720)


func _resolution(dimensions: Vector2i) -> void:
	expected_size = dimensions
	root.mode = Window.MODE_WINDOWED
	root.unresizable = true
	root.size = dimensions
	if DisplayServer.get_name() != "headless": root.position = Vector2i(40,40)
	await _frames(20)
	_check(root.size == dimensions,"house viewport matches requested size")


func _shot(tag: String) -> void:
	await _frames(10)
	_check(root.size == expected_size,"house screenshot has intended viewport: "+tag)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and picture.get_size() == expected_size,"house screenshot pixels have intended resolution: "+tag)
	if picture != null: _check(picture.save_png("res://tests/output/house_"+tag+".png") == OK,"saved house screenshot: "+tag)


func _detail_bounds(context: String) -> void:
	for id in ["TalentCurrent","TalentNext","TalentPrerequisite","TalentCost","TalentApplication","BuyTalent"]:
		_check(_inside(_control(id)),"fixed house decision field is readable: "+context+" / "+id)
	for label in _control("TalentDetail").find_children("*","Label",true,false):
		_check(label.get_theme_font_size("font_size") >= 18,"house body remains at least 18px: "+context)
	var words := _text(_control("LegacyBoard"))
	for old in ["성장점","영구 강화","영구 재능","출정","시작 장비"]:
		_check(not words.contains(old),"house uses current Korean vocabulary: "+old)


func _run() -> void:
	await _resolution(Vector2i(1280,720))
	await _fresh("house_ui")
	await _click("OpenArchive")
	_check(_control("BuyTalent").disabled and _control("RefundTalents").disabled,"empty profile clearly cannot buy or refund")
	_check(_control("HouseBranches").find_children("legacy_branch_*","Button",true,false).size() == 6,"six house branches have direct text tabs")
	await _shot("01_empty_720")
	var view := LegacyPath.overview(screen.session.profile)
	_check(view.items.size() == 48 and view.legacy_upgrades.size() == 8,"all 56 actual purchasable items are reachable")
	for branch in view.branches:
		await _click("legacy_branch_"+str(branch.id))
		_check(_control("TalentTree").find_children("talent_*","Button",true,false).size() == 8,"branch narrows to eight nodes: "+str(branch.id))
		var path: Control = _control("HouseTrainingPath")
		_check(path != null and path.nodes.size() == 8,"branch renders eight connected training nodes")
		if path != null:
			var definitions: Dictionary = LegacyPath.definitions().talents
			for id in branch.items:
				_check(path.requirements[id] == definitions[id].requires,"training connector uses actual prerequisite: "+str(id))
				_check(_inside(path.nodes[id]),"every training node fits without scrolling: "+str(id))
		for id in branch.items:
			await _reveal("talent_"+str(id))
			await _click("talent_"+str(id))
			_detail_bounds(str(id))
		var scroll := _control("HouseListScroll") as ScrollContainer
		var position: int = scroll.scroll_vertical
		screen._render()
		await _frames(10)
		_check((_control("HouseListScroll") as ScrollContainer).scroll_vertical == position,"house selection keeps branch scroll: "+str(branch.id))
	await _shot("02_last_branch_720")
	await _resolution(Vector2i(1440,900))
	_detail_bounds("last branch at 900p")
	await _shot("02b_branch_900")
	await _resolution(Vector2i(1280,720))
	await _purchase_and_refund()
	await _choices_and_restart()
	print("HOUSE UI: %d checks, %d failures" % [checks,failures])
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)


func _purchase_and_refund() -> void:
	# Test funds are local to this isolated profile; prices are paid by the production commands.
	screen.session.profile.points = 5000
	screen._open_house_talent("LF01")
	await _frames()
	for index in 3: await _click("BuyTalent")
	_check(screen.session.profile.points == 4988 and LegacyPath.rank(screen.session.profile,"LF01") == 3,"existing LF01 keeps its three paid 2/4/6 ranks")
	_check(_control("BuyTalent").disabled,"maximum rank has no further purchase action")
	await _click("LegacyAdditional")
	_check(_control("TalentTree").find_children("meta_*","Button",true,false).size() == 8,"eight additional foundations are visible in the same entrance")
	await _reveal("meta_M01")
	await _click("meta_M01")
	await _click("upgrade_M01")
	_check("M01" in screen.session.profile.upgrades and screen.session.profile.points == 4980,"additional foundation pays its preserved cost")
	await _shot("03_additional_720")
	await _click("RefundTalents")
	_check(screen.session.profile.points == 4992 and screen.session.profile.legacy_talents.is_empty() and "M01" in screen.session.profile.upgrades,"respec refunds house ranks and preserves additional foundation ownership")
	await _click("LegacyPolicyManager")
	await _click("house_doctrine_LF07")
	_check(_control("DoctrineUnlockRoute") != null and _control("SelectDoctrine") == null,"buying a doctrine and selecting its effect are separate actions")
	await _click("DoctrineUnlockRoute")
	_check(screen.selected_talent == "LF07" and screen.house_branch == "finance","locked doctrine routes to its exact purchase node")
	# Unlock the complete catalog through production purchase commands for the remaining layout/selection checks.
	for iteration in 8:
		var changed := false
		for item in LegacyPath.overview(screen.session.profile).items:
			if item.rank < item.max_rank and screen.session.buy_talent(item.id) == "": changed = true
		if not changed: break
	_check(LegacyPath.overview(screen.session.profile).items.all(func(item): return item.rank == item.max_rank),"full fixture owns every actual house rank through valid purchases")
	screen._render()
	await _frames()
	await _click("LegacyPolicyManager")
	await _click("house_doctrine_LF07")
	await _click("SelectDoctrine")
	_check(_inside(_control("HouseLoadout")) and _text(_control("HousePlanSlot_0")).contains("긴축 재정"),"selected doctrine is reflected in the actual next-run loadout")
	await _click("house_doctrine_LA07")
	await _click("SelectDoctrine")
	var points: int = screen.session.profile.points
	await _reveal("house_doctrine_LS07")
	await _click("house_doctrine_LS07")
	_check(_inside(_control("replace_doctrine_LF07")) and _inside(_control("replace_doctrine_LA07")),"two occupied doctrine slots expose explicit replacement choices")
	_check(_inside(_control("DoctrineEffects")) and _control("DoctrineNext") == null,"doctrine effect is readable once rather than duplicated")
	await _shot("04_doctrine_replace_720")
	await _click("replace_doctrine_LF07")
	_check(screen.session.profile.legacy_doctrines == ["LS07","LA07"] and screen.session.profile.points == points,"replacing a doctrine changes only the selected two, without repurchasing")
	await _click("RemoveDoctrine")
	_check(screen.session.profile.legacy_doctrines == ["LA07"],"unselecting keeps the purchased doctrine available")
	await _click("SelectDoctrine")
	await _resolution(Vector2i(1440,900))
	await _shot("05_doctrines_900")
	await _click("house_setup_supply_packs")
	await _click("house_option_LA05")
	await _click("SelectPreparation")
	_check(screen.session.profile.legacy_preparation.supply_pack == "LA05","one unlocked support package can be selected separately from equipment budget")
	_check(_text(_control("HouseSupplySlot")).contains("식량 보급"),"support loadout reflects the actual selected package")
	await _shot("06_support_900")
	await _click("house_setup_perk_families")
	await _click("house_option_industry")
	await _click("SelectPreparation")
	_check(_text(_control("PreparationScope")).contains("첫 특전 제안에만"),"perk focus explicitly applies to the first offer only")
	await _click("house_setup_relic_families")
	await _click("house_option_guard")
	await _click("SelectPreparation")
	_check(_text(_control("PreparationScope")).contains("첫 성물 발견에만"),"relic focus explicitly applies to the first discovery only")
	await _resolution(Vector2i(1280,720))
	await _shot("07_first_relic_720")


func _choices_and_restart() -> void:
	var chosen: Dictionary = screen.session.profile.legacy_preparation.duplicate(true)
	var doctrines: Array = screen.session.profile.legacy_doctrines.duplicate()
	_check(SaveStore.valid(screen.session.bundle()) and screen.store.read().ok,"all house purchases and selections persist as valid saves")
	var directory: String = screen.save_directory
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.save_directory = directory
	root.add_child(screen)
	await _frames(12)
	_check(not screen.load_blocked and screen.session.profile.legacy_preparation == chosen and screen.session.profile.legacy_doctrines == doctrines,"profile reload preserves exact chosen doctrines and support")
	await _click("NewRun")
	screen.guide_enabled = false
	screen.draft_seed = 61427
	await _click("PrepareNext")
	await _click("PrepareNext")
	_check(_inside(_control("SetupHouseChoices")) and _inside(_control("StartRun")),"house review and start remain visible in the existing three-step preparation")
	_check(_inside(_control("HouseSetupDoctrines")) and _inside(_control("HouseSetupSupport")),"actual chosen doctrine and support names appear before starting")
	await _shot("08_prepare_720")
	await _click("SetupHouseChoices")
	await _click("LegacySetupBack")
	_check(screen.page == "prepare" and screen.prepare_step == 2,"review returns to the same preparation step")
	await _click("StartRun")
	var state: Dictionary = screen.session.state
	_check(state.legacy_setup.doctrines == doctrines and state.legacy_setup.preparation == chosen,"real new run freezes the reviewed house configuration")
	_check(state.perk_offer.any(func(id): return screen.session.content.progression.perks[id].family == "industry"),"actual first perk offer honors the selected family")
	var old_offer: Array = state.perk_offer.duplicate()
	var excluded: String = old_offer[0]
	_check(_inside(_control("banish_perk_"+excluded)),"unlocked candidate removal is reachable at 720p")
	await _shot("09_banish_720")
	await _click("banish_perk_"+excluded)
	_check(excluded in state.legacy_setup.banished_perks and excluded not in state.perk_offer and old_offer[1] in state.perk_offer and old_offer[2] in state.perk_offer,"real exclusion keeps the other two offered perks")
	await _click("perk_"+str(state.perk_offer[0]))
	await _settle()
	_check(VillageRelics.request_offer(state,screen.session.content,"house_ui_discovery") == "","valid discovery supplies the relic offer for UI checks")
	screen.decision_hidden = false
	screen._render()
	await _frames(12)
	_check(_inside(_control("RefreshRelics")),"unlocked relic refresh is reachable at 720p")
	await _shot("10_relic_refresh_720")
	await _click("RefreshRelics")
	_check(state.legacy_setup.relic_refreshes == 0 and state.realm.sanctuary.offer.any(func(id): return VillageRelics.definitions().relics[id].category == "guard"),"real first relic refresh consumes one use and preserves first-family guarantee")
	await _click("take_relic_"+str(state.realm.sanctuary.offer[0]))
	await _settle()
	var resources: Dictionary = state.public.duplicate(true)
	var setup: Dictionary = state.legacy_setup.duplicate(true)
	screen._go("archive")
	await _frames()
	_check(_control("BuyTalent").disabled and _control("RefundTalents").disabled,"current run locks house purchases and respec")
	await _click("LegacyPolicyManager")
	await _click("house_doctrine_LA07")
	_check(_control("RemoveDoctrine").disabled,"current run cannot change its selected doctrine snapshot")
	_check(state.public == resources and state.legacy_setup == setup and SaveStore.valid(screen.session.bundle()),"viewing house choices cannot reapply rewards or alter the active run")
	await _shot("11_active_lock_720")
