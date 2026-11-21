class_name OperatingDashboard
extends RefCounted
## 운영 페이지의 작업영역과 가로 결과 띠. 실제 명령과 상태 변경은 기존 화면에 위임한다.


static func render(ui: Variant) -> void:
	var workspace: VBoxContainer = ui._plate(Rect2(28,170,ui.size.x-56,ui.size.y-386),false,18)
	workspace.name = "OperatingWorkspace"
	workspace.add_theme_constant_override("separation",0)
	var columns: HBoxContainer = ui._row(workspace)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",24)
	var project: VBoxContainer = ui._box(columns,1.65)
	project.name = "DevelopmentProcess"
	project.add_theme_constant_override("separation",6)
	_project(ui,project)
	var divider := VSeparator.new()
	columns.add_child(divider)
	var crew: VBoxContainer = ui._box(columns,1.0)
	crew.name = "WorkcrewArea"
	crew.add_theme_constant_override("separation",8)
	if ui.has_method("_workcrew_panel"): ui._workcrew_panel(crew)
	_result(ui,ui._plate(Rect2(28,ui.size.y-204,ui.size.x-56,110),false,12))


static func _project(ui: Variant, parent: VBoxContainer) -> void:
	var state: Dictionary = ui.session.state
	var pending: bool = not state.orders.is_empty()
	var active: bool = pending or not state.projects.is_empty()
	var metadata: Dictionary = state.get("cabinet",{}).get("project",{})
	var focus: Dictionary = ui._focus_item()
	var turn: Dictionary = state.get("last_receipt",{})
	var id := ""
	var count := 1
	var complete := false
	if active:
		id = str(metadata.get("id",""))
		if id.is_empty(): id = str(state.orders[0]) if pending else str(state.projects[0].id)
		var unfinished: int = state.orders.count(id)
		for project in state.projects:
			if project.id == id: unfinished += 1
		count = int(metadata.get("count",maxi(1,unfinished)))
	elif int(ui.development_result.get("week",0)) == int(state.week) and not ui.development_result.is_empty():
		id = str(ui.development_result.id)
		count = int(ui.development_result.get("count",1))
		complete = true
	elif turn.get("valid",false) and int(turn.week) == int(state.week)-1 and not turn.development.completed.is_empty():
		id = str(turn.development.completed[0].id)
		count = int(turn.development.completed[0].count)
		complete = true
	elif focus.kind == "build":
		id = str(focus.facility)
		count = CabinetActions._count(state,id)
	if complete and str(metadata.get("id","")) == id:
		var total_built := int(state.facilities.get(id,0)) - int(metadata.get("start_count",state.facilities.get(id,0)))
		if total_built >= int(metadata.get("count",1)): count = int(metadata.get("count",count))
	var header: HBoxContainer = ui._row(parent)
	ui._heading(header,"개발 완료" if complete else "진행 중인 개발" if active else "다음 개발")
	if id.is_empty():
		ui._button(header,"개발 목록",func(): ui._go("build"),false,"DevelopmentList")
		_idle(ui,parent,focus)
		return
	var hero: HBoxContainer = ui._row(parent)
	hero.add_theme_constant_override("separation",16)
	ui._building_art(hero,id,68)
	var title_box: VBoxContainer = ui._box(hero)
	title_box.add_theme_constant_override("separation",3)
	var title: String = str(ui.session.content.facilities[id].name)
	if count > 1: title += " ×%d" % count
	var name_label: Label = ui._heading(title_box,title)
	name_label.add_theme_font_size_override("font_size",26)
	ui._label(title_box,CabinetActions.BENEFITS.get(id,""),18,GameTheme.GOOD)
	var list_button: Button = ui._button(hero,"목록" if active or complete else "변경",func(): ui._go("build"),false,"DevelopmentList")
	list_button.custom_minimum_size.x = 76
	var costs := {}
	var offer := {}
	if pending:
		for queued in ui.brief.get("construction",{}).get("queued",[]):
			for asset in queued.cost: costs[asset] = float(costs.get(asset,0)) + float(queued.cost[asset])
	elif not active and not complete:
		offer = CabinetActions.offer(ui.session,id)
		costs = offer.cost
	if not costs.is_empty(): _costs(ui,parent,costs,"다음 주 결제" if pending else "승인할 비용")
	var completed_count := maxi(0,int(state.facilities.get(id,0)) - int(metadata.get("start_count",state.facilities.get(id,0)))) if active else count if complete else 0
	var remaining := int(ui.brief.get("construction",{}).get("remaining_work",0))
	var recorded_total := 0
	for project in ui.brief.get("construction",{}).get("projects",[]): recorded_total += int(project.work_total)
	for queued in ui.brief.get("construction",{}).get("queued",[]): recorded_total += int(queued.work_total)
	var total := maxi(1,int(metadata.get("total_work",recorded_total))) if active else 1
	var phase := 2 if complete else 0 if pending or not active else 1
	_stages(ui,parent,phase,pending)
	if active:
		var progress := clampf(1.0 - float(remaining)/float(total),0,1)
		ui._bar(parent,progress)
		if not pending:
			var figures: HBoxContainer = ui._row(parent)
			_figure(ui,figures,"완공", "%d / %d" % [completed_count,count])
			_figure(ui,figures,"남은 작업",str(remaining))
			_figure(ui,figures,"진행", "%.0f%%" % (progress*100))
		_flex(parent)
		ui._label(parent,"예약 완료 · 아래 ‘한 주 진행’으로 착공" if pending else "인력 자동 배치 · 아래 ‘한 주 진행’으로 작업",18,GameTheme.MUTED)
	elif complete:
		ui._bar(parent,1.0)
		var figures: HBoxContainer = ui._row(parent)
		_figure(ui,figures,"완공 시설","+%d" % count,GameTheme.GOOD)
		_figure(ui,figures,"현재 보유",str(state.facilities.get(id,0)))
		_flex(parent)
		ui._primary(ui._button(parent,"다음 개발 선택",func(): ui.development_result.clear(); ui._go("build"),false,"FocusAction"))
	else:
		_flex(parent)
		var footer: HBoxContainer = ui._row(parent)
		var explanation: String = str(offer.error) if not str(offer.error).is_empty() else str(offer.eta_text) + " 예상"
		var caption: Label = ui._label(footer,explanation,18,GameTheme.WARN if not str(offer.error).is_empty() else GameTheme.MUTED)
		caption.tooltip_text = explanation
		var approve: Button = ui._button(footer,"개발 승인",func(): ui._command_build(id),not str(offer.error).is_empty(),"FocusAction")
		approve.custom_minimum_size.x = 148
		ui._primary(approve)


static func _idle(ui: Variant, parent: VBoxContainer, focus: Dictionary) -> void:
	_flex(parent)
	ui._heading(parent,str(focus.title))
	ui._label(parent,"진행 중인 공사 없음",18,GameTheme.MUTED)
	_stages(ui,parent,-1,false)
	_flex(parent)
	ui._primary(ui._button(parent,str(focus.action),func(): ui._go(str(focus.get("page","build"))),false,"FocusAction"))


static func _costs(ui: Variant, parent: Node, costs: Dictionary, title: String) -> void:
	var row: HBoxContainer = ui._row(parent)
	row.name = "ProjectCosts"
	row.add_theme_constant_override("separation",12)
	var label: Label = ui._label(row,title,18,GameTheme.MUTED)
	label.size_flags_horizontal = Control.SIZE_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 120
	for asset in ["money","wood","stone","tools","iron"]:
		if float(costs.get(asset,0)) <= 0: continue
		var text: String = ui._money(float(costs[asset])) if asset == "money" else _number(float(costs[asset]))
		_figure(ui,row,TurnReceipt.LABELS[asset],text)


static func _stages(ui: Variant, parent: Node, phase: int, reserved: bool) -> void:
	var row: HBoxContainer = ui._row(parent)
	row.name = "ConstructionStages"
	row.add_theme_constant_override("separation",6)
	for index in 3:
		var text: String = ["승인", "공사", "완공"][index]
		if reserved and index == 0: text = "승인 완료"
		elif index < phase: text = "● " + text
		var label: Label = ui._label(row,text,18,GameTheme.GOOD if index <= phase else GameTheme.MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if index == phase: label.add_theme_font_override("font",PixelTheme.heading_font())
		if index < 2:
			var arrow: Label = ui._label(row,"→",18,GameTheme.MUTED)
			arrow.size_flags_horizontal = Control.SIZE_FILL


static func _result(ui: Variant, parent: VBoxContainer) -> void:
	parent.name = "WeekResult"
	parent.add_theme_constant_override("separation",0)
	var turn: Dictionary = ui.session.state.get("last_receipt",{})
	var row: HBoxContainer = ui._row(parent)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",18)
	var stamp: VBoxContainer = ui._box(row)
	stamp.size_flags_horizontal = Control.SIZE_FILL
	stamp.custom_minimum_size.x = 90
	if not turn.get("valid",false):
		ui._heading(stamp,"첫 운영")
		var guide: VBoxContainer = ui._box(row)
		var pending: bool = not ui.session.state.orders.is_empty()
		var line: Label = ui._heading(guide,"2 · 한 주 진행" if pending else "1 · 개발 승인")
		line.name = "FirstWeekInstruction"
		ui._label(guide,"승인 완료  →  주 진행  →  비용·완공 확인" if pending else "시설 선택  →  승인  →  한 주 진행",18,GameTheme.MUTED)
		ui._button(row,"안내",ui._help,false,"FirstWeekHelp")
		return
	ui._label(stamp,"%d주 결과" % int(turn.week),18,GameTheme.MUTED)
	ui._heading(stamp,"완료",false,GameTheme.GOOD)
	var money := _receipt_row(turn,"money")
	var food := _receipt_row(turn,"food")
	if not money.is_empty():
		var detail := "수입 %s · 지출 %s" % [ui._money(money.income),ui._money(money.expense)]
		if money.construction > 0 and is_zero_approx(float(money.income)):
			detail = "공사 %s · 운영 %s" % [ui._money(money.construction),ui._money(maxf(0,float(money.expense)-float(money.construction)))]
		_result_number(ui,row,"금고","%+.2f금" % (float(money.delta)/100.0),detail,float(money.delta),"MoneyResult")
	if not food.is_empty():
		var other_in := maxf(0,float(food.income)-float(food.production))
		var losses := maxf(0,float(food.expense)-float(food.consumption))
		var detail := "확보 +%s · 소모 −%s" % [_number(float(food.income)),_number(float(food.expense))]
		var breakdown := "생산 %s · 외부 유입 %s\n주민 소비 %s · 보관 손실 %s · 그 밖의 사용 %s" % [_number(float(food.production)),_number(other_in),_number(float(food.consumption)),_number(float(food.spoilage)),_number(maxf(0,losses-float(food.spoilage)))]
		_result_number(ui,row,"식량",_signed(float(food.delta)),detail,float(food.delta),"FoodResult",1.3,breakdown)
	var work: Dictionary = turn.development
	var result_title := "공사"
	var value := "+%d 작업" % int(work.work_done)
	var detail := "남은 작업 %d" % int(work.remaining_work)
	if not work.completed.is_empty():
		var built: Dictionary = work.completed[0]
		result_title = str(ui.session.content.facilities[built.id].name)
		value = "+%d 완공" % int(built.count)
	elif int(work.work_done) == 0:
		var advisor: Dictionary = turn.advisor
		result_title = "보좌관" if advisor.get("acted",false) else "이번 운영"
		value = str(advisor.label) + " " + _signed(float(advisor.amount)) if advisor.get("amount_known",false) else "활동 완료" if advisor.get("acted",false) else "결산 완료"
		detail = str(advisor.name) if advisor.get("amount_known",false) else "세부 내역에서 확인"
	_result_number(ui,row,result_title,value,detail,0,"DevelopmentResult")
	var button: Button = ui._button(row,"상세",func(): ui.receipt_open = true; ui._render(),false,"TurnDetails")
	button.custom_minimum_size.x = 76


static func _result_number(ui: Variant, parent: Node, title: String, value: String, detail: String, delta: float, id: String, ratio: float = 1.0, breakdown: String = "") -> void:
	var box: VBoxContainer = ui._box(parent,ratio)
	box.name = id
	box.add_theme_constant_override("separation",0)
	var heading: Label = ui._label(box,title,18,GameTheme.MUTED)
	heading.max_lines_visible = 1
	var number: Label = ui._heading(box,value,false,GameTheme.WARN if delta < 0 else GameTheme.GOOD)
	number.add_theme_font_size_override("font_size",26)
	var caption: Label = ui._label(box,detail,18,GameTheme.MUTED)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.tooltip_text = detail if breakdown.is_empty() else detail + "\n" + breakdown


static func _figure(ui: Variant, parent: Node, title: String, value: String, color: Color = GameTheme.TEXT) -> void:
	var box: VBoxContainer = ui._box(parent)
	box.add_theme_constant_override("separation",0)
	ui._label(box,title,18,GameTheme.MUTED)
	var label: Label = ui._heading(box,value,false,color)
	label.add_theme_font_size_override("font_size",24)


static func _receipt_row(receipt: Dictionary, id: String) -> Dictionary:
	for row in receipt.get("resource_rows",[]):
		if row.id == id: return row
	return {}


static func _flex(parent: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


static func _number(value: float) -> String:
	return "%.0f" % value if is_equal_approx(value,roundf(value)) else "%.1f" % value


static func _signed(value: float) -> String:
	return ("+" if value >= 0 else "−") + _number(absf(value))
