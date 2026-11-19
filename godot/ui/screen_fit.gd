class_name ScreenFit
extends Node
## 휴대폰·태블릿과 화소가 촘촘한 화면 대응. 화면 배치 규칙은 건드리지 않고,
## 창 전체 배율과 손가락 스크롤만 맡는다.

const BASE := Vector2(1280, 720)
const SLOP := 14.0

var area: ScrollContainer
var origin := Vector2.ZERO
var from := Vector2.ZERO
var dragging := false


## 설계 최소 크기(1280x720)가 항상 화면에 들어가는 배율. 촘촘한 화면에서는 그만큼 키운다.
static func factor(size: Vector2, density: float) -> float:
	return clampf(minf(density, minf(size.x / BASE.x, size.y / BASE.y)), 0.25, 4.0)


func _ready() -> void:
	# 데스크톱은 창 최소 크기가 지켜지므로 배율을 건드리지 않는다.
	if not (OS.has_feature("web") or OS.has_feature("mobile")): return
	get_window().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var window := get_window()
	var wanted := factor(Vector2(window.size), DisplayServer.screen_get_scale())
	if not is_equal_approx(window.content_scale_factor, wanted): window.content_scale_factor = wanted


func _scroll_at(point: Vector2) -> ScrollContainer:
	var modal: Variant = get_parent().get("current_modal")
	var found: ScrollContainer
	for node in get_parent().find_children("*", "ScrollContainer", true, false):
		if not node.is_visible_in_tree() or not node.get_global_rect().has_point(point): continue
		if is_instance_valid(modal) and not modal.is_ancestor_of(node): continue
		found = node
	return found


func _input(event: InputEvent) -> void:
	# 버튼과 판은 손가락 끌기를 가로채서 목록이 밀리지 않는다. 여기서 직접 민다.
	if event is InputEventScreenTouch and event.index == 0:
		area = _scroll_at(event.position) if event.pressed else null
		origin = event.position
		dragging = false
		if area != null: from = Vector2(area.scroll_horizontal, area.scroll_vertical)
	elif event is InputEventScreenDrag and event.index == 0 and is_instance_valid(area):
		var moved: Vector2 = event.position - origin
		if not dragging and moved.length() < SLOP: return
		if not dragging:
			dragging = true
			_drop_press()
		area.scroll_horizontal = int(from.x - moved.x)
		area.scroll_vertical = int(from.y - moved.y)


## 끌기가 시작되면 눌려 있던 버튼을 화면 밖으로 끌고 나가 뗀 것으로 처리해 눌림을 취소한다.
## 버튼은 뗀 자리가 아니라 마지막으로 움직인 자리로 안팎을 가리므로 움직임부터 보낸다.
func _drop_press() -> void:
	var away := Vector2(-10000, -10000)
	var move := InputEventMouseMotion.new()
	move.position = away
	move.global_position = away
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = away
	up.global_position = away
	get_viewport().push_input(up)
