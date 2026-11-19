class_name WorkcrewRules
extends RefCounted
## 농사 우선 배치 뒤 남은 인력 중 직영 작업반만 운용한다. 생산식과 결제는 WeekSim을 따른다.

const IDS := ["balanced", "food", "build", "winter"]
const JOBS := ["gather", "build", "logging", "quarry", "garden", "fuel", "milling"]
const DATA_PATH := "res://content/workcrew.json"
const PREVIEW_SCOPE := "착공 비용·생산·소비를 반영한 기본 작업 예상입니다. 보좌관·사건·도착 물자·계절 보상·겨울 시련·성물·운영 조합의 주간 교환은 제외합니다."


static func enabled(state: Dictionary) -> bool:
	return state.get("workcrew", {}) is Dictionary and state.get("workcrew", {}).get("enabled", false) == true


static func valid(state: Dictionary) -> bool:
	if not state.has("workcrew"): return true
	var value: Variant = state.workcrew
	if not value is Dictionary or not value.get("enabled") is bool: return false
	if not (value.get("version") is int or value.get("version") is float) or value.version != 1: return false
	return value.get("policy") is String and value.policy in IDS


static func setup(state: Dictionary, config: Dictionary) -> bool:
	if state.is_empty() or config.get("workcrew", false) != true or config.get("campaign", false) != true: return false
	# 기존 회차의 명시적 비활성화나 잘못된 값을 자동으로 덮어쓰지 않는다.
	if state.has("workcrew"): return enabled(state) and valid(state)
	state.workcrew = {"enabled":true, "version":1, "policy":"balanced"}
	return true


static func _definitions(content: Dictionary) -> Dictionary:
	if content.get("workcrew") is Dictionary: return content.workcrew
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed if parsed is Dictionary else {}


static func _result(state: Dictionary) -> Dictionary:
	var policy := str(state.get("workcrew", {}).get("policy", "balanced")) if state.get("workcrew", {}) is Dictionary else "balanced"
	return {"enabled":enabled(state), "changed":false, "focus":policy, "policy":policy,
		"assign":state.get("assign", {}).duplicate(true), "available":0, "farm":0, "reserved":0,
		"budget":0, "crew":0, "idle":0, "work_remaining":0, "blocked":false, "errors":[], "notes":[]}


static func allocate(state: Dictionary, content: Dictionary) -> Dictionary:
	var result := _result(state)
	if not result.enabled: return result
	if not valid(state) or state.get("status", "") != "active":
		result.blocked = true
		result.errors.append("작업반 방침이 올바르지 않습니다." if not valid(state) else "종료된 회차입니다.")
		return result
	var data := _definitions(content)
	if data.is_empty() or not data.get("policies", {}).has(result.policy):
		result.blocked = true
		result.errors.append("작업반 설정을 읽지 못했습니다.")
		return result
	var definition: Dictionary = data.policies[result.policy]
	# 비용·첫 개간 특성·이미 진행 중인 공사를 포함한 착공 이후 용량을 읽는다.
	# CabinetRules.reassign은 이 함수로 위임하므로 여기서 호출하면 안 된다.
	var trial: Dictionary = state.duplicate(true)
	for id in state.get("orders", []):
		var error := WeekSim._start_project(trial, content, str(id), [])
		if error != "": result.errors.append(error)
	if not result.errors.is_empty():
		result.blocked = true
		return result
	for project in trial.projects: result.work_remaining += int(project.work_left)
	var week := WeekSim.week_of_year(int(state.week))
	var season := WeekSim.season_of(week)
	result.available = maxi(0, int(floor(float(state.pop) * float(state.labor_ratio))))
	result.farm = mini(result.available, WeekSim.farm_demand(state, week))
	result.budget = mini(int(data.crew_limit), maxi(0, result.available - result.farm))
	result.reserved = maxi(0, result.available - result.farm - result.budget)
	var budget := {"left":int(result.budget)}
	var plan := {}
	for job in JOBS: plan[job] = 0
	var facilities: Dictionary = state.facilities
	var caps := {"gather":int(definition.gather_per_site) * int(facilities.get("B17", 0)),
		"garden":int(definition.garden_per_site) * int(facilities.get("B14", 0)),
		"build":mini(int(definition.build_limit), result.work_remaining),
		"logging":4 * int(facilities.get("B25", 0)), "quarry":4 * int(facilities.get("B27", 0)),
		"milling":3 * int(facilities.get("B19", 0))}
	if season == 3:
		caps.garden = 0
		if WeekSim.bonus(state, "winter_gather", 0.0) <= 0: caps.gather = 0
	if WeekSim.total_food(state) <= 0: caps.milling = 0
	var materials := {"wood":float(trial.public.wood), "tools":float(trial.public.tools)}
	var unpaid := int(state.get("unpaid_weeks", 0))
	var efficiency := .5 if unpaid >= 8 else .75 if unpaid >= 4 else 1.0
	for job in definition.order:
		if job == "woodwork":
			_woodwork(state, plan, budget, materials, caps.logging, efficiency, definition.wood_mode == "fuel")
		elif job == "quarry":
			_quarry(state, plan, budget, materials, caps.quarry, efficiency)
		else:
			_take(plan, budget, str(job), int(caps[job]))
	result.crew = result.budget - int(budget.left)
	result.idle = int(budget.left)
	result.assign = plan.duplicate(true)
	result.changed = state.assign != plan
	state.assign = plan
	result.notes.append("농사 %d명 · 직영 작업 %d / %d명 · 주민 생업 %d명" % [result.farm,result.crew,result.budget,result.reserved])
	if result.work_remaining > 0 and plan.build == 0:
		result.notes.append("선택한 작업을 우선해 이번 주 공사는 대기합니다.")
	var unavailable := _unavailable(state, result, str(result.policy))
	if unavailable != "": result.notes.append(unavailable)
	return result


static func _take(plan: Dictionary, budget: Dictionary, job: String, target: int) -> int:
	var added := mini(int(budget.left), maxi(0, target - int(plan[job])))
	plan[job] += added
	budget.left -= added
	return added


static func _woodwork(state: Dictionary, plan: Dictionary, budget: Dictionary, materials: Dictionary, cap: int, efficiency: float, fuel_first: bool) -> void:
	if cap <= 0: return
	var tool_cost := .2 * WeekSim.bonus(state, "tool_use")
	var logging_limit := cap
	if fuel_first:
		logging_limit = 0 if materials.wood >= cap * 3.0 * efficiency else int(ceil(cap / 2.0))
	if tool_cost <= 0 or materials.tools <= 0:
		logging_limit = 0
	else:
		logging_limit = mini(logging_limit, int(ceil(materials.tools / tool_cost * 4.0 / efficiency)))
	var logging := _take(plan, budget, "logging", logging_limit)
	if logging > 0:
		var output := minf(logging / 4.0 * efficiency, materials.tools / tool_cost)
		materials.tools = maxf(0, materials.tools - output * tool_cost)
		materials.wood += output * 20.0 * WeekSim.bonus(state, "logging")
	if fuel_first and materials.wood > 0:
		var fuel_limit := mini(cap - int(plan.logging), int(ceil(materials.wood / (3.0 * efficiency))))
		_take(plan, budget, "fuel", fuel_limit)


static func _quarry(state: Dictionary, plan: Dictionary, budget: Dictionary, materials: Dictionary, cap: int, efficiency: float) -> void:
	var tool_cost := .2 * WeekSim.bonus(state, "tool_use")
	if cap <= 0 or tool_cost <= 0 or materials.tools <= 0: return
	var limit := mini(cap, int(ceil(materials.tools / tool_cost * 4.0 / efficiency)))
	_take(plan, budget, "quarry", limit)


static func _unavailable(state: Dictionary, allocation: Dictionary, id: String) -> String:
	if id == "build" and allocation.work_remaining == 0: return "진행할 공사가 없습니다."
	if id == "food" and allocation.assign.get("gather",0) + allocation.assign.get("garden",0) == 0:
		return "이번 주에 운영할 채집터나 채소밭이 없습니다."
	if id == "winter":
		if int(state.facilities.get("B25",0)) == 0: return "장작을 만들 벌목소가 필요합니다."
		if allocation.assign.get("fuel",0) == 0: return "장작을 가공할 인력이나 목재가 부족합니다."
	return ""


static func select(state: Dictionary, content: Dictionary, id: String) -> String:
	if not enabled(state) or state.get("status", "") != "active": return "진행 중인 직영 작업반이 없습니다."
	if id not in IDS: return "알 수 없는 작업 방침입니다."
	if not valid(state): return "작업반 방침이 올바르지 않습니다."
	var trial: Dictionary = state.duplicate(true)
	trial.workcrew.policy = id
	var allocation := allocate(trial, content)
	if allocation.blocked: return " · ".join(allocation.errors)
	var error := _unavailable(trial, allocation, id)
	if error != "": return error
	state.workcrew.policy = id
	state.assign = trial.assign.duplicate(true)
	return ""


static func choices(state: Dictionary, content: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not enabled(state) or not valid(state): return result
	var data := _definitions(content)
	for id in IDS:
		var definition: Dictionary = data.policies[id]
		var trial: Dictionary = state.duplicate(true)
		trial.workcrew.policy = id
		var allocation := allocate(trial, content)
		var row := {"id":id, "name":str(definition.name), "description":str(definition.description),
			"selected":state.workcrew.policy == id, "available":false, "error":"", "scope":PREVIEW_SCOPE,
			"allocation":allocation, "production":{"food":0.0,"wood":0.0,"fuel":0.0},
			"deltas":{"food":0.0,"money":0.0,"wood":0.0,"fuel":0.0}, "work":0,
			"completed":[], "completed_count":0, "workers":{}, "budget":allocation.budget, "idle":allocation.idle}
		if allocation.blocked:
			row.error = " · ".join(allocation.errors)
			result.append(row)
			continue
		row.error = _unavailable(trial, allocation, id)
		var ledger_start: int = trial.ledger.size()
		var outcome := WeekSim.process_week(trial, content)
		if not outcome.advanced:
			row.error = " · ".join(outcome.notes)
			result.append(row)
			continue
		row.available = row.error == ""
		row.workers = trial.labor_report.duplicate(true)
		for asset in row.deltas:
			row.deltas[asset] = WeekSim.total_food(trial) - WeekSim.total_food(state) if asset == "food" else float(trial.public.get(asset,0)) - float(state.public.get(asset,0))
		for entry in trial.ledger.slice(ledger_start):
			if float(entry.qty) <= 0: continue
			if entry.asset == "food" and entry.src in ["gather","garden","harvest"]: row.production.food += float(entry.qty)
			if entry.asset == "wood" and entry.src == "logging": row.production.wood += float(entry.qty)
			if entry.asset == "fuel" and entry.src == "fuel": row.production.fuel += float(entry.qty)
		var remaining := 0
		for project in trial.projects: remaining += int(project.work_left)
		row.work = maxi(0, int(allocation.work_remaining) - remaining)
		for facility in trial.facilities:
			var count := int(trial.facilities[facility]) - int(state.facilities.get(facility,0))
			if count > 0:
				row.completed.append({"id":str(facility), "name":str(content.facilities[facility].name), "count":count})
				row.completed_count += count
		result.append(row)
	return result
