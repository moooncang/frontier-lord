extends "res://tests/test_crisis_director.gd"
## 긍정·부정 사건의 실제 선택, 예약 보호, 후속 저장, 후보 격리와 같은 정책의 52주 비교.

var expansion_events := {}
var good_events := {}
var bad_events := {}
const EVENT_FILES := ["events","realm_events","relic_events","realm_events_plus","realm_events_good","realm_events_bad"]
const EA_ASSETS := ["money","food","wood","stone","tools","fuel"]
const EA_STATS := ["mood","health","security","trust","village","guild"]
const EA_EFFECTS := ["money","food","wood","stone","tools","fuel","resident_food","pop","mood","health","security","trust","village","guild","crop","perm","threat","trade_discount","flag"]
const EA_MODS := ["gather","logging","harvest","seed","sow_labor","storage","tool_use","heating","buy","wages","maintenance","spoil","build_work"]
const FAMILY_EXAMPLE := {"abundance":"F01","craft":"C01","guard":"G01"}
var save_root := ""


func _init() -> void:
	for name in ["realm_events_good","realm_events_bad"]:
		if not FileAccess.file_exists("res://content/%s.json" % name):
			printerr("EVENT EXPANSION BLOCKED: missing content/%s.json" % name)
			quit(2)
			return
	content = Content.load_all()
	good_events = Content._load("res://content/realm_events_good.json")
	bad_events = Content._load("res://content/realm_events_bad.json")
	expansion_events.merge(good_events)
	expansion_events.merge(bad_events)
	save_root = "res://tests/output/event_expansion_%d" % Time.get_ticks_usec()
	_expansion_schema()
	_expansion_pools()
	_expansion_choices()
	_expansion_scarcity()
	_expansion_followups()
	_cargo_recovery_boundary()
	_reward_delta_precision()
	_expansion_playthroughs()
	print("EVENT EXPANSION: %d checks, %d failures" % [assertions,failures])
	quit(1 if failures else 0)


func _event_game(seed_value: int = 61427) -> GameSession:
	var game := _new(seed_value)
	game.state.perk_offer = []
	game.state.active_event = ""
	game.state.realm.queue = []
	game.state.realm.next_event = 999
	return game


func _event_rich(seed_value: int = 61427) -> GameSession:
	var game := _event_game(seed_value)
	for key in EA_ASSETS: game.state.public[key] = 100000 if key == "money" else 4000.0
	game.state.resident.food = 4000.0
	game.state.resident.money = 100000
	for key in EA_STATS: game.state[key] = 55.0
	game.state.realm.threat = 30.0
	game.state.trade_discount = .1
	for id in content.facilities:
		if str(id).begins_with("B"): game.state.facilities[id] = 1
	game.state.facilities.B01 = 8
	game.state.facilities.B13 = 4
	game.state.realm.sanctuary.owned = ["F01","C01","G01"]
	game.state.realm.sanctuary.equipped = ["F01","C01","G01"]
	RealmRules.refresh(game.state,game.content)
	return game


func _meet(game: GameSession, option: Dictionary) -> void:
	var need: Dictionary = option.get("requires",{})
	if need.has("facility"): game.state.facilities[need.facility] = maxi(1,int(game.state.facilities.get(need.facility,0)))
	if need.has("stat"): game.state[need.stat[0]] = maxf(float(game.state[need.stat[0]]),float(need.stat[1]))
	if need.has("policy") and need.policy not in game.state.realm.policies: game.state.realm.policies.append(need.policy)
	if option.has("requires_housing"): game.state.facilities.B01 = 8
	RealmRules.refresh(game.state,game.content)


func _unconditional(option: Dictionary) -> bool:
	return option.get("cost",{}).is_empty() and option.get("requires",{}).is_empty() and not option.has("requires_housing") and not option.has("chance")


func _effect_schema(effects: Dictionary, context: String) -> void:
	for key in effects:
		_check(key in EA_EFFECTS,"known consumed event effect: " + context + "/" + key)
		if key == "flag":
			_check(effects[key] is String and not str(effects[key]).is_empty(),"nonempty recorded flag: " + context)
		elif key == "perm":
			_check(effects[key] is Dictionary,"run effect is a multiplier dictionary: " + context)
			for modifier in effects[key]:
				_check(modifier in EA_MODS and is_finite(float(effects[key][modifier])) and float(effects[key][modifier]) > 0,"real positive multiplier: " + context + "/" + modifier)
		else:
			_check((effects[key] is int or effects[key] is float) and is_finite(float(effects[key])),"finite numeric effect: " + context + "/" + key)
			if key == "crop": _check(float(effects[key]) > -1.0,"crop can never produce negative harvest")


func _has_crop(event: Dictionary) -> bool:
	for option in event.options:
		if option.get("effects",{}).has("crop"): return true
		if option.has("chance"):
			for branch in ["win","lose"]:
				if option.chance[branch].get("effects",{}).has("crop"): return true
	return false


func _expansion_schema() -> void:
	_check(Content.validate(content).is_empty(),"full 166-event content validates: " + str(Content.validate(content)))
	var historical_events: Array = content.events.keys().filter(func(id): return not content.events[id].get("fantasy_only",false))
	_check(historical_events.size() == 166 and expansion_events.size() == 80,"166 historical events including exactly 80 additions, separate from fantasy chains")
	var seen := {}
	for filename in EVENT_FILES:
		for id in Content._load("res://content/%s.json" % filename):
			_check(not seen.has(id),"no overwritten event ID across six files: " + id)
			seen[id] = true
	var incoming := {}
	for group in [[good_events,"positive"],[bad_events,"negative"]]:
		var data: Dictionary = group[0]
		_check(data.size() == 40,"40 authored events per tone: " + group[1])
		var roots := 0
		for id in data:
			var event: Dictionary = data[id]
			_check(event.get("realm") == true and event.get("plus_only") == true and int(event.week) == 999,"expansion-only realm scheduling: " + id)
			_check(event.get("tone") == group[1],"explicit matching event tone: " + id)
			_check(event.body is String and event.body.length() <= 100 and event.body.count(".") <= 3,"brief readable event body: " + id)
			_check(content.chronicle.characters.has(event.portrait) and content.chronicle.characters[event.portrait].name == event.speaker,"established speaker uses matching portrait: " + id)
			_check(event.options.size() >= 2 and event.options.size() <= 4,"bounded actual decisions: " + id)
			_check(event.options.any(_unconditional),"deterministic free ungated fallback: " + id)
			if event.has("pool"):
				roots += 1
				_check(event.pool.get("once") == true and int(event.pool.get("weight",0)) > 0,"no recurring resource farming: " + id)
				_check(int(event.pool.min) >= 1 and int(event.pool.min) <= int(event.pool.max) and int(event.pool.max) <= 51,"valid playable week range: " + id)
				if event.pool.has("facility"): _check(content.facilities.has(event.pool.facility),"real pool building: " + id)
				for season in event.pool.get("seasons",[]): _check(int(season) in range(4),"known season: " + id)
				if _has_crop(event): _check(int(event.pool.max) <= 36,"crop choice still precedes a real harvest: " + id)
			for option in event.options:
				_check(option.label.length() <= 26,"compact actionable option: " + id)
				for key in option.get("cost",{}): _check(key in EA_ASSETS and is_finite(float(option.cost[key])) and float(option.cost[key]) > 0,"real payable positive cost: " + id)
				_effect_schema(option.get("effects",{}),id)
				var need: Dictionary = option.get("requires",{})
				for key in need: _check(key in ["facility","stat","policy","relic_family"],"supported requirement: " + id + "/" + key)
				if need.has("facility"): _check(content.facilities.has(need.facility),"known option facility: " + id)
				if need.has("policy"): _check(content.realm.policies.has(need.policy),"known option policy: " + id)
				if need.has("stat"): _check(need.stat.size() == 2 and need.stat[0] in EA_STATS and float(need.stat[1]) <= 100,"reachable statistic gate: " + id)
				if need.has("relic_family"): _check(content.village_relics.categories.has(need.relic_family),"real equipped relic family: " + id)
				if float(option.get("effects",{}).get("pop",0)) > 0: _check(int(option.get("requires_housing",0)) >= int(option.effects.pop),"new residents require actual housing: " + id)
				if option.has("chance"):
					_check(float(option.chance.base) > 0 and float(option.chance.base) < 1,"risk probability is meaningful: " + id)
					if option.chance.has("stat"): _check(option.chance.stat in EA_STATS,"real chance statistic: " + id)
					for fid in option.chance.get("facility",{}): _check(content.facilities.has(fid),"real chance building: " + id)
					for pid in option.chance.get("policy",{}): _check(content.realm.policies.has(pid),"real chance policy: " + id)
					for branch in ["win","lose"]:
						_effect_schema(option.chance[branch].effects,id + "/" + branch)
						_check(not str(option.chance[branch].text).is_empty(),"risk branch explains its actual result: " + id)
				if option.has("followup"):
					var next: String = option.followup.id
					_check(data.has(next) and not data[next].has("pool"),"authored followup cannot independently roll: " + id)
					_check(int(option.followup.delay) > 0,"followup occurs in a later week: " + id)
					if event.has("pool"):
						var latest := int(event.pool.max)+int(option.followup.delay)
						_check(latest <= 52,"latest possible followup still fits the run: " + id)
						if data.has(next) and _has_crop(data[next]): _check(latest <= 36,"latest queued crop reward still precedes harvest: " + id)
					incoming[next] = true
		_check(roots == 32,"32 independently scheduled roots per tone")
	for id in expansion_events:
		if not expansion_events[id].has("pool"): _check(incoming.has(id),"every followup has an authored reachable parent: " + id)


func _eligible(game: GameSession, id: String) -> bool:
	return RealmRules.eligible(game.state,game.content).any(func(row): return row.id == id)


func _expansion_pools() -> void:
	var legacy := GameSession.new(content)
	var legacy_config := CONFIG.duplicate(true)
	legacy_config["village_relics"] = true
	legacy.start_run(61427,"settler",legacy_config)
	_check(not legacy.state.has("escalation") and SaveStore.valid(legacy.bundle()),"actual old-config save stays neutral and valid under expanded definitions")
	for week in range(1,53):
		legacy.state.week = week
		_check(not RealmRules.eligible(legacy.state,content).any(func(row): return expansion_events.has(row.id)),"old-config pool rejects new positive and negative events throughout the year")
	for id in expansion_events:
		var event: Dictionary = expansion_events[id]
		var game := _event_rich()
		if not event.has("pool"):
			for week in [1,14,27,40,51]:
				game.state.week = week
				_check(not _eligible(game,id),"followup never enters a random pool: " + id)
			continue
		var found := false
		for week in range(1,53):
			game.state.week = week
			var correct: bool = week >= int(event.pool.min) and week <= int(event.pool.max)
			var season := WeekSim.season_of(WeekSim.week_of_year(week))
			if event.pool.has("seasons"): correct = correct and event.pool.seasons.any(func(value): return int(value) == season)
			_check(_eligible(game,id) == correct,"real pool respects week and season: %s/%d" % [id,week])
			if not correct or found: continue
			found = true
			if event.pool.has("facility"):
				var fid: String = event.pool.facility
				game.state.facilities.erase(fid)
				_check(not _eligible(game,id),"facility-locked situation cannot precede building: " + id)
				game.state.facilities[fid] = 1
			game.state.escalation.erase("enabled")
			_check(not _eligible(game,id),"old save excludes new tone events: " + id)
			game.state.escalation.enabled = true
			game.state.seen_events.append(id)
			_check(not _eligible(game,id),"once-per-run rule blocks a repeated situation: " + id)
			game.state.seen_events.erase(id)
		_check(found,"root has at least one reachable week: " + id)


func _resolved_effects(option: Dictionary, won: bool) -> Dictionary:
	var effects: Dictionary = option.get("effects",{}).duplicate(true)
	if option.has("chance"):
		var branch: Dictionary = option.chance.win if won else option.chance.lose
		for key in branch.effects:
			if branch.effects[key] is int or branch.effects[key] is float: effects[key] = float(effects.get(key,0))+float(branch.effects[key])
			else: effects[key] = branch.effects[key].duplicate(true) if branch.effects[key] is Dictionary else branch.effects[key]
	return effects


func _verify_result(game: GameSession, before: Dictionary, option: Dictionary, context: String) -> void:
	var effects := _resolved_effects(option,bool(game.state.realm.outcome.win))
	var held := WeekSim.reserved(before,game.content)
	for key in EA_ASSETS:
		var after_cost := float(before.public[key])-float(option.get("cost",{}).get(key,0))
		var effect := float(effects.get(key,0))
		if effect < 0: effect = -minf(-effect,maxf(0.0,after_cost-float(held.get(key,0))))
		_check(is_equal_approx(float(game.state.public[key]),after_cost+effect),"exact cost and actual available reward/loss: " + context + "/" + key)
	for key in EA_STATS: _check(is_equal_approx(float(game.state[key]),clampf(float(before[key])+float(effects.get(key,0)),0,100)),"actual bounded statistic: " + context + "/" + key)
	_check(is_equal_approx(float(game.state.resident.food),float(before.resident.food)+float(effects.get("resident_food",0))),"resident food follows the stated account: " + context)
	_check(int(game.state.pop) == maxi(1,int(before.pop)+int(effects.get("pop",0))),"population effect respects final resident: " + context)
	_check(is_equal_approx(float(game.state.realm.threat),clampf(float(before.realm.threat)+float(effects.get("threat",0)),0,float(content.realm.threat.max))),"threat effect clamps to actual bounds: " + context)
	if effects.has("crop"): _check(is_equal_approx(float(game.state.realm.crop),float(before.realm.crop)*(1.0+float(effects.crop))),"yearly crop multiplier truly changes: " + context)
	if effects.has("trade_discount"): _check(is_equal_approx(float(game.state.trade_discount),minf(.5,float(before.trade_discount)+float(effects.trade_discount))),"delivery discount is real and capped: " + context)
	if effects.has("flag"): _check(game.state.realm.flags.count(effects.flag) == before.realm.flags.count(effects.flag)+1,"branch flag is recorded once: " + context)
	for key in effects.get("perm",{}): _check(is_equal_approx(float(game.state.realm.perm[key]),float(before.realm.perm.get(key,1.0))*float(effects.perm[key])),"remaining-run modifier actually applied: " + context + "/" + key)
	if option.get("relic_offer",false): _check(not game.state.realm.sanctuary.offer.is_empty(),"promised relic reward opens a real offer: " + context)
	_check(SaveStore.valid(game.bundle()),"native event result remains saveable: " + context)
	_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"serialized event result remains saveable: " + context)


func _expansion_choices() -> void:
	for id in expansion_events:
		var event: Dictionary = expansion_events[id]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			var seen_branches := []
			for seed_value in range(1,129) if option.has("chance") else [1]:
				var game := _event_rich(seed_value)
				_meet(game,option)
				game.state.active_event = id
				var before: Dictionary = game.state.duplicate(true)
				var odds := RealmRules.chance_of(game.state,option)
				_check(game.choose_event(index) == "","actual expanded choice resolves: %s/%d" % [id,index])
				_verify_result(game,before,option,"%s/%d" % [id,index])
				var resolved: Dictionary = game.state.duplicate(true)
				_check(game.choose_event(index) != "" and game.state == resolved,"event result cannot be redeemed twice: " + id)
				if option.has("chance"):
					_check(is_equal_approx(float(game.state.realm.outcome.chance),odds),"shown and applied chance agree: " + id)
					var twin := _event_rich(seed_value)
					_meet(twin,option)
					twin.state.active_event = id
					twin.choose_event(index)
					_check(twin.state == game.state,"same seed and choice reproduce the full branch result: " + id)
					if game.state.realm.outcome.win not in seen_branches: seen_branches.append(game.state.realm.outcome.win)
					if seen_branches.size() == 2: break
			if option.has("chance"): _check(seen_branches.size() == 2,"both authored probability outcomes are reachable: %s/%d" % [id,index])
			_test_option_gate(id,index,option)


func _test_option_gate(id: String, index: int, option: Dictionary) -> void:
	for key in option.get("requires",{}):
		var game := _event_rich()
		_meet(game,option)
		match key:
			"facility": game.state.facilities.erase(option.requires.facility)
			"stat": game.state[option.requires.stat[0]] = float(option.requires.stat[1])-1.0
			"policy": game.state.realm.policies.erase(option.requires.policy)
			"relic_family": game.state.realm.sanctuary.equipped = []
		game.state.active_event = id
		var before: Dictionary = game.state.duplicate(true)
		_check(game.choose_event(index) != "" and game.state == before,"missing gate rejects atomically: " + id + "/" + key)
		if key == "relic_family":
			_check(FAMILY_EXAMPLE[option.requires.relic_family] in game.state.realm.sanctuary.owned,"relic gate fixture owns the needed family")
			game.state.realm.sanctuary.equipped = [FAMILY_EXAMPLE[option.requires.relic_family]]
			_check(game.option_error(option) == "","equipping, not merely owning, unlocks the choice: " + id)
	if option.has("requires_housing"):
		var game := _event_rich()
		game.state.facilities.erase("B01")
		game.state.facilities.erase("T_HOUSING")
		_check(game.option_error(option) != "","no free houses rejects settlement: " + id)


func _expansion_scarcity() -> void:
	for id in expansion_events:
		var event: Dictionary = expansion_events[id]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if not option.get("cost",{}).is_empty():
				var poor := _event_rich()
				_meet(poor,option)
				for key in EA_ASSETS: poor.state.public[key] = 0
				poor.state.active_event = id
				var before: Dictionary = poor.state.duplicate(true)
				_check(poor.choose_event(index) != "" and poor.state == before,"insufficient resources never partially pay or queue: " + id)
			if _unconditional(option):
				var poor := _event_game()
				for key in EA_ASSETS: poor.state.public[key] = 0
				poor.state.resident.food = 0.0
				poor.state.pop = 1
				poor.state.facilities = {}
				poor.state.realm.sanctuary.equipped = []
				poor.state.active_event = id
				_check(poor.choose_event(index) == "","resource-empty estate can finish its decision: " + id)
				_check(poor.state.public.values().all(func(value): return float(value) >= 0) and float(poor.state.resident.food) >= 0 and int(poor.state.pop) >= 1,"free fallback cannot create negative stores or kill final resident: " + id)
			# Reserve an actual farm and leave only the advertised cost available beyond its protected materials.
			var reserved := _event_rich()
			_meet(reserved,option)
			_check(reserved.queue_build("B13") == "","real farm reservation for resource protection")
			var held := WeekSim.reserved(reserved.state,content)
			for key in EA_ASSETS: reserved.state.public[key] = float(held.get(key,0))+float(option.get("cost",{}).get(key,0))
			reserved.state.public.money = int(reserved.state.public.money)
			reserved.state.active_event = id
			var prior: Dictionary = reserved.state.duplicate(true)
			_check(reserved.choose_event(index) == "","only unreserved amount can pay the option: " + id)
			_verify_result(reserved,prior,option,"reserved/" + id)
			_check(WeekSim.validate_orders(reserved.state,content).is_empty(),"negative outcome preserves actual reserved construction: " + id)
			if not option.get("cost",{}).is_empty():
				var blocked := _event_rich()
				_meet(blocked,option)
				blocked.queue_build("B13")
				var blocked_held := WeekSim.reserved(blocked.state,content)
				for key in option.cost: blocked.state.public[key] = float(blocked_held.get(key,0))+float(option.cost[key])-.5
				blocked.state.public.money = int(blocked.state.public.money)
				blocked.state.active_event = id
				var before: Dictionary = blocked.state.duplicate(true)
				_check(blocked.choose_event(index) != "" and blocked.state == before,"event cost cannot borrow reserved resources: " + id)


func _expansion_followups() -> void:
	for id in expansion_events:
		var event: Dictionary = expansion_events[id]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if not option.has("followup"): continue
			var game := _event_rich()
			_meet(game,option)
			game.state.week = int(event.pool.min)
			game.state.active_event = id
			game.choose_event(index)
			var due := int(event.pool.min)+int(option.followup.delay)
			_check(game.state.realm.queue.size() == 1 and game.state.realm.queue[0].id == option.followup.id and int(game.state.realm.queue[0].week) == due,"selected branch queues once at promised due week: " + id)
			_check(game.state.realm.outcome.get("followup",{}).get("id","") == option.followup.id and int(game.state.realm.outcome.get("followup",{}).get("week",0)) == due,"result receipt exposes the same promised followup and due week: " + id)
			var store := SaveStore.new(save_root.path_join("%s_%d" % [id,index]))
			_check(store.write(game.bundle()) == "","pending followup writes a real checksummed save: " + id)
			var loaded := store.read()
			_check(loaded.get("ok",false),"pending followup reloads from disk: " + id)
			if not loaded.get("ok",false): continue
			var resumed := _event_game()
			resumed.state = loaded.bundle.state
			resumed.profile = loaded.bundle.profile
			_check(JSON.stringify(resumed.state.realm.queue) == JSON.stringify(game.state.realm.queue),"queued branch and due week survive actual save normalization: " + id)
			_check(resumed.state.realm.outcome.get("followup",{}) == game.state.realm.outcome.get("followup",{}),"saved result keeps the visible delivery promise: " + id)
			resumed.state.week = due-1
			RealmRules.schedule(resumed.state,content)
			_check(resumed.state.active_event == "","followup cannot appear before its promise: " + id)
			resumed.state.week = due
			RealmRules.schedule(resumed.state,content)
			_check(resumed.state.active_event == option.followup.id and resumed.state.realm.queue.is_empty(),"saved followup arrives exactly once on the due week: " + id)
			var next: Dictionary = content.events[resumed.state.active_event]
			var fallback := 0
			while fallback < next.options.size() and not _unconditional(next.options[fallback]): fallback += 1
			_check(fallback < next.options.size() and resumed.choose_event(fallback) == "","prepaid followup always has a finishable result: " + id)
			_check(store.write(resumed.bundle()) == "","resolved followup writes a second generation save: " + id)
			var final_save := store.read()
			_check(final_save.get("ok",false) and final_save.bundle.state.realm.queue.is_empty() and option.followup.id in final_save.bundle.state.seen_events,"resolved save cannot recreate a queued reward: " + id)


func _cargo_recovery_boundary() -> void:
	# A partial clamped loss must not fund a later fixed recovery larger than what was lost.
	var root_event: Dictionary = expansion_events.RB_STOLEN_DELIVERY
	var index := 0
	while not root_event.options[index].has("followup"): index += 1
	var followup: Dictionary = expansion_events.RB_CARGO_FOUND
	var poor := _event_rich()
	poor.state.public.wood = 2.0
	poor.state.active_event = "RB_STOLEN_DELIVERY"
	var before: Dictionary = poor.state.duplicate(true)
	_check(poor.choose_event(index) != "" and poor.state == before,"two actual logs cannot authorize recovery of an alleged fourteen-log loss")
	for choice in followup.options.size():
		var game := _event_rich()
		game.state.public.wood = 14.0
		game.state.active_event = "RB_STOLEN_DELIVERY"
		_check(game.choose_event(index) == "" and is_zero_approx(float(game.state.public.wood)),"tracking first commits the full fourteen-log loss")
		var queued: Dictionary = game.state.realm.queue[0]
		game.state.week = int(queued.week)
		RealmRules.schedule(game.state,content)
		_meet(game,followup.options[choice])
		_check(game.choose_event(choice) == "" and float(game.state.public.wood) <= 14.0,"each recovery branch can return only part of the actual original cargo")


func _reward_delta_precision() -> void:
	# The real before/after delta crosses a binary precision boundary at 64.
	var crisis := _announced("CR07")
	_prepare_fixture(crisis, true)
	crisis.state.security = 63.99999999999999
	var before: Dictionary = crisis.state.duplicate(true)
	var report := WeekSim.process_week(crisis.state, content)
	CrisisDirector.after_week(before, crisis.state, content, report)
	var record: Dictionary = crisis.state.escalation.records[0]
	_check(record.success and float(record.effects.security) > 4.0 and absf(float(record.effects.security) - 4.0) < 0.00000001, "actual clamped crisis stat delta reproduces sub-ULP upper-bound rounding")
	_check(SaveStore.valid(crisis.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(crisis.bundle()))), "rounded actual crisis reward remains saveable natively and after JSON")
	var store := SaveStore.new(save_root.path_join("precision_crisis"))
	_check(store.write(crisis.bundle()) == "" and store.read().ok, "rounded crisis record writes and reloads through production save validation")
	var broken: Dictionary = crisis.bundle().duplicate(true)
	broken.state.escalation.records[0].effects.security = 4.0001
	_check(not SaveStore.valid(broken), "stat tolerance still rejects a genuinely oversized crisis reward")
	broken = crisis.bundle().duplicate(true)
	broken.state.escalation.records[0].effects.wood = 12.000000001
	_check(not SaveStore.valid(broken), "resource reward bounds retain their exact preexisting limit")
	var care := _event_rich()
	care.state.cabinet.enabled = false
	care.state.workcrew.enabled = false
	care.state.perks = []
	care.state.realm.sanctuary.owned = ["F15"]
	care.state.realm.sanctuary.equipped = ["F15"]
	var cards: Array = content.progression.perks.keys().filter(func(id): return content.progression.perks[id].family == "agriculture")
	cards.sort()
	for id in cards.slice(0, 2):
		care.state.perk_offer = [id]
		_check(care.choose_perk(id), "precision fixture earns actual matching-family perks")
	care.state.health = 63.99999999999999
	care.state.mood = 70.0
	before = care.state.duplicate(true)
	report = WeekSim.process_week(care.state, content)
	var result := VillageRelics.after_week(before, care.state, content, report)
	_check(result.builds.size() == 1 and result.builds[0].id == "commons" and float(result.builds[0].effects.health) > 2.0, "actual care build also reproduces the fractional stat-delta boundary")
	_check(SaveStore.valid(care.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(care.bundle()))), "rounded operating-build delta remains saveable")
	broken = care.bundle().duplicate(true)
	broken.state.realm.sanctuary.last_result.builds[0].effects.health = 2.0001
	_check(not SaveStore.valid(broken), "build stat tolerance still rejects inflated effects")


func _expansion_playthroughs() -> void:
	var before_pool: Dictionary = content.duplicate(true)
	for id in expansion_events: before_pool.events.erase(id)
	var expanded_seen := {}
	var changed := 0
	for seed_value in [61427,88001,4711,27]:
		var baseline := _new(seed_value)
		baseline.content = before_pool
		var with_events := _new(seed_value)
		var previous := _play(baseline,true)
		var current := _play(with_events,true)
		for game in [baseline,with_events]:
			_check(int(game.state.week) == 53 and game.state.status == "finalized","normal policy reaches actual 52-week settlement without event deadlock")
			_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"full run remains saveable with tone events and consequences")
			for id in expansion_events: _check(game.state.seen_events.count(id) <= 1,"new situation does not repeat in one actual run: " + id)
		var encountered := 0
		for id in with_events.state.seen_events:
			if expansion_events.has(id): expanded_seen[id] = true; encountered += 1
		_check(not baseline.state.seen_events.any(func(id): return expansion_events.has(id)),"comparison baseline truly excludes all 80 new events")
		if baseline.state.public != with_events.state.public or baseline.state.facilities != with_events.state.facilities or previous.success != current.success: changed += 1
		print("EVENT EXPANSION RUN seed=%d before=%s after=%s new_events=%d before_food=%.1f after_food=%.1f before_gold=%d after_gold=%d" % [seed_value,previous.success,current.success,encountered,WeekSim.food_weeks(baseline.state),WeekSim.food_weeks(with_events.state),previous.money,current.money])
	_check(not expanded_seen.is_empty() and changed > 0,"actual new events appear and produce a meaningful economic difference")
	print("EVENT EXPANSION COVERAGE distinct=%d/80 changed_runs=%d/4" % [expanded_seen.size(),changed])
