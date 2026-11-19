extends "res://tests/test_expedition_ui.gd"
## Real commands can consume a reserved budget; failed weeks must explain why and remain recoverable.

class UnavailableStore extends SaveStore:
	func write(_bundle: Dictionary) -> String:
		return "저장 파일을 쓸 수 없습니다."


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WEEK FEEDBACK FAIL: ", message)


func _run() -> void:
	root.size = Vector2i(1280,720)
	save_path = "res://tests/output/week_feedback_%d" % Time.get_ticks_usec()
	screen = load("res://ui/main.tscn").instantiate()
	screen.set_script(load("res://ui/expedition_ui.gd"))
	screen.save_directory = save_path
	root.add_child(screen)
	await _frames()
	# A valid low-cash estate reproduces an ordinary late-run affordability conflict.
	screen.session.start_run(61427,"settler",{"region":"river","candidate":1,"relics":["seeds","seal"],"tutorial":false,"cabinet":true,"campaign":true,"workcrew":true,"onboarding":false})
	screen.session.choose_perk(screen.session.state.perk_offer[0])
	screen.session.state.public.money = 1000
	screen.page = "estate"
	screen._changed("예산 충돌 검증")
	await _frames()
	_check(SaveStore.valid(screen.session.bundle()),"low-cash fixture is a valid ordinary saved estate")
	await _click("FocusAction")
	_check(screen.session.state.orders.count("B13") == 2 and screen.session.state.public.money == 1000,"real approval reserves two farms without charging early")
	await _navigate("trade")
	var quote: int = screen.session.trade_quote("wood",40,true)
	await _click("supply_wood")
	_check(screen.session.state.public.money == 1000-quote and screen.session.state.shipments.size() == 1,"real supply purchase charges its quoted amount")
	_check(screen.session.state.public.money < 800 and screen.session.state.orders.size() == 2,"purchase leaves the already reserved project unaffordable")
	await _click("BackEstate")
	var before: Dictionary = screen.session.state.duplicate(true)
	await _click("NextWeek")
	_check(screen.session.state == before,"failed week changes no resources, ledger, workforce, receipts, rewards or time")
	_check(not screen.advance_error.is_empty() and "money" in screen.advance_error,"failed week retains its actual construction affordability error")
	_check(_visible("ActionNotice") and "금고" in _text("ActionNotice") and not "money" in _text("ActionNotice"),"failure reason is visible in player-facing Korean after all outer saves and renders")
	_check(SaveStore.valid(screen.session.bundle()) and screen.store.read().ok,"failure leaves a valid recoverable save")
	# Cancel both not-yet-started plots through the existing construction controls.
	await _navigate("build")
	await _click("ProjectDetails")
	for expected in [1,0]:
		var cancel: Button
		for button in screen.interface.find_children("*","Button",true,false):
			if button.text == "예약 취소":
				cancel = button
				break
		_check(cancel != null,"an unaffordable reservation has a visible cancellation action")
		if cancel != null: cancel.pressed.emit()
		await _frames()
		_check(screen.session.state.orders.size() == expected,"cancellation removes exactly one reservation")
	_check(screen.session.state.public.money == before.public.money and screen.session.state.shipments == before.shipments,"canceling an uncharged reservation neither invents refunds nor removes the purchased supply")
	await _click("BackEstate")
	await _click("NextWeek")
	_check(screen.session.state.week == 2 and screen.session.state.history.size() == 1,"correcting the reservation allows exactly one actual week")
	_check(screen.advance_error.is_empty() and not _visible("ActionNotice"),"successful retry clears the stale progression error")
	var recovered: Dictionary = screen.store.read()
	_check(recovered.ok and recovered.bundle.state.week == 2 and SaveStore.valid(recovered.bundle),"successful retry persists the new week")
	# Rendering policy forecasts repeatedly must not replay work or alter RNG/economy.
	var stable: Dictionary = screen.session.state.duplicate(true)
	for iteration in 4:
		screen._render()
		await _frames(2)
	_check(screen.session.state == stable,"repeated dashboard and four-policy forecasts preserve the completed state")
	# Storage failure is distinct: this week's economy completed, but its write failed.
	var real_store: SaveStore = screen.store
	screen.store = UnavailableStore.new()
	var week: int = screen.session.state.week
	await screen._advance(1)
	await _frames()
	_check(screen.session.state.week == week+1,"failed storage does not replay or roll back completed economic work")
	_check(screen.advance_error == "저장 파일을 쓸 수 없습니다.","storage failure survives all outer post-week saves")
	_check(_visible("ActionNotice") and screen.advance_error in _text("ActionNotice"),"storage failure is visible in the actual UI")
	screen.store = real_store
	_check(screen._save() and screen.store.read().bundle.state.week == week+1,"restored storage can persist the already completed week without advancing again")
	await _season_priority()
	print("WEEK FEEDBACK: %d checks, %d failures" % [checks,failures])
	screen.queue_free()
	await _frames()
	quit(1 if failures else 0)


func _season_priority() -> void:
	for iteration in 20:
		if screen.session.state.week >= 14: break
		await _resolve_decisions()
		var before: int = screen.session.state.week
		await screen._advance(1)
		await _frames()
		_check(screen.session.state.week == before+1,"season-priority fixture advances each actual week once")
	_check(screen.session.state.week == 14 and screen.show_season_result,"first actual seasonal evaluation leaves an acknowledgement pending")
	_check(not screen.session.state.perk_offer.is_empty() and _visible("PerkChoicesArea"),"the new seasonal perk takes visual priority over the seasonal receipt")
	var state: Dictionary = screen.session.state.duplicate(true)
	await _key(KEY_ESCAPE)
	_check(screen.show_season_result and screen.decision_hidden,"escaping a perk hides that decision without discarding the unseen seasonal result")
	_check(_visible("CloseSeasonResult") and not _visible("PerkChoicesArea"),"the waiting seasonal result can now be reviewed")
	await _key(KEY_ESCAPE)
	_check(not screen.show_season_result and not _visible("DecisionModal"),"escaping the actual seasonal modal acknowledges only that result")
	_check(screen.session.state == state,"modal acknowledgements change neither decisions, rewards nor completed time")
	await _click("NextWeek")
	_check(screen.session.state.week == 14 and _visible("PerkChoicesArea"),"unresolved perk still blocks the next week and remains accessible")
