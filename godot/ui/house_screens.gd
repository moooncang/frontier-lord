class_name HouseScreens
extends RefCounted
## 가문 강화의 구매와 다음 부임의 선택을 분리한다. 수치와 조건은 LegacyPath가 제공한다.

const KIND_NAMES := {"foundation":"기반 강화", "choice":"선택권 해금", "doctrine":"가문 방침"}
const PREP_NAMES := {"doctrines":"가문 방침", "supply_packs":"지원 물자", "perk_families":"첫 특전", "relic_families":"첫 성물"}
const PREP_KEYS := {"supply_packs":"supply_pack", "perk_families":"perk_family", "relic_families":"relic_family"}

## Lines use the real prerequisite IDs. They stay behind the eight inspectable nodes.
class TrainingLinks:
	extends Control
	var nodes: Dictionary = {}
	var requirements: Dictionary = {}
	var ranks: Dictionary = {}
	var last_geometry := ""
	func _process(_delta: float) -> void:
		var geometry := ""
		for id in nodes:
			if is_instance_valid(nodes[id]): geometry += str(nodes[id].get_global_rect())
		if geometry != last_geometry:
			last_geometry = geometry
			queue_redraw()
	func _draw() -> void:
		for id in requirements:
			var previous: String = requirements[id]
			if not nodes.has(previous) or not is_instance_valid(nodes[id]) or not is_instance_valid(nodes[previous]): continue
			var first: Rect2 = nodes[previous].get_global_rect()
			var second: Rect2 = nodes[id].get_global_rect()
			var color := Color("719876") if int(ranks.get(previous,0)) > 0 else Color("746d5a")
			var start := first.get_center() - global_position
			var finish := second.get_center() - global_position
			if absf(start.y-finish.y) < 8:
				start.x = first.end.x-global_position.x
				finish.x = second.position.x-global_position.x
			else:
				start.y = first.end.y-global_position.y
				finish.y = second.position.y-global_position.y-26
			draw_line(start,finish,color,2,false)
			draw_rect(Rect2(finish-Vector2(2,2),Vector2(4,4)),color)


static func _copy(ui: Variant, parent: Node, text: String, name: String = "", color: Color = GameTheme.TEXT, px: int = 18) -> Label:
	var label: Label = ui._label(parent,text,px,color)
	label.add_theme_constant_override("line_spacing",2)
	if name != "": label.name = name
	return label


static func _selected(button: Button, selected: bool) -> void:
	button.toggle_mode = true
	button.button_pressed = selected
	button.add_theme_stylebox_override("pressed",RealmTheme.surface(Color("42594b"),10))
	button.add_theme_stylebox_override("hover_pressed",RealmTheme.surface(Color("526c5b"),10))


static func _fixed(parent: Control, width: float) -> void:
	parent.custom_minimum_size.x = width
	parent.size_flags_horizontal = 0


static func _scroll(ui: Variant, parent: Node, key: String) -> VBoxContainer:
	var box: VBoxContainer = ui._scroll(parent)
	var scroll: ScrollContainer = box.get_parent()
	scroll.name = "HouseListScroll"
	scroll.set_meta("scroll_key",key)
	ui._restore_house_scroll.call_deferred(scroll,int(ui.house_scroll_positions.get(key,0)))
	return box


static func _active_lock(ui: Variant) -> String:
	return "현재 통치를 마친 뒤 변경할 수 있습니다." if ui._is_active() else ""


static func page(ui: Variant) -> void:
	var view: Dictionary = LegacyPath.overview(ui.session.profile)
	var frame: VBoxContainer = ui._plate(Rect2(36,28,ui.size.x-72,ui.size.y-56),false,20)
	frame.name = "LegacyBoard"
	frame.add_theme_constant_override("separation",8)
	var header: HBoxContainer = ui._row(frame)
	ui._heading(header,"가문 강화",true)
	_copy(ui,header,"공훈 %d" % view.points,"LegacyPoints",GameTheme.GOOD,24)
	ui._button(header,"메뉴",func(): ui._go("menu"),false,"LegacyBack")
	var tabs: HBoxContainer = ui._row(frame)
	tabs.name = "HouseBranches"
	for branch in view.branches:
		var id: String = branch.id
		var count: int = view.items.filter(func(item): return item.branch == id and item.rank > 0).size()
		var button: Button = ui._button(tabs,"%s  %d/8" % [branch.name,count],func(): ui.house_branch = id; ui._render(),false,"legacy_branch_"+id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",18)
		ui._quiet(button)
		_selected(button,ui.house_branch == id)
	var additional: Button = ui._button(tabs,"공통 강화",func(): ui.house_branch = "additional"; ui._render(),false,"LegacyAdditional")
	additional.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	additional.add_theme_font_size_override("font_size",18)
	if ui.house_branch == "additional": ui._primary(additional)
	var body: HBoxContainer = ui._row(frame)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",16)
	if ui.house_branch == "additional": _additional(ui,body,view)
	else: _branch(ui,body,view)
	var plan: HBoxContainer = ui._row(frame)
	_copy(ui,plan,"다음 통치  "+_doctrine_names(view)+"  ·  지원 "+_support_name(view),"LegacyPolicySummary",GameTheme.MUTED)
	ui._button(plan,"방침·지원 선택",func(): ui._open_house_preparation("archive"),false,"LegacyPolicyManager")
	var footer: HBoxContainer = ui._row(frame)
	var refund: Button = ui._button(footer,"무료 재분배",ui._refund_talents,ui._is_active() or ui._talent_ranks() == 0 or ui.load_blocked,"RefundTalents")
	refund.tooltip_text = "가문 특성에 쓴 공훈을 전부 돌려받습니다. 선택한 방침과 지원 설정은 해제되고, 공통 강화 구매는 유지됩니다."
	ui._button(footer,"발견·통치 기록",func(): ui._go("catalog"),false,"LegacyCatalog")
	ui._spacer(footer)
	ui._primary(ui._button(footer,"통치 이어 하기" if ui._is_active() else "새 통치 준비 →",ui._continue if ui._is_active() else ui._open_prepare,ui.load_blocked,"LegacyPrepare"))


static func _branch(ui: Variant, parent: Node, view: Dictionary) -> void:
	var rows: Array = view.items.filter(func(item): return item.branch == ui.house_branch)
	if rows.is_empty():
		ui.house_branch = str(view.branches[0].id)
		rows = view.items.filter(func(item): return item.branch == ui.house_branch)
	var left: VBoxContainer = ui._box(parent)
	left.name = "TalentTree"
	left.add_theme_constant_override("separation",6)
	var acquired: int = rows.filter(func(item): return item.rank > 0).size()
	var branch: Dictionary = view.branches.filter(func(item): return item.id == ui.house_branch)[0]
	_copy(ui,left,"%s 성장 경로  ·  %d / %d 습득" % [branch.name,acquired,rows.size()],"HouseBranchProgress",GameTheme.GOOD,20)
	_copy(ui,left,"기반을 1단계 익히면 연결된 다음 특성을 해금할 수 있습니다.","HousePathHint",GameTheme.MUTED)
	var list: VBoxContainer = _scroll(ui,left,"branch:"+ui.house_branch)
	if not rows.any(func(item): return item.id == ui.selected_talent): ui.selected_talent = str(rows[0].id)
	var path := TrainingLinks.new()
	path.name = "HouseTrainingPath"
	path.custom_minimum_size.y = 80 + 2 * _node_height(ui)
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(path)
	var lanes := HBoxContainer.new()
	lanes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lanes.add_theme_constant_override("separation",16)
	path.add_child(lanes)
	var foundations: Array = rows.filter(func(item): return item.kind == "foundation")
	var definitions: Dictionary = LegacyPath.definitions().talents
	for index in foundations.size():
		var foundation: Dictionary = foundations[index]
		var lane: VBoxContainer = ui._box(lanes)
		lane.add_theme_constant_override("separation",0)
		var label := _copy(ui,lane,"기반 %d" % (index+1),"",GameTheme.MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var first := _path_node(ui,lane,foundation)
		path.nodes[foundation.id] = first
		path.ranks[foundation.id] = foundation.rank
		path.requirements[foundation.id] = str(definitions[foundation.id].requires)
		var gap := Control.new()
		gap.custom_minimum_size.y = 30
		lane.add_child(gap)
		var children: Array = rows.filter(func(item): return item.kind != "foundation" and str(definitions[item.id].requires) == foundation.id)
		for item in children:
			var kind := _copy(ui,lane,"선택권" if item.kind == "choice" else "가문 방침","",GameTheme.MUTED)
			kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			path.nodes[item.id] = _path_node(ui,lane,item)
			path.ranks[item.id] = item.rank
			path.requirements[item.id] = str(foundation.id)
	var detail: VBoxContainer = ui._card(parent)
	_fixed(detail.get_parent(),414)
	detail.name = "TalentDetail"
	detail.add_theme_constant_override("separation",6)
	var selected: Dictionary = rows.filter(func(item): return item.id == ui.selected_talent)[0]
	_detail(ui,detail,selected)


## 성장 경로 마디의 높이. 큰 창에서는 나무 아래 빈 자리만큼 키운다.
static func _node_height(ui: Variant) -> float:
	return clampf(108.0 + (ui.size.y - 720.0) * 0.45, 108.0, 190.0)


static func _path_node(ui: Variant, parent: Node, item: Dictionary) -> Button:
	var status := "완료" if item.rank >= item.max_rank else "공훈 %d" % item.cost
	if item.rank < item.max_rank and str(item.error).begins_with("선행"): status = "선행 필요"
	var caption := "%s\n%d/%d단계 · %s" % [item.name,item.rank,item.max_rank,status]
	if _node_height(ui) >= 170: caption += "\n" + str(item.next_text if item.rank < item.max_rank else item.current_text)
	var button: Button = ui._quiet(ui._button(parent,caption,func(): ui.selected_talent = item.id; ui._render(),false,"talent_"+str(item.id)))
	button.custom_minimum_size.y = _node_height(ui)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",18)
	_selected(button,item.id == ui.selected_talent)
	button.tooltip_text = str(item.description)+("\n선행: "+str(item.requires_text) if str(item.requires_text) != "" else "")
	return button


## 상세 칸의 남는 자리에 단계별 효과와 이 특성을 익히면 열리는 특성을 적는다.
static func _talent_notes(ui: Variant, notes: Node, item: Dictionary) -> void:
	var definitions: Dictionary = LegacyPath.definitions().talents
	if int(item.max_rank) > 1:
		_copy(ui,notes,"단계별 효과","",GameTheme.MUTED)
		for step in range(1,int(item.max_rank)+1):
			var tone: Color = GameTheme.GOOD if step <= int(item.rank) else GameTheme.TEXT if step == int(item.rank)+1 else GameTheme.MUTED
			_copy(ui,notes,"%d단계 · %s" % [step,LegacyPath.effect_text(definitions[item.id],step)],"",tone)
	var opens: Array[String] = []
	for id in definitions:
		if str(definitions[id].requires) == str(item.id): opens.append("%s (%s)" % [definitions[id].name,KIND_NAMES.get(str(definitions[id].get("kind","foundation")),"기반 강화")])
	if not opens.is_empty(): _copy(ui,notes,"익히면 열리는 특성\n"+"\n".join(opens),"TalentOpens",GameTheme.MUTED)


static func _detail(ui: Variant, parent: Node, item: Dictionary) -> void:
	ui._heading(parent,str(item.name),false)
	_copy(ui,parent,"%s · %d/%d단계" % [KIND_NAMES.get(item.kind,"기반 강화"),item.rank,item.max_rank],"TalentKind",GameTheme.MUTED)
	var effects: VBoxContainer = ui._box(parent)
	effects.add_theme_constant_override("separation",8)
	_copy(ui,effects,"현재  "+str(item.current_text),"TalentCurrent",GameTheme.MUTED,19)
	_copy(ui,effects,("구매 후  " if item.kind != "foundation" else "다음 단계  ")+str(item.next_text),"TalentNext",GameTheme.GOOD,19)
	var notes: VBoxContainer = ui._scroll(parent)
	notes.name = "TalentNotes"
	if item.kind != "foundation" and str(item.description) not in [str(item.current_text),str(item.next_text)]: _copy(ui,notes,str(item.description))
	_talent_notes(ui,notes,item)
	_copy(ui,parent,"선행  "+(str(item.requires_text) if str(item.requires_text) != "" else "없음"),"TalentPrerequisite",GameTheme.MUTED)
	_copy(ui,parent,"적용  "+str(item.application_text),"TalentApplication",GameTheme.MUTED)
	var maxed: bool = item.rank >= item.max_rank
	var cost_text: String = "모든 단계를 습득했습니다." if maxed else _cost_text(int(ui.session.profile.points),int(item.cost))
	_copy(ui,parent,cost_text,"TalentCost",GameTheme.TEXT,20)
	var error: String = _active_lock(ui)
	if error == "": error = str(item.error)
	if error != "" and not maxed: _copy(ui,parent,error,"TalentError",GameTheme.WARN)
	var action: String = "습득 완료" if maxed else "강화하기" if item.kind == "foundation" else "선택권 해금" if item.kind == "choice" else "방침 해금"
	ui._primary(ui._button(parent,action,ui._buy_talent,error != "" or maxed or ui.load_blocked,"BuyTalent"))


static func _additional(ui: Variant, parent: Node, view: Dictionary) -> void:
	var left: VBoxContainer = ui._box(parent)
	left.name = "TalentTree"
	_copy(ui,left,"공통 강화 · 구매한 항목은 다음 부임부터 계속 적용됩니다.","AdditionalGuide",GameTheme.MUTED)
	var list: VBoxContainer = _scroll(ui,left,"additional")
	if not view.legacy_upgrades.any(func(item): return item.id == ui.selected_upgrade): ui.selected_upgrade = str(view.legacy_upgrades[0].id)
	var grid: GridContainer = _choice_grid(list)
	for item in view.legacy_upgrades:
		var button: Button = _choice(ui,grid,str(item.name)+(" · 구매 완료" if item.owned else " · 공훈 %d" % item.cost),str(item.description),func(): ui.selected_upgrade = item.id; ui._render(),"meta_"+str(item.id))
		button.tooltip_text = str(item.description)
		if item.id == ui.selected_upgrade: ui._primary(button)
	var detail: VBoxContainer = ui._card(parent)
	_fixed(detail.get_parent(),440)
	detail.name = "TalentDetail"
	var item: Dictionary = view.legacy_upgrades.filter(func(row): return row.id == ui.selected_upgrade)[0]
	ui._heading(detail,str(item.name))
	_copy(ui,detail,"공통 강화 · 1회 구매", "TalentKind",GameTheme.MUTED)
	_copy(ui,detail,"현재  "+("구매 완료" if item.owned else "미구매"),"TalentCurrent",GameTheme.MUTED,19)
	_copy(ui,detail,"구매 후  "+str(item.description),"TalentNext",GameTheme.GOOD,19)
	var follows: Array[String] = []
	for id in ui.session.content.progression.upgrades:
		if str(ui.session.content.progression.upgrades[id].requires) == str(item.id): follows.append(str(ui.session.content.progression.upgrades[id].name))
	if not follows.is_empty():
		var chain: Label = _copy(ui,detail,"이어서 열림  "+", ".join(follows),"TalentOpens",GameTheme.MUTED)
		chain.max_lines_visible = 1
		chain.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		chain.tooltip_text = ", ".join(follows)
	ui._spacer(detail)
	var source: Dictionary = ui.session.content.progression.upgrades[item.id]
	_copy(ui,detail,"선행  "+(str(ui.session.content.progression.upgrades[source.requires].name) if source.requires != "" else "없음"),"TalentPrerequisite",GameTheme.MUTED)
	_copy(ui,detail,"적용  다음 부임부터", "TalentApplication",GameTheme.MUTED)
	_copy(ui,detail,"구매 완료" if item.owned else _cost_text(view.points,item.cost),"TalentCost",GameTheme.TEXT,20)
	var error: String = _active_lock(ui)
	if error == "": error = str(item.error)
	if error != "" and not item.owned: _copy(ui,detail,error,"TalentError",GameTheme.WARN)
	ui._primary(ui._button(detail,"구매 완료" if item.owned else "공통 강화 구매",func(): ui._upgrade(item.id),item.owned or error != "" or ui.load_blocked,"upgrade_"+str(item.id)))


static func _doctrine_names(view: Dictionary) -> String:
	var names: Array[String] = []
	for item in view.doctrines:
		if item.id in view.selected_doctrines: names.append(str(item.name))
	return " / ".join(names) if not names.is_empty() else "선택 없음 · 최대 2개"


static func _support_name(view: Dictionary) -> String:
	var id := str(view.preparation.get("supply_pack",""))
	for item in view.preparation_options.supply_packs:
		if item.id == id: return str(item.name)
	return "없음"


static func _loadout(ui: Variant, parent: Node, view: Dictionary) -> void:
	var row: HBoxContainer = ui._row(parent)
	row.name = "HouseLoadout"
	row.add_theme_constant_override("separation",12)
	for index in 2:
		var card: VBoxContainer = ui._box(row)
		card.name = "HousePlanSlot_%d" % index
		var item: Dictionary = {}
		if index < view.selected_doctrines.size():
			item = view.doctrines.filter(func(entry): return entry.id == view.selected_doctrines[index])[0]
		_copy(ui,card,"방침 %d  ·  %s" % [index+1,item.get("name","미선택")],"",GameTheme.GOOD,19)
		_copy(ui,card,str(item.get("description","해금한 방침을 선택하세요.")),"",GameTheme.MUTED,18)
	var support: VBoxContainer = ui._box(row)
	support.name = "HouseSupplySlot"
	_copy(ui,support,"지원 물자  ·  "+_support_name(view),"",GameTheme.GOOD,19)
	_copy(ui,support,"해금한 6종 중 1종 · 부임 때 한 번 지급","",GameTheme.MUTED,18)


static func _cost_text(points: int, price: int) -> String:
	if points < price: return "비용  공훈 %d · 보유 %d · %d 부족" % [price,points,price-points]
	return "비용  공훈 %d · 구매 후 %d" % [price,points-price]


static func setup_summary(ui: Variant, parent: Node) -> void:
	var view: Dictionary = LegacyPath.overview(ui.session.profile)
	var learned: int = view.items.filter(func(item): return item.rank > 0).size()
	_copy(ui,parent,"가문 특성 %d개 · 방침 %d/2" % [learned,view.selected_doctrines.size()],"HouseSetupSummary",GameTheme.GOOD)
	_copy(ui,parent,"방침  "+_doctrine_names(view),"HouseSetupDoctrines",GameTheme.MUTED)
	var choices: Array[String] = []
	for pair in [["supply_packs","지원"],["perk_families","특전"],["relic_families","성물"]]:
		var chosen: String = str(view.preparation.get(PREP_KEYS[pair[0]],""))
		if chosen == "": continue
		for item in view.preparation_options[pair[0]]:
			if str(item.id) == chosen: choices.append(str(pair[1])+" "+str(item.name))
	if not choices.is_empty(): _copy(ui,parent," · ".join(choices),"HouseSetupSupport",GameTheme.MUTED)
	ui._button(parent,"가문 방침·지원 확인",func(): ui._open_house_preparation("prepare"),false,"SetupHouseChoices")


static func preparation_page(ui: Variant) -> void:
	var view: Dictionary = LegacyPath.overview(ui.session.profile)
	var frame: VBoxContainer = ui._plate(Rect2(36,28,ui.size.x-72,ui.size.y-56),false,20)
	frame.name = "HousePreparation"
	frame.add_theme_constant_override("separation",8)
	var header: HBoxContainer = ui._row(frame)
	ui._heading(header,"다음 부임 준비",true)
	ui._button(header,"돌아가기",func(): ui._go(ui.house_return),false,"LegacySetupBack")
	_copy(ui,frame,"가문 방침  %s  ·  %d/2 선택" % [_doctrine_names(view),view.selected_doctrines.size()],"HouseSelectedDoctrines",GameTheme.GOOD,20)
	_loadout(ui,frame,view)
	var tabs: HBoxContainer = ui._row(frame)
	for key in PREP_NAMES:
		var button: Button = ui._button(tabs,PREP_NAMES[key],func(): ui.house_setup_tab = key; ui.selected_house_option = ""; ui._render(),false,"house_setup_"+key)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if ui.house_setup_tab == key: ui._primary(button)
	var body: HBoxContainer = ui._row(frame)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",16)
	var list: VBoxContainer = _scroll(ui,body,"setup:"+ui.house_setup_tab)
	var detail: VBoxContainer = ui._card(body)
	_fixed(detail.get_parent(),420)
	detail.name = "HouseOptionDetail"
	if ui.house_setup_tab == "doctrines": _doctrines(ui,list,detail,view)
	else: _preparation_options(ui,list,detail,view)
	var footer: HBoxContainer = ui._row(frame)
	_copy(ui,footer,"선택은 다음 부임에 적용됩니다. 구매한 선택권을 다시 쓸 때 공훈은 들지 않습니다.","HousePreparationTiming",GameTheme.MUTED)
	ui._button(footer,"가문 강화",func(): ui._go("archive"),false,"HouseToTalents")


static func _choice_grid(list: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	list.add_child(grid)
	return grid


## 이름·상태 아래에 효과를 함께 적는 선택 카드.
static func _choice(ui: Variant, grid: Node, title: String, note: String, action: Callable, name: String) -> Button:
	var button: Button = ui._button(grid,title+("\n"+note if note != "" else ""),action,false,name)
	button.add_theme_font_size_override("font_size",18)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 76
	return button


## 특전·성물 계열에 속한 항목의 이름과 효과.
static func _family_members(ui: Variant, key: String, id: String) -> Array:
	var members: Array = []
	if id == "": return members
	if key == "perk_family":
		for perk in ui.session.content.progression.perks.values():
			if str(perk.get("family","")) == id: members.append({"name":str(perk.name),"text":str(perk.description)})
	elif key == "relic_family":
		for relic in ui.session.content.village_relics.relics.values():
			if str(relic.get("category","")) == id: members.append({"name":str(relic.name),"text":str(relic.text)})
	return members


static func _doctrines(ui: Variant, list: Node, detail: Node, view: Dictionary) -> void:
	var rows: Array = view.doctrines
	if not rows.any(func(item): return item.id == ui.selected_house_option): ui.selected_house_option = str(rows[0].id)
	var grid: GridContainer = _choice_grid(list)
	for item in rows:
		var status: String = "선택 중" if item.selected else "해금됨" if item.rank > 0 else "미해금"
		var button: Button = _choice(ui,grid,str(item.name)+" · "+status,str(item.description),func(): ui.selected_house_option = item.id; ui._render(),"house_doctrine_"+str(item.id))
		if item.id == ui.selected_house_option: ui._primary(button)
	var item: Dictionary = rows.filter(func(row): return row.id == ui.selected_house_option)[0]
	ui._heading(detail,str(item.name),true)
	_copy(ui,detail,"가문 방침 · "+("선택 중" if item.selected else "해금 완료" if item.rank > 0 else "미해금"),"DoctrineState",GameTheme.GOOD if item.selected else GameTheme.MUTED)
	var notes: VBoxContainer = ui._scroll(detail)
	var roomy: bool = ui.size.y >= 860
	_copy(ui,notes,str(item.description).replace(" · ","\n") if roomy else str(item.description),"DoctrineEffects",GameTheme.TEXT,20)
	if roomy and item.rank > 0:
		var after: Array = view.selected_doctrines.duplicate()
		var adding: bool = not item.selected and after.size() < 2
		if adding: after.append(item.id)
		ui._rule(notes)
		_copy(ui,notes,"고른 뒤의 방침 구성" if adding else "지금 방침 구성","DoctrineLoadout",GameTheme.MUTED)
		for id in after:
			var entry: Dictionary = rows.filter(func(row): return row.id == id)[0]
			_copy(ui,notes,str(entry.name),"",GameTheme.GOOD,19)
			_copy(ui,notes,str(entry.description),"",GameTheme.MUTED)
	_copy(ui,detail,"선택한 방침만 다음 부임에 적용됩니다.", "DoctrineApplication",GameTheme.MUTED)
	var lock: String = _active_lock(ui)
	if lock != "": _copy(ui,detail,lock,"DoctrineError",GameTheme.WARN)
	if item.rank == 0:
		ui._primary(ui._button(detail,"가문 강화에서 해금",func(): ui._open_house_talent(item.id),false,"DoctrineUnlockRoute"))
	elif item.selected:
		ui._button(detail,"선택 해제",func(): ui._remove_house_doctrine(item.id),ui._is_active() or ui.load_blocked,"RemoveDoctrine")
	elif view.selected_doctrines.size() < 2:
		ui._primary(ui._button(detail,"다음 부임 방침으로 선택",func(): ui._select_house_doctrine(item.id),ui._is_active() or ui.load_blocked or str(item.selection_error) != "","SelectDoctrine"))
	else:
		_copy(ui,detail,"교체할 방침 선택 · 해금 상태는 유지됩니다.","DoctrineReplaceHint",GameTheme.MUTED)
		for id in view.selected_doctrines:
			var previous: Dictionary = rows.filter(func(row): return row.id == id)[0]
			ui._button(detail,str(previous.name)+" 대신 선택",func(): ui._select_house_doctrine(item.id,id),ui._is_active() or ui.load_blocked,"replace_doctrine_"+str(id))


static func _preparation_options(ui: Variant, list: Node, detail: Node, view: Dictionary) -> void:
	var rows: Array = view.preparation_options.get(ui.house_setup_tab,[]).duplicate(true)
	rows.push_front({"id":"","name":"지원 물자 없음" if ui.house_setup_tab == "supply_packs" else "계열 지정 안 함","text":"","unlocked":true,"error":""})
	var key: String = PREP_KEYS[ui.house_setup_tab]
	var chosen: String = str(view.preparation.get(key,""))
	if not rows.any(func(item): return str(item.id) == ui.selected_house_option): ui.selected_house_option = str(rows[0].id)
	# 고를 것이 몇 개뿐이라 카드가 목록 높이를 나눠 채운다.
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid: GridContainer = _choice_grid(list)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for item in rows:
		var status: String = "선택 중" if str(item.id) == chosen else "선택 가능" if item.unlocked else "미해금"
		var members: Array = _family_members(ui,key,str(item.id))
		var note: String = str(item.get("text","")).replace("지원 물자: ","").replace(" · 지원 물자 1개 선택","")
		if key == "perk_family" and str(item.id) != "": note = str(ui.session.content.chronicle.families[item.id].description)
		elif key == "relic_family" and not members.is_empty(): note = "%s · %s 외 %d종" % [members[0].name,members[1].name,members.size()-2]
		elif str(item.id) == "": note = "받지 않고 시작합니다." if key == "supply_pack" else "모든 계열에서 무작위로 받습니다."
		var button: Button = _choice(ui,grid,str(item.name)+" · "+status,note,func(): ui.selected_house_option = str(item.id); ui._render(),"house_option_"+str(item.id))
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if str(item.id) == ui.selected_house_option: ui._primary(button)
	var item: Dictionary = rows.filter(func(row): return str(row.id) == ui.selected_house_option)[0]
	ui._heading(detail,str(item.name),true)
	if str(item.get("text","")) != "": _copy(ui,detail,str(item.text),"PreparationEffect",GameTheme.GOOD,20)
	var scope: String = "선택한 지원 물자는 새 통치 시작에 1회 지급됩니다.\n물자 예산으로 고르는 부임 물자와 함께 받을 수 있습니다."
	if key == "perk_family": scope = "첫 특전 제안에만 적용됩니다.\n고른 계열의 후보 1개가 포함되며, 3개 중 1개를 선택합니다."
	elif key == "relic_family": scope = "첫 성물 발견에만 적용됩니다.\n고른 계열의 후보 1개가 포함되며, 3개 중 1개를 선택합니다."
	if str(item.id) == "": scope = "지원 물자를 받지 않습니다." if key == "supply_pack" else "첫 제안도 계열을 지정하지 않고 받습니다."
	_copy(ui,detail,scope,"PreparationScope",GameTheme.MUTED,19)
	var family: Array = _family_members(ui,key,str(item.id))
	if family.is_empty(): ui._spacer(detail)
	else:
		# 계열을 고르면 무엇이 나올 수 있는지 상세 칸의 빈 자리에 보여 준다.
		ui._rule(detail)
		ui._heading(detail,"이 계열에서 나오는 %s %d종" % ["특전" if key == "perk_family" else "성물",family.size()])
		var catalog: VBoxContainer = ui._scroll(detail)
		catalog.name = "PreparationFamily"
		catalog.add_theme_constant_override("separation",2)
		for member in family:
			var line: Label = _copy(ui,catalog,"%s · %s" % [member.name,member.text],"",GameTheme.TEXT,18)
			line.max_lines_visible = 1
			line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			line.tooltip_text = "%s\n%s" % [member.name,member.text]
	var error: String = _active_lock(ui)
	if error == "": error = str(item.error)
	if error != "": _copy(ui,detail,error,"PreparationError",GameTheme.WARN)
	ui._primary(ui._button(detail,"선택 중" if str(item.id) == chosen else "다음 부임에 사용",func(): ui._set_house_preparation(key,str(item.id)),not item.unlocked or error != "" or ui.load_blocked or str(item.id) == chosen,"SelectPreparation"))
