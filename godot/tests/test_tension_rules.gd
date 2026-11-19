extends SceneTree
## 2026-11-19 긴장·지역·인물 규칙 검사: 수확 배율, 왕실 신임과 해임, 지역별 계절 목표, 사람들의 기억.
## 실행: godot --headless --path . -s tests/test_tension_rules.gd

var failures := 0
var assertions := 0
var content: Dictionary

const CONFIG := {"region":"forest", "candidate":0, "relics":[], "tutorial":false, "cabinet":true, "campaign":true, "workcrew":true,
	"realm":true, "village_relics":true, "modifiers":true, "escalation":true, "mandate":true, "regional":true, "people":true}


func _init() -> void:
	content = Content.load_all()
	_check(Content.validate(content).is_empty(), "content validation " + str(Content.validate(content)))
	_test_balance()
	_test_regions()
	_test_mandate()
	_test_people()
	print("TENSION RULES: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		print("TENSION FAIL: " + label)


func _new(region: String = "forest", extra: Dictionary = {}) -> GameSession:
	var game := GameSession.new(content)
	var config := CONFIG.duplicate(true)
	config.region = region
	for key in extra: config[key] = extra[key]
	game.start_run(61427, "settler", config)
	if not game.state.perk_offer.is_empty(): game.choose_perk(str(game.state.perk_offer[0]))
	return game


func _test_balance() -> void:
	var game := _new()
	_check(is_equal_approx(float(content.campaign.balance.harvest), 0.45) and is_equal_approx(float(game.state.campaign.balance.gather), 0.45), "new runs start on the 45% frontier")
	_check(SaveStore.valid(game.bundle()), "a fresh run with every new rule is saveable")
	game.state.campaign.balance = {"harvest":0.55, "gather":0.55}
	_check(CampaignDirector.valid(game.state, content), "a run started on the old 55% balance still loads")
	game.state.campaign.balance = {"harvest":0.7, "gather":0.7}
	_check(not CampaignDirector.valid(game.state, content), "an unknown balance is rejected")
	_check(is_equal_approx(float(content.realm.event.chance), 0.35), "events arrive less often")


func _test_regions() -> void:
	var forest := _new("forest")
	var river := _new("river")
	var highland := _new("highland")
	var plain := _new("river", {"regional":false})
	_check(CampaignDirector.overview(forest.state, content).title == "농지 6구획 확보", "the forest keeps the classic spring goal")
	_check(CampaignDirector.overview(river.state, content).objective.detail.contains("곡물 곳간"), "the river spring goal is the granary")
	_check(CampaignDirector.overview(highland.state, content).objective.target == 2.0, "the highland spring goal needs two facilities")
	_check(CampaignDirector.overview(plain.state, content).title == "농지 6구획 확보" and not plain.state.campaign.has("regional"), "without the flag every region keeps the shared goals")
	_check(is_equal_approx(WeekSim.raw_bonus(highland.state, "sell"), 1.3) and is_equal_approx(WeekSim.raw_bonus(plain.state, "sell"), 1.0), "only the regional highland sells at a premium")
	_check(WeekSim.raw_bonus(river.state, "buy") < WeekSim.raw_bonus(plain.state, "buy"), "the regional river buys cheaper than before")
	highland.state.facilities["B25"] = 1
	_check(CampaignDirector.overview(highland.state, content).objective.current == 1.0 and not CampaignDirector.overview(highland.state, content).met, "one of two facilities is half the goal")
	highland.state.facilities["B27"] = 1
	_check(CampaignDirector.overview(highland.state, content).met, "both facilities meet the goal")
	_check(CampaignDirector.region_view(content, "river").goals.size() == 2 and CampaignDirector.region_view(content, "river").hint != "", "the setup screen can describe a region")
	_check(SaveStore.valid(river.bundle()) and SaveStore.valid(highland.bundle()), "regional runs are saveable")


func _test_mandate() -> void:
	var game := _new()
	_check(MandateRules.enabled(game.state) and int(game.state.mandate.value) == 3, "a new lord starts with three points of royal trust")
	_check(not MandateRules.enabled(_new("forest", {"mandate":false}).state), "the mandate is off without its flag")
	var before: Dictionary = game.state.duplicate(true)
	game.state.campaign.records.append({"index":0, "season":"봄", "success":false})
	var report := {"advanced":true, "week":13, "notes":[]}
	MandateRules.after_week(before, game.state, content, report)
	_check(int(game.state.mandate.value) == 2 and report.notes.size() == 1 and str(report.notes[0]).contains("봄 목표 미달"), "a missed season goal costs one point and says why")
	before = game.state.duplicate(true)
	game.state.campaign.records.append({"index":1, "season":"여름", "success":true})
	MandateRules.after_week(before, game.state, content, {"advanced":true, "week":26, "notes":[]})
	_check(int(game.state.mandate.value) == 2, "a met goal costs nothing")
	before = game.state.duplicate(true)
	game.state.escalation.records.append({"name":"시험 위기", "success":false})
	game.state.campaign.records.append({"index":2, "season":"가을", "success":false})
	MandateRules.after_week(before, game.state, content, {"advanced":true, "week":39, "notes":[]})
	_check(int(game.state.mandate.value) == 0 and MandateRules.dismissed(game.state), "a failed crisis and a missed goal in one week exhaust the trust")
	_check(MandateRules.valid(game.state), "the mandate log accounts for every lost point")
	game.state.mandate.value = 5
	_check(not MandateRules.valid(game.state), "trust above its maximum is rejected")
	# 실제 주 진행: 신임이 바닥난 주에 통치가 해임으로 끝난다
	var run := _new()
	run.state.mandate.value = 0
	run.state.mandate.log.append({"week":1, "lost":3, "text":"시험"})
	if run.state.active_event != "": run.choose_event(0)
	var outcome := run.advance()
	_check(outcome.advanced and run.state.status == "finalized" and str(run.state.result.reason) == "해임" and not run.state.result.success, "a lord without trust is dismissed mid-reign")


func _test_people() -> void:
	var game := _new()
	var s := game.state
	var raid: Dictionary = content.events["RV_RAID"]
	var road: Dictionary = content.events["EV03"]
	_check(PeopleRules.enabled(s) and not PeopleRules.enabled(_new("forest", {"people":false}).state), "people remember only when the flag is on")
	_check(PeopleRules.stance(raid, 0) == 1 and PeopleRules.stance(road, 0) == 1 and PeopleRules.stance(road, 1) == -1, "paying a cost helps; taking the free last option refuses")
	_check(PeopleRules.stance({"portrait":"CH01", "options":[{"effects":{"mood":1}}, {"effects":{"trust":1}}]}, 1) == 0, "an event with no costly path leaves no grudge")
	var who := str(road.portrait)
	var person: Dictionary = content.chronicle.characters[who]
	PeopleRules.record(s, content, road, 1)
	var seen := PeopleRules.view(s, content, who)
	_check(seen.known and int(seen.regard) == -1 and str(seen.memory).contains(str(road.title)) and str(seen.memory).contains("물리치"), "a refusal is remembered by name")
	_check(PeopleRules.stance_text(s, content, road, 1).contains("등을 돌립니다") and PeopleRules.stance_text(s, content, road, 0).contains("호의"), "the next answer is announced before it is given")
	PeopleRules.record(s, content, road, 1)
	_check(s.people.pending.size() == 1 and s.people.pending[0].kind == "grudge" and int(s.people.regard[who]) == 0, "two refusals turn into a grudge and the count starts over")
	var held := float(s[person.effect])
	var report := {"advanced":true, "week":1, "notes":[]}
	PeopleRules.after_week(s, content, report)
	_check(is_equal_approx(float(s[person.effect]), clampf(held - float(person.value) * 2.0, 0, 100)) and s.people.pending.is_empty() and report.notes.size() == 1, "the grudge is paid in that person's own field")
	PeopleRules.record(s, content, raid, 0)
	PeopleRules.record(s, content, raid, 0)
	held = float(s[content.chronicle.characters[raid.portrait].effect])
	PeopleRules.after_week(s, content, {"advanced":true, "week":2, "notes":[]})
	_check(float(s[content.chronicle.characters[raid.portrait].effect]) > held and int(s.people.tally.favor) == 1 and int(s.people.tally.grudge) == 1, "two favours are repaid")
	_check(PeopleRules.court(s, content, 4).size() == 2 and PeopleRules.valid(s, content) and SaveStore.valid(game.bundle()), "the court lists who was met and the state is saveable")
	s.people.regard[who] = 9
	_check(not PeopleRules.valid(s, content), "an impossible regard is rejected")
