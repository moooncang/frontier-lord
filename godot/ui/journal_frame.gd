class_name JournalFrame
extends Control
## 모든 경계는 정수 픽셀로 그린다. 텍스트는 별도 UI 노드로 유지한다.
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := floorf(size.x)
	var h := floorf(size.y)
	draw_rect(Rect2(8, 12, w - 8, h - 8), Color("17100edb"))
	draw_rect(Rect2(0, 5, w - 8, h - 12), Color("241512"))
	draw_rect(Rect2(5, 0, w - 18, h - 2), Color("241512"))
	draw_rect(Rect2(5, 5, w - 18, h - 14), Color("6c3d29"))
	draw_rect(Rect2(9, 8, w - 26, 4), Color("a87345"))
	draw_rect(Rect2(12, 15, w - 32, h - 30), Color("b69b6b"))
	draw_rect(Rect2(16, 15, w - 40, h - 36), TycoonTheme.PAPER)
	for y in [h - 27, h - 23]:
		draw_line(Vector2(19, y), Vector2(w - 25, y), Color("8e7553"), 1)
	# 작은 가죽 모서리 보호대. 읽기 영역에는 무늬를 넣지 않는다.
	for p in [Vector2(5, 5), Vector2(w - 28, 5), Vector2(5, h - 30), Vector2(w - 28, h - 30)]:
		draw_rect(Rect2(p, Vector2(15, 15)), Color("7f552f"))
		draw_rect(Rect2(p + Vector2(4, 4), Vector2(4, 4)), Color("c9a164"))
