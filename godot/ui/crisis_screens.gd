class_name CrisisScreens
extends RefCounted
## 위기와 비용 상승은 규칙 모듈의 공개 정보만 표시한다. 화면 조회는 상태를 바꾸지 않는다.


static func map_status(ui: Variant, parent: Node) -> void:
	if not CrisisDirector.enabled(ui.session.state): return
	var info: Dictionary = CrisisDirector.overview(ui.session.state,ui.session.content)
	var title := "위기 대비"
	if not info.current.is_empty(): title += " · %d주 남음" % info.current.remaining
	elif not info.upcoming.is_empty(): title += " · %d주 예고" % info.upcoming.announce
	else: title = "위기 평가 완료"
	var pressure: Label = ui._lit(parent,"부담 %d/4" % (int(info.pressure.index)+1),16,ui.LIT_WARN if int(info.pressure.index)>0 else ui.LIT_MUTED)
	pressure.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pressure.tooltip_text = str(info.pressure.name)+"\n"+str(info.pressure.text)
	pressure.mouse_filter = Control.MOUSE_FILTER_STOP
	var button: Button = ui._button(parent,title,func(): ui._go("crises"),false,"OpenCrisis")
	button.add_theme_font_size_override("font_size",16)
	button.custom_minimum_size.y = 32
	button.tooltip_text = "예고된 요구량 · 대비 방법 · 운영 부담 상승 일정"
	if not info.current.is_empty() and int(info.current.remaining) <= 2: ui._primary(button)


static func page(ui: Variant, parent: Node) -> void:
	var info: Dictionary = CrisisDirector.overview(ui.session.state,ui.session.content)
	if not info.enabled:
		ui._label(parent,"이 저장은 기존 운영 규칙을 사용합니다. 새 통치부터 위기와 운영 부담이 적용됩니다.",21)
		return
	var body: HBoxContainer = ui._row(parent)
	body.name = "CrisisOverview"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",16)
	var current: VBoxContainer = ui._card(body)
	current.name = "CurrentCrisis"
	current.get_parent().size_flags_stretch_ratio = 1.4
	current.add_theme_constant_override("separation",6)
	if not info.current.is_empty():
		_active(ui,current,info.current)
	else:
		ui._heading(current,"다음 위기에 대비하세요" if not info.upcoming.is_empty() else "네 번의 위기 평가 완료",true)
		if not info.upcoming.is_empty():
			ui._label(current,"%d주에 정보 공개 · %d주 말 평가" % [info.upcoming.announce,info.upcoming.deadline],21,GameTheme.TEAL)
			ui._label(current,"예고가 오면 필요한 시설과 비축량을 확인할 수 있습니다. 지금은 개발과 계절 목표을 진행하세요.",20)
		else: ui._label(current,"남은 기간은 연말 목표와 겨울 시련을 준비하세요.",20)
		ui._rule(current)
		var history: VBoxContainer = ui._scroll(current)
		history.name = "CrisisHistory"
		if info.records.is_empty(): ui._label(history,"첫 7주는 개발에 집중할 수 있습니다.\n위기는 마감 4~6주 전에 예고합니다.",19,GameTheme.MUTED)
		for item in info.records:
			ui._label(history,"%d주 · %s · %s" % [item.week,item.name,"극복" if item.success else "피해 발생"],20,GameTheme.GOOD if item.success else GameTheme.WARN)
			ui._label(history,str(item.message),18,GameTheme.MUTED)
			ui._rule(history)
	var actions: HBoxContainer = ui._row(current)
	for entry in [["build","시설 준비"],["trade","물자 확보"],["policy","포고 검토"]]:
		var button: Button = ui._button(actions,entry[1],func(): ui._go(entry[0]),false,"Crisis_"+str(entry[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",18)
	var timeline: VBoxContainer = ui._card(body)
	timeline.name = "PressureTimeline"
	timeline.get_parent().size_flags_stretch_ratio = 1.0
	ui._heading(timeline,"운영 부담  %d / 4" % (int(info.pressure.index)+1))
	ui._label(timeline,"계절 전환 때 상승 · 현재 단계만 적용",17,GameTheme.MUTED)
	var phases: VBoxContainer = ui._scroll(timeline)
	phases.add_theme_constant_override("separation",3)
	for index in ui.session.content.crises.phases.size():
		var phase: Dictionary = ui.session.content.crises.phases[index]
		var active: bool = int(info.pressure.index) == index
		ui._label(phases,("▶ " if active else "")+"%d주부터 · %s" % [phase.start,phase.name],18,GameTheme.TEAL if active else GameTheme.MUTED)
		var values: Dictionary = phase.mods
		var text: String = "추가 부담 없음" if values.is_empty() else "물자값 +%d%% · 급여 +%d%%\n유지비 +%d%% · 위협 증가 +%d%%" % [roundi((float(values.buy)-1)*100),roundi((float(values.wages)-1)*100),roundi((float(values.maintenance)-1)*100),roundi((float(values.threat_growth)-1)*100)]
		ui._label(phases,text,17,GameTheme.TEXT if active else GameTheme.MUTED)
		ui._rule(phases)
	if not info.next_pressure.is_empty(): ui._label(timeline,"다음 상승까지 %d주" % info.next_pressure.remaining,18,GameTheme.WARN if info.next_pressure.warned else GameTheme.MUTED)
	else: ui._label(timeline,"마지막 단계 · 52주까지 유지",18,GameTheme.WARN)


static func _active(ui: Variant, parent: Node, current: Dictionary) -> void:
	ui._heading(parent,str(current.name),true)
	ui._label(parent,"%d주 말 평가 · %d주 남음 · 조건 %d / %d" % [current.deadline,current.remaining,current.met_count,current.total_checks],19,GameTheme.GOOD if current.ready else GameTheme.WARN).name = "CrisisCountdown"
	var area: VBoxContainer = ui._scroll(parent)
	area.name = "CrisisRequirements"
	area.add_theme_constant_override("separation",4)
	ui._label(area,str(current.hint),19,GameTheme.MUTED)
	ui._rule(area)
	for index in current.checks.size():
		var check: Dictionary = current.checks[index]
		var box: VBoxContainer = ui._box(area)
		box.name = "CrisisCheck_%d" % index
		box.add_theme_constant_override("separation",2)
		ui._label(box,("✓ " if check.met else "○ ")+str(check.label),20,GameTheme.GOOD if check.met else GameTheme.TEXT)
		ui._label(box,str(check.text),19,GameTheme.GOOD if check.met else GameTheme.WARN)
	ui._rule(area)
	ui._label(area,"조건은 예고 때 확정됩니다. 비축품은 대비 조건이며, 성공 시 차감하지 않습니다. 공사 예약 자재는 비축량에서 제외합니다.",17,GameTheme.MUTED)
	var consequences: VBoxContainer = ui._box(parent)
	consequences.name = "CrisisConsequences"
	consequences.add_theme_constant_override("separation",2)
	ui._label(consequences,"극복 보상 · "+RealmRules.changes_text(current.reward)+( " · 성물 1개 선택" if current.relic else ""),18,GameTheme.GOOD)
	ui._label(consequences,"미달 피해 · "+RealmRules.changes_text(current.penalty),18,GameTheme.WARN)


static func alerts(state: Dictionary, content: Dictionary) -> Array:
	if not CrisisDirector.enabled(state): return []
	var info: Dictionary = CrisisDirector.overview(state,content)
	var out := []
	if not info.current.is_empty():
		var current: Dictionary = info.current
		out.append(["warn" if not current.ready and int(current.remaining)<=2 else "info","%s · %d주 말 평가 · 대비 %d/%d" % [current.name,current.deadline,current.met_count,current.total_checks]])
	if not info.next_pressure.is_empty() and info.next_pressure.warned:
		out.append(["warn","%d주부터 %s · 위기 대비에서 상승 폭을 확인하세요." % [info.next_pressure.start,info.next_pressure.name]])
	return out


static func results(ui: Variant, parent: Node) -> void:
	if not CrisisDirector.enabled(ui.session.state): return
	var info: Dictionary = CrisisDirector.overview(ui.session.state,ui.session.content)
	ui._rule(parent)
	ui._heading(parent,"위기 극복 %d / %d" % [info.records.filter(func(row): return row.success).size(),info.records.size()])
	for row in info.records:
		ui._label(parent,("✓ " if row.success else "✗ ")+"%d주 · %s" % [row.week,row.name],19,GameTheme.GOOD if row.success else GameTheme.WARN)
