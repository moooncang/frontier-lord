extends SceneTree
## 가문 강화 데이터의 참조·수치·미지원 효과를 게임 시작 전에 거절한다.

var checks := 0
var failures := 0
var source: Dictionary


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("HOUSE CONTENT FAIL: ", description)


func _reject(change: Callable, description: String) -> void:
	var data := source.duplicate(true)
	change.call(data.legacy)
	_check(not Content.validate(data).is_empty(), description)


func _run() -> void:
	source = Content.load_all()
	_check(Content.validate(source).is_empty(), "production catalogs validate together")
	_check(source.legacy.branches.size() == 6 and source.legacy.talents.size() == 48, "six branches and forty-eight new-tree nodes")
	var kinds := {"foundation":0,"choice":0,"doctrine":0}
	for item in source.legacy.talents.values(): kinds[item.kind] += 1
	_check(kinds == {"foundation":24,"choice":12,"doctrine":12}, "permanent stats, unlocks and selected doctrines are distinct")
	_check(source.progression.upgrades.size() == 8, "eight prior upgrades remain available")
	_reject(func(d): d.version = 1, "unsupported definition version")
	_reject(func(d): d.branches = [], "malformed branch list")
	_reject(func(d): d.talents = [], "malformed node list")
	_reject(func(d): d.talents.LF01 = [], "malformed node")
	_reject(func(d): d.branches.finance.talents.append("LF01"), "duplicate node in branch")
	_reject(func(d): d.branches.finance.talents.append("missing"), "missing referenced node")
	_reject(func(d): d.branches.finance.talents.erase("LF01"), "orphan node")
	_reject(func(d): d.talents.LF01.branch = "agriculture", "incorrect branch membership")
	_reject(func(d): d.talents.LF01.requires = "missing", "missing prerequisite")
	_reject(func(d): d.talents.LF01.requires = "LF04", "multi-node prerequisite cycle")
	_reject(func(d): d.talents.LF01.name = "", "empty display name")
	_reject(func(d): d.talents.LF01.kind = "hidden", "unimplemented kind")
	_reject(func(d): d.talents.LF01.tier = 0.5, "fractional tier")
	_reject(func(d): d.talents.LF01.max_rank = 4, "unsupported maximum rank")
	_reject(func(d): d.talents.LF01.costs = [2], "incomplete rank prices")
	_reject(func(d): d.talents.LF01.costs = [2,1,6], "decreasing price")
	_reject(func(d): d.talents.LF01.costs = [2,4.5,6], "fractional price")
	_reject(func(d): d.talents.LF01.costs = [2,-4,6], "negative price")
	_reject(func(d): d.talents.LF01.resources.money = 0.5, "fractional base currency")
	_reject(func(d): d.talents.LF01.resources.money = INF, "nonfinite resource")
	_reject(func(d): d.talents.LF01.resources.food = -1, "negative starting stock")
	_reject(func(d): d.talents.LF02.bonuses.maintenance = -0.5, "negative multiplier at max rank")
	_reject(func(d): d.talents.LF02.bonuses.build_work = -0.1, "unconsumed raw bonus key")
	_reject(func(d): d.talents.LF04.adds.unknown = 1, "unsupported additive effect")
	_reject(func(d): d.talents.LF05.choice.type = "free_gold", "unimplemented unlock")
	_reject(func(d): d.talents.LF05.choice.resources = {}, "empty support pack")
	_reject(func(d): d.talents.LF05.choice.resources.invalid = 1, "unsupported support resource")
	_reject(func(d): d.talents.LF05.resources.food = 10, "unapplied passive effects on an unlock")
	_reject(func(d): d.talents.LF06.choice.amount = 0, "zero-use unlock")
	_reject(func(d): d.talents.LF06.choice.amount = 1.5, "fractional unlock uses")
	_reject(func(d): d.talents.LF07.doctrine = [], "malformed doctrine")
	_reject(func(d): d.talents.LF07.doctrine.mods.maintenance = 0, "zero doctrine multiplier")
	_reject(func(d): d.talents.LF07.doctrine.mods.unknown = 1.2, "unconsumed doctrine effect")
	_reject(func(d): d.talents.LF07.doctrine.targets.mood = NAN, "nonfinite target modifier")
	_reject(func(d): d.talents.LF07.doctrine.targets.trust = 5, "unsupported realm target")
	_check(Content.validate(source).is_empty(), "corruption probes never mutate production definitions")
	print("HOUSE CONTENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
