extends "res://tests/test_realm_playflow.gd"
## Actual production input for shrine discovery, three equipment slots and saved relics.
## Additional draft fixtures use the real offer generator; no item is inserted by the UI test.

var received: Array[String] = []

func _start(guide: bool) -> void:
	await _click("NewRun")
	screen.draft_seed = 61427
	screen.guide_enabled = guide
	await _click("PrepareNext")
	var conditions := ExpeditionModifiers.preview(screen.session.content, screen.draft_seed)
	_check(conditions.size() == 2, "new expedition previews one opportunity and one constraint")
	var detail := _control("SetupDetail")
	for condition in conditions:
		_check(_text(detail).contains(str(condition.name)), "world setup discloses the actual seeded condition: " + str(condition.id))
	for item in detail.find_children("*", "Control", true, false):
		if item is Label or item is BaseButton:
			var ancestor := item.get_parent()
			while ancestor != null:
				if ancestor is ScrollContainer: ancestor.ensure_control_visible(item)
				ancestor = ancestor.get_parent()
			await _frames(2)
			_check(_inside(item), "world setup text and actions are reachable by scrolling at 720p: " + str(item.name))
	_check(_inside(_control("PrepareNext")) and _inside(_control("RerollWorld")), "world setup preserves both reroll and progress actions")
	await _shot("00_world_setup_720")
	await _click("PrepareNext")
	await _click("StartRun")
	_check(RealmRules.enabled(screen.session.state), "real new-run setup enables realm rules")
	_check(ExpeditionModifiers.overview(screen.session.state, screen.session.content) == conditions, "starting the run applies the conditions actually shown before departure")

func _shot(tag: String) -> void:
	await _frames(8)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty(), "rendered relic screen " + tag)
	if picture != null and not picture.is_empty():
		_check(picture.save_png("res://tests/output/relics_" + tag + ".png") == OK, "saved relic screen " + tag)

func _wheel_end(scroller: ScrollContainer) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = scroller.get_global_rect().get_center()
	root.push_input(motion)
	for tick in 14:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = true
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await _frames(2)
	await _frames()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _fresh("relics")
	await _start(false)
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	await _presentation_contract()
	if "--board-only" in OS.get_cmdline_user_args():
		await _finish_relics()
		return
	_check(VillageRelics.enabled(screen.session.state), "new production run enables village relics")
	await _first_discovery()
	await _equipment_and_storage()
	await _reload_current_run()
	await _codex_and_next_run()
	await _expanded_layout_fixture()
	await _finish_relics()

func _draft(source: String) -> String:
	var error := VillageRelics.request_offer(screen.session.state, screen.session.content, source)
	if not _check(error == "", "real discovery generator accepts " + source): return ""
	screen.decision_hidden = false
	screen._go("estate")
	await _frames()
	var offered: Array = screen.session.state.realm.sanctuary.offer
	if not _check(not offered.is_empty(), "fixture reward has selectable candidates"): return ""
	var id := str(offered[0])
	for candidate in offered:
		if not received.is_empty() and str(candidate).left(1) == received[0].left(1):
			id = str(candidate)
			break
	var stock: Dictionary = screen.session.state.public.duplicate(true)
	await _click("take_relic_" + id)
	_check(id in screen.session.state.realm.sanctuary.owned and screen.session.state.public == stock, "candidate choice records ownership without duplicating a reward: " + id)
	received.append(id)
	if _visible("RelicAcquiredContinue"): await _click("RelicAcquiredContinue")
	return id

func _reload_current_run() -> void:
	var directory: String = screen.save_directory
	var inventory: Dictionary = screen.session.state.realm.sanctuary.duplicate(true)
	var discoveries: Array = screen.session.profile.relic_discoveries.duplicate()
	root.remove_child(screen)
	screen.queue_free()
	await _frames()
	screen = load("res://ui/main.tscn").instantiate()
	screen.save_directory = directory
	root.add_child(screen)
	await _frames()
	await _click("ContinueRun")
	_check(screen.session.state.realm.sanctuary == inventory, "continuing the real save preserves equipped, stored, offered and processed relic metadata")
	_check(screen.session.profile.relic_discoveries == discoveries, "relic codex discoveries survive save reload")
	_check(SaveStore.valid(screen.session.bundle()), "reloaded relic state remains valid for the next autosave")

func _first_discovery() -> void:
	await _click("side_tab_projects")
	await _click("FocusAction")
	await _click("build_B13")
	for attempt in 4:
		if int(screen.session.state.week) >= 4: break
		await _settle()
		await _click("NextWeek")
	_check(screen.session.state.active_event == "RS_RUINS", "fourth-week ruins event is reached through real time progression")
	if screen.session.state.active_event != "RS_RUINS": return
	await _shot("01_ruins_720")
	var money: float = screen.session.state.public.money
	var tools_before: float = screen.session.state.public.tools
	await _reveal("event_option_0")
	await _click("event_option_0")
	_check(is_equal_approx(float(screen.session.state.public.money), money - 200) and is_equal_approx(float(screen.session.state.public.tools), tools_before - 1), "restoring the relic case charges the displayed event cost exactly once")
	if _visible("AcknowledgeOutcome"): await _click("AcknowledgeOutcome")
	var offer: Array = screen.session.state.realm.sanctuary.offer
	_check(offer.size() == 3, "ruins discovery offers three distinct relic choices")
	if offer.is_empty(): return
	for id in offer: _check(_inside(_control("take_relic_" + str(id))), "all first relic choices fit within 720p: " + str(id))
	await _shot("02_choice_720")
	var id := str(offer[mini(1, offer.size() - 1)])
	var stock: Dictionary = screen.session.state.public.duplicate(true)
	await _click("take_relic_" + id)
	received.append(id)
	_check(id in screen.session.state.realm.sanctuary.owned and id in screen.session.state.realm.sanctuary.equipped, "chosen relic is owned and fills the first empty equipment slot")
	_check(id in screen.session.profile.relic_discoveries and screen.session.state.public == stock, "discovery persists in the codex without granting a second economic reward")
	_check(screen.session.state.realm.sanctuary.offer.is_empty(), "one selection consumes the pending draft")
	_check(_visible("RelicAcquired"), "receiving the first relic has visible acquisition feedback")
	await _shot("03_acquired_720")
	await _click("RelicAcquiredContinue")
	await _click("RelicShrine")
	_check(screen.page == "sanctuary" and _visible("RelicInventory"), "actual shrine click opens equipment and storage")
	await _shot("04_sanctuary_720")
	_check(SaveStore.valid(screen.session.bundle()), "first relic and current run stay saveable")

func _equipment_and_storage() -> void:
	for index in 3: await _draft("ui_fixture:discovery_%d" % index)
	var value: Dictionary = screen.session.state.realm.sanctuary
	if not _check(value.owned.size() == 4 and value.equipped.size() == 3, "four real choices fill three slots and put the fourth relic in storage"): return
	var stored := str(value.owned[3])
	var old := str(value.equipped[0])
	await _click("nav_sanctuary")
	await _reveal("relic_pick_" + stored)
	await _click("relic_pick_" + stored)
	_check(screen.selected_relic == stored, "actual inventory click selects the stored relic")
	_check(_text(_control("RelicDetail")).contains("교체"), "stored relic explains that replacement is required when the shrine is full")
	var dock_top: float = _control("RunDock").get_parent().get_global_rect().position.y
	for id in value.equipped:
		var replacement := _control("replace_relic_" + str(id))
		_check(_inside(replacement) and replacement.get_global_rect().end.y <= dock_top - 4, "all three replacement actions are reachable above the dock at 720p: " + str(id))
	await _shot("05_replace_720")
	var stock: Dictionary = screen.session.state.public.duplicate(true)
	await _click("replace_relic_" + old)
	_check(stored in value.equipped and old not in value.equipped and old in value.owned and value.equipped.size() == 3, "replacement swaps one equipped relic and preserves the old relic in storage")
	_check(screen.session.state.public == stock, "replacement does not repeat an acquisition or weekly reward")
	await _click("unequip_relic_" + stored)
	_check(value.equipped.size() == 2 and stored in value.owned, "unequipping preserves ownership and frees exactly one slot")
	await _click("equip_relic_" + stored)
	_check(value.equipped.size() == 3 and stored in value.equipped, "the stored relic can be equipped in the empty slot")
	# Four relics across three categories guarantee at least one real two-relic set.
	var definitions := VillageRelics.definitions()
	var counts := {}
	var pair: Array = []
	for id in value.owned:
		var category: String = definitions.relics[id].category
		if not counts.has(category): counts[category] = []
		counts[category].append(id)
		if counts[category].size() == 2: pair = counts[category].duplicate()
	if _check(pair.size() == 2, "owned relics provide a real combination to equip"):
		for id in pair:
			if id in value.equipped: continue
			var removable := ""
			for equipped in value.equipped:
				if equipped not in pair: removable = str(equipped); break
			await _reveal("relic_pick_" + str(id))
			await _click("relic_pick_" + str(id))
			_check(screen.selected_relic == str(id), "inventory remains clickable immediately after an equipment update")
			await _click("replace_relic_" + removable)
			_check(id in value.equipped and removable not in value.equipped, "real replacement equips the intended combination piece")
		var category: String = definitions.relics[pair[0]].category
		_check(category in VillageRelics.bonuses(screen.session.state, screen.session.content).sets, "two equipped relics activate their category combination")
		_check(_text(screen.interface).contains(str(definitions.categories[category].set_text)), "active combination is explained on the equipment screen")
	await _shot("06_combination_720")
	root.size = Vector2i(1440, 900)
	await _frames(10)
	for index in 3: _check(_inside(_control("relic_slot_%d" % index)), "equipped slot remains visible at 900p")
	await _shot("07_sanctuary_900")
	await _click("RelicCollection")
	_check(screen.relic_collection and _control("RelicInventory").find_children("relic_pick_*", "Button", true, false).size() == definitions.relics.size(), "collection displays all relic definitions including unknown silhouettes")
	await _shot("08_collection_900")
	await _click("RelicCollection")
	await _click("BackEstate")
	await _click("nav_build")
	await _click("district_civic")
	_check(screen.realm_board.shrine.tooltip_text.contains("3 / 3") and screen.realm_board.shrine.tooltip_text.contains("4개"), "map shrine reflects three equipped and four owned relics after swapping")
	_check(SaveStore.valid(screen.session.bundle()), "equipment, storage and combinations remain saveable")

func _codex_and_next_run() -> void:
	root.size = Vector2i(1280, 720)
	await _frames(10)
	await _click("nav_menu")
	await _click("OpenCodex")
	await _click("OpenRelicCodex")
	_check(screen.page == "relic_codex" and _visible("RelicInventory"), "main-menu discovery route opens the relic codex")
	await _reveal("relic_pick_" + received[0])
	await _click("relic_pick_" + received[0])
	_check(_text(_control("RelicDetail")).contains(str(VillageRelics.definitions().relics[received[0]].name)), "persisted discovery shows the real relic details")
	for prefix in ["equip_relic_", "unequip_relic_", "replace_relic_"]:
		_check(_control("RelicDetail").find_children(prefix + "*", "Button", true, false).is_empty(), "menu codex remains read-only: " + prefix)
	await _shot("09_meta_codex_720")
	await _click("RelicCodexBack")
	await _key(KEY_ESCAPE)
	await _click("ContinueRun")
	await _click("MoreActions")
	await _click("more_journey")
	await _reveal("RetireRun")
	await _click("RetireRun")
	var dialogs := screen.find_children("*", "ConfirmationDialog", true, false)
	if not _check(dialogs.size() == 1, "ending the test run requires the real retirement confirmation"): return
	# Existing native retirement confirmation is already covered by legacy UI tests.
	# Cross that boundary explicitly; every new relic control uses pointer input.
	var dialog: ConfirmationDialog = dialogs[0]
	dialog.confirmed.emit()
	await _frames()
	if not _check(screen.session.state.status == "finalized" and _visible("ResultRestart"), "confirming the retirement dialog settles the run"): return
	var discoveries: Array = screen.session.profile.relic_discoveries.duplicate()
	await _shot("10_run_result_720")
	await _click("ResultRestart")
	screen.guide_enabled = false
	await _click("PrepareNext")
	await _click("PrepareNext")
	await _click("StartRun")
	await _click("perk_" + str(screen.session.state.perk_offer[0]))
	_check(screen.session.state.realm.sanctuary.owned.is_empty() and screen.session.state.realm.sanctuary.equipped.is_empty(), "new run starts with empty relic ownership and equipment")
	_check(screen.session.profile.relic_discoveries == discoveries, "new run retains every codex discovery")
	await _click("RelicShrine")
	if not screen.relic_collection: await _click("RelicCollection")
	await _reveal("relic_pick_" + received[0])
	await _click("relic_pick_" + received[0])
	_check(_text(_control("RelicDetail")).contains("아직 보유하지"), "known relic clearly distinguishes discovery from current-run ownership")
	_check(not _visible("equip_relic_" + received[0]), "historical discovery cannot be equipped without earning the relic again")
	await _shot("11_next_run_codex_720")

## Layout-only inventory fixture, after real acquisition/save/new-run verification.
## Its grants are isolated to this test's private save and never imply earned rewards.
func _expanded_layout_fixture() -> void:
	root.size = Vector2i(1280, 720)
	var definitions := VillageRelics.definitions()
	var value: Dictionary = screen.session.state.realm.sanctuary
	value.owned = ["G05", "G06", "G08", "C05", "F08"]
	value.equipped = ["G05", "G06", "G08"]
	value.offer = []
	value.offer_source = ""
	screen.session.profile.relic_discoveries = definitions.relics.keys()
	screen.selected_relic = "G06"
	screen.relic_collection = false
	RealmRules.refresh(screen.session.state, screen.session.content)
	screen._go("sanctuary")
	await _frames(12)
	_check(VillageRelics.bonuses(screen.session.state, screen.session.content).surges == ["guard"], "three expansion guard relics activate the real specialization for layout inspection")
	_check(_text(screen.interface).contains(str(definitions.categories.guard.plus_set.set_text)), "active three-slot specialization explains its benefit and cost")
	for id in definitions.relics:
		if definitions.relics[id].get("plus_only", false):
			_check(screen.assets.texture(str(definitions.relics[id].icon)) != null, "new relic has a real imported pixel texture: " + str(id))
	var effect_scroll := _control("RelicEffectScroll").get_parent() as ScrollContainer
	_check(effect_scroll != null and _inside(effect_scroll) and effect_scroll.size.y >= 64, "long relic effects retain a usable bounded scroll area at 720p")
	_check(_inside(_control("unequip_relic_G06")), "long conditional description leaves the equipment action visible")
	await _shot("12_specialization_720")
	await _wheel_end(effect_scroll)
	var detail_labels := _control("RelicEffectScroll").find_children("*", "Label", true, false)
	_check(not detail_labels.is_empty() and _inside(detail_labels[-1]), "actual wheel reveals the complete specialization clause in the effect pane")
	_check(_inside(_control("unequip_relic_G06")), "scrolling effects leaves the equipment action fixed and visible")
	await _shot("12b_effects_scrolled_720")
	await _reveal("relic_pick_C05")
	await _click("relic_pick_C05")
	var dock_top: float = _control("RunDock").get_parent().get_global_rect().position.y
	for id in value.equipped:
		var action := _control("replace_relic_" + str(id))
		_check(_inside(action) and action.get_global_rect().end.y < dock_top - 4, "long expanded description preserves every replacement action above the dock: " + str(id))
	await _shot("13_expanded_replace_720")
	await _click("replace_relic_G05")
	_check("C05" in value.equipped and "G05" not in value.equipped and VillageRelics.bonuses(screen.session.state, screen.session.content).surges.is_empty(), "actual replacement removes the guard specialization and its penalty")
	await _click("RelicCollection")
	await _reveal("relic_pick_G08")
	var collection_scroll := _control("RelicInventoryScroll") as ScrollContainer
	var prior_scroll := collection_scroll.scroll_vertical
	await _click("relic_pick_G08")
	_check(_control("RelicInventory").find_children("relic_pick_*", "Button", true, false).size() == definitions.relics.size() and screen.selected_relic == "G08", "the full relic catalog remains reachable through the actual scrollable collection")
	var restored_scroll := (_control("RelicInventoryScroll") as ScrollContainer).scroll_vertical
	_check(prior_scroll > 0 and restored_scroll == prior_scroll, "selecting a lower collection item preserves the actual list scroll position after rerender: %d -> %d" % [prior_scroll, restored_scroll])
	await _shot("14_expanded_collection_720")
	root.size = Vector2i(1440, 900)
	await _frames(12)
	await _shot("15_expanded_collection_900")


func _presentation_contract() -> void:
	await _click("nav_build")
	await _click("district_civic")
	var fixture := RealmBoard.new()
	fixture.position = screen.realm_board.global_position
	fixture.size = screen.realm_board.size
	root.add_child(fixture)
	var state: Dictionary = screen.session.state.duplicate(true)
	var seen := {"clicks":0}
	fixture.shrine_selected.connect(func(): seen.clicks += 1)
	state.realm.erase("sanctuary")
	fixture.configure(screen.assets, state, screen.session.content, "", true)
	await _frames()
	_check(fixture.lots.size() == 22 and not fixture.shrine.visible, "legacy map has the same 22 facility lots and no shrine")
	state.realm["sanctuary"] = {"enabled":true,"equipped":["F01","C01","G01"],"owned":["F01","C01","G01","F02"],"offer":[]}
	for id in ["B16", "B25", "B27", "B33", "B67", "B71"]: state.facilities[id] = 1
	state.labor_report = {"farm":4,"logging":4,"fuel":0,"quarry":3,"realm_by":{"B16":4,"B33":3}}
	state.week = 14
	state.realm.weather = "summer_monsoon"
	var before := JSON.stringify(state)
	fixture.configure(screen.assets, state, screen.session.content, "", true)
	await _frames()
	_check(fixture.shrine.visible and fixture.shrine.tooltip_text.contains("3 / 3") and fixture.shrine.tooltip_text.contains("4개"), "shrine distinguishes three equipped relics from four total owned relics")
	for id in ["B13", "B16", "B25", "B27", "B33"]:
		_check(fixture.lots[id].get_node("OperatingEffect").visible, "executed work activates facility detail: " + id)
	_check(fixture.lots.B67.get_node("OperatingEffect").visible and fixture.raining, "built defenses and actual rainy weather receive their map details")
	await _pointer(fixture.shrine.get_global_rect().get_center())
	_check(seen.clicks == 1, "actual shrine pointer emits one navigation request")
	await _shot("00_map_activity_fixture_720")
	_check(JSON.stringify(state) == before, "rendering and shrine interaction never mutate economic or relic state")
	fixture.configure(screen.assets, state, screen.session.content, "", false)
	await _frames()
	await _pointer(fixture.shrine.get_global_rect().get_center())
	_check(fixture.shrine.disabled and seen.clicks == 1, "disabled map blocks shrine interaction")
	state.labor_report = {}
	state.week = 40
	state.realm.weather = "winter_frost"
	state.realm.sanctuary.offer = ["F03","C02","G02"]
	fixture.configure(screen.assets, state, screen.session.content, "", true)
	await _frames()
	for id in ["B13", "B16", "B25", "B27", "B33"]:
		_check(not fixture.lots[id].get_node("OperatingEffect").visible, "idle facility cannot imply production: " + id)
	_check(fixture.season == 3 and fixture.lots.B13.get_node("Art").texture.resource_path.ends_with("building_farm_winter.tres"), "winter fields use the harvested dormant crop sprite")
	_check(fixture.shrine.get_node("ShrineOffer").visible, "pending relic choice has a shrine marker")
	await _shot("00_map_winter_fixture_720")
	paused = true
	var paused_clock: float = fixture.clock
	await _frames(4)
	_check(is_equal_approx(fixture.clock, paused_clock), "pausing the game pauses map activity without an independent timer")
	paused = false
	root.remove_child(fixture)
	var stopped_clock: float = fixture.clock
	await _frames(8)
	_check(is_equal_approx(fixture.clock, stopped_clock), "detached map stops its presentation clock")
	fixture.free()
	await _frames()

func _finish_relics() -> void:
	print("VILLAGE RELICS UI: %d checks, %d failures" % [checks, failures])
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await _frames()
	quit(1 if failures else 0)
