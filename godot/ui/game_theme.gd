class_name GameTheme
extends RefCounted
## 색과 스타일은 여기에서만 정한다. 06번: 종이·목재의 절제된 질감, 본문 대비 4.5:1 이상,
## 숫자 증감을 색 하나에만 맡기지 않는다(색 + 문장 + 막대).

const BG := Color("15120e")
const PANEL := Color("231e18")
const RAISED := Color("2d261e")
const BORDER := Color("4a3d2c")
const TEXT := Color("f3ead9")
const MUTED := Color("bfb199")
const GOLD := Color("e3bb6d")
const TEAL := Color("8fc6b8")
const RED := Color("ef8a78")
const GOOD := Color("9fd48f")
const WARN := Color("f0c060")
const BAD := Color("ef8a78")
const INFO := Color("8fc6b8")
const SEASON := [Color("9fd48f"), Color("e3bb6d"), Color("e89a5a"), Color("9cc3e6")]


static func level_color(level: String) -> Color:
	match level:
		"good":
			return GOOD
		"warn":
			return WARN
		"bad":
			return BAD
		"info":
			return INFO
	return GOLD


static func panel(color: Color = PANEL, border: Color = BORDER, radius: int = 8, border_width: int = 1, margin: int = -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(mini(radius, 2))
	style.anti_aliasing = false
	var side: int = 18 if margin < 0 else margin
	var vertical: int = 14 if margin < 0 else margin
	style.content_margin_left = side
	style.content_margin_right = side
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


static func create(font: Font) -> Theme:
	var result := Theme.new()
	result.default_font = font
	result.default_font_size = 17
	result.set_color("font_color", "Label", TEXT)
	result.set_color("default_color", "RichTextLabel", TEXT)
	for kind in ["Button", "OptionButton"]:
		result.set_stylebox("normal", kind, panel(RAISED, BORDER))
		result.set_stylebox("hover", kind, panel(Color("3a3127"), GOLD))
		result.set_stylebox("pressed", kind, panel(Color("4a3d2c"), GOLD, 8, 2))
		result.set_stylebox("disabled", kind, panel(Color("1c1813"), Color("2e2821")))
		result.set_stylebox("focus", kind, panel(Color(0, 0, 0, 0), GOLD, 8, 2))
		result.set_color("font_color", kind, TEXT)
		result.set_color("font_hover_color", kind, TEXT)
		result.set_color("font_pressed_color", kind, GOLD)
		result.set_color("font_disabled_color", kind, Color("7a6f5e"))
	result.set_stylebox("panel", "PanelContainer", panel())
	for kind in ["LineEdit", "SpinBox"]:
		result.set_stylebox("normal", kind, panel(BG, BORDER))
		result.set_stylebox("focus", kind, panel(BG, GOLD, 8, 2))
		result.set_color("font_color", kind, TEXT)
	result.set_stylebox("panel", "PopupMenu", panel(RAISED, BORDER))
	result.set_color("font_color", "PopupMenu", TEXT)
	result.set_color("font_hover_color", "PopupMenu", GOLD)
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 12)
	result.set_constant("h_separation", "GridContainer", 12)
	result.set_constant("v_separation", "GridContainer", 12)
	return result
