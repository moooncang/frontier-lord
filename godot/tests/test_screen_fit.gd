extends "res://tests/test_realm_playflow.gd"
## 휴대폰 대응: 화면 배율 계산과 손가락으로 목록 밀기.

var pressed_count := 0

func _touch(point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = down
	Input.parse_input_event(event)
	await _frames(2)

func _drag(from: Vector2, to: Vector2) -> void:
	for step in 6:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = from.lerp(to, (step + 1) / 6.0)
		event.relative = (to - from) / 6.0
		Input.parse_input_event(event)
		await _frames(1)

## 내용이 넘치는 목록과 그 안에서 화면에 보이는 버튼을 찾는다.
func _long_list() -> Array:
	for scroll in screen.find_children("*", "ScrollContainer", true, false):
		if not scroll.is_visible_in_tree() or scroll.get_v_scroll_bar().max_value < scroll.size.y + 160: continue
		for button in scroll.find_children("*", "Button", true, false):
			var rect: Rect2 = button.get_global_rect()
			if button.is_visible_in_tree() and not button.disabled and scroll.get_global_rect().encloses(rect) and rect.size.y >= 24: return [scroll, button]
	return []

func _run() -> void:
	_check(is_equal_approx(ScreenFit.factor(Vector2(1440, 900), 1.0), 1.0), "a desktop window keeps its own size")
	_check(is_equal_approx(ScreenFit.factor(Vector2(2532, 1170), 3.0), 1.625), "a phone held sideways shows the whole 720-line layout")
	_check(is_equal_approx(ScreenFit.factor(Vector2(1920, 1080), 1.25), 1.25), "a dense laptop screen is enlarged by its own density")
	_check(ScreenFit.factor(Vector2(1000, 600), 1.0) < 0.8, "a window below the minimum shrinks instead of cutting the layout")
	root.size = Vector2i(1280, 720)
	await _frames(10)
	await _fresh("screen_fit")
	_check(screen.find_children("*", "ScreenFit", true, false).size() == 1 or screen.get_children().any(func(node): return node is ScreenFit), "the production screen carries the touch support node")
	var found: Array = []
	for opener in ["OpenArchive", "OpenCodex"]:
		await _click(opener)
		found = _long_list()
		if not found.is_empty(): break
		screen._go("menu")
		await _frames()
	if not _check(not found.is_empty(), "a long list with a button exists to drag"):
		await _finish()
		return
	var scroll: ScrollContainer = found[0]
	var button: Button = found[1]
	button.pressed.connect(func(): pressed_count += 1)
	var page: String = screen.page
	var start: Vector2 = button.get_global_rect().get_center()
	await _touch(start, true)
	await _drag(start, start - Vector2(0, 120))
	await _touch(start - Vector2(0, 120), false)
	_check(scroll.scroll_vertical >= 100, "dragging a finger over a button moves the list (%d)" % scroll.scroll_vertical)
	_check(pressed_count == 0 and screen.page == page, "a drag is not taken for a tap")
	if is_instance_valid(button) and scroll.get_global_rect().encloses(button.get_global_rect()):
		var spot: Vector2 = button.get_global_rect().get_center()
		await _touch(spot, true)
		await _touch(spot, false)
		_check(pressed_count == 1, "a plain tap still presses the button")
	await _finish()
