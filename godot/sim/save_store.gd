class_name SaveStore
extends RefCounted
## 두 세대 슬롯 + 체크섬. 메타와 회차는 같은 파일의 단일 스냅숏이다.

var directory: String
var sequence := 0


func _init(path: String = "user://saves") -> void:
	directory = path


func write(bundle: Dictionary) -> String:
	if not valid(bundle):
		return "저장할 상태의 형식이 올바르지 않습니다."
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return "저장 폴더를 만들지 못했습니다 (%d)." % error
	var next := sequence + 1
	var payload := JSON.stringify(bundle)
	var envelope := {"version": 1, "sequence": next, "payload": payload, "checksum": payload.sha256_text()}
	var slot := directory.path_join("slot_%d.json" % (next % 2))
	var temporary := slot + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "저장 파일을 쓸 수 없습니다."
	file.store_string(JSON.stringify(envelope))
	file.flush()
	file.close()
	if _read_envelope(temporary).is_empty():
		return "저장 검증에 실패했습니다. 이전 기록은 보존되었습니다."
	# 다른 슬롯의 직전 스냅숏은 교체 중에도 남아 있다.
	if FileAccess.file_exists(slot):
		error = DirAccess.remove_absolute(slot)
		if error != OK:
			return "오래된 저장 슬롯을 교체하지 못했습니다."
	error = DirAccess.rename_absolute(temporary, slot)
	if error != OK:
		return "저장 파일을 확정하지 못했습니다 (%d)." % error
	sequence = next
	return ""


func read() -> Dictionary:
	var best: Dictionary = {}
	var found := false
	var invalid := false
	for i in 2:
		var path := directory.path_join("slot_%d.json" % i)
		if not FileAccess.file_exists(path):
			continue
		found = true
		var candidate := _read_envelope(path)
		if candidate.is_empty():
			invalid = true
		elif best.is_empty() or int(candidate.sequence) > int(best.sequence):
			best = candidate
	if best.is_empty():
		return {"ok": false, "error": "저장이 손상되었습니다. 자동으로 덮어쓰지 않습니다." if found else "", "found": found}
	sequence = int(best.sequence)
	return {"ok": true, "bundle": _normalize(JSON.parse_string(best.payload)), "recovered": invalid}


func _read_envelope(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var envelope = parser.data
	if not envelope is Dictionary or envelope.get("version", 0) != 1 or not envelope.get("payload") is String or not envelope.get("sequence") is float and not envelope.get("sequence") is int:
		return {}
	if envelope.payload.sha256_text() != envelope.get("checksum", ""):
		return {}
	if parser.parse(envelope.payload) != OK:
		return {}
	var parsed = parser.data
	if not valid(parsed):
		return {}
	return envelope


static func valid(bundle: Variant) -> bool:
	if not bundle is Dictionary or bundle.get("version", 0) != 1:
		return false
	var profile = bundle.get("profile")
	var state = bundle.get("state")
	if not profile is Dictionary or not state is Dictionary:
		return false
	if not profile.get("upgrades") is Array or not profile.get("receipts") is Dictionary:
		return false
	if not _nonnegative(profile.get("points")) or not _nonnegative(profile.get("runs")):
		return false
	if not LegacyPath.valid(profile): return false
	for receipt in profile.receipts.values():
		if receipt is Dictionary and not FrontierDifficulty.receipt_valid(receipt): return false
	var definitions := Content.load_all()
	if not VillageRelics.profile_valid(profile, definitions): return false
	for id in profile.upgrades:
		if not id is String or not definitions.progression.upgrades.has(id):
			return false
	if profile.has("discoveries"):
		if not profile.discoveries is Array: return false
		for id in profile.discoveries:
			if not definitions.progression.perks.has(id): return false
	if profile.has("chronicles"):
		if not profile.chronicles is Array: return false
		for item in profile.chronicles:
			if not item is Dictionary or not definitions.chronicle.regions.has(item.get("region", "")) or not item.get("perks") is Array or not item.get("reason") is String or not item.get("success") is bool: return false
			for key in ["seed", "week", "points"]:
				if not _nonnegative(item.get(key)): return false
	if profile.has("tutorial_done") and not profile.tutorial_done is bool: return false
	if profile.has("onboarding_complete") and not profile.onboarding_complete is bool: return false
	if state.is_empty():
		return true
	if state.has("legacy_snapshot"):
		if not LegacyPath.valid({"legacy_talents": state.legacy_snapshot}): return false
	if not LegacyPath.state_valid(state, definitions): return false
	if not CampaignDirector.valid(state, definitions): return false
	if not ExpeditionModifiers.valid(state, definitions): return false
	if not Onboarding.valid(state) or not WorkcrewRules.valid(state): return false
	if not RealmRules.valid(state, definitions): return false
	if not MandateRules.valid(state): return false
	if not PeopleRules.valid(state, definitions): return false
	if not VillageRelics.valid(state, definitions): return false
	if not CrisisDirector.valid(state, definitions): return false
	if not FrontierDifficulty.valid(state, definitions) or not SeasonalInvestments.valid(state, definitions): return false
	if not FantasyFrontiers.valid(state,definitions): return false
	if state.has("last_receipt") and not TurnReceipt.valid(state.last_receipt): return false
	if state.has("chronicle"):
		if not state.chronicle is bool: return false
		if state.chronicle and not _valid_chronicle(state, definitions): return false
	if state.has("cabinet"):
		var cabinet = state.cabinet
		if not cabinet is Dictionary or not cabinet.get("enabled") is bool: return false
		if cabinet.get("focus", "") not in ["balanced", "food", "build", "winter"]: return false
		if not definitions.chronicle.characters.has(cabinet.get("advisor", "")): return false
		if cabinet.has("advisor_week") and not _nonnegative(cabinet.advisor_week): return false
		if cabinet.has("project"):
			var project = cabinet.project
			if not project is Dictionary or not definitions.facilities.has(project.get("id","")): return false
			for key in ["count","start_count","total_work"]:
				if not _nonnegative(project.get(key)): return false
	for key in ["public", "resident", "facilities", "assign", "bonuses", "goals", "result"]:
		if not state.get(key) is Dictionary:
			return false
	for key in ["projects", "orders", "shipments", "perks", "perk_offer", "seen_events", "history", "ledger", "log", "meta_snapshot", "actions_used"]:
		if not state.get(key) is Array:
			return false
	if not state.get("run_id") is String or state.get("status", "") not in ["active", "finalized"]:
		return false
	if not _nonnegative(state.get("week")) or state.week < 1 or not _nonnegative(state.get("pop")):
		return false
	for key in ["seed", "labor_ratio", "soil", "weather", "mood", "health", "security", "ration", "plots_sown", "sow_f_sum", "food_satisfaction", "famine_weeks", "birth_rate", "death_rate", "birth_res", "death_res", "money_res", "arrears_wage", "arrears_tax", "tax_year", "prev_year_tax", "tribute_exempt_years", "drafts", "refreshes", "village", "guild", "trust", "actions", "trade_discount"]:
		if not _nonnegative(state.get(key)):
			return false
	if float(state.ration) not in [1.0, 0.9, 0.75] or state.labor_ratio > 1 or state.trade_discount > 0.5:
		return false
	if not definitions.progression.origins.has(state.get("origin", "")) or not state.get("active_event") is String:
		return false
	if state.active_event != "" and not definitions.events.has(state.active_event):
		return false
	for id in state.facilities:
		if not definitions.facilities.has(id) or not _nonnegative(state.facilities[id]):
			return false
	for id in state.orders:
		if not definitions.facilities.has(id):
			return false
	for id in state.perks + state.perk_offer:
		if not definitions.progression.perks.has(id):
			return false
	for id in state.seen_events:
		if not definitions.events.has(id):
			return false
	for key in state.assign:
		if not _nonnegative(state.assign[key]):
			return false
	for key in state.bonuses:
		var value: Variant = state.bonuses[key]
		# 복합 특전의 세율·접견 가산 대가는 음수일 수 있다. 생산 배율은 기존 음수 금지를 유지한다.
		if key in ["tax", "trust"]:
			if not (value is int or value is float) or not is_finite(float(value)): return false
		elif not _nonnegative(value):
			return false
	for project in state.projects:
		if not project is Dictionary or not definitions.facilities.has(project.get("id", "")):
			return false
		for key in ["work_left", "work_total", "escrow"]:
			if not _nonnegative(project.get(key)):
				return false
		if project.work_total <= 0 or project.work_left > project.work_total:
			return false
	for shipment in state.shipments:
		if not shipment is Dictionary or not GameSession.RESOURCE_PRICES.has(shipment.get("asset", "")) or not shipment.get("buy") is bool:
			return false
		for key in ["quantity", "money", "arrival"]:
			if not _nonnegative(shipment.get(key)):
				return false
	for item in state.history:
		if not item is Dictionary or not item.get("notes") is Array:
			return false
		for key in ["week", "money", "food", "pop"]:
			if not _nonnegative(item.get(key)):
				return false
	for entry in state.ledger:
		if not entry is Dictionary or not entry.get("src") is String or not entry.get("asset") is String or not _nonnegative(entry.get("w")):
			return false
		if not (entry.get("qty") is float or entry.get("qty") is int):
			return false
		if entry.src == "transfer" and (not _nonnegative(entry.get("amount")) or not entry.get("from") is String or not entry.get("to") is String):
			return false
	for goal in state.goals.values():
		if not goal is Dictionary or not goal.get("title") is String or not goal.get("detail") is String or not goal.get("done") is bool:
			return false
	if state.status == "finalized":
		if not FrontierDifficulty.receipt_valid(state.result): return false
		if not state.result.get("reason") is String or not state.result.get("success") is bool:
			return false
		for key in ["week", "objectives", "objective_points", "completion_points", "first_points", "points"]:
			if not _nonnegative(state.result.get(key)):
				return false
	for account in ["public", "resident"]:
		for key in (["money", "food", "wood", "stone", "tools", "fuel", "iron"] if account == "public" else ["money", "food"]):
			if not state[account].has(key):
				return false
		for value in state[account].values():
			if not _nonnegative(value):
				return false
	return true


static func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= -0.000001


static func _valid_chronicle(s: Dictionary, c: Dictionary) -> bool:
	if not c.chronicle.regions.has(s.get("region", "")) or not c.chronicle.trials.has(s.get("trial", "")): return false
	if not s.get("trial_started") is bool or not s.get("contract") is Dictionary or not s.get("tutorial") is Dictionary: return false
	if not s.tutorial.get("enabled") is bool or not _nonnegative(s.tutorial.get("step")) or s.tutorial.step > 7: return false
	for pair in [["traits", c.chronicle.traits], ["relics", c.chronicle.relics], ["contract_offer", c.chronicle.missions], ["council_visits", c.chronicle.characters]]:
		if not s.get(pair[0]) is Array: return false
		for id in s[pair[0]]:
			if not id is String or not pair[1].has(id): return false
	if not s.get("synergies") is Array or not s.get("contract_results") is Array: return false
	for id in s.synergies:
		if not id is String: return false
		var parts: PackedStringArray = id.split(":")
		if parts.size() != 2 or not c.chronicle.families.has(parts[0]) or parts[1] not in ["2", "4"]: return false
	if not s.contract.is_empty():
		if not c.chronicle.missions.has(s.contract.get("id", "")) or not _nonnegative(s.contract.get("deadline")): return false
	for result in s.contract_results:
		if not result is Dictionary or not c.chronicle.missions.has(result.get("id", "")) or not result.get("passed") is bool or not _nonnegative(result.get("week")): return false
	return true


static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize(item))
		return result
	if value is float and value == floor(value):
		return int(value)
	return value
