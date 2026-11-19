class_name EstateView
extends Control
## 실제 전경이 연결되면 동일한 영역에 표시한다. 없으면 코드 기반 지도 전경.

var season := 0
var building_count := 6
var backdrop: Texture2D


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var sky_colors := [Color("658a85"), Color("638b8a"), Color("99876b"), Color("71858c")]
	var grass_colors := [Color("536f54"), Color("435f47"), Color("7b6d46"), Color("afbab5")]
	var w := size.x
	var h := size.y
	if backdrop != null:
		var texture_size := backdrop.get_size()
		var scale_factor := maxf(w / texture_size.x, h / texture_size.y)
		var source_size := size / scale_factor
		draw_texture_rect_region(backdrop, Rect2(Vector2.ZERO, size), Rect2((texture_size - source_size) * 0.5, source_size))
		return
	draw_rect(Rect2(Vector2.ZERO, size), sky_colors[season])
	draw_circle(Vector2(w * 0.78, h * 0.18), 25, Color("eadbb0"))
	var mountains := PackedVector2Array([Vector2(0,h*.5),Vector2(w*.16,h*.13),Vector2(w*.33,h*.5),Vector2(w*.53,h*.19),Vector2(w*.75,h*.51),Vector2(w*.87,h*.28),Vector2(w,h*.43),Vector2(w,h),Vector2(0,h)])
	draw_colored_polygon(mountains, Color("435d5b"))
	draw_colored_polygon(PackedVector2Array([Vector2(0,h*.57),Vector2(w*.28,h*.4),Vector2(w*.58,h*.55),Vector2(w*.8,h*.42),Vector2(w,h*.59),Vector2(w,h),Vector2(0,h)]), grass_colors[season])
	draw_colored_polygon(PackedVector2Array([Vector2(w*.84,h*.49),Vector2(w*.9,h*.5),Vector2(w*.72,h),Vector2(w*.48,h)]), Color("678f98"))
	draw_line(Vector2(w*.1,h), Vector2(w*.54,h*.53), Color("b19c72"), 22, true)
	for i in 10:
		var x := 20 + i * w * .054
		var y := h * (.48 + .035 * (i % 3))
		draw_line(Vector2(x,y),Vector2(x,y+37),Color("433f30"),4)
		draw_colored_polygon(PackedVector2Array([Vector2(x,y-20),Vector2(x-18,y+22),Vector2(x+18,y+22)]),Color("2d5245"))
	for i in mini(12, building_count):
		var x := w * .21 + (i % 4) * 54
		var y := h * .6 + (i / 4) * 39
		draw_rect(Rect2(x, y, 37, 29), Color("b6a17b"))
		draw_colored_polygon(PackedVector2Array([Vector2(x-5,y),Vector2(x+18,y-22),Vector2(x+42,y)]), Color("614b3b") if season != 3 else Color("d5d8cf"))
		draw_rect(Rect2(x+14,y+12,9,17),Color("3e463d"))
	draw_line(Vector2(w*.58,h*.58),Vector2(w*.58,h*.34),Color("c7b48a"),3)
	draw_colored_polygon(PackedVector2Array([Vector2(w*.58,h*.34),Vector2(w*.58+35,h*.36),Vector2(w*.58,h*.42)]),Color("933f3c"))
	draw_rect(Rect2(0,h-36,w,36),Color(0.04,.08,.08,.72))
	draw_string(ThemeDB.fallback_font, Vector2(18,h-13), "E R N    /    THE FRONTIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e5d5ae"))
