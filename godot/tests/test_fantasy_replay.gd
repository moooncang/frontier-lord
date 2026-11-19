extends SceneTree
## Independent integration audit. Uses production actions and isolated save files only.

var checks := 0
var failures := 0
var content: Dictionary
var discovered := {}
var completed := {}
var branches := {}
var build_started := {}
var build_finished := {}
var production := {}
const PATHS := ["grove", "ember", "tide", "clockwork", "veil", "astral"]
const CONFIG := {"region":"forest", "candidate":0, "relics":["seeds","axe"], "tutorial":false,
	"cabinet":true, "campaign":true, "workcrew":true, "realm":true, "modifiers":true,
	"village_relics":true, "escalation":true, "seasonal_support":true, "difficulty":0}


func _init() -> void:
	content = Content.load_all()
	_test_plan_and_queries()
	_test_legacy_neutrality()
	_test_replay_paths()
	print("FANTASY REPLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FANTASY REPLAY FAIL: ", message)


func _new(seed_value: int, fantasy: bool = true, include_flag: bool = true) -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	if include_flag: config["fantasy"] = fantasy
	game.start_run(seed_value, "settler", config)
	return game


func _test_plan_and_queries() -> void:
	_check(Content.validate(content).is_empty(), "combined fantasy content validates")
	var catalog := content.duplicate(true)
	var coverage := {}
	for seed_value in range(1,49):
		var game := _new(seed_value)
		var twin := _new(seed_value)
		_check(game.state.fantasy == twin.state.fantasy, "same seed fixes the fantasy discovery plan: %d" % seed_value)
		var ids := []
		var weeks := []
		for item in game.state.fantasy.plan:
			ids.append(str(item.id))
			weeks.append(int(item.week))
			coverage[item.id] = true
		_check(ids.size() == 3 and ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2], "three distinct discoveries: %d" % seed_value)
		_check(weeks == [8,14,20], "discoveries avoid the first action tutorial: %d" % seed_value)
		var snapshot := game.bundle().duplicate(true)
		for attempt in 3:
			var view: Dictionary = FantasyFrontiers.overview(game.state,content)
			_check(view.enabled and view.limit == 2 and view.paths.size() == 6, "overview exposes six paths and the two-path limit")
			view.selected.append("forged")
			view.paths[0].name = "forged"
			if not view.paths[0].buildings.is_empty(): view.paths[0].buildings[0].cost.money = 999999
		_check(game.bundle() == snapshot, "opening and editing returned views cannot mutate state or RNG")
		_check(content == catalog, "returned view cannot mutate the shared event or building definitions")
		_check(SaveStore.valid(game.bundle()), "new fantasy run is immediately saveable")
	_check(coverage.size() == 6, "the discovery stream can produce every fantasy path")


func _test_legacy_neutrality() -> void:
	var absent := _new(61427,false,false)
	var disabled := _new(61427,false)
	_check(absent.bundle() == disabled.bundle(), "missing and disabled flags preserve the complete legacy run")
	var snapshot := absent.bundle().duplicate(true)
	var enabled := _new(61427,true)
	_check(enabled.state.realm.rolls == absent.state.realm.rolls and enabled.state.perk_offer == absent.state.perk_offer and enabled.state.expedition_modifiers == absent.state.expedition_modifiers, "planning fantasy discoveries never consumes existing event, perk or environment randomness")
	var view: Dictionary = FantasyFrontiers.overview(absent.state,content)
	_check(not view.enabled and absent.bundle() == snapshot, "inspecting an old run cannot opt it into fantasy content")
	_check(SaveStore.valid(absent.bundle()), "a pre-fantasy save still validates")
	var restored := _roundtrip(absent,"legacy")
	_check(not FantasyFrontiers.overview(restored.state,content).enabled, "loading an old run remains neutral")
	for week in 21:
		_resolve(absent,"","care")
		_resolve(disabled,"","care")
		var first := absent.advance()
		var second := disabled.advance()
		_check(first.advanced and second.advanced and absent.bundle() == disabled.bundle(), "old saves remain identical through discovery boundary %d" % (week+1))
		_check(not absent.state.seen_events.any(func(id): return str(id).begins_with("FF_")), "fantasy events never enter the old-save event pool")


func _roundtrip(game: GameSession, tag: String) -> GameSession:
	var directory := "res://tests/output/fantasy_replay_%s_%s" % [str(Time.get_ticks_usec()),tag]
	var store := SaveStore.new(directory)
	_check(SaveStore.valid(game.bundle()) and store.write(game.bundle()) == "", "native state writes to an isolated slot: "+tag)
	var saved := store.read()
	_check(saved.ok, "isolated slot can be read: "+tag)
	if not saved.ok: return game
	var restored := GameSession.new(content)
	restored.state = saved.bundle.state
	restored.profile = saved.bundle.profile
	_check(_same(game.bundle(),restored.bundle()), "disk roundtrip preserves resources, discovery plan and decisions: "+tag)
	_check(store.write(restored.bundle()) == "" and store.sequence == 2, "loaded state can be saved again without normalization rejection: "+tag)
	return restored


func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b)) <= 0.0000001 * maxf(1.0,maxf(absf(float(a)),absf(float(b))))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not _same(a[index],b[index]): return false
		return true
	return typeof(a) == typeof(b) and a == b


func _test_replay_paths() -> void:
	var seeds := {}
	for seed_value in range(1,129):
		for item in _new(seed_value).state.fantasy.plan:
			if not seeds.has(item.id): seeds[item.id] = seed_value
		if seeds.size() == PATHS.size(): break
	for path in PATHS:
		_check(seeds.has(path), "a reproducible seed reaches path "+path)
		if not seeds.has(path): continue
		for branch in ["care","drive"]:
			var game := _new(int(seeds[path]))
			# Generous starting stores isolate progression from balance. No facility or week is fabricated.
			game.state.public.money = 100000
			game.state.public.food = 5000.0
			game.state.resident.food = 5000.0
			for resource in ["wood","stone","tools","fuel"]: game.state.public[resource] = 1000.0
			var result := _play(game,path,branch,true)
			_check(result.state.week == 53, "fixture reaches a real full-year ending: "+path+" / "+branch)
			var row: Dictionary = FantasyFrontiers.overview(result.state,content).paths.filter(func(value): return value.id == path)[0]
			_check(row.selected and row.branch == branch and row.completed and int(row.background_stage) == 3, "all three facilities and final reward are reachable: "+path+" / "+branch)
			_check(result.state.fantasy.selected.size() == 1, "declined discoveries cannot become adopted paths")
			_check(SaveStore.valid(result.bundle()), "completed fantasy path is saveable")
			for building in row.buildings:
				var definition: Dictionary = content.facilities[building.id]
				for resource in definition.get("output",{}):
					_check(float(production.get(building.id+":"+str(resource),0.0)) > 0, "completed producer really delivers its output: "+building.id+" / "+str(resource))
				var without := result.state.duplicate(true)
				without.facilities.erase(building.id)
				RealmRules.refresh(without,content)
				for key in definition.get("mods",{}):
					_check(is_equal_approx(RealmRules.mod(result.state,str(key))/RealmRules.mod(without,str(key)),float(definition.mods[key])), "each completed facility's live multiplier is consumed once: "+building.id+" / "+str(key))
	for seed_value in [61427,88001]:
		var game := _new(seed_value)
		var result := _play(game,"","care",false)
		var view: Dictionary = FantasyFrontiers.overview(result.state,content)
		var totals := []
		for row in view.paths:
			if row.selected: totals.append("%s:%d/3%s" % [row.id,row.background_stage," complete" if row.completed else ""])
		print("FANTASY ECONOMY seed=%d week=%d selected=%s first=%s final=%s production=%s gold=%.2f food=%.1f success=%s" % [seed_value,result.state.week,str(totals),str(build_started),str(build_finished),str(production),float(result.state.public.money)/100.0,WeekSim.food_weeks(result.state),str(result.state.get("result",{}).get("success",false))])
		_check(result.state.week == 53 and result.state.status == "finalized", "actual starting-resource fantasy run reaches settlement: %d" % seed_value)
		_check(view.selected.size() == 2, "real run adopts two discoveries and handles the third decline")
		_check(view.paths.any(func(row): return row.selected and row.background_stage >= 1), "real run can afford a functional fantasy building")
		var baseline := _play(_new(seed_value,false),"","care",false)
		print("FANTASY BASELINE seed=%d week=%d gold=%.2f food=%.1f success=%s" % [seed_value,baseline.state.week,float(baseline.state.public.money)/100.0,WeekSim.food_weeks(baseline.state),str(baseline.state.get("result",{}).get("success",false))])
		_check(baseline.state.week == 53 and not baseline.state.has("fantasy"), "same operator can compare a complete legacy economy without fabricated resources")


func _resolve(game: GameSession, focus: String, branch: String) -> void:
	for guard in 30:
		if not game.state.perk_offer.is_empty():
			var wanted: String = str(content.fantasy_frontiers.paths.get(focus,{}).get("family",""))
			var candidates: Array = game.state.perk_offer.filter(func(id): return content.progression.perks[id].family == wanted)
			game.choose_perk(str(candidates[0] if not candidates.is_empty() else game.state.perk_offer[0]))
			continue
		if not game.state.get("contract_offer",[]).is_empty():
			game.choose_contract(str(game.state.contract_offer[0]))
			continue
		if not game.state.realm.sanctuary.offer.is_empty():
			_check(game.choose_relic(str(game.state.realm.sanctuary.offer[0])) == "", "fantasy rewards coexist with the existing relic queue")
			continue
		if str(game.state.active_event).is_empty(): return
		var event: Dictionary = RealmRules.event_definition(game.state,content,str(game.state.active_event))
		var candidates := []
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			var meta: Dictionary = option.get("fantasy",{})
			if not meta.is_empty():
				if meta.action in ["accept","decline"]:
					var accept: bool = (focus == "" or focus == meta.path) and game.state.fantasy.selected.size() < 2
					if (meta.action == "accept") != accept: continue
				elif meta.action == "branch" and str(meta.get("branch","")) != branch: continue
			if game.option_error(option) == "": candidates.append(index)
		_check(not candidates.is_empty(), "every encountered event has an affordable chosen or fallback decision: "+str(game.state.active_event))
		if candidates.is_empty(): return
		var selected_index: int = int(candidates[0])
		# Avoid spending the last survival stores on ordinary optional deals.
		if not str(game.state.active_event).begins_with("FF_"):
			for index in candidates:
				var option: Dictionary = event.options[index]
				if option.get("cost",{}).is_empty() and not option.has("chance"):
					selected_index = index
					break
		var id: String = str(game.state.active_event)
		_check(game.choose_event(selected_index) == "", "actual event choice resolves "+id)
		if id.begins_with("FF_"): discovered[id] = true
		_check(SaveStore.valid(game.bundle()), "event result is valid natively: "+id)
	_check(false, "pending choices terminate instead of forming a modal loop")


func _play(game: GameSession, focus: String, branch: String, fixture: bool) -> GameSession:
	build_started = {}
	build_finished = {}
	production = {}
	var saved_weeks := {}
	for guard in 55:
		if game.state.status != "active": break
		_resolve(game,focus,branch)
		_develop(game,fixture)
		var s: Dictionary = game.state
		var policy := "build" if not s.orders.is_empty() or not s.projects.is_empty() else "balanced"
		var fuel_goal := float(s.pop)*0.1*13.0*WeekSim.bonus(s,"heating")*1.4
		if int(s.week) >= 24 and s.public.fuel < fuel_goal and s.facilities.get("B25",0) > 0: policy = "winter"
		WorkcrewRules.select(s,content,policy)
		if WeekSim.food_weeks(s) < (15.0 if s.week >= 38 else 7.0) and s.public.money > 1200 and not s.shipments.any(func(row): return row.asset == "food"): CabinetActions.buy_supply(game,"food")
		for resource in ["stone","tools","wood","fuel"]:
			var floor_value: float = {"stone":12,"tools":3,"wood":16,"fuel":fuel_goal*0.6 if s.week >= 30 else 16.0}[resource]
			if float(s.public[resource]) < floor_value and s.public.money > 2200 and not s.shipments.any(func(row): return row.asset == resource): CabinetActions.buy_supply(game,resource)
		var before_facilities: Dictionary = s.facilities.duplicate(true)
		var report := game.advance()
		_check(report.advanced, "actual weekly processing continues at week %d: %s" % [s.week,str(report.get("notes",[]))])
		if not report.advanced: break
		for id in s.facilities:
			if str(id).begins_with("F") and not before_facilities.has(id): build_finished[id] = int(report.week)
		for entry in s.ledger:
			if int(entry.w) == int(report.week) and str(entry.src).begins_with("fantasy:") and float(entry.qty) > 0:
				var key: String = str(entry.src).trim_prefix("fantasy:")+":"+str(entry.asset)
				production[key] = float(production.get(key,0.0))+float(entry.qty)
		_check(SaveStore.valid(game.bundle()), "every actual weekly state remains saveable")
		for resource in ["money","food","wood","stone","tools","fuel"]:
			_check(float(s.public[resource]) >= -0.000001, "fantasy progression cannot create negative public stores")
		if FantasyFrontiers.enabled(s): _check(s.fantasy.selected.size() <= 2, "adoption limit holds throughout a live year")
		if int(s.week) in [9,17,29,42] and not saved_weeks.has(s.week):
			saved_weeks[s.week] = true
			game = _roundtrip(game,"%s_%s_%d" % [focus,branch,s.week])
	return game


func _develop(game: GameSession, fixture: bool) -> void:
	var s: Dictionary = game.state
	if not s.orders.is_empty() or not s.projects.is_empty(): return
	var candidates: Array = []
	if int(s.facilities.get("B13",0)) < 6: candidates.append("B13")
	for id in ["B22","B25","B01"]:
		if int(s.facilities.get(id,0)) == 0: candidates.append(id)
	var view: Dictionary = FantasyFrontiers.overview(s,content)
	for path in view.paths:
		if not path.selected: continue
		for building in path.buildings:
			if building.unlocked and not building.built and not building.queued: candidates.append(str(building.id)); break
	for id in ["B14","B27","B57","B67","B49"]:
		if int(s.facilities.get(id,0)) == 0: candidates.append(id)
	for id in candidates:
		var offer: Dictionary = CabinetActions.offer(game,str(id))
		if str(offer.error) != "": continue
		if not fixture and float(s.public.money)-float(offer.cost.money) < 1500: continue
		if CabinetActions.start_project(game,str(id)) == "":
			if str(id).begins_with("F"): build_started[id] = int(s.week)
			break
