extends SceneTree

var checks := 0
var failures := 0
var content: Dictionary
const OLD_TALENTS := ["LF01","LF02","LF03","LA01","LA02","LA03","LS01","LS02","LS03","LP01","LP02","LP03"]


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LEGACY FAIL: ", message)


func _profile(points := 0) -> Dictionary:
	return {"version": 1, "points": points, "upgrades": ["M01", "M02", "M03", "M04"], "receipts": {"farm": true}, "runs": 2}


func _state() -> Dictionary:
	return RunState.new_run(content.charters.C01, 9341)


func _full_profile() -> Dictionary:
	var profile := _profile(0)
	LegacyPath.ensure(profile)
	for id in OLD_TALENTS:
		profile.legacy_talents[id] = 3
	return profile


func _ledger(state: Dictionary, source: String, asset: String) -> float:
	var total := 0.0
	for entry in state.ledger:
		if entry.src == source and entry.asset == asset:
			total += float(entry.qty)
	return total


func _init() -> void:
	content = Content.load_all()
	_test_definitions_and_old_profile()
	_test_purchase_and_refund()
	_test_validation_and_rejection()
	_test_snapshot_and_composition()
	_test_actual_economy()
	print("LEGACY PATH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_definitions_and_old_profile() -> void:
	var data := LegacyPath.definitions()
	_check(data.version == 2 and data.branches.size() == 6 and data.talents.size() == 48, "expanded catalog preserves the original twelve talents within 48")
	for branch in ["finance", "agriculture", "survival", "planning"]:
		var ids: Array = data.branches[branch].talents.slice(0, 3)
		var coherent := ids.size() == 3
		for index in ids.size():
			var definition: Dictionary = data.talents[ids[index]]
			coherent = coherent and definition.branch == branch and definition.tier == index + 1 and definition.max_rank == 3
			coherent = coherent and definition.costs.size() == 3 and definition.requires == ("" if index == 0 else ids[index - 1])
		_check(coherent, "branch order, three ranks and previous-tier prerequisites: " + branch)
	data.talents.LF01.costs[0] = 999
	_check(LegacyPath.definitions().talents.LF01.costs[0] == 2, "caller cannot mutate later definitions")
	var profile := _profile(16)
	var original := profile.duplicate(true)
	_check(LegacyPath.valid(profile), "old profile without talents remains valid")
	LegacyPath.ensure(profile)
	var expected := original.duplicate(true)
	expected.legacy_talents = {}
	_check(profile == expected, "migration adds only empty talents and preserves old upgrades, receipts and points")
	LegacyPath.ensure(profile)
	_check(profile == expected, "migration is idempotent")
	_check(LegacyPath.rank(profile, "LA01") == 0 and LegacyPath.cost(profile, "LA01") == 2, "first permanent rank starts at two points")
	_check(LegacyPath.cost(profile, "missing") == -1 and not LegacyPath.current_error(profile, "missing").is_empty(), "unknown talent has no purchase price")


func _test_purchase_and_refund() -> void:
	# 13주 첫 목표·첫 증빙·계절 정산의 16점으로 세 방향과 농업 3단계를 시험할 수 있다.
	var profile := _profile(16)
	var old_upgrades: Array = profile.upgrades.duplicate()
	var bought := true
	for id in ["LA01", "LA02", "LA03", "LF01", "LS01", "LP01"]:
		bought = LegacyPath.buy(profile, id).is_empty() and bought
	_check(bought and profile.legacy_talents.size() == 6 and profile.points == 1, "first-season budget buys six distinct ranks including one third-tier talent")
	_check(profile.upgrades == old_upgrades and profile.receipts == {"farm": true}, "new purchases preserve old permanent upgrades and receipts")
	_check(LegacyPath.refund(profile) == 15 and profile.points == 16 and profile.legacy_talents.is_empty(), "refund returns exact new-talent spending")
	_check(profile.upgrades == old_upgrades and LegacyPath.refund(profile) == 0 and profile.points == 16, "refund leaves old upgrades and cannot be repeated for profit")
	_check(LegacyPath.buy(profile, "LS01").is_empty() and LegacyPath.buy(profile, "LS02").is_empty(), "refunded points can choose a different branch")
	var full := _profile(216)
	var complete := true
	for id in OLD_TALENTS:
		for level in 3:
			complete = LegacyPath.buy(full, id).is_empty() and complete
	_check(complete and full.points == 0 and full.legacy_talents.size() == 12, "all 36 ranks cost a finite 216 points")
	var before := full.duplicate(true)
	_check(LegacyPath.cost(full, "LF01") == -1 and not LegacyPath.buy(full, "LF01").is_empty() and full == before, "maximum rank rejects without spending")
	_check(LegacyPath.refund(full) == 216 and full.points == 216, "full refund sums every tier's actual rank prices")


func _test_validation_and_rejection() -> void:
	var profile := _profile(20)
	var before := profile.duplicate(true)
	_check(not LegacyPath.buy(profile, "LA03").is_empty() and profile == before, "unmet prerequisites do not mutate old profile")
	profile.points = 1
	before = profile.duplicate(true)
	_check(not LegacyPath.buy(profile, "LA01").is_empty() and profile == before, "insufficient points reject atomically")
	_check(not LegacyPath.buy(profile, "unknown").is_empty() and profile == before, "unknown id rejects atomically")
	for invalid in [{"missing": 1}, {"LA01": -1}, {"LA01": 1.5}, {"LA01": 4}, {"LA01": true}, {"LA02": 1}, {"LA01": 0, "LA02": 1}, {"LA01": 1, "LA03": 1}, []]:
		profile = _profile(20)
		profile.legacy_talents = invalid
		before = profile.duplicate(true)
		var state := _state()
		var old_state := state.duplicate(true)
		LegacyPath.ensure(profile)
		var buy_error := LegacyPath.buy(profile, "LF01")
		var refund := LegacyPath.refund(profile)
		LegacyPath.apply(state, profile)
		_check(not LegacyPath.valid(profile) and not buy_error.is_empty() and refund == 0 and profile == before and state == old_state, "invalid ranks reject without mutation: " + str(invalid))
	for value in [-1, 2.5, "20", true, INF, NAN]:
		profile = _profile(0)
		profile.points = value
		_check(not LegacyPath.valid(profile), "growth points must be finite nonnegative integers: " + str(value))
	profile = _profile(8)
	profile.legacy_talents = {"LA01": 2, "LA02": 1, "LF01": 0}
	var restored = JSON.parse_string(JSON.stringify(profile))
	_check(LegacyPath.valid(restored) and LegacyPath.rank(restored, "LA01") == 2, "JSON numeric ranks and zero placeholders restore safely")
	_check(LegacyPath.valid({"legacy_talents": {"LF01": 1, "LF02": 1}}), "snapshot can be validated without unrelated profile fields")


func _test_snapshot_and_composition() -> void:
	var profile := _full_profile()
	var before_profile := profile.duplicate(true)
	var state := _state()
	var original := state.duplicate(true)
	state.bonuses = {"gather": 1.12, "harvest": 0.9, "wages": 0.85, "tax": 0.04}
	LegacyPath.apply(state, profile)
	_check(state.public.money == original.public.money + 1200 and state.public.money is int, "three finance ranks add twelve gold in integer copper")
	_check(state.public.food == original.public.food + 240 and state.public.wood == original.public.wood + 24 and state.public.tools == original.public.tools + 3 and state.public.fuel == original.public.fuel + 72, "starting resource effects use public inventory only")
	_check(state.resident == original.resident and state.pop == original.pop and state.facilities == original.facilities and state.refreshes == original.refreshes and state.ledger == original.ledger, "talents do not alter population, resident stock, facilities, refreshes or transaction history")
	_check(is_equal_approx(state.bonuses.gather, 1.12 * 1.15) and is_equal_approx(state.bonuses.harvest, 0.9 * 1.12) and is_equal_approx(state.bonuses.wages, 0.85 * 0.88), "ranks add within a talent and multiply with origin and relic bonuses")
	_check(is_equal_approx(state.bonuses.maintenance, 0.88) and is_equal_approx(state.bonuses.buy, 0.91) and is_equal_approx(state.bonuses.heating, 0.85) and is_equal_approx(state.bonuses.storage, 1.3) and state.bonuses.tax == 0.04, "bounded economic effects preserve unrelated bonus keys")
	_check(profile == before_profile and state.legacy_snapshot == profile.legacy_talents, "apply snapshots ranks without changing profile")
	var applied := state.duplicate(true)
	LegacyPath.apply(state, profile)
	_check(state == applied, "apply cannot double starting resources or multipliers")
	LegacyPath.refund(profile)
	LegacyPath.buy(profile, "LF01")
	LegacyPath.apply(state, profile)
	_check(state == applied and state.legacy_snapshot.LA01 == 3, "refund and new purchases never change the active snapshot or economic effects")
	var next := _state()
	LegacyPath.apply(next, profile)
	_check(next.legacy_snapshot == {"LF01": 1} and next.public.money == original.public.money + 400 and next.public.food == original.public.food, "new run receives current allocation after refund")
	var empty := _state()
	var old_profile := _profile(3)
	LegacyPath.apply(empty, old_profile)
	var empty_applied := empty.duplicate(true)
	LegacyPath.buy(old_profile, "LA01")
	LegacyPath.apply(empty, old_profile)
	_check(empty == empty_applied and empty.legacy_snapshot.is_empty(), "empty starting allocation also freezes and cannot gain talents later")


func _test_actual_economy() -> void:
	var profile := _full_profile()
	var base := _state()
	var trained := base.duplicate(true)
	LegacyPath.apply(trained, profile)
	WeekSim.process_week(base, content)
	WeekSim.process_week(trained, content)
	_check(is_equal_approx(_ledger(trained, "gather", "food"), _ledger(base, "gather", "food") * 1.15), "real gathering ledger receives the learned production bonus")
	base = _state()
	base.week = 33
	base.plots_sown = 4
	base.sow_f_sum = 1.0
	trained = base.duplicate(true)
	LegacyPath.apply(trained, profile)
	WeekSim.process_week(base, content)
	WeekSim.process_week(trained, content)
	_check(is_equal_approx(_ledger(trained, "harvest", "food"), _ledger(base, "harvest", "food") * 1.12), "real harvest uses the bounded three-rank bonus")
	base = _state()
	base.week = 40
	base.public.fuel = 100
	trained = base.duplicate(true)
	LegacyPath.apply(trained, profile)
	WeekSim.process_week(base, content)
	WeekSim.process_week(trained, content)
	_check(is_equal_approx(_ledger(trained, "heating", "fuel"), _ledger(base, "heating", "fuel") * 0.85) and trained.heat_fill == 1, "winter fuel expense falls while full heating is preserved")
	base = _state()
	base.facilities.B25 = 1
	base.assign.logging = 4
	trained = base.duplicate(true)
	LegacyPath.apply(trained, profile)
	# 동 단위 반올림 잔여를 포함하므로 4주 누계로 반복 지출을 비교한다.
	for week in 4:
		WeekSim.process_week(base, content)
		WeekSim.process_week(trained, content)
	_check(_ledger(trained, "wages", "money") > _ledger(base, "wages", "money") and _ledger(trained, "maintenance", "money") > _ledger(base, "maintenance", "money"), "real public wages and facility expense both decrease")
	base = _state()
	base.public.food = 4000
	trained = base.duplicate(true)
	LegacyPath.apply(trained, profile)
	# 같은 시작 식량에서 창고 효과만 비교한다.
	trained.public.food = base.public.food
	WeekSim.process_week(base, content)
	WeekSim.process_week(trained, content)
	_check(_ledger(trained, "spoil", "food") > _ledger(base, "spoil", "food"), "extra storage reduces actual excess-food spoilage")
	var session := GameSession.new(content)
	session.state = _state()
	var untrained_quote := session.trade_quote("tools", 10, true)
	LegacyPath.apply(session.state, profile)
	_check(session.trade_quote("tools", 10, true) == 1201 and session.trade_quote("tools", 10, true) < untrained_quote, "buy talent discounts goods while keeping the actual fixed trade fee")
