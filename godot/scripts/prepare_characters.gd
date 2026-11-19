extends SceneTree

func _init() -> void:
	var records: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../에셋 원본/generation_canonical.json"))
	for record in records:
		var image := Image.load_from_file("res://../에셋 원본/" + record.original)
		if image == null:
			push_error("Missing original " + record.original)
			quit(1)
			return
		image.resize(record.logical_width, record.logical_height, Image.INTERPOLATE_NEAREST)
		image.resize(record.width, record.height, Image.INTERPOLATE_NEAREST)
		var error := image.save_webp("res://" + record.destination, false)
		if error != OK: push_error("Failed to package " + record.destination); quit(1); return
	print("12 canonical pixel portraits packaged.")
	quit()
