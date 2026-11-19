class_name FantasyFrontiers
extends RefCounted
## 한 통치에 발견 세 방향, 채택 두 방향. 사건으로 허가하고 실제 완공으로 다음 사건을 연다.
const STREAM := 131
const DISCOVERY_WEEKS := [8,14,20]
const LIMIT := 2
static var _cached: Dictionary = {}


static func _data(content: Dictionary = {}) -> Dictionary:
	if content.has("fantasy_frontiers"): return content.fantasy_frontiers
	if _cached.is_empty(): _cached = Content._load("res://content/fantasy_frontiers.json")
	return _cached


static func definitions(content: Dictionary = {}) -> Dictionary:
	return _data(content).duplicate(true)


static func enabled(state: Dictionary) -> bool:
	return state.get("fantasy") is Dictionary and state.fantasy.get("enabled") == true


static func _plan(seed_value: int, content: Dictionary = {}) -> Array:
	var ids: Array = _data(content).paths.keys()
	ids.sort()
	var random := Xoshiro128.new(seed_value,STREAM)
	var result := []
	for week in DISCOVERY_WEEKS:
		result.append({"id":str(ids.pop_at(random.randi_range(0,ids.size()-1))),"week":week})
	return result


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if config.get("fantasy",false) != true or not RealmRules.enabled(state): return false
	if state.has("fantasy"): return valid(state,content)
	var paths := {}
	for id in _data(content).paths:
		paths[str(id)] = {"discovered":false,"status":"unknown","stage":0,"branch":"","next_week":0,"completed_week":0}
	state.fantasy = {"enabled":true,"version":1,"plan":_plan(int(state.seed),content),"selected":[],"paths":paths,"last_week":0,"records":[],"news":[]}
	return true


static func accepted_paths(state: Dictionary) -> Array:
	return state.fantasy.selected.duplicate() if enabled(state) else []


static func building_path(id: String, content: Dictionary = {}) -> String:
	return str(_data(content).facilities.get(id,{}).get("fantasy_path",""))


static func facility_label(id: String, content: Dictionary = {}) -> String:
	return str(_data(content).facilities.get(id,{}).get("name",id))


static func path_label(id: String, content: Dictionary = {}) -> String:
	return str(_data(content).paths.get(id,{}).get("name",id))


static func building_operation(state: Dictionary, content: Dictionary, id: String) -> Dictionary:
	var facility: Dictionary = content.facilities.get(id,{})
	if not facility.has("jobs"): return {"productive":false,"workers":0,"capacity":0,"status":"passive","missing":[],"fraction":0.0,"week":0}
	var actual: Dictionary = state.get("labor_report",{}).get("realm_operations",{}).get(id,{})
	if not actual.is_empty(): return actual.duplicate(true)
	return {"productive":true,"workers":0,"capacity":int(facility.jobs),"status":"waiting","missing":[],"fraction":0.0,"week":0}


static func path_stage(state: Dictionary, key: String, content: Dictionary = {}) -> int:
	if not enabled(state) or key not in state.fantasy.selected or not _data(content).paths.has(key): return 0
	var count := 0
	for id in _data(content).paths[key].buildings:
		if int(state.facilities.get(id,0)) > 0: count += 1
	return count


static func visual_path(state: Dictionary) -> String:
	var selected := accepted_paths(state)
	return str(selected[0]) if not selected.is_empty() else ""


static func bonuses(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"mods":{},"targets":{}}
	if not enabled(state): return result
	for id in state.fantasy.selected:
		var branch := str(state.fantasy.paths[id].branch)
		if branch.is_empty(): continue
		var definition: Dictionary = _data(content).paths[id].branches[branch]
		for key in definition.get("mods",{}): result.mods[key] = float(result.mods.get(key,1.0))*float(definition.mods[key])
		for key in definition.get("targets",{}): result.targets[key] = float(result.targets.get(key,0.0))+float(definition.targets[key])
	return result


static func build_error(state: Dictionary, content: Dictionary, id: String) -> String:
	var facility: Dictionary = content.facilities.get(id,{})
	if not facility.get("fantasy",false): return ""
	if not enabled(state): return "이 통치에는 이계 지구가 열리지 않았습니다."
	var key := str(facility.fantasy_path)
	if key not in state.fantasy.selected: return "%s 협약을 먼저 채택하세요." % _data(content).paths[key].name
	var needed: int = [1,2,4][int(facility.fantasy_stage)-1]
	if int(state.fantasy.paths[key].stage) < needed or (int(facility.fantasy_stage) == 3 and state.fantasy.paths[key].status == "paused"):
		return "협약 사건에서 %s 건설 허가를 받아야 합니다." % facility.name
	return ""


static func _queued(state: Dictionary, id: String) -> bool:
	return state.active_event == id or id in state.seen_events or state.realm.queue.any(func(row): return row.id == id)


static func _queue(state: Dictionary, content: Dictionary, key: String, stage: int, report: Dictionary) -> void:
	var id := str(_data(content).paths[key].events[stage-1])
	if _queued(state,id): return
	state.realm.queue.append({"id":id,"week":int(state.week)})
	var text := "%s · %s" % [_data(content).paths[key].name,content.events[id].title]
	_news(state,report,text)


static func _news(state: Dictionary, report: Dictionary, text: String) -> void:
	var row := {"level":"info","text":text,"kind":"fantasy","week":int(report.week)}
	state.fantasy.news.append(row)
	state.realm.news.append(row.duplicate(true))
	report.notes.append(text)


static func after_week(before: Dictionary, state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	if not enabled(state) or not enabled(before) or report.get("advanced") != true: return
	var week := int(report.get("week",0))
	if int(before.week) != week or int(state.week) != week+1 or before.run_id != state.run_id or week <= int(state.fantasy.last_week): return
	state.fantasy.last_week = week
	state.fantasy.news.clear()
	if state.pop <= 0:
		state.realm.queue = state.realm.queue.filter(func(row): return not content.events[row.id].get("fantasy_only",false))
		return
	var data := _data(content)
	for planned in state.fantasy.plan:
		var path: Dictionary = state.fantasy.paths[planned.id]
		if path.discovered or int(state.week) < int(planned.week): continue
		path.discovered = true
		path.status = "offered" if state.fantasy.selected.size() < LIMIT and int(state.week) <= 49 else "unavailable"
		if path.status == "offered": _queue(state,content,str(planned.id),1,report)
	for key in state.fantasy.selected:
		var path: Dictionary = state.fantasy.paths[key]
		if path.status in ["complete","paused"] or int(state.week) < int(path.next_week): continue
		var stage := int(path.stage)
		var built := path_stage(state,str(key),content)
		if stage == 4 and built == 3 and int(state.week) >= 52:
			_complete_at_end(state,content,str(key),week,report)
		elif int(state.week) <= 51:
			if stage == 1 and built >= 1: _queue(state,content,str(key),2,report)
			elif stage == 2 and built >= 2: _queue(state,content,str(key),3,report)
			elif stage == 3 and int(state.week) <= 48: _queue(state,content,str(key),4,report)
			elif stage == 4 and built == 3: _queue(state,content,str(key),5,report)
	if int(state.week) > 52:
		state.realm.queue = state.realm.queue.filter(func(row): return not content.events[row.id].get("fantasy_only",false))


static func _complete_at_end(state: Dictionary, content: Dictionary, key: String, week: int, report: Dictionary) -> void:
	var path: Dictionary = state.fantasy.paths[key]
	if int(path.stage) != 4: return
	var definition: Dictionary = _data(content).paths[key]
	var event := str(definition.events[4])
	for asset in definition.completion_reward:
		var amount := float(definition.completion_reward[asset])
		state.public[asset] += amount
		WeekSim._ledger(state,week,"fantasy_reward:"+key,str(asset),amount)
	state.public.money = int(state.public.money)
	path.stage = 5
	path.status = "complete"
	path.completed_week = week
	path.next_week = week+1
	state.fantasy.records.append({"path":key,"event":event,"stage":5,"action":"complete","branch":str(path.branch),"week":week,"automatic":true})
	if event not in state.seen_events: state.seen_events.append(event)
	state.realm.queue = state.realm.queue.filter(func(row): return row.id != event)
	var text := "%s 완성 · 마지막 주에는 협약 물자를 바로 지급합니다." % definition.name
	_news(state,report,text)


static func option_error(state: Dictionary, content: Dictionary, option: Dictionary) -> String:
	if not option.has("fantasy"): return ""
	if not enabled(state) or state.get("status") != "active": return "이 통치에는 이계 협약이 없습니다."
	var meta: Dictionary = option.fantasy
	var key := str(meta.path)
	var stage := int(meta.stage)
	var path: Dictionary = state.fantasy.paths.get(key,{})
	if path.is_empty() or not path.discovered: return "아직 발견하지 않은 협약입니다."
	if state.active_event != _data(content).paths[key].events[stage-1] or stage != int(path.stage)+1: return "이미 처리했거나 다른 단계의 협약입니다."
	if stage == 1:
		if path.status != "offered": return "이미 결정한 협약입니다."
		if meta.action == "accept" and state.fantasy.selected.size() >= LIMIT: return "한 통치에 이계 협약은 두 방향까지만 채택할 수 있습니다."
	else:
		if key not in state.fantasy.selected or path.status != "selected": return "현재 진행 중인 협약이 아닙니다."
		var built := path_stage(state,key,content)
		if (stage == 2 and built < 1) or (stage in [3,4] and built < 2) or (stage == 5 and built < 3): return "앞 단계의 시설을 먼저 완공하세요."
		if stage == 4 and meta.action == "permit" and int(state.week) > 48: return "최종 건설 허가는 48주까지 가능합니다. 이번 공사를 보류하세요."
	return ""


static func resolve(state: Dictionary, content: Dictionary, event_id: String, option: Dictionary) -> void:
	if not option.has("fantasy"): return
	var meta: Dictionary = option.fantasy
	var key := str(meta.path)
	var stage := int(meta.stage)
	var path: Dictionary = state.fantasy.paths[key]
	path.stage = stage
	path.next_week = int(state.week)+(2 if stage == 3 else 1)
	var unlocked := []
	match str(meta.action):
		"accept":
			state.fantasy.selected.append(key)
			path.status = "selected"
			unlocked.append(str(_data(content).paths[key].buildings[0]))
		"decline": path.status = "declined"
		"branch":
			path.branch = str(meta.branch)
			unlocked.append(str(_data(content).paths[key].buildings[1]))
		"permit": unlocked.append(str(_data(content).paths[key].buildings[2]))
		"close": path.status = "paused"
		"complete":
			path.status = "complete"
			path.completed_week = int(state.week)
	state.fantasy.records.append({"path":key,"event":event_id,"stage":stage,"action":str(meta.action),"branch":str(path.branch),"week":int(state.week),"automatic":false})
	state.realm.outcome["fantasy"] = {"path":key,"stage":stage,"action":str(meta.action),"branch":str(path.branch),"unlocked":unlocked,"completed":stage==5,"text":option_text(option,content)}


static func option_text(option: Dictionary, content: Dictionary = {}) -> String:
	if not option.has("fantasy"): return ""
	var meta: Dictionary = option.fantasy
	var definition: Dictionary = _data(content).paths[meta.path]
	match str(meta.action):
		"accept": return "%s 채택 · %s 건설 허가 (협약 1칸 사용)" % [definition.name,_data(content).facilities[definition.buildings[0]].name]
		"decline": return "이번 통치에서 이 협약을 채택하지 않습니다."
		"branch": return "%s · %s · %s 건설 허가" % [definition.branches[meta.branch].name,definition.branches[meta.branch].text,_data(content).facilities[definition.buildings[1]].name]
		"resolve": return "문제를 마무리합니다. 최종 허가는 2주 뒤, 늦어도 48주까지 검토합니다."
		"permit": return "%s 건설 허가 · 공사비와 자재는 별도" % _data(content).facilities[definition.buildings[2]].name
		"close": return "올해 최종 건설을 보류합니다. 이미 지은 시설과 분기 효과는 유지합니다."
		"complete": return "%s 완성 기록" % definition.name
	return ""


static func overview(state: Dictionary, content: Dictionary = {}) -> Dictionary:
	var result := {"enabled":enabled(state),"limit":LIMIT,"selected":accepted_paths(state),"paths":[],"news":[],"discovery_weeks":DISCOVERY_WEEKS.duplicate()}
	var data := _data(content)
	for key in data.paths:
		var definition: Dictionary = data.paths[key]
		var path: Dictionary = state.get("fantasy",{}).get("paths",{}).get(key,{})
		var selected: bool = enabled(state) and key in state.fantasy.selected
		var stage := int(path.get("stage",0))
		var branch := str(path.get("branch",""))
		var row := {"id":str(key),"name":str(definition.name),"status":str(path.get("status","unknown")),"discovered":bool(path.get("discovered",false)),"selected":selected,"branch":branch,
			"branch_name":str(definition.branches.get(branch,{}).get("name","")),"branch_text":str(definition.branches.get(branch,{}).get("text","")),
			"stage":stage,"completed":path.get("status")=="complete","background_stage":path_stage(state,str(key),content),
			"benefit":str(definition.benefit),"tradeoff":str(definition.tradeoff),"next_text":"이번 통치에서 아직 발견하지 않았습니다.","buildings":[]}
		if path.get("status") == "offered": row.next_text = "도착한 협약 사건에서 채택 여부를 결정하세요."
		elif path.get("status") in ["declined","unavailable"]: row.next_text = "이번 통치에서는 채택하지 않은 방향입니다."
		elif path.get("status") == "paused": row.next_text = "최종 건설을 보류했습니다. 현재 시설은 계속 운영합니다."
		elif selected:
			match stage:
				1: row.next_text = "첫 시설을 완공하면 운영 분기를 선택합니다."
				2: row.next_text = "둘째 시설을 완공하면 협약의 문제를 해결합니다."
				3: row.next_text = "%d주부터 최종 건설 허가를 검토합니다." % int(path.next_week) if int(state.week)<=48 else "최종 건설 허가 기한(48주)이 지났습니다."
				4: row.next_text = "셋째 시설을 완공하면 협약 보상을 받습니다."
				5: row.next_text = "협약을 완성했습니다. 시설과 분기 효과는 이번 통치 동안 유지됩니다."
			var expected_buildings := 1 if stage==1 else 2 if stage==2 else 3 if stage==4 else 99
			if int(row.background_stage)>=expected_buildings:
				var action := "운영 분기" if stage==1 else "운영 문제 보고" if stage==2 else "협약 완성 보상"
				row.next_text = "%s 사건이 대기 중입니다." % action if int(state.week)>=int(path.next_week) else "%d주부터 %s 사건을 받습니다." % [int(path.next_week),action]
		for id in definition.buildings:
			var facility: Dictionary = data.facilities[id]
			var grade: Dictionary = Constants.GRADE_COST[facility.grade]
			var built := int(state.get("facilities",{}).get(id,0))>0
			var queued: bool = id in state.get("orders",[]) or state.get("projects",[]).any(func(project): return project.id==id)
			var error := build_error(state,content,str(id)) if content.has("facilities") else ""
			if error.is_empty() and content.has("facilities"): error = RealmRules.build_error(state,content,str(id),1 if built or queued else 0)
			var permits: bool = selected and stage >= [1,2,4][int(facility.fantasy_stage)-1] and not (int(facility.fantasy_stage)==3 and path.get("status")=="paused")
			row.buildings.append({"id":str(id),"name":str(facility.name),"stage":int(facility.fantasy_stage),"unlocked":permits,"built":built,"queued":queued,
				"effect":str(facility.effect),"grade":str(facility.grade),"cost":{"money":int(grade.gold)*100,"wood":int(grade.wood),"stone":int(grade.stone),"tools":int(grade.tools),"iron":int(grade.iron)},"error":error,"sprite":str(facility.sprite)})
		result.paths.append(row)
	if enabled(state): result.news = state.fantasy.news.duplicate()
	return result


static func result(state: Dictionary) -> Array:
	var rows := []
	if not enabled(state): return rows
	for id in state.fantasy.selected:
		var path: Dictionary = state.fantasy.paths[id]
		rows.append({"id":str(id),"branch":str(path.branch),"stage":int(path.stage),"completed":path.status=="complete"})
	return rows


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)==floor(float(value))


static func valid(state: Dictionary, content: Dictionary = {}) -> bool:
	if not state.has("fantasy"):
		for id in state.get("facilities",{}):
			if _data(content).facilities.has(id): return false
		for id in state.get("orders",[]):
			if _data(content).facilities.has(id): return false
		for project in state.get("projects",[]):
			if _data(content).facilities.has(project.get("id","")): return false
		if _data(content).events.has(state.get("active_event","")): return false
		for id in state.get("seen_events",[]):
			if _data(content).events.has(id): return false
		for queued in state.get("realm",{}).get("queue",[]):
			if _data(content).events.has(queued.get("id","")): return false
		return true
	var value: Variant = state.fantasy
	var data := _data(content)
	if not value is Dictionary or value.size()!=8 or value.get("enabled")!=true or not value.enabled is bool or value.get("version")!=1 or not RealmRules.enabled(state): return false
	if not value.get("plan") is Array or not _plans_equal(value.plan,_plan(int(state.get("seed",0)),content)): return false
	if not value.get("paths") is Dictionary or value.paths.size()!=6 or not value.get("selected") is Array or value.selected.size()>LIMIT: return false
	if not _whole(value.get("last_week")) or int(value.last_week)>mini(52,int(state.get("week",1))-1): return false
	if not value.get("records") is Array or value.records.size()>15 or not value.get("news") is Array: return false
	var selected := []
	for id in value.selected:
		if not id is String or not data.paths.has(id) or id in selected: return false
		selected.append(id)
	var recorded := {}
	for record in value.records:
		if not record is Dictionary or record.size()!=7 or not data.paths.has(record.get("path","")) or not _whole(record.get("stage")) or record.stage<1 or record.stage>5: return false
		var key := str(record.path)
		var stage := int(record.stage)
		if record.get("event")!=data.paths[key].events[stage-1] or recorded.has(record.event): return false
		if not _whole(record.get("week")) or record.week<1 or record.week>mini(52,int(state.week)) or not record.get("automatic") is bool: return false
		if record.get("action") not in (["accept","decline"] if stage==1 else ["branch"] if stage==2 else ["resolve"] if stage==3 else ["permit","close"] if stage==4 else ["complete"]): return false
		if record.automatic and (stage!=5 or record.week<51): return false
		if not record.get("branch") is String or (stage>=2 and not data.paths[key].branches.has(record.branch)): return false
		if stage>1:
			if not recorded.has(data.paths[key].events[stage-2]): return false
			var previous: Dictionary = recorded[data.paths[key].events[stage-2]]
			if int(record.week)<int(previous.week) or previous.action!=["accept","branch","resolve","permit"][stage-2]: return false
			if stage>2 and record.branch!=previous.branch: return false
		recorded[record.event]=record
	for id in data.paths:
		if not value.paths.has(id): return false
		var path: Variant = value.paths[id]
		if not path is Dictionary or path.size()!=6 or not path.get("discovered") is bool or path.get("status") not in ["unknown","offered","unavailable","selected","declined","paused","complete"]: return false
		for field in ["stage","next_week","completed_week"]:
			if not _whole(path.get(field)): return false
		if path.stage>5 or path.next_week>54 or path.completed_week>52 or not path.get("branch") is String: return false
		if path.discovered and not value.plan.any(func(row): return row.id==id and int(row.week)<=int(state.week)): return false
		if not path.discovered and (path.status!="unknown" or path.stage!=0): return false
		if not path.discovered and recorded.values().any(func(row): return row.path==id): return false
		if (id in selected) != (path.status in ["selected","paused","complete"]): return false
		if recorded.values().filter(func(row): return row.path==id).size()!=int(path.stage): return false
		if path.stage==0:
			if path.branch!="" or path.completed_week!=0 or path.next_week!=0: return false
		else:
			if not recorded.has(data.paths[id].events[int(path.stage)-1]): return false
			var last: Dictionary = recorded[data.paths[id].events[int(path.stage)-1]]
			if last.branch!=path.branch: return false
			if int(path.next_week)!=int(last.week)+(2 if int(path.stage)==3 else 1): return false
			if path.status not in ["selected","declined","paused","complete"]: return false
			if path.status=="selected" and (path.stage==5 or last.action in ["decline","close"]): return false
			if path.status=="declined" and (path.stage!=1 or last.action!="decline"): return false
			if path.status=="paused" and (path.stage!=4 or last.action!="close"): return false
			if path.status=="complete" and (path.stage!=5 or path.completed_week!=last.week): return false
			if path.status!="complete" and path.completed_week!=0: return false
			var required := 3 if int(path.stage)==5 else 2 if int(path.stage)>=3 else 1 if int(path.stage)>=2 else 0
			if path_stage(state,str(id),content)<required: return false
		for facility in data.paths[id].buildings:
			var exists: bool = int(state.get("facilities",{}).get(facility,0))>0 or facility in state.get("orders",[]) or state.get("projects",[]).any(func(project): return project.get("id")==facility)
			if exists and (id not in selected or build_error(state,content,str(facility))!=""): return false
	for line in value.news:
		if not line is Dictionary or not line.get("text") is String or line.get("kind")!="fantasy" or line.get("level")!="info" or not _whole(line.get("week")): return false
	var pending := []
	var active_id := str(state.get("active_event",""))
	if data.events.has(active_id): pending.append(active_id)
	for queued in state.get("realm",{}).get("queue",[]):
		if not data.events.has(queued.get("id","")): continue
		if queued.id in pending: return false
		pending.append(queued.id)
	for id in pending:
		var event: Dictionary = data.events[id]
		var path: Dictionary = value.paths[event.fantasy_path]
		if not path.discovered or int(event.fantasy_stage)!=int(path.stage)+1 or path.status not in ["offered","selected"]: return false
	return true


static func _plans_equal(actual: Array, expected: Array) -> bool:
	if actual.size()!=expected.size(): return false
	for index in actual.size():
		if not actual[index] is Dictionary or actual[index].size()!=2 or actual[index].get("id")!=expected[index].id or not _whole(actual[index].get("week")) or int(actual[index].week)!=int(expected[index].week): return false
	return true


static func data_errors(data: Variant, content: Dictionary = {}) -> Array:
	if not data is Dictionary or data.get("version")!=1 or not data.get("paths") is Dictionary or data.paths.size()!=6 or not data.get("facilities") is Dictionary or data.facilities.size()!=18 or not data.get("events") is Dictionary or data.events.size()!=30: return ["이계 지구: 6방향·18시설·30사건 구조 필요"]
	var errors := []
	var mods := ["harvest","gather","logging","quarry","garden","smithy","spoil","storage","buy","wages","maintenance","heating","tool_use","build_work","threat_growth"]
	for id in data.paths:
		var path: Variant = data.paths[id]
		if not path is Dictionary or not path.get("name") is String or not path.get("buildings") is Array or path.buildings.size()!=3 or not path.get("events") is Array or path.events.size()!=5 or not path.get("branches") is Dictionary or path.branches.size()!=2: errors.append("이계 지구: 경로 정의 오류"); continue
		if not path.get("benefit") is String or not path.get("tradeoff") is String or not path.get("completion_reward") is Dictionary: errors.append("이계 지구: 설명·완성 보상 오류"); continue
		if content.has("chronicle") and not content.chronicle.families.has(path.get("family","")): errors.append("이계 지구: 특전 계열 오류")
		if content.has("village_relics") and not content.village_relics.categories.has(path.get("relic_family","")): errors.append("이계 지구: 성물 계열 오류")
		for asset in path.completion_reward:
			if asset not in ["money","food","wood","stone","tools","fuel"] or not _finite(path.completion_reward[asset]) or path.completion_reward[asset]<=0 or path.completion_reward[asset]>1000: errors.append("이계 지구: 완성 자원 보상 오류")
		for index in 3:
			var facility: Variant = data.facilities.get(path.buildings[index])
			if not facility is Dictionary or facility.get("fantasy_path")!=id or facility.get("fantasy_stage")!=index+1 or facility.get("max")!=1 or facility.get("fantasy")!=true: errors.append("이계 지구: 시설 연결 오류")
		for index in 5:
			var event: Variant = data.events.get(path.events[index])
			if not event is Dictionary or event.get("fantasy_path")!=id or event.get("fantasy_stage")!=index+1 or event.get("week")!=999 or event.get("fantasy_only")!=true: errors.append("이계 지구: 사건 연결 오류"); continue
			if not event.get("options") is Array or event.options.size()<2: errors.append("이계 지구: 선택지 부족"); continue
			for option in event.options:
				if not option.get("fantasy") is Dictionary or option.fantasy.get("path")!=id or option.fantasy.get("stage")!=index+1: errors.append("이계 지구: 선택 단계 오류"); continue
				if option.fantasy.get("action") not in [["accept","decline"],["branch"],["resolve"],["permit","close"],["complete"]][index]: errors.append("이계 지구: 선택 명령 오류")
				if index==1 and not path.branches.has(option.fantasy.get("branch","")): errors.append("이계 지구: 분기 연결 오류")
				if option.get("relic_offer",false) and index!=4: errors.append("이계 지구: 완료 전 성물 보상 오류")
				var need: Dictionary = option.get("requires",{})
				if need.has("perk_family"):
					if not need.perk_family is Dictionary or need.perk_family.get("id")!=path.family or not _whole(need.perk_family.get("count")) or need.perk_family.count<1 or need.perk_family.count>4: errors.append("이계 지구: 특전 조건 오류")
				if need.has("relic_family") and need.relic_family!=path.relic_family: errors.append("이계 지구: 성물 조건 오류")
		for branch in path.branches.values():
			if not branch is Dictionary or not branch.get("name") is String or not branch.get("text") is String: errors.append("이계 지구: 분기 설명 오류"); continue
			for key in branch.get("mods",{}):
				if key not in mods or not _finite(branch.mods[key]) or branch.mods[key]<.5 or branch.mods[key]>1.5: errors.append("이계 지구: 분기 배율 오류")
			for stat in branch.get("targets",{}):
				if stat not in ["health","security","mood"] or not _finite(branch.targets[stat]) or absf(float(branch.targets[stat]))>15: errors.append("이계 지구: 분기 목표 오류")
	for facility in data.facilities.values():
		if not facility is Dictionary: continue
		if facility.has("jobs") and (not _whole(facility.jobs) or facility.jobs<1 or facility.jobs>6): errors.append("이계 지구: 생산 인력 오류")
		if facility.has("output") and not facility.has("jobs"): errors.append("이계 지구: 노동 없는 생산 오류")
		if facility.get("account","public") not in ["public","resident"]: errors.append("이계 지구: 생산 계정 오류")
		if facility.get("output_bonus","") not in ["","garden","gather","logging","quarry","smithy"]: errors.append("이계 지구: 미소비 생산 보정")
		for key in facility.get("mods",{}):
			if key not in mods or not _finite(facility.mods[key]) or facility.mods[key]<.5 or facility.mods[key]>1.5: errors.append("이계 지구: 시설 배율 오류")
		for stat in facility.get("targets",{}):
			if stat not in ["health","security","mood"] or not _finite(facility.targets[stat]) or absf(float(facility.targets[stat]))>15: errors.append("이계 지구: 시설 목표 오류")
		for direction in ["input","output"]:
			for key in facility.get(direction,{}):
				if key not in ["food","wood","stone","tools","fuel","iron"] or not _finite(facility[direction][key]) or float(facility[direction][key])<=0: errors.append("이계 지구: 생산 자원 오류")
				if direction=="output" and facility.get("account")=="resident" and key!="food": errors.append("이계 지구: 주민 생산 계정 오류")
	return errors


static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
