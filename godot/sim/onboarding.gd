class_name Onboarding
extends RefCounted
## 실제 플레이 상태를 읽는 안내. 변경하는 필드는 state.onboarding뿐이다.

const TOTAL := 6
const FIELDS := ["version", "enabled", "skipped", "step", "started_week", "project_week", "reviewed_week"]
const TITLES := ["첫 특전 고르기", "농지 개발 승인", "한 주 진행", "운영 결과 확인", "농지 완공", "다음 운영 선택"]
const BODIES := [
	"마음에 드는 특전을 하나 골라 이번 통치의 장점을 정하세요.",
	"농지 개발을 승인하세요. 비용은 다음 주 착공 때 지불합니다.",
	"한 주를 진행하면 배치된 인력이 공사하고 생활비와 식량을 사용합니다.",
	"이번 주 상세 결과를 열고 비용과 식량 변화를 확인한 뒤 닫으세요.",
	"한 주씩 진행하여 농지 6구획을 완성하세요.",
	"운영 방침을 고르거나 다음에 개발할 시설을 선택하세요."
]
const TARGETS := ["PerkChoicesArea", "FocusAction", "NextWeek", "TurnDetails", "NextWeek", "PolicyChoices"]
const ACTIONS := ["특전 선택", "농지 개발 승인", "한 주 진행", "상세 결과 확인", "한 주 진행", "운영 방침 선택"]


static func setup(state: Dictionary, enabled: bool = true) -> Dictionary:
	if state.is_empty(): return current(state)
	# 저장을 읽거나 화면을 다시 열어도 기존 진행과 건너뛰기 선택을 덮어쓰지 않는다.
	if not state.has("onboarding"):
		state.onboarding = _fresh(state, enabled)
	return sync(state)


static func _fresh(state: Dictionary, enabled: bool) -> Dictionary:
	return {"version":1, "enabled":enabled, "skipped":false, "step":0,
		"started_week":maxi(1, int(state.get("week", 1))), "project_week":0, "reviewed_week":0}


static func sync(state: Dictionary) -> Dictionary:
	if not _active(state): return current(state)
	var progress: Dictionary = state.onboarding
	# 여러 사실이 이미 성립한 기존 회차를 인정하되 결과 확인과 마지막 선택은 건너뛰지 않는다.
	for iteration in TOTAL:
		var previous := int(progress.step)
		match previous:
			0:
				if state.get("perk_offer", []).is_empty() and (not state.get("perks", []).is_empty() or not bool(state.get("chronicle", false))):
					progress.step = 1
			1:
				if _farm_project(state) or _farms(state) >= 6:
					progress.project_week = _project_week(state, int(progress.started_week))
					progress.step = 2
			2:
				if _receipt_week(state) >= int(progress.project_week): progress.step = 3
			4:
				if _farms(state) >= 6 and int(state.get("week", 1)) > int(progress.project_week): progress.step = 5
		if int(progress.step) == previous: break
	return current(state)


static func acknowledge(state: Dictionary, event: String) -> bool:
	sync(state)
	if not _active(state): return false
	var progress: Dictionary = state.onboarding
	if int(progress.step) == 3 and event == "turn_details_closed":
		var week := _receipt_week(state)
		if week < int(progress.project_week): return false
		progress.reviewed_week = week
		progress.step = 4
		sync(state)
		return true
	if int(progress.step) == 5 and event in ["next_development", "policy_selected"]:
		progress.step = TOTAL
		return true
	return false


static func skip(state: Dictionary) -> Dictionary:
	if state.has("onboarding") and valid(state): state.onboarding.skipped = true
	return current(state)


static func resume(state: Dictionary) -> Dictionary:
	if not state.has("onboarding"): return setup(state)
	if valid(state):
		state.onboarding.enabled = true
		state.onboarding.skipped = false
	return sync(state)


static func restart(state: Dictionary) -> Dictionary:
	if state.is_empty(): return current(state)
	state.onboarding = _fresh(state, true)
	return sync(state)


static func current(state: Dictionary) -> Dictionary:
	var result := {"enabled":false, "active":false, "completed":false, "skipped":false,
		"step":0, "total":TOTAL, "title":"", "body":"", "target_id":"", "action":"", "event":"", "error":""}
	if not state.has("onboarding"): return result
	if not valid(state):
		result.error = "안내 진행 기록을 읽을 수 없습니다."
		return result
	var progress: Dictionary = state.onboarding
	result.enabled = progress.enabled
	result.skipped = progress.skipped
	result.step = int(progress.step)
	result.completed = int(progress.step) == TOTAL
	result.active = _active(state)
	if result.completed:
		result.title = "기본 운영을 익혔습니다"
		result.body = "개발과 운영 방침을 선택하고, 한 주 진행 뒤 결과를 확인하세요."
		return result
	var step := int(progress.step)
	result.title = TITLES[step]
	result.body = BODIES[step]
	result.target_id = TARGETS[step]
	result.action = ACTIONS[step]
	result.event = "turn_details_closed" if step == 3 else "policy_selected" if step == 5 else ""
	if step == 1 and (not state.get("orders", []).is_empty() or not state.get("projects", []).is_empty()) and not _farm_project(state):
		result.title = "진행 중인 공사 마치기"
		result.body = "현재 공사를 마친 뒤 농지 개발을 승인하세요."
		result.target_id = "NextWeek"
		result.action = "한 주 진행"
	# 재학습 시 이미 완성한 농지를 다시 짓도록 요구하지 않는다.
	if step == 2 and _farms(state) >= 6 and not _farm_project(state):
		result.body = "한 주를 진행하여 현재 영지의 수입과 지출을 확인하세요."
	return result


static func valid(state: Dictionary) -> bool:
	if not state.has("onboarding"): return true
	var progress: Variant = state.onboarding
	if not progress is Dictionary or progress.size() != FIELDS.size(): return false
	for key in FIELDS:
		if not progress.has(key): return false
	if not _integer(progress.version) or int(progress.version) != 1: return false
	if not progress.enabled is bool or not progress.skipped is bool: return false
	for key in ["step", "started_week", "project_week", "reviewed_week"]:
		if not _integer(progress[key]) or progress[key] < 0: return false
	if not _integer(state.get("week")) or state.week < 1: return false
	if progress.step > TOTAL or progress.started_week < 1 or progress.started_week > state.week: return false
	if progress.step < 2:
		if progress.project_week != 0 or progress.reviewed_week != 0: return false
	else:
		if progress.project_week < progress.started_week or progress.project_week > state.week: return false
		if progress.step < 4:
			if progress.reviewed_week != 0: return false
		elif progress.reviewed_week < progress.project_week or progress.reviewed_week >= state.week: return false
	return true


static func _active(state: Dictionary) -> bool:
	if not state.has("onboarding") or not valid(state): return false
	var progress: Dictionary = state.onboarding
	return progress.enabled and not progress.skipped and int(progress.step) < TOTAL and state.get("status", "active") == "active"


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func _farms(state: Dictionary) -> int:
	return int(state.get("facilities", {}).get("B13", 0))


static func _farm_project(state: Dictionary) -> bool:
	if "B13" in state.get("orders", []): return true
	for project in state.get("projects", []):
		if project is Dictionary and project.get("id", "") == "B13": return true
	return false


static func _receipt_week(state: Dictionary) -> int:
	var receipt: Variant = state.get("last_receipt", {})
	if not receipt is Dictionary or not receipt.get("valid") is bool or receipt.get("valid") != true: return -1
	if not _integer(receipt.get("week")) or receipt.week < 1: return -1
	return int(receipt.week) if int(receipt.week) == int(state.get("week", 1)) - 1 else -1


static func _project_week(state: Dictionary, started_week: int) -> int:
	if "B13" in state.get("orders", []): return maxi(started_week, int(state.week))
	var receipt_week := _receipt_week(state)
	# 공사가 안내를 건너뛴 사이에 끝났어도 마지막 실제 진행 주의 결과를 확인할 수 있다.
	if receipt_week >= started_week: return receipt_week
	return maxi(started_week, int(state.week))
