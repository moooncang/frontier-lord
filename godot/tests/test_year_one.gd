extends SceneTree
## 실행: godot --headless --path . -s tests/test_year_one.gd
## 기획서 10번 3절 첫 1년 식량 예제, 식량 보존, 예약 거부, 난수 테스트 벡터를 검사한다.

var fails := 0


func _init() -> void:
	_check_rng()
	var c := Content.load_all()
	var errors := Content.validate(c)
	_expect(errors.is_empty(), "콘텐츠 검증 " + str(errors))
	_check_year_one(c)
	_check_construction(c)
	_check_forecast(c)
	print("FAIL %d" % fails if fails > 0 else "OK")
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("실패: " + msg)


func _check_rng() -> void:
	var r := Xoshiro128.new(0)
	r.s = [1, 2, 3, 4]
	var got := []
	for i in 5:
		got.append(r.next_u32())
	_expect(got == [11520, 0, 5927040, 70819200, 2031721883], "xoshiro128** 참조 벡터 " + str(got))
	var seeded := Xoshiro128.new(12345, 0)
	got = [seeded.next_u32(), seeded.next_u32(), seeded.next_u32()]
	_expect(got == [518667457, 440444462, 4232892992], "시드 파생 벡터 " + str(got))
	var a := Xoshiro128.new(7, 2)
	var b := Xoshiro128.new(7, 2)
	_expect(a.next_u32() == b.next_u32(), "같은 시드·스트림 재현")


func _check_year_one(c: Dictionary) -> void:
	var s := RunState.new_run(c.charters.C01, 1)
	s.facilities["B13"] = 6 # 예제 가정: 농지 6구획, 인구 80 고정, 평년
	s.birth_rate = 0.0
	s.death_rate = 0.0
	var start := WeekSim.total_food(s)
	var lowest := INF
	var lowest_week := 0
	for i in 52:
		var r := WeekSim.process_week(s, c)
		var t := WeekSim.total_food(s)
		if t < lowest:
			lowest = t
			lowest_week = r.week
		if r.week == 20:
			s.facilities["B22"] = 1 # 21주부터 정식 곳간
	_expect(absf(WeekSim.total_food(s) - 2109.10) < 0.01, "연말 식량 %.2f (기대 2109.10)" % WeekSim.total_food(s))
	_expect(absf(lowest - 353.66) < 0.01 and lowest_week == 32, "최저 재고 %.2f @%d주 (기대 353.66 @32)" % [lowest, lowest_week])
	var delta := 0.0
	for e in s.ledger:
		if e.asset == "food":
			delta += e.qty
	_expect(absf(start + delta - WeekSim.total_food(s)) < 1e-6, "식량 보존: 원장 합계와 재고 불일치")
	_expect(s.resident.money == 8000 - 5440, "주민 현금 세금 5440동 납부, 잔액 %d" % s.resident.money)
	_expect(s.public.money > 17200 and s.public.money < 17440, "금고 %d (세수 5440 - 유지비)" % s.public.money)
	_expect(s.pop == 80 and s.famine_weeks == 0, "인구 80 유지, 기아 없음")
	_expect(s.week == 53 and WeekSim.week_of_year(s.week) == 1, "53번째 주는 2년 1주")


func _check_construction(c: Dictionary) -> void:
	var s := RunState.new_run(c.charters.C01, 2)
	s.assign.build = 4
	s.orders = ["B22", "B22", "B22"] # 석재 20으로는 2개만 가능, 셋째는 거부
	var money0: int = s.public.money
	var original := s.duplicate(true)
	var invalid := WeekSim.process_week(s, c)
	_expect(not invalid.advanced and s == original, "무효 주문 묶음은 주·재고·사업 모두 불변")
	s.orders = ["B22", "B22"]
	for i in 7:
		WeekSim.process_week(s, c)
	_expect(s.projects.size() == 1 and s.facilities.get("B22", 0) == 1, "B22 첫째 6주 완공·둘째 진행 중: %s" % str(s.projects))
	_expect(invalid.notes[0].contains("거부"), "셋째 주문은 자재 부족으로 거부")
	_expect(s.public.stone == 0 and s.public.wood == 40, "자재 차감 석재 %s 목재 %s" % [s.public.stone, s.public.wood])
	_expect(s.public.money < money0 - 1200, "금화 12금 지급 + 급여, 금고 %d" % s.public.money)


func _check_forecast(c: Dictionary) -> void:
	var s := RunState.new_run(c.charters.C01, 3)
	s.facilities["B13"] = 6
	var before := s.duplicate(true)
	var f := WeekSim.forecast(s, c, 13)
	_expect(s == before, "전망 계산은 원본 상태를 바꾸지 않음")
	_expect(f.lowest_week >= 1 and f.lowest_week <= 13 and f.lowest <= WeekSim.food_weeks(s), "전망 최저점은 13주 안, 현재 이하 (%.1f @%d)" % [f.lowest, f.lowest_week])
	for i in 13:
		WeekSim.process_week(s, c)
	_expect(absf(WeekSim.total_food(s) - f.food) < 0.01, "전망 13주 뒤 식량 %.1f = 실제 진행 %.1f" % [f.food, WeekSim.total_food(s)])
	_expect(WeekSim.farm_demand(s, 3) == 24 and WeekSim.farm_demand(s, 10) == 6 and WeekSim.farm_demand(s, 34) == 24 and WeekSim.farm_demand(s, 45) == 0, "농사 노동 수요 파종 24·생육 6·수확 24·겨울 0")
