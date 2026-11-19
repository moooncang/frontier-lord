extends "res://tests/test_crisis_director.gd"
## The real economy operator is inherited; focused fixtures isolate build effects.


func _init() -> void:
	content = Content.load_all()
	_test_operating_catalog()
	_test_activation_and_previews()
	_test_every_build()
	_test_economic_multipliers()
	_test_payment_boundaries()
	_test_drafts_and_legacy()
	if "--skip-years" not in OS.get_cmdline_user_args(): _test_eight_years()
	print("OPERATING BUILDS: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _family_cards(family: String) -> Array:
	var ids: Array = content.progression.perks.keys().filter(func(id): return content.progression.perks[id].family == family)
	ids.sort()
	return ids.slice(0, 2)


func _take(game: GameSession, id: String) -> void:
	if id in game.state.perks: return
	game.state.perk_offer = [id]
	_check(game.choose_perk(id), "actual selection acquires perk " + id)


func _fixture_build(id: String) -> GameSession:
	var game := _new()
	_clear(game)
	game.state.cabinet.enabled = false
	game.state.workcrew.enabled = false
	game.state.perks = []
	game.state.bonuses = {}
	game.state.synergies = []
	for key in game.state.assign: game.state.assign[key] = 0
	for key in game.state.public: game.state.public[key] = 100000 if key == "money" else 200.0
	game.state.public.food = 3000.0
	game.state.resident.food = 3000.0
	game.state.public.fuel = 500.0
	game.state.health = 55.0
	game.state.mood = 85.0
	game.state.security = 70.0
	game.state.realm.threat = 10.0
	for facility in ["B01", "B06", "B14", "B22", "B25", "B27", "B33"]: game.state.facilities[facility] = 1
	if id.is_empty():
		RealmRules.refresh(game.state, game.content)
		return game
	var definition: Dictionary = OperatingBuilds.definitions(content).builds[id]
	game.state.realm.sanctuary.owned = [definition.relics[0]]
	game.state.realm.sanctuary.equipped = [definition.relics[0]]
	for perk in _family_cards(str(definition.family)): _take(game, str(perk))
	match id:
		"harvest_trade": game.state.week = 33; game.state.plots_sown = 4; game.state.sow_f_sum = 1.0
		"market_garden": game.state.assign.garden = 4
		"timber_trade", "civic": game.state.assign.logging = 4
		"stoneworks": game.state.assign.quarry = 4
		"prefab":
			game.state.assign.build = 8
			_check(game.queue_build("B22") == "", "prefab fixture approves an actual granary")
		"caravan":
			_check(game.trade("food", 20, true) == "", "caravan fixture buys an actual shipment")
			_check(game.advance().advanced and not _build_paid(game, id), "ordering alone cannot trigger an arrival build")
			_clear(game)
		"infirmary": game.state.health = 40.0
		"winter_hearth": game.state.week = 40
	RealmRules.refresh(game.state, game.content)
	return game


func _build_paid(game: GameSession, id: String) -> bool:
	return game.state.realm.sanctuary.last_result.get("builds", []).any(func(row): return row.id == id)


func _test_operating_catalog() -> void:
	_check(Content.validate(content).is_empty(), "expanded content validates")
	_check(OperatingBuilds.definitions(content).builds.size() == 12 and content.progression.perks.size() == 96 and content.village_relics.relics.size() == 48, "twelve builds connect 96 perks and 48 relics")
	var families := {}
	for index in range(100, 148):
		var id := "P%d" % index
		_check(content.progression.perks.has(id), "all reserved new perk IDs exist: " + id)
		var perk: Dictionary = content.progression.perks[id]
		families[perk.family] = int(families.get(perk.family, 0)) + 1
		_check(perk.plus_only and not perk.extra_bonuses.is_empty(), "new perk combines benefit and economic cost: " + id)
	for family in families: _check(families[family] == 12, "each existing family gains twelve perk choices")
	# Choose every old and new perk through the production API and reject replay.
	for id in content.progression.perks:
		var game := _fixture_build("")
		_take(game, str(id))
		var saved: Dictionary = game.state.duplicate(true)
		_check(not game.choose_perk(str(id)) and game.state == saved, "no perk can apply twice: " + id)
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "every perk is saveable natively and serialized: " + id)
	for id in OperatingBuilds.definitions(content).builds:
		var definition: Dictionary = OperatingBuilds.definitions(content).builds[id]
		_check(definition.relics.size() == 2 and definition.perk_count == 2 and definition.trigger == id, "build has explicit two-candidate identity and weekly trigger: " + id)
		_check(definition.reward.keys().any(func(key): return key in VillageRelics.RESOURCE_KEYS and float(definition.reward[key]) < 0) and definition.reward.keys().any(func(key): return float(definition.reward[key]) > 0 or key == "threat" and float(definition.reward[key]) < 0), "every build conversion has a real cost and benefit: " + id)
		_check(TurnReceipt.source_label("build:"+id).contains(str(definition.name)), "weekly source resolves the actual build name: " + id)
	for field in ["modifier", "relic", "trigger", "link", "family"]:
		var broken := content.duplicate(true)
		match field:
			"modifier": broken.operating_builds.builds.granary.mods["invented"] = 1.1
			"relic": broken.operating_builds.builds.granary.relics[0] = "NO_RELIC"
			"trigger": broken.operating_builds.builds.granary.trigger = "NO_TRIGGER"
			"link": broken.progression.perks.P100.build_id = "NO_BUILD"
			"family": broken.progression.perks.P100.family = "court"
		_check(not Content.validate(broken).is_empty(), "content validation rejects corrupted operating-build " + field)


func _test_activation_and_previews() -> void:
	for id in OperatingBuilds.definitions(content).builds:
		var definition: Dictionary = OperatingBuilds.definitions(content).builds[id]
		var game := _fixture_build("")
		var cards := _family_cards(str(definition.family))
		game.state.realm.sanctuary.owned = definition.relics.duplicate()
		game.state.realm.sanctuary.equipped = [definition.relics[0]]
		_take(game, str(cards[0]))
		_check(id not in OperatingBuilds.active(game.state, content), "one matching perk is insufficient: " + id)
		var before: Dictionary = game.state.duplicate(true)
		_check(id in OperatingBuilds.preview(game.state, content, str(cards[1])).activated and game.state == before, "second-perk preview is exact and immutable: " + id)
		_take(game, str(cards[1]))
		_check(id in OperatingBuilds.active(game.state, content), "either matching relic plus two old-family perks activates: " + id)
		var once: Dictionary = game.state.realm.mods.duplicate(true)
		for repeat in 4: RealmRules.refresh(game.state, content)
		_check(game.state.realm.mods == once, "refresh never compounds build multipliers: " + id)
		_check(id in OperatingBuilds.preview(game.state, content, "", "", str(definition.relics[0])).deactivated, "unequip preview shows lost build: " + id)
		_check(game.equip_relic(str(definition.relics[1])) == "", "paired relic can share an equipment loadout")
		_check(OperatingBuilds.active(game.state, content).count(id) == 1, "two matching relics still grant one build: " + id)
		game.unequip_relic(str(definition.relics[0]))
		_check(id in OperatingBuilds.active(game.state, content), "the other paired relic independently sustains the build: " + id)
		game.unequip_relic(str(definition.relics[1]))
		_check(id not in OperatingBuilds.active(game.state, content), "inventory ownership does not count as equipment: " + id)
		before = game.state.duplicate(true)
		_check(id in OperatingBuilds.preview(game.state, content, "", str(definition.relics[0])).activated and game.state == before, "relic acquisition preview changes no resources, RNG, or save")
	var full := _fixture_build("market_garden")
	full.state.realm.sanctuary.owned = ["F01", "C01", "G01"]
	full.state.realm.sanctuary.equipped = ["F01", "C01", "G01"]
	_check(OperatingBuilds.preview(full.state, content, "", "F11").activated.is_empty(), "full inventory acquisition goes to storage without phantom activation")
	_check("market_garden" in OperatingBuilds.preview(full.state, content, "", "F11", "F01").activated, "replacement preview accounts for the freed equipment slot")


func _test_every_build() -> void:
	for id in OperatingBuilds.definitions(content).builds:
		var game := _fixture_build(str(id))
		var control := GameSession.new(game.content.duplicate(true))
		control.state = game.state.duplicate(true)
		control.profile = game.profile.duplicate(true)
		control.content.operating_builds.builds.erase(id)
		RealmRules.refresh(control.state, control.content)
		var definition: Dictionary = OperatingBuilds.definitions(content).builds[id]
		for key in definition.get("mods", {}):
			_check(is_equal_approx(WeekSim.bonus(game.state, key) / WeekSim.bonus(control.state, key), float(definition.mods[key])), "benefit and penalty each enter economics exactly once: " + id + "/" + key)
		var before: Dictionary = game.state.duplicate(true)
		var report := game.advance()
		_check(report.advanced and control.advance().advanced and _build_paid(game, str(id)) and not _build_paid(control, str(id)), "real weekly evidence triggers only the active build: " + id)
		var paid_rows: Array = game.state.realm.sanctuary.last_result.get("builds", [])
		var matching: Array = paid_rows.filter(func(row): return row.id == id)
		_check(matching.size() == 1 and matching[0].effects == definition.reward, "actual exchange matches all declared costs and benefits: " + id)
		for asset in definition.reward:
			if asset not in VillageRelics.RESOURCE_KEYS: continue
			var ledger := VillageRelics._flow(game.state.ledger.slice(before.ledger.size()), "build:"+id, asset) - VillageRelics._flow(game.state.ledger.slice(before.ledger.size()), "build:"+id, asset, false)
			_check(is_equal_approx(ledger, float(definition.reward[asset])), "build cost/reward is recorded once in actual ledger: " + id + "/" + asset)
			var rows: Array = game.state.last_receipt.resource_rows.filter(func(row): return row.id == asset)
			_check(not rows.is_empty() and is_equal_approx(float(rows[0].by_source.get("build:"+id, 0)), ledger), "weekly receipt reconciles the build exchange: " + id + "/" + asset)
		var settled: Dictionary = game.state.duplicate(true)
		_check(VillageRelics.after_week(before, game.state, content, report).builds.is_empty() and game.state == settled, "repeated callback cannot replay a build: " + id)
		game.unequip_relic(str(definition.relics[0]))
		game.equip_relic(str(definition.relics[0]))
		settled = game.state.duplicate(true)
		_check(VillageRelics.after_week(before, game.state, content, report).builds.is_empty() and game.state == settled, "re-equipping does not reset build payment history: " + id)
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "actual build result survives native and JSON save: " + id)
		var restored: Dictionary = JSON.parse_string(JSON.stringify(game.bundle())).state
		var saved := restored.duplicate(true)
		_check(VillageRelics.after_week(before, restored, content, report).builds.is_empty() and restored == saved, "serialized last-week guard cannot farm a build: " + id)
		var store := SaveStore.new("res://tests/output/operating_build_%s_%d" % [id, Time.get_ticks_usec()])
		_check(store.write(game.bundle()) == "", "actual build result writes through production SaveStore: " + id)
		var loaded := store.read()
		var normalized: Dictionary = SaveStore._normalize(JSON.parse_string(JSON.stringify(game.state.realm.sanctuary.last_result)))
		_check(loaded.ok and loaded.bundle.state.realm.sanctuary.last_result == normalized, "actual saved build receipt reloads unchanged after documented integer normalization: " + id)
		_check(loaded.ok and store.write(loaded.bundle) == "", "reloaded build receipt remains valid for autosave: " + id)


func _test_economic_multipliers() -> void:
	for key in ["garden", "quarry", "smithy"]:
		var plain := _fixture_build("")
		plain.state.assign.garden = 4
		plain.state.assign.quarry = 4
		var boosted := GameSession.new(plain.content)
		boosted.state = plain.state.duplicate(true)
		boosted.profile = plain.profile.duplicate(true)
		boosted.state.bonuses[key] = 1.5
		RealmRules.refresh(boosted.state, boosted.content)
		_check(plain.advance().advanced and boosted.advance().advanced, "paired production weeks advance for " + key)
		var asset: String = {"garden":"food", "quarry":"stone", "smithy":"tools"}[key]
		var base := VillageRelics._flow(plain.state.ledger, key, asset)
		_check(base > 0 and is_equal_approx(VillageRelics._flow(boosted.state.ledger, key, asset), base * 1.5), "new output multiplier changes real production once: " + key)
		_check(plain.state.labor_report == boosted.state.labor_report, "output boost does not invent workers: " + key)
		for source in ["quarry", "smithy", "wages", "maintenance"]:
			for input in ["wood", "stone", "tools", "money"]:
				_check(is_equal_approx(VillageRelics._flow(plain.state.ledger, source, input, false), VillageRelics._flow(boosted.state.ledger, source, input, false)), "new yield does not double-charge inputs or wages: " + key + "/" + source + "/" + input)


func _test_payment_boundaries() -> void:
	for available in [3.0, 4.0]:
		var game := _fixture_build("market_garden")
		game.state.facilities.erase("B33")
		game.state.public.wood = 20.0 + available
		var before: Dictionary = game.state.duplicate(true)
		var report := WeekSim.process_week(game.state, content)
		_check(game.queue_build("B22") == "", "actual granary commitment is reserved before reconciliation")
		var stock: Dictionary = game.state.public.duplicate(true)
		VillageRelics.after_week(before, game.state, content, report)
		_check(_build_paid(game, "market_garden") == (available == 4), "full uncommitted exchange cost is required")
		_check(float(game.state.public.wood) >= 20 and game.state.orders == ["B22"], "build exchange never spends reserved construction stock")
		_check(is_equal_approx(float(game.state.public.food) - float(stock.food), 18.0 if available == 4 else 0.0), "failed conversion grants no partial reward")
	var not_worked := _fixture_build("prefab")
	not_worked.state.unpaid_weeks = 8
	_check(not_worked.advance().advanced and not _build_paid(not_worked, "prefab"), "eight assigned workers reduced to four actual work do not trigger prefab")
	var hungry := _fixture_build("infirmary")
	hungry.state.public.food = 0.0
	hungry.state.resident.food = 0.0
	hungry.state.facilities.erase("B14")
	_check(hungry.advance().advanced and not _build_paid(hungry, "infirmary"), "unfed residents cannot trigger care conversion")
	var healthy := _fixture_build("commons")
	healthy.state.health = 100.0
	_check(healthy.advance().advanced and not _build_paid(healthy, "commons"), "healthy residents do not waste communal-care food above the health threshold")
	var unpaid := _fixture_build("civic")
	unpaid.state.public.money = 0
	_check(unpaid.advance().advanced and not _build_paid(unpaid, "civic"), "unpaid wages cannot trigger civic exchange")
	var pacified := _fixture_build("garrison")
	pacified.state.realm.sanctuary.owned.append("G03")
	pacified.state.realm.sanctuary.equipped.append("G03")
	pacified.state.realm.threat = 1.0
	RealmRules.refresh(pacified.state, content)
	_check(pacified.advance().advanced and pacified.state.realm.threat == 0 and not _build_paid(pacified, "garrison"), "prior relic removes the last threat without making a later build burn fuel for zero benefit")
	var dead := _fixture_build("civic")
	dead.state.pop = 1
	dead.state.death_res = 1.0
	_check(dead.advance().advanced and dead.state.pop == 0 and not _build_paid(dead, "civic"), "last resident death never grants a posthumous build reward")
	var stale := _fixture_build("market_garden")
	stale.state.assign.garden = 0
	stale.state.facilities.erase("B14")
	WeekSim._ledger(stale.state, 1, "garden", "food", 100)
	_check(stale.advance().advanced and not _build_paid(stale, "market_garden"), "historical production is not fresh weekly evidence")
	for reverse in [false, true]:
		var shared := _fixture_build("market_garden")
		var healer: Dictionary = OperatingBuilds.definitions(content).builds.infirmary
		shared.state.realm.sanctuary.owned.append(healer.relics[0])
		shared.state.realm.sanctuary.equipped.append(healer.relics[0])
		if reverse: shared.state.realm.sanctuary.equipped.reverse()
		for perk in _family_cards("provisions"): _take(shared, str(perk))
		shared.state.public.food = 0.0
		shared.state.health = 40.0
		_check(shared.advance().advanced and _build_paid(shared, "market_garden") and not _build_paid(shared, "infirmary"), "same-week production-build reward cannot fund care-build cost in either slot order")
	var snapshot := _fixture_build("market_garden")
	snapshot.unequip_relic("F11")
	var without: Dictionary = snapshot.state.duplicate(true)
	var week := WeekSim.process_week(snapshot.state, content)
	snapshot.equip_relic("F11")
	VillageRelics.after_week(without, snapshot.state, content, week)
	_check(not _build_paid(snapshot, "market_garden"), "equipping after production cannot claim a past build reward")
	var invalid := _fixture_build("market_garden")
	invalid.advance()
	var broken: Dictionary = invalid.bundle().duplicate(true)
	broken.state.realm.sanctuary.last_result.builds[0].effects.food = 99999
	_check(not SaveStore.valid(broken), "saved build result rejects inflated rewards")
	broken = invalid.bundle().duplicate(true)
	broken.state.realm.sanctuary.last_result.builds.append(broken.state.realm.sanctuary.last_result.builds[0].duplicate(true))
	_check(not SaveStore.valid(broken), "saved build result rejects duplicate payment records")


func _test_drafts_and_legacy() -> void:
	for seed_value in [1, 27, 61427, 88001]:
		var old := GameSession.new(content.duplicate(true))
		var old_config := CONFIG.duplicate(true)
		old_config.village_relics = true
		old.start_run(seed_value, "settler", old_config)
		old.state.perk_offer = []
		var reduced := GameSession.new(old.content.duplicate(true))
		reduced.state = old.state.duplicate(true)
		reduced.profile = old.profile.duplicate(true)
		reduced.content.operating_builds.builds = {}
		for id in reduced.content.village_relics.relics.keys():
			if reduced.content.village_relics.relics[id].get("plus_only", false): reduced.content.village_relics.relics.erase(id)
		for index in 4:
			VillageRelics.request_offer(old.state, old.content, "legacy:%d" % index)
			VillageRelics.request_offer(reduced.state, reduced.content, "legacy:%d" % index)
			_check(old.state.realm.sanctuary.offer == reduced.state.realm.sanctuary.offer, "legacy twelve-relic RNG remains unchanged for seed " + str(seed_value))
			old.choose_relic(str(old.state.realm.sanctuary.offer[0]))
			reduced.choose_relic(str(reduced.state.realm.sanctuary.offer[0]))
		_check(OperatingBuilds.active(old.state, content).is_empty() and OperatingBuilds.bonuses(old.state, content) == {"mods":{},"targets":{}}, "legacy saves receive no build economy")
		var game := _fixture_build("")
		_take(game, "P01")
		var before: Dictionary = game.state.duplicate(true)
		var matching := OperatingBuilds.matching_relics(game.state, content, VillageRelics.available_ids(game.state, content))
		VillageRelics.request_offer(game.state, content, "matching")
		_check(game.state.realm.sanctuary.offer[0] in matching, "expanded first draft slot follows an already-owned perk family")
		var same := before.duplicate(true)
		VillageRelics.request_offer(same, content, "matching")
		_check(same.realm.sanctuary.offer == game.state.realm.sanctuary.offer and before.realm.rolls == game.state.realm.rolls, "matching draft is seeded and never consumes event RNG")


func _test_eight_years() -> void:
	var completed := 0
	for seed_value in [61427, 88001, 4711, 27, 1, 1207, 911, 5731]:
		var game := _new(seed_value)
		var result := _play(game, true)
		_check(game.state.status == "finalized" and game.state.week == 53, "real resource-limited expanded run reaches first-year settlement: " + str(seed_value))
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "expanded full-year results survive save roundtrip: " + str(seed_value))
		completed += 1 if result.success else 0
		print("BUILD RUN seed=%d success=%s week=%d gold=%d active=%s" % [seed_value, result.success, game.state.week, result.money, str(OperatingBuilds.active(game.state, content))])
	_check(completed >= 2, "prepared play remains capable of successful first-year completion with expanded content")
