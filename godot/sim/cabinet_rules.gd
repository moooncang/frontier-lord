class_name CabinetRules
extends RefCounted
## 명시적으로 켠 회차의 노동 요청만 자동 작성한다. 경제 처리는 WeekSim이 수행한다.

const FOCUSES := ["balanced", "food", "build", "winter"]
const JOBS := ["gather", "build", "logging", "quarry", "garden", "fuel", "milling"]


static func enabled(state: Dictionary) -> bool:
	return state.get("cabinet", {}) is Dictionary and state.get("cabinet", {}).get("enabled", false) == true


static func setup(state: Dictionary) -> void:
	if state.is_empty(): return
	var cabinet: Dictionary = state.get("cabinet", {}).duplicate(true) if state.get("cabinet", {}) is Dictionary else {}
	cabinet.enabled = true
	if cabinet.get("focus", "") not in FOCUSES: cabinet.focus = "balanced"
	if not cabinet.has("advisor"): cabinet.advisor = "CH01"
	state.cabinet = cabinet


static func set_focus(state: Dictionary, content: Dictionary, focus: String) -> Dictionary:
	if not enabled(state) or focus not in FOCUSES:
		var rejected := _result(state)
		rejected.blocked = true
		rejected.errors.append("간편 통치가 켜져 있지 않습니다." if not enabled(state) else "알 수 없는 운영 우선순위입니다.")
		return rejected
	var previous: Dictionary = state.cabinet.duplicate(true)
	state.cabinet.focus = focus
	var result := reassign(state, content)
	if result.blocked:
		state.cabinet = previous
		result.focus = str(previous.get("focus", "balanced"))
	else:
		result.changed = result.changed or previous.focus != focus
	return result


static func reassign(state: Dictionary, content: Dictionary) -> Dictionary:
	if WorkcrewRules.enabled(state): return WorkcrewRules.allocate(state, content)
	var result := _result(state)
	if not result.enabled: return result
	if state.get("status", "active") != "active":
		result.blocked = true
		result.errors.append("종료된 회차입니다.")
		return result
	# 실제 착공 검증을 복제 상태에만 적용한다. 예약 비용과 M04 작업량도 엔진을 따른다.
	var trial: Dictionary = state.duplicate(true)
	for id in state.get("orders", []):
		var error := WeekSim._start_project(trial, content, str(id), [])
		if error != "": result.errors.append(error)
	if not result.errors.is_empty():
		result.blocked = true
		return result
	var remaining := 0
	for project in trial.projects: remaining += int(project.work_left)
	result.work_remaining = remaining
	var wy := WeekSim.week_of_year(int(state.week))
	var season := WeekSim.season_of(wy)
	result.available = maxi(0, int(floor(state.pop * state.labor_ratio)))
	result.farm = mini(result.available, WeekSim.farm_demand(state, wy))
	var budget := {"left":result.available - result.farm}
	var plan := {}
	for job in JOBS: plan[job] = 0
	var facilities: Dictionary = state.facilities
	var caps := {
		"gather":8 * int(facilities.get("B17", 0)), "build":mini(8, remaining),
		"logging":4 * int(facilities.get("B25", 0)), "quarry":4 * int(facilities.get("B27", 0)),
		"garden":4 * int(facilities.get("B14", 0)), "milling":3 * int(facilities.get("B19", 0))
	}
	if season == 3:
		caps.garden = 0
		if WeekSim.bonus(state, "winter_gather", 0.0) <= 0: caps.gather = 0
	if WeekSim.total_food(state) <= 0: caps.milling = 0
	var materials := {"wood":float(trial.public.wood), "tools":float(trial.public.tools)}
	var efficiency := .5 if int(state.get("unpaid_weeks", 0)) >= 8 else .75 if int(state.get("unpaid_weeks", 0)) >= 4 else 1.0
	var focus := str(result.focus)
	if focus == "food":
		_take(plan, budget, "gather", caps.gather)
		_take(plan, budget, "garden", caps.garden)
		_take(plan, budget, "build", caps.build)
		_woodwork(state, plan, budget, materials, caps.logging, efficiency, false)
	elif focus == "winter":
		_take(plan, budget, "gather", mini(8, caps.gather))
		_woodwork(state, plan, budget, materials, caps.logging, efficiency, true)
		_take(plan, budget, "build", caps.build)
		_take(plan, budget, "garden", caps.garden)
		_take(plan, budget, "gather", caps.gather)
	else:
		_take(plan, budget, "gather", mini(8, caps.gather))
		_take(plan, budget, "build", caps.build)
		if focus == "balanced":
			_take(plan, budget, "gather", caps.gather)
			_take(plan, budget, "garden", caps.garden)
		_woodwork(state, plan, budget, materials, caps.logging, efficiency, season >= 2)
	_quarry(state, plan, budget, materials, caps.quarry, efficiency)
	_take(plan, budget, "garden", caps.garden)
	_take(plan, budget, "gather", caps.gather)
	_take(plan, budget, "milling", caps.milling)
	result.idle = int(budget.left)
	result.assign = plan.duplicate(true)
	result.changed = state.assign != plan
	state.assign = plan
	result.notes.append("농사 %d명 · 공공 작업 %d명 · 유휴 %d명" % [result.farm, result.available - result.farm - result.idle, result.idle])
	result.notes.append("남은 공사 %d인주 · 이번 주 건설 %d명 배치" % [remaining, plan.build] if remaining > 0 else "진행할 공사가 없습니다.")
	if remaining > 0 and int(plan.build) == 0: result.notes.append("농사와 선택한 우선 작업에 인력을 사용해 이번 주 공사는 진행되지 않습니다.")
	if caps.logging + caps.quarry > 0 and materials.tools <= 0 and plan.logging + plan.quarry == 0:
		result.notes.append("도구가 없어 벌목·채석을 배치하지 않았습니다.")
	if focus == "winter" and caps.logging == 0: result.notes.append("벌목소가 없어 장작을 생산할 수 없습니다.")
	return result


static func _result(state: Dictionary) -> Dictionary:
	var cabinet: Dictionary = state.get("cabinet", {}) if state.get("cabinet", {}) is Dictionary else {}
	var focus := str(cabinet.get("focus", "balanced"))
	return {"enabled":enabled(state), "changed":false, "focus":focus if focus in FOCUSES else "balanced",
		"assign":state.get("assign", {}).duplicate(true), "available":0, "farm":0, "idle":0,
		"work_remaining":0, "blocked":false, "errors":[], "notes":[]}


## 목표 인원까지 추가 배치한다. 이미 채운 작업을 다시 호출해도 중복 배치하지 않는다.
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
		# 목재가 충분하면 전원 장작, 부족하면 절반을 벌목에 배치한다. 두 작업은 한도를 공유한다.
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
