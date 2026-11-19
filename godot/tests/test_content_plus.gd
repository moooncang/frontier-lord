extends SceneTree
## 확장 콘텐츠의 실제 선택·지불·후속 도착·경제 효과와 기존 회차 격리.

var checks := 0
var failures := 0
var content: Dictionary
var extra_events: Dictionary
const CONFIG := {"region":"forest","candidate":0,"relics":["seeds","axe"],"tutorial":false,
	"cabinet":true,"campaign":true,"workcrew":true,"realm":true,"escalation":true}
const ADDITIVE := ["tax","trust","winter_gather"]
const BONUSES := ["gather","logging","harvest","seed","sow_labor","storage","tool_use","heating","buy","wages","maintenance","tax","trust","winter_gather","garden","quarry","smithy"]
const ASSETS := ["money","food","wood","stone","tools","fuel"]
const STATS := ["mood","health","security","trust","village","guild"]
const EFFECTS := ["money","food","wood","stone","tools","fuel","resident_food","pop","mood","health","security","trust","village","guild","crop","perm","threat","trade_discount"]


func _init() -> void:
	content = Content.load_all()
	extra_events = Content._load("res://content/realm_events_plus.json")
	_schema()
	_perk_choices()
	_pool_isolation()
	_event_choices()
	_followups()
	_actual_economy()
	print("CONTENT PLUS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CONTENT PLUS FAIL: ",message)


func _new(seed_value: int = 61427, expanded: bool = true) -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config.escalation = expanded
	game.start_run(seed_value,"settler",config)
	game.state.perk_offer = []
	game.state.active_event = ""
	return game


func _rich(seed_value: int = 61427) -> GameSession:
	var game := _new(seed_value)
	for key in ASSETS: game.state.public[key] = 100000 if key == "money" else 2000.0
	game.state.resident.money = 100000
	game.state.resident.food = 2000.0
	for key in STATS: game.state[key] = 50.0
	for id in ["B01","B06","B13","B17","B25","B27","B33","B49","B52","B59","B63"]:
		game.state.facilities[id] = 1
	game.state.facilities.B01 = 8
	game.state.facilities.B13 = 4
	game.state.realm.queue = []
	RealmRules.refresh(game.state,content)
	return game


func _schema() -> void:
	_check(Content.validate(content).is_empty(),"merged content validates")
	_check(content.progression.perks.size() == 96,"96 total perks")
	var families := {}
	var legacy := 0
	for id in content.progression.perks:
		var p: Dictionary = content.progression.perks[id]
		if not p.get("plus_only",false): legacy += 1; continue
		if int(str(id).trim_prefix("P")) >= 100: continue # New operating-build cards have their own schema/economy suite.
		_check(int(str(id).trim_prefix("P")) in range(70,94),"new perk ID in reserved range: " + id)
		families[p.family] = int(families.get(p.family,0))+1
		_check(content.chronicle.families.has(p.family),"existing family reused: " + id)
		_check(not p.extra_bonuses.is_empty(),"perk has a combined economic effect: " + id)
		_check(p.description.length() <= 65,"all gains and costs fit short copy: " + id)
		_check(int(p.pool_min_week) <= int(p.pool_max_week),"perk relevance window: " + id)
		var all: Dictionary = p.extra_bonuses.duplicate(true)
		all[p.effect] = p.value
		for key in all:
			_check(key in BONUSES and is_finite(float(all[key])) and (key in ADDITIVE or float(all[key]) > 0),"consumed finite bonus: " + id + "/" + key)
	_check(legacy == 24 and families.size() == 4 and families.values().all(func(v): return v == 6),"original 24 plus six new cards per existing family")
	_check(extra_events.size() == 33,"33 new events")
	var roots := 0
	var reachable := []
	var ids := {}
	for path in ["events","realm_events","relic_events","realm_events_plus"]:
		for id in Content._load("res://content/%s.json" % path):
			_check(not ids.has(id),"unique event ID across merged files: " + id)
			ids[id] = true
	for id in extra_events:
		var event: Dictionary = extra_events[id]
		_check(event.realm and event.plus_only and int(event.week) == 999,"only expanded random/queued event: " + id)
		_check(event.body.length() <= 65 and event.body.count(".") <= 3,"short concrete event body: " + id)
		_check(content.chronicle.characters.has(event.portrait) and content.chronicle.characters[event.portrait].name == event.speaker,"established character and portrait: " + id)
		_check(event.options.size() >= 2 and event.options.size() <= 3,"two or three decisions: " + id)
		_check(event.options.any(func(o): return o.get("cost",{}).is_empty() and o.get("requires",{}).is_empty() and not o.has("requires_housing") and not o.has("chance")),"unconditional deterministic free fallback: " + id)
		if event.has("pool"):
			roots += 1
			_check(event.pool.once and event.pool.min <= event.pool.max and event.pool.max <= 48,"one-time meaningful pool window: " + id)
			if event.pool.has("facility"): _check(content.facilities.has(event.pool.facility),"known facility gate: " + id)
		for option in event.options:
			_check(option.label.length() <= 17,"compact action label: " + id)
			for key in option.get("cost",{}):
				_check(key in ASSETS and is_finite(float(option.cost[key])) and option.cost[key] > 0,"payable real public resource: " + id)
			_check_effects(option.effects,id)
			if option.has("chance"):
				_check(option.chance.base > 0 and option.chance.base < 1,"risk has real probability: " + id)
				for branch in ["win","lose"]:
					_check_effects(option.chance[branch].effects,id + "/" + branch)
			if option.has("followup"):
				var next: String = option.followup.id
				_check(extra_events.has(next) and not extra_events[next].has("pool"),"paid followup never occurs independently: " + id)
				_check(event.has("pool") and int(event.pool.max)+int(option.followup.delay) <= 48,"followup has room before final week: " + id)
				reachable.append(next)
	_check(roots == 17,"17 random entry points")
	for id in extra_events:
		if not extra_events[id].has("pool"): _check(id in reachable,"every followup reachable from a real decision: " + id)


func _check_effects(effects: Dictionary, context: String) -> void:
	for key in effects:
		_check(key in EFFECTS,"effect is actually consumed: " + context + "/" + key)
		if key == "perm":
			for bonus in effects.perm:
				_check((bonus in BONUSES and bonus not in ADDITIVE) or bonus in ["spoil","build_work"],"real realm multiplier: " + context + "/" + bonus)
				_check(is_finite(float(effects.perm[bonus])) and effects.perm[bonus] > 0,"positive realm multiplier: " + context)
		else: _check(is_finite(float(effects[key])),"finite actual effect: " + context)


func _perk_choices() -> void:
	for id in content.progression.perks:
		var perk: Dictionary = content.progression.perks[id]
		if not perk.get("plus_only",false): continue
		var game := _new()
		game.state.perk_offer = [id]
		var before: Dictionary = game.state.bonuses.duplicate(true)
		_check(game.choose_perk(id),"new perk can be chosen: " + id)
		var effects: Dictionary = perk.extra_bonuses.duplicate(true)
		effects[perk.effect] = perk.value
		for key in effects:
			var expected := float(before.get(key,0.0))+float(effects[key]) if key in ADDITIVE else float(before.get(key,1.0))*float(effects[key])
			_check(is_equal_approx(WeekSim.raw_bonus(game.state,key,0.0 if key in ADDITIVE else 1.0),expected),"primary and secondary benefit/cost applied exactly once: " + id + "/" + key)
		var taken: Dictionary = game.state.duplicate(true)
		_check(not game.choose_perk(id) and game.state == taken,"duplicate selection cannot reapply compound effects: " + id)
		_check(SaveStore.valid(game.bundle()),"native chosen perk remains saveable including signed costs: " + id)
		_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"chosen perk survives JSON save: " + id)
		_check(ConciseCopy.perk_brief(id,perk) == perk.description,"visible perk copy includes every downside: " + id)
	for family in content.chronicle.families:
		var game := _new()
		var candidates: Array = content.progression.perks.keys().filter(func(id): return content.progression.perks[id].family == family and content.progression.perks[id].get("plus_only",false))
		for index in 4:
			game.state.perk_offer = [candidates[index]]
			game.choose_perk(candidates[index])
			_check(game.state.synergies.size() == (0 if index == 0 else 1 if index < 3 else 2),"existing 2/4 thresholds retained: " + family)
		var before: Dictionary = game.state.bonuses.duplicate(true)
		ChronicleRules.unlock_synergies(content,game.state)
		_check(game.state.bonuses == before,"synergy only paid once: " + family)


func _pool_isolation() -> void:
	var found_initial := false
	for seed_value in range(1,49):
		for expanded in [false,true]:
			var game := _new(seed_value,expanded)
			game._offer_perks()
			for week in [1,7,14,27,34,40,47]:
				game.state.week = week
				game._offer_perks()
				for id in game.state.perk_offer:
					var p: Dictionary = content.progression.perks[id]
					_check(expanded or not p.get("plus_only",false),"legacy drafts exclude all new content")
					_check(week >= int(p.get("pool_min_week",1)) and week <= int(p.get("pool_max_week",52)),"no expired sowing or harvest choice")
					if expanded:
						_check(not (p.effect == "seed" and week > 2),"expanded drafts exclude spent seed bonuses")
						_check(not (p.effect == "sow_labor" and week > 6),"expanded drafts exclude completed sowing work")
						_check(not (p.effect in ["harvest","tax"] and week > 36),"expanded drafts exclude finished harvest/tax bonuses")
					if week == 1 and p.get("plus_only",false): found_initial = true
	_check(found_initial,"new perks are in the actual initial draft after expansion setup")
	# Keep each old card as the sole unowned candidate: this proves the boundary without relying on a lucky draft.
	for entry in [["P51",2],["P01",6],["P50",36],["P21",36]]:
		for expanded in [false,true]:
			var game := _new(61427,expanded)
			var target: String = entry[0]
			game.state.perks = content.progression.perks.keys().filter(func(id): return id != target)
			game.state.week = int(entry[1])
			game._offer_perks()
			_check(game.state.perk_offer == [target],"old seasonal perk remains available during its real use window: " + target)
			game.state.week += 1
			game._offer_perks()
			_check(game.state.perk_offer.is_empty() if expanded else game.state.perk_offer == [target],"expired old perk excluded only for expanded runs; legacy pool preserved: " + target)
	for id in extra_events:
		var event: Dictionary = extra_events[id]
		if not event.has("pool"): continue
		var game := _rich()
		game.state.week = int(event.pool.min)
		_check(RealmRules.eligible(game.state,content).any(func(row): return row.id == id),"root is actually reachable at first eligible week: " + id)
		game.state.escalation.erase("enabled")
		_check(not RealmRules.eligible(game.state,content).any(func(row): return row.id == id),"legacy event pool excludes expansion root: " + id)
		game.state.escalation.enabled = true
		game.state.seen_events.append(id)
		_check(not RealmRules.eligible(game.state,content).any(func(row): return row.id == id),"investment cannot be farmed repeatedly: " + id)


func _event_choices() -> void:
	for id in extra_events:
		var event: Dictionary = extra_events[id]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			for seed_value in range(1,13) if option.has("chance") else [1]:
				var game := _rich(seed_value)
				game.state.active_event = id
				var before: Dictionary = game.state.duplicate(true)
				_check(game.choose_event(index) == "","actual choice resolves: %s/%d" % [id,index])
				var effects: Dictionary = option.effects.duplicate(true)
				if option.has("chance"):
					var branch: Dictionary = option.chance.win if game.state.realm.outcome.win else option.chance.lose
					for key in branch.effects: effects[key] = float(effects.get(key,0.0))+float(branch.effects[key])
				for key in ASSETS:
					var expected := float(before.public[key])-float(option.get("cost",{}).get(key,0))+float(effects.get(key,0))
					_check(is_equal_approx(float(game.state.public[key]),expected),"actual resource matches paid cost and revealed outcome: %s/%d/%s" % [id,index,key])
				for key in STATS:
					_check(is_equal_approx(float(game.state[key]),clampf(float(before[key])+float(effects.get(key,0)),0,100)),"actual stat matches decision: " + id + "/" + key)
				if effects.has("pop"): _check(int(game.state.pop) == int(before.pop)+int(effects.pop),"accepted residents actually arrive")
				if effects.has("crop"): _check(is_equal_approx(float(game.state.realm.crop),float(before.realm.crop)*(1.0+float(effects.crop))),"this year's harvest effect is real: " + id)
				for key in effects.get("perm",{}):
					_check(is_equal_approx(float(game.state.realm.perm[key]),float(before.realm.perm.get(key,1.0))*float(effects.perm[key])),"run multiplier is applied: " + id + "/" + key)
				_check(SaveStore.valid(game.bundle()),"native resolved event save: " + id)
				_check(SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"JSON resolved event save: " + id)
				var resolved: Dictionary = game.state.duplicate(true)
				_check(game.choose_event(index) != "" and game.state == resolved,"resolved event cannot pay twice: " + id)
		# No money, supplies, buildings or good statistics can force a payment or housing deadlock.
		var poor := _new()
		for key in ASSETS: poor.state.public[key] = 0
		poor.state.facilities = {}
		for key in STATS: poor.state[key] = 0.0
		var alternatives: Array = event.options.filter(func(o): return o.get("cost",{}).is_empty() and o.get("requires",{}).is_empty() and not o.has("requires_housing") and not o.has("chance"))
		_check(not alternatives.is_empty() and poor.option_error(alternatives[0]) == "","zero-resource estate can resolve: " + id)
		for index in event.options.size():
			if event.options[index].get("cost",{}).is_empty(): continue
			poor.state.active_event = id
			var before: Dictionary = poor.state.duplicate(true)
			_check(poor.choose_event(index) != "" and poor.state == before,"unaffordable choice is atomic: " + id)


func _followups() -> void:
	for id in extra_events:
		var event: Dictionary = extra_events[id]
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if not option.has("followup"): continue
			var game := _rich()
			game.state.week = int(event.pool.min)
			game.state.active_event = id
			game.choose_event(index)
			_check(game.state.realm.queue.size() == 1 and game.state.realm.queue[0].id == option.followup.id,"chosen branch queues only its own followup: " + id)
			var due := int(event.pool.min)+int(option.followup.delay)
			_check(int(game.state.realm.queue[0].week) == due,"announced delay matches actual arrival: " + id)
			var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(game.bundle()))
			_check(SaveStore.valid(roundtrip),"pending followup survives save validation: " + id)
			game.state = roundtrip.state
			game.state.realm.next_event = 999
			game.state.week = due-1
			RealmRules.schedule(game.state,content)
			_check(game.state.active_event == "","prepaid delivery cannot arrive early: " + id)
			game.state.week = due
			RealmRules.schedule(game.state,content)
			_check(game.state.active_event == option.followup.id and game.state.realm.queue.is_empty(),"saved branch arrives on exact week: " + id)
			var next: Dictionary = content.events[game.state.active_event]
			var fallback := 0
			while not next.options[fallback].get("cost",{}).is_empty() or next.options[fallback].has("requires_housing"): fallback += 1
			_check(game.choose_event(fallback) == "","followup has a payable completion: " + id)


func _flow(state: Dictionary, source: String, asset: String) -> float:
	var total := 0.0
	for row in state.ledger:
		if row.src == source and row.asset == asset: total += float(row.qty)
	return total


func _actual_economy() -> void:
	# Each advertised multiplier must reach an actual economic consumer, not only a bonus dictionary.
	for key in ["gather","logging","harvest","seed","sow_labor","storage","tool_use","heating","wages","maintenance","tax","winter_gather"]:
		var game := _rich()
		var a: Dictionary = game.state.duplicate(true)
		a.bonuses = {}
		a.week = 3 if key in ["seed","sow_labor"] else 34 if key == "harvest" else 40 if key in ["heating","winter_gather"] else 13 if key == "tax" else 10
		a.facilities.B22 = 1
		if key == "storage":
			a.public.food = 20000.0
			a.resident.food = 20000.0
		a.plots_sown = 4
		a.sow_f_sum = 1.0
		a.assign = {"gather":8,"build":0,"logging":4,"quarry":4,"garden":0,"fuel":0,"milling":0}
		a.ledger = []
		var b: Dictionary = a.duplicate(true)
		b.bonuses[key] = .2 if key in ADDITIVE else .5 if key in ["seed","sow_labor","tool_use","heating","wages","maintenance"] else 1.5
		_check(WeekSim.process_week(a,content).advanced and WeekSim.process_week(b,content).advanced,"real weekly fixtures advance: " + key)
		var different := false
		match key:
			"gather","winter_gather": different = _flow(a,"gather","food") != _flow(b,"gather","food")
			"logging": different = _flow(a,"logging","wood") != _flow(b,"logging","wood")
			"tool_use": different = _flow(a,"logging","tools") != _flow(b,"logging","tools")
			"harvest","seed": different = _flow(a,key,"food") != _flow(b,key,"food")
			"sow_labor": different = a.labor_report.farm != b.labor_report.farm
			"storage": different = _flow(a,"spoil","food") != _flow(b,"spoil","food")
			"heating": different = _flow(a,"heating","fuel") != _flow(b,"heating","fuel")
			"wages","maintenance","tax": different = _flow(a,key,"money") != _flow(b,key,"money")
		_check(different,"advertised modifier changes actual work/production/cost: " + key)
	var trade := _rich()
	var original := trade.trade_quote("wood",40,true)
	ChronicleRules.apply_bonuses(trade.state,{"buy":.8})
	_check(trade.trade_quote("wood",40,true) < original,"purchase modifier changes goods quote")
	var interview := _rich()
	interview.state.trust = 30
	var baseline: Dictionary = interview.state.duplicate(true)
	interview.council_visit("CH01")
	var gain := float(interview.state.trust)-30
	interview.state = baseline
	ChronicleRules.apply_bonuses(interview.state,{"trust":-2})
	interview.council_visit("CH01")
	_check(is_equal_approx(float(interview.state.trust)-30,gain-2),"negative interview modifier changes the real recovery")
