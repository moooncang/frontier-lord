class_name StewardScreens
extends RefCounted
## 집무 장부의 보조 화면. 목록은 탐색, 본문은 판단, 하단은 실행에 쓴다.

const EFFECT_NAMES := {"trust":"신뢰", "security":"치안", "health":"건강", "guild":"길드 호감", "village":"주민 관계", "mood":"민심"}
const BONUS_NAMES := {"harvest":"수확", "sow_labor":"파종 노동", "seed":"종자 소모", "gather":"채집", "logging":"벌목", "tool_use":"도구 소모", "maintenance":"유지비", "wages":"공공 급여", "buy":"구매가", "storage":"저장 용량", "heating":"난방 소비", "tax":"수금률", "trust":"접견 신뢰", "winter_gather":"겨울 채집"}
const GOODS := {"food":"식량", "wood":"목재", "stone":"석재", "tools":"도구", "fuel":"장작"}


static func _split(ui: Variant, parent: Node, key: String) -> Dictionary:
	var row: HBoxContainer = ui._row(parent)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 22)
	var list: VBoxContainer = ui._scroll(row)
	list.add_theme_constant_override("separation", 4)
	var scroll: ScrollContainer = list.get_parent()
	scroll.name = key + "List"
	scroll.custom_minimum_size.x = 220
	scroll.size_flags_horizontal = 0
	var remembered: int = int(ui.get_meta(key + "_scroll", 0))
	scroll.get_v_scroll_bar().value_changed.connect(func(value: float): ui.set_meta(key + "_scroll", int(value)))
	scroll.set_deferred("scroll_vertical", remembered)
	var rule := VSeparator.new()
	row.add_child(rule)
	var body: VBoxContainer = ui._box(row)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	return {"list": list, "body": body}


static func _selection(ui: Variant, parent: Node, text: String, action: Callable, selected: bool, id: String) -> Button:
	var button: Button = ui._button(parent, text, action, false, id)
	ui._quiet(button)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	if selected:
		var style: StyleBoxFlat = TycoonTheme.panel(Color("e4dfd2"), Color.TRANSPARENT, 12)
		style.border_color = TycoonTheme.ACCENT
		style.border_width_left = 3
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		button.add_theme_stylebox_override("normal", style)
	return button


static func people(ui: Variant, parent: Node) -> void:
	var s: Dictionary = ui.session.state
	var characters: Dictionary = ui.session.content.chronicle.characters
	if not characters.has(ui.selected_person): ui.selected_person = characters.keys()[0]
	var panes: Dictionary = _split(ui, parent, "People")
	ui._label(panes.list, "이번 주 접견 %d회 남음" % s.actions, 18, GameTheme.MUTED)
	for id in characters:
		var visited: bool = "council_" + id in s.actions_used
		_selection(ui, panes.list, characters[id].name, func(): ui.selected_person = id; ui._render(), ui.selected_person == id, "person_" + id)
		if visited: ui._label(panes.list, "이번 주 접견 완료", 18, GameTheme.MUTED)
	var id: String = ui.selected_person
	var person: Dictionary = characters[id]
	var detail: VBoxContainer = ui._scroll(panes.body)
	detail.add_theme_constant_override("separation", 10)
	var head: HBoxContainer = ui._row(detail)
	ui._face(head, id, 80)
	var identity: VBoxContainer = ui._box(head)
	ui._heading(identity, person.name, true)
	ui._label(identity, person.role + " · " + person.age, 18, GameTheme.MUTED)
	ui._label(identity, person.quote, 19)
	ui._heading(detail, person.action)
	var before: float = s[person.effect]
	var gain: float = person.value + (WeekSim.bonus(s, "trust", 0) if person.effect == "trust" else 0.0)
	var after: float = minf(100.0, before + gain)
	var effect: String = EFFECT_NAMES.get(person.effect, person.effect)
	var visited: bool = "council_" + id in s.actions_used
	var receipt: Dictionary = ui.get_meta("steward_council_receipt", {})
	if receipt.get("id", "") == id and int(receipt.get("week", -1)) == int(s.week):
		ui._label(detail, receipt.text, 22, GameTheme.GOOD).name = "CouncilReceipt"
	elif visited:
		ui._label(detail, "이번 주 접견을 마쳤습니다. 현재 %s %.0f / 100" % [effect, before], 20, GameTheme.MUTED)
	else:
		ui._label(detail, "%s  %.0f → %.0f  (+%.0f)" % [effect, before, after, after - before], 22, GameTheme.TEAL)
		if is_equal_approx(before, after): ui._label(detail, "이미 상한에 도달했습니다. 접견해도 이 수치는 늘지 않습니다.", 18, GameTheme.WARN)
	ui._label(detail, "인물마다 주 1회 접견할 수 있습니다.", 18, GameTheme.MUTED)
	ui._rule(panes.body)
	var controls: HBoxContainer = ui._row(panes.body)
	var reason: String = "다음 주에 다시 접견할 수 있습니다." if visited else "이번 주 일정을 모두 사용했습니다." if int(s.actions) <= 0 else "접견 결과는 즉시 적용됩니다."
	ui._label(controls, reason, 18, GameTheme.MUTED)
	var locked: bool = not ui._is_active() or not ChronicleRules.active(s) or int(s.actions) <= 0 or visited
	var visit: Button = ui._button(controls, "이번 주 접견 완료" if visited else "접견하기 · 일정 1회", func():
		var previous: float = ui.session.state[person.effect]
		var error: String = ui.session.council_visit(id)
		if error == "":
			var current: float = ui.session.state[person.effect]
			var result: String = "접견 완료 · %s %.0f → %.0f (+%.0f)" % [effect, previous, current, current - previous]
			ui.set_meta("steward_council_receipt", {"id": id, "week": ui.session.state.week, "text": result})
			ui._sync_tutorial()
			ui._changed(result)
		else: ui._message(error)
	, locked, "CouncilVisit")
	visit.custom_minimum_size.y = 48
	ui._primary(visit)


static func boons(ui: Variant, parent: Node) -> void:
	var s: Dictionary = ui.session.state
	var content: Dictionary = ui.session.content
	var counts: Dictionary = ChronicleRules.family_counts(content, s)
	if ui.selected_perk not in s.perks: ui.selected_perk = "" if s.perks.is_empty() else s.perks[0]
	var panes: Dictionary = _split(ui, parent, "Boons")
	ui._label(panes.list, "보유 특전 %d / 8" % s.perks.size(), 18, GameTheme.MUTED)
	for id in s.perks:
		_selection(ui, panes.list, content.progression.perks[id].name, func(): ui.selected_perk = id; ui._render(), ui.selected_perk == id, "owned_" + id)
	if s.perks.is_empty(): ui._label(panes.list, "아직 획득한 특전이 없습니다.", 18)
	ui._label(panes.list, "이번 회차에 적용됩니다.\n가문 강화는 별도로 구매합니다.", 18, GameTheme.MUTED)
	var detail: VBoxContainer = ui._scroll(panes.body)
	if ui.selected_perk != "":
		var perk: Dictionary = content.progression.perks[ui.selected_perk]
		ui._heading(detail, perk.name, true)
		ui._label(detail, perk.description, 22, GameTheme.TEAL)
		ui._label(detail, "%s 계열 · %d개 보유" % [content.chronicle.families[perk.family].name, counts[perk.family]], 18, GameTheme.MUTED)
	else:
		ui._heading(detail, "이번 회차의 성장", true)
		ui._label(detail, "회차를 시작할 때 특전 1개를 고르고, 이후 6·13·20·26·33·39·46주에 추가로 선택합니다.", 19)
	ui._heading(detail, "특전 세트")
	var has_family := false
	for family_id in counts:
		var family: Dictionary = content.chronicle.families[family_id]
		var count: int = int(counts[family_id])
		if count == 0: continue
		has_family = true
		var status: String = "4개 세트 적용" if count >= 4 else "2개 세트 적용" if count >= 2 else "%d개 더 모으면 첫 세트" % (2 - count)
		ui._label(detail, "%s %d개 · %s" % [family.name, count, status], 20, GameTheme.TEAL if count >= 2 else GameTheme.TEXT)
		ui._label(detail, family.description.replace("2장:", "2개:").replace("4장:", "4개:"), 18, GameTheme.MUTED)
	if not has_family: ui._label(detail, "같은 계열의 특전 2개·4개를 모으면 특전 세트 효과가 적용됩니다.", 18, GameTheme.MUTED)
	if ChronicleRules.active(s):
		ui._heading(detail, "영주 특성")
		for id in s.traits:
			var trait_data: Dictionary = content.chronicle.traits[id]
			ui._label(detail, trait_data.name + " · " + trait_data.description, 19, GameTheme.WARN if trait_data.get("flaw", false) else GameTheme.TEXT)
		ui._heading(detail, "부임 물자")
		for id in s.relics:
			var relic: Dictionary = content.chronicle.relics[id]
			ui._label(detail, relic.name + " · " + relic.description, 19)
		ui._heading(detail, "현재 합산 효과")
		for key in s.bonuses:
			var amount: float = s.bonuses[key]
			if (key in ChronicleRules.ADDITIVE and is_zero_approx(amount)) or (key not in ChronicleRules.ADDITIVE and is_equal_approx(amount, 1.0)): continue
			var value: String = ("%+.0f" % amount if key == "trust" else "%+.0f%%p" % (amount * 100)) if key in ChronicleRules.ADDITIVE else "%+.0f%%" % ((amount - 1) * 100)
			ui._label(detail, BONUS_NAMES.get(key, key) + " " + value, 19)
	else:
		ui._label(detail, "이전 회차 규칙입니다. 특전 세트과 부임 물자는 새 회차부터 적용됩니다.", 18, GameTheme.WARN)


static func archive(ui: Variant, parent: Node) -> void:
	var upgrades: Dictionary = ui.session.content.progression.upgrades
	var profile: Dictionary = ui.session.profile
	if not upgrades.has(ui.selected_upgrade): ui.selected_upgrade = upgrades.keys()[0]
	var panes: Dictionary = _split(ui, parent, "Archive")
	ui._label(panes.list, "보유 공훈 %d점" % profile.points, 20)
	for id in upgrades:
		_selection(ui, panes.list, upgrades[id].name, func(): ui.selected_upgrade = id; ui._render(), ui.selected_upgrade == id, "meta_" + id)
		ui._label(panes.list, "구매 완료" if id in profile.upgrades else "%d 공훈" % upgrades[id].cost, 18, GameTheme.MUTED)
	var id: String = ui.selected_upgrade
	var upgrade: Dictionary = upgrades[id]
	var owned: bool = id in profile.upgrades
	var prerequisite: bool = upgrade.requires != "" and upgrade.requires not in profile.upgrades
	var shortfall: int = maxi(0, int(upgrade.cost) - int(profile.points))
	var detail: VBoxContainer = ui._scroll(panes.body)
	ui._heading(detail, upgrade.name, true)
	ui._label(detail, upgrade.description, 22, GameTheme.TEAL)
	ui._label(detail, "다음 회차부터 영구 적용", 19, GameTheme.MUTED)
	if owned:
		ui._label(detail, "구매 완료 · 영구 적용", 20, GameTheme.GOOD)
	else:
		ui._label(detail, "구매 비용 %d점 · 보유 %d점" % [upgrade.cost, profile.points], 20)
		if prerequisite: ui._label(detail, "먼저 구매해야 합니다: " + upgrades[upgrade.requires].name, 19, GameTheme.WARN)
		elif shortfall > 0: ui._label(detail, "공훈 %d점이 더 필요합니다." % shortfall, 19, GameTheme.WARN)
		else: ui._label(detail, "구매 후 공훈 %d점이 남습니다." % (profile.points - upgrade.cost), 19, GameTheme.MUTED)
	ui._heading(detail, "회차 기록")
	ui._label(detail, "완료한 회차 %d회 · 발견한 특전 %d / %d개" % [profile.get("chronicles", []).size(), profile.get("discoveries", []).size(),ui.session.content.progression.perks.size()], 18)
	for record in profile.get("chronicles", []).slice(-3):
		ui._label(detail, "%d주 · %s · 공훈 +%d" % [record.week, "성공" if record.success else record.reason, record.points], 18, GameTheme.MUTED)
	ui._label(detail, "13주 이상 생존 후 결산 보상\n계절 +2점 · 계약 +3점 · 기본 목표당 +6점 · 시련 +6점", 18, GameTheme.MUTED)
	ui._rule(panes.body)
	var actions: HBoxContainer = ui._row(panes.body)
	var back: Button = ui._button(actions, "새 회차 준비" if not ui._is_active() else "주간 보고로", func():
		if ui._is_active(): ui._continue()
		else: ui._open_prepare()
	, ui.load_blocked)
	ui._quiet(back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buy: Button = ui._button(actions, "구매 완료" if owned else "구매 · %d 공훈" % upgrade.cost, func(): ui._upgrade(id), owned or prerequisite or shortfall > 0 or ui.load_blocked, "upgrade_" + id)
	buy.custom_minimum_size.y = 48
	ui._primary(buy)


static func market(ui: Variant, parent: Node) -> void:
	var s: Dictionary = ui.session.state
	var panes: Dictionary = _split(ui, parent, "Market")
	ui._label(panes.list, "거래할 공공 재고", 18, GameTheme.MUTED)
	for id in GOODS:
		_selection(ui, panes.list, "%s  %.0f" % [GOODS[id], s.public[id]], func(): ui.selected_goods = id; ui._render(), ui.selected_goods == id, "goods_" + id)
	ui._label(panes.list, "금고 " + ui._money(s.public.money), 20)
	ui._label(panes.list, "운송 기간 2주\n남은 수레 %d / 3대" % (3 - s.shipments.size()), 18, GameTheme.MUTED)
	var id: String = ui.selected_goods
	ui._heading(panes.body, GOODS[id] + " 교역")
	var controls: HBoxContainer = ui._row(panes.body)
	ui._label(controls, "거래 수량", 19)
	var quantity := SpinBox.new()
	quantity.name = "quantity_" + id
	quantity.min_value = 1
	quantity.max_value = 200
	quantity.value = int(ui.trade_quantities.get(id, {"food":200, "wood":40, "stone":40, "tools":8, "fuel":120}[id]))
	quantity.custom_minimum_size.x = 180
	quantity.editable = ui._is_active() and not ui.busy
	controls.add_child(quantity)
	var detail: VBoxContainer = ui._scroll(panes.body)
	ui._label(detail, "구매: 지금 선불 지출 → %d주에 물자 도착\n판매: 지금 재고 출고 → %d주에 대금 수령" % [s.week + 2, s.week + 2], 19)
	ui._label(detail, "표시 금액에는 운송료가 포함됩니다.", 18, GameTheme.MUTED)
	ui._heading(detail, "운송 중 %d / 3대" % s.shipments.size())
	for shipment in s.shipments:
		ui._label(detail, "%s %d · %d주에 %s" % [GOODS[shipment.asset], shipment.quantity, shipment.arrival, "물자 도착" if shipment.buy else "판매 대금 수령"], 19)
	if s.shipments.is_empty(): ui._label(detail, "운송 중인 수레가 없습니다.", 18, GameTheme.MUTED)
	var reason: Label = ui._label(panes.body, "", 18, GameTheme.MUTED)
	reason.name = "trade_reason_" + id
	var actions: HBoxContainer = ui._row(panes.body)
	var buy: Button = ui._button(actions, "", func(): ui._command_trade(id, int(quantity.value), true), false, "buy_" + id)
	var sell: Button = ui._button(actions, "", func(): ui._command_trade(id, int(quantity.value), false), false, "sell_" + id)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.custom_minimum_size.y = 48
	sell.custom_minimum_size.y = 48
	ui._primary(buy)
	quantity.value_changed.connect(func(value: float): ui.trade_quantities[id] = int(value); ui._refresh_quote(id, int(value), buy, sell, reason))
	ui._refresh_quote(id, int(quantity.value), buy, sell, reason)
