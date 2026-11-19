extends SceneTree
## 생성 원본은 보존하고 납품 규격에 맞는 크기·파일 형식으로 패키징한다.

func _init() -> void:
	var source_root := ProjectSettings.globalize_path("res://../에셋 원본/")
	var records: Array = JSON.parse_string(FileAccess.get_file_as_string(source_root.path_join("generation_pixel.json")))
	var replace_existing := "--replace" in OS.get_cmdline_user_args()
	var failed := false
	for entry in records:
		var target: String = "res://assets/" + entry.destination
		if FileAccess.file_exists(target) and not replace_existing:
			print("SKIP existing ", target)
			continue
		var bitmap := Image.load_from_file(source_root.path_join(entry.original))
		if bitmap == null or bitmap.is_empty():
			push_error("원본 읽기 실패: " + entry.original)
			failed = true
			continue
		# 새로 생성한 도트 원화를 논리 해상도로 정규화하고 정수 배율로 납품한다.
		# 보간·손실 압축으로 픽셀 경계가 번지지 않도록 한다.
		bitmap.resize(int(entry.logical_width), int(entry.logical_height), Image.INTERPOLATE_NEAREST)
		bitmap.resize(int(entry.width), int(entry.height), Image.INTERPOLATE_NEAREST)
		var error := bitmap.save_webp(target, false) if target.ends_with(".webp") else bitmap.save_png(target)
		if error != OK:
			failed = true
			push_error("납품 파일 저장 실패: " + target)
		else:
			print("READY ", target, " ", bitmap.get_size(), " alpha=", bitmap.detect_alpha())
	quit(1 if failed else 0)
