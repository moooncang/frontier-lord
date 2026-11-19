class_name WeekSim
## 주간 경제 코어. 명령 묶음은 검증 후 원자적으로 접수한다.
## Node·현재 시각·저장소를 참조하지 않는다. 수치 공식은 이 파일에만 둔다.
## shortcut: 수량은 float로 저장, 원장 보존 검증을 1/100 정수로 바꿀 때 전환

const SOW_WEEKS := [3, 4, 5, 6]
const GROW_WEEKS := [7, 32]
const HARVEST_WEEKS := [33, 36]
const GATHER_PER_SEASON := [48.0, 48.0, 24.0, 0.0] # 02번 4절, 1단지 8명 기준
const SEASON_NAMES := ["봄", "여름", "가을", "겨울"]


static func week_of_year(w: int) -> int:
	return (w - 1) % Constants.WEEKS_PER_YEAR + 1


@warning_ignore("integer_division")
static func season_of(wy: int) -> int:
	return (wy - 1) / Constants.WEEKS_PER_SEASON


@warning_ignore("integer_division")
static func year_of(w: int) -> int:
	return (w - 1) / Constants.WEEKS_PER_YEAR + 1


static func total_food(s: Dictionary) -> float:
	return s.public.food + s.resident.food


static func food_weeks(s: Dictionary) -> float:
	var need: float = s.pop * Constants.FOOD_PER_PERSON_WEEK * s.ration
	return total_food(s) / need if need > 0 else INF


static func capacity(s: Dictionary, content: Dictionary, key: String) -> float:
	var result := 0.0
	for id in s.facilities:
		result += float(content.facilities[id].get(key, 0)) * s.facilities[id]
	return result


static func stage(s: Dictionary, content: Dictionary) -> int:
	if s.pop >= 100 and capacity(s, content, "housing") >= s.pop * 0.9 and capacity(s, content, "water") >= s.pop * 0.9 and s.facilities.get("B22", 0) > 0:
		return 2
	return 1


## 저장된 회차 보너스. 특전·특성처럼 누적해 저장할 때는 반드시 이 값을 쓴다.
static func raw_bonus(s: Dictionary, key: String, fallback: float = 1.0) -> float:
	return float(s.get("bonuses", {}).get(key, fallback))


## 이번 주에 실제로 적용되는 값. 영지 규칙의 날씨·정책·시설·수치 배율을 포함한다.
static func bonus(s: Dictionary, key: String, fallback: float = 1.0) -> float:
	return RealmRules.apply(s, key, raw_bonus(s, key, fallback), fallback == 0.0)


## 이번 주 농사에 자동 배정되는 노동. 파종 4명/구획, 생육 1명, 수확 4명.
static func farm_demand(s: Dictionary, wy: int) -> int:
	var plots := int(s.facilities.get("B13", 0))
	if wy >= SOW_WEEKS[0] and wy <= SOW_WEEKS[-1]:
		return int(ceil(plots * 4 * bonus(s, "sow_labor")))
	if wy >= GROW_WEEKS[0] and wy <= GROW_WEEKS[1]:
		return plots
	if wy >= HARVEST_WEEKS[0] and wy <= HARVEST_WEEKS[1]:
		return plots * 4
	return 0


## 현재 배치·진행 사업 그대로 n주 진행한 전망. 사건·교역은 제외하며 원본과 난수를 건드리지 않는다.
static func forecast(s: Dictionary, content: Dictionary, weeks: int = 13) -> Dictionary:
	var trial: Dictionary = s.duplicate(true)
	trial.orders = []
	trial.ledger = []
	var lowest := food_weeks(trial)
	var lowest_week := int(trial.week)
	for i in weeks:
		process_week(trial, content)
		if food_weeks(trial) < lowest:
			lowest = food_weeks(trial)
			lowest_week = int(trial.week) - 1
	return {"food_weeks": food_weeks(trial), "food": total_food(trial), "lowest": lowest, "lowest_week": lowest_week,
		"money": int(trial.public.money), "fuel": float(trial.public.fuel), "pop": int(trial.pop)}


## 예약만 하고 아직 착공하지 않은 공사가 쓸 몫. 구매·사건 지출이 이 몫을 건드리지 않게 한다.
static func reserved(s: Dictionary, content: Dictionary) -> Dictionary:
	var out := {"money": 0.0, "wood": 0.0, "stone": 0.0, "tools": 0.0, "iron": 0.0}
	for id in s.get("orders", []):
		if not content.facilities.has(id):
			continue
		var cost: Dictionary = Constants.GRADE_COST[content.facilities[id].grade]
		out.money += float(cost.gold) * Constants.COPPER_PER_GOLD
		for key in ["wood", "stone", "tools", "iron"]:
			out[key] += float(cost[key])
	return out


static func validate_orders(s: Dictionary, content: Dictionary) -> Array:
	var trial: Dictionary = s.duplicate(true)
	var errors: Array = []
	for id in s.orders:
		var error := _start_project(trial, content, str(id), [])
		if error != "":
			errors.append(error)
	return errors


static func process_week(s: Dictionary, content: Dictionary) -> Dictionary:
	var w: int = s.week
	var wy := week_of_year(w)
	var season := season_of(wy)
	var fac: Dictionary = content.facilities
	var notes: Array = []

	# 실패한 묶음은 자원·시간·다른 주문을 전혀 변경하지 않는다.
	var errors := validate_orders(s, content)
	if not errors.is_empty():
		return {"advanced": false, "week": w, "notes": errors, "food_weeks": food_weeks(s)}
	# 여러 주 미리보기에서도 기간이 끝난 지원을 다음 주까지 남기지 않는다.
	if SeasonalInvestments.enabled(s): RealmRules.refresh(s,content)
	for order in s.orders:
		_start_project(s, content, order, notes)
	s.orders = []
	_repay_arrears(s)
	var efficiency := 1.0
	if int(s.get("unpaid_weeks", 0)) >= 8:
		efficiency = 0.5
	elif int(s.get("unpaid_weeks", 0)) >= 4:
		efficiency = 0.75
	if efficiency < 1.0:
		notes.append("미지급 누적으로 공공 작업 효율 %.0f%%" % (efficiency * 100))

	# 5 가용 노동 확정. 우선순위: 파종·수확 > 채집 > 공사 > 산업
	var labor := int(floor(s.pop * s.labor_ratio))
	var plots := int(s.facilities.get("B13", 0))
	var demand := farm_demand(s, wy)
	var farm_workers := mini(labor, demand)
	var left := labor - farm_workers
	var gather_w := mini(left, mini(maxi(0, int(s.assign.gather)), 8 * int(s.facilities.get("B17", 0))))
	left -= gather_w
	var work_remaining := 0
	for project in s.projects:
		work_remaining += int(project.work_left)
	var build_w := mini(left, mini(maxi(0, int(s.assign.build)), work_remaining))
	left -= build_w
	var logging_w := mini(left, mini(maxi(0, int(s.assign.logging)), 4 * int(s.facilities.get("B25", 0))))
	left -= logging_w
	var quarry_w := mini(left, mini(maxi(0, int(s.assign.quarry)), 4 * int(s.facilities.get("B27", 0))))
	left -= quarry_w
	var garden_w := mini(left, mini(maxi(0, int(s.assign.get("garden", 0))), 4 * int(s.facilities.get("B14", 0))))
	left -= garden_w
	# 벌목과 장작 가공은 같은 작업장의 인원 한도를 공유한다.
	var fuel_w := mini(left, mini(maxi(0, int(s.assign.get("fuel", 0))), maxi(0, 4 * int(s.facilities.get("B25", 0)) - logging_w)))
	left -= fuel_w
	var milling_w := mini(left, mini(maxi(0, int(s.assign.get("milling", 0))), 3 * int(s.facilities.get("B19", 0))))
	left -= milling_w
	if RealmRules.enabled(s):
		# 주민 생업: 작업반 밖의 주민은 스스로 채집터와 채소밭의 빈자리를 채운다.
		var open_gather := 8 * int(s.facilities.get("B17", 0)) - gather_w
		if season == 3 and bonus(s, "winter_gather", 0.0) <= 0:
			open_gather = 0
		var joined := mini(left, maxi(0, open_gather))
		gather_w += joined
		left -= joined
		joined = mini(left, maxi(0, 4 * int(s.facilities.get("B14", 0)) - garden_w)) if season < 3 else 0
		garden_w += joined
		left -= joined
	s["labor_report"] = {"available": labor, "farm": farm_workers, "gather": gather_w, "build": build_w, "logging": logging_w, "quarry": quarry_w, "garden": garden_w, "fuel": fuel_w, "milling": milling_w}
	var farm_f := 1.0 if demand == 0 else float(farm_workers) / demand

	# 6 생산. 수확 = 540 × 파종충족 × 수확충족 × 토질 × 날씨, 33~36주에 25%씩.
	if wy == SOW_WEEKS[0]:
		# shortcut: 파종 첫 주의 구획 수로 고정, 파종 중 개간한 구획은 이듬해부터
		var per_plot := Constants.SEED_PER_PLOT * bonus(s, "seed")
		s.plots_sown = mini(plots, int(floor(total_food(s) / per_plot)))
		var seed_need: float = s.plots_sown * per_plot
		_transfer(s, "food", "public", "resident", seed_need)
		s.resident.food -= seed_need
		_ledger(s, w, "seed", "food", -seed_need)
		s.sow_f_sum = 0.0
	if wy in SOW_WEEKS:
		s.sow_f_sum += farm_f / SOW_WEEKS.size()
	if wy >= HARVEST_WEEKS[0] and wy <= HARVEST_WEEKS[1]:
		var h: float = Constants.BASE_FARM_HARVEST * s.plots_sown * 0.25 * s.sow_f_sum * farm_f * s.soil * s.weather * bonus(s, "harvest")
		s.resident.food += h
		_ledger(s, w, "harvest", "food", h)
	var sites := int(s.facilities.get("B17", 0))
	if sites > 0 and gather_w > 0:
		var per_site: float = GATHER_PER_SEASON[season]
		if season == 3:
			per_site = 48.0 * bonus(s, "winter_gather", 0.0)
		var g: float = per_site * sites * minf(1.0, gather_w / (8.0 * sites)) * bonus(s, "gather")
		s.resident.food += g
		_ledger(s, w, "gather", "food", g)
	if s.facilities.get("B25", 0) > 0 and logging_w > 0:
		var tool_cost := 0.2 * bonus(s, "tool_use")
		var f: float = minf(logging_w / 4.0 * efficiency, s.public.tools / tool_cost)
		s.public.wood += 20.0 * f * bonus(s, "logging")
		s.public.tools -= tool_cost * f
		_ledger(s, w, "logging", "wood", 20.0 * f * bonus(s, "logging"))
		_ledger(s, w, "logging", "tools", -tool_cost * f)
	if s.facilities.get("B27", 0) > 0 and quarry_w > 0:
		var tool_cost := 0.2 * bonus(s, "tool_use")
		var f: float = minf(quarry_w / 4.0 * efficiency, s.public.tools / tool_cost)
		s.public.stone += 12.0 * f * bonus(s, "quarry")
		s.public.tools -= tool_cost * f
		_ledger(s, w, "quarry", "stone", 12.0 * f * bonus(s, "quarry"))
		_ledger(s, w, "quarry", "tools", -tool_cost * f)
	if garden_w > 0 and season < 3:
		var vegetables := garden_w * 4.0 * bonus(s, "garden")
		s.resident.food += vegetables
		_ledger(s, w, "garden", "food", vegetables)
	if fuel_w > 0:
		var fuel_work := minf(fuel_w / 4.0 * efficiency, s.public.wood / 12.0)
		s.public.wood -= fuel_work * 12.0
		s.public.fuel += fuel_work * 24.0
		_ledger(s, w, "fuel", "wood", -fuel_work * 12.0)
		_ledger(s, w, "fuel", "fuel", fuel_work * 24.0)

	# 영지 규칙의 생업 시설(어장·대장간 등)은 작업반 밖의 주민 인력으로 돌아간다.
	var realm_work := RealmRules.produce(s, content, w, season, left, efficiency)
	if RealmRules.enabled(s):
		s.labor_report["realm"] = int(realm_work.used)
		s.labor_report["realm_by"] = realm_work.by
		if FantasyFrontiers.enabled(s): s.labor_report["realm_operations"] = realm_work.operations
	for key in ["wood", "stone", "tools", "fuel"]:
		# 나눗셈 오차로 생긴 -0.0000001 같은 값은 재고 0이다.
		if float(s.public[key]) < 0.0:
			s.public[key] = 0.0

	# 7 건설. 공사는 명령 순서대로 노동을 받고, 완공 시설은 다음 주부터 운영한다.
	var avail := int(floor(build_w * efficiency))
	for p in s.projects:
		if avail <= 0:
			break
		var d: Dictionary = fac[p.id]
		var cost: Dictionary = Constants.GRADE_COST[d.grade]
		var work: int = mini(avail, int(p.work_left))
		avail -= work
		p.work_left -= work
		var gold: float = cost.gold * Constants.COPPER_PER_GOLD
		var progress_cost: int = mini(int(p.escrow), int(round(gold * 0.6 * work / p.work_total)))
		p.escrow -= progress_cost
		_ledger(s, w, "construction", "money", -progress_cost)
		if p.work_left <= 0:
			_ledger(s, w, "construction", "money", -int(p.escrow))
			p.escrow = 0
			s.pending.append(p.id)
			notes.append("%s 완공, 다음 주부터 운영" % d.name)
	s.projects = s.projects.filter(func(p): return p.work_left > 0)

	# 8 식량 소비. 주민 재고 → 부족분 공공 구휼(이전) → 미충족.
	var need: float = s.pop * Constants.FOOD_PER_PERSON_WEEK * s.ration
	var eaten: float = minf(need, s.resident.food)
	if eaten < need:
		var relief := _transfer(s, "food", "public", "resident", need - eaten)
		if relief > 0:
			notes.append("구휼 %.0f식량" % relief)
		eaten += relief
	s.resident.food -= eaten
	_ledger(s, w, "consume", "food", -eaten)
	var fill: float = eaten / need if need > 0 else 1.0
	s.food_satisfaction = fill
	s.famine_weeks = s.famine_weeks + 1 if fill < 0.75 else 0
	if season == 3:
		var fuel_need: float = s.pop * 0.1 * bonus(s, "heating")
		var fuel_used := minf(fuel_need, s.public.fuel)
		s.public.fuel -= fuel_used
		s["heat_fill"] = fuel_used / fuel_need if fuel_need > 0 else 1.0
		_ledger(s, w, "heating", "fuel", -fuel_used)
	else:
		s["heat_fill"] = 1.0

	# 9 부패. 저장 시설 중 가장 낮은 부패율 하나, 용량 초과분은 야적 2%.
	var cap := 0.0
	var rate := Constants.YARD_SPOILAGE
	for id in s.facilities:
		var d: Dictionary = fac[id]
		if d.has("storage"):
			cap += d.storage * s.facilities[id]
			rate = minf(rate, d.spoilage)
	cap *= bonus(s, "storage")
	rate *= RealmRules.mod(s, "spoil")
	if milling_w > 0:
		rate *= 1.0 - 0.2 * minf(1.0, milling_w / 3.0)
	var total := total_food(s)
	if total > 0:
		var over := maxf(0.0, total - cap)
		var spoil_rate: float = (rate * (total - over) + Constants.YARD_SPOILAGE * over) / total
		if over > 0:
			notes.append("창고 초과 야적 %.0f" % over)
		for acct in ["public", "resident"]:
			var loss: float = s[acct].food * spoil_rate
			s[acct].food -= loss
			_ledger(s, w, "spoil", "food", -loss)

	# 10 급여·세금·유지비·공납. 금고 0이면 체불로 기록하고 음수 현금을 만들지 않는다.
	_pay(s, (build_w + logging_w + quarry_w + fuel_w + milling_w + int(realm_work.paid)) * Constants.PUBLIC_WORKER_ANNUAL_WAGE / 52.0 * bonus(s, "wages"), "wages", true)
	var fee := RealmRules.market_fee(s, content)
	if fee > 0:
		s.public.money += fee
		_ledger(s, w, "market_fee", "money", fee)
	var maint := 0.0
	for id in s.facilities:
		maint += Constants.GRADE_COST[fac[id].grade].gold * Constants.COPPER_PER_GOLD * s.facilities[id]
	_pay(s, maint * Constants.MAINTENANCE_RATE / 52.0 * bonus(s, "maintenance"), "maintenance")
	var share := 0.3 if wy == 13 else (0.7 if wy == 36 else 0.0) # 농촌 납부 주
	if share > 0.0:
		_collect_tax(s, share, notes)
	if wy == 39 and year_of(w) > s.tribute_exempt_years:
		var due := int(round(s.prev_year_tax * Constants.TRIBUTE_RATE))
		_pay(s, due, "tribute")
		notes.append("공납 %d동" % due)
	if wy == Constants.WEEKS_PER_YEAR:
		s.prev_year_tax = s.tax_year
		s.tax_year = 0
	s.unpaid_weeks = int(s.get("unpaid_weeks", 0)) + 1 if s.arrears_wage > 0 else 0

	# 11 출생·사망. 잔여 누적 후 정수 반영, 기아 사망은 4주 연속 부족부터.
	s.birth_res += s.pop * s.birth_rate / 52.0
	s.death_res += s.pop * s.death_rate / 52.0
	if s.famine_weeks >= 4:
		s.death_res += s.pop * minf(0.03, (0.75 - fill) * 0.04)
	var births := int(floor(s.birth_res))
	s.birth_res -= births
	var deaths := int(floor(s.death_res))
	s.death_res -= deaths
	s.pop = maxi(0, s.pop + births - deaths)

	# 15 완공 시설 반영, 주 번호 증가, 요약 반환
	for id in s.pending:
		s.facilities[id] = s.facilities.get(id, 0) + 1
	s.pending = []
	s.week += 1
	s.log.append_array(notes)
	if s.log.size() > 200:
		s.log = s.log.slice(-200)
	return {"advanced": true, "week": w, "notes": notes, "food_weeks": food_weeks(s)}


static func _start_project(s: Dictionary, content: Dictionary, id: String, notes: Array) -> String:
	var fac: Dictionary = content.facilities
	if not fac.has(id):
		return "알 수 없는 시설 %s" % id
	var d: Dictionary = fac[id]
	if d.grade == "T":
		return "임시 시설은 새로 건설할 수 없습니다."
	var planned: int = int(s.facilities.get(id, 0))
	for project in s.projects:
		if project.id == id:
			planned += 1
	if RealmRules.enabled(s):
		# 영지 규칙: 인구 단계 대신 선행 시설과 시설별 한도로 연다.
		var blocked := RealmRules.build_error(s, content, id, planned)
		if blocked != "":
			return blocked
	else:
		if d.get("realm", false):
			return "%s: 이 통치에서는 지을 수 없는 시설입니다." % d.name
		if int(d.stage) > stage(s, content):
			return "%s: 촌락 승격 후 건설할 수 있습니다." % d.name
	if id == "B17" and planned >= 2:
		return "채집터는 이 지역에 2개까지 만들 수 있습니다."
	var c: Dictionary = Constants.GRADE_COST[d.grade]
	var lack := []
	for k in ["wood", "stone", "tools", "iron"]:
		if s.public.get(k, 0) < c[k]:
			lack.append(k)
	if s.public.money < c.gold * Constants.COPPER_PER_GOLD:
		lack.append("money")
	if not lack.is_empty():
		return "%s 착공 거부: %s 부족" % [d.name, ", ".join(lack)]
	for k in ["wood", "stone", "tools", "iron"]:
		s.public[k] -= c[k]
	var full_price: int = int(c.gold * Constants.COPPER_PER_GOLD)
	s.public.money -= full_price
	var deposit: int = int(round(full_price * 0.2))
	_ledger(s, s.week, "construction", "money", -deposit)
	var work: int = int(c.work)
	if id == "B13" and "M04" in s.get("meta_snapshot", []) and not s.get("first_survey", false):
		work = int(ceil(work * 0.85))
		s.first_survey = true
	work = maxi(1, int(ceil(work * RealmRules.mod(s, "build_work"))))
	s.projects.append({"id": id, "work_left": work, "work_total": work, "escrow": full_price - deposit})
	notes.append("%s 착공 (%d인주)" % [d.name, work])
	return ""


static func cancel_project(s: Dictionary, content: Dictionary, index: int) -> bool:
	if index < 0 or index >= s.projects.size():
		return false
	var p: Dictionary = s.projects[index]
	var cost: Dictionary = Constants.GRADE_COST[content.facilities[p.id].grade]
	var unused: float = float(p.work_left) / p.work_total
	for key in ["wood", "stone", "tools", "iron"]:
		s.public[key] += cost[key] * (unused + (1.0 - unused) * 0.3)
	s.public.money += int(p.escrow)
	s.projects.remove_at(index)
	return true


static func _collect_tax(s: Dictionary, share: float, notes: Array) -> void:
	var rate := minf(0.98, Constants.TAX_COLLECTION_BASE + bonus(s, "tax", 0.0))
	if s.facilities.get("B63", 0) > 0:
		rate = minf(0.98, rate + 0.03)
	var assessed := int(round(s.pop * Constants.TAX_BASE_RURAL * rate * share))
	var in_kind_value := int(round(assessed * Constants.TAX_IN_KIND_SHARE))
	var cash := assessed - in_kind_value
	var grain := _transfer(s, "food", "resident", "public", float(in_kind_value) / Constants.FOOD_REFERENCE_PRICE)
	var paid: int = mini(cash, s.resident.money)
	s.resident.money -= paid
	s.public.money += paid
	s.tax_year += paid + int(grain * Constants.FOOD_REFERENCE_PRICE)
	if paid < cash:
		s.arrears_tax += cash - paid
	s.arrears_tax += maxi(0, in_kind_value - int(round(grain * Constants.FOOD_REFERENCE_PRICE)))
	_ledger(s, s.week, "tax", "money", paid)
	notes.append("세금 현금 %d동, 현물 %.0f식량" % [paid, grain])


## 이전은 총재고 증감 0과 양쪽 계정을 기록한다.
static func _transfer(s: Dictionary, asset: String, from: String, to: String, qty: float) -> float:
	var moved: float = minf(qty, s[from][asset])
	s[from][asset] -= moved
	s[to][asset] += moved
	if moved > 0:
		s.ledger.append({"w": s.week, "src": "transfer", "asset": asset, "qty": 0, "amount": moved, "from": from, "to": to})
	return moved


static func _pay(s: Dictionary, amount: float, source: String = "expense", to_residents: bool = false) -> void:
	s.money_res += amount
	var due := int(floor(s.money_res))
	s.money_res -= due
	var paid: int = mini(due, s.public.money)
	s.public.money -= paid
	if to_residents:
		s.resident.money += paid
	_ledger(s, s.week, source, "money", -paid)
	if paid < due:
		s.arrears_wage += due - paid
		if not s.has("arrears"):
			s.arrears = {}
		s.arrears[source] = int(s.arrears.get(source, 0)) + due - paid


static func _repay_arrears(s: Dictionary) -> void:
	if not s.has("arrears"):
		s.arrears = {}
	for source in s.arrears:
		var paid := mini(int(s.public.money), int(s.arrears[source]))
		if paid <= 0:
			continue
		s.public.money -= paid
		s.arrears[source] -= paid
		s.arrears_wage -= paid
		if source == "wages":
			s.resident.money += paid
		_ledger(s, s.week, "arrears_payment", "money", -paid)


static func _ledger(s: Dictionary, w: int, src: String, asset: String, qty: float) -> void:
	s.ledger.append({"w": w, "src": src, "asset": asset, "qty": qty})
