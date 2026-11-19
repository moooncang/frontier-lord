class_name RealmBoard
extends Control
## 건설 지구. 여섯 시설 이내의 같은 시점·지면을 공유하는 실제 거리 장면.
## 화면을 다시 그려도 유지되는 노드라서 주민의 걸음과 수치 팝업이 끊기지 않는다.

signal lot_selected(id: String)
signal shrine_selected

## Pure presentation overlay; it never owns simulation timers or random draws.
class PixelDetail:
	extends Control
	var paint: Callable
	func _draw() -> void:
		if paint.is_valid(): paint.call(self)

const COLS := 3
const ROWS := 2
const DISTRICTS := {
	"civic": {"name":"마을", "lots":["B01","B06","B11","B57","B59"]},
	"food": {"name":"농경지", "lots":["B13","B14","B16","B17","B19","B22"]},
	"industry": {"name":"작업장", "lots":["B25","B26","B27","B33","B21","B20"]},
	"defense": {"name":"성벽", "lots":["B63","B49","B52","B67","B71"]}}
# 안정적인 전체 시설 ID 목록. 배치는 지구 안에서만 정한다.
const LOTS := [["B01"],["B06"],["B11"],["B57"],["B59"],
	["B13"],["B14"],["B16"],["B17"],["B19"],["B22"],
	["B25"],["B26"],["B27"],["B33"],["B21"],["B20"],
	["B63"],["B49"],["B52"],["B67"],["B71"]]
## 정식 시설을 짓기 전에 그 자리를 지키는 임시 시설.
const TEMP := {"B63": ["T_ADMIN", "행정 천막"], "B22": ["T_GRANARY", "임시 곳간"], "B01": ["T_HOUSING", "임시 주거"]}
const INK := Color("172329")
const PLATE := Color("f4e6bc")
const GOLD := Color("e3bb6d")
const GOOD := Color("9fd48f")
const BAD := Color("f4a08a")
const FOLK := [Color("7b4a32"), Color("3f5a6b"), Color("6b5a2e"), Color("5b3a52"), Color("42603f")]
const FANTASY_LOTS := {
	"grove": ["FG01","FG02","FG03"], "ember": ["FE01","FE02","FE03"],
	"tide": ["FT01","FT02","FT03"], "clockwork": ["FC01","FC02","FC03"],
	"veil": ["FV01","FV02","FV03"], "astral": ["FA01","FA02","FA03"]}
const FANTASY_COLORS := {"grove":Color("b6efd0"), "ember":Color("ffc37f"), "tide":Color("a9e8f3"),
	"clockwork":Color("edd69a"), "veil":Color("c9b9ee"), "astral":Color("d4c5ff")}
const FANTASY_DISTRICTS := {"grove":"food", "ember":"industry", "tide":"food", "clockwork":"industry", "veil":"defense", "astral":"civic"}

var district := "civic"
var backdrop: Texture2D
var secondary_backdrop: Texture2D
var fantasy_selected: Array = []
var fantasy_stages: Dictionary = {}
var scene_paths: Array = []
var bank: AssetBank
var state: Dictionary = {}
var content: Dictionary = {}
var selected := ""
var interactive := true
## 평소에는 실제 영지만, 건설 계획 보기에서는 아직 없는 시설도 표시한다.
var show_plans := false
var season := 0
var raining := false
var clock := 0.0
var lots: Dictionary = {}
var kinds: Dictionary = {}
var shrine: Button
var sanctuary: Dictionary = {}
var activity: Dictionary = {}
var fantasy_operations: Dictionary = {}
var detail_tick := -1


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)


## 터의 상태: built 가동 / temp 임시 시설 / site 공사 중 / open 지을 수 있음 / locked 조건 미달
static func lot_kind(run: Dictionary, data: Dictionary, id: String) -> String:
	var count := int(run.get("facilities", {}).get(id, 0))
	if count > 0: return "built"
	if sites(run, id) > 0: return "site"
	if TEMP.has(id) and int(run.get("facilities", {}).get(TEMP[id][0], 0)) > 0: return "temp"
	return "open" if lock_reason(run, data, id) == "" else "locked"


static func sites(run: Dictionary, id: String) -> int:
	var total: int = run.get("orders", []).count(id)
	for project in run.get("projects", []):
		if project.id == id: total += 1
	return total


static func lock_reason(run: Dictionary, data: Dictionary, id: String) -> String:
	var facility: Dictionary = data.facilities[id]
	var planned := int(run.get("facilities", {}).get(id, 0)) + sites(run, id)
	if RealmRules.enabled(run): return RealmRules.build_error(run, data, id, planned)
	if facility.get("realm", false): return "새 통치에서 지을 수 있는 시설입니다"
	if int(facility.stage) > WeekSim.stage(run, data): return "촌락 승격 후 건설할 수 있습니다"
	return ""


func configure(asset_bank: AssetBank, run: Dictionary, data: Dictionary, chosen: String, can_interact: bool) -> void:
	bank = asset_bank
	state = run
	content = data
	_sync_fantasy_state()
	selected = chosen
	if chosen != "" and district_for(chosen) != "": district = district_for(chosen)
	interactive = can_interact
	var week := clampi(int(state.get("week", 1)), 1, 52)
	season = WeekSim.season_of(week)
	raining = RealmRules.enabled(state) and state.realm.weather in ["spring_rain", "summer_monsoon"]
	_update_backdrop()
	if lots.is_empty(): _create()
	_sync_fantasy_lots()
	activity.clear()
	fantasy_operations.clear()
	for id in lots: _refresh(str(id))
	_refresh_shrine()
	_layout.call_deferred()
	queue_redraw()


func _create() -> void:
	for lot in LOTS:
		var id := str(lot[0])
		_create_lot(id)
	_create_shrine()


func _create_lot(id: String) -> void:
	var button := Button.new()
	button.name = "lot_" + id
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.focus_mode = FOCUS_ALL
	button.pressed.connect(func(): lot_selected.emit(id))
	add_child(button)
	var art := TextureRect.new()
	art.name = "Art"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(art)
	var detail := PixelDetail.new()
	detail.name = "OperatingEffect"
	detail.mouse_filter = MOUSE_FILTER_IGNORE
	detail.clip_contents = true
	detail.paint = _draw_activity.bind(id)
	button.add_child(detail)
	var work := ProgressBar.new()
	work.name = "Work"
	work.max_value = 1.0
	work.show_percentage = false
	work.mouse_filter = MOUSE_FILTER_IGNORE
	work.add_theme_stylebox_override("background", GameTheme.panel(Color("10181c"), INK, 0, 2, 0))
	work.add_theme_stylebox_override("fill", GameTheme.panel(GOLD, GOLD, 0, 0, 0))
	button.add_child(work)
	var plate := Label.new()
	plate.name = "Plate"
	plate.z_index = 10
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_theme_font_override("font", PixelTheme.heading_font())
	plate.add_theme_font_size_override("font_size", 18)
	button.add_child(plate)
	var chip := Label.new()
	chip.name = "Chip"
	chip.z_index = 11
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", 16)
	button.add_child(chip)
	lots[id] = button

func _sync_fantasy_state() -> void:
	fantasy_selected.clear()
	fantasy_stages.clear()
	if FantasyFrontiers.enabled(state):
		var view := FantasyFrontiers.overview(state, content)
		fantasy_selected = view.get("selected", []).duplicate()
	for path in fantasy_selected:
		var completed := 0
		for id in FANTASY_LOTS.get(path, []):
			if int(state.get("facilities", {}).get(id, 0)) > 0: completed += 1
		fantasy_stages[path] = completed
	if district == "fantasy" and fantasy_selected.is_empty(): district = "civic"


func _sync_fantasy_lots() -> void:
	for path in fantasy_selected:
		for id in FANTASY_LOTS.get(path, []):
			if content.facilities.has(id) and not lots.has(id): _create_lot(id)
	# Reusing a board for another run must not leave another run's plots clickable.
	for id in lots.keys():
		var path := fantasy_path_for(str(id))
		if path != "" and path not in fantasy_selected:
			lots[id].queue_free()
			lots.erase(id)
			kinds.erase(id)


func district_lots() -> Array:
	if district != "fantasy": return DISTRICTS.get(district, {}).get("lots", [])
	var result: Array = []
	for path in fantasy_selected: result.append_array(FANTASY_LOTS.get(path, []))
	return result


static func fantasy_path_for(id: String) -> String:
	for path in FANTASY_LOTS:
		if id in FANTASY_LOTS[path]: return path
	return ""


func _create_shrine() -> void:
	shrine = Button.new()
	shrine.name = "RelicShrine"
	shrine.focus_mode = FOCUS_ALL
	shrine.pressed.connect(func():
		if interactive: shrine_selected.emit())
	add_child(shrine)
	var art := TextureRect.new()
	art.name = "Art"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = MOUSE_FILTER_IGNORE
	shrine.add_child(art)
	var detail := PixelDetail.new()
	detail.name = "ShrineLamps"
	detail.mouse_filter = MOUSE_FILTER_IGNORE
	detail.paint = _draw_shrine
	shrine.add_child(detail)
	var plate := Label.new()
	plate.name = "Plate"
	plate.z_index = 10
	plate.text = "성소"
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_theme_font_override("font", PixelTheme.heading_font())
	plate.add_theme_font_size_override("font_size", 18)
	plate.add_theme_color_override("font_color", INK)
	plate.add_theme_stylebox_override("normal", GameTheme.panel(PLATE, Color("574c36"), 0, 2, 4))
	shrine.add_child(plate)
	var ready := Label.new()
	ready.name = "ShrineOffer"
	ready.text = "성물 선택"
	ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready.mouse_filter = MOUSE_FILTER_IGNORE
	ready.add_theme_font_size_override("font_size", 15)
	ready.add_theme_color_override("font_color", GOLD)
	ready.add_theme_stylebox_override("normal", GameTheme.panel(INK, GOLD, 0, 1, 4))
	shrine.add_child(ready)


func _refresh_shrine() -> void:
	sanctuary = state.get("realm", {}).get("sanctuary", {})
	shrine.visible = district == "civic" and RealmRules.enabled(state) and sanctuary.get("enabled", false) == true
	shrine.disabled = not interactive
	shrine.mouse_default_cursor_shape = CURSOR_POINTING_HAND if interactive else CURSOR_ARROW
	shrine.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	shrine.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	shrine.add_theme_stylebox_override("hover", GameTheme.panel(Color(1, 0.9, 0.55, 0.09), GOLD, 0, 2, 0))
	shrine.add_theme_stylebox_override("pressed", GameTheme.panel(Color(1, 0.9, 0.55, 0.16), GOLD, 0, 2, 0))
	var art: TextureRect = shrine.get_node("Art")
	art.texture = bank.texture("building_relic_shrine") if shrine.visible else null
	art.visible = art.texture != null
	var equipped: Array = sanctuary.get("equipped", [])
	var offered: Array = sanctuary.get("offer", [])
	shrine.get_node("ShrineOffer").visible = not offered.is_empty()
	shrine.tooltip_text = "성소 · 장착 성물 %d / 3\n보유 성물 %d개 · 클릭하여 성물 확인%s" % [equipped.size(), sanctuary.get("owned", []).size(), "\n새 성물을 선택할 수 있습니다." if not offered.is_empty() else ""]
	shrine.get_node("ShrineLamps").queue_redraw()


func _refresh(id: String) -> void:
	var button: Button = lots[id]
	var facility: Dictionary = content.facilities[id]
	var kind := lot_kind(state, content, id)
	kinds[id] = kind
	var chosen := selected == id
	var solid: bool = kind in ["built", "temp", "site"]
	var show_building: bool = solid or show_plans or chosen
	button.visible = id in district_lots() and (kind != "locked" or show_plans or chosen)
	var count := int(state.get("facilities", {}).get(id, 0))
	var building := sites(state, id)
	if count > 0 and fantasy_path_for(id) != "":
		fantasy_operations[id] = FantasyFrontiers.building_operation(state, content, id)
	var art: TextureRect = button.get_node("Art")
	var sprite_key := "building_" + str(facility.get("sprite", ""))
	if kind == "temp": sprite_key = "building_" + str(TEMP[id][0]).to_lower()
	if kind == "site": sprite_key = "building_construction"
	var seasonal_art: bool = season == 3 and bank.paths.has(sprite_key + "_winter")
	if seasonal_art: sprite_key += "_winter"
	var texture := bank.texture(sprite_key)
	var placeholder := texture == null
	if placeholder: texture = bank.texture("building_" + str(facility.get("fallback", "admin")))
	art.texture = texture
	art.visible = show_building
	# 전용 그림이 아직 없는 시설은 대체 그림에 푸른 기를 입혀 구분한다.
	var tint := Color(0.78, 0.9, 1.08) if placeholder else Color.WHITE
	match kind:
		"built": art.modulate = tint
		"temp": art.modulate = Color(tint.r * 0.9, tint.g * 0.88, tint.b * 0.8)
		"site": art.modulate = tint
		"open": art.modulate = Color(tint.r, tint.g, tint.b, 0.38)
		_: art.modulate = Color(0.16, 0.18, 0.22, 0.42)
	# The same field asset reads as dormant frost in winter instead of ripe grain.
	if id in ["B13", "B14"] and solid and season == 3 and not seasonal_art:
		art.modulate *= Color(0.65, 0.75, 0.82)
	var workers := _operating_workers(id) if count > 0 and state.get("status", "") == "active" else 0
	activity[id] = workers
	var detail: PixelDetail = button.get_node("OperatingEffect")
	detail.visible = workers > 0 or (count > 0 and (id in ["B67", "B71"] or fantasy_operations.get(id, {}).get("status", "") == "passive"))
	detail.queue_redraw()
	var title := str(facility.name)
	if kind == "temp": title = str(TEMP[id][1])
	elif count > 1 or (id == "B13" and count > 0): title += " ×%d" % count
	var plate: Label = button.get_node("Plate")
	plate.text = title
	plate.visible = show_building
	plate.add_theme_color_override("font_color", INK if solid else Color("f3e7cd", 0.92 if kind == "open" else 0.5))
	plate.add_theme_stylebox_override("normal", GameTheme.panel(PLATE if solid else Color(0.07, 0.1, 0.12, 0.72 if kind == "open" else 0.5), Color("574c36") if solid else Color(1, 1, 1, 0.16), 0, 2, 4))
	var chip: Label = button.get_node("Chip")
	var note := ""
	var hue := Color("dfe8e2")
	if building > 0:
		note = "공사 중" if not state.get("projects", []).filter(func(p): return p.id == id).is_empty() else "착공 대기"
		hue = GOLD
	elif kind == "open":
		note = "＋ " + str(facility.name)
		hue = GOLD
	elif kind == "locked":
		note = "잠김"
		hue = Color("aab3b6")
	else:
		note = _status(id)
		if note.contains("쉬는") or note.contains("휴지") or note.contains("부족"): hue = Color("f0c060")
	chip.text = note
	chip.visible = note != ""
	chip.add_theme_color_override("font_color", hue)
	chip.add_theme_stylebox_override("normal", GameTheme.panel(Color(0.06, 0.09, 0.11, 0.86), Color(hue, 0.7), 0, 1, 4))
	var work: ProgressBar = button.get_node("Work")
	work.visible = building > 0
	if work.visible:
		work.value = 0.0
		for project in state.get("projects", []):
			if project.id == id:
				work.value = 1.0 - float(project.work_left) / maxf(1.0, float(project.work_total))
				break
	button.add_theme_stylebox_override("normal", GameTheme.panel(Color(1, 0.9, 0.55, 0.16), GOLD, 0, 3, 0) if chosen else StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", GameTheme.panel(Color(1, 1, 1, 0.1), Color("fff0bd"), 0, 3, 0))
	button.add_theme_stylebox_override("pressed", GameTheme.panel(Color(1, 0.9, 0.6, 0.2), GOLD, 0, 2, 0))
	button.add_theme_stylebox_override("focus", GameTheme.panel(Color.TRANSPARENT, GOOD, 0, 2, 0))
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.disabled = not interactive
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND if interactive else CURSOR_ARROW
	var tip := "%s\n%s" % [facility.name, facility.get("effect", "")]
	if kind == "locked": tip += "\n잠김 · " + lock_reason(state, content, id)
	elif kind == "open": tip += "\n클릭하여 비용과 공사 기간 확인"
	button.tooltip_text = tip
	if workers > 0: button.tooltip_text += "\n직전 주 실제 가동 · %d명" % workers
	if fantasy_operations.has(id):
		var operation: Dictionary = fantasy_operations[id]
		var missing: Array[String] = []
		var resource_names := {"food":"식량","wood":"목재","stone":"석재","tools":"도구","fuel":"장작","iron":"철"}
		for asset in operation.get("missing", []): missing.append(str(resource_names.get(asset, asset)))
		if not missing.is_empty(): button.tooltip_text += "\n직전 주 부족 재료 · " + " · ".join(missing)
	if count > 0 and id in ["B67", "B71"]:
		button.tooltip_text += "\n경계 깃발 · 치안 %d · 변경의 위협 %d" % [int(state.get("security", 0)), int(state.get("realm", {}).get("threat", 0))]


func _operating_workers(id: String) -> int:
	var report: Dictionary = state.get("labor_report", {})
	if fantasy_path_for(id) != "": return int(report.get("realm_by", {}).get(id, 0))
	match id:
		"B13": return int(report.get("farm", 0))
		"B25": return int(report.get("logging", 0)) + int(report.get("fuel", 0))
		"B27": return int(report.get("quarry", 0))
		"B16", "B33": return int(report.get("realm_by", {}).get(id, 0))
	return 0


## 지어진 시설 위에 붙는 한 줄 상태. 직전 주의 실제 배치를 읽는다.
func _status(id: String) -> String:
	if fantasy_path_for(id) != "":
		var operation: Dictionary = fantasy_operations.get(id, {})
		match str(operation.get("status", "")):
			"operating": return "재료 부족 · 일부 가동" if not operation.get("missing", []).is_empty() else "가동 %d/%d명" % [operation.workers, operation.capacity]
			"inputs": return "재료 부족"
			"labor": return "일손 부족"
			"passive": return "효과 적용"
		return "첫 가동 대기"
	var report: Dictionary = state.get("labor_report", {})
	var week := clampi(int(state.get("week", 1)), 1, 52)
	match id:
		"B13": return "파종 준비" if week < 3 else "파종 중" if week <= 6 else "자라는 중" if week <= 32 else "수확 중" if week <= 36 else "수확 끝"
		"B17": return "겨울 휴지" if season == 3 and WeekSim.bonus(state, "winter_gather", 0.0) <= 0 else ("%d명 채집" % report.gather if report.has("gather") else "")
		"B14": return "겨울 휴지" if season == 3 else ("%d명 경작" % report.garden if report.has("garden") else "")
		"B25": return "" if not report.has("logging") else ("쉬는 중" if int(report.logging) + int(report.get("fuel", 0)) == 0 else "%d명 작업" % (int(report.logging) + int(report.get("fuel", 0))))
		"B27": return "" if not report.has("quarry") else ("쉬는 중" if int(report.quarry) == 0 else "%d명 채석" % report.quarry)
		"B16", "B33":
			if not report.has("realm_by"): return ""
			return "가동 중" if int(report.realm_by.get(id, 0)) > 0 else ("재료 부족" if id == "B33" else "쉬는 중")
		"B22":
			var cap := WeekSim.capacity(state, content, "storage") * WeekSim.bonus(state, "storage")
			return "저장 %d%%" % int(round(WeekSim.total_food(state) / maxf(1.0, cap) * 100.0))
		"B01": return "%d / %d명" % [state.pop, int(WeekSim.capacity(state, content, "housing"))]
	if TEMP.has(id) and id == "B22":
		return "저장 %d%%" % int(round(WeekSim.total_food(state) / maxf(1.0, WeekSim.capacity(state, content, "storage") * WeekSim.bonus(state, "storage")) * 100.0))
	return ""


static func district_for(id: String) -> String:
	if fantasy_path_for(id) != "": return "fantasy"
	for key in DISTRICTS:
		if id in DISTRICTS[key].lots: return key
	return ""


func set_district(id: String) -> void:
	if (not DISTRICTS.has(id) and id != "fantasy") or district == id: return
	if id == "fantasy" and fantasy_selected.is_empty(): return
	district = id
	selected = ""
	if bank != null: _update_backdrop()
	if lots.is_empty() or state.is_empty(): return
	for lot in lots: _refresh(str(lot))
	_refresh_shrine()
	_layout()


func get_lot_rect(id: String) -> Rect2:
	if not lots.has(id): return Rect2()
	return lots[id].get_global_rect()


func _update_backdrop() -> void:
	secondary_backdrop = null
	scene_paths.clear()
	var key: String = "realm_district_" + (["autumn", "winter"][season-2] if season >= 2 else district)
	backdrop = bank.texture(key)
	if backdrop == null: backdrop = bank.texture("realm_district_" + district)
	if backdrop == null: backdrop = bank.texture("realm_district_civic")
	if backdrop == null: backdrop = bank.texture("terrain_" + ["spring", "summer", "autumn", "winter"][season])
	if district == "fantasy":
		for path in fantasy_selected:
			scene_paths.append(path)
		if not scene_paths.is_empty() and int(fantasy_stages.get(scene_paths[0], 0)) > 0:
			var first: Texture2D = bank.texture("realm_district_" + str(scene_paths[0]))
			if first != null: backdrop = first
		if scene_paths.size() > 1:
			var second_key := "realm_district_" + str(scene_paths[1]) if int(fantasy_stages.get(scene_paths[1], 0)) > 0 else key
			secondary_backdrop = bank.texture(second_key)
			if secondary_backdrop == null: secondary_backdrop = bank.texture("realm_district_civic")
	else:
		# Completing a specialty district transforms the matching ordinary district too.
		for path in fantasy_selected:
			if FANTASY_DISTRICTS.get(path, "") == district and int(fantasy_stages.get(path, 0)) >= 3:
				var transformed: Texture2D = bank.texture("realm_district_" + str(path))
				if transformed != null:
					backdrop = transformed
					scene_paths.append(path)
					break


func _cell() -> Vector2:
	return Vector2(size.x / COLS, size.y * 0.38)


func _slot(id: String) -> int:
	var key := district_for(id)
	if key == "fantasy":
		var index := 0
		for path in fantasy_selected:
			var found: int = FANTASY_LOTS[path].find(id)
			if found >= 0: return index + found
			index += 3
		return 0
	return DISTRICTS[key].lots.find(id) if key != "" else 0


func _ground(index: int) -> Vector2:
	return Vector2(size.x * [0.19,0.50,0.81][index % 3], size.y * (0.49 if index < 3 else 0.85)).round()


func _center(id: String) -> Vector2:
	return _ground(_slot(id))


func _place_sprite(button: Button, index: int, is_shrine: bool = false) -> void:
	var foot := _ground(index)
	var height := floorf(minf(size.y * 0.32, size.x * 0.24))
	var width := floorf(size.x * 0.28)
	button.position = (foot - Vector2(width * 0.5, height)).round()
	button.size = Vector2(width, height + 28)
	var art: TextureRect = button.get_node("Art")
	art.size = Vector2(height, height)
	# 독립 그림의 발 위치를 거리의 지면에 맞춘다. 투명 여백도 같은 기준을 쓴다.
	art.position = Vector2((width - art.size.x) * 0.5, height - art.size.y * 0.96).round()
	var detail: Control = button.get_node("ShrineLamps" if is_shrine else "OperatingEffect")
	detail.position = Vector2.ZERO
	detail.size = button.size
	var plate: Label = button.get_node("Plate")
	plate.size = Vector2.ZERO
	plate.size = plate.get_combined_minimum_size()
	plate.position = Vector2((width - plate.size.x) * 0.5, height - 1).round()
	if is_shrine:
		var ready: Label = button.get_node("ShrineOffer")
		ready.size = ready.get_combined_minimum_size()
		ready.position = Vector2((width - ready.size.x) * 0.5, 0).round()
	else:
		var chip: Label = button.get_node("Chip")
		chip.size = Vector2.ZERO
		chip.size = chip.get_combined_minimum_size()
		var id := button.name.trim_prefix("lot_")
		chip.position = Vector2((width - chip.size.x) * 0.5, 3 if art.visible else height - chip.size.y - 8).round()
		var work: ProgressBar = button.get_node("Work")
		work.size = Vector2(width * 0.62, 8).floor()
		work.position = Vector2((width - work.size.x) * 0.5, height - 12).round()
	detail.queue_redraw()


func _layout() -> void:
	if lots.is_empty() or size.x < 10: return
	for id in lots:
		_place_sprite(lots[id], _slot(str(id)))
	if is_instance_valid(shrine): _place_sprite(shrine,5,true)
	queue_redraw()


## Tiny, six-frame-per-second effects use the executed labor report, never the plan.
func _draw_activity(canvas: Control, id: String) -> void:
	if not lots.has(id): return
	var art: TextureRect = lots[id].get_node("Art")
	var rect := Rect2(art.position, art.size)
	var unit := 2.0
	var tick := int(floor(clock * 6.0))
	var center := rect.position + rect.size * Vector2(0.5, 0.68)
	var fantasy_path := fantasy_path_for(id)
	if fantasy_path != "":
		var color: Color = FANTASY_COLORS[fantasy_path]
		for index in 3:
			var phase := (tick + index * 4) % 14
			var at := rect.position + rect.size * Vector2(0.46 + index * 0.07, 0.44) + Vector2((index - 1) * 4, -phase * 1.4)
			canvas.draw_rect(Rect2(at.round(), Vector2(2, 3) if fantasy_path in ["ember", "veil"] else Vector2(3, 2)), Color(color, 0.85 - phase * 0.04))
		return
	match id:
		"B16":
			for index in 2:
				var at := center + Vector2(index * 12 - 8, 5 + (tick + index * 2) % 3 * 2)
				canvas.draw_rect(Rect2(at.round(), Vector2(8 + index * 4, 2)), Color("acd8df"))
		"B25", "B27", "B13":
			var color := Color("d9b27e") if id == "B25" else Color("c4c9c9") if id == "B27" else Color("c7b568")
			var swing := tick % 4
			var at := center + Vector2(rect.size.x * 0.22, 1)
			canvas.draw_rect(Rect2(at.round(), Vector2(2, 7)), Color("61482d"))
			canvas.draw_rect(Rect2((at + Vector2(-2, -swing)).round(), Vector2(6, 2)), color)
			if swing == 0:
				for index in 2: canvas.draw_rect(Rect2((at + Vector2(-6 + index * 11, 6 - index * 2)).round(), Vector2.ONE * unit), color)
		"B33":
			canvas.draw_rect(Rect2((center + Vector2(6, 0)).round(), Vector2(6, 3)), Color("eeb75f") if tick % 3 == 0 else Color("b57237"))
			for index in 2:
				var rise := (tick + index * 5) % 10
				var at := rect.position + rect.size * Vector2(0.62, 0.30) + Vector2(index * 3 - rise / 3.0, -rise * 1.5)
				canvas.draw_rect(Rect2(at.round(), Vector2.ONE * (2 + index)), Color("a9b1ad", 0.7 - rise * 0.04))
		"B67", "B71":
			var at := rect.position + rect.size * Vector2(0.82, 0.30)
			var threat := float(state.get("realm", {}).get("threat", 0))
			var hue := BAD if threat >= 25 and float(state.get("security", 0)) < 55 else GOOD if float(state.get("security", 0)) >= 55 else GOLD
			canvas.draw_rect(Rect2(at.round(), Vector2(2, 20)), Color("725837"))
			canvas.draw_rect(Rect2((at + Vector2(2, 1)).round(), Vector2(7, 5)), hue)
			canvas.draw_rect(Rect2((at + Vector2(7, 3 + tick % 2)).round(), Vector2(4, 4)), hue)


func _draw_shrine(canvas: Control) -> void:
	if not is_instance_valid(shrine) or not shrine.visible: return
	var art: TextureRect = shrine.get_node("Art")
	var center := Vector2(shrine.size.x * 0.5, minf(shrine.size.y - 30, art.size.y * 0.76)).round()
	if not art.visible:
		# Temporary code-native altar remains usable while the independent art imports.
		canvas.draw_rect(Rect2(center - Vector2(23, 10), Vector2(46, 14)), Color("59666a"))
		canvas.draw_rect(Rect2(center - Vector2(28, 1), Vector2(56, 6)), Color("8d9592"))
		canvas.draw_rect(Rect2(center - Vector2(8, 28), Vector2(16, 20)), Color("a6b3af"))
	var equipped: Array = sanctuary.get("equipped", [])
	for index in 3:
		var at := center + Vector2((index - 1) * 18, 4)
		canvas.draw_rect(Rect2(at - Vector2(3, 0), Vector2(6, 4)), Color("4b514d"))
		if index >= equipped.size(): continue
		var id := str(equipped[index])
		var hue := Color("a8d183") if id.begins_with("F") else Color("e5b972") if id.begins_with("C") else Color("9bcddd")
		var flicker := int(floor(clock * 6)) % 3
		canvas.draw_rect(Rect2(at - Vector2(2, 5 + flicker % 2), Vector2(4, 6)), hue)
		canvas.draw_rect(Rect2(at - Vector2(1, 2), Vector2(2, 3)), Color("fff0c4"))


## 승인·완공의 위치를 짧게 강조한다. 지도 상태나 게임 수치는 변경하지 않는다.
func flash_lot(id: String, good: bool = true) -> void:
	if not lots.has(id) or not is_inside_tree(): return
	var button: Button = lots[id]
	if not button.visible: return
	var previous := button.get_node_or_null("CompletionFlash")
	if previous != null:
		button.remove_child(previous)
		previous.queue_free()
	var flash := Panel.new()
	flash.name = "CompletionFlash"
	flash.mouse_filter = MOUSE_FILTER_IGNORE
	var tone := GOOD if good else BAD
	flash.add_theme_stylebox_override("panel", GameTheme.panel(Color(tone, 0.12), tone, 0, 2, 0))
	button.add_child(flash)
	flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	flash.modulate.a = 0.0
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.9, 0.14)
	tween.tween_property(flash, "modulate:a", 0.0, 0.86).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(flash.queue_free)


## 한 주가 지난 뒤 시설 위로 떠오르는 수치.
func pop(id: String, text: String, good: bool, delay: float = 0.0) -> void:
	if not lots.has(id) or not is_inside_tree() or not lots[id].visible: return
	var label := Label.new()
	label.text = text
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", PixelTheme.heading_font())
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", GOOD if good else BAD)
	label.add_theme_color_override("font_outline_color", Color("0c1418"))
	label.add_theme_constant_override("outline_size", 6)
	label.modulate.a = 0.0
	add_child(label)
	var from := _center(id) - Vector2(label.get_combined_minimum_size().x * 0.5, 34)
	label.position = from
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(label, "position:y", from.y - 34.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _process(delta: float) -> void:
	clock += delta
	queue_redraw()
	var next_tick := int(floor(clock * 6.0))
	if next_tick != detail_tick:
		detail_tick = next_tick
		for button in lots.values():
			var detail: Control = button.get_node("OperatingEffect")
			if detail.is_visible_in_tree(): detail.queue_redraw()
		if is_instance_valid(shrine) and shrine.visible: shrine.get_node("ShrineLamps").queue_redraw()


func _draw() -> void:
	if backdrop != null:
		var hue := Color.WHITE
		if season == 1: hue = Color(0.96,1.02,0.94)
		draw_texture_rect(backdrop, Rect2(Vector2.ZERO,size), false, hue)
		if secondary_backdrop != null:
			var split := 0.60
			var source_size := secondary_backdrop.get_size()
			draw_texture_rect_region(secondary_backdrop, Rect2(0, floorf(size.y * split), size.x, ceilf(size.y * (1.0-split))), Rect2(0, source_size.y * split, source_size.x, source_size.y * (1.0-split)))
			# A shallow stone road edge makes the boundary between two covenants legible.
			draw_rect(Rect2(0, floorf(size.y * split), size.x, 3), Color("6d6462", 0.5))
	else: draw_rect(Rect2(Vector2.ZERO,size),Color("50604a"))
	if lots.is_empty() or state.is_empty(): return
	# 빈터는 화면에 뜬 아이콘 대신 지면에 꽂힌 작은 말뚝으로 표현한다.
	for id in district_lots():
		if not lots.has(id): continue
		if not lots[id].visible or kinds[id] in ["built","temp","site"]: continue
		var at := _ground(_slot(id))
		var hue := Color("e1c793") if kinds[id] == "open" else Color("797c73")
		for dx in [-31,31]:
			draw_rect(Rect2(at + Vector2(dx,-10),Vector2(3,13)),Color("5b4532"))
			draw_rect(Rect2(at + Vector2(dx-2,-11),Vector2(7,3)),hue)
		draw_line(at+Vector2(-30,1),at+Vector2(33,1),Color(hue,0.45),2)
	var walkers := clampi(int(int(state.get("pop",80))/16.0),3,9)
	if season == 3: walkers = maxi(2,walkers-3)
	var unit := 2.0
	for index in walkers:
		var lane := size.y * (0.55 if index % 2 == 0 else 0.90) + (index % 3)*3
		var span := maxf(1,size.x-80)
		var phase := fmod(clock*(10+index%4*3)+index*173.0,span*2)
		var x := 40+(phase if phase<span else span*2-phase)
		var stride := int(clock*5+index)%2
		var at := Vector2(x,lane-unit*7).round()
		draw_rect(Rect2(at+Vector2(-1,unit*6),Vector2(7,2)),Color(0.05,0.08,0.08,0.35))
		draw_rect(Rect2(at+Vector2(0,unit*2),Vector2(5,6)),FOLK[index%FOLK.size()])
		draw_rect(Rect2(at+Vector2(1,unit),Vector2(4,3)),Color("d8b591"))
		draw_rect(Rect2(at,Vector2(6,2)),Color("594330"))
		draw_rect(Rect2(at+Vector2(stride*2,unit*5),Vector2(2,4)),Color("302d2c"))
		draw_rect(Rect2(at+Vector2(4-stride*2,unit*5),Vector2(2,4)),Color("302d2c"))
	if season == 3:
		for index in 38:
			var at := Vector2(fmod(index*113.7+clock*10,size.x),fmod(index*73.1+clock*(14+index%4*3),size.y))
			draw_rect(Rect2(at.snapped(Vector2(3,3)),Vector2(3,3)),Color(1,1,1,0.7))
	elif raining:
		for index in 32:
			var drop := Vector2(fmod(index*97.3+clock*60,size.x),fmod(index*57.9+clock*420,size.y))
			draw_line(drop,drop+Vector2(-3,9),Color(0.75,0.87,1,0.45),2)
	_draw_fantasy_landscape()


func _draw_fantasy_landscape() -> void:
	for row in scene_paths.size():
		var path := str(scene_paths[row])
		var stage := int(fantasy_stages.get(path, 0))
		var hue: Color = FANTASY_COLORS[path]
		var y_start := 0.03 if row == 0 else 0.64
		var y_span := 0.39 if row == 0 else 0.20
		# More completed landmarks produce more motes; unbuilt covenants only mark the boundary.
		for index in 4 + stage * 4:
			var x := fmod(index * 137.0 + clock * (3 + index % 3), maxf(1.0, size.x - 32)) + 16
			var y := size.y * (y_start + fmod(index * 0.071 + clock * 0.006, y_span))
			var fade := 0.28 + float((index + int(clock * 2)) % 4) * 0.14
			draw_rect(Rect2(Vector2(x,y).snapped(Vector2(2,2)), Vector2(2,2)), Color(hue,fade))
		if stage >= 2:
			var baseline := size.y * (0.50 if row == 0 else 0.86)
			for side in [0.025, 0.975]:
				var at := Vector2(size.x * side, baseline).round()
				draw_rect(Rect2(at - Vector2(3,14),Vector2(6,15)),Color("52616b"))
				draw_rect(Rect2(at - Vector2(2,17),Vector2(4,5)),hue)
