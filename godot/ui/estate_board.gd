class_name EstateBoard
extends Control
## 지형, 개별 건물 Sprite2D, 클릭 영역, 상태 표지판을 별도 노드로 합성한다.

signal site_selected(site: String)

const BUILDINGS := [
	["B01", "housing", "주거", "housing", Vector2(.12, .29)],
	["B63", "admin", "집무실", "council", Vector2(.38, .29)],
	["B22", "storage", "곳간", "storage", Vector2(.64, .29)],
	["B59", "chapel", "예배당", "B59", Vector2(.88, .29)],
	["B17", "gather", "채집터", "work", Vector2(.12, .64)],
	["B06", "well", "우물", "B06", Vector2(.38, .64)],
	["B25", "logging", "벌목소", "B25", Vector2(.64, .64)],
	["B27", "quarry", "채석장", "B27", Vector2(.88, .64)],
	["B13", "farm", "농지", "farms", Vector2(.12, .98)],
	["B14", "garden", "채소밭", "B14", Vector2(.38, .98)],
	["B49", "market", "교역소", "trade", Vector2(.64, .98)],
	["B19", "mill", "방앗간", "B19", Vector2(.88, .98)]
]
var backdrop: Texture2D
var season := 0
var fields := 4
var construction_count := 0
var clock_time := 0.0
var enabled := true
var sprites: Dictionary = {}
var markers: Array[Button] = []
var labels: Dictionary = {}
var state: Dictionary = {}
var bank: AssetBank
var compact := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_place_markers)

func configure(asset_bank: AssetBank, run_state: Dictionary, can_interact: bool) -> void:
	bank = asset_bank
	state = run_state
	enabled = can_interact
	if sprites.is_empty(): _create_buildings()
	for i in BUILDINGS.size():
		var item: Array = BUILDINGS[i]
		var count := int(state.get("facilities", {}).get(item[0], 0))
		var base: bool = item[0] in ["B01", "B22", "B63", "B49"]
		var queued := _queued(item[0])
		var visible_building: bool = count > 0 or base or queued > 0 or state.is_empty()
		var sprite: Sprite2D = sprites[item[0]]
		sprite.visible = visible_building
		sprite.modulate = Color(1, 1, 1, .42 if count == 0 and queued > 0 and not base else 1.0)
		markers[i].visible = visible_building and enabled
		var label: Label = labels[item[0]]
		var label_text: String = item[2]
		if item[0] == "B13": label_text += " ×%d" % count
		elif count > 1: label_text += " ×%d" % count
		if queued > 0: label_text += " · 공사"
		if count == 0 and item[0] == "B22": label_text = "임시 곳간" + (" · 공사" if queued > 0 else "")
		label.text = label_text
		markers[i].tooltip_text = "%s · 보유 %d · 예약/공사 %d\n클릭하여 관리" % [item[2], count, queued]
	_place_markers.call_deferred()

func _queued(id: String) -> int:
	var count := 0
	for order in state.get("orders", []):
		if order == id: count += 1
	for project in state.get("projects", []):
		if project.id == id: count += 1
	return count

func _create_buildings() -> void:
	for item in BUILDINGS:
		var sprite := Sprite2D.new()
		sprite.name = "Building_" + item[0]
		sprite.texture = bank.texture("building_" + item[1])
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		sprites[item[0]] = sprite
		var button := Button.new()
		button.name = "site_" + item[3]
		button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", GameTheme.panel(Color(1, .9, .6, .1), GameTheme.GOLD, 0, 3, 0))
		button.add_theme_stylebox_override("hover", GameTheme.panel(Color(1, 1, 1, .07), Color("fff0bd"), 0, 3, 0))
		button.pressed.connect(func(): site_selected.emit(item[3]))
		add_child(button)
		markers.append(button)
		var plate := PanelContainer.new()
		plate.name = "Nameplate"
		plate.mouse_filter = MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", PixelTheme.frame(Color("f4e6bc"), Color("574c36"), 7))
		button.add_child(plate)
		var label := Label.new()
		label.mouse_filter = MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", PixelTheme.heading_font())
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color("172329"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plate.add_child(label)
		labels[item[0]] = label

func _place_markers() -> void:
	if sprites.is_empty(): return
	var area := Rect2(316, 132, maxf(780, size.x - 450), maxf(410, size.y - 310))
	if compact: area = Rect2(20, 12, size.x - 40, size.y - 58)
	var extent := floorf(minf(180, area.size.y * .26))
	for i in BUILDINGS.size():
		var item: Array = BUILDINGS[i]
		var center: Vector2 = area.position + item[4] * area.size
		var sprite: Sprite2D = sprites[item[0]]
		sprite.position = (center - Vector2(0, extent * .5)).round()
		var source_extent := maxf(sprite.texture.get_width(),sprite.texture.get_height()) if sprite.texture != null else 128.0
		sprite.scale = Vector2.ONE * extent / maxf(1.0,source_extent)
		var button := markers[i]
		var plate := button.get_node("Nameplate") as PanelContainer
		plate.size = plate.get_combined_minimum_size().ceil()
		button.size = Vector2(maxf(extent, plate.size.x), extent + plate.size.y - 10)
		button.position = (center - Vector2(button.size.x * .5, extent)).round()
		plate.position = Vector2((button.size.x - plate.size.x) * .5, extent - 10).round()
	queue_redraw()

func _process(delta: float) -> void:
	clock_time += delta
	queue_redraw()

func _draw() -> void:
	if backdrop != null: draw_texture_rect(backdrop, Rect2(Vector2.ZERO, size), false)
	if season == 3:
		for i in 36:
			var at := Vector2(fmod(i * 113.7 + clock_time * 10, size.x), fmod(i * 73.1 + clock_time * (12 + i % 4), size.y))
			draw_rect(Rect2(at.snapped(Vector2(3, 3)), Vector2(3, 3)), Color(1, 1, 1, .65))

