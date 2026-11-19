class_name TycoonTheme
extends RefCounted
## 집무실의 장부와 책갈피. 글자는 선명하게, 조작부는 단단한 픽셀 경계로 구분한다.

const PAPER := Color("f0e3c6")
const INK := Color("30271f")
const MUTED := Color("6d5d4b")
const ACCENT := Color("793c32")
const NAV := Color("33241e")
const NAV_TEXT := Color("f3e7cd")
const LINE := Color("b6a180")
const GOOD := Color("34583b")
const WARN := Color("80511f")
const BAD := Color("9a332b")

const INPUT := Color("fff1d8")
const HOVER := Color("f9eccc")
const PRESSED := Color("dfcba5")
const DISABLED := Color("d4c6ab")
const DISABLED_INK := Color("776852")
const EDGE := Color("6c4c36")
const WAX_EDGE := Color("40221d")

static func panel(fill: Color, border: Color = LINE, inset: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(0 if is_zero_approx(border.a) else 1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.set_content_margin_all(inset)
	return style

static func primary() -> StyleBoxFlat:
	return _command_box(ACCENT)

static func _button_box(fill: Color, border: Color = LINE) -> StyleBoxFlat:
	var style := panel(fill, border, 14)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if border.a > 0:
		style.border_width_right = 2
		style.border_width_bottom = 3
	return style

static func _command_box(fill: Color, pressed: bool = false) -> StyleBoxFlat:
	var style := _button_box(fill, WAX_EDGE)
	style.set_border_width_all(2)
	style.border_width_bottom = 2 if pressed else 5
	style.content_margin_top = 12 if pressed else 9
	style.content_margin_bottom = 9 if pressed else 12
	return style

static func _tab_box(fill: Color, selected: bool = false) -> StyleBoxFlat:
	var style := _button_box(fill, EDGE)
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 3
	style.border_width_bottom = 1 if selected else 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func _focus() -> StyleBoxFlat:
	var style := panel(Color.TRANSPARENT, ACCENT, 0)
	style.set_border_width_all(2)
	return style

static func _line(vertical: bool = false) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = LINE
	line.thickness = 1
	line.vertical = vertical
	return line

static func _text_states(theme: Theme, kind: String, normal: Color, disabled: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, kind, normal)
	theme.set_color("font_disabled_color", kind, disabled)
	theme.set_color("font_outline_color", kind, Color.TRANSPARENT)
	theme.set_constant("outline_size", kind, 0)

static func create(body: Font) -> Theme:
	var result := Theme.new()
	result.default_font = body
	result.default_font_size = 20
	result.set_font("font", "Label", body)
	result.set_font_size("font_size", "Label", 20)
	result.set_color("font_color", "Label", INK)
	result.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	result.set_color("font_outline_color", "Label", Color.TRANSPARENT)
	result.set_constant("outline_size", "Label", 0)
	result.set_constant("line_spacing", "Label", 4)
	result.set_font("normal_font", "RichTextLabel", body)
	result.set_font_size("normal_font_size", "RichTextLabel", 20)
	result.set_color("default_color", "RichTextLabel", INK)
	result.set_color("selection_color", "RichTextLabel", Color("e0c4a8"))
	result.set_constant("line_separation", "RichTextLabel", 5)
	result.set_stylebox("panel", "PanelContainer", panel(PAPER))

	for kind in ["Button", "OptionButton"]:
		result.set_font("font", kind, body)
		result.set_font_size("font_size", kind, 19)
		result.set_stylebox("normal", kind, _button_box(PAPER, EDGE))
		result.set_stylebox("hover", kind, _button_box(HOVER, EDGE))
		var pressed := _button_box(PRESSED, EDGE)
		pressed.border_width_bottom = 1
		pressed.content_margin_top = 12
		pressed.content_margin_bottom = 8
		result.set_stylebox("pressed", kind, pressed)
		result.set_stylebox("hover_pressed", kind, pressed)
		result.set_stylebox("disabled", kind, _button_box(DISABLED, LINE))
		result.set_stylebox("focus", kind, _focus())
		result.set_constant("h_separation", kind, 10)
		_text_states(result, kind, INK, DISABLED_INK)
	result.set_constant("modulate_arrow", "OptionButton", 1)
	result.set_constant("arrow_margin", "OptionButton", 10)

	# 주 행동은 봉랍색 받침, 보조 행동은 종이, 장부 이동은 책갈피로 구분한다.
	result.set_type_variation("PrimaryButton", "Button")
	result.set_stylebox("normal", "PrimaryButton", primary())
	result.set_stylebox("hover", "PrimaryButton", _command_box(Color("914b3c")))
	result.set_stylebox("pressed", "PrimaryButton", _command_box(Color("622d26"), true))
	result.set_stylebox("hover_pressed", "PrimaryButton", _command_box(Color("622d26"), true))
	result.set_stylebox("disabled", "PrimaryButton", _button_box(DISABLED, LINE))
	_text_states(result, "PrimaryButton", Color("fff3da"), DISABLED_INK)
	var primary_focus := _focus()
	primary_focus.border_color = Color("fff0cf")
	primary_focus.set_border_width_all(2)
	result.set_stylebox("focus", "PrimaryButton", primary_focus)

	result.set_type_variation("QuietButton", "Button")
	result.set_stylebox("normal", "QuietButton", _button_box(Color.TRANSPARENT, Color.TRANSPARENT))
	result.set_stylebox("hover", "QuietButton", _button_box(HOVER, LINE))
	result.set_stylebox("pressed", "QuietButton", _tab_box(PRESSED, true))
	result.set_stylebox("hover_pressed", "QuietButton", _tab_box(PRESSED, true))
	result.set_stylebox("disabled", "QuietButton", _button_box(Color.TRANSPARENT, Color.TRANSPARENT))
	result.set_stylebox("focus", "QuietButton", _focus())
	_text_states(result, "QuietButton", ACCENT, DISABLED_INK)

	result.set_type_variation("NavigationButton", "Button")
	result.set_stylebox("normal", "NavigationButton", _tab_box(Color("d7c19a")))
	result.set_stylebox("hover", "NavigationButton", _tab_box(HOVER))
	var nav_selected := _tab_box(INPUT, true)
	result.set_stylebox("pressed", "NavigationButton", nav_selected)
	result.set_stylebox("hover_pressed", "NavigationButton", nav_selected)
	result.set_stylebox("disabled", "NavigationButton", _tab_box(DISABLED))
	var nav_focus := _focus()
	nav_focus.border_color = ACCENT
	result.set_stylebox("focus", "NavigationButton", nav_focus)
	_text_states(result, "NavigationButton", INK, DISABLED_INK)

	for kind in ["LineEdit", "SpinBox"]:
		result.set_font("font", kind, body)
		result.set_font_size("font_size", kind, 20)
		result.set_color("font_color", kind, INK)
		result.set_color("font_uneditable_color", kind, MUTED)
		result.set_color("font_placeholder_color", kind, MUTED)
		result.set_color("caret_color", kind, INK)
		result.set_color("selection_color", kind, ACCENT)
		result.set_color("font_selected_color", kind, Color("fffdf6"))
		var input := _button_box(INPUT, EDGE)
		input.border_width_top = 2
		input.border_width_left = 2
		input.border_width_right = 1
		input.border_width_bottom = 1
		result.set_stylebox("normal", kind, input)
		result.set_stylebox("read_only", kind, _button_box(DISABLED, LINE))
		result.set_stylebox("focus", kind, _focus())
	# Godot's default numerical arrows are pale on a light paper background.
	result.set_constant("buttons_width", "SpinBox", 28)
	result.set_constant("field_and_buttons_separation", "SpinBox", 4)
	for direction in ["up", "down"]:
		result.set_color(direction + "_icon_modulate", "SpinBox", INK)
		result.set_color(direction + "_hover_icon_modulate", "SpinBox", ACCENT)
		result.set_color(direction + "_pressed_icon_modulate", "SpinBox", INK)
		result.set_color(direction + "_disabled_icon_modulate", "SpinBox", DISABLED_INK)
		result.set_stylebox(direction + "_background", "SpinBox", panel(INPUT, LINE, 0))
		result.set_stylebox(direction + "_background_hovered", "SpinBox", panel(HOVER, ACCENT, 0))
		result.set_stylebox(direction + "_background_pressed", "SpinBox", panel(PRESSED, ACCENT, 0))
		result.set_stylebox(direction + "_background_disabled", "SpinBox", panel(DISABLED, LINE, 0))

	for kind in ["CheckButton", "CheckBox"]:
		result.set_font("font", kind, body)
		result.set_font_size("font_size", kind, 19)
		result.set_stylebox("normal", kind, _button_box(Color.TRANSPARENT, Color.TRANSPARENT))
		result.set_stylebox("hover", kind, _button_box(HOVER, Color.TRANSPARENT))
		result.set_stylebox("pressed", kind, _button_box(Color.TRANSPARENT, Color.TRANSPARENT))
		result.set_stylebox("hover_pressed", kind, _button_box(HOVER, Color.TRANSPARENT))
		result.set_stylebox("disabled", kind, _button_box(Color.TRANSPARENT, Color.TRANSPARENT))
		result.set_stylebox("focus", kind, _focus())
		result.set_constant("h_separation", kind, 10)
		_text_states(result, kind, INK, DISABLED_INK)

	for kind in ["VScrollBar", "HScrollBar"]:
		# 최소 12px 트랙을 확보하여 얇은 장식선처럼 보이지 않게 한다.
		result.set_stylebox("scroll", kind, panel(Color("d4c09b"), Color.TRANSPARENT, 6))
		result.set_stylebox("scroll_focus", kind, panel(Color("d4c09b"), ACCENT, 6))
		result.set_stylebox("grabber", kind, panel(Color("967652"), EDGE, 6))
		result.set_stylebox("grabber_highlight", kind, panel(Color("795739"), EDGE, 6))
		result.set_stylebox("grabber_pressed", kind, panel(NAV, EDGE, 6))

	result.set_stylebox("separator", "HSeparator", _line())
	result.set_stylebox("separator", "VSeparator", _line(true))
	result.set_constant("separation", "HSeparator", 12)
	result.set_constant("separation", "VSeparator", 16)
	result.set_stylebox("background", "ProgressBar", panel(Color("d4c09b"), Color.TRANSPARENT, 0))
	result.set_stylebox("fill", "ProgressBar", panel(ACCENT, Color.TRANSPARENT, 0))
	result.set_font_size("font_size", "ProgressBar", 18)
	result.set_color("font_color", "ProgressBar", INK)
	result.set_color("font_outline_color", "ProgressBar", Color.TRANSPARENT)
	result.set_stylebox("panel", "PopupMenu", panel(INPUT, EDGE, 10))
	result.set_stylebox("hover", "PopupMenu", panel(HOVER, Color.TRANSPARENT, 8))
	result.set_stylebox("separator", "PopupMenu", _line())
	result.set_font("font", "PopupMenu", body)
	result.set_font_size("font_size", "PopupMenu", 19)
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_color("font_disabled_color", "PopupMenu", DISABLED_INK)
	result.set_stylebox("panel", "TooltipPanel", panel(NAV, EDGE, 12))
	result.set_color("font_color", "TooltipLabel", NAV_TEXT)
	result.set_font_size("font_size", "TooltipLabel", 18)
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 16)
	result.set_constant("h_separation", "GridContainer", 16)
	result.set_constant("v_separation", "GridContainer", 12)
	return result
