class_name PixelTheme
extends RefCounted

static var regular: Font
static var bold: Font
static var frames: Dictionary = {}
static var heading: SystemFont

static func heading_font() -> Font:
	if heading == null:
		heading = SystemFont.new()
		heading.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
		heading.font_weight = 700
	return heading

static func font(strong: bool = false) -> Font:
	if regular == null:
		regular = load("res://assets/fonts/Galmuri11.ttf")
		bold = load("res://assets/fonts/Galmuri11-Bold.ttf")
		for face in [regular, bold]:
			if face is FontFile:
				face.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return bold if strong else regular

static func frame(fill: Color, edge: Color, inset: int = 16) -> StyleBoxTexture:
	var key := "%s/%s/%d" % [fill.to_html(), edge.to_html(), inset]
	if frames.has(key): return frames[key]
	# UI 본래 도형을 18px 격자에 그린 9분할 프레임. 모서리 2px 계단은 확대하지 않는다.
	var canvas := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	for y in 18:
		for x in 18:
			if (x < 2 or x > 15) and (y < 2 or y > 15): continue
			var color := fill
			if x < 2 or x > 15 or y < 2 or y > 15: color = edge.darkened(0.3)
			elif x == 3 or y == 3: color = edge
			elif x == 14 or y == 14: color = fill.darkened(0.25)
			canvas.set_pixel(x, y, color)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(canvas)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 6)
		style.set_content_margin(side, inset)
	frames[key] = style
	return style

static func create(body: Font) -> Theme:
	var result := GameTheme.create(body)
	result.default_font_size = 18
	result.set_stylebox("panel", "PanelContainer", frame(GameTheme.PANEL, GameTheme.BORDER))
	for kind in ["Button", "OptionButton"]:
		result.set_font("font", kind, body)
		result.set_font_size("font_size", kind, 18)
		result.set_stylebox("normal", kind, frame(GameTheme.RAISED, Color("74634a"), 12))
		result.set_stylebox("hover", kind, frame(Color("3b3527"), GameTheme.GOLD, 12))
		result.set_stylebox("pressed", kind, frame(Color("423923"), GameTheme.GOLD, 12))
		result.set_stylebox("disabled", kind, frame(Color("201e18"), Color("3f3a30"), 12))
		result.set_stylebox("focus", kind, GameTheme.panel(Color.TRANSPARENT, GameTheme.TEAL, 0, 2, 0))
	result.set_font("font", "OptionButton", body)
	result.set_color("font_disabled_color", "Button", Color("a39d90"))
	for kind in ["LineEdit", "SpinBox"]:
		result.set_stylebox("normal", kind, frame(GameTheme.BG, GameTheme.BORDER, 10))
		result.set_stylebox("focus", kind, frame(GameTheme.BG, GameTheme.GOLD, 10))
	result.set_stylebox("scroll", "VScrollBar", GameTheme.panel(GameTheme.BG, GameTheme.BG, 0, 0, 5))
	result.set_stylebox("grabber", "VScrollBar", GameTheme.panel(GameTheme.BORDER, GameTheme.BORDER, 0, 0, 5))
	result.set_stylebox("grabber_highlight", "VScrollBar", GameTheme.panel(GameTheme.GOLD, GameTheme.GOLD, 0, 0, 5))
	return result
