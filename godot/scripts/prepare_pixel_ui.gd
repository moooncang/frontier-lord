extends SceneTree
func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/interface")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/assets.json"))
	for key in ["ui_frame_paper","ui_frame_slate","ui_button_wax"]:
		var image := Image.load_from_file("res://../에셋 원본/"+key+".png")
		image.resize(192 if key == "ui_button_wax" else 128,64 if key == "ui_button_wax" else 96,Image.INTERPOLATE_NEAREST)
		var path: String = "res://assets/interface/"+key+".webp"
		image.save_webp(path,false)
		manifest[key] = path
	FileAccess.open("res://content/assets.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  ")+"\n")
	quit()
