extends "res://tests/test_village_relics.gd"
## Expansion relics use actual weekly economy, not simulated UI rewards.
## Only isolated fixture saves under tests/output are written.

func _init() -> void:
	content = Content.load_all()
	_test_pools()
	_test_triggered_items()
	_test_costs_and_evidence()
	_test_reserved_exchange_cost()
	_test_passive_plus()
	_test_specializations()
	_test_specialization_economy()
	_test_early_seedbox()
	print("RELICS PLUS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _plus(id: String = "", week: int = 1) -> GameSession:
	var game := GameSession.new(content.duplicate(true))
	var config := CONFIG.duplicate(true)
	config.escalation = true
	config.cabinet = false
	config.workcrew = false
	game.start_run(61427, "settler", config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	_clear(game)
	game.state.week = week
	game.state.public.fuel = 200.0
	for key in game.state.assign: game.state.assign[key] = 0
	if not id.is_empty(): _own(game, [id])
	return game


func _test_pools() -> void:
	var old := _new()
	var game := _plus()
	_check(VillageRelics.plus_enabled(game.state), "actual new-run escalation configuration enables expanded relic pool")
	_check(VillageRelics.available_ids(old.state, content).size() == 12 and VillageRelics.available_ids(game.state, content).size() == 48, "old and expanded runs expose precisely 12 and 48 eligible relics")
	var false_flag: Dictionary = old.state.duplicate(true)
	false_flag.escalation = {"enabled":false}
	_check(VillageRelics.available_ids(false_flag, content).size() == 12, "explicit disabled escalation keeps the original pool")
	for target in [old, game]:
		var total := 48 if VillageRelics.plus_enabled(target.state) else 12
		for index in total:
			_check(VillageRelics.request_offer(target.state, content, "pool:%d" % index) == "", "eligible remaining relic can be offered: %d/%d" % [index, total])
			var offer: Array = target.state.realm.sanctuary.offer
			_check(offer.size() == mini(3, total-index), "draft shrinks correctly near eligible-pool exhaustion")
			for id in offer:
				_check(id not in target.state.realm.sanctuary.owned and id in VillageRelics.available_ids(target.state, content), "every offered relic is eligible and unowned: " + str(id))
			if offer.is_empty(): break
			_check(target.choose_relic(str(offer[0])) == "", "all eligible relics can be acquired through their actual offer")
		_check(target.state.realm.sanctuary.owned.size() == total and target.state.realm.sanctuary.equipped.size() == 3, "ownership exhausts its own pool while equipment stays at three")
		var saved: Dictionary = target.bundle()
		_check(VillageRelics.request_offer(target.state, content, "exhausted") != "" and target.bundle() == saved, "exhausted discovery changes neither source history nor RNG")
		_check(SaveStore.valid(saved), "entire eligible inventory is saveable")
	var broken: Dictionary = old.state.duplicate(true)
	broken.realm.sanctuary.owned.append("F05")
	_check(not VillageRelics.valid(broken, content), "old run rejects injected expansion ownership")
	broken = old.state.duplicate(true)
	broken.realm.sanctuary.offer = ["G08"]
	broken.realm.sanctuary.offer_source = "injected"
	broken.realm.sanctuary.sources.append("injected")
	_check(not VillageRelics.valid(broken, content) and VillageRelics.choose(broken, content, "G08") != "", "old run cannot validate or consume an injected expansion draft")
	_check(VillageRelics.profile_valid({"relic_discoveries":VillageRelics.definitions().relics.keys()}, content), "permanent discovery record accepts all 48 across old and new runs")
	var store := SaveStore.new("res://tests/output/relics_plus_pool_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "", "expanded 48-item inventory writes through production SaveStore")
	var loaded := store.read()
	_check(loaded.ok and loaded.bundle.state.realm.sanctuary == game.state.realm.sanctuary and store.write(loaded.bundle) == "", "expanded inventory reloads and can be saved again")


func _fixture(id: String) -> GameSession:
	var game := _plus(id)
	match id:
		"F05": game.state.week = 4; game.state.plots_sown = 4; game.state.sow_f_sum = 0.25
		"F06", "F08": game.state.facilities.B14 = 1
		"C05":
			game.state.assign.build = 8
			_check(game.queue_build("B13") == "", "conversion fixture approves a real farm project")
		"C06": game.state.facilities.B33 = 1
		"C07":
			_check(game.trade("food", 20, true) == "", "import rebate fixture orders real supplies")
			var first := game.advance()
			_check(first.advanced and not _triggered(game, id), "ordering a shipment does not pay its arrival reward")
			_clear(game)
		"G05":
			game.state.security = 70
			game.state.realm.threat = 9.0
		"G06": game.state.health = 40.0
		"G08": game.state.week = 40
	RealmRules.refresh(game.state, game.content)
	return game


func _paid_week(game: GameSession, id: String) -> void:
	var before: Dictionary = game.state.duplicate(true)
	var report := game.advance()
	_check(report.advanced and _triggered(game, id), "actual economy triggers expansion relic " + id)
	var reward: Dictionary = content.village_relics.relics[id].reward
	var row: Dictionary = {}
	for item in game.state.realm.sanctuary.last_result.get("triggered", []):
		if item.id == id: row = item
	_check(not row.is_empty() and row.effects == reward, "actual costs and rewards match the description exactly: " + id)
	var entries: Array = game.state.ledger.slice(before.ledger.size())
	for asset in reward:
		if asset not in VillageRelics.RESOURCE_KEYS: continue
		var total := 0.0
		for entry in entries:
			if entry.src == "relic:" + id and entry.asset == asset: total += float(entry.qty)
		_check(is_equal_approx(total, float(reward[asset])), "both spending and reward are present in the weekly ledger: " + id + "/" + str(asset))
		var resource: Dictionary = game.state.last_receipt.resource_rows.filter(func(item): return item.id == asset)[0]
		_check(is_equal_approx(float(resource.by_source.get("relic:" + id, 0)), float(reward[asset])), "visible receipt includes the same relic flow: " + id + "/" + str(asset))
	var paid: Dictionary = game.state.duplicate(true)
	_check(VillageRelics.after_week(before, game.state, content, report).triggered.is_empty() and game.state == paid, "weekly callback cannot duplicate positive or negative payment: " + id)
	game.unequip_relic(id)
	game.equip_relic(id)
	var swapped: Dictionary = game.state.duplicate(true)
	_check(VillageRelics.after_week(before, game.state, content, report).triggered.is_empty() and game.state == swapped, "unequip/equip does not reset paid-week protection: " + id)
	_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "paid expansion relic remains saveable before and after JSON roundtrip: " + id)
	var store := SaveStore.new("res://tests/output/relics_plus_%s_%d" % [id, Time.get_ticks_usec()])
	_check(store.write(game.bundle()) == "", "paid relic writes a real isolated save: " + id)
	var loaded := store.read()
	if loaded.ok:
		var restored: Dictionary = loaded.bundle.state
		var frozen := restored.duplicate(true)
		_check(VillageRelics.after_week(before, restored, content, report).triggered.is_empty() and restored == frozen and store.write(loaded.bundle) == "", "save reload and autosave cannot repeat this week's relic: " + id)
	else: _check(false, "paid relic save reload succeeds: " + id)


func _test_triggered_items() -> void:
	for id in ["F05", "F06", "F08", "C05", "C06", "C07", "C08", "G05", "G06", "G08"]:
		_paid_week(_fixture(id), id)
	var invalid_cases := {
		"F05":func(g): g.state.week = 7,
		"F06":func(g): g.state.facilities.erase("B14"),
		"F08":func(g): g.state.facilities.erase("B06"),
		"C05":func(g): g.state.assign.build = 4,
		"C06":func(g): g.state.public.wood = 0.0,
		"C07":func(g): g.state.shipments.clear(),
		"C08":func(g): g.state.public.money = 0,
		"G05":func(g): g.state.security = 40.0,
		"G06":func(g): g.state.ration = 0.75,
		"G08":func(g): g.state.public.fuel = 0.0,
	}
	for id in invalid_cases:
		var game := _fixture(id)
		invalid_cases[id].call(game)
		_check(game.advance().advanced and not _triggered(game, id), "unmet real condition pays no reward: " + str(id))


func _test_costs_and_evidence() -> void:
	for id in ["F06", "C05", "C06", "G05", "G06", "G08"]:
		var game := _fixture(id)
		match id:
			"F06": game.state.public.wood = 1.0
			"C05": game.state.public.wood = 11.0 # Eight wood is consumed by the actual farm.
			"C06": game.state.public.fuel = 5.0
			"G05": game.state.public.fuel = 2.0
			"G06": game.state.public.food = 7.0; game.state.resident.food = 1000.0
			"G08": game.state.public.money = 0
		_check(game.advance().advanced and not _triggered(game, id), "insufficient exchange cost prevents the entire payment: " + id)
		for amount in game.state.public.values(): _check(float(amount) >= 0, "failed relic exchange never creates negative public stock: " + id)
	# A historical arrival ledger or cached assignment is insufficient evidence.
	var stale := _plus("C07")
	WeekSim._ledger(stale.state, 1, "trade_arrival", "food", 200)
	_check(stale.advance().advanced and not _triggered(stale, "C07"), "previous-ledger arrival is not reused by a later week")
	var empty := _plus("C06")
	empty.state.labor_report = {"realm_by":{"B33":3}}
	_check(empty.advance().advanced and not _triggered(empty, "C06"), "cached smithy workers without actual production do not trigger the bellows")
	var barren := _fixture("F05")
	barren.state.plots_sown = 0
	_check(barren.advance().advanced and not _triggered(barren, "F05"), "farm assignments on fields without sown seeds cannot produce the seedbox reward")
	for ids in [["F06", "G06"], ["G06", "F06"]]:
		var exchange := _plus()
		_own(exchange, ids)
		exchange.state.facilities.B14 = 1
		exchange.state.health = 40
		exchange.state.public.food = 4.0
		exchange.state.resident.food = 1000.0
		_check(exchange.advance().advanced and _triggered(exchange, "F06") and not _triggered(exchange, "G06"), "same-week relic reward cannot fund another relic's unmet cost, regardless of slot order")


func _test_reserved_exchange_cost() -> void:
	# Exercise the real weekly work/ledger, then reserve the next project before
	# reward reconciliation. The callback must protect that pending commitment.
	for free_wood in [3, 4]:
		var game := _fixture("C05")
		game.state.public.wood = 28.0 + free_wood # Farm 8 + pending granary 20.
		var before: Dictionary = game.state.duplicate(true)
		var report := WeekSim.process_week(game.state, content)
		_check(report.advanced and game.state.facilities.B13 == int(before.facilities.B13) + 1, "reserved-exchange fixture completes a real farm through the weekly economy")
		_check(game.queue_build("B22") == "", "next granary reserves its actual construction materials before relic reconciliation")
		var reserved := RealmRules.held(game.state, content)
		var stock: Dictionary = game.state.public.duplicate(true)
		_check(is_equal_approx(float(reserved.wood), 20.0) and is_equal_approx(float(stock.wood) - float(reserved.wood), float(free_wood)), "reserved-exchange fixture has exactly three or four uncommitted wood")
		var ledger_start: int = game.state.ledger.size()
		var result := VillageRelics.after_week(before, game.state, content, report)
		var paid: bool = free_wood == 4
		_check(_triggered(game, "C05") == paid, "conversion pays only when four uncommitted wood remain after reservation")
		_check(is_equal_approx(float(game.state.public.wood), float(stock.wood) - (4.0 if paid else 0.0)) and float(game.state.public.wood) >= float(reserved.wood), "conversion never consumes the granary's reserved wood")
		_check(is_equal_approx(float(game.state.public.stone), float(stock.stone) + (6.0 if paid else 0.0)), "blocked conversion grants no stone; funded conversion grants its exact reward")
		var entries: Array = game.state.ledger.slice(ledger_start)
		_check(entries.size() == (2 if paid else 0) and result.triggered.size() == (1 if paid else 0), "only a funded conversion writes its paired cost and reward to the ledger")
		_check(game.state.orders == ["B22"] and RealmRules.held(game.state, content) == reserved, "relic reconciliation preserves the pending construction commitment")
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "reserved conversion state remains valid natively and after JSON roundtrip")
		_clear(game)
		_check(game.advance().advanced and game.state.orders.is_empty() and game.state.projects.any(func(project): return project.id == "B22"), "protected materials let the pending granary start during the next actual week")


func _test_passive_plus() -> void:
	var jar := _plus("F07")
	var plain := _plus()
	jar.state.public.food = 4000.0
	plain.state.public.food = 4000.0
	_check(is_equal_approx(WeekSim.bonus(jar.state, "storage") / WeekSim.bonus(plain.state, "storage"), 1.3) and is_equal_approx(WeekSim.bonus(jar.state, "spoil") / WeekSim.bonus(plain.state, "spoil"), 1.15), "measuring cup adds both storage capacity and its loss penalty")
	jar.advance()
	plain.advance()
	_check(VillageRelics._flow(jar.state.ledger, "spoil", "food", false) < VillageRelics._flow(plain.state.ledger, "spoil", "food", false), "expanded storage changes actual overflow losses despite the spoilage tradeoff")
	jar = _plus("F07")
	plain = _plus()
	jar.advance()
	plain.advance()
	_check(VillageRelics._flow(jar.state.ledger, "spoil", "food", false) > VillageRelics._flow(plain.state.ledger, "spoil", "food", false), "below normal capacity, measuring cup really pays its extra spoilage cost")
	var drum := _plus("G07")
	plain = _plus()
	for game in [drum, plain]:
		game.state.assign.build = 8
		game.queue_build("B13")
		game.advance()
	_check(drum.state.security > plain.state.security and VillageRelics._flow(drum.state.ledger, "wages", "money", false) > VillageRelics._flow(plain.state.ledger, "wages", "money", false), "march drum improves actual security and charges its actual wage premium")
	var scale := _plus("C07")
	plain = _plus()
	_check(scale.trade_quote("food", 200, true) > plain.trade_quote("food", 200, true), "trader scale's purchase-price penalty changes the actual quoted price")
	var jug := _plus("F08")
	plain = _plus()
	for game in [jug, plain]:
		game.state.facilities.B22 = 2
		for week in 8:
			_clear(game)
			game.advance()
	_check(VillageRelics._flow(jug.state.ledger, "maintenance", "money", false) > VillageRelics._flow(plain.state.ledger, "maintenance", "money", false), "rain jug's maintenance premium is paid in the actual ledger")
	var abacus := _plus("C08")
	abacus.queue_build("B22")
	abacus.advance()
	_check(abacus.state.projects[0].work_total == int(ceil(Constants.GRADE_COST.B.work * 1.1)) and not _triggered(abacus, "C08"), "abacus slows actual new construction and never pays while a project remains")


func _test_specializations() -> void:
	for ids in [["F01", "F02", "F05"], ["C01", "C02", "C05"], ["G01", "G02", "G05"]]:
		var game := _plus()
		_own(game, ids)
		var category: String = content.village_relics.relics[ids[0]].category
		var bonus := VillageRelics.bonuses(game.state, content)
		_check(bonus.sets == [category] and bonus.surges == [category], "three same-family relics including a new item activate exactly one specialization")
		_check(VillageRelics.overview(game.state, content).sets.size() == 2, "overview explains both normal set and its specialization tradeoff")
		var initial: Dictionary = game.state.realm.mods.duplicate(true)
		for repeat in 10: RealmRules.refresh(game.state, content)
		_check(game.state.realm.mods == initial, "specialization bonuses do not accumulate on UI refresh")
		game.unequip_relic(ids[2])
		_check(VillageRelics.bonuses(game.state, content).surges.is_empty(), "removing the third relic removes both specialization benefit and penalty")
		game.equip_relic(ids[2])
		_check(game.state.realm.mods == initial, "re-equipping restores exactly one specialization")
	var old := _new()
	_own(old, ["F01", "F02", "F03"])
	_check(VillageRelics.bonuses(old.state, content).surges.is_empty() and not VillageRelics.bonuses(old.state, content).mods.has("heating"), "old three-item combinations retain their exact original effect")
	var only_old := _plus()
	_own(only_old, ["F01", "F02", "F03"])
	_check(VillageRelics.bonuses(only_old.state, content).surges.is_empty(), "expanded run still needs an expansion item for specialization")


func _test_specialization_economy() -> void:
	var triple := _plus()
	var pair := _plus()
	_own(triple, ["F01", "F02", "F05"])
	_own(pair, ["F01", "F02"])
	for game in [triple, pair]:
		game.state.week = 33
		game.state.plots_sown = 4
		game.state.sow_f_sum = 1.0
		game.advance()
	_check(is_equal_approx(VillageRelics._flow(triple.state.ledger, "harvest", "food") / VillageRelics._flow(pair.state.ledger, "harvest", "food"), 1.2), "abundance specialization increases actual harvest by its stated 20 percent")
	for game in [triple, pair]:
		_clear(game)
		game.state.week = 40
		game.state.public.fuel = 300
		game.advance()
	_check(is_equal_approx(VillageRelics._flow(triple.state.ledger, "heating", "fuel", false) / VillageRelics._flow(pair.state.ledger, "heating", "fuel", false), 1.15), "abundance specialization also consumes 15 percent more actual winter fuel")
	triple = _plus()
	pair = _plus()
	_own(triple, ["C01", "C02", "C05"])
	_own(pair, ["C01", "C02"])
	for game in [triple, pair]:
		game.state.assign.build = 8
		game.queue_build("B22")
		game.advance()
	_check(triple.state.projects[0].work_total == int(ceil(24 * 0.85 * 0.85)) and pair.state.projects[0].work_total == int(ceil(24 * 0.85)), "craft specialization changes the real new-project work budget")
	_check(VillageRelics._flow(triple.state.ledger, "wages", "money", false) > VillageRelics._flow(pair.state.ledger, "wages", "money", false), "craft specialization charges its public-worker wage premium in the same real construction week")
	triple = _plus()
	pair = _plus()
	_own(triple, ["G01", "G02", "G05"])
	_own(pair, ["G01", "G02"])
	for game in [triple, pair]:
		game.state.facilities.B22 = 2
		for week in 8:
			_clear(game)
			game.advance()
	_check(triple.state.security > pair.state.security, "guard specialization raises actual weekly security")
	_check(VillageRelics._flow(triple.state.ledger, "maintenance", "money", false) > VillageRelics._flow(pair.state.ledger, "maintenance", "money", false), "guard specialization pays its upkeep cost across real copper-rounded weeks")


func _test_early_seedbox() -> void:
	var game := _plus()
	var config := CONFIG.duplicate(true)
	config.escalation = true
	var found_seed := -1
	for candidate in range(1, 120):
		var probe := GameSession.new(content)
		probe.start_run(candidate, "settler", config)
		VillageRelics.request_offer(probe.state, content, "early_seed")
		if "F05" in probe.state.realm.sanctuary.offer: found_seed = candidate; break
	_check(found_seed >= 0, "first three-item offer can actually contain the seedbox")
	if found_seed < 0: return
	game.start_run(found_seed, "settler", config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	game.queue_build("B13")
	game.queue_build("B13")
	for week in 3:
		_clear(game)
		_check(game.advance().advanced, "actual early farm campaign reaches first ruins")
	_check(game.state.week == 4 and game.state.active_event == "RS_RUINS", "first seedbox acquisition is after the initial sowing week")
	_check(game.choose_event(0) == "" and "F05" in game.state.realm.sanctuary.offer and game.choose_relic("F05") == "", "seedbox is acquired through the real fourth-week ruins offer")
	_check(game.advance().advanced and _triggered(game, "F05") and game.state.realm.sanctuary.last_result.totals.food == 16, "week-four acquisition immediately rewards actual week-four farm work")
	_clear(game)
	_check(game.advance().advanced and _triggered(game, "F05"), "week-five farm work earns exactly the next weekly payment")
