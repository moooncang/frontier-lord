class_name SpritePanelStyle
extends StyleBox
## 실제 도트 테두리와 불투명 읽기 면을 합성한다. 원본의 알파는 보존한다.
var fill := Color("f3e6c9")
var frame: StyleBoxTexture

static func make(texture: Texture2D, color: Color, inset: int, tinted: Color = Color.WHITE) -> SpritePanelStyle:
	var style := SpritePanelStyle.new()
	style.fill = color
	style.set_content_margin_all(inset)
	style.frame = StyleBoxTexture.new()
	style.frame.texture = texture
	style.frame.draw_center = false
	style.frame.modulate_color = tinted
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.frame.set_texture_margin(side,12)
	return style

func _draw(canvas_item: RID, rect: Rect2) -> void:
	RenderingServer.canvas_item_add_rect(canvas_item,rect.grow(-3),fill)
	if frame != null and frame.texture != null: frame.draw(canvas_item,rect)
