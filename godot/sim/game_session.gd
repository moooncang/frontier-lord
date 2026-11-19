class_name GameSession
extends RefCounted
## 화면에 의존하지 않는 플레이 흐름. 메타와 회차를 함께 저장한다.

const RUN_WEEKS := 52
const RESOURCE_PRICES := {"food": 2, "wood": 10, "stone": 12, "tools": 100, "fuel": 4}
const DRAFT_WEEKS := [13, 26, 39]

var content: Dictionary
var state: Dictionary = {}
var profile: Dictionary = {"version": 1, "points": 0, "upgrades": [], "receipts": {}, "runs": 0}


func _init(data: Dictionary) -> void:
	content = data


func start_run(run_seed: int, origin: String, config: Dictionary = {}) -> void:
	if not config.is_empty():
		origin = ChronicleRules.candidates(content.chronicle, run_seed)[clampi(int(config.get("candidate", 0)), 0, 2)].origin
	if not content.progression.origins.has(origin):
		origin = "settler"
	profile.runs = int(profile.runs) + 1
	state = RunState.new_run(content.charters.C01, run_seed)
	state.run_id = "%d-%d" % [run_seed, profile.runs]
	state.origin = origin
	state.meta_snapshot = profile.upgrades.duplicate()
	var setup: Dictionary = content.progression.origins[origin]
	for key in ["logging", "wages", "maintenance", "gather", "harvest", "seed", "buy"]:
		if setup.has(key):
			state.bonuses[key] = setup[key]
	state.public.money = int(round(state.public.money * setup.get("money", 1.0) * (1.05 if "M01" in profile.upgrades else 1.0)))
	state.public.wood += setup.get("wood", 0)
	if "M02" in profile.upgrades:
		state.public.food *= 1.05
		state.resident.food *= 1.05
	if "M03" in profile.upgrades:
		state.public.tools += maxi(1, int(ceil(state.public.tools * 0.1)))
	if "M14" in profile.upgrades:
		state.trust += 3
	# 전용 기후 스트림. 화면 열기·불러오기는 난수를 소비하지 않는다.
	var climate := Xoshiro128.new(run_seed, 1)
	state.weather = [0.90, 1.0, 1.10][climate.randi_range(0, 2)]
	if not config.is_empty():
		ChronicleRules.setup(content, state, profile, config)
	LegacyPath.ensure(profile)
	LegacyPath.apply(state, profile)
	CampaignDirector.setup(state, content, config)
	WorkcrewRules.setup(state, config)
	ExpeditionModifiers.setup(state, content, config)
	RealmRules.setup(state, content, config)
	VillageRelics.setup(state, content, config)
	CrisisDirector.setup(state, content, config)
	MandateRules.setup(state, content, config)
	PeopleRules.setup(state, config)
	FrontierDifficulty.setup(state, profile, content, config)
	SeasonalInvestments.setup(state, content, config)
	FantasyFrontiers.setup(state, content, config)
	if FrontierDifficulty.enabled(state) or SeasonalInvestments.enabled(state) or FantasyFrontiers.enabled(state): RealmRules.refresh(state,content)
	if bool(config.get("cabinet", false)):
		CabinetRules.setup(state)
		state.cabinet.advisor_week = 0
		state.tutorial.enabled = false
		CabinetRules.reassign(state, content)
	if not config.is_empty(): _offer_perks()
	_update_goals()
	_schedule_event()
	if config.has("onboarding"): Onboarding.setup(state, bool(config.onboarding))


func advance() -> Dictionary:
	if state.is_empty() or state.status != "active":
		return {"advanced": false, "notes": ["진행 중인 회차가 없습니다."]}
	if state.active_event != "" or not state.perk_offer.is_empty() or not state.get("contract_offer", []).is_empty():
		return {"advanced": false, "notes": ["남아 있는 결단을 먼저 선택해 주세요."]}
	if VillageRelics.enabled(state) and not state.realm.sanctuary.offer.is_empty():
		return {"advanced":false,"notes":["발견한 성물을 먼저 선택해 주세요."]}
	var errors := WeekSim.validate_orders(state, content)
	if not errors.is_empty():
		return {"advanced": false, "notes": errors}
	var before := state.duplicate(true)
	var advisor_context := {}
	if state.get("cabinet", {}).get("enabled", false):
		var allocation := CabinetRules.reassign(state, content)
		if not allocation.errors.is_empty(): return {"advanced":false, "notes":allocation.errors}
		# 선임한 인물의 접견은 한 주에 한 번만 처리한다. 화면을 여는 행위로는 적용하지 않는다.
		if int(state.cabinet.get("advisor_week", 0)) != int(state.week):
			advisor_context = CabinetActions.advisor_definition(self,str(state.cabinet.get("advisor","CH01")))
			var advisor_error := council_visit(str(state.cabinet.get("advisor", "CH01")))
			if advisor_error == "": state.cabinet.advisor_week = int(state.week)
	RealmRules.refresh(state, content)
	var report := WeekSim.process_week(state, content)
	# 다음 주가 열리는 시점에 도착: 1주에 주문한 수레는 3주 시작에 사용 가능.
	report.notes.append_array(_arrive())
	_wellbeing()
	RealmRules.after_week(state, content, report)
	if VillageRelics.enabled(state):
		VillageRelics.after_week(before,state,content,report)
		RealmRules.refresh(state,content)
	ChronicleRules.after_week(content, state, report)
	CampaignDirector.after_week(state, content, report)
	if CrisisDirector.enabled(state):
		CrisisDirector.after_week(before,state,content,report)
		RealmRules.refresh(state,content)
	MandateRules.after_week(before,state,content,report)
	PeopleRules.after_week(state,content,report)
	if SeasonalInvestments.enabled(state):
		SeasonalInvestments.after_week(before,state,content,report)
		RealmRules.refresh(state,content)
	if FantasyFrontiers.enabled(state):
		FantasyFrontiers.after_week(before,state,content,report)
		RealmRules.refresh(state,content)
	state.actions = 2
	state.actions_used = []
	_update_goals()
	state.history.append({"week": report.week, "money": state.public.money, "food": WeekSim.total_food(state), "pop": state.pop, "notes": report.notes.duplicate()})
	if state.pop <= 0:
		settle("패배")
	elif MandateRules.dismissed(state):
		settle("해임")
	elif state.week > RUN_WEEKS:
		settle("완주")
	else:
		# 회차를 계속할 때만 선택 보상을 연다. 마지막 주 승격의 금고·점수 보상은 위에서 유지한다.
		if VillageRelics.enabled(state) and int(before.realm.rank) < 1 and int(state.realm.rank) >= 1:
			VillageRelics.request_offer(state,content,"rank:1")
		if report.week in (ChronicleRules.DRAFT_WEEKS if ChronicleRules.active(state) else DRAFT_WEEKS):
			_offer_perks()
		_schedule_event()
	if CabinetRules.enabled(state) and state.status == "active":
		# 다음 주 화면의 예상도 바뀐 계절·시설에 맞는 자동 계획으로 계산한다.
		CabinetRules.reassign(state, content)
	report["stop"] = state.status != "active" or state.active_event != "" or not state.perk_offer.is_empty() or not state.get("contract_offer", []).is_empty() or WeekSim.food_weeks(state) < 4.0 or report.week in [13, 26, 39, 52]
	if VillageRelics.enabled(state) and not state.realm.sanctuary.offer.is_empty(): report.stop = true
	report["receipt_context"] = {"advisor":advisor_context}
	state.last_receipt = TurnReceipt.build(before,state,report)
	return report


func queue_build(id: String) -> String:
	if state.is_empty() or state.status != "active":
		return "진행 중인 회차가 없습니다."
	state.orders.append(id)
	var errors := WeekSim.validate_orders(state, content)
	if not errors.is_empty():
		state.orders.pop_back()
		return str(errors[0])
	return ""


func _schedule_event() -> void:
	if state.active_event != "":
		return
	for id in content.events:
		if content.events[id].get("fantasy_only",false) and not FantasyFrontiers.enabled(state): continue
		if content.events[id].get("plus_only", false) and not CrisisDirector.enabled(state):
			continue
		if content.events[id].get("relic_only", false) and not VillageRelics.enabled(state):
			continue
		if content.events[id].get("chronicle_only", false) and not ChronicleRules.active(state):
			continue
		if id not in state.seen_events and int(content.events[id].week) <= int(state.week):
			if state.get("cabinet", {}).get("enabled", false):
				if id == "EV01":
					# 안내만을 위한 첫 서신은 첫 개발 목표에 통합한다.
					state.seen_events.append(id)
					continue
				if id == "EV14":
					# 비용 없는 보상과 무효 선택의 비교는 주간 소식으로 처리한다.
					state.active_event = id
					choose_event(0)
					state.cabinet.news = "행정 기록 정리 · 신뢰 +4"
					state.cabinet.news_week = int(state.week)
					continue
			state.active_event = id
			return
	RealmRules.schedule(state, content)


func event_cost(option: Dictionary) -> Dictionary:
	var cost: Dictionary = option.get("cost", {}).duplicate(true)
	var event: Dictionary = content.events.get(state.active_event, {})
	if event.get("immigration", false) and not state.first_immigrant and "M13" in state.meta_snapshot and cost.has("money"):
		cost.money = int(ceil(cost.money * 0.8))
	return cost


func option_error(option: Dictionary) -> String:
	if option.get("relic_offer", false):
		var relic_error := VillageRelics.offer_error(state,content)
		if relic_error != "": return relic_error
	var cost := event_cost(option)
	var held := RealmRules.held(state, content)
	for key in cost:
		if state.public.get(key, 0) < cost[key]:
			return "공공 재고가 부족합니다: %s" % key
		if state.public.get(key, 0) - float(held.get(key, 0)) < cost[key]:
			return "예약한 공사에 쓸 몫을 빼면 부족합니다: %s" % key
	if option.has("requires_housing") and WeekSim.capacity(state, content, "housing") < state.pop + option.requires_housing:
		return "수용할 주거가 부족합니다. 움집 구역을 먼저 마련하세요."
	return RealmRules.option_error(state, content, option)


func choose_event(index: int) -> String:
	if state.status != "active" or not content.events.has(state.active_event):
		return "처리할 사건이 없습니다."
	var event: Dictionary = RealmRules.event_definition(state, content, str(state.active_event))
	if index < 0 or index >= event.options.size():
		return "잘못된 선택입니다."
	var option: Dictionary = event.options[index]
	var error := option_error(option)
	if error != "":
		return error
	var before := state.duplicate(true) if RealmRules.enabled(state) else {}
	var cost := event_cost(option)
	var paid := {}
	for key in cost:
		var qty: float = cost[key]
		var previous: float = state.public[key]
		state.public[key] -= qty
		paid[str(key)] = previous - float(state.public[key])
		WeekSim._ledger(state, state.week, "event_cost", key, -qty)
	state.public.money = int(state.public.money)
	if paid.has("money") and not before.is_empty(): paid["money"] = float(before.public.money) - float(state.public.money)
	var effects: Dictionary = option.get("effects", {}).duplicate(true)
	RealmRules.resolve(state, content, state.active_event, option, effects)
	for key in effects:
		var value: float = effects[key]
		if key == "money":
			# 금화 보상은 공공 금고로 들어간다.
			state.public.money = int(state.public.money) + int(value)
			WeekSim._ledger(state, state.week, "event", "money", int(value))
		elif key == "resident_food":
			state.resident.food += value
			WeekSim._ledger(state, state.week, "event", "food", value)
		elif key in ["food", "wood", "stone", "tools", "fuel"]:
			state.public[key] += value
			WeekSim._ledger(state, state.week, "event", key, value)
		elif key == "pop":
			state.pop += int(value)
			if value > 0: state.first_immigrant = true
		else:
			state[key] = float(state.get(key, 0)) + value
	for key in ["mood", "health", "security", "trust", "village", "guild"]:
		state[key] = clampf(state[key], 0, 100)
	FantasyFrontiers.resolve(state,content,str(state.active_event),option)
	state.log.append("%d주 · %s — %s" % [state.week, event.title, option.label])
	state.seen_events.append(state.active_event)
	PeopleRules.record(state, content, event, index)
	if option.get("relic_offer", false):
		var source := "event:%s:%d" % [state.active_event,state.week]
		var relic_error := VillageRelics.request_offer(state,content,source)
		if relic_error == "": state.realm.outcome["relic_offer"] = true
	state.active_event = ""
	RealmRules.refresh(state, content)
	RealmRules.finalize_outcome(before, state, paid)
	_update_goals()
	return ""


func choose_relic(id: String, replace_id: String = "") -> String:
	var error := VillageRelics.choose(state,content,id,replace_id,profile)
	if error == "":
		RealmRules.refresh(state,content)
		if CabinetRules.enabled(state): CabinetRules.reassign(state,content)
	return error


func equip_relic(id: String, replace_id: String = "") -> String:
	var error := VillageRelics.equip(state,content,id,replace_id)
	if error == "":
		RealmRules.refresh(state,content)
		if CabinetRules.enabled(state): CabinetRules.reassign(state,content)
	return error


func unequip_relic(id: String) -> String:
	var error := VillageRelics.unequip(state,id)
	if error == "":
		RealmRules.refresh(state,content)
		if CabinetRules.enabled(state): CabinetRules.reassign(state,content)
	return error


func _perk_candidates() -> Array:
	var available: Array = []
	for id in content.progression.perks:
		var perk: Dictionary = content.progression.perks[id]
		if perk.get("plus_only",false) and not CrisisDirector.enabled(state): continue
		if int(state.week) < int(perk.get("pool_min_week",1)) or int(state.week) > int(perk.get("pool_max_week",52)): continue
		if CrisisDirector.enabled(state):
			# 지난 파종·수확·징세에만 영향을 주는 선택지는 새 회차의 후반 드래프트에서 제외한다.
			var last_useful_week: int = {"seed":2,"sow_labor":6,"harvest":36,"tax":36}.get(str(perk.effect),52)
			if int(state.week) > last_useful_week: continue
		if content.progression.perks[id].get("chronicle_only", false) and not ChronicleRules.active(state):
			continue
		if id not in state.perks and id not in state.get("legacy_setup", {}).get("banished_perks", []):
			available.append(id)
	available.sort()
	return available


func _offer_perks() -> void:
	var available := _perk_candidates()
	var random := Xoshiro128.new(int(state.seed) ^ (int(state.drafts) * 7919), 5)
	state.perk_offer = []
	var focus := LegacyPath.perk_focus(state)
	var matching: Array = available.filter(func(id): return content.progression.perks[id].get("family", "") == focus) if not focus.is_empty() else []
	if not matching.is_empty():
		var id: String = matching[random.randi_range(0, matching.size() - 1)]
		state.perk_offer.append(id)
		available.erase(id)
	while not available.is_empty() and state.perk_offer.size() < 3:
		var index := random.randi_range(0, available.size() - 1)
		state.perk_offer.append(available[index])
		available.remove_at(index)
	state.drafts += 1


func choose_perk(id: String) -> bool:
	if state.status != "active" or id not in state.perk_offer or id in state.perks:
		return false
	var perk: Dictionary = content.progression.perks[id]
	var fallback := 0.0 if perk.effect in ["tax", "trust", "winter_gather"] else 1.0
	if fallback == 0:
		state.bonuses[perk.effect] = WeekSim.raw_bonus(state, perk.effect, 0) + perk.value
	else:
		state.bonuses[perk.effect] = WeekSim.raw_bonus(state, perk.effect) * perk.value
	state.perks.append(id)
	ChronicleRules.apply_bonuses(state,perk.get("extra_bonuses",{}))
	ChronicleRules.unlock_synergies(content, state)
	if ChronicleRules.active(state) and id not in profile.discoveries:
		profile.discoveries.append(id)
	state.perk_offer = []
	state.log.append("특전 획득 · " + perk.name)
	RealmRules.refresh(state, content)
	if CabinetRules.enabled(state): CabinetRules.reassign(state, content)
	return true


func refresh_perks() -> bool:
	if state.status != "active" or state.perk_offer.is_empty() or state.refreshes <= 0:
		return false
	state.refreshes -= 1
	_offer_perks()
	return true


func banish_perk(id: String) -> String:
	if state.is_empty() or state.get("status", "") != "active" or id not in state.get("perk_offer", []): return "현재 제안된 특전을 선택하세요."
	if int(state.get("legacy_setup", {}).get("perk_banishes", 0)) <= 0: return "남은 특전 제외권이 없습니다."
	var available: Array = _perk_candidates().filter(func(candidate): return candidate not in state.perk_offer and candidate != id)
	if available.is_empty(): return "대신 제안할 특전이 없습니다."
	var focus := LegacyPath.perk_focus(state)
	if not focus.is_empty() and not state.perk_offer.any(func(candidate): return candidate != id and content.progression.perks[candidate].get("family", "") == focus):
		var matching: Array = available.filter(func(candidate): return content.progression.perks[candidate].get("family", "") == focus)
		if not matching.is_empty(): available = matching
	var random := Xoshiro128.new(int(state.seed) ^ (int(state.drafts) * 7919), 5)
	var replacement: String = available[random.randi_range(0, available.size() - 1)]
	state.perk_offer[state.perk_offer.find(id)] = replacement
	state.legacy_setup.banished_perks.append(id)
	state.legacy_setup.perk_banishes -= 1
	state.drafts += 1
	return ""


func refresh_relics() -> String:
	return VillageRelics.refresh_offer(state, content)


func trade_quote(asset: String, quantity: int, buying: bool) -> int:
	if not RESOURCE_PRICES.has(asset) or quantity <= 0 or quantity > 200:
		return -1
	var discount: float = minf(0.5, state.trade_discount + (0.25 if state.facilities.get("B49", 0) > 0 else 0.0))
	var fee: int = int(round(200 * (1.0 - discount)))
	# 판매 배율(sell)은 지역 특성이 준다. 없으면 1이다.
	var multiplier := 1.1 * WeekSim.bonus(state, "buy") if buying else 0.9 * WeekSim.bonus(state, "sell")
	multiplier *= RealmRules.price(state, content, asset)
	var goods := int(round(quantity * RESOURCE_PRICES[asset] * multiplier))
	return goods + fee if buying else goods - fee


func trade(asset: String, quantity: int, buying: bool) -> String:
	if state.is_empty() or state.status != "active":
		return "진행 중인 회차가 없습니다."
	var quote := trade_quote(asset, quantity, buying)
	if quote < 0:
		return "운송료를 충당하지 못하는 물량입니다."
	if state.shipments.size() >= RealmRules.carts(state):
		return "교역 수레 %d대가 모두 운행 중입니다." % RealmRules.carts(state)
	if not buying and RealmRules.enabled(state) and int(state.facilities.get("B49", 0)) <= 0:
		return "장터를 지어야 물자를 내다 팔 수 있습니다."
	var held := RealmRules.held(state, content)
	if buying:
		if state.public.money < quote:
			return "교역 대금이 부족합니다."
		if state.public.money - float(held.money) < quote:
			return "예약한 공사비를 빼면 교역 대금이 부족합니다."
		state.public.money -= quote
		WeekSim._ledger(state, state.week, "trade_buy", "money", -quote)
	else:
		if state.public.get(asset, 0) - float(held.get(asset, 0)) < quantity:
			return "판매할 공공 재고가 부족합니다."
		state.public[asset] -= quantity
		WeekSim._ledger(state, state.week, "trade_depart", asset, -quantity)
	state.shipments.append({"asset": asset, "quantity": quantity, "buy": buying, "money": quote, "arrival": int(state.week) + RealmRules.delivery(state)})
	return ""


func _arrive() -> Array:
	var notes: Array = []
	var remaining: Array = []
	for shipment in state.shipments:
		if int(shipment.arrival) > int(state.week):
			remaining.append(shipment)
			continue
		if shipment.buy:
			state.public[shipment.asset] += shipment.quantity
			WeekSim._ledger(state, state.week, "trade_arrival", shipment.asset, shipment.quantity)
			notes.append("교역 수레 도착 · %s %d" % [shipment.asset, shipment.quantity])
		else:
			state.public.money += int(shipment.money)
			WeekSim._ledger(state, state.week, "trade_sale", "money", shipment.money)
			notes.append("교역 대금 도착 · %.2f금" % (shipment.money / 100.0))
	state.shipments = remaining
	return notes


func activity(id: String) -> String:
	if state.status != "active" or state.actions <= 0 or id in state.actions_used:
		return "이번 주에 더 진행할 수 없는 일정입니다."
	match id:
		"visit":
			state.mood = minf(100, state.mood + 3)
			state.village = minf(100, state.village + 2)
		"talk":
			state.trust = minf(100, state.trust + 3 + WeekSim.bonus(state, "trust", 0))
		"relief":
			if state.public.food < 40:
				return "구휼할 공공 식량 40이 필요합니다."
			WeekSim._transfer(state, "food", "public", "resident", 40)
			state.mood = minf(100, state.mood + 4)
		_:
			return "알 수 없는 일정입니다."
	state.actions -= 1
	state.actions_used.append(id)
	return ""


func _wellbeing() -> void:
	var housing := minf(1.0, WeekSim.capacity(state, content, "housing") / maxf(1, state.pop))
	var water := minf(1.0, WeekSim.capacity(state, content, "water") / maxf(1, state.pop))
	var mood_target: float = 45 + 15 * state.food_satisfaction + 10 * housing + (state.village - 50) * 0.2 - (1.0 - state.ration) * 40
	mood_target += RealmRules.target(state, "mood")
	state.mood = clampf(state.mood + clampf((mood_target - state.mood) * 0.15, -5, 5), 0, 100)
	var health_target: float = 35 + 15 * water + 15 * state.food_satisfaction + 10 * housing - (1 - state.get("heat_fill", 1.0)) * 20
	health_target -= (1.0 - state.ration) * 40
	if state.facilities.get("B59", 0) > 0:
		health_target += 5
	health_target += RealmRules.target(state, "health")
	state.health = clampf(lerpf(state.health, health_target, 0.1), 0, 100)


func choose_contract(id: String) -> String:
	return ChronicleRules.choose_contract(content, state, id)


func choose_support(id: String) -> String:
	var error := SeasonalInvestments.choose(state,content,id)
	if error.is_empty() and CabinetRules.enabled(state): CabinetRules.reassign(state,content)
	return error


func decline_support() -> String:
	return SeasonalInvestments.decline(state,content)


func council_visit(id: String) -> String:
	if (not ChronicleRules.active(state) and not CabinetRules.enabled(state)) or state.status != "active" or not content.chronicle.characters.has(id):
		return "접견할 수 없는 인물입니다."
	if state.actions <= 0 or "council_" + id in state.actions_used:
		return "이번 주에는 더 접견할 수 없습니다."
	var person: Dictionary = content.chronicle.characters[id]
	var amount: float = person.value + (WeekSim.bonus(state, "trust", 0) if person.effect == "trust" else 0)
	state[person.effect] = minf(100, state[person.effect] + amount)
	state.actions -= 1
	state.actions_used.append("council_" + id)
	if not state.has("council_visits"): state.council_visits = []
	if id not in state.council_visits: state.council_visits.append(id)
	return ""


func _update_goals() -> void:
	var farms := int(state.facilities.get("B13", 0))
	var granary := int(state.facilities.get("B22", 0)) >= 1
	var building: bool = state.projects.any(func(p): return p.id == "B22") or "B22" in state.orders
	var food := WeekSim.total_food(state)
	var target: int = int(state.pop) * 13
	state.goals = {
		"farms": {"title": "농지 6개", "detail": "농지 6구획 확보", "done": farms >= 6, "progress": minf(1.0, farms / 6.0), "status": "%d / 6구획" % farms},
		"storage": {"title": "곡물 곳간 1개", "detail": "정식 곡물 곳간 건설", "done": granary, "progress": 1.0 if granary else (0.5 if building else 0.0), "status": "완공" if granary else ("공사 중" if building else "미착공")},
		"food": {"title": "식량 13주분", "detail": "정상 배급 기준 식량 13주분", "done": food >= target, "progress": minf(1.0, food / maxf(1, target)), "status": "%.0f / %d" % [food, target]}
	}


func settle(reason: String) -> Dictionary:
	if state.is_empty():
		return {}
	if state.status == "finalized":
		return state.result
	_update_goals()
	var complete := 0
	for goal in state.goals.values():
		if goal.done:
			complete += 1
	var eligible: bool = int(state.week) > 13
	var success: bool = reason == "완주" and complete == 3 and state.pop > 0
	if ChronicleRules.active(state):
		success = success and ChronicleRules.trial_passed(content, state)
	var objective_points := complete * 6 if eligible else 0
	var completion_points := 10 if success else 0
	var first_points := 8 if eligible and profile.receipts.is_empty() else 0
	var points := objective_points + completion_points + first_points
	var result := {"reason": reason, "success": success, "objectives": complete, "objective_points": objective_points, "completion_points": completion_points, "first_points": first_points, "points": points, "week": mini(RUN_WEEKS, int(state.week) - 1)}
	if ChronicleRules.active(state):
		var extra := ChronicleRules.bonus_points(content, state)
		for key in extra:
			result[key] = extra[key] if eligible else 0
			points += int(result[key])
		result.points = points
		result.trial_passed = ChronicleRules.trial_passed(content, state)
	if CampaignDirector.enabled(state):
		result.campaign_points = int(state.campaign.points) if eligible else 0
		points += int(result.campaign_points)
		result.points = points
	if RealmRules.enabled(state):
		var realm_score := RealmRules.score(state, content, success)
		result.realm_points = int(realm_score.points) if eligible else 0
		result.grade = realm_score.grade
		result.grade_title = realm_score.title
		result.realm_lines = realm_score.lines
		points += int(result.realm_points)
		result.points = points
	var difficulty_result := FrontierDifficulty.result(state,eligible)
	if FantasyFrontiers.enabled(state): result["fantasy_paths"] = FantasyFrontiers.result(state)
	if not difficulty_result.is_empty():
		result.difficulty_level = difficulty_result.difficulty_level
		result.difficulty_points = difficulty_result.difficulty_points
		points += int(difficulty_result.difficulty_points)
		result.points = points
	if not profile.receipts.has(state.run_id):
		profile.points = int(profile.points) + points
		# 13주 미만 종료는 첫 기록 보너스를 소모하지 않는다.
		if eligible:
			profile.receipts[state.run_id] = result.duplicate(true)
		if ChronicleRules.active(state):
			profile.chronicles.append({"run_id": state.run_id, "seed": state.seed, "region": state.region, "perks": state.perks.duplicate(), "points": points, "week": result.week, "reason": reason, "success": success})
			if profile.chronicles.size() > 20: profile.chronicles.pop_front()
	state.result = result
	state.status = "finalized"
	return result


func buy_upgrade(id: String) -> String:
	if not state.is_empty() and state.get("status") == "active": return "진행 중인 통치를 끝낸 뒤 가문을 강화할 수 있습니다."
	if not content.progression.upgrades.has(id):
		return "알 수 없는 강화 항목입니다."
	if id in profile.upgrades:
		return "이미 구매한 강화입니다."
	var upgrade: Dictionary = content.progression.upgrades[id]
	if upgrade.requires != "" and upgrade.requires not in profile.upgrades:
		return "선행 강화를 먼저 구매해야 합니다."
	if profile.points < upgrade.cost:
		return "공훈이 부족합니다."
	profile.points = int(profile.points) - int(upgrade.cost)
	profile.upgrades.append(id)
	return ""


func buy_talent(id: String) -> String:
	if not state.is_empty() and state.get("status") == "active":
		return "진행 중인 통치를 끝낸 뒤 강화할 수 있습니다."
	return LegacyPath.buy(profile, id)


func refund_talents() -> int:
	if not state.is_empty() and state.get("status") == "active": return 0
	return LegacyPath.refund(profile)


func set_legacy_doctrine(id: String, replace_id: String = "") -> String:
	if not state.is_empty() and state.get("status") == "active": return "진행 중인 통치를 끝낸 뒤 가문 방침을 변경할 수 있습니다."
	return LegacyPath.select_doctrine(profile, id, replace_id)


func remove_legacy_doctrine(id: String) -> String:
	if not state.is_empty() and state.get("status") == "active": return "진행 중인 통치를 끝낸 뒤 가문 방침을 변경할 수 있습니다."
	return LegacyPath.remove_doctrine(profile, id)


func set_legacy_preparation(key: String, value: String) -> String:
	if not state.is_empty() and state.get("status") == "active": return "진행 중인 통치를 끝낸 뒤 부임 준비를 변경할 수 있습니다."
	return LegacyPath.set_preparation(profile, key, value)


func bundle() -> Dictionary:
	return {"version": 1, "profile": profile.duplicate(true), "state": state.duplicate(true)}
