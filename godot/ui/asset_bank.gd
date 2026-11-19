class_name AssetBank
extends RefCounted

var paths: Dictionary
var cache: Dictionary = {}


func _init(manifest: Dictionary) -> void:
	paths = manifest


func texture(key: String) -> Texture2D:
	if cache.has(key):
		return cache[key]
	var path: String = paths.get(key, "")
	# 목록에 아직 없는 새 그림은 약속된 경로에 파일을 넣기만 하면 쓰인다.
	if path == "" and key.begins_with("building_"): path = "res://assets/world/%s.webp" % key.trim_prefix("building_")
	if path == "" and key.begins_with("icon_"): path = "res://assets/icons/stat_%s.png" % key.trim_prefix("icon_")
	if path != "" and ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			cache[key] = resource
			return resource
	return null


func body_font() -> Font:
	var path: String = paths.get("font_body", "")
	if path != "" and ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Font:
			return resource
	# 시스템 글꼴은 브라우저에 없다. 어디서나 함께 싣는 도트 글꼴을 쓴다.
	return PixelTheme.font()
