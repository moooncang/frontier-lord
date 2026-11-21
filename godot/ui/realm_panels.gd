class_name RealmPanels
extends RefCounted
## 지도 옆의 짧은 운영 화면. 계산·지급은 규칙 모듈에 맡긴다.


static func overview(ui: Variant, parent: Node) -> void:
	ui._news_block(parent)
	ui._rule(parent)
	var crew: VBoxContainer = ui._box(parent)
	crew.name = "WorkcrewArea"
	ui._workcrew_panel(crew)
	ui._rule(parent)
	ui._last_week_block(parent)


static func office_plan(ui: Variant, parent: Node) -> void:
	var crew: VBoxContainer = ui._box(parent)
	crew.name = "WorkcrewArea"
	ui._workcrew_panel(crew)
	ui._rule(parent)
	var plan: Dictionary = CabinetActions.project_preview(ui.session)
	ui._heading(parent,"이번 주 공사")
	if plan.rows.is_empty():
		var advice: Dictionary = ui._focus_item()
		ui._label(parent,str(advice.title),19,GameTheme.MUTED)
		ui._button(parent,"건설 지구 확인",func(): ui._go("build"),false,"OfficeConstruction")
	else:
		var first: Dictionary = plan.rows[0]
		ui._label(parent,"%s · %s" % [first.name,first.eta_text],19)
		ui._label(parent,"이번 주 %d 작업 · 진행 %d곳" % [plan.work_this_week,plan.rows.size()],18,GameTheme.MUTED)
		ui._bar(parent,1.0-float(first.work_left)/maxf(1.0,float(first.work_total)))
		ui._button(parent,"공사 순서 확인",func(): ui._side("projects"),false,"OfficeConstruction")
	ui._office_extras(parent, 397.0 if plan.rows.is_empty() else 431.0)
	ui._spacer(parent)


static func construction(ui: Variant, parent: Node) -> void:
	var s: Dictionary = ui.session.state
	var box: VBoxContainer = ui._box(parent)
	box.name = "DevelopmentProcess"
	box.add_theme_constant_override("separation",8)
	var head: HBoxContainer = ui._row(box)
	ui._heading(head,"공사 %d / %d곳" % [s.orders.size()+s.projects.size(),RealmRules.project_limit(s,ui.session.content)])
	if ui.page != "build": ui._button(head,"현장으로",func(): ui._go("build"),false,"DevelopmentList")
	var plan: Dictionary = CabinetActions.project_preview(ui.session)
	if not str(plan.error).is_empty(): ui._label(box,str(plan.error),18,GameTheme.BAD)
	if plan.rows.is_empty():
		var advice: Dictionary = ui._focus_item()
		ui._heading(box,str(advice.title),false,GameTheme.TEAL)
		if advice.kind == "build":
			var offer: Dictionary = CabinetActions.offer(ui.session,str(advice.facility))
			ui._lot_art(box,str(advice.facility),72)
			ui._label(box,str(ui.session.content.facilities[advice.facility].get("effect",offer.benefit)),20)
			ui._cost_row(box,offer.cost)
			ui._label(box,str(offer.eta_text)+" 예상" if str(offer.error).is_empty() else str(offer.error),18,GameTheme.MUTED)
			ui._primary(ui._button(box,"개발할 현장 확인",func(): ui._open_build_lot(str(advice.facility)),false,"FocusAction"))
		else:
			ui._label(box,str(advice.body),19)
			ui._primary(ui._button(box,str(advice.action),func(): ui._go(str(advice.get("page","build"))),false,"FocusAction"))
		return
	ui._label(box,"위에서부터 작업 · 먼저 끝낼 공사를 고르세요",18,GameTheme.MUTED)
	for project in plan.rows:
		var line: HBoxContainer = ui._row(box)
		line.add_theme_constant_override("separation",6)
		var words: VBoxContainer = ui._box(line)
		words.add_theme_constant_override("separation",3)
		ui._label(words,"%d. %s" % [project.priority,project.name],19)
		ui._label(words,"이번 주 %d 작업 · %s" % [project.work_next,project.eta_text],17,GameTheme.GOOD if project.remaining_next == 0 else GameTheme.MUTED)
		ui._bar(words,1.0-float(project.work_left)/maxf(1,float(project.work_total)))
		var promote: Button = ui._button(line,"먼저",func(): ui._prioritize(project.kind,project.index),not project.can_promote or not ui._is_active(),"promote_%s_%d" % [project.kind,project.index])
		promote.add_theme_font_size_override("font_size",17)
		var cancel: Button = ui._button(line,"취소",func(): ui._cancel_site(project.kind,project.index),not ui._is_active(),"cancel_%s_%d" % [project.kind,project.index])
		cancel.add_theme_font_size_override("font_size",17)
		ui._rule(box)
	var scope: Label = ui._label(box,"이번 주 건설 %d명 · 총 %d 작업 예상" % [plan.build_workers,plan.work_this_week],18,GameTheme.TEAL)
	scope.tooltip_text = str(plan.scope)
	ui._button(box,"작업반 배정 바꾸기",func(): ui.side_page = "overview"; ui._go("estate"),false,"AdjustWorkcrew")


## 지난주 기록 가운데 책상에 덧붙여 보여 줄 줄. 완공은 따로 표시하므로 뺀다.
static func week_notes(ui: Variant) -> Array:
	var turn: Dictionary = ui.session.state.get("last_receipt", {})
	if not turn.get("valid", false): return []
	return turn.get("notes", []).filter(func(note): return not "완공" in str(note))


static func result_strip(ui: Variant, parent: Node) -> void:
	var box: VBoxContainer = ui._box(parent)
	box.name = "WeekResult"
	box.add_theme_constant_override("separation",4)
	var turn: Dictionary = ui.session.state.get("last_receipt",{})
	if not turn.get("valid",false):
		ui._heading(box,"첫 개발을 시작하세요").name = "FirstWeekInstruction"
		ui._label(box,"영지 둘러보기에서 농지를 고르고, 비용을 확인한 뒤 승인하세요.",18,GameTheme.MUTED)
		return
	var head: HBoxContainer = ui._row(box)
	ui._heading(head,"%d주 결과" % turn.week)
	var details: Button = ui._button(head,"결산 보기",ui._open_turn_report,false,"TurnDetails")
	details.add_theme_font_size_override("font_size",17)
	details.custom_minimum_size.y = 36
	var figures: HBoxContainer = ui._row(box)
	for asset in ["money","food","wood","stone","tools","fuel"]:
		for item in turn.resource_rows:
			if item.id != asset: continue
			if asset not in ["money","food"] and absf(float(item.delta)) < 0.5: continue
			var column: HBoxContainer = ui._row(figures)
			column.add_theme_constant_override("separation",6)
			var caption: Label = ui._label(column,item.label,18,GameTheme.MUTED)
			caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			caption.autowrap_mode = TextServer.AUTOWRAP_OFF
			var value: Label = ui._label(column,"%+.2f금" % (float(item.delta)/100.0) if asset == "money" else "%+.0f" % item.delta,24,GameTheme.GOOD if item.delta >= 0 else GameTheme.WARN)
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			value.add_theme_font_override("font",PixelTheme.heading_font())
	var feedback: Dictionary = RealmFeedback.weekly(ui.session.state,ui.session.content)
	var completed: Array = feedback.get("completed",[])
	if not completed.is_empty():
		var names: Array[String] = []
		for item in completed: names.append(str(item.name)+" ×%d" % item.count)
		var label: Label = ui._label(box,"완공 · "+" / ".join(names),18,GameTheme.GOOD)
		label.max_lines_visible = 1
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = " / ".join(names)
	elif feedback.get("promoted",false):
		ui._label(box,str(feedback.get("rank_name",""))+" 승격",18,GameTheme.GOOD)
	for note in week_notes(ui).slice(0, ui.desk_notes):
		var line: Label = ui._label(box,"· "+str(note),18,GameTheme.MUTED)
		line.max_lines_visible = 1
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.tooltip_text = str(note)


static func growth(ui: Variant, parent: Node) -> void:
	var s: Dictionary = ui.session.state
	var overview: Dictionary = CampaignDirector.overview(s,ui.session.content)
	if overview.enabled:
		ui._heading(parent,overview.season+" 목표 · %d주 평가" % overview.deadline)
		ui._label(parent,overview.objective.detail,21,GameTheme.GOOD if overview.met else GameTheme.TEXT)
		ui._bar(parent,float(overview.progress))
		ui._label(parent,"보상 · "+overview.reward_text,18,GameTheme.GOOD)
		ui._label(parent,"미달 · "+overview.penalty_text,17,GameTheme.WARN)
		if int(s.week) >= 27 and RealmRules.enabled(s):
			var weather: Dictionary = RealmRules.season_weather(s,ui.session.content,3)
			ui._label(parent,"겨울 예보 · "+str(weather.name),19,GameTheme.TEAL)
			ui._label(parent,str(weather.text),17,GameTheme.MUTED)
	ui._rule(parent)
	if not RealmRules.enabled(s):
		ui._button(parent,"연간 목표 확인",func(): ui._go("journey"))
		return
	var rank: Dictionary = RealmRules.rank_progress(s,ui.session.content)
	ui._heading(parent,"영지 등급 · "+rank.name)
	if rank.next == "":
		ui._label(parent,"최고 등급에 도달했습니다",20,GameTheme.GOOD)
		return
	ui._label(parent,str(rank.next)+" 승격 조건",20,GameTheme.TEAL)
	for condition in rank.checks:
		ui._label(parent,("● " if condition.done else "○ ")+str(condition.text),18,GameTheme.GOOD if condition.done else GameTheme.TEXT)
	var goal: Dictionary = ui.session.content.realm.ranks[int(rank.rank)+1]
	ui._label(parent,"승격 보상 · "+RealmRules.changes_text(goal.get("reward",{})),18,GameTheme.GOOD)
	if VillageRelics.enabled(s) and int(rank.rank) == 0: ui._label(parent,"첫 촌락 승격 · 성물 3개 중 1개 선택",18,GameTheme.TEAL)
	if rank.ready: ui._label(parent,"다음 주 진행 시 승격",18,GameTheme.GOOD)
	ui._button(parent,"계절 기록 · 연말 목표",func(): ui._go("journey"),false,"AllGoals")
	ui._rule(parent)
	RelicScreens.environments(ui,parent)
	if VillageRelics.enabled(s):
		ui._button(parent,"성물 세트 확인 · %d/3 장착" % s.realm.sanctuary.equipped.size(),func(): ui._go("sanctuary"),false,"GrowthRelics")
