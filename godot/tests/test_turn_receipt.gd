extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TURN RECEIPT FAIL: ", message)


func _init() -> void:
	content = Content.load_all()
	_test_first_week_and_purity()
	_test_boundaries()
	_test_construction_cash_and_work()
	_test_arrival_trial_and_rewards()
	_test_advisor_attribution()
	_test_unclassified_and_gross_flows()
	_test_save_validation()
	print("TURN RECEIPT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _state() -> Dictionary:
	return RunState.new_run(content.charters.C01, 9341)


func _game(campaign := false) -> GameSession:
	var game := GameSession.new(content)
	game.start_run(9341, "settler", {"candidate":0, "region":"forest", "relics":[], "tutorial":false, "cabinet":true, "campaign":campaign})
	game.state.perk_offer = []
	game.state.active_event = ""
	return game


func _row(receipt: Dictionary, id: String) -> Dictionary:
	for row in receipt.resource_rows:
		if row.id == id: return row
	return {}


func _record(game: GameSession, with_advisor := true) -> Dictionary:
	game.state.perk_offer = []
	game.state.active_event = ""
	var before := game.state.duplicate(true)
	var context := {"advisor":CabinetActions.advisor_definition(game, str(game.state.cabinet.advisor))}
	var report := game.advance()
	if with_advisor: report.receipt_context = context
	else: report.erase("receipt_context")
	var receipt := TurnReceipt.build(before, game.state, report)
	_check(TurnReceipt.valid(receipt) and TurnReceipt.valid(JSON.parse_string(JSON.stringify(receipt))), "actual game receipt is valid before save and after JSON restore")
	return receipt


func _test_first_week_and_purity() -> void:
	var after := _state()
	var before := after.duplicate(true)
	var report := WeekSim.process_week(after, content)
	var originals := [before.duplicate(true), after.duplicate(true), report.duplicate(true)]
	var receipt := TurnReceipt.build(before, after, report)
	var food := _row(receipt, "food")
	var money := _row(receipt, "money")
	_check(receipt.valid and receipt.week == 1 and before.history.is_empty(), "first completed week works without history snapshots")
	_check(is_equal_approx(food.before, 1800) and is_equal_approx(food.after, WeekSim.total_food(after)) and is_equal_approx(food.delta, food.after - food.before), "food combines public and resident balances")
	_check(is_equal_approx(food.production, 48) and is_equal_approx(food.consumption, 80) and food.spoilage > 0 and food.fully_explained, "production, positive consumption and spoilage remain separate")
	_check(is_equal_approx(food.income - food.expense, food.delta) and is_equal_approx(money.income - money.expense, money.delta), "actual gross flows reconcile to stock changes")
	_check(money.before == before.public.money and money.after == after.public.money, "money means public treasury only")
	_check(before == originals[0] and after == originals[1] and report == originals[2], "receipt construction never mutates states or report")
	_check(TurnReceipt.build(before, after, report) == receipt, "rebuilding is deterministic")
	var restored = JSON.parse_string(JSON.stringify(receipt))
	_check(restored is Dictionary and restored.valid and restored.week == receipt.week and restored.resource_rows.size() == 7 and is_equal_approx(_row(restored,"food").delta, food.delta) and restored.notes == receipt.notes, "receipt values survive JSON save and restore")
	receipt.notes.append("changed")
	food.by_source.gather = 999
	_check(before == originals[0] and after == originals[1] and report == originals[2], "returned collections do not alias original records")


func _test_boundaries() -> void:
	var before := _state()
	var after := before.duplicate(true)
	var rejected := TurnReceipt.build(before, after, {"advanced":false, "notes":["자재 부족"]})
	_check(not rejected.valid and rejected.resource_rows.is_empty() and rejected.notes == ["자재 부족"], "blocked action has no fictitious completed-week result")
	after.week = 3
	_check(not TurnReceipt.build(before, after, {"advanced":true, "week":1}).valid, "multi-week or wrong before snapshot rejects")
	after.week = 2
	after.run_id = "another-run"
	_check(not TurnReceipt.build(before, after, {"advanced":true, "week":1}).valid, "different runs cannot be compared")
	after.run_id = before.run_id
	before.ledger = [{"w":1,"src":"trade_buy","asset":"money","qty":-300}]
	after.ledger = []
	_check(not TurnReceipt.build(before, after, {"advanced":true,"week":1}).valid, "truncated ledger does not silently fall back to week matching")
	after.ledger = [{"w":1,"src":"trade_buy","asset":"money","qty":-301}]
	_check(not TurnReceipt.build(before, after, {"advanced":true,"week":1}).valid, "changed ledger prefix rejects")
	after.ledger = before.ledger.duplicate(true)
	var receipt := TurnReceipt.build(before, after, {"advanced":true,"week":1,"notes":[]})
	_check(receipt.valid and _row(receipt,"money").expense == 0, "earlier same-week manual trade is excluded from this advance interval")


func _test_construction_cash_and_work() -> void:
	for discount in [false, true]:
		var game := _game()
		if discount: game.state.meta_snapshot = ["M04"]
		_check(CabinetActions.start_project(game, "B13").is_empty(), "two-farm business queues atomically")
		var first := _record(game)
		var money := _row(first,"money")
		_check(first.development.started == [{"id":"B13","count":2}] and first.development.completed == [{"id":"B13","count":1}], "first week distinguishes two starts from one completion")
		_check(first.development.work_done == 8 and first.development.remaining_work == (7 if discount else 8), "actual construction work respects first-farm M04 discount")
		_check(first.development.cash_paid == 800 and first.development.recognized_cost < 800 and first.development.escrow_after > 0, "full eight-gold cash prepayment differs from recognized progress expense")
		_check(money.construction == 800 and money.fully_explained and is_equal_approx(money.income - money.expense, money.delta), "cash flow includes full construction escrow without double counting")
		var second := _record(game)
		_check(second.development.started.is_empty() and second.development.completed == [{"id":"B13","count":1}] and second.development.remaining_work == 0, "second week completes remaining field without a new start")
		_check(second.development.work_done == (7 if discount else 8) and second.development.cash_paid == 0 and second.development.recognized_cost > 0, "later construction consumes prepaid escrow but no new cash")
		_check(_row(second,"money").construction == 0 and _row(second,"money").fully_explained and game.state.assign.build == 0, "next-week automatic reassignment cannot erase completed-week work")
	var delayed := _state()
	delayed.orders = ["B13"]
	delayed.assign.build = 8
	delayed.unpaid_weeks = 8
	var before := delayed.duplicate(true)
	var outcome := WeekSim.process_week(delayed,content)
	var slow := TurnReceipt.build(before,delayed,outcome)
	_check(slow.development.actual_workers == 8 and slow.development.work_done == 4 and slow.development.remaining_work == 4, "unpaid efficiency halves actual new-project work, not worker count")


func _test_arrival_trial_and_rewards() -> void:
	var game := _game()
	_check(game.trade("food", 100, true).is_empty(), "test buys a real food shipment")
	_record(game)
	var arrived := _record(game)
	var food := _row(arrived,"food")
	_check(arrived.week == 2 and food.by_source.trade_arrival == 100 and food.fully_explained, "next-week-numbered arrival is included in actual completed interval")
	_check(not _row(arrived,"money").by_source.has("trade_buy") and arrived.notes.any(func(line): return "도착" in line), "previous purchase is excluded but delivery note is retained")
	for trial in ["rot", "audit"]:
		game = _game()
		game.state.week = 39
		game.state.trial = trial
		game.state.trial_started = false
		var receipt := _record(game)
		var row := _row(receipt,"food" if trial == "rot" else "money")
		_check(row.by_source.has("trial") and row.by_source.trial < 0 and row.fully_explained, "winter-start expense stamped week 40 belongs to advance of week 39: " + trial)
	game = _game(true)
	game.state.week = 13
	game.state.facilities.B13 = 6
	var rewarded := _record(game)
	_check(_row(rewarded,"wood").by_source.campaign_reward == 16 and _row(rewarded,"tools").by_source.campaign_reward == 2, "automatic season rewards enter actual resource flows")
	_check(_row(rewarded,"money").income > 0 and _row(rewarded,"money").by_source.tax > 0, "tax income is reported separately from cash expenses")
	_check(_row(rewarded,"food").fully_explained and not _row(rewarded,"food").by_source.has("transfer"), "tax in kind is an internal food transfer, not food production")
	_check("목표" in str(rewarded.notes[0]), "season outcome precedes routine notes")
	game = _game(true)
	game.state.week = 13
	var missed := _record(game)
	_check(_row(missed,"money").by_source.campaign_penalty == -300 and _row(missed,"money").fully_explained, "season failure costs are included in the same actual report")


func _test_advisor_attribution() -> void:
	var game := _game()
	CabinetActions.set_advisor(game,"CH03")
	var definition := CabinetActions.advisor_definition(game,"CH03")
	game.state[definition.effect] = 98.0
	var before_value: float = game.state[definition.effect]
	var receipt := _record(game)
	_check(receipt.advisor.acted and receipt.advisor.amount_known and receipt.advisor.id == "CH03", "advisor week marker confirms one actual activity")
	_check(is_equal_approx(receipt.advisor.amount, minf(100,before_value + definition.amount) - before_value), "advisor effect is capped at action time")
	_check(not is_equal_approx(game.state[definition.effect] - before_value, receipt.advisor.amount), "week-end health change is not misattributed to the advisor")
	game = _game()
	var unknown := _record(game,false)
	_check(unknown.advisor.acted and not unknown.advisor.amount_known, "missing advisor definition reports activity without inventing a numeric effect")
	game = _game()
	game.state.actions = 0
	var absent := _record(game)
	_check(not absent.advisor.acted and absent.advisor.amount == 0, "no available action produces no automatic advisor benefit")
	game = _game()
	game.council_visit(str(game.state.cabinet.advisor))
	var duplicate := _record(game)
	_check(not duplicate.advisor.acted, "manual visit before advance is not counted again")
	game = _game()
	definition = CabinetActions.advisor_definition(game,str(game.state.cabinet.advisor))
	game.state[definition.effect] = 100.0
	var capped := _record(game)
	_check(capped.advisor.acted and capped.advisor.amount_known and capped.advisor.amount == 0, "capped advisor can act without fabricated extra stats")


func _test_unclassified_and_gross_flows() -> void:
	var before := _state()
	var after := before.duplicate(true)
	after.week = 2
	after.public.wood -= 7
	after.public.money += 20
	after.ledger.append({"w":1,"src":"event","asset":"money","qty":30})
	after.ledger.append({"w":1,"src":"event","asset":"money","qty":-10})
	var receipt := TurnReceipt.build(before,after,{"advanced":true,"week":1,"notes":["공사 시작","곡물 곳간 완공","곡물 곳간 완공","교역 수레 도착","여름 목표 달성"]})
	var money := _row(receipt,"money")
	var wood := _row(receipt,"wood")
	_check(money.income == 30 and money.expense == 10 and money.delta == 20 and money.fully_explained, "same source can contain both income and expense without losing gross amounts")
	_check(wood.delta == -7 and wood.unclassified_delta == -7 and not wood.fully_explained and wood.consumption == 0, "unlogged inventory change is explicit instead of guessed consumption")
	_check(receipt.notes == ["여름 목표 달성","곡물 곳간 완공","교역 수레 도착","공사 시작"], "notes prioritize season outcomes before completion and arrival, deduplicate and preserve facts")


func _test_save_validation() -> void:
	var after := _state()
	var before := after.duplicate(true)
	var report := WeekSim.process_week(after, content)
	var original := TurnReceipt.build(before, after, report)
	var restored = JSON.parse_string(JSON.stringify(original))
	_check(TurnReceipt.valid(original) and TurnReceipt.valid(restored), "complete receipt and JSON numeric conversion pass save validation")
	var frozen := original.duplicate(true)
	TurnReceipt.valid(original)
	_check(original == frozen, "save validation is read only")
	for bad in [null, true, 1, [], {}, {"version":1}, TurnReceipt.build(before,before,{"advanced":false})]:
		_check(not TurnReceipt.valid(bad), "invalid or incomplete root is rejected: " + str(bad).left(30))
	for key in ["week","resource_rows","development","advisor","notes"]:
		var missing := original.duplicate(true)
		missing.erase(key)
		_check(not TurnReceipt.valid(missing), "required root field is checked: " + key)
	for value in [0,53,1.5,"1",INF,NAN]:
		var wrong := original.duplicate(true)
		wrong.week = value
		_check(not TurnReceipt.valid(wrong), "week must be a finite integer between 1 and 52")
	var wrong := original.duplicate(true)
	wrong.resource_rows[0].id = "unknown"
	_check(not TurnReceipt.valid(wrong), "unknown resource id rejects")
	wrong = original.duplicate(true)
	wrong.resource_rows[1].id = "money"
	_check(not TurnReceipt.valid(wrong), "duplicate resource ids reject")
	for value in [NAN,INF,"10",true]:
		wrong = original.duplicate(true)
		wrong.resource_rows[0].after = value
		_check(not TurnReceipt.valid(wrong), "resource numbers must be finite numeric values")
	wrong = original.duplicate(true)
	wrong.resource_rows[0].income = -1
	_check(not TurnReceipt.valid(wrong), "gross cash flows cannot be negative")
	wrong = original.duplicate(true)
	wrong.resource_rows[0].delta += 10
	_check(not TurnReceipt.valid(wrong), "stock delta must agree with before and after balances")
	wrong = original.duplicate(true)
	wrong.resource_rows[0].flows = ["invalid"]
	_check(not TurnReceipt.valid(wrong), "flow detail has a defined structure")
	wrong = original.duplicate(true)
	wrong.development.completed = [{"id":"B13","count":0}]
	_check(not TurnReceipt.valid(wrong), "completed facility count must be positive")
	wrong = original.duplicate(true)
	wrong.development.cash_paid = 1
	_check(not TurnReceipt.valid(wrong), "construction cash must reconcile to escrow and recognized cost")
	wrong = original.duplicate(true)
	wrong.advisor.acted = 1
	_check(not TurnReceipt.valid(wrong), "advisor activity must be a boolean")
	wrong = original.duplicate(true)
	wrong.advisor.amount = INF
	_check(not TurnReceipt.valid(wrong), "advisor amount cannot be infinite")
	wrong = original.duplicate(true)
	wrong.notes = [{"text":"not a note string"}]
	_check(not TurnReceipt.valid(wrong), "notes require strings")
