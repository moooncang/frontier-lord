extends SceneTree
## 기존 실행 창의 미저장 진행과 충돌하지 않는 전체 게임 실행.
## 일반 main.tscn과 같은 규칙을 사용하며 저장 위치만 분리한다.

func _initialize() -> void:
	_open.call_deferred()

func _open() -> void:
	var screen: Control = load("res://ui/main.tscn").instantiate()
	screen.save_directory = "res://playtest/saves"
	root.add_child(screen)
	DisplayServer.window_set_title("변경의 신임 영주가 되었다 · 새 운영")
