class_name WeeklyBrief
extends RefCounted
## 읽기 전용 주간 보고. UI를 열어도 경제·난수·기록을 변경하지 않는다.

const FOOD_SOURCES := {"harvest":"곡물 수확", "gather":"채집", "garden":"채소 생산", "consume":"주민 소비", "spoil":"보관 손실", "seed":"파종 종자", "event":"사건", "event_cost":"사건 지출", "trade_arrival":"교역 도착", "trade_depart":"판매 출하"}
const PREVIEW_SCOPE := "현재 예약과 노동 배치로 이번 주 경제만 계산한 예상입니다. 미결 선택·새 사건·교역 도착·계절 계약·겨울 시련·건강·민심 결산은 제외합니다."

static func build(state: Dictionary, content: Dictionary) -> Dictionary:
	if state.is_empty(): return {}
	var week := int(state.week)
	var history: Array = state.get("history", [])
	var last: Dictionary = history.back() if not history.is_empty() else {}
	var previous: Dictionary = history[history.size() - 2] if history.size() > 1 else {}
	var preview := _preview(state, content)
	var construction := _construction(state, content, preview)
	var calendar := _calendar(week)
	var food := _food_ledger(state, int(last.get("week", 0)))
	var priorities := _priorities(state, content, preview, construction, calendar)
	var report := {
		"week":int(last.get("week", 0)), "has_previous":not last.is_empty(),
		"food":food, "notes":last.get("notes", []).duplicate(true),
		"scope":"최신 완료 주의 원장 기록입니다. 공공·주민 간 이전은 총재고 변화가 없어 합계에서 제외합니다. 운송 도착은 다음 주 번호로 기록되므로 원장 합계와 주말 잔액 증감은 다를 수 있습니다."
	}
	return {
		"week":week, "season":WeekSim.SEASON_NAMES[WeekSim.season_of(clampi(week, 1, 52))],
		"headline":priorities[0].title if not priorities.is_empty() else "이번 주 운영 계획을 확인하세요.",
		"metrics":{
			"money":_metric(float(state.public.money), "money", last, previous),
			"food":_metric(WeekSim.total_food(state), "food", last, previous),
			"pop":_metric(float(state.pop), "pop", last, previous),
			"food_weeks":WeekSim.food_weeks(state)
		},
		"report":report, "preview":preview, "construction":construction,
		"calendar":calendar, "priorities":priorities.slice(0, 3)
	}

static func _metric(value: float, key: String, last: Dictionary, previous: Dictionary) -> Dictionary:
	var known := not last.is_empty() and not previous.is_empty()
	return {"value":value, "delta":float(last[key]) - float(previous[key]) if known else 0.0,
		"has_delta":known, "report_value":float(last.get(key, value)),
		"current_delta":value - float(last.get(key, value)),
		"delta_scope":"직전 두 완료 주의 잔액 차이" if known else "비교할 이전 주 기록 없음"}

static func _food_ledger(state: Dictionary, completed_week: int) -> Dictionary:
	var result := {"production":0.0, "consumption":0.0, "spoilage":0.0, "seeds":0.0, "other_in":0.0, "other_out":0.0, "net":0.0, "by_source":{}, "rows":[], "transferred":0.0}
	if completed_week <= 0: return result
	for entry in state.get("ledger", []):
		if int(entry.w) != completed_week or entry.asset != "food": continue
		if entry.src == "transfer":
			result.transferred += float(entry.get("amount", 0))
			continue
		var amount := float(entry.qty)
		var source := str(entry.src)
		result.net += amount
		result.by_source[source] = float(result.by_source.get(source, 0)) + amount
		match source:
			"harvest", "gather", "garden", "fishery": result.production += amount
			"consume": result.consumption -= amount
			"spoil": result.spoilage -= amount
			"seed": result.seeds -= amount
			_:
				if amount > 0: result.other_in += amount
				else: result.other_out -= amount
	for source in result.by_source:
		result.rows.append({"source":source, "name":FOOD_SOURCES.get(source, source), "amount":result.by_source[source]})
	return result

static func _preview(state: Dictionary, content: Dictionary) -> Dictionary:
	var result := {"available":false, "week":int(state.week), "result_week":int(state.week) + 1, "scope":PREVIEW_SCOPE, "blocked_reasons":[], "notes":[], "labor":{}, "deltas":{}}
	if state.get("status", "active") != "active" or int(state.week) > 52:
		result.blocked_reasons.append("종료된 회차입니다.")
		return result
	var trial: Dictionary = state.duplicate(true)
	var outcome := WeekSim.process_week(trial, content)
	result.available = bool(outcome.advanced)
	result.notes = outcome.notes.duplicate(true)
	if not result.available:
		result.blocked_reasons = outcome.notes.duplicate(true)
		return result
	result.money = int(trial.public.money)
	result.food = WeekSim.total_food(trial)
	result.food_weeks = WeekSim.food_weeks(trial)
	result.pop = int(trial.pop)
	result.fuel = float(trial.public.fuel)
	result.arrears = int(trial.arrears_wage)
	result.food_satisfaction = float(trial.food_satisfaction)
	result.heat_fill = float(trial.get("heat_fill", 1.0))
	result.labor = trial.get("labor_report", {}).duplicate(true)
	result.deltas = {"money":int(trial.public.money) - int(state.public.money), "food":WeekSim.total_food(trial) - WeekSim.total_food(state), "pop":int(trial.pop) - int(state.pop), "fuel":float(trial.public.fuel) - float(state.public.fuel)}
	result.food_flow = _food_ledger({"ledger":trial.ledger.slice(state.ledger.size())}, int(state.week))
	return result

static func _construction(state: Dictionary, content: Dictionary, preview: Dictionary) -> Dictionary:
	var queued: Array = []
	var projects: Array = []
	var total_work := 0
	var work_to_allocate := int(preview.labor.get("build", 0))
	var efficiency := 0.5 if int(state.get("unpaid_weeks", 0)) >= 8 else (0.75 if int(state.get("unpaid_weeks", 0)) >= 4 else 1.0)
	work_to_allocate = int(floor(work_to_allocate * efficiency))
	var actual_work := work_to_allocate
	for i in state.projects.size():
		var project: Dictionary = state.projects[i]
		var left := int(project.work_left)
		var applied := mini(left, work_to_allocate)
		work_to_allocate -= applied
		total_work += left
		projects.append({"id":project.id, "name":content.facilities[project.id].name, "index":i,
			"work_left":left, "work_total":int(project.work_total), "progress":1.0 - float(left) / maxf(1, float(project.work_total)),
			"escrow":int(project.escrow), "next_work":applied, "completes_this_week":applied >= left})
	var survey_used := bool(state.get("first_survey", false))
	for i in state.orders.size():
		var id := str(state.orders[i])
		if not content.facilities.has(id): continue
		var facility: Dictionary = content.facilities[id]
		var cost: Dictionary = Constants.GRADE_COST[facility.grade]
		var work := int(cost.work)
		if id == "B13" and "M04" in state.get("meta_snapshot", []) and not survey_used:
			work = int(ceil(work * .85))
			survey_used = true
		work = maxi(1, int(ceil(work * RealmRules.mod(state, "build_work"))))
		var applied := mini(work, work_to_allocate)
		work_to_allocate -= applied
		total_work += work
		queued.append({"id":id, "name":facility.name, "index":i, "work_left":work, "work_total":work,
			"cost":{"money":int(cost.gold) * Constants.COPPER_PER_GOLD, "wood":int(cost.wood), "stone":int(cost.stone), "tools":int(cost.tools), "iron":int(cost.iron)},
			"next_work":applied, "completes_this_week":applied >= work})
	return {"queued":queued, "projects":projects, "requested_workers":int(state.assign.get("build", 0)),
		"actual_workers":int(preview.labor.get("build", 0)), "remaining_work":total_work, "work_this_week":actual_work,
		"blocked":total_work > 0 and actual_work == 0}

static func _calendar(week: int) -> Dictionary:
	var harvest_active := week >= 33 and week <= 36
	var winter_active := week >= 40 and week <= 52
	return {"harvest_week":33 if week <= 36 else 0, "harvest_in":maxi(0, 33 - week) if week <= 36 else -1,
		"harvest_active":harvest_active, "harvest_text":"수확 진행 중 · 36주까지" if harvest_active else ("수확까지 %d주" % (33 - week) if week < 33 else "올해 수확 종료"),
		"winter_week":40 if week <= 52 else 0, "winter_in":maxi(0, 40 - week) if week <= 52 else -1,
		"winter_active":winter_active, "winter_text":"겨울 진행 중 · %d주 남음" % (53 - week) if winter_active else ("겨울까지 %d주" % (40 - week) if week < 40 else "회차 종료")}

static func _priority(id: String, severity: String, title: String, body: String, action: String, page: String, tab: String = "", facility: String = "") -> Dictionary:
	return {"id":id, "severity":severity, "title":title, "body":body, "action":action, "page":page, "tab":tab, "facility":facility}

static func _planned(state: Dictionary, id: String) -> int:
	var count: int = int(state.facilities.get(id, 0)) + state.orders.count(id)
	for project in state.projects:
		if project.id == id: count += 1
	return count

static func _priorities(state: Dictionary, content: Dictionary, preview: Dictionary, construction: Dictionary, calendar: Dictionary) -> Array:
	var out: Array = []
	var weeks := WeekSim.food_weeks(state)
	var critical_food: bool = weeks < 4 or (preview.available and preview.food_satisfaction < .75)
	if critical_food:
		out.append(_priority("food_critical", "danger", "식량 %.1f주분 · 공급 확보 필요" % weeks,
			"현재 식량 %.0f, 현재 배급량은 주당 %.0f입니다. 구매 물자는 2주 뒤 도착합니다. 채집 배치와 주문 도착일을 함께 확인하세요." % [WeekSim.total_food(state), state.pop * Constants.FOOD_PER_PERSON_WEEK * state.ration], "식량 거래 확인", "trade"))
	if not preview.available and not preview.blocked_reasons.is_empty() and state.get("status", "active") == "active":
		out.append(_priority("orders_blocked", "danger", "건설 예약을 처리할 수 없습니다", " / ".join(preview.blocked_reasons), "예약 조정", "build", "queue"))
	if preview.available and preview.arrears > int(state.arrears_wage):
		out.append(_priority("cash_shortfall", "danger", "이번 주 비용 미지급 예상", "현재 금고 %.2f금입니다. 계획대로 진행하면 미지급 비용이 %.2f금 늘어납니다. 건설 예약과 인력 배치를 조정하세요." % [state.public.money / 100.0, (preview.arrears - int(state.arrears_wage)) / 100.0], "지출과 예약 확인", "build", "queue"))
	if calendar.winter_active and preview.available and preview.heat_fill < 1.0:
		out.append(_priority("heating_critical", "danger", "이번 주 난방용 장작 부족", "현재 장작 %.0f. 예정된 생산을 포함해도 이번 주 난방 수요의 %.0f%%만 충족합니다." % [state.public.fuel, preview.heat_fill * 100], "장작 공급 확인", "trade"))
	var housing := int(WeekSim.capacity(state, content, "housing"))
	if housing < int(state.pop):
		out.append(_priority("housing", "warning", "주거 %d명분 부족" % (int(state.pop) - housing), "주민 %d명에 주거 %d명분입니다. 움집 구역을 추가하면 한 구역당 40명분을 확보합니다." % [state.pop, housing], "주거 확장", "build", "facilities", "B01"))
	if construction.blocked:
		out.append(_priority("construction_labor", "warning", "공사에 배치되는 인력이 없습니다", "남은 공사 %d인주. 건설 요청 %d명 중 실제 배치가 0명입니다. 농사·채집이 먼저 인력을 사용하므로 실제 배치를 확인하세요." % [construction.remaining_work, construction.requested_workers], "노동 재배치", "build", "labor"))
	elif construction.actual_workers < construction.requested_workers and construction.remaining_work > construction.work_this_week:
		out.append(_priority("construction_shortfall", "warning", "건설 요청보다 실제 배치가 적습니다", "요청 %d명 → 실제 %d명. 현재 계획으로 이번 주 %d인주를 처리하고 %d인주가 남습니다." % [construction.requested_workers, construction.actual_workers, construction.work_this_week, construction.remaining_work - construction.work_this_week], "노동 배치 확인", "build", "labor"))
	if not critical_food and weeks < 8:
		out.append(_priority("food_warning", "warning", "식량 %.1f주분 · 수확 전 보급 확인" % weeks, "구매 수레는 2주 뒤 도착합니다. 채집 생산과 수레 도착분을 확인한 뒤 부족분을 주문하세요.", "식량 거래 확인", "trade"))
	if int(state.week) >= 27 and int(state.week) < 40:
		var heating := WeekSim.bonus(state, "heating")
		if state.get("trial", "") == "frost" and not state.get("trial_started", false): heating *= 1.5
		var target: float = state.pop * .1 * heating * 13
		if state.public.fuel < target:
			out.append(_priority("winter_stock", "warning", "겨울 장작 준비 · %.0f / %.0f" % [state.public.fuel, target], "겨울까지 %d주. 현재 인구와 예고된 시련 기준의 13주 난방량입니다. 예정 생산과 운송 중 장작은 이 재고에 포함하지 않았습니다." % calendar.winter_in, "장작 공급 계획", "trade"))
	if _planned(state, "B13") < 6:
		var body := "현재 %d구획, 예약·공사 포함 %d구획입니다. 농지 6구획이 회차의 최종 목표입니다." % [state.facilities.get("B13", 0), _planned(state, "B13")]
		body += " 3주 파종 전에 완공해야 올해 수확에 반영됩니다." if int(state.week) < 3 else " 올해 파종 구획은 3주에 확정되므로 지금 추가한 농지는 올해 수확량을 늘리지 않습니다."
		out.append(_priority("farm_goal", "plan", "농지 6구획 확보", body, "농지 건설", "build", "facilities", "B13"))
	if _planned(state, "B22") < 1:
		out.append(_priority("granary_goal", "plan", "곡물 곳간 건설", "곡물 곳간 1개가 회차의 최종 목표입니다. 저장량이 12,000 늘어나고 보관 손실률이 낮아집니다.", "곳간 건설", "build", "facilities", "B22"))
	if out.is_empty():
		out.append(_priority("review", "plan", "진행 중인 계획을 확인하세요", "현재 긴급 경고가 없습니다. 이번 주 예상 생산·소비와 공사 진행을 확인한 뒤 시간을 진행하세요.", "노동 배치 확인", "build", "labor"))
	return out
