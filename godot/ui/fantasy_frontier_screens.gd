class_name FantasyFrontierScreens
extends RefCounted
## 영지의 변화는 사건에서 채택하고 실제 공사로 발전한다. 이 화면은 공개 정보만 읽는다.

const RESOURCES := {"money":"금고","wood":"목재","stone":"석재","tools":"도구","iron":"철"}

static func _copy(ui: Variant, parent: Node, text: String, id: String = "", color: Color = GameTheme.TEXT, px: int = 18) -> Label:
	var label: Label = ui._label(parent,text,px,color)
	if id != "": label.name = id
	return label

static func _status(path: Dictionary) -> String:
	if path.selected: return "완공 %d/3" % int(path.background_stage)
	if path.get("status","") in ["declined","unavailable"]: return "이번 통치 미채택"
	return "발견" if path.discovered else "미발견"

static func _cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for asset in RESOURCES:
		var amount := float(cost.get(asset,0))
		if amount <= 0: continue
		parts.append("%s %s" % [RESOURCES[asset],(("%d금" % int(amount/100.0)) if is_equal_approx(fmod(amount,100.0),0.0) else ("%.2f금" % (amount/100.0))) if asset == "money" else "%d" % int(amount)])
	return " · ".join(parts) if not parts.is_empty() else "비용 없음"

static func summary(ui: Variant, parent: Node) -> void:
	var view: Dictionary = FantasyFrontiers.overview(ui.session.state,ui.session.content)
	if not view.enabled: return
	var names: Array[String] = []
	for path in view.paths:
		if path.selected: names.append(str(path.name)+" %d/3" % int(path.background_stage))
	ui._heading(parent,"영지의 변화")
	_copy(ui,parent," · ".join(names) if not names.is_empty() else "새로운 발견에서 영지의 성장 방향을 정합니다.","FantasySummary",GameTheme.TEAL if not names.is_empty() else GameTheme.MUTED)
	ui._button(parent,"발견과 전용 건물 확인",func(): ui._go("fantasy_frontier"),false,"OpenFantasyFrontier")
	ui._rule(parent)

static func page(ui: Variant, parent: Node) -> void:
	var view: Dictionary = FantasyFrontiers.overview(ui.session.state,ui.session.content)
	if not view.enabled:
		_copy(ui,parent,"이 통치는 원래의 영지 규칙을 사용합니다. 새로운 발견과 전용 건물은 다음 부임부터 적용됩니다.","FantasyLegacy",GameTheme.MUTED,20)
		return
	var dates: Array[String] = []
	for week in view.get("discovery_weeks",[]): dates.append(str(week))
	var schedule := "·".join(dates)+"주 새 발견 · " if not dates.is_empty() else ""
	_copy(ui,parent,schedule+"최대 %d계열 채택 · 시설 효과는 완공 후 다음 주부터" % int(view.limit),"FantasyScope",GameTheme.MUTED)
	if view.paths.is_empty(): return
	if not view.paths.any(func(path): return path.id == ui.selected_frontier):
		ui.selected_frontier = str(view.selected[0]) if not view.selected.is_empty() else str(view.paths[0].id)
	var body: HBoxContainer = ui._row(parent)
	body.name = "FantasyFrontierPage"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	var list: VBoxContainer = ui._scroll(body)
	var list_scroll: ScrollContainer = list.get_parent()
	list_scroll.name = "FantasyPathScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_FILL
	list_scroll.custom_minimum_size.x = 252
	ui._restore_relic_scroll.call_deferred(list_scroll,int(ui.fantasy_scroll_positions.get("paths",0)))
	var selected: Dictionary = view.paths[0]
	for path in view.paths:
		var button: Button = ui._button(list,str(path.name)+"\n"+_status(path),func(): ui.selected_frontier = path.id; ui.selected_frontier_building = ""; ui._render(),false,"fantasy_path_"+str(path.id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size",18)
		button.custom_minimum_size.y = 60
		if path.id == ui.selected_frontier:
			ui._primary(button)
			selected = path
	var detail: VBoxContainer = ui._card(body)
	detail.name = "FantasyFrontierDetail"
	detail.add_theme_constant_override("separation",7)
	var heading: HBoxContainer = ui._row(detail)
	ui._heading(heading,str(selected.name),true)
	var adoption: String = "채택 %d/%d" % [view.selected.size(),view.limit] if selected.selected else "채택 한도 도달" if view.selected.size() >= int(view.limit) else "이번 통치 미채택" if selected.get("status","") in ["declined","unavailable"] else "발견 후 사건에서 선택"
	_copy(ui,heading,adoption,"FantasyAdoption",GameTheme.GOOD if selected.selected else GameTheme.MUTED)
	var effects: HBoxContainer = ui._row(detail)
	effects.add_theme_constant_override("separation",18)
	var benefit: VBoxContainer = ui._box(effects)
	ui._heading(benefit,"성장 방향",false,GameTheme.GOOD)
	_copy(ui,benefit,str(selected.benefit),"FantasyBenefit",GameTheme.TEXT)
	var tradeoff: VBoxContainer = ui._box(effects)
	ui._heading(tradeoff,"운영 시 유의점",false,GameTheme.WARN)
	_copy(ui,tradeoff,str(selected.tradeoff),"FantasyTradeoff",GameTheme.TEXT)
	var steps: HBoxContainer = ui._row(detail)
	steps.name = "FantasyBuildingSteps"
	steps.add_theme_constant_override("separation",8)
	var buildings: Array = selected.buildings
	if buildings.is_empty(): return
	if not buildings.any(func(building): return building.id == ui.selected_frontier_building):
		ui.selected_frontier_building = str(buildings[0].id)
		for building in buildings:
			if building.unlocked and not building.built: ui.selected_frontier_building = str(building.id); break
	var chosen: Dictionary = buildings[0]
	for building in buildings:
		var state := "완공" if building.built else "공사 중" if building.queued else "허가 받음" if building.unlocked else "허가 전"
		var action: Button = ui._button(steps,str(building.name)+"\n"+state,func(): ui.selected_frontier_building = building.id; ui._render(),false,"fantasy_building_"+str(building.id))
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("font_size",18)
		if building.id == ui.selected_frontier_building:
			ui._primary(action)
			chosen = building
	var reading: VBoxContainer = ui._scroll(detail)
	reading.name = "FantasyBuildingDetail"
	var scroll: ScrollContainer = reading.get_parent()
	scroll.name = "FantasyDetailScroll"
	scroll.set_meta("scroll_key",str(selected.id)+":"+str(chosen.id))
	ui._restore_relic_scroll.call_deferred(scroll,int(ui.fantasy_scroll_positions.get(scroll.get_meta("scroll_key"),0)))
	var row: HBoxContainer = ui._row(reading)
	var image: TextureRect = ui._art(row,"building_"+str(chosen.sprite),Vector2(88,88))
	image.name = "FantasyBuildingArt"
	image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var words: VBoxContainer = ui._box(row)
	_copy(ui,words,str(chosen.effect),"FantasyBuildingEffect",GameTheme.TEAL,19)
	if chosen.built: operation(ui,words,str(chosen.id))
	if selected.branch_name != "":
		_copy(ui,words,"적용 중 · "+str(selected.branch_name),"FantasyBranch",GameTheme.GOOD)
		if str(selected.get("branch_text","")) != "": _copy(ui,words,str(selected.branch_text),"FantasyBranchEffect",GameTheme.MUTED)
	_copy(ui,reading,str(selected.next_text),"FantasyNext",GameTheme.MUTED)
	_copy(ui,reading,"사건 진행 %d/5 · 전용 건물 완공 %d/3" % [selected.stage,selected.background_stage],"FantasyProgress",GameTheme.MUTED)
	if str(chosen.error) != "" and not chosen.built and not chosen.queued: _copy(ui,reading,str(chosen.error),"FantasyBuildingError",GameTheme.WARN)
	ui._rule(detail)
	var footer: HBoxContainer = ui._row(detail)
	_copy(ui,footer,("기본 건설비 · " if chosen.built else "건설 비용 · ")+_cost(chosen.cost),"FantasyConstructionCost")
	var action_label: String = "현장 확인" if selected.selected else "이번 통치 미채택" if selected.get("status","") in ["declined","unavailable"] else "사건에서 채택"
	var open: Button = ui._button(footer,action_label,func(): ui._open_build_lot(str(chosen.id)),not selected.selected,"FantasyGoSite")
	open.custom_minimum_size.x = 150
	open.tooltip_text = "이 화면에서는 비용을 쓰지 않습니다. 건설 현장에서 실제 비용·완공 예상을 확인하고 승인합니다."
	if selected.selected: ui._primary(open)

static func operation(ui: Variant, parent: Node, id: String) -> void:
	var current: Dictionary = FantasyFrontiers.building_operation(ui.session.state,ui.session.content,id)
	var text := "시설 효과 적용 중"
	var tone := GameTheme.GOOD
	if current.productive:
		match str(current.status):
			"waiting": text = "완공 · 다음 주부터 생산"
			"labor": text = "지난주 일손 부족 · 미가동"; tone = GameTheme.WARN
			"inputs":
				var missing: Array[String] = []
				for resource in current.missing: missing.append(str(TurnReceipt.LABELS.get(resource,resource)))
				text = "지난주 재료 부족 · "+" / ".join(missing)
				tone = GameTheme.WARN
			"operating": text = "%d주 가동 · %d명 / %d명" % [current.week,current.workers,current.capacity]
	_copy(ui,parent,text,"FantasyOperation_"+id,tone)

static func results(ui: Variant, parent: Node) -> void:
	var view: Dictionary = FantasyFrontiers.overview(ui.session.state,ui.session.content)
	if not view.enabled or view.selected.is_empty(): return
	ui._rule(parent)
	ui._heading(parent,"통치를 마친 영지의 변화")
	for path in view.paths:
		if not path.selected: continue
		_copy(ui,parent,str(path.name)+" · 완공 %d/3" % int(path.background_stage),"FinalFantasy_"+str(path.id),GameTheme.GOOD,20)
		if path.branch_name != "": _copy(ui,parent,str(path.branch_name),"",GameTheme.MUTED)
