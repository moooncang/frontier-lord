class_name TurnReceipt
extends RefCounted
## 한 번의 실제 주 진행 전후를 비교한다. 원본·난수·파일을 변경하거나 미래 경제를 실행하지 않는다.

const ASSETS := ["money", "food", "wood", "stone", "tools", "fuel", "iron"]
const LABELS := {"money":"금고", "food":"식량", "wood":"목재", "stone":"석재", "tools":"도구", "fuel":"장작", "iron":"철"}
const SOURCES := {
	"tax":"세금", "wages":"공공 급여", "maintenance":"시설 유지비", "tribute":"공납", "arrears_payment":"미지급 비용 상환",
	"construction":"공사비", "construction_cash":"이번 착공 결제", "harvest":"곡물 수확", "gather":"채집", "garden":"채소 생산",
	"consume":"주민 식량 소비", "spoil":"보관 손실", "seed":"파종 종자", "logging":"벌목", "quarry":"채석", "fuel":"장작 가공", "heating":"난방",
	"trade_arrival":"구매 물자 도착", "trade_sale":"판매 대금 도착", "trade_buy":"물자 구매", "trade_depart":"판매 출하",
	"contract":"계약 보상", "campaign_reward":"계절 목표 보상", "campaign_penalty":"계절 목표 미달", "trial":"겨울 시련",
	"event":"사건 효과", "event_cost":"사건 비용", "crisis_reward":"위기 대비 보상", "crisis_penalty":"위기 피해",
	"fishery":"어장", "smithy":"대장간", "market_fee":"장터 통행세", "rank":"영지 승격 포상",
	"relic:F01":"청동 낫", "relic:F02":"개척자의 바구니", "relic:F03":"밀랍 봉인 항아리", "relic:F04":"순례자의 식기",
	"relic:C01":"석공의 망치", "relic:C02":"장인의 숫돌", "relic:C03":"영주의 측량추", "relic:C04":"장인의 모래시계",
	"relic:G01":"꺼지지 않는 화로", "relic:G02":"은제 약병", "relic:G03":"초소의 청동종", "relic:G04":"겨울 부적",
	"relic:F05":"파종자의 씨앗상자", "relic:F06":"돌절구", "relic:F07":"곡물 계량잔", "relic:F08":"빗물 주전자",
	"relic:C05":"목수의 먹줄", "relic:C06":"대장장이의 풀무", "relic:C07":"상단의 저울", "relic:C08":"톱니 계산기",
	"relic:G05":"순찰대의 등불", "relic:G06":"구휼소의 붕대", "relic:G07":"행군 북", "relic:G08":"눈길 방울"
}
const PRODUCTION := ["harvest", "gather", "garden", "logging", "quarry", "fuel", "fishery", "smithy"]


## 저장된 마지막 완료 주 결과의 구조와 수치 관계를 검사한다. JSON 정수형 실수도 허용한다.
static func valid(receipt: Variant) -> bool:
	if not receipt is Dictionary: return false
	if not _integer(receipt.get("version")) or int(receipt.version) != 1: return false
	if receipt.get("valid") != true or not receipt.get("valid") is bool: return false
	if not _integer(receipt.get("week")) or receipt.week < 1 or receipt.week > 52: return false
	for key in ["scope", "reason"]:
		if not receipt.get(key) is String: return false
	if not receipt.get("resource_rows") is Array or receipt.resource_rows.size() != ASSETS.size(): return false
	var found: Array = []
	for row in receipt.resource_rows:
		if not row is Dictionary or not row.get("id") is String or row.id not in ASSETS or row.id in found: return false
		found.append(row.id)
		for key in ["label", "unit", "scope"]:
			if not row.get(key) is String: return false
		for key in ["before", "after", "income", "expense", "production", "consumption", "spoilage", "seeds"]:
			if not _number(row.get(key)) or row[key] < 0: return false
		for key in ["delta", "construction", "ledger_net", "explained_delta", "unclassified_delta"]:
			if not _number(row.get(key)): return false
		if not row.get("fully_explained") is bool or not row.get("by_source") is Dictionary or not row.get("flows") is Array: return false
		for source in row.by_source:
			if not source is String or not _number(row.by_source[source]): return false
		for flow in row.flows:
			if not flow is Dictionary or not flow.get("source") is String or not flow.get("label") is String or not _number(flow.get("amount")): return false
		if not _close(float(row.after) - float(row.before), float(row.delta)): return false
		if not _close(float(row.income) - float(row.expense), float(row.explained_delta)): return false
		if not _close(float(row.explained_delta) + float(row.unclassified_delta), float(row.delta)): return false
		if row.fully_explained and not _close(float(row.unclassified_delta), 0): return false
	var development = receipt.get("development")
	if not development is Dictionary: return false
	for key in ["started", "completed"]:
		if not development.get(key) is Array: return false
		for item in development[key]:
			if not item is Dictionary or not item.get("id") is String or item.id.is_empty() or not _integer(item.get("count")) or item.count < 1: return false
	for key in ["work_done", "actual_workers", "remaining_work", "queued_remaining"]:
		if not _integer(development.get(key)) or development[key] < 0: return false
	for key in ["cash_paid", "recognized_cost", "escrow_before", "escrow_after"]:
		if not _number(development.get(key)): return false
	if development.escrow_before < 0 or development.escrow_after < 0: return false
	if not development.get("work_known") is bool or development.get("status") not in ["idle", "building", "completed"]: return false
	if not _close(float(development.recognized_cost) + float(development.escrow_after) - float(development.escrow_before), float(development.cash_paid)): return false
	var advisor = receipt.get("advisor")
	if not advisor is Dictionary: return false
	for key in ["id", "name", "effect", "label", "reason"]:
		if not advisor.get(key) is String: return false
	if not advisor.get("acted") is bool or not advisor.get("amount_known") is bool or not _number(advisor.get("amount")): return false
	if not receipt.get("notes") is Array: return false
	for line in receipt.notes:
		if not line is String: return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))


static func _close(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


static func build(before: Dictionary, after: Dictionary, report: Dictionary) -> Dictionary:
	var week := int(report.get("week", before.get("week", 0)))
	var result := {"version":1, "week":week, "valid":false, "scope":"한 주 진행 버튼을 누르기 직전부터 처리가 끝날 때까지의 실제 변화",
		"resource_rows":[], "development":{}, "advisor":{}, "notes":[], "reason":""}
	if not bool(report.get("advanced", false)) or int(before.get("week", 0)) != week or int(after.get("week", 0)) != week + 1:
		result.reason = "완료된 한 주의 전후 기록이 아닙니다."
		result.notes = _notes(report.get("notes", []))
		return result
	if str(before.get("run_id", "")) != str(after.get("run_id", "")):
		result.reason = "서로 다른 통치의 기록입니다."
		return result
	var previous: Array = before.get("ledger", [])
	var current: Array = after.get("ledger", [])
	if current.size() < previous.size() or current.slice(0, previous.size()) != previous:
		result.reason = "주 진행 전후의 원장이 연결되지 않습니다."
		return result
	# w 번호로 거르지 않는다. 도착·시련은 다음 주 번호로 기록되어도 이번 advance의 실제 결과다.
	var entries := current.slice(previous.size())
	var development := _development(before, after, entries)
	for asset in ASSETS:
		result.resource_rows.append(_resource(before, after, entries, asset, development))
	result.development = development
	result.advisor = _advisor(before, after, report, week)
	result.notes = _notes(report.get("notes", []))
	result.valid = true
	return result


static func _balance(state: Dictionary, asset: String) -> float:
	var value := float(state.get("public", {}).get(asset, 0))
	if asset == "food": value += float(state.get("resident", {}).get(asset, 0))
	return value


static func _resource(before: Dictionary, after: Dictionary, entries: Array, asset: String, development: Dictionary) -> Dictionary:
	var row := {"id":asset, "label":LABELS[asset], "unit":"동" if asset == "money" else "개",
		"scope":"공공·주민 합계" if asset == "food" else "공공 재고", "before":_balance(before, asset), "after":_balance(after, asset),
		"delta":_balance(after, asset) - _balance(before, asset), "income":0.0, "expense":0.0, "production":0.0, "consumption":0.0,
		"spoilage":0.0, "seeds":0.0, "construction":0.0, "ledger_net":0.0, "explained_delta":0.0,
		"unclassified_delta":0.0, "fully_explained":false, "by_source":{}, "flows":[]}
	for entry in entries:
		if str(entry.get("asset", "")) != asset or str(entry.get("src", "")) == "transfer": continue
		var source := str(entry.src)
		var amount := float(entry.qty)
		row.ledger_net += amount
		row.by_source[source] = float(row.by_source.get(source, 0)) + amount
		if asset != "money" or source != "construction":
			if amount >= 0: row.income += amount
			else: row.expense -= amount
		if (source in PRODUCTION or source.begins_with("fantasy:")) and amount > 0: row.production += amount
		if source == "consume" or source == "heating" or ((source in ["logging", "quarry", "fuel", "smithy"] or source.begins_with("fantasy:")) and amount < 0): row.consumption += maxf(0, -amount)
		if source == "spoil": row.spoilage += maxf(0, -amount)
		if source == "seed": row.seeds += maxf(0, -amount)
	if asset == "money":
		# 공사 진행 원장은 이미 예치한 금액을 비용으로 인식한다. 이번 금고 지출로 다시 세지 않는다.
		row.by_source.erase("construction")
		if not is_zero_approx(float(development.cash_paid)):
			row.by_source["construction_cash"] = -float(development.cash_paid)
		row.construction = float(development.cash_paid)
		if float(development.cash_paid) >= 0: row.expense += float(development.cash_paid)
		else: row.income -= float(development.cash_paid)
	for source in row.by_source:
		var amount: float = row.by_source[source]
		row.explained_delta += amount
		if not is_zero_approx(amount): row.flows.append({"source":source, "label":source_label(str(source)), "amount":amount})
	row.unclassified_delta = float(row.delta) - float(row.explained_delta)
	row.fully_explained = absf(float(row.unclassified_delta)) < 0.00001
	if row.fully_explained: row.unclassified_delta = 0.0
	# 재료처럼 원장에 없는 변화는 다른 생산·지출이라고 추측하지 않고 별도로 남긴다.
	return row


static func source_label(source: String) -> String:
	if source.begins_with("fantasy:"): return FantasyFrontiers.facility_label(source.trim_prefix("fantasy:"))
	if source.begins_with("fantasy_reward:"): return "이계 협약 완성 · " + FantasyFrontiers.path_label(source.trim_prefix("fantasy_reward:"))
	if source.begins_with("support:"):
		var definition: Dictionary = SeasonalInvestments.definitions().definitions.get(source.trim_prefix("support:"), {})
		return "계절 지원 · " + str(definition.get("name", source.trim_prefix("support:")))
	if source.begins_with("build:"):
		var definition: Dictionary = OperatingBuilds.definitions().builds.get(source.trim_prefix("build:"), {})
		return "운영 조합 · " + str(definition.get("name", source.trim_prefix("build:")))
	if source.begins_with("relic:"):
		var definition: Dictionary = VillageRelics.definitions().relics.get(source.trim_prefix("relic:"), {})
		if not definition.is_empty(): return str(definition.name)
	return str(SOURCES.get(source, source))


static func _development(before: Dictionary, after: Dictionary, entries: Array) -> Dictionary:
	var recognized := 0.0
	for entry in entries:
		if entry.get("src", "") == "construction" and entry.get("asset", "") == "money": recognized -= float(entry.qty)
	var escrow_before := _project_sum(before, "escrow")
	var escrow_after := _project_sum(after, "escrow")
	var started_counts := {}
	for id in before.get("orders", []): started_counts[id] = int(started_counts.get(id, 0)) + 1
	for id in after.get("orders", []): started_counts[id] = maxi(0, int(started_counts.get(id, 0)) - 1)
	var started: Array[Dictionary] = []
	var completed: Array[Dictionary] = []
	var possible := started_counts.duplicate()
	for project in before.get("projects", []): possible[project.id] = int(possible.get(project.id, 0)) + 1
	for id in started_counts:
		if started_counts[id] > 0: started.append({"id":id, "count":int(started_counts[id])})
	for id in possible:
		var gained := int(after.get("facilities", {}).get(id, 0)) - int(before.get("facilities", {}).get(id, 0))
		var built := mini(maxi(0, gained), int(possible[id]))
		if built > 0: completed.append({"id":id, "count":built})
	var remaining := int(_project_sum(after, "work_left"))
	var workers := int(after.get("labor_report", {}).get("build", 0))
	var work_known: bool = after.get("labor_report", {}).has("build")
	var work_done := 0
	if before.get("orders", []).is_empty():
		work_done = maxi(0, int(_project_sum(before, "work_left")) - remaining)
		work_known = true
	elif work_known:
		# WeekSim 기록의 실제 건설 배치에, 같은 처리 주의 미지급 효율을 적용한다.
		var unpaid := int(before.get("unpaid_weeks", 0))
		var efficiency := 0.5 if unpaid >= 8 else (0.75 if unpaid >= 4 else 1.0)
		work_done = int(floor(workers * efficiency))
	return {"started":started, "completed":completed, "work_done":work_done, "work_known":work_known,
		"actual_workers":workers, "remaining_work":remaining, "queued_remaining":after.get("orders", []).size(),
		"cash_paid":recognized + escrow_after - escrow_before, "recognized_cost":recognized,
		"escrow_before":escrow_before, "escrow_after":escrow_after,
		"status":"building" if remaining > 0 else ("completed" if not completed.is_empty() else "idle")}


static func _project_sum(state: Dictionary, key: String) -> float:
	var total := 0.0
	for project in state.get("projects", []): total += float(project.get(key, 0))
	return total


static func _advisor(before: Dictionary, after: Dictionary, report: Dictionary, week: int) -> Dictionary:
	var cabinet: Dictionary = before.get("cabinet", {})
	var id := str(cabinet.get("advisor", ""))
	var result := {"id":id, "name":id, "acted":false, "amount_known":false, "effect":"", "label":"", "amount":0.0, "reason":""}
	if not bool(cabinet.get("enabled", false)) or id.is_empty():
		result.reason = "자동 보좌관을 사용하지 않습니다."
		return result
	result.acted = int(after.get("cabinet", {}).get("advisor_week", 0)) == week and int(cabinet.get("advisor_week", 0)) != week
	if not result.acted:
		result.reason = "이번 주에 이미 활동했습니다." if int(cabinet.get("advisor_week", 0)) == week or "council_" + id in before.get("actions_used", []) else "이번 주에 보좌관 활동이 없었습니다."
		return result
	var definition: Dictionary = report.get("receipt_context", {}).get("advisor", {})
	if str(definition.get("id", "")) != id or not definition.has("effect") or not definition.has("amount"):
		result.reason = "활동 완료 · 개별 효과 기록 없음"
		return result
	var effect := str(definition.effect)
	if not before.has(effect): return result
	result.name = str(definition.get("name", id))
	result.effect = effect
	result.label = CabinetActions.ADVISOR_EFFECTS.get(effect, effect)
	result.amount = minf(100.0, float(before[effect]) + float(definition.amount)) - float(before[effect])
	result.amount_known = true
	result.reason = "상한에 도달해 추가 변화 없음" if is_zero_approx(float(result.amount)) else "한 주 진행 중 한 번 활동"
	return result


static func _notes(items: Array) -> Array[String]:
	var priority: Array[String] = []
	var finished: Array[String] = []
	var arrivals: Array[String] = []
	var rest: Array[String] = []
	var seen: Array[String] = []
	for item in items:
		var line := str(item)
		if line.is_empty() or line in seen: continue
		seen.append(line)
		if "목표" in line or "시련" in line or "미납" in line or "부족" in line:
			priority.append(line)
		elif "완공" in line: finished.append(line)
		elif "도착" in line: arrivals.append(line)
		else: rest.append(line)
	priority.append_array(finished)
	priority.append_array(arrivals)
	priority.append_array(rest)
	return priority
