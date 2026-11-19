extends SceneTree
func _init() -> void:
	var image := Image.load_from_file("res://../에셋 원본/study_pixel.png")
	image.resize(640, 360, Image.INTERPOLATE_NEAREST)
	image.save_webp("res://assets/interiors/study.webp", false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/assets.json"))
	manifest.study = "res://assets/interiors/study.webp"
	FileAccess.open("res://content/assets.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "  ") + "\n")
	quit()
