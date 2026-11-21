extends "res://tests/test_realm_playflow.gd"
## 휴대폰 배치(세로 540줄, 가장 좁은 1120): 한 판의 주요 흐름을 끝까지 누를 수 있어야 한다.
## 목록 안의 것은 밀어서 닿으면 되고, 목록 밖의 단추는 화면 안에 다 들어와야 한다.

func _overview_bounds(_tag: String) -> void:
	pass

func _click(id: String) -> bool:
	await _reveal(id)
	return await super._click(id)

func _scrollable(item: Node) -> bool:
	var holder := item.get_parent()
	while holder != null:
		if holder is ScrollContainer: return true
		holder = holder.get_parent()
	return false

## 목록 밖에 놓인 단추가 화면 밖으로 밀려나지 않았는지 본다. 창이 떠 있으면 창 안만 본다.
func _fits(context: String) -> void:
	await _frames(8)
	var scope: Node = screen.current_modal if is_instance_valid(screen.current_modal) else screen
	var view := Rect2(Vector2.ZERO, Vector2(root.size)).grow(1)
	var lost: Array[String] = []
	for button in scope.find_children("*", "BaseButton", true, false):
		if not button.is_visible_in_tree() or _scrollable(button) or button.get_parent() is ScrollBar or button.get_parent() is SpinBox: continue
		if not view.encloses(button.get_global_rect()): lost.append(str(button.name))
	_check(lost.is_empty(), "every fixed button fits the phone screen [%s]: %s" % [context, ", ".join(lost)])
	await _shot("phone_" + context)

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.unresizable = true
	root.size = Vector2i(1120, 540)
	await _frames(10)
	await _fresh("phone")
	_check(screen.compact, "a 540-line screen draws the phone layout")
	await _fits("00_menu")
	await _click("OpenArchive")
	await _fits("01_house")
	await _click("LegacyPolicyManager")
	await _fits("02_house_plan")
	for tab in ["supply_packs", "perk_families", "relic_families"]:
		await _click("house_setup_" + tab)
		await _fits("02_house_" + tab)
	await _click("LegacySetupBack")
	screen._go("catalog")
	await _fits("03_records")
	var tallest := 0.0
	for scroll in screen.find_children("*", "ScrollContainer", true, false):
		if scroll.is_visible_in_tree(): tallest = maxf(tallest, scroll.size.y)
	_check(tallest >= 200, "the records list gets real height instead of collapsing (%d)" % tallest)
	screen._go("menu")
	await _frames()
	await _click("NewRun")
	screen.draft_seed = 61427
	screen.guide_enabled = false
	await _fits("04_lord")
	await _click("PrepareNext")
	await _fits("05_region")
	await _click("PrepareNext")
	await _fits("06_supplies")
	await _click("StartRun")
	await _fits("07_perk")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	_check(_inside(_control("OfficeDesk")) and _inside(_control("PolicyChoices")), "the office shows the desk and the work crew choice without scrolling")
	await _fits("08_office")
	await _click("nav_build")
	await _click("district_food")
	_check(screen.realm_board.size.x >= 600 and screen.realm_board.size.y >= 240, "the district scene stays large enough to tap lots (%s)" % str(screen.realm_board.size))
	await _click("lot_B13")
	await _fits("09_lot")
	await _click("build_B13")
	await _click("NextWeek")
	await _settle()
	await _click("TurnDetails")
	await _fits("10_receipt")
	await _click("CloseTurnDetails")
	await _click("MoreActions")
	await _fits("11_commands")
	await _click("CloseManagement")
	for target in ["trade", "policy", "people", "boons", "sanctuary", "journey", "ledger", "crises", "operating_builds", "season_support", "fantasy_frontier"]:
		screen._go(target)
		await _fits("12_" + target)
		_check(screen.page == target, "the page opens on the phone: " + target)
	screen._go("estate")
	screen.session.state.active_event = "RV_RAID"
	screen.decision_hidden = false
	screen._go("estate")
	await _fits("13_event")
	var options: int = screen.session.content.events["RV_RAID"].options.size() if screen.session.content.events.has("RV_RAID") else RealmRules.event_definition(screen.session.state, screen.session.content, "RV_RAID").options.size()
	for index in options:
		await _reveal("event_option_%d" % index)
		_check(_inside(_control("event_option_%d" % index)), "event choice %d can be brought into view" % index)
	await _click("event_option_1")
	await _fits("14_outcome")
	await _click("AcknowledgeOutcome")
	await _click("nav_menu")
	await _fits("15_menu_running")
	await _click("EndRun")
	var dialogs := screen.find_children("*", "ConfirmationDialog", true, false)
	if _check(dialogs.size() == 1, "ending the reign asks first on the phone too"): dialogs[0].confirmed.emit()
	await _frames()
	_check(screen.page == "result", "the result opens after ending the reign")
	await _fits("16_result")
	await _finish()
