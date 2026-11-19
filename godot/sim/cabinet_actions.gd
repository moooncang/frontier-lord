class_name CabinetActions
extends RefCounted
## 간편 통치의 사업·물자·보좌관 명령. 화면을 열거나 견적을 봐도 원본은 바뀌지 않는다.

const BENEFITS := {
	"B01":"주거 +40명", "B06":"물 공급 +100명", "B13":"곡물 수확량 증가",
	"B14":"겨울 전까지 채소 생산", "B17":"주민 식량 채집", "B19":"식량 보관 손실 감소",
	"B22":"식량 저장 +12,000", "B25":"목재·장작 생산", "B27":"석재 생산",
	"B49":"운송 수수료 감소", "B59":"주민 건강 개선", "B63":"세금 수금률 개선"
}
const SUPPLIES := {
	"food":{"title":"식량 확보", "quantity":0}, "wood":{"title":"건설용 목재", "quantity":40},
	"stone":{"title":"건설용 석재", "quantity":40}, "tools":{"title":"공용 도구", "quantity":4},
	"fuel":{"title":"겨울 장작", "quantity":120}
}
const ADVISOR_EFFECTS := {"trust":"신뢰", "security":"치안", "health":"건강", "guild":"상인 호감", "village":"주민 관계", "mood":"민심"}
const ETA_LIMIT := 16
const ETA_SCOPE := "사건과 교역 도착을 제외한 경제 예상입니다."
const PROJECT_SCOPE := "현재 작업 방침·농사·공사 순서·미지급 임금의 효율을 반영한 예상입니다. 미래의 사건·보좌관·날씨 변화·물자 입고는 제외합니다. 완공한 시설은 다음 주부터 운영합니다."


static func offer(session: GameSession, id: String) -> Dictionary:
	var result := {"id":id, "count":1, "name":id, "benefit":"", "cost":{}, "error":"", "eta":-1, "eta_text":"완공 시기 미정"}
	if session == null or not session.content.facilities.has(id):
		result.error = "알 수 없는 시설입니다."
		return result
	var facility: Dictionary = session.content.facilities[id]
	var count := _count(session.state, id)
	result.count = count
	result.name = "%s %d구획" % [facility.name, count] if id == "B13" else facility.name
	result.benefit = BENEFITS.get(id, "")
	var grade: Dictionary = Constants.GRADE_COST[facility.grade]
	result.cost = {"money":int(grade.gold * Constants.COPPER_PER_GOLD) * count}
	for asset in ["wood", "stone", "tools", "iron"]: result.cost[asset] = int(grade[asset]) * count
	var plan := _plan(session, id, count)
	result.error = plan.error
	if result.error != "":
		result.eta_text = "착공 불가"
		return result
	var preview := _completion(plan.trial, id, count)
	result.eta = preview.eta
	result.eta_text = preview.text
	return result


static func start_project(session: GameSession, id: String) -> String:
	if session == null: return "진행 중인 회차가 없습니다."
	var plan := _plan(session, id, _count(session.state, id))
	if plan.error != "": return str(plan.error)
	var trial: GameSession = plan.trial
	# 원본에는 검증이 끝난 예약과 배치만 반영한다. 자원 결제는 실제 주 진행 때 한다.
	session.state.orders = trial.state.orders.duplicate(true)
	session.state.assign = trial.state.assign.duplicate(true)
	var work_plan := CabinetRules.reassign(trial.state,trial.content)
	session.state.cabinet.project = {"id":id,"count":_count(session.state,id),"start_count":int(session.state.facilities.get(id,0)),"total_work":int(work_plan.work_remaining)}
	session._update_goals()
	return ""


static func _count(state: Dictionary, id: String) -> int:
	return clampi(6 - int(state.get("facilities", {}).get("B13", 0)), 1, 2) if id == "B13" else 1


static func _plan(session: GameSession, id: String, count: int) -> Dictionary:
	var result := {"trial":null, "error":""}
	if session.state.is_empty() or session.state.get("status", "") != "active":
		result.error = "진행 중인 회차가 없습니다."
		return result
	if not CabinetRules.enabled(session.state):
		result.error = "간편 통치가 켜져 있지 않습니다."
		return result
	var sites: int = session.state.orders.size() + session.state.projects.size()
	if sites > 0 and sites + count > RealmRules.project_limit(session.state, session.content):
		result.error = "진행 중인 공사를 먼저 끝내세요" if not RealmRules.enabled(session.state) else "공사는 동시에 %d곳까지 진행할 수 있습니다" % RealmRules.project_limit(session.state, session.content)
		return result
	var trial := GameSession.new(session.content)
	trial.state = session.state.duplicate(true)
	trial.profile = session.profile.duplicate(true)
	for index in count:
		var error := trial.queue_build(id)
		if error != "":
			result.error = _readable_error(error)
			return result
	var assigned := CabinetRules.reassign(trial.state, trial.content)
	if assigned.blocked:
		result.error = " · ".join(assigned.errors)
		return result
	result.trial = trial
	return result


static func _readable_error(error: String) -> String:
	var message := error.get_slice(" 착공 거부: ", 1) if " 착공 거부: " in error else error
	var names := {"wood":"목재", "stone":"석재", "tools":"도구", "iron":"철", "money":"금고"}
	for asset in names: message = message.replace(asset, names[asset])
	return message


static func _completion(queued: GameSession, id: String, count: int) -> Dictionary:
	var trial: Dictionary = queued.state.duplicate(true)
	var target := int(trial.facilities.get(id, 0)) + count
	var stalled := ""
	for step in ETA_LIMIT:
		if int(trial.week) > GameSession.RUN_WEEKS:
			return {"eta":-1, "text":"회차 종료 전 완공 어려움"}
		var assigned := CabinetRules.reassign(trial, queued.content)
		if assigned.blocked:
			return {"eta":-1, "text":"완공 시기 미정 · " + str(assigned.errors[0])}
		if int(assigned.assign.get("build", 0)) == 0 and stalled == "":
			stalled = "일할 주민이 부족합니다." if int(assigned.available) == 0 else "농사와 우선 작업에 인력을 배치해 공사가 대기합니다."
		var processed := WeekSim.process_week(trial, queued.content)
		if not processed.advanced:
			return {"eta":-1, "text":"완공 시기 미정 · " + str(processed.notes[0])}
		if int(trial.facilities.get(id, 0)) >= target:
			return {"eta":step + 1, "text":"약 %d주" % (step + 1) + (" · " + stalled if stalled != "" else "")}
	return {"eta":-1, "text":"완공 시기 미정 · " + (stalled if stalled != "" else "16주 안에 완공하기 어렵습니다.")}


static func set_advisor(session: GameSession, id: String) -> String:
	if session == null or session.state.is_empty() or session.state.get("status", "") != "active": return "진행 중인 회차가 없습니다."
	if not session.content.chronicle.characters.has(id): return "알 수 없는 보좌관입니다."
	if not CabinetRules.enabled(session.state): return "간편 통치가 켜져 있지 않습니다."
	session.state.cabinet.advisor = id
	return ""


static func advisor_definition(session: GameSession, id: String) -> Dictionary:
	if session == null or not session.content.chronicle.characters.has(id): return {}
	var person: Dictionary = session.content.chronicle.characters[id]
	var amount: float = person.value + (WeekSim.bonus(session.state, "trust", 0) if person.effect == "trust" else 0.0)
	return {"id":id, "name":person.name, "role":person.role, "effect":person.effect, "amount":amount,
		"benefit":"매주 %s +%.0f" % [ADVISOR_EFFECTS.get(person.effect, person.effect), amount]}


static func supplies(session: GameSession) -> Array[Dictionary]:
	var packages: Array[Dictionary] = []
	var active: bool = session != null and not session.state.is_empty() and session.state.get("status", "") == "active"
	for asset in SUPPLIES:
		var quantity: int = int(SUPPLIES[asset].quantity)
		if asset == "food": quantity = clampi(int(ceil(float(session.state.get("pop", 0)) * 2.0)), 1, 200) if session != null else 1
		var price: int = session.trade_quote(asset, quantity, true) if active else -1
		var arrival: int = int(session.state.get("week", 0)) + RealmRules.delivery(session.state) if session != null else 0
		var error := ""
		if not active: error = "진행 중인 회차가 없습니다."
		elif price < 0: error = "현재 가격으로 주문할 수 없습니다."
		elif session.state.shipments.size() >= RealmRules.carts(session.state): error = "교역 수레 %d대가 모두 운행 중입니다." % RealmRules.carts(session.state)
		elif session.state.public.money < price: error = "교역 대금이 부족합니다."
		elif session.state.public.money - float(RealmRules.held(session.state, session.content).money) < price: error = "예약한 공사비를 빼면 대금이 부족합니다."
		packages.append({"asset":asset, "quantity":quantity, "title":SUPPLIES[asset].title, "price":price, "arrival":arrival, "error":error})
	return packages


static func buy_supply(session: GameSession, asset: String) -> String:
	if not SUPPLIES.has(asset): return "알 수 없는 물자입니다."
	for package in supplies(session):
		if package.asset != asset: continue
		if package.error != "": return str(package.error)
		return session.trade(asset, int(package.quantity), true)
	return "진행 중인 회차가 없습니다."


## 이미 결제한 공사의 진행도와 예치금을 보존한 채 첫 작업 대상으로 옮긴다.
static func promote_project(session: GameSession, index: int) -> String:
	return _promote(session, "projects", index)


## 예약끼리 순서를 바꾼다. 착공 전 예약은 진행 중인 공사를 앞지르지 않는다.
static func promote_order(session: GameSession, index: int) -> String:
	return _promote(session, "orders", index)


static func _promote(session: GameSession, key: String, index: int) -> String:
	if session == null or session.state.is_empty() or session.state.get("status", "") != "active":
		return "진행 중인 회차가 없습니다."
	if not RealmRules.enabled(session.state) or not CabinetRules.enabled(session.state):
		return "이 통치에서는 공사 우선순위를 바꿀 수 없습니다."
	var source: Array = session.state.get(key, [])
	if index < 0 or index >= source.size(): return "선택한 공사가 없습니다."
	var trial: Dictionary = session.state.duplicate(true)
	var selected: Variant = trial[key][index]
	trial[key].remove_at(index)
	trial[key].push_front(selected)
	var allocation := CabinetRules.reassign(trial, session.content)
	if allocation.blocked: return " · ".join(allocation.errors)
	# 검증용 복제에서 발생한 예약 결제나 기타 상태는 원본에 옮기지 않는다.
	session.state[key] = trial[key].duplicate(true)
	session.state.assign = trial.assign.duplicate(true)
	return ""


## 경제 엔진의 공사 객체를 추적한다. 같은 시설을 두 번 예약해도 서로 다른 행이다.
## 조회는 원본의 RNG, 예약, 예치금, 저장 상태에 손대지 않는다.
static func project_preview(session: GameSession) -> Dictionary:
	var result := {"rows":[], "build_workers":0, "work_this_week":0, "total_work":0,
		"error":"", "scope":PROJECT_SCOPE}
	if session == null or session.state.is_empty() or session.state.get("status", "") != "active":
		result.error = "진행 중인 회차가 없습니다."
		return result
	var trial: Dictionary = session.state.duplicate(true)
	var content: Dictionary = session.content
	var first_week := int(trial.week)
	var allocation := CabinetRules.reassign(trial, content)
	if allocation.blocked:
		result.error = " · ".join(allocation.errors)
		return result
	var rows: Array = result.rows
	for index in trial.projects.size():
		var project: Dictionary = trial.projects[index]
		project["_preview_index"] = rows.size()
		rows.append(_project_row(content, project, "project", index, rows.size()))
	# process_week가 수행할 착공을 동일한 엔진 함수로 미리 실행해 예약의 작업량도 읽는다.
	# 이후 orders를 비워 중복 결제를 막고 실제 FIFO 작업·효율 계산은 엔진에 맡긴다.
	for index in trial.orders.size():
		var error := WeekSim._start_project(trial, content, str(trial.orders[index]), [])
		if error != "":
			result.error = _readable_error(error)
			result.rows = []
			return result
		var project: Dictionary = trial.projects.back()
		project["_preview_index"] = rows.size()
		rows.append(_project_row(content, project, "order", index, rows.size()))
	trial.orders = []
	for row in rows: result.total_work += int(row.work_left)
	if rows.is_empty(): return result
	for step in ETA_LIMIT:
		if int(trial.week) > GameSession.RUN_WEEKS or int(trial.pop) <= 0: break
		if step > 0:
			RealmRules.refresh(trial, content)
			allocation = CabinetRules.reassign(trial, content)
			if allocation.blocked:
				result.error = " · ".join(allocation.errors)
				break
		var report := WeekSim.process_week(trial, content)
		if not report.advanced:
			result.error = " · ".join(report.notes)
			break
		var remaining := {}
		for project in trial.projects: remaining[int(project._preview_index)] = int(project.work_left)
		if step == 0:
			result.build_workers = int(trial.get("labor_report", {}).get("build", 0))
		for index in rows.size():
			var row: Dictionary = rows[index]
			if step == 0:
				row.remaining_next = int(remaining.get(index, 0))
				row.work_next = int(row.work_left) - int(row.remaining_next)
				result.work_this_week += int(row.work_next)
				row.status = "이번 주 완공" if row.remaining_next == 0 else "이번 주 작업" if row.work_next > 0 else "작업 대기"
			if row.eta < 0 and not remaining.has(index):
				row.eta = step + 1
				row.completion_week = first_week + step
				row.eta_text = "이번 주 완공" if step == 0 else "약 %d주 뒤 완공" % (step + 1)
		if trial.projects.is_empty(): break
	for row in rows:
		if row.work_next == 0:
			row.status = "농사·우선 작업으로 대기" if int(result.build_workers) == 0 else "앞선 공사 뒤에 작업"
		if row.eta >= 0: continue
		if first_week + ETA_LIMIT > GameSession.RUN_WEEKS:
			row.eta_text = "회차 종료 전 완공 어려움"
		else:
			row.eta_text = "완공 시기 미정"
	return result


static func _project_row(content: Dictionary, project: Dictionary, kind: String, index: int, priority: int) -> Dictionary:
	return {"kind":kind, "index":index, "id":str(project.id), "name":str(content.facilities[project.id].name),
		"priority":priority + 1, "work_left":int(project.work_left), "work_total":int(project.work_total),
		"work_next":0, "remaining_next":int(project.work_left), "eta":-1, "eta_text":"완공 시기 미정",
		"completion_week":-1, "can_promote":index > 0, "status":"작업 대기"}
