extends "res://tests/test_realm_playflow.gd"
## Positive/adverse event decisions use the production popup, pointer input and isolated saves.

var baseline: Dictionary


func _shot(tag: String) -> void:
	await _frames(8)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty(), "rendered event expansion " + tag)
	if picture != null and not picture.is_empty():
		_check(picture.save_png("res://tests/output/event_expansion_" + tag + ".png") == OK, "saved event expansion " + tag)


func _fixture(id: String) -> void:
	screen.session.state = baseline.duplicate(true)
	var state: Dictionary = screen.session.state
	var event: Dictionary = screen.session.content.events[id]
	state.week = int(event.get("pool", {}).get("min", 12))
	state.active_event = id
	for asset in ["money", "food", "wood", "stone", "tools", "fuel"]: state.public[asset] = 1000
	state.public.money = 50000
	state.realm.queue = []
	state.realm.outcome = {}
	screen.page = "estate"
	screen.outcome_open = false
	screen.decision_hidden = false
	RealmRules.refresh(state, screen.session.content)
	screen._render()
	await _frames()
	_check(_inside(_control("EventTone")), "event classification stays above scrolling choices")
	_check(_inside(_control("InspectEstate")), "estate inspection remains reachable")


func _candidate(prefix: String, mode: String) -> Dictionary:
	for id in screen.session.content.events:
		if not str(id).begins_with(prefix): continue
		var event: Dictionary = screen.session.content.events[id]
		if not event.has("pool"): continue
		for index in event.options.size():
			var option: Dictionary = event.options[index]
			if mode == "relic" and option.get("requires", {}).has("relic_family"): return {"id":id, "index":index}
			if mode == "followup" and option.has("followup"): return {"id":id, "index":index}
			if mode == "chance" and option.has("chance"): return {"id":id, "index":index}
	return {}


func _relic_choice(prefix: String, resolution: Vector2i) -> void:
	root.size = resolution
	var selected := _candidate(prefix, "relic")
	if not _check(not selected.is_empty(), "content includes a relic response " + prefix): return
	await _fixture(selected.id)
	var option: Dictionary = screen.session.content.events[selected.id].options[selected.index]
	var category: String = option.requires.relic_family
	var id := "event_option_%d" % selected.index
	await _reveal(id)
	_check((_control(id) as BaseButton).disabled, "missing equipped relic disables response")
	_check(_text(screen.current_modal).contains("성물을 성소에 장착"), "locked relic response explains how to unlock")
	_check(_text(_control("EventTone")) == ("좋은 소식" if prefix == "RG_" else "문제 발생"), "classification uses words, not only color")
	for index in screen.session.content.events[selected.id].options.size():
		_check(_inside(_control("event_option_%d" % index)), "all three ordinary event choices fit without scrolling at %dp" % resolution.y)
	await _shot("%s_locked_%d" % [prefix.to_lower(), resolution.y])
	var relic := ""
	for key in screen.session.content.village_relics.relics:
		if screen.session.content.village_relics.relics[key].category == category: relic = str(key); break
	screen.session.state.realm.sanctuary.owned.append(relic)
	_check(screen.session.option_error(option) != "", "ownership alone does not unlock equipped relic response")
	_check(screen.session.equip_relic(relic) == "", "real relic equipment operation succeeds")
	screen._render()
	await _frames()
	await _reveal(id)
	_check(_visible("EventRequirement_%d" % selected.index), "unlocked response names the equipped relic family")
	_check(_inside(_control(id)), "unlocked relic decision can be clicked at viewport size")
	await _shot("%s_unlocked_%d" % [prefix.to_lower(), resolution.y])
	await _click(id)
	_check(screen.session.state.active_event == "" and _visible("AcknowledgeOutcome"), "real click resolves the event exactly once")
	_check(str(screen.session.state.realm.outcome.event) == str(selected.id), "result identifies the chosen event")
	_check(SaveStore.valid(screen.session.bundle()), "event result remains save-valid")
	var saved: Dictionary = SaveStore.new(screen.store.directory).read()
	_check(saved.ok and saved.bundle.state.realm.outcome.event == selected.id, "actual autosave contains resolved event")
	await _click("AcknowledgeOutcome")


func _followup_choice() -> void:
	root.size = Vector2i(1280, 720)
	var selected := _candidate("RG_", "followup")
	if not _check(not selected.is_empty(), "content contains followup investment"): return
	await _fixture(selected.id)
	var option: Dictionary = screen.session.content.events[selected.id].options[selected.index]
	var due := int(screen.session.state.week) + int(option.followup.delay)
	var next_title: String = screen.session.content.events[option.followup.id].title
	var id := "event_option_%d" % selected.index
	await _reveal(id)
	_check(_text(_control("EventFollowup_%d" % selected.index)).contains(next_title), "decision names the real queued event")
	_check(_text(_control("EventFollowup_%d" % selected.index)).contains("(%d주)" % due), "decision shows arrival week before paying")
	await _shot("followup_before_720")
	await _click(id)
	_check(screen.session.state.realm.queue.size() == 1 and screen.session.state.realm.queue[0].week == due, "pointer decision queues one real followup")
	_check(_inside(_control("OutcomeFollowup")) and _text(_control("OutcomeFollowup")).contains(next_title), "result retains scheduled report and its date")
	await _shot("followup_result_720")
	var saved: Dictionary = SaveStore.new(screen.store.directory).read()
	_check(saved.ok and saved.bundle.state.realm.queue[0].id == option.followup.id, "followup persists in actual autosave")
	await _click("AcknowledgeOutcome")


func _adverse_fallback() -> void:
	var selected := _candidate("RB_", "chance")
	if not _check(not selected.is_empty(), "adverse event offers a visible risk"): return
	await _fixture(selected.id)
	var event: Dictionary = screen.session.content.events[selected.id]
	await _reveal("event_option_%d" % selected.index)
	_check(_text(screen.current_modal).contains("성공 확률") and _text(screen.current_modal).contains("실패 ·"), "risk displays probability and both results")
	await _shot("risk_720")
	for asset in ["money", "food", "wood", "stone", "tools", "fuel"]: screen.session.state.public[asset] = 0
	screen._render()
	await _frames()
	var fallback := -1
	for index in event.options.size():
		var option: Dictionary = event.options[index]
		if option.get("cost", {}).is_empty() and option.get("requires", {}).is_empty() and not option.has("chance") and not option.has("requires_housing"): fallback = index; break
	if not _check(fallback >= 0, "bankrupt player has a deterministic response"): return
	await _reveal("event_option_%d" % fallback)
	await _click("event_option_%d" % fallback)
	_check(screen.session.state.active_event == "" and SaveStore.valid(screen.session.bundle()), "free loss response resolves without negative resources")
	await _click("AcknowledgeOutcome")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _fresh("event_expansion")
	await _start(false)
	await _settle()
	baseline = screen.session.state.duplicate(true)
	_check(screen.session.content.events.size() == 196 and screen.session.content.events.values().filter(func(event): return event.get("fantasy_only",false)).size() == 30, "production preserves 166 events and adds all 30 fantasy events")
	await _relic_choice("RG_", Vector2i(1280, 720))
	await _relic_choice("RB_", Vector2i(1440, 900))
	await _followup_choice()
	await _adverse_fallback()
	screen.queue_free()
	await _frames()
	print("EVENT EXPANSION UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
