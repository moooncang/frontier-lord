class_name RelicScreens
extends RefCounted
## 성물의 선택·장착·발견 기록을 같은 데이터로 표시한다. 보상은 세션만 지급한다.

const COLORS := {"abundance":Color("426f47"),"craft":Color("9a5d32"),"guard":Color("365f7d")}

static func image(ui: Variant, parent: Node, key: String, extent: int) -> TextureRect:
	var art: TextureRect = ui._art(parent,key,Vector2(extent,extent))
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


static func scene(ui: Variant, parent: Node, height: int, equipped: Array) -> void:
	var stage := Control.new()
	stage.name = "SanctuaryStage"
	stage.custom_minimum_size.y = height
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stage)
	var background := TextureRect.new()
	background.texture = ui.assets.texture("scene_relic_shrine")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	stage.clip_contents = true
	var relics: Array[TextureRect] = []
	for item in equipped:
		var art := image(ui,stage,str(item.icon),86)
		art.tooltip_text = str(item.name)
		relics.append(art)
	# The source's three alcoves are at x=570/770/963, y=390 on a 1536x1024 canvas.
	# Keep those alcoves in frame at both window sizes, and place items inside them.
	var arrange := func():
		var scale: float = stage.size.x / 1536.0
		background.size = Vector2(stage.size.x,1024.0 * scale)
		background.position.y = stage.size.y * 0.5 - 390.0 * scale
		var centers := [570.0,770.0,963.0]
		for index in relics.size():
			relics[index].size = Vector2(86,86)
			relics[index].position = Vector2(centers[index] * scale - 43,stage.size.y * 0.5 - 43)
	stage.resized.connect(arrange)
	arrange.call_deferred()


static func page(ui: Variant, parent: Node) -> void:
	var definitions: Dictionary = VillageRelics.definitions()
	var info: Dictionary = VillageRelics.overview(ui.session.state,ui.session.content)
	var discovered: Array = ui.session.profile.get("relic_discoveries",[])
	var top: HBoxContainer = ui._row(parent)
	var guide: String = "장착한 성물만 적용 · 같은 계열 2개로 성물 세트 적용"
	if CrisisDirector.enabled(ui.session.state): guide = "장착 3칸 · 같은 계열 2개 세트 · 확장 성물 포함 3개 전문화"
	ui._label(top,"한 번 발견한 성물은 기록에 남습니다 · 새 통치에서는 다시 획득" if ui.page == "relic_codex" else guide,18,GameTheme.MUTED)
	if ui.page != "relic_codex":
		ui._button(top,"보관함 보기" if ui.relic_collection else "발견 도감 %d / %d" % [discovered.size(),definitions.relics.size()],func(): ui.relic_collection = not ui.relic_collection; ui._render(),false,"RelicCollection")
		if _builds_enabled(ui): ui._button(top,"운영 조합",func(): ui._go("operating_builds"),false,"SanctuaryBuilds")
	else: ui._label(top,"발견 %d / %d" % [discovered.size(),definitions.relics.size()],20,GameTheme.GOOD)
	var body: HBoxContainer = ui._row(parent)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	var left: VBoxContainer = ui._box(body,1.7)
	left.add_theme_constant_override("separation",8)
	if not ui.relic_collection:
		scene(ui,left,64 if ui.size.y < 800 else 144,info.equipped)
		var slots: HBoxContainer = ui._row(left)
		for index in 3:
			var item: Dictionary = info.equipped[index] if index < info.equipped.size() else {}
			var button: Button = ui._button(slots,"%d  %s" % [index+1,item.name if not item.is_empty() else "빈 성물칸"],func():
				if not item.is_empty(): ui.selected_relic = item.id; ui._render()
			,false,"relic_slot_%d" % index)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size",18)
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.tooltip_text = str(item.get("text","성물을 얻으면 빈칸에 자동으로 장착됩니다."))
			if not item.is_empty() and item.id == ui.selected_relic: ui._primary(button)
		var set_lines: Array[String] = []
		for item in info.sets: set_lines.append(str(item.set_text))
		var sets: Label = ui._label(left,"\n".join(set_lines) if not set_lines.is_empty() else "성물 세트 없음 · 같은 계열 2개 장착 시 적용",18,GameTheme.GOOD if not set_lines.is_empty() else GameTheme.MUTED)
		sets.max_lines_visible = 2
		sets.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sets.tooltip_text = "\n".join(set_lines)
	var filters: HBoxContainer = ui._row(left)
	filters.name = "RelicFamilyFilters"
	for entry in [["","전체"],["abundance","풍요"],["craft","공방"],["guard","수호"]]:
		var filter: Button = ui._button(filters,entry[1],func(): ui.relic_family_filter = entry[0]; ui._render(),false,"relic_filter_"+str(entry[0]))
		filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter.custom_minimum_size.y = 32
		filter.add_theme_font_size_override("font_size",18)
		if ui.relic_family_filter == entry[0]: ui._primary(filter)
	var inventory: VBoxContainer = ui._scroll(left)
	inventory.name = "RelicInventory"
	var inventory_scroll: ScrollContainer = inventory.get_parent()
	inventory_scroll.name = "RelicInventoryScroll"
	inventory_scroll.set_meta("collection",ui.relic_collection)
	var scroll_key: String = ("collection" if ui.relic_collection else "owned")+":"+ui.relic_family_filter
	inventory_scroll.set_meta("scroll_key",scroll_key)
	ui._restore_relic_scroll.call_deferred(inventory_scroll,int(ui.relic_scroll_positions.get(scroll_key,0)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory.add_child(grid)
	var ids: Array = definitions.relics.keys() if ui.relic_collection else ui.session.state.get("realm",{}).get("sanctuary",{}).get("owned",[])
	ids = ids.filter(func(id): return ui.relic_family_filter == "" or definitions.relics[id].category == ui.relic_family_filter)
	if ui.selected_relic not in ids: ui.selected_relic = "" if ids.is_empty() else str(ids[0])
	if ids.is_empty():
		ui._label(inventory,"아직 성물이 없습니다.\n유적 조사·행상 교환·촌락 승격에서 획득할 수 있습니다.",20,GameTheme.MUTED)
	for id in ids:
		var item: Dictionary = definitions.relics[id]
		var known: bool = id in discovered
		var tile: VBoxContainer = ui._card(grid)
		tile.add_theme_constant_override("separation",2)
		var art := image(ui,tile,str(item.icon),48 if ui.relic_collection else 40)
		if not known: art.modulate = Color(0.12,0.15,0.18,0.65)
		var button: Button = ui._button(tile,item.name if known else "미발견",func(): ui.selected_relic = id; ui._render(),false,"relic_pick_"+str(id))
		button.add_theme_font_size_override("font_size",18)
		button.custom_minimum_size = Vector2(0,34)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(item.name) if known else "발견 후 효과를 확인할 수 있습니다."
		if id == ui.selected_relic: ui._primary(button)
	var detail: VBoxContainer = ui._card(body)
	detail.add_theme_constant_override("separation",4)
	detail.name = "RelicDetail"
	detail.get_parent().size_flags_stretch_ratio = 1.0
	detail.get_parent().custom_minimum_size.x = 340
	_detail(ui,detail,info,definitions,discovered)


static func _detail(ui: Variant, parent: Node, info: Dictionary, definitions: Dictionary, discovered: Array) -> void:
	var id: String = ui.selected_relic
	if id == "" and not info.owned.is_empty(): id = str(info.owned[0].id)
	if not definitions.relics.has(id):
		ui._heading(parent,"마을의 성물",true)
		ui._label(parent,"사건에서 성물을 얻고, 성소에 세 개까지 장착합니다.",21)
		ui._rule(parent)
		ui._label(parent,"풍요 · 식량과 수확\n공방 · 건설과 자재\n수호 · 치안과 겨울",20)
		ui._label(parent,"발견 기록은 다음 통치에도 남습니다. 성물은 새 통치에서 다시 획득합니다.",18,GameTheme.MUTED)
		return
	var item: Dictionary = definitions.relics[id]
	var known: bool = id in discovered
	var category: Dictionary = definitions.categories[item.category]
	var head: HBoxContainer = ui._row(parent)
	var art := image(ui,head,str(item.icon),56)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if not known: art.modulate = Color(0.12,0.15,0.18,0.65)
	var heading: VBoxContainer = ui._box(head)
	heading.add_theme_constant_override("separation",2)
	ui._heading(heading,str(item.name) if known else "미발견 성물",false)
	ui._label(heading,str(category.name)+" 계열",18,COLORS[item.category])
	if not known:
		ui._label(parent,"유적 조사와 거래, 마을 승격 보상에서 발견할 수 있습니다.",20)
		return
	var effects: VBoxContainer = ui._scroll(parent)
	effects.name = "RelicEffectScroll"
	ui._label(effects,str(item.text),21)
	ui._rule(effects)
	ui._label(effects,str(category.set_text),18,GameTheme.MUTED)
	if category.has("plus_set") and (CrisisDirector.enabled(ui.session.state) or ui.page == "relic_codex"):
		ui._label(effects,str(category.plus_set.set_text),18,GameTheme.WARN)
	if _builds_enabled(ui): relic_routes(ui,effects,id)
	var owned: bool = info.owned.any(func(row): return row.id == id)
	var equipped: bool = info.equipped.any(func(row): return row.id == id)
	var fired: Array = info.last_result.get("triggered",[])
	for row in fired:
		if row.id == id: ui._label(effects,"지난주 발동 · "+RealmRules.changes_text(row.effects),18,GameTheme.GOOD)
	if ui.page == "relic_codex":
		ui._label(parent,"발견 기록 · 성물의 장착과 교체는 통치 중 마을 성소에서 합니다.",18,GameTheme.MUTED)
	elif not owned:
		ui._label(parent,"발견 기록 · 이번 통치에서는 아직 보유하지 않았습니다.",18,GameTheme.MUTED)
	elif equipped:
		ui._label(parent,"성소 장착 중 · 효과 적용",18,GameTheme.GOOD)
		_change_preview(ui,effects,"",id)
		ui._button(parent,"성소에서 빼서 보관",func(): ui._unequip_relic(id),not ui._is_active(),"unequip_relic_"+id)
	elif info.equipped.size() < 3:
		_change_preview(ui,effects,id)
		ui._primary(ui._button(parent,"빈칸에 장착",func(): ui._equip_relic(id),not ui._is_active(),"equip_relic_"+id))
	else:
		var changes: Array[String] = []
		if _builds_enabled(ui):
			for index in info.equipped.size():
				var change: Dictionary = OperatingBuilds.preview(ui.session.state,ui.session.content,"",id,str(info.equipped[index].id))
				if not change.deactivated.is_empty() and not change.activated.is_empty(): changes.append("%d번: %s → %s" % [index+1,_names(ui,change.deactivated),_names(ui,change.activated)])
				elif not change.deactivated.is_empty(): changes.append("%d번: %s 해제" % [index+1,_names(ui,change.deactivated)])
				elif not change.activated.is_empty(): changes.append("%d번: %s 활성" % [index+1,_names(ui,change.activated)])
		if not changes.is_empty():
			var fixed_preview: Label = ui._label(parent,"\n".join(changes),18,GameTheme.WARN)
			fixed_preview.name = "FixedBuildChangePreview"
			fixed_preview.add_theme_constant_override("line_spacing",0)
		ui._label(parent,"교체할 성물칸 선택 · 기존 성물은 보관",18,GameTheme.MUTED)
		var choices: HBoxContainer = ui._row(parent)
		choices.add_theme_constant_override("separation",6)
		for index in info.equipped.size():
			var old: Dictionary = info.equipped[index]
			_change_preview(ui,effects,id,str(old.id),"%d번 교체" % (index+1))
			var button: Button = ui._button(choices,"%d번 교체\n%s" % [index+1,old.name],func(): ui._equip_relic(id,old.id),not ui._is_active(),"replace_relic_"+str(old.id))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.tooltip_text = str(old.name)+" 대신 "+str(item.name)+" 장착\n"+_preview_text(ui,id,str(old.id))
			button.add_theme_font_size_override("font_size",18)


static func offer(ui: Variant) -> void:
	var info: Dictionary = VillageRelics.overview(ui.session.state,ui.session.content)
	var defs: Dictionary = VillageRelics.definitions()
	ui._shade(ui.interface,0.8).name = "DecisionBlocker"
	var box: VBoxContainer = ui._window("마을에 가져갈 성물",Vector2(minf(1100,ui.size.x-80),minf(620,ui.size.y-70)),false,true)
	ui.current_modal = box.get_parent()
	ui.current_modal.set_meta("kind","relic_choice")
	box.name = "RelicOffer"
	ui._label(box,"세 개 중 하나 선택 · 빈 성물칸에 자동 장착 · 칸이 가득 차면 보관",18,GameTheme.MUTED)
	var cards: HBoxContainer = ui._row(box)
	cards.name = "RelicChoices"
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for item in info.offer:
		var card: VBoxContainer = ui._card(cards)
		image(ui,card,item.icon,88)
		var category: Dictionary = defs.categories[item.category]
		ui._label(card,category.name+" 성물",18,COLORS[item.category])
		ui._heading(card,item.name)
		var detail: VBoxContainer = ui._scroll(card)
		ui._label(detail,item.text,20)
		if _builds_enabled(ui): relic_routes(ui,detail,item.id)
		if info.equipped.size() < 3: _change_preview(ui,detail,item.id)
		else: ui._label(detail,"획득 시 보관 · 성소에서 교체하면 조합 적용",18,GameTheme.MUTED)
		var count: int = info.equipped.filter(func(held): return held.category == item.category).size()
		ui._label(card,"현재 같은 계열 %d개 장착" % count,18,GameTheme.MUTED)
		if count == 1 and info.equipped.size() < 3: ui._label(card,"장착하면 성물 세트 적용",18,GameTheme.GOOD)
		ui._primary(ui._button(card,"이 성물 획득",func(): ui._take_relic(item.id),false,"take_relic_"+str(item.id)))
	var actions: HBoxContainer = ui._row(box)
	ui._button(actions,"영지를 보고 결정",func(): ui.decision_hidden = true; ui._render(),false,"InspectRelicEstate")
	var refreshes: int = int(ui.session.state.get("legacy_setup",{}).get("relic_refreshes",0))
	if refreshes > 0:
		ui._button(actions,"성물 후보 새로고침 · %d회" % refreshes,ui._refresh_house_relics,false,"RefreshRelics")
	ui._focus_decision.call_deferred()


static func acquired(ui: Variant, id: String) -> void:
	var defs: Dictionary = VillageRelics.definitions()
	if not defs.relics.has(id): return
	var item: Dictionary = defs.relics[id]
	var equipped: bool = id in ui.session.state.realm.sanctuary.equipped
	ui._shade(ui.interface,0.8).name = "DecisionBlocker"
	var box: VBoxContainer = ui._window("성물 획득",Vector2(720,minf(570,ui.size.y-80)),false,true)
	ui.current_modal = box.get_parent()
	ui.current_modal.set_meta("kind","relic_acquired")
	box.name = "RelicAcquired"
	var art := image(ui,box,item.icon,160)
	art.modulate.a = 0.0
	ui.create_tween().tween_property(art,"modulate:a",1.0,0.3)
	ui._heading(box,item.name,true)
	ui._label(box,item.text,22)
	ui._label(box,"성소에 장착했습니다. 이번 통치에 효과가 적용됩니다." if equipped else "보관함에 넣었습니다. 성소에서 기존 성물과 교체할 수 있습니다.",19,GameTheme.GOOD)
	ui._spacer(box)
	var actions: HBoxContainer = ui._row(box)
	ui._button(actions,"성소 확인",func(): ui.relic_reward = ""; ui._go("sanctuary"),false,"RelicAcquiredSanctuary")
	ui._primary(ui._button(actions,"운영 계속",func(): ui.relic_reward = ""; ui._render(),false,"RelicAcquiredContinue"))


static func environments(ui: Variant, parent: Node, preview: bool = false) -> void:
	var rows: Array = ExpeditionModifiers.preview(ui.session.content,ui.draft_seed) if preview else ExpeditionModifiers.overview(ui.session.state,ui.session.content)
	if rows.is_empty(): return
	var box: VBoxContainer = ui._box(parent)
	box.name = "RunEnvironments"
	box.add_theme_constant_override("separation",4)
	for item in rows:
		var label: Label = ui._label(box,("기회 · " if item.kind == "opportunity" else "제약 · ")+item.name+"\n"+item.description,18,GameTheme.GOOD if item.kind == "opportunity" else GameTheme.WARN)
		label.tooltip_text = item.hint


static func triggers(ui: Variant, parent: Node) -> void:
	if not VillageRelics.enabled(ui.session.state): return
	var result: Dictionary = ui.session.state.realm.sanctuary.last_result
	if int(result.get("week",0)) != int(ui.session.state.week)-1: return
	for item in result.get("triggered",[]):
		var row: HBoxContainer = ui._row(parent)
		image(ui,row,str(VillageRelics.definitions().relics[item.id].icon),40).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ui._label(row,"성물 발동 · "+item.name+"\n"+RealmRules.changes_text(item.effects),19,GameTheme.GOOD)
	for item in result.get("builds",[]):
		var line: Label = ui._label(parent,"운영 조합 · "+str(item.name)+"\n"+RealmRules.changes_text(item.effects),19,GameTheme.GOOD)
		line.name = "OperatingBuildResult_"+str(item.id)


static func _builds_enabled(ui: Variant) -> bool:
	return CrisisDirector.enabled(ui.session.state) and VillageRelics.enabled(ui.session.state)


static func _names(ui: Variant, ids: Array) -> String:
	var names: Array[String] = []
	for item in OperatingBuilds.overview(ui.session.state,ui.session.content):
		if item.id in ids: names.append(str(item.name))
	return " · ".join(names)


static func _preview_text(ui: Variant, relic_id: String, replace_id: String = "") -> String:
	if not _builds_enabled(ui): return ""
	var change: Dictionary = OperatingBuilds.preview(ui.session.state,ui.session.content,"",relic_id,replace_id)
	var lines: Array[String] = []
	if not change.activated.is_empty(): lines.append("활성 · "+_names(ui,change.activated))
	if not change.deactivated.is_empty(): lines.append("해제 · "+_names(ui,change.deactivated))
	return "\n".join(lines) if not lines.is_empty() else "운영 조합의 활성 상태 유지"


static func _change_preview(ui: Variant, parent: Node, relic_id: String, replace_id: String = "", caption: String = "장착 변경") -> void:
	if not _builds_enabled(ui): return
	var label: Label = ui._label(parent,caption+" → "+_preview_text(ui,relic_id,replace_id),18,GameTheme.TEAL)
	label.name = "BuildChangePreview_"+replace_id


static func relic_routes(ui: Variant, parent: Node, relic_id: String) -> void:
	if not _builds_enabled(ui): return
	var definitions: Dictionary = VillageRelics.definitions()
	for item in OperatingBuilds.overview(ui.session.state,ui.session.content):
		if relic_id not in item.relics: continue
		ui._rule(parent)
		var family: String = ui.session.content.chronicle.families[item.family].name
		var pair: Array[String] = []
		for id in item.relics: pair.append(str(definitions.relics[id].name))
		var label: Label = ui._label(parent,"운영 조합 · "+str(item.name)+"\n"+" 또는 ".join(pair)+" 중 1개\n%s 특전 %d개 · 필요 %d개 · %s" % [family,item.perks_owned,item.perk_count,"성물 1/1" if item.equipped_count > 0 else "성물 0/1"],18,GameTheme.GOOD if item.active else GameTheme.MUTED)
		label.name = "RelicBuildRoute_"+str(item.id)
		ui._label(parent,str(item.text),18)


static func perk_routes(ui: Variant, parent: Node, perk_id: String, candidate: bool = false) -> void:
	if not _builds_enabled(ui): return
	var perk: Dictionary = ui.session.content.progression.perks[perk_id]
	var preview: Dictionary = OperatingBuilds.preview(ui.session.state,ui.session.content,perk_id) if candidate else {"activated":[]}
	var area: VBoxContainer = ui._box(parent)
	area.name = "PerkBuildRoutes_"+perk_id
	for item in OperatingBuilds.overview(ui.session.state,ui.session.content):
		if item.family != perk.family: continue
		var text: String = str(item.name)+(" · 성물 1/1\n" if item.equipped_count > 0 else " · 성물 0/1\n")
		if candidate and item.perks_owned < item.perk_count: text += "특전 %d → %d/%d" % [item.perks_owned,item.perks_owned+1,item.perk_count]
		else: text += "특전 %d/%d" % [mini(item.perks_owned,item.perk_count),item.perk_count]
		if item.id in preview.activated: text += " · 선택 시 활성"
		elif item.active: text += " · 활성 중"
		ui._label(area,text,18,GameTheme.GOOD if item.id in preview.activated or item.active else GameTheme.MUTED)


static func perk_impact(ui: Variant, parent: Node, perk_id: String) -> void:
	if not _builds_enabled(ui): return
	var preview: Dictionary = OperatingBuilds.preview(ui.session.state,ui.session.content,perk_id)
	var text := ""
	if not preview.activated.is_empty(): text = "선택 시 활성 · "+_names(ui,preview.activated)
	else:
		var family: String = ui.session.content.progression.perks[perk_id].family
		var rows: Array = OperatingBuilds.overview(ui.session.state,ui.session.content).filter(func(row): return row.family == family)
		if rows.is_empty(): return
		rows.sort_custom(func(a,b): return a.equipped_count > b.equipped_count)
		var item: Dictionary = rows[0]
		text = str(item.name)+(" · 특전 조건 충족" if item.perks_owned >= item.perk_count else " · 특전 %d → %d/%d" % [item.perks_owned,item.perks_owned+1,item.perk_count])
	var label: Label = ui._label(parent,text,18,GameTheme.GOOD if not preview.activated.is_empty() else GameTheme.MUTED)
	label.name = "PerkBuildImpact_"+perk_id


static func builds_summary(ui: Variant, parent: Node) -> void:
	if not _builds_enabled(ui): return
	var rows: Array = OperatingBuilds.overview(ui.session.state,ui.session.content)
	var names: Array[String] = []
	for item in rows:
		if item.active: names.append(str(item.name))
	ui._heading(parent,"운영 조합 · %d개 활성" % names.size())
	ui._label(parent," · ".join(names) if not names.is_empty() else "연결 성물 1개와 지정 계열 특전 2개로 운영 방식을 강화합니다.",18,GameTheme.GOOD if not names.is_empty() else GameTheme.MUTED)
	ui._button(parent,"운영 조합 12개 확인",func(): ui._go("operating_builds"),false,"OpenOperatingBuilds")
	ui._rule(parent)


static func builds_page(ui: Variant, parent: Node) -> void:
	if not _builds_enabled(ui):
		ui._label(parent,"운영 조합은 새 통치의 성물과 특전으로 구성합니다.",20)
		return
	var rows: Array = OperatingBuilds.overview(ui.session.state,ui.session.content)
	if rows.is_empty(): return
	if not rows.any(func(item): return item.id == ui.selected_operating_build): ui.selected_operating_build = str(rows[0].id)
	ui._label(parent,"연결된 두 성물 중 1개 장착 + 지정 계열 특전 2개 · 성물 3칸으로 여러 조합을 함께 구성할 수 있습니다",18,GameTheme.MUTED)
	var body: HBoxContainer = ui._row(parent)
	body.name = "OperatingBuildsPage"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	var list: VBoxContainer = ui._scroll(body)
	var scroll: ScrollContainer = list.get_parent()
	scroll.name = "OperatingBuildListScroll"
	scroll.custom_minimum_size.x = 290
	scroll.size_flags_horizontal = Control.SIZE_FILL
	ui._restore_relic_scroll.call_deferred(scroll,ui.operating_build_scroll)
	var selected: Dictionary = rows[0]
	for item in rows:
		var text: String = ("활성 · " if item.active else "")+str(item.name)+"\n%s · 특전 %d/%d" % ["성물 1/1" if item.equipped_count > 0 else "성물 0/1",mini(item.perks_owned,item.perk_count),item.perk_count]
		var choice: Button = ui._button(list,text,func(): ui.selected_operating_build = item.id; ui._render(),false,"operating_build_"+str(item.id))
		choice.add_theme_font_size_override("font_size",18)
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.custom_minimum_size.y = 60
		if item.id == ui.selected_operating_build: ui._primary(choice); selected = item
	var detail: VBoxContainer = ui._card(body)
	detail.name = "OperatingBuildDetail"
	ui._heading(detail,str(selected.name),true)
	ui._label(detail,str(selected.text),20).name = "OperatingBuildEffect"
	var family: String = ui.session.content.chronicle.families[selected.family].name
	var progress: Label = ui._label(detail,"%s · 성물 %d/1 · %s 특전 %d/%d" % ["활성 중" if selected.active else "조건 충족 시 자동 활성",mini(selected.equipped_count,1),family,mini(selected.perks_owned,selected.perk_count),selected.perk_count],18,GameTheme.GOOD if selected.active else GameTheme.MUTED)
	progress.name = "OperatingBuildProgress"
	progress.tooltip_text = "%s 계열 특전 %d개 보유 · 필요 %d개" % [family,selected.perks_owned,selected.perk_count]
	var effects: VBoxContainer = ui._scroll(detail)
	effects.name = "OperatingBuildRequirements"
	var definitions: Dictionary = VillageRelics.definitions()
	ui._label(effects,"아래 성물 중 1개 이상 장착",18,GameTheme.MUTED)
	for id in selected.relics:
		var item: Dictionary = definitions.relics[id]
		var row: HBoxContainer = ui._row(effects)
		image(ui,row,str(item.icon),56).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var equipped: bool = id in ui.session.state.realm.sanctuary.equipped
		ui._label(row,("✓ " if equipped else "○ ")+str(item.name)+( " · 장착" if equipped else " · 보관 중" if id in ui.session.state.realm.sanctuary.owned else " · 미보유"),20,GameTheme.GOOD if equipped else GameTheme.TEXT)
	ui._label(effects,"자원 변환은 실제 주간 조건과 비용을 모두 충족할 때 한 번 실행합니다. 비용이 부족하면 지급도 없습니다.",18,GameTheme.MUTED)
	var actions: HBoxContainer = ui._row(detail)
	ui._button(actions,"성소에서 장착",func(): ui._go("sanctuary"),false,"BuildGoSanctuary")
	ui._button(actions,"특전 계열 확인",func(): ui.boon_family_filter = selected.family; ui._go("boons"),false,"BuildGoPerks")


static func builds_results(ui: Variant, parent: Node) -> void:
	if not _builds_enabled(ui): return
	var rows: Array = OperatingBuilds.overview(ui.session.state,ui.session.content)
	ui._rule(parent)
	ui._heading(parent,"통치를 마친 운영 조합")
	var active: Array = rows.filter(func(item): return item.active)
	if active.is_empty(): ui._label(parent,"마지막 장착에서 활성인 운영 조합은 없습니다.",18,GameTheme.MUTED)
	for item in active:
		ui._label(parent,str(item.name)+" · "+str(item.text),19).name = "FinalBuild_"+str(item.id)
