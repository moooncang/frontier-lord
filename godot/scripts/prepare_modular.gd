extends SceneTree

func _init() -> void:
	var records: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../에셋 원본/generation_modular.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/assets.json"))
	for record in records:
		var source := Image.load_from_file("res://../에셋 원본/" + record.original)
		if source == null: push_error(record.original); quit(1); return
		if record.transparent and source.detect_alpha() == Image.ALPHA_NONE:
			push_error("Transparent asset required: " + record.id); quit(1); return
		# 생성 원본은 보존한다. 런타임 텍스처만 논리 도트 격자로 패키징한다.
		source.resize(int(record.logical_width), int(record.logical_height), Image.INTERPOLATE_NEAREST)
		var error := source.save_webp("res://" + record.destination, false)
		if error != OK: push_error(record.destination); quit(1); return
		manifest[record.key] = "res://" + record.destination
	var file := FileAccess.open("res://content/assets.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	print("Modular assets packaged: ", records.size())
	quit()
