extends "res://ui/steward_ui.gd"
## 무엇을 만들지와 사건의 손익만 직접 고른다. 노동·반복 접견은 맡긴다.

var desk_open := false
var all_projects := false
var detail_open := false
var supply_details := false
var all_advisors := false
var development_result: Dictionary = {}

func _changed(message: String) -> void:
	if _is_active() and CabinetRules.enabled(session.state): CabinetRules.reassign(session.state,session.content)
	super._changed(message)

func _advance(count: int) -> void:
	var before: Dictionary = session.state.get("facilities",{}).duplicate(true)
	var week := int(session.state.get("week",0))
	await super._advance(count)
	if int(session.state.week) != week:
		development_result.clear()
		for id in session.state.facilities:
			var gained := int(session.state.facilities[id]) - int(before.get(id,0))
			if gained > 0: development_result = {"id":id,"count":gained,"week":session.state.week}
		_render()

func _render() -> void:
	super._render()
	if desk_open and not is_instance_valid(current_modal): _desk_menu()

func _open_prepare() -> void:
	if _is_active() or load_blocked: return
	draft_seed = int(Time.get_unix_time_from_system()) & 0x7fffffff
	draft_region = "forest"
	draft_candidate = 0
	draft_relics = ["seeds", "axe"]
	_start()

func _start() -> void:
	if _is_active() or load_blocked: return
	session.start_run(draft_seed, "settler", {"region":draft_region,"candidate":draft_candidate,"relics":draft_relics,"tutorial":false,"cabinet":true})
	page = "estate"
	development_result.clear()
	scroll_positions.clear()
	_changed("첫 특전 하나를 고르세요.")

func _prepare(parent: Node) -> void:
	super._prepare(parent)
	for check in parent.find_children("*","CheckButton",true,false): check.queue_free()

func _continue() -> void:
	if _is_active() and not CabinetRules.enabled(session.state):
		CabinetRules.setup(session.state)
		if session.state.has("tutorial"): session.state.tutorial.enabled = false
		CabinetRules.reassign(session.state, session.content)
		if session.state.active_event == "EV01":
			session.state.seen_events.append("EV01")
			session.state.active_event = ""
		if not session.state.get("contract_offer", []).is_empty(): session.choose_contract("skip")
		_save()
	page = "estate" if _is_active() else "result"
	_render()

func _go(target: String) -> void:
	desk_open = false
	detail_open = false
	super._go(target)

func _reading_menu() -> void:
	super._reading_menu()
	var start_button := find_child("NewRun", true, false) as Button
	if start_button != null:
		start_button.text = "새 통치 시작"
		var box := start_button.get_parent()
		var setup := _button(box, "시작 조건 직접 설정", func():
			draft_seed = int(Time.get_unix_time_from_system()) & 0x7fffffff
			prepare_step = 0
			page = "prepare"
			_render()
		, false, "AdvancedStart")
		box.move_child(setup, start_button.get_index() + 1)

func _navigation() -> void:
	var holder := _paper(Rect2(44, 100, size.x - 88, 48), 0, Color.TRANSPARENT)
	holder.get_parent().name = "JournalTabs"
	var row := _row(holder)
	row.add_theme_constant_override("separation", 6)
	for entry in [["estate","이번 주"],["build","개발"],["boons","특전"]]:
		if session.state.is_empty(): continue
		var button := _button(row, entry[1], func(): _go(entry[0]), false, "nav_" + entry[0])
		button.custom_minimum_size.x = 132
		button.theme_type_variation = "NavigationButton"
		if page == entry[0]: button.add_theme_stylebox_override("normal", theme.get_stylebox("pressed", "NavigationButton"))
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(gap)
	var more := _button(row, "기록 · 관리", func(): desk_open = not desk_open; _render(), false, "MoreDesk")
	more.theme_type_variation = "NavigationButton"
	var menu := _button(row, "메뉴", func(): _go("menu"), false, "nav_menu")
	menu.theme_type_variation = "NavigationButton"

func _desk_menu() -> void:
	_shade(interface, .55)
	var box := _window("기록과 관리", Vector2(700, 520), false, true)
	current_modal = box.get_parent()
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var entries := [["world","영지 전경"],["trade","물자 구매"],["people","보좌관"],["journey","올해 목표"],["ledger","상세 장부"],["archive","가문 강화"]]
	for entry in entries:
		if session.state.is_empty() and entry[0] != "archive": continue
		var button := _button(grid, entry[1], func(): _go(entry[0]), false, "nav_" + entry[0])
		button.custom_minimum_size = Vector2(300, 54)
	_quiet(_button(box, "닫기", func(): desk_open = false; _render(), false, "CloseDesk"))

func _reading_header(rect: Rect2) -> void:
	var box := _paper(rect)
	box.get_parent().name = "StatusHeader"
	var row := _row(box)
	_heading(row, {"estate":"이번 주", "build":"무엇을 만들까요?", "trade":"물자 구매", "people":"보좌관에게 맡기기", "boons":"이번 통치의 특전", "ledger":"상세 장부", "journey":"겨울까지 준비할 것", "archive":"다음 통치 준비", "result":"이번 통치 결과", "world":"영지 전경"}.get(page,"영지"), true)
	var help := _quiet(_button(row, "도움말", _help, false, "HeaderHelp"))
	help.custom_minimum_size.y = 30

func _study_hud() -> void:
	var box := _paper(Rect2(30, 20, size.x - 60, 64), 12, TycoonTheme.NAV)
	box.get_parent().name = "EstateStatus"
	box.get_parent().add_theme_stylebox_override("panel", TycoonTheme.panel(TycoonTheme.NAV, Color("a87945"), 12))
	var row := _row(box)
	_heading(row, "영주 집무실", false, TycoonTheme.NAV_TEXT)
	if session.state.is_empty(): return
	var s := session.state
	for text in ["%s %d주" % [["봄","여름","가을","겨울"][mini(3,int((int(s.week)-1)/13))],mini(52,s.week)], "금고 " + _money(s.public.money), "식량 %.1f주" % WeekSim.food_weeks(s), "민심 %d" % s.mood]:
		_tag(row, text, TycoonTheme.NAV_TEXT, 21)

func _weekly_report(parent: Node) -> void:
	var s := session.state
	var results := _row(parent)
	results.name = "CabinetResults"
	if not receipt.is_empty():
		_label(results, "결정: " + receipt.choice, 20)
		_label(results, " · ".join(receipt.changes) if not receipt.changes.is_empty() else "적용 완료", 20, GameTheme.GOOD)
	elif not s.history.is_empty():
		_label(results, "%d주 결과" % s.history.back().week, 20, GameTheme.MUTED)
		var money_delta: float = brief.metrics.money.delta if brief.metrics.money.has_delta else float(last_turn.get("money", 0))
		var food_delta: float = brief.metrics.food.delta if brief.metrics.food.has_delta else float(last_turn.get("food", 0))
		if brief.metrics.money.has_delta or not last_turn.is_empty():
			_label(results, "금고 %+.2f금" % (money_delta / 100.0), 21)
			if int(s.get("cabinet",{}).get("news_week",-1)) == int(s.week):
				_label(results, s.cabinet.news, 20, GameTheme.GOOD)
			else: _label(results, "식량 %+.0f" % food_delta, 21)
		else: _label(results, "식량 생산 +%.0f · 소비 −%.0f" % [brief.report.food.production,brief.report.food.consumption], 20)
	else:
		_label(results, "첫 목표  ·  농지 4 → 6구획", 21, GameTheme.TEAL)
		_label(results, "시설을 고르면 인력은 자동으로 배치됩니다.", 19, GameTheme.MUTED)
	_rule(parent)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	var focus := _box(row, 2.1)
	focus.name = "CabinetFocus"
	var suggestion := _focus_item()
	var heading := _row(focus)
	_face(heading, "CH01", 64)
	var words := _box(heading)
	_label(words, "오딜의 보고", 18, GameTheme.MUTED)
	_heading(words, suggestion.title, true)
	_label(focus, suggestion.body, 22)
	if suggestion.kind == "build":
		var offer := CabinetActions.offer(session, suggestion.facility)
		_label(focus, "%s · %s" % [_money(offer.cost.money),offer.eta_text], 21, GameTheme.TEAL)
		_label(focus, _materials(offer.cost), 18, GameTheme.MUTED)
		var button := _button(focus, suggestion.action, func(): _command_build(suggestion.facility), offer.error != "", "FocusAction")
		_primary(button)
		if offer.error != "": _label(focus, offer.error, 18, GameTheme.WARN)
	else:
		_primary(_button(focus, suggestion.action, func(): _go(suggestion.page), false, "FocusAction"))
	row.add_child(VSeparator.new())
	var side := _box(row, 1.0)
	side.custom_minimum_size.x = 300
	side.name = "CabinetProjects"
	_project_status(side)
	var actions := _row(side)
	_quiet(_button(actions, "물자 구매", func(): _go("trade"), false, "QuickSupplies"))
	_quiet(_button(actions, "자세히", func(): _go("journey"), false, "MoreReport"))

func _focus_item() -> Dictionary:
	var s := session.state
	for issue in brief.priorities:
		if issue.severity != "danger": continue
		var body: String = {"food_critical":"구매한 식량은 2주 뒤 도착합니다.","orders_blocked":"예약을 취소하거나 부족한 자재를 구매하세요.","cash_shortfall":"현재 계획을 유지하면 이번 주 비용을 내지 못합니다.","heating_critical":"장작을 구매해 겨울 난방을 보충하세요."}.get(issue.id,"공사와 물자 상태를 확인하세요.")
		return {"kind":"page","title":issue.title,"body":body,"action":issue.action,"page":issue.page}
	if not s.orders.is_empty() or not s.projects.is_empty():
		return {"kind":"page","title":"공사를 진행하고 있습니다", "body":"작업 인력은 자동으로 배치합니다.\n한 주를 진행하면 공사가 진척됩니다.","action":"공사 확인","page":"build"}
	if s.facilities.get("B13",0) < 6:
		var count := clampi(6 - int(s.facilities.get("B13",0)),1,2)
		var timing := "3주 파종 전에 완공하면 올해 수확이 늘어납니다." if int(s.week) < 3 else "올해 파종은 끝났지만, 겨울 평가에는 6구획이 필요합니다."
		return {"kind":"build","title":"농지를 넓힙시다", "body":"농지 %d구획을 늘립니다.\n" % count + timing,"action":"농지 확대 시작","facility":"B13"}
	if s.facilities.get("B22",0) < 1:
		return {"kind":"build","title":"수확물을 담을 곳간이 필요합니다", "body":"곳간은 식량 보관량을 늘리고\n보관 중 사라지는 식량을 줄입니다.","action":"곡물 곳간 건설","facility":"B22"}
	if int(s.week) >= 27 and s.public.fuel < s.pop:
		return {"kind":"page","title":"겨울 장작을 준비하세요", "body":"겨울은 40주부터 시작됩니다.\n벌목소에서 생산하거나 물자를 구매하세요.","action":"장작 구매","page":"trade"}
	return {"kind":"page","title":"다음 개발을 고를 수 있습니다", "body":"식량 생산을 늘릴지, 자재를 확보할지\n필요한 시설 하나를 선택하세요.","action":"개발 고르기","page":"build"}

func _project_status(parent: Node) -> void:
	var s := session.state
	var work: int = int(brief.construction.remaining_work)
	if work > 0:
		_heading(parent, "진행 중인 개발")
		var id: String = s.orders[0] if not s.orders.is_empty() else s.projects[0].id
		_building_art(parent, id, 72)
		_label(parent, session.content.facilities[id].name, 21)
		var total := work
		for p in s.projects: total += int(p.work_total - p.work_left)
		var current_project: Dictionary = s.get("cabinet",{}).get("project",{})
		if not current_project.is_empty() and current_project.id == id: total = maxi(work,int(current_project.total_work))
		_bar(parent, 1.0 - float(work) / maxf(1,total))
		var count: int = s.orders.count(id)
		for p in s.projects:
			if p.id == id: count += 1
		var preview := CabinetActions._completion(session,id,count)
		_label(parent, "완공까지 " + preview.text if preview.eta > 0 else "농사 우선으로 공사가 대기할 수 있습니다.", 19)
	elif not development_result.is_empty() and int(development_result.week) == int(s.week):
		_heading(parent, "완공했습니다", false, GameTheme.GOOD)
		_building_art(parent,development_result.id,80)
		_label(parent, "%s +%d" % [session.content.facilities[development_result.id].name,development_result.count],22)
	else:
		_heading(parent, "겨울 준비")
		for text in ["농지 %d / 6구획" % s.facilities.get("B13",0),"곳간 %d / 1개" % s.facilities.get("B22",0),"비축 %.1f / 13주" % (WeekSim.total_food(s) / maxf(1,s.pop))]: _label(parent,text,22)
		if ChronicleRules.active(s):
			var warning := _label(parent,{"frost":"겨울 장작 소비 +50%","rot":"40주에 식량 15% 소실","audit":"40주에 공납 20금"}.get(s.trial,""),18,GameTheme.WARN)
			warning.tooltip_text = session.content.chronicle.trials[s.trial].description
	if not s.shipments.is_empty():
		var shipment: Dictionary = s.shipments[0]
		_label(parent, "%d주에 %s 도착" % [shipment.arrival,RESOURCES[shipment.asset]], 18, GameTheme.TEAL)

func _materials(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in ["wood","stone","tools"]:
		if cost.get(id,0) > 0: parts.append("%s %d" % [RESOURCES[id],cost[id]])
	return " · ".join(parts)

func _building_art(parent: Node, id: String, extent: int = 80) -> void:
	for building in EstateBoard.BUILDINGS:
		if building[0] != id: continue
		var art := TextureRect.new()
		art.texture = assets.texture("building_" + building[1])
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(extent,extent)
		art.mouse_filter = MOUSE_FILTER_IGNORE
		parent.add_child(art)

func _development(parent: Node) -> void:
	var s := session.state
	if not s.orders.is_empty() or not s.projects.is_empty():
		var row := _row(parent)
		var project := _box(row)
		_project_status(project)
		var notes := _box(row)
		_heading(notes,"완공되면 다음 개발을 선택합니다")
		_label(notes,"건설 인력은 자동 배치됩니다.",22)
		_primary(_button(notes,"한 주 진행",func(): _advance(1),busy,"ProjectAdvance"))
		_quiet(_button(notes,"공사 상세 · 취소",func(): detail_open = not detail_open; _render(),false,"ProjectDetails"))
		if detail_open: _construction_queue(_scroll(parent))
		return
	var options: Array = ["B13","B22","B25"]
	if int(s.facilities.get("B13",0)) >= 6: options[0] = "B17" if s.facilities.get("B17",0) < 2 else "B14"
	if int(s.facilities.get("B22",0)) > 0: options[1] = "B01" if WeekSim.capacity(s,session.content,"housing") < s.pop + 12 else "B06"
	if int(s.facilities.get("B25",0)) > 0: options[2] = "B27"
	var top := _row(parent)
	_label(top, "개발 하나를 고르세요. 인력은 자동으로 배치합니다.",20)
	_quiet(_button(top,"추천만 보기" if all_projects else "모든 시설",func(): all_projects = not all_projects; _render(),false,"AllProjects"))
	if all_projects:
		options = []
		for id in session.content.facilities:
			var listed: Dictionary = session.content.facilities[id]
			if listed.grade != "T" and (RealmRules.enabled(s) or not listed.get("realm", false)): options.append(id)
	var area: Node = _scroll(parent) if all_projects else parent
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	area.add_child(grid)
	for id in options:
		var offer := CabinetActions.offer(session,id)
		var card := _card(grid)
		card.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
		var head := _row(card)
		_heading(head,offer.name)
		_building_art(head,id,64)
		_label(card,offer.benefit,20)
		_label(card,"%s · %s" % [_money(offer.cost.money),offer.eta_text],21,GameTheme.TEAL)
		_label(card,_materials(offer.cost),18,GameTheme.MUTED)
		var start := _button(card,"건설",func(): _command_build(id),offer.error != "","build_" + id)
		_primary(start)
		start.tooltip_text = "목재 %d · 석재 %d · 도구 %d" % [offer.cost.wood,offer.cost.stone,offer.cost.tools]
		if offer.error != "": _label(card,offer.error,18,GameTheme.WARN)

func _command_build(id: String) -> void:
	var error := CabinetActions.start_project(session,id)
	if error != "": _message(error); return
	page = "estate"
	receipt.clear()
	_changed("개발을 시작합니다. 다음 주부터 비용과 작업을 적용합니다.")

func _reading_market(parent: Node) -> void:
	var top := _row(parent)
	_label(top,"지금 결제 · 2주 뒤 도착",21)
	_quiet(_button(top,"묶음 주문" if supply_details else "수량 직접 정하기",func(): supply_details = not supply_details; _render(),false,"SupplyDetails"))
	if supply_details:
		StewardScreens.market(self,parent)
		return
	var area := _scroll(parent)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	area.add_child(grid)
	for package in CabinetActions.supplies(session):
		var card := _card(grid)
		_heading(card,package.title)
		_label(card,"%d개 · %d주 도착" % [package.quantity,package.arrival],20)
		var buy := _button(card,"구매 " + _money(package.price),func():
			var error := CabinetActions.buy_supply(session,package.asset)
			if error == "": _changed("%s %d개 주문 · %d주 도착" % [RESOURCES[package.asset],package.quantity,package.arrival])
			else: _message(error)
		,package.error != "","supply_" + package.asset)
		_primary(buy)
		if package.error != "": _label(card,package.error,18,GameTheme.WARN)

func _people(parent: Node) -> void:
	var s := session.state
	var top := _row(parent)
	var selected: String = s.get("cabinet",{}).get("advisor","CH01")
	_label(top,"한 명을 선임하면 매주 자동으로 도움을 받습니다.",20)
	_quiet(_button(top,"추천 인물" if all_advisors else "모든 인물",func(): all_advisors = not all_advisors; _render(),false,"AllAdvisors"))
	var area := _scroll(parent)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	area.add_child(grid)
	var ids: Array = session.content.chronicle.characters.keys() if all_advisors else [selected,"CH09","CH12"]
	var shown: Array = []
	for id in ids:
		if id in shown: continue
		shown.append(id)
		var person: Dictionary = session.content.chronicle.characters[id]
		var card := _card(grid)
		var head := _row(card)
		_face(head,id,56)
		_heading(head,person.name)
		var gain: float = person.value + (WeekSim.bonus(s,"trust",0) if person.effect == "trust" else 0)
		_label(card,"매주 %s +%.0f" % [StewardScreens.EFFECT_NAMES.get(person.effect,person.effect),gain],22,GameTheme.TEAL)
		_label(card,"최대 100 · 주 진행 시 적용",18,GameTheme.MUTED)
		_primary(_button(card,"맡기는 중" if selected == id else "맡기기",func():
			var error := CabinetActions.set_advisor(session,id)
			if error == "": _changed(person.name + "에게 맡겼습니다.")
			else: _message(error)
		,selected == id,"advisor_" + id))

func _boons(parent: Node) -> void:
	var top := _row(parent)
	_label(top,_next_reward_text(),20,GameTheme.TEAL)
	_quiet(_button(top,"특전만 보기" if detail_open else "특성 · 조합 자세히",func(): detail_open = not detail_open; _render(),false,"BoonDetails"))
	if detail_open:
		StewardScreens.boons(self,parent)
		return
	var area := _scroll(parent)
	for id in session.state.perks:
		var perk: Dictionary = session.content.progression.perks[id]
		var row := _row(area)
		_heading(row,perk.name)
		_label(row,ConciseCopy.perk_brief(id,perk),22,GameTheme.TEAL)
		_rule(area)

func _decision_popup() -> void:
	_shade(interface,.72).name = "DecisionBlocker"
	var s := session.state
	var box := _window("특전 하나를 고르세요" if not s.perk_offer.is_empty() else "영주님의 결정",Vector2(minf(1060,size.x-90),minf(550,size.y-80)),false,true)
	current_modal = box.get_parent()
	if not s.perk_offer.is_empty(): _perk_choices(box)
	elif s.active_event != "": _event_choices(box)
	else: _contract_choices(box)
	_quiet(_button(box,"영지 상태 확인",func(): decision_hidden = true; _render(),false,"InspectEstate"))
	_focus_decision.call_deferred()

func _perk_choices(parent: Node) -> void:
	var counts := ChronicleRules.family_counts(session.content,session.state)
	var row := _row(parent)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	for id in session.state.perk_offer:
		var perk: Dictionary = session.content.progression.perks[id]
		var card := _card(row)
		_heading(card,perk.name)
		_label(card,ConciseCopy.perk_brief(id,perk),22,GameTheme.TEAL)
		var family: Dictionary = session.content.chronicle.families[perk.family]
		_label(card,"%s %d → %d개" % [family.name,counts[perk.family],counts[perk.family]+1],18,GameTheme.MUTED)
		if counts[perk.family] in [1,3]: _label(card,"선택하면 특전 세트 효과 발동",18,GameTheme.GOOD)
		var gap := Control.new()
		gap.size_flags_vertical = SIZE_EXPAND_FILL
		card.add_child(gap)
		_primary(_button(card,"선택",func(): session.choose_perk(id); _changed(perk.name + " 적용"),false,"perk_" + id))
	_quiet(_button(parent,"후보 새로고침 · %d회 남음" % session.state.refreshes,func(): session.refresh_perks(); _changed("후보를 바꿨습니다."),session.state.refreshes <= 0,"RefreshPerks"))

func _event_choices(parent: Node) -> void:
	var id: String = session.state.active_event
	var event: Dictionary = RealmRules.event_definition(session.state,session.content,id)
	var copy := ConciseCopy.event_brief(id,event)
	var top := _row(parent)
	_face(top,event.get("portrait","CH01"),56)
	var words := _box(top)
	_heading(words,copy.title)
	_label(words,copy.body,22)
	var choices := _scroll(parent)
	for i in event.options.size():
		var option: Dictionary = event.options[i]
		var row := _row(choices)
		var explanation := _box(row)
		_heading(explanation,copy.options[i].label)
		var cost := session.event_cost(option)
		_label(explanation,("비용 " + _resources_text(cost) + "  →  " if not cost.is_empty() else "") + copy.options[i].effect,20,GameTheme.TEAL)
		var error := session.option_error(option)
		_primary(_button(row,"결정",func(): _resolve(i),error != "","event_option_%d" % i))
		if error != "": _label(explanation,error,18,GameTheme.WARN)
		_rule(choices)

func _reading_footer(rect: Rect2) -> void:
	var box := _paper(rect)
	var row := _row(box)
	report_status = _label(row,notice if notice != "저장 완료" else "자동 저장됨",18,GameTheme.MUTED)
	report_status.max_lines_visible = 1
	notice_label = report_status
	if _is_active():
		_primary(_button(row,"결정 확인" if _pending() else "다음 주  →",_open_decision if _pending() else func(): _advance(1),busy,"NextWeek"))
	else: _quiet(_button(row,"메인 메뉴",func(): _go("menu")))

func _help_popup() -> void:
	_shade(interface,.72)
	var box := _window("플레이 방법",Vector2(780,480),false,true)
	current_modal = box.get_parent()
	_heading(box,"1  특전 하나를 고릅니다")
	_label(box,"특전은 이번 통치의 생산과 비용을 바꿉니다.",21)
	_heading(box,"2  필요한 개발을 고릅니다")
	_label(box,"노동 배치는 자동입니다. 첫 개발은 농지 2구획 확대입니다.",21)
	_heading(box,"3  다음 주로 진행합니다")
	_label(box,"공사와 생산이 진행됩니다. 사건이 생기면 손익을 비교해 결정하세요.",21)
	_label(box,"Space 다음 주 · F 결정 확인 · Esc 닫기",18,GameTheme.MUTED)
	_primary(_button(box,"닫기",func(): help_open=false; _render(),false,"CloseHelp"))

func _input(event: InputEvent) -> void:
	if _handle_quit_input(event): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and desk_open:
		desk_open = false
		_render()
		get_viewport().set_input_as_handled()
		return
	super._input(event)
