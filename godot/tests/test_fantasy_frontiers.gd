extends "res://tests/test_crisis_director.gd"
## Production integration, real construction/economy and isolated save boundaries.


func _init() -> void:
	content = Content.load_all()
	_test_fantasy_data()
	_test_fantasy_plan()
	_test_fantasy_chains()
	_test_fantasy_permissions()
	_test_fantasy_production()
	_test_fantasy_last_week()
	print("FANTASY FRONTIERS: %d checks, %d failures" % [assertions,failures])
	quit(1 if failures else 0)


func _fantasy(seed_value: int = 61427) -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config["fantasy"] = true
	config["escalation"] = true
	config["village_relics"] = true
	game.start_run(seed_value,"settler",config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _seed_for_path(key: String) -> int:
	for seed_value in range(1,300):
		if FantasyFrontiers._plan(seed_value,content)[0].id == key: return seed_value
	return -1


func _rich_fantasy(key: String) -> GameSession:
	var game := _fantasy(_seed_for_path(key))
	for asset in game.state.public: game.state.public[asset] = 5000
	game.state.public.money = 100000
	game.state.resident.food = 10000.0
	game.state.pop = 120
	game.state.facilities.B01 = 3
	game.state.facilities.B06 = 2
	game.state.facilities.B25 = 1
	game.state.facilities.B22 = 1
	game.state.birth_rate = 0.0
	game.state.death_rate = 0.0
	game.state.realm.next_event = 999
	game.state.seen_events = content.events.keys().filter(func(id): return not content.events[id].get("fantasy_only",false))
	game.state.active_event = ""
	RealmRules.refresh(game.state,content)
	return game


func _drain(game: GameSession, keep: String = "") -> void:
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	while not game.state.realm.sanctuary.offer.is_empty(): game.choose_relic(str(game.state.realm.sanctuary.offer[0]))
	if game.state.active_event == "" or game.state.active_event == keep: return
	var event: Dictionary = RealmRules.event_definition(game.state,content,str(game.state.active_event))
	if event.get("fantasy_only",false):
		for index in event.options.size():
			if event.options[index].fantasy.action == "decline": game.choose_event(index); return
	for index in event.options.size():
		if game.option_error(event.options[index]) == "": game.choose_event(index); return


func _step(game: GameSession) -> bool:
	_drain(game)
	if game.state.status != "active": return false
	WorkcrewRules.select(game.state,content,"build" if not game.state.orders.is_empty() or not game.state.projects.is_empty() else "balanced")
	var report := game.advance()
	_check(report.advanced,"fantasy fixture advances through actual weekly session")
	_check(SaveStore.valid(game.bundle()),"actual fantasy weekly state remains saveable")
	return report.advanced


func _seek(game: GameSession, key: String, stage: int) -> bool:
	var id := str(content.fantasy_frontiers.paths[key].events[stage-1])
	for guard in 52:
		if game.state.active_event == id: return true
		if not _step(game): break
	_check(false,"expected fantasy chain event arrives: "+id)
	return false


func _construct(game: GameSession, id: String) -> void:
	_check(game.queue_build(id) == "","actual construction queue accepts permitted fantasy facility: "+id)
	for guard in 12:
		if int(game.state.facilities.get(id,0))>0: return
		if not _step(game): break
	_check(false,"permitted facility completes with real labor: "+id)


func _path_complete(key: String, branch: String = "care", finish: bool = true) -> GameSession:
	var game := _rich_fantasy(key)
	var path: Dictionary = content.fantasy_frontiers.paths[key]
	if not _seek(game,key,1): return game
	_check(game.choose_event(0)=="","accept a discovered path by paying its actual fee")
	_construct(game,str(path.buildings[0]))
	if not _seek(game,key,2): return game
	_check(game.choose_event(0 if branch=="care" else 1)=="","choose the requested operating branch")
	_construct(game,str(path.buildings[1]))
	if not _seek(game,key,3): return game
	_check(game.choose_event(2)=="","deterministic free incident alternative advances with real loss")
	if not _seek(game,key,4): return game
	_check(game.choose_event(0)=="","pay for final facility permission")
	if not finish: return game
	_construct(game,str(path.buildings[2]))
	if not _seek(game,key,5): return game
	var before: Dictionary = game.state.public.duplicate(true)
	_check(game.choose_event(1)=="","complete chain with its distinct material reward")
	for asset in path.completion_reward:
		_check(is_equal_approx(float(game.state.public[asset])-float(before[asset]),float(path.completion_reward[asset])),"completion pays the exact path-specific resource reward")
	return game


func _test_fantasy_data() -> void:
	_check(Content.validate(content).is_empty(),"all integrated fantasy definitions validate: "+str(Content.validate(content)))
	_check(content.events.size()==196 and content.fantasy_frontiers.paths.size()==6 and content.fantasy_frontiers.facilities.size()==18,"six paths add eighteen facilities and thirty events")
	for id in content.fantasy_frontiers.events:
		var event: Dictionary = content.events[id]
		_check(event.week==999 and not event.has("pool") and event.fantasy_only,"fantasy events cannot leak into ordinary random or fixed pools")
		_check(event.options.any(func(option): return not option.has("cost") and not option.has("requires") and not option.has("chance")),"every fantasy event retains a deterministic free alternative")
	for id in content.fantasy_frontiers.facilities:
		_check(content.facilities[id].max==1 and content.facilities[id].grade in ["A","B"],"every fantasy construction has a finite reachable grade and cap")


func _test_fantasy_plan() -> void:
	var encountered := {}
	var combinations := {}
	for seed_value in range(1,61):
		var plan := FantasyFrontiers._plan(seed_value,content)
		_check(plan==FantasyFrontiers._plan(seed_value,content) and plan.size()==3,"seeded discovery plan is reproducible")
		var ids := []
		for row in plan: ids.append(row.id); encountered[row.id]=true
		_check(ids[0]!=ids[1] and ids[0]!=ids[2] and ids[1]!=ids[2],"each run discovers three distinct paths")
		combinations[JSON.stringify(ids)]=true
	_check(encountered.size()==6 and combinations.size()>=12,"repeated runs can reach all six paths and varied combinations")
	var legacy := _new()
	var game := _fantasy()
	var clean := game.state.duplicate(true)
	clean.erase("fantasy")
	_check(clean==legacy.state,"opt-in setup does not alter existing economy, drafts or event RNG")
	var before := game.state.duplicate(true)
	for repeat in 10:
		var view := FantasyFrontiers.overview(game.state,content)
		view.paths[0].buildings[0].cost.money=999999
	_check(game.state==before,"overview and visual helpers are read-only")
	for id in content.fantasy_frontiers.facilities:
		_check(legacy.queue_build(id)!="","old run rejects new-only construction")
	_check(FantasyFrontiers.setup(game.state,content,{"fantasy":true}) and game.state==before,"re-entering setup never rerolls paths or grants anything")


func _test_fantasy_chains() -> void:
	for key in content.fantasy_frontiers.paths:
		for branch in ["care","drive"]:
			var game := _path_complete(key,branch)
			_check(game.state.fantasy.paths[key].stage==5 and game.state.fantasy.paths[key].status=="complete" and FantasyFrontiers.path_stage(game.state,key,content)==3,"all five events and three real buildings complete: "+key+"/"+branch)
			_check(game.state.fantasy.paths[key].branch==branch,"operating branch remains recorded")
			_check(SaveStore.valid(game.bundle()) and SaveStore.valid(JSON.parse_string(JSON.stringify(game.bundle()))),"complete fantasy path validates natively and after JSON")
			var store := SaveStore.new("res://tests/output/fantasy_%s_%s_%d" % [key,branch,Time.get_ticks_usec()])
			_check(store.write(game.bundle())=="","path writes to isolated SaveStore")
			var loaded := store.read()
			_check(loaded.ok and store.write(loaded.bundle)=="","normalized path reload can autosave again")
			var before := game.state.duplicate(true)
			for repeat in 5: RealmRules.refresh(game.state,content)
			_check(before==game.state,"branch bonuses never accumulate from repeat refresh")
			_check(game.choose_event(1)!="" and before==game.state,"completion cannot be claimed again")
			var text_rows := RealmFeedback.outcome_lines(game.state,content)
			_check(text_rows.any(func(row): return row.id=="fantasy" and row.effect_text.contains(content.fantasy_frontiers.paths[key].name)),"actual receipt names the completed fantasy agreement")


func _test_fantasy_permissions() -> void:
	var game := _rich_fantasy("grove")
	_seek(game,"grove",1)
	game.state.orders=["B22"]
	var reserved := RealmRules.held(game.state,content)
	game.state.public.money=int(reserved.money)
	var before := game.state.duplicate(true)
	_check(game.choose_event(0)!="" and game.state==before,"discovery cannot spend reserved construction money")
	game.state.orders=[]
	game.state.public.money=100000
	var event: Dictionary=content.events[game.state.active_event]
	game.state.realm.sanctuary.equipped=[]
	_check(game.option_error(event.options[1])!="","relic waiver is unavailable without an equipped matching category")
	var relic_id := "F01"
	if relic_id not in game.state.realm.sanctuary.owned: game.state.realm.sanctuary.owned.append(relic_id)
	game.state.realm.sanctuary.equipped.append(relic_id)
	before=game.state.duplicate(true)
	_check(game.choose_event(1)=="" and game.state.public.money==before.public.money,"equipped matching relic really waives agreement cost")
	_check(game.queue_build("FG02")!="" and game.queue_build("FG03")!="","later buildings require chain permission even with abundant materials")
	_construct(game,"FG01")
	_seek(game,"grove",2)
	event=content.events[game.state.active_event]
	_check(game.option_error(event.options[2])!="","advanced free branch requires two matching perks")
	for id in content.progression.perks:
		if content.progression.perks[id].get("family","")=="agriculture" and id not in game.state.perks:
			game.state.perks.append(id)
			if ChronicleRules.family_counts(content,game.state).agriculture>=2: break
	before=game.state.duplicate(true)
	_check(game.choose_event(2)=="" and game.state.public.money==before.public.money and game.state.fantasy.paths.grove.branch=="drive","matching perk build unlocks the actual normally paid branch for free")
	var broken:=game.bundle()
	broken.state.fantasy.plan[0].id="astral"
	_check(not SaveStore.valid(broken),"saved discovery seed plan cannot be forged")
	broken=game.bundle()
	broken.state.fantasy.paths.grove.stage=5
	_check(not SaveStore.valid(broken),"unearned construction permission is rejected")
	broken=game.bundle()
	broken.state.fantasy.records.append(broken.state.fantasy.records[0].duplicate(true))
	_check(not SaveStore.valid(broken),"duplicate claimed stages are rejected")
	broken=game.bundle()
	broken.state.fantasy.selected=["grove","tide","ember"]
	_check(not SaveStore.valid(broken),"third adopted path rejected by persistence validation")


func _test_fantasy_production() -> void:
	for key in content.fantasy_frontiers.paths:
		var game := _path_complete(key)
		for id in content.fantasy_frontiers.paths[key].buildings:
			var definition: Dictionary=content.facilities[id]
			var full: Dictionary=game.state.duplicate(true)
			full.pop=300
			full.assign={"gather":8,"build":0,"logging":4,"quarry":0,"garden":0,"fuel":0,"milling":0}
			for asset in full.public: full.public[asset]=5000
			full.resident.food=5000.0
			full.week=30
			RealmRules.refresh(full,content)
			var plain: Dictionary=full.duplicate(true)
			plain.facilities.erase(id)
			RealmRules.refresh(plain,content)
			for modifier in definition.get("mods",{}): _check(is_equal_approx(RealmRules.mod(full,modifier)/RealmRules.mod(plain,modifier),float(definition.mods[modifier])),"completed facility applies its exact modifier: "+id+"/"+modifier)
			for stat in definition.get("targets",{}): _check(is_equal_approx(RealmRules.target(full,stat)-RealmRules.target(plain,stat),float(definition.targets[stat])),"completed facility applies its actual target cost/benefit")
			if not definition.has("jobs"): continue
			var original:=full.duplicate(true)
			var start: int=full.ledger.size()
			var report:=WeekSim.process_week(full,content)
			var operation:=FantasyFrontiers.building_operation(full,content,id)
			_check(report.advanced and operation.status=="operating" and operation.workers>0,"fantasy production reports real employed workers")
			for asset in definition.output:
				var produced:=0.0
				for entry in full.ledger.slice(start):
					if entry.src==definition.kind and entry.asset==asset and entry.qty>0: produced+=float(entry.qty)
				var expected: float=float(definition.output[asset])*float(operation.fraction)*WeekSim.bonus(original,str(definition.get("output_bonus","no_bonus")))
				_check(is_equal_approx(produced,expected),"actual fantasy output uses workers, inputs and current perk modifiers exactly once")
				_check(TurnReceipt.source_label(str(definition.kind))==definition.name,"ledger names the actual fantasy producer")
			_check(TurnReceipt.valid(TurnReceipt.build(original,full,report)),"new production flows reconcile with actual resource receipt")
			if definition.has("input"):
				var empty: Dictionary=original.duplicate(true)
				var missing_asset: String=str(definition.input.keys()[0])
				empty.public[missing_asset]=0.0
				# Isolate this facility so an earlier producer cannot refill its missing ingredient.
				empty.facilities={id:1}
				var work:=RealmRules.produce(empty,content,30,2,10,1.0)
				_check(work.operations[id].status=="inputs" and work.operations[id].fraction==0.0,"input shortage produces no phantom activity or output")
			var idle:=RealmRules.produce(original,content,30,2,0,1.0)
			_check(idle.operations[id].status=="labor" and idle.operations[id].workers==0,"labor shortage does not light an idle fantasy factory")


func _test_fantasy_last_week() -> void:
	var game:=_path_complete("ember","care",false)
	var id: String=content.fantasy_frontiers.paths.ember.buildings[2]
	_check(game.queue_build(id)=="","last-week fixture reserves a legitimately permitted final building")
	game.state.week=51
	game.state.assign.build=40
	game.state.realm.queue=[]
	game.state.active_event=""
	game.state.perk_offer=[]
	game.state.realm.sanctuary.offer=[]
	game.state.workcrew.policy="build"
	var first:=game.advance()
	_check(first.advanced and game.state.projects.any(func(project): return project.id==id),"final project pays and works during week 51 before finishing week 52")
	_drain(game)
	var report:=game.advance()
	_check(report.advanced and game.state.status=="finalized" and game.state.facilities.get(id,0)==1,"final fantasy facility can finish in the last actual week")
	_check(game.state.fantasy.paths.ember.stage==5 and game.state.realm.sanctuary.offer.is_empty(),"last-week completion pays materials instead of leaving a blocked relic choice")
	_check(game.state.fantasy.records.back().automatic and game.state.realm.queue.all(func(row): return not content.events[row.id].get("fantasy_only",false)),"final settlement leaves no pending fantasy chain event")
	_check(SaveStore.valid(game.bundle()),"final-week automatic completion remains saveable")
	var before:=game.state.duplicate(true)
	FantasyFrontiers._complete_at_end(game.state,content,"ember",52,report)
	_check(game.state==before,"automatic completion cannot be paid twice")
