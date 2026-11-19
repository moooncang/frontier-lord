extends SceneTree

func _init() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/assets.json"))
	for key in ["title_frontier","lord_settler","lord_steward","lord_grower"]:
		var image := Image.load_from_file("res://../에셋 원본/" + key + ".png")
		image.resize(640 if key == "title_frontier" else 96,360 if key == "title_frontier" else 128,Image.INTERPOLATE_NEAREST)
		var path: String = "res://assets/" + ("world/" if key == "title_frontier" else "portraits/") + key + ".webp"
		image.save_webp(path,false)
		manifest[key] = path
	FileAccess.open("res://content/assets.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  ")+"\n")
	quit()
