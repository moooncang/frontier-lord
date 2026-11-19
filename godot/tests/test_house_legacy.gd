extends "res://tests/test_crisis_director.gd"
## Uses only isolated fixture saves; no running user game or user profile is touched.


func _init() -> void:
	content = Content.load_all()
	_test_house_purchases()
	_test_house_preparation()
	_test_house_doctrines()
	_test_house_economy()
	_test_house_choices()
	_test_house_saves()
	_test_house_legacy_rng()
	_test_house_years()
	print("HOUSE LEGACY: %d checks, %d failures" % [assertions,failures])
	quit(1 if failures else 0)


func _profile() -> Dictionary:
	return {"version":1,"points":10000,"upgrades":[],"receipts":{},"runs":0}


func _learn(profile: Dictionary, id: String, maximum: bool = false) -> void:
	var definition: Dictionary = LegacyPath.definitions().talents[id]
	if definition.requires != "" and LegacyPath.rank(profile, str(definition.requires)) == 0: _learn(profile, str(definition.requires))
	var wanted: int = int(definition.max_rank) if maximum else 1
	while LegacyPath.rank(profile, id) < wanted:
		var error := LegacyPath.buy(profile, id)
		_check(error == "", "purchase prerequisite/level through actual API: " + id)
		if error != "": break


func _all_profile() -> Dictionary:
	var profile := _profile()
	for id in LegacyPath.definitions().talents: _learn(profile, str(id), true)
	return profile


func _house(profile: Dictionary = {}, seed_value: int = 61427) -> GameSession:
	var game := GameSession.new(content.duplicate(true))
	if not profile.is_empty(): game.profile = profile.duplicate(true)
	var config := CONFIG.duplicate(true)
	config.escalation = true
	config.village_relics = true
	game.start_run(seed_value, "settler", config)
	return game


func _test_house_purchases() -> void:
	var profile := _all_profile()
	var data := LegacyPath.definitions()
	var spent := 0
	for definition in data.talents.values():
		for value in definition.costs: spent += int(value)
	_check(profile.legacy_talents.size() == 48 and profile.points == 10000-spent and LegacyPath.valid(profile), "all 48 items have finite correctly charged rank costs")
	var before := profile.duplicate(true)
	for id in data.talents: _check(LegacyPath.buy(profile,id) != "", "max rank blocks repeat purchase: " + id)
	_check(before == profile, "failed purchases cannot change balance or unlocks")
	profile.upgrades = ["M01","M20","M21"]
	LegacyPath.select_doctrine(profile,"LF07")
	LegacyPath.set_preparation(profile,"supply_pack","LA05")
	_check(LegacyPath.refund(profile) == spent and profile.points == 10000 and profile.legacy_doctrines.is_empty() and profile.legacy_preparation.is_empty(), "refund returns exact paid ranks and clears now-locked selections")
	_check(profile.upgrades == ["M01","M20","M21"] and LegacyPath.refund(profile) == 0 and profile.points == 10000, "old eight-upgrade ownership survives and refund cannot manufacture points")
	var overview := LegacyPath.overview(profile)
	_check(overview.items.size() == 48 and overview.branches.size() == 6 and overview.doctrines.size() == 12 and overview.legacy_upgrades.size() == 8, "single overview exposes all house items and preserved historical upgrades")
	_check(overview.items.all(func(row): return row.has("current_text") and row.has("next_text") and row.has("error") and row.has("requires_text") and row.has("application_text")), "UI receives computed costs, conditions, effects and application scope")
	for pair in [["LF05","부임 준비","지원 물자"],["LA06","부임 준비","첫 특전"],["LS06","부임 준비","첫 성물"],["LF06","통치 중 특전 선택 창","새로고침"],["LP06","통치 중 성물 선택 창","새로고침"],["LI06","통치 중 특전 선택 창","후보 제외"],["LD06","물자 예산","자동 반영"]]:
		var item: Dictionary = overview.items.filter(func(row): return row.id == pair[0])[0]
		_check(str(item.application_text).contains(pair[1]) and str(item.application_text).contains(pair[2]), "choice application text names its actual phase and action: " + str(pair[0]))
	print("HOUSE FULL COST ", spent, " points")


func _test_house_preparation() -> void:
	var profile := _all_profile()
	for id in ["LF05","LA05","LS05","LP05","LI05","LD05"]:
		profile.legacy_preparation = {}
		var plain := _house(profile)
		_check(LegacyPath.set_preparation(profile,"supply_pack",id) == "", "unlocked support package can be selected: " + id)
		var prepared := _house(profile)
		var resources: Dictionary = LegacyPath.definitions().talents[id].choice.resources
		for asset in prepared.state.public:
			_check(is_equal_approx(float(prepared.state.public[asset])-float(plain.state.public[asset]),float(resources.get(asset,0))), "exactly one selected package reaches starting public inventory: " + id + "/" + asset)
		var snapshot: Dictionary = prepared.state.duplicate(true)
		LegacyPath.apply(prepared.state, profile)
		_check(prepared.state == snapshot, "reapplying preparation never repeats a package")
	var empty := _profile()
	var saved := empty.duplicate(true)
	_check(LegacyPath.set_preparation(empty,"supply_pack","LF05") != "" and empty == saved, "locked support package cannot be forged by configuration")
	var gear := _profile()
	_check(LegacyPath.equipment_budget(gear) == 3, "default equipment allowance stays three")
	gear.upgrades = ["M20"]
	_check(LegacyPath.equipment_budget(gear) == 4, "old M20 retains its original equipment allowance")
	_learn(gear,"LD06")
	_check(LegacyPath.equipment_budget(gear) == 5, "new allowance adds one to the preserved M20 bonus")
	var game := GameSession.new(content)
	game.profile = gear
	var config := CONFIG.duplicate(true)
	config.escalation = true
	config.village_relics = true
	config.relics = ["seeds","lantern","axe"]
	game.start_run(61427,"settler",config)
	_check(game.state.relics == ["seeds","lantern","axe"], "five-point allowance is actually consumed during Chronicle setup")


func _test_house_doctrines() -> void:
	var profile := _all_profile()
	for id in LegacyPath.definitions().talents:
		var definition: Dictionary = LegacyPath.definitions().talents[id]
		if definition.kind != "doctrine": continue
		profile.legacy_doctrines = []
		var plain := _house(profile)
		_check(LegacyPath.select_doctrine(profile,id) == "", "learned doctrine can occupy a preparation slot: " + id)
		var equipped := _house(profile)
		for key in definition.doctrine.get("mods", {}):
			_check(is_equal_approx(RealmRules.mod(equipped.state,key)/RealmRules.mod(plain.state,key),float(definition.doctrine.mods[key])), "doctrine benefit/downside reaches actual economic modifier once: " + id + "/" + key)
		for key in definition.doctrine.get("targets", {}):
			_check(is_equal_approx(RealmRules.target(equipped.state,key)-RealmRules.target(plain.state,key),float(definition.doctrine.targets[key])), "doctrine stat target changes exactly as declared: " + id + "/" + key)
		for key in equipped.state.public:
			_check(is_equal_approx(float(equipped.state.public[key])-float(plain.state.public[key]),float(definition.doctrine.get("resources",{}).get(key,0))), "doctrine starting grant appears once: " + id + "/" + key)
		var mods: Dictionary = equipped.state.realm.mods.duplicate(true)
		for repeat in 5: RealmRules.refresh(equipped.state,content)
		_check(equipped.state.realm.mods == mods, "reopening panels never stacks doctrine effects: " + id)
	profile.legacy_doctrines = []
	_check(LegacyPath.select_doctrine(profile,"LA07") == "" and LegacyPath.select_doctrine(profile,"LS08") == "", "two different house doctrines can be prepared")
	var before := profile.duplicate(true)
	_check(LegacyPath.select_doctrine(profile,"LI07") != "" and profile == before, "third doctrine cannot silently apply")
	_check(LegacyPath.select_doctrine(profile,"LI07","LA07") == "" and profile.legacy_doctrines == ["LI07","LS08"], "replacement preserves exactly two selections")
	var game := _house(profile)
	var active: Dictionary = game.state.duplicate(true)
	_check(game.set_legacy_doctrine("LF07","LI07") != "" and game.remove_legacy_doctrine("LI07") != "" and game.set_legacy_preparation("supply_pack","LF05") != "" and game.buy_talent("LF01") != "" and game.buy_upgrade("M01") != "" and game.refund_talents() == 0, "all family editing paths are blocked during active governance")
	_check(game.state == active, "blocked preparation edits preserve active resources and snapshot")
	LegacyPath.refund(game.profile)
	RealmRules.refresh(game.state,content)
	_check(game.state.legacy_setup == active.legacy_setup and game.state.realm.mods == active.realm.mods and SaveStore.valid(game.bundle()), "external profile redistribution cannot change frozen active doctrine effects")


func _test_house_economy() -> void:
	var profile := _all_profile()
	var cases := {
		"LF07":[["wages","money",false,.9],["maintenance","money",false,.8]],
		"LF08":[["maintenance","money",false,1.12]],
		"LA07":[["harvest","food",true,1.2],["garden","food",true,1.15],["logging","wood",true,.85]],
		"LA08":[["gather","food",true,1.25],["harvest","food",true,.9]],
		"LS08":[["heating","fuel",false,.75],["logging","tools",false,1.1]],
		"LP07":[["wages","money",false,1.15]],
		"LP08":[["logging","tools",false,.75]],
		"LI07":[["logging","wood",true,1.2],["quarry","stone",true,1.2],["quarry","tools",false,1.2]],
		"LI08":[["smithy","tools",true,1.35],["maintenance","money",false,1.15]],
		"LD08":[["wages","money",false,1.15]]}
	for id in cases:
		profile.legacy_doctrines = []
		var plain := _house(profile)
		profile.legacy_doctrines = [id]
		var equipped := _house(profile)
		for game in [plain,equipped]:
			_clear(game)
			game.state.cabinet.enabled = false
			game.state.workcrew.enabled = false
			for key in game.state.assign: game.state.assign[key] = 0
			game.state.week = 40 if id == "LS08" else 33 if id in ["LA07","LA08"] else 1
			game.state.plots_sown = 4
			game.state.sow_f_sum = 1.0
			for facility in ["B14","B25","B27","B33"]: game.state.facilities[facility] = 1
			game.state.assign.logging = 4
			game.state.assign.quarry = 4
			game.state.assign.garden = 4
			game.state.assign.gather = 4
			game.state.public.tools = 200.0
			game.state.public.wood = 200.0
			game.state.public.stone = 200.0
			game.state.public.fuel = 500.0
			game.state.public.food = 2000.0
			game.state.resident.food = 2000.0
			RealmRules.refresh(game.state,content)
			if id in ["LP07","LP08"]: _check(game.queue_build("B22") == "", "real construction starts with selected doctrine")
		var reports := [WeekSim.process_week(plain.state,content),WeekSim.process_week(equipped.state,content)]
		_check(reports[0].advanced and reports[1].advanced, "real paired economy advances for doctrine " + id)
		for row in cases[id]:
			var base := VillageRelics._flow(plain.state.ledger,row[0],row[1],row[2])
			var actual := VillageRelics._flow(equipped.state.ledger,row[0],row[1],row[2])
			var tolerance := 1.01 if row[1] == "money" else .00001
			_check(base > 0 and absf(actual-base*float(row[3])) <= tolerance, "actual ledger applies declared doctrine benefit or downside: " + id + "/" + str(row[0]))
		if id in ["LP07","LP08"]:
			var modifier: float = .8 if id == "LP07" else 1.1
			_check(equipped.state.projects[0].work_total == ceili(plain.state.projects[0].work_total*modifier), "construction work contract receives the doctrine multiplier once")
			for pair in [[plain,reports[0]],[equipped,reports[1]]]:
				var project: Dictionary = pair[0].state.projects[0]
				var expected_note := "%s 착공 (%d인주)" % [content.facilities[project.id].name,int(project.work_total)]
				_check(expected_note in pair[1].notes, "construction news displays the same adjusted work total as its live project: " + id)
	profile.legacy_doctrines = []
	var buyer := _house(profile)
	profile.legacy_doctrines = ["LD07"]
	var negotiator := _house(profile)
	var quoted := negotiator.trade_quote("tools", 4, true)
	var cash: int = negotiator.state.public.money
	_check(quoted < buyer.trade_quote("tools",4,true) and negotiator.trade("tools",4,true) == "" and cash-negotiator.state.public.money == quoted, "merchant doctrine lowers the actual price and pays the displayed quote")
	profile.legacy_doctrines = ["LS07"]
	var storehouse := _house(profile)
	_check(is_equal_approx(WeekSim.bonus(storehouse.state,"storage")/WeekSim.bonus(buyer.state,"storage"),1.2) and storehouse.trade_quote("tools",4,true) > buyer.trade_quote("tools",4,true), "storage doctrine's capacity gain has a real purchase-price cost")


func _test_house_choices() -> void:
	var profile := _all_profile()
	profile.upgrades = ["M21"]
	var plain := _house()
	var extra := _house(profile)
	_check(extra.state.refreshes == plain.state.refreshes+2, "new refresh and old M21 each add exactly one actual perk refresh")
	for family in LegacyPath.PERK_FAMILIES:
		LegacyPath.set_preparation(profile,"perk_family",family)
		var game := _house(profile)
		var twin := _house(profile)
		_check(game.state.perk_offer == twin.state.perk_offer and content.progression.perks[game.state.perk_offer[0]].family == family, "first offered perk is seeded and guaranteed to the selected eligible family")
		_check(game.refresh_perks() and content.progression.perks[game.state.perk_offer[0]].family == family, "initial perk refresh retains the chosen family")
		var excluded := str(game.state.perk_offer[0])
		var previous: Array = game.state.perk_offer.duplicate()
		var rolls: int = game.state.realm.rolls
		_check(game.banish_perk(excluded) == "" and game.state.perk_offer[1] == previous[1] and game.state.perk_offer[2] == previous[2] and excluded not in game.state.perk_offer, "exclude replaces only its own candidate and preserves the other two")
		_check(game.state.realm.rolls == rolls and game.state.legacy_setup.perk_banishes == 0 and game.state.legacy_setup.banished_perks == [excluded], "exclusion consumes one saved permission without event RNG")
		var saved: Dictionary = game.state.duplicate(true)
		_check(game.banish_perk(str(game.state.perk_offer[0])) != "" and saved == game.state, "spent exclusion cannot be repeated")
		game.choose_perk(str(game.state.perk_offer[0]))
		for week in [7,14,27,40]:
			game.state.week = week
			game._offer_perks()
			_check(excluded not in game.state.perk_offer, "excluded card stays out of all later relevant pools")
		_check(SaveStore.valid(game.bundle()), "saved excluded-card history and remaining counters agree")
	for family in LegacyPath.RELIC_FAMILIES:
		LegacyPath.set_preparation(profile,"relic_family",family)
		var game := _house(profile)
		VillageRelics.request_offer(game.state,content,"house:first")
		var previous: Array = game.state.realm.sanctuary.offer.duplicate()
		var source := str(game.state.realm.sanctuary.offer_source)
		var sources: Array = game.state.realm.sanctuary.sources.duplicate()
		var rolls: int = game.state.realm.rolls
		_check(content.village_relics.relics[previous[0]].category == family, "first discovery guarantees the selected eligible relic family")
		_check(game.refresh_relics() == "" and content.village_relics.relics[game.state.realm.sanctuary.offer[0]].category == family, "relic refresh retains the first source's family guarantee")
		_check(game.state.realm.sanctuary.offer.any(func(id): return id not in previous) and game.state.realm.sanctuary.offer_source == source and game.state.realm.sanctuary.sources == sources and game.state.realm.rolls == rolls, "relic refresh introduces a fresh choice without new reward source or event RNG")
		var saved: Dictionary = game.state.duplicate(true)
		_check(game.refresh_relics() != "" and game.state == saved, "spent relic refresh cannot be repeated")
		_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "refreshed first-source offer remains saveable")
	var unavailable := _profile()
	var saved := unavailable.duplicate(true)
	_check(LegacyPath.set_preparation(unavailable,"perk_family","court") != "" and LegacyPath.set_preparation(unavailable,"relic_family","guard") != "" and unavailable == saved, "locked family choices cannot be injected")


func _test_house_saves() -> void:
	var profile := _all_profile()
	LegacyPath.select_doctrine(profile,"LF07")
	LegacyPath.select_doctrine(profile,"LD08")
	LegacyPath.set_preparation(profile,"supply_pack","LP05")
	LegacyPath.set_preparation(profile,"perk_family","industry")
	var game := _house(profile)
	game.banish_perk(str(game.state.perk_offer[0]))
	var store := SaveStore.new("res://tests/output/house_%d" % Time.get_ticks_usec())
	_check(store.write(game.bundle()) == "", "purchased ranks, selected doctrines, pack and used permission write through real save")
	var loaded := store.read()
	_check(loaded.ok and store.write(loaded.bundle) == "", "normalized JSON preparation can be loaded and autosaved again")
	if loaded.ok:
		var current: Dictionary = loaded.bundle.state
		var before := current.duplicate(true)
		LegacyPath.apply(current,loaded.bundle.profile)
		_check(current == before, "loading a run does not repeat starting grants")
	for kind in ["third_doctrine","locked_pack","bad_family","infinite_counter","wrong_effect","forgotten_banish"]:
		var broken := game.bundle().duplicate(true)
		match kind:
			"third_doctrine": broken.profile.legacy_doctrines.append("LA07")
			"locked_pack": broken.profile.legacy_preparation.supply_pack = "LF01"
			"bad_family": broken.state.legacy_setup.preparation.perk_family = "unknown"
			"infinite_counter": broken.state.legacy_setup.relic_refreshes = 5
			"wrong_effect": broken.state.legacy_setup.mods.wages = .01
			"forgotten_banish": broken.state.legacy_setup.banished_perks = []
		_check(not SaveStore.valid(broken), "save validator rejects preparation corruption: " + kind)


func _test_house_legacy_rng() -> void:
	for seed_value in [1,27,61427]:
		var game := _house({},seed_value)
		var without := GameSession.new(game.content)
		without.profile = game.profile.duplicate(true)
		without.state = game.state.duplicate(true)
		without.state.erase("legacy_setup")
		game.state.drafts = 0
		without.state.drafts = 0
		game._offer_perks()
		without._offer_perks()
		_check(game.state.perk_offer == without.state.perk_offer, "no new unlock keeps exact prior perk RNG")
		VillageRelics.request_offer(game.state,content,"old:first")
		VillageRelics.request_offer(without.state,content,"old:first")
		_check(game.state.realm.sanctuary.offer == without.state.realm.sanctuary.offer, "no new unlock keeps exact prior relic RNG")
		var old := without.bundle()
		old.profile.erase("legacy_talents")
		old.profile.erase("legacy_doctrines")
		old.profile.erase("legacy_preparation")
		_check(SaveStore.valid(old), "old save with no new preparation fields remains valid")


func _test_house_years() -> void:
	var profile := _all_profile()
	for pair in [["LA07","LS08"],["LI07","LF07"],["LP07","LI08"],["LD07","LD08"]]:
		profile.legacy_doctrines = pair.duplicate()
		LegacyPath.set_preparation(profile,"supply_pack","LP05")
		LegacyPath.set_preparation(profile,"perk_family","industry")
		LegacyPath.set_preparation(profile,"relic_family","craft")
		var game := _house(profile,61427)
		var result := _play(game,true)
		_check(game.state.week == 53 and game.state.status == "finalized" and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))), "fully learned and equipped house completes a real 52-week saveable run")
		print("HOUSE RUN doctrines=%s success=%s gold=%d food=%.1f" % [str(pair),result.success,result.money,WeekSim.food_weeks(game.state)])
