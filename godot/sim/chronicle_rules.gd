class_name ChronicleRules
extends RefCounted
## 회차 변형은 기존 경제 엔진에 명시적인 보너스와 계약으로 연결한다.

const DRAFT_WEEKS := [6, 13, 20, 26, 33, 39, 46]
const ADDITIVE := ["tax", "trust", "winter_gather"]

static func active(s: Dictionary) -> bool:
	return s.get("chronicle", false)

static func candidates(data: Dictionary, run_seed: int) -> Array:
	var good: Array = []
	var bad: Array = []
	for id in data.traits:
		if data.traits[id].get("flaw", false): bad.append(id)
		else: good.append(id)
	good.sort()
	bad.sort()
	var rng := Xoshiro128.new(run_seed, 21)
	var out: Array = []
	for i in 3:
		var pool := good.duplicate()
		var traits: Array = []
		for j in 2:
			var index := rng.randi_range(0, pool.size() - 1)
			traits.append(pool.pop_at(index))
		traits.append(bad[rng.randi_range(0, bad.size() - 1)])
		out.append({"origin": ["settler", "steward", "grower"][i], "traits": traits})
	return out

static func trial_for(data: Dictionary, run_seed: int) -> String:
	var ids: Array = data.trials.keys()
	ids.sort()
	return ids[Xoshiro128.new(run_seed, 22).randi_range(0, ids.size() - 1)]

static func apply_bonuses(s: Dictionary, effects: Dictionary) -> void:
	for key in effects:
		if key in ADDITIVE:
			s.bonuses[key] = WeekSim.raw_bonus(s, key, 0) + effects[key]
		else:
			s.bonuses[key] = WeekSim.raw_bonus(s, key) * effects[key]

static func setup(c: Dictionary, s: Dictionary, profile: Dictionary, config: Dictionary) -> void:
	var data: Dictionary = c.chronicle
	s.chronicle = true
	s.region = str(config.get("region", "forest"))
	if not data.regions.has(s.region): s.region = "forest"
	s.traits = candidates(data, int(s.seed))[clampi(int(config.get("candidate", 0)), 0, 2)].traits
	s.relics = []
	var budget := LegacyPath.equipment_budget(profile)
	for id in config.get("relics", []):
		if not data.relics.has(id) or id in s.relics: continue
		var relic: Dictionary = data.relics[id]
		if int(relic.cost) > budget: continue
		budget -= int(relic.cost)
		s.relics.append(id)
		_apply_setup(s, relic)
	_apply_setup(s, data.regions[s.region])
	for id in s.traits: _apply_setup(s, data.traits[id])
	if "M21" in profile.upgrades: s.refreshes += 1
	s.synergies = []
	s.trial = trial_for(data, int(s.seed))
	s.trial_started = false
	s.contract_offer = []
	s.contract = {}
	s.contract_results = []
	s.tutorial = {"enabled": bool(config.get("tutorial", not profile.get("tutorial_done", false))), "step": 0}
	s.council_visits = []
	if not profile.has("discoveries"): profile.discoveries = []
	if not profile.has("chronicles"): profile.chronicles = []

static func _apply_setup(s: Dictionary, setup_data: Dictionary) -> void:
	apply_bonuses(s, setup_data.get("bonuses", {}))
	for key in setup_data.get("resources", {}):
		s.public[key] += setup_data.resources[key]
	s.refreshes += int(setup_data.get("refreshes", 0))

static func family_counts(c: Dictionary, s: Dictionary) -> Dictionary:
	var counts := {}
	for id in c.chronicle.families: counts[id] = 0
	for id in s.get("perks", []):
		var family: String = c.progression.perks[id].get("family", "")
		if counts.has(family): counts[family] += 1
	return counts

static func unlock_synergies(c: Dictionary, s: Dictionary) -> void:
	if not active(s): return
	var counts := family_counts(c, s)
	for family in counts:
		for tier in [2, 4]:
			var key := "%s:%d" % [family, tier]
			if counts[family] < tier or key in s.synergies: continue
			apply_bonuses(s, c.chronicle.families[family].tiers[str(tier)])
			s.synergies.append(key)
			s.log.append("조합 발동 · %s %d단계" % [c.chronicle.families[family].name, tier])

static func value(s: Dictionary, target: String) -> float:
	match target:
		"farms": return float(s.facilities.get("B13", 0))
		"food_weeks": return WeekSim.food_weeks(s)
		"money", "wood": return float(s.public[target])
	return float(s.get(target, 0))

static func after_week(c: Dictionary, s: Dictionary, report: Dictionary) -> void:
	if not active(s): return
	if int(report.week) in [13, 26, 39, 52] and not s.contract.is_empty():
		var mission: Dictionary = c.chronicle.missions[s.contract.id]
		var passed: bool = value(s, mission.target) >= mission.threshold
		if passed:
			for key in mission.reward:
				s.public[key] += mission.reward[key]
				WeekSim._ledger(s, report.week, "contract", key, mission.reward[key])
		var result := {"id": s.contract.id, "week": report.week, "passed": passed}
		s.contract_results.append(result)
		report.notes.append("계절 계약 %s · %s" % ["달성" if passed else "미달성", mission.name])
		s.contract = {}
	if int(s.week) in [7, 20, 33, 46] and not s.get("cabinet", {}).get("enabled", false):
		var pool: Array = c.chronicle.missions.keys()
		pool.sort()
		var rng := Xoshiro128.new(int(s.seed) ^ (int(s.week) * 829), 23)
		s.contract_offer = []
		while s.contract_offer.size() < 3:
			s.contract_offer.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	if int(s.week) == 40 and not s.trial_started:
		s.trial_started = true
		match s.trial:
			"frost": apply_bonuses(s, {"heating": 1.5})
			"rot":
				var lost := WeekSim.total_food(s) * 0.15
				s.public.food *= 0.85
				s.resident.food *= 0.85
				WeekSim._ledger(s, 40, "trial", "food", -lost)
			"audit":
				var paid := minf(2000, s.public.money)
				s.public.money -= paid
				WeekSim._ledger(s, 40, "trial", "money", -paid)
				if paid < 2000:
					s.mood = maxf(0, s.mood - 10)
					report.notes.append("특별 공납 미납 · 민심 -10")
		report.notes.append("겨울 시련 시작 · " + c.chronicle.trials[s.trial].name)

static func contract_error(c: Dictionary, s: Dictionary, id: String) -> String:
	if s.status != "active" or id not in s.get("contract_offer", []): return "지금 선택할 수 없는 계약입니다."
	for key in c.chronicle.missions[id].cost:
		if s.public[key] < c.chronicle.missions[id].cost[key]: return "계약 준비에 필요한 공공 재고가 부족합니다."
	return ""

static func choose_contract(c: Dictionary, s: Dictionary, id: String) -> String:
	if id == "skip" and s.status == "active" and not s.get("contract_offer", []).is_empty():
		s.contract_offer = []
		s.log.append("이번 계절은 영지 안정에 집중합니다.")
		return ""
	var error := contract_error(c, s, id)
	if error != "": return error
	for key in c.chronicle.missions[id].cost:
		var cost: float = c.chronicle.missions[id].cost[key]
		s.public[key] -= cost
		WeekSim._ledger(s, s.week, "contract_cost", key, -cost)
	s.contract = {"id": id, "deadline": mini(52, (int((int(s.week) - 1) / 13) + 1) * 13)}
	s.contract_offer = []
	return ""

static func trial_passed(c: Dictionary, s: Dictionary) -> bool:
	var trial: Dictionary = c.chronicle.trials[s.trial]
	return s.week > 52 and s.pop > 0 and value(s, trial.target) >= trial.threshold

static func bonus_points(c: Dictionary, s: Dictionary) -> Dictionary:
	var contracts := 0
	for result in s.contract_results:
		if result.passed: contracts += 3
	return {"season_points": mini(4, int((int(s.week) - 1) / 13)) * 2, "contract_points": contracts, "trial_points": 6 if trial_passed(c, s) else 0}

static func tutorial_step(s: Dictionary) -> int:
	if not active(s) or not s.tutorial.enabled: return -1
	var step: int = int(s.tutorial.step)
	while step < 7:
		var done := false
		match step:
			0: done = not s.perks.is_empty()
			1: done = not s.seen_events.is_empty()
			2: done = int(s.facilities.get("B13", 0)) + s.orders.count("B13") + s.projects.filter(func(p): return p.id == "B13").size() >= 6
			3: done = s.assign.build >= 8 or int(s.facilities.get("B13", 0)) >= 6
			4: done = s.week >= 3
			5: done = not s.council_visits.is_empty()
			6: done = s.get("tutorial_build_seen", false)
		if not done: break
		step += 1
	s.tutorial.step = step
	return step
