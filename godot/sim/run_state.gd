class_name RunState
## 헌장에서 회차 상태 Dictionary를 만든다. 상태는 원시값만 담아 JSON으로 바로 저장할 수 있다.


static func new_run(charter: Dictionary, run_seed: int) -> Dictionary:
	var st: Dictionary = charter.start.duplicate(true)
	var facilities := {}
	for id in st.facilities:
		facilities[id] = int(st.facilities[id])
	st.public.money = int(st.public.money)
	st.resident.money = int(st.resident.money)
	st.public["iron"] = 0.0
	st.public["fuel"] = 0.0
	return {
		"seed": run_seed, "charter": charter.id,
		"week": int(st.week), "pop": int(st.pop), "labor_ratio": st.labor_ratio,
		"public": st.public, "resident": st.resident, "facilities": facilities,
		"soil": st.soil, "weather": st.weather,
		"mood": st.mood, "health": st.health, "security": st.security,
		"ration": 1.0,
		"assign": {"gather": 8, "build": 0, "logging": 0, "quarry": 0, "garden": 0, "fuel": 0, "milling": 0},
		"orders": [], "projects": [], "pending": [],
		"plots_sown": 0, "sow_f_sum": 0.0, "food_satisfaction": 1.0, "famine_weeks": 0,
		"birth_rate": Constants.BIRTH_RATE_YEAR, "death_rate": Constants.DEATH_RATE_YEAR,
		"birth_res": 0.0, "death_res": 0.0,
		"money_res": 0.0, "arrears_wage": 0, "arrears_tax": 0,
		"arrears": {}, "unpaid_weeks": 0,
		"tax_year": 0, "prev_year_tax": 0, "tribute_exempt_years": int(st.tribute_exempt_years),
		"ledger": [], "log": [],
		"version": 1, "status": "active", "origin": "", "bonuses": {},
		"perks": [], "perk_offer": [], "drafts": 0, "refreshes": 1,
		"seen_events": [], "active_event": "", "shipments": [],
		"village": 55.0, "guild": 40.0, "trust": 35.0,
		"actions": 2, "actions_used": [], "meta_snapshot": [],
		"history": [], "goals": {}, "result": {}, "first_immigrant": false,
		"first_survey": false, "trade_discount": 0.0, "run_id": "",
	}
