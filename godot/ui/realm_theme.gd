class_name RealmTheme
extends RefCounted
## 장면의 목재·철재·장부와 같은 팔레트를 쓰는 공통 픽셀 UI.

const PAPER := Color("ead9b4")
const DARK := Color("202b2b")
const WOOD := Color("4a382a")
const EDGE := Color("8b7350")
const TEXT := Color("f6ebd0")
const ACCENT := Color("854b36")

static func surface(fill: Color, inset: int = 16) -> StyleBoxTexture:
	var edge := Color("ab9469") if fill.get_luminance() > 0.45 else Color("72634d")
	return PixelTheme.frame(fill,edge,inset).duplicate() as StyleBoxTexture

static func create(body: Font) -> Theme:
	var result := TycoonTheme.create(body)
	for kind in ["Button","OptionButton","NavigationButton","QuietButton","PrimaryButton"]:
		if kind not in ["Button","OptionButton"]: result.set_type_variation(kind,"Button")
		var fill := ACCENT if kind == "PrimaryButton" else DARK.lightened(.06)
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var color := fill.lightened(.08 if kind == "PrimaryButton" else .12) if state == "hover" else fill.darkened(.13) if state in ["pressed","hover_pressed"] else fill
			if state == "disabled": color = Color("55534a")
			var style := surface(color,10)
			style.content_margin_top = 8
			style.content_margin_bottom = 8
			result.set_stylebox(state,kind,style)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
			result.set_color(key,kind,TEXT)
		result.set_color("font_disabled_color",kind,Color("eee5ce"))
		result.set_font_size("font_size",kind,19)
		result.set_font("font",kind,body)
		var focus := TycoonTheme._focus()
		focus.border_color = TEXT
		result.set_stylebox("focus",kind,focus)
	result.set_stylebox("panel","PanelContainer",surface(PAPER,16))
	result.set_stylebox("scroll","VScrollBar",TycoonTheme.panel(Color("ccba96"),Color.TRANSPARENT,4))
	result.set_stylebox("grabber","VScrollBar",surface(Color("8a7454"),3))
	result.set_stylebox("grabber_highlight","VScrollBar",surface(Color("a68a60"),3))
	return result
