class_name MandateRules
extends RefCounted
## 왕실 신임. 신임 영주는 시험받는 자리다. 계절 목표나 위기 대비를 놓칠 때마다 신임이 줄고, 바닥나면 통치 중에 해임된다.
## 새 통치에서만 깃발(mandate)로 켠다. 수치는 content/campaign.json의 mandate에 있다.


static func enabled(state: Dictionary) -> bool:
	return state.get("mandate", {}) is Dictionary and state.get("mandate", {}).get("enabled", false) == true


static func setup(state: Dictionary, content: Dictionary, config: Dictionary) -> bool:
	if not bool(config.get("mandate", false)) or state.is_empty() or not CampaignDirector.enabled(state): return false
	if enabled(state): return true
	var start := int(content.campaign.get("mandate", {}).get("start", 3))
	state.mandate = {"enabled":true, "version":1, "value":start, "max":start, "log":[]}
	return true


static func dismissed(state: Dictionary) -> bool:
	return enabled(state) and int(state.mandate.value) <= 0


## 이번 주에 새로 평가된 계절 목표와 위기를 보고 신임을 깎는다. 겨울 결산은 통치가 끝나는 주라 세지 않는다.
static func after_week(before: Dictionary, state: Dictionary, content: Dictionary, report: Dictionary) -> void:
	if not enabled(state) or not bool(report.get("advanced", false)): return
	var rules: Dictionary = content.campaign.get("mandate", {})
	var causes: Array[String] = []
	var lost := 0
	var seasons: Array = state.get("campaign", {}).get("records", [])
	for record in seasons.slice(before.get("campaign", {}).get("records", []).size()):
		if record.success or int(record.index) >= 3: continue
		lost += int(rules.get("season_fail", 1))
		causes.append("%s 목표 미달" % record.season)
	var crises: Array = state.get("escalation", {}).get("records", [])
	for record in crises.slice(before.get("escalation", {}).get("records", []).size()):
		if record.success: continue
		lost += int(rules.get("crisis_fail", 1))
		causes.append("%s 대비 실패" % record.name)
	if lost <= 0: return
	var mandate: Dictionary = state.mandate
	mandate.value = maxi(0, int(mandate.value) - lost)
	var text := "왕실 신임 -%d · %s · 남은 신임 %d" % [lost, " · ".join(causes), mandate.value]
	if int(mandate.value) <= 0: text = "왕실이 영주를 해임했습니다 · " + " · ".join(causes)
	mandate.log.append({"week":int(report.get("week", 0)), "lost":lost, "text":text})
	state.log.append(text)
	report.notes.append(text)


static func valid(state: Dictionary) -> bool:
	if not state.has("mandate"): return true
	var mandate: Variant = state.mandate
	if not mandate is Dictionary or not mandate.get("enabled") is bool or not mandate.get("log") is Array: return false
	for key in ["version", "value", "max"]:
		var number: Variant = mandate.get(key)
		if not (number is int or number is float) or float(number) != floorf(float(number)): return false
	if int(mandate.max) < 1 or int(mandate.max) > 9 or int(mandate.value) < 0 or int(mandate.value) > int(mandate.max): return false
	var total := 0
	for entry in mandate.log:
		if not entry is Dictionary or not entry.get("text") is String or not (entry.get("lost") is int or entry.get("lost") is float) or float(entry.lost) < 1: return false
		total += int(entry.lost)
	return total >= int(mandate.max) - int(mandate.value)
