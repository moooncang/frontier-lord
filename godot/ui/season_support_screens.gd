class_name SeasonSupportScreens
extends RefCounted
## A seasonal purchase is optional, expires with the season, and uses the same public stores as construction.

const RESOURCE_NAMES := {"food":"식량","wood":"목재","stone":"석재","tools":"도구","fuel":"장작","iron":"철"}
const SUPPORT_ART := {"SS01":"farm","SS02":"smithy","SS03":"depot","SS04":"garden","SS05":"logging","SS06":"storage","SS07":"farm","SS08":"logging","SS09":"storage","SS10":"clinic","SS11":"depot","SS12":"watchtower"}
## 난도 불이익마다 어떻게 대비하면 되는지 한 줄.
const ADVICE := {"buy":"물자 구매가 비싸집니다. 식량과 목재는 직접 생산하는 편이 유리합니다.", "maintenance":"시설이 많을수록 금고 부담이 커집니다. 필요한 시설부터 지으세요.", "tool_use":"벌목과 채석이 도구를 더 빨리 씁니다. 도구 재고를 넉넉히 두세요.", "heating":"겨울 장작이 더 듭니다. 가을까지 장작을 더 쌓아 두세요.", "threat_growth":"변경의 위협이 빨리 자랍니다. 치안을 높게 유지하고 방어 시설을 일찍 준비하세요."}
const EFFECT_NAMES := {"gather":"채집 생산","logging":"벌목 생산","tool_use":"도구 소모","maintenance":"시설 유지비","build_work":"새 공사 작업량","wages":"공공 급여","garden":"채소 생산","spoil":"창고 손실","storage":"저장 용량","harvest":"곡물 수확","heating":"난방 장작","threat_growth":"위협 증가"}


static func _copy(ui: Variant, parent: Node, value: String, id: String = "", color: Color = GameTheme.TEXT, px: int = 19) -> Label:
	return HouseScreens._copy(ui,parent,value,id,color,px)


static func _cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for key in cost:
		var amount := float(cost[key])
		if amount <= 0: continue
		parts.append("%.2f금" % (amount/100.0) if key == "money" else "%s %s" % [RESOURCE_NAMES.get(key,key),str(int(amount)) if is_equal_approx(amount,roundf(amount)) else "%.1f" % amount])
	return " · ".join(parts) if not parts.is_empty() else "비용 없음"


static func banner(ui: Variant, parent: Node) -> void:
	var view: Dictionary = SeasonalInvestments.overview(ui.session.state,ui.session.content)
	if not view.enabled: return
	if not view.offer.is_empty():
		var button: Button = ui._button(parent,"계절 지원 도착  ·  %d주까지 선택" % int(view.expires),func(): ui._go("season_support"),false,"OpenSeasonSupport")
		button.tooltip_text = "세 가지 지원 중 하나를 구매하거나 이번 계절은 건너뛸 수 있습니다. 선택하지 않아도 주를 진행할 수 있습니다."
	elif not view.active.is_empty():
		var button: Button = ui._quiet(ui._button(parent,"%s  ·  %d주 남음" % [view.active.name,view.remaining],func(): ui._go("season_support"),false,"OpenSeasonSupport"))
		button.tooltip_text = str(view.active.text)


static func _effects(item: Dictionary) -> String:
	var lines: Array[String] = []
	for key in item.get("mods",{}): lines.append("%s  %+.0f%%" % [EFFECT_NAMES.get(key,key),(float(item.mods[key])-1.0)*100.0])
	for key in item.get("targets",{}): lines.append("%s 목표  %+.0f" % [RealmRules.NAMES.get(key,key),float(item.targets[key])])
	return "\n".join(lines)


static func _scope(item: Dictionary) -> String:
	if item.get("mods",{}).has("build_work"): return "이미 진행 중인 공사의 남은 작업량은 그대로입니다."
	if item.get("mods",{}).has("harvest"): return "남은 33~36주 수확에만 적용됩니다."
	if item.get("mods",{}).has("spoil"): return "마당에 보관한 식량의 손실률은 그대로입니다."
	if not item.get("targets",{}).is_empty(): return "건강·민심·치안은 매주 목표를 향해 변합니다."
	return "계절이 끝나면 이 효과는 사라집니다."


static func page(ui: Variant) -> void:
	var view: Dictionary = SeasonalInvestments.overview(ui.session.state,ui.session.content)
	var frame: VBoxContainer = ui._plate(ui._sheet(36,28),false,20)
	frame.name = "SeasonSupportPage"
	var header: HBoxContainer = ui._row(frame)
	ui._heading(header,"계절 지원",true)
	ui._spacer(header)
	ui._button(header,"영지로 돌아가기",func(): ui._go("estate"),false,"CloseSeasonSupport")
	_copy(ui,frame,"이번 계절에 필요한 지원 하나를 고르세요. 비용은 공공 재고에서 지불합니다.","SupportScope",GameTheme.MUTED)
	var stock: Dictionary = ui.session.state.get("public",{})
	_copy(ui,frame,"보유  "+_cost({"money":stock.get("money",0),"food":stock.get("food",0),"wood":stock.get("wood",0),"stone":stock.get("stone",0),"tools":stock.get("tools",0),"fuel":stock.get("fuel",0)}),"SupportStores",GameTheme.GOOD)
	if not view.enabled:
		_copy(ui,frame,"이 통치에서는 계절 지원을 사용하지 않습니다.","SupportUnavailable",GameTheme.MUTED)
		return
	if not view.active.is_empty():
		var active: Dictionary = view.active
		var card: VBoxContainer = ui._card(frame)
		card.name = "ActiveSeasonSupport"
		ui._heading(card,str(active.name))
		_copy(ui,card,str(active.text),"ActiveSupportEffect",GameTheme.GOOD,22)
		_copy(ui,card,"%d주까지 적용 · 남은 기간 %d주" % [active.until,view.remaining],"ActiveSupportDuration")
		_copy(ui,card,"지불한 비용  "+_cost(active.cost),"ActiveSupportCost",GameTheme.MUTED)
		_copy(ui,card,"이번 계절의 지원을 선택했습니다. 표시된 적용 기간이 끝나면 효과가 사라집니다.","SupportChosen",GameTheme.MUTED)
		return
	if view.offer.is_empty():
		_copy(ui,frame,"현재 선택할 지원이 없습니다. 다음 계절에 새 제안이 도착합니다.","NoSeasonSupport",GameTheme.MUTED)
		return
	_copy(ui,frame,"제안은 %d주까지 · 적용 기간은 지원마다 확인 · 3종 중 1종" % int(view.expires),"SupportDuration",GameTheme.WARN)
	var row: HBoxContainer = ui._row(frame)
	row.name = "SeasonSupportOffers"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",14)
	for item in view.offer:
		var card: VBoxContainer = ui._card(row)
		card.name = "SupportCard_"+str(item.id)
		var head: HBoxContainer = ui._row(card)
		var grown: float = 96.0 + clampf((ui.size.y - 720.0) * 0.5, 0.0, 90.0)
		var art: TextureRect = ui._art(head,"building_"+str(SUPPORT_ART.get(item.id,"depot")),Vector2(grown,grown))
		art.name = "SupportArt_"+str(item.id)
		var title: VBoxContainer = ui._box(head)
		ui._heading(title,str(item.name))
		_copy(ui,title,"이번 계절에만 적용","",GameTheme.MUTED,18)
		var detail: VBoxContainer = ui._scroll(card)
		detail.name = "SupportEffect_"+str(item.id)
		_copy(ui,detail,_effects(item),"",GameTheme.GOOD,22)
		_copy(ui,detail,_scope(item),"",GameTheme.MUTED,18)
		if ui.size.y >= 860: _copy(ui,detail,str(item.text),"",GameTheme.TEXT,18)
		detail.tooltip_text = str(item.text)
		_copy(ui,card,"지출  "+_cost(item.cost),"SupportCost_"+str(item.id),GameTheme.TEXT,20)
		_copy(ui,card,"기간  지금부터 %d주까지" % int(item.until),"SupportUntil_"+str(item.id),GameTheme.MUTED)
		var error: String = str(item.error)
		if error != "": _copy(ui,card,error,"SupportError_"+str(item.id),GameTheme.WARN,18)
		ui._primary(ui._button(card,"이 지원 구매",func(): _buy(ui,str(item.id)),error != "" or ui.load_blocked,"buy_support_"+str(item.id)))
	var footer: HBoxContainer = ui._row(frame)
	_copy(ui,footer,"선택을 미뤄도 주를 진행할 수 있습니다.","SupportOptional",GameTheme.MUTED)
	ui._spacer(footer)
	ui._button(footer,"이번 계절은 지원 없이",func(): _decline(ui),ui.load_blocked,"DeclineSeasonSupport")


static func _buy(ui: Variant, id: String) -> void:
	var error: String = ui.session.choose_support(id)
	if error != "": ui._message(error); return
	var active: Dictionary = SeasonalInvestments.overview(ui.session.state,ui.session.content).active
	ui._changed("계절 지원을 구매했습니다. %d주까지 적용됩니다." % int(active.get("until",ui.session.state.week)))


static func _decline(ui: Variant) -> void:
	var error: String = ui.session.decline_support()
	if error != "": ui._message(error); return
	ui.page = "estate"
	ui._changed("이번 계절은 지원 없이 운영합니다.")


static func prepare(ui: Variant, parent: Node) -> void:
	var view: Dictionary = FrontierDifficulty.overview(ui.session.profile,ui.session.content)
	var level: int = clampi(int(ui.draft_difficulty),0,int(view.unlocked))
	var current: Dictionary = view.levels[level]
	var button: Button = ui._button(parent,"개척 난도 %d  ·  결산 공훈 +%d  ›" % [level,current.bonus_points],func(): ui.set_meta("frontier_inspect",level); ui._go("frontier_setup"),false,"OpenFrontierDifficulty")
	button.tooltip_text = "13주를 완료한 뒤 결산하면 추가 공훈을 받습니다. 통치 중에는 난도를 바꿀 수 없습니다.\n"+_rules(current)


static func _rules(row: Dictionary) -> String:
	var lines: Array[String] = []
	for rule in row.get("rules",[]): lines.append(str(rule.text))
	return "추가 불이익 없음" if lines.is_empty() else "\n".join(lines)


static func _level_name(row: Dictionary) -> String:
	return "기본 통치" if row.rules.is_empty() else str(row.rules[-1].name)


static func difficulty_page(ui: Variant) -> void:
	var view: Dictionary = FrontierDifficulty.overview(ui.session.profile,ui.session.content)
	var inspected: int = clampi(int(ui.get_meta("frontier_inspect",ui.draft_difficulty)),0,view.levels.size()-1)
	var current: Dictionary = view.levels[inspected]
	var frame: VBoxContainer = ui._plate(ui._sheet(36,28),false,20)
	frame.name = "FrontierDifficultyPage"
	var header: HBoxContainer = ui._row(frame)
	ui._heading(header,"개척 난도",true)
	ui._spacer(header)
	ui._button(header,"부임 준비로",func(): ui._go("prepare"),false,"CloseFrontierDifficulty")
	_copy(ui,frame,"난도는 직접 선택합니다. 해금한 최고 난도로 통치에 성공하면 다음 단계가 열립니다.","FrontierScope",GameTheme.MUTED)
	var body: HBoxContainer = ui._row(frame)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",20)
	var left: VBoxContainer = ui._box(body)
	left.name = "FrontierLevels"
	left.size_flags_stretch_ratio = 0.85
	for item in view.levels:
		var status: String = "선택 중" if int(item.level) == int(ui.draft_difficulty) else "선택 가능" if item.unlocked else "미해금"
		var burden: String = "추가 불이익 없음" if item.rules.is_empty() else str(item.rules[-1].text)
		var button: Button = ui._quiet(ui._button(left,"%d  %s  ·  %s\n%s · 공훈 +%d" % [item.level,_level_name(item),status,burden,int(item.bonus_points)],func(): ui.set_meta("frontier_inspect",int(item.level)); ui._render(),false,"difficulty_"+str(item.level)))
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",18)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		HouseScreens._selected(button,int(item.level) == inspected)
	var detail: VBoxContainer = ui._card(body)
	detail.name = "FrontierDetail"
	ui._heading(detail,"난도 %d · %s" % [inspected,_level_name(current)])
	_copy(ui,detail,"이전 단계의 불이익도 모두 적용됩니다.","FrontierCumulative",GameTheme.MUTED)
	var rules: VBoxContainer = ui._scroll(detail)
	rules.name = "FrontierRules"
	_copy(ui,rules,_rules(current),"FrontierRuleText",GameTheme.TEXT,21)
	var tips: Array[String] = []
	for rule in current.get("rules",[]):
		for key in rule.mods:
			if ADVICE.has(key): tips.append("· "+str(ADVICE[key]))
	if not tips.is_empty():
		ui._rule(rules)
		_copy(ui,rules,"대비","",GameTheme.MUTED,18)
		_copy(ui,rules,"\n".join(tips),"FrontierAdvice",GameTheme.TEXT,19)
	_copy(ui,detail,"13주 이상 통치 결산  공훈 +%d" % int(current.bonus_points),"FrontierReward",GameTheme.GOOD,22)
	if not current.unlocked: _copy(ui,detail,str(current.error),"FrontierLocked",GameTheme.WARN)
	ui._primary(ui._button(detail,"이 난도로 부임 준비",func(): ui.draft_difficulty = inspected; ui._go("prepare"),not current.unlocked or ui.load_blocked,"ConfirmFrontierDifficulty"))


static func result(ui: Variant, parent: Node) -> void:
	var ending: Dictionary = ui.session.state.get("result",{})
	if not ending.has("difficulty_level"): return
	var view: Dictionary = FrontierDifficulty.overview(ui.session.profile,ui.session.content)
	var level := int(ending.difficulty_level)
	_copy(ui,parent,"개척 난도 %d  ·  추가 공훈 %d" % [level,int(ending.get("difficulty_points",0))],"DifficultyResult",GameTheme.GOOD)
	var target := "최고 난도까지 통치에 성공했습니다. 다른 운영 조합에 도전하세요."
	if not bool(ending.get("success",false)):
		target = "다음 목표: 난도 %d 통치 성공. 가문 강화와 지원 구성을 바꿔 다시 준비하세요." % level
	elif int(view.unlocked) > level:
		target = "다음 목표: 개척 난도 %d. 부임 준비에서 새 불이익과 보상을 확인하세요." % int(view.unlocked)
	_copy(ui,parent,target,"NextFrontierGoal",GameTheme.MUTED,19)
