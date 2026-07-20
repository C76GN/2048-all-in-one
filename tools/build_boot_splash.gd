## 将可编辑的 SVG 品牌标记构建为 Godot 原生启动页所需的 PNG。
extends SceneTree


const _BUILD_TARGETS: Array[Dictionary] = [
	{
		"source": "res://features/asset_library/resources/textures/branding/printworks_boot_mark.svg",
		"output": "res://features/asset_library/resources/textures/branding/printworks_boot_mark.png",
		"scale": 2.0,
	},
	{
		"source": "res://features/asset_library/resources/textures/branding/printworks_boot_splash.svg",
		"output": "res://features/asset_library/resources/textures/branding/printworks_boot_splash.png",
		"scale": 1.0,
	},
]


func _initialize() -> void:
	for target: Dictionary in _BUILD_TARGETS:
		var source_path: String = GFVariantData.get_option_string(target, "source")
		var output_path: String = GFVariantData.get_option_string(target, "output")
		var raster_scale: float = GFVariantData.get_option_float(target, "scale", 1.0)
		var build_error: Error = _build_target(source_path, output_path, raster_scale)
		if build_error != OK:
			quit(build_error)
			return
	quit(0)


func _build_target(source_path: String, output_path: String, raster_scale: float) -> Error:
	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if not is_instance_valid(source_file):
		push_error("[BuildBootSplash] 无法读取源文件：%s" % source_path)
		return ERR_FILE_CANT_OPEN

	var image: Image = Image.new()
	var load_error: Error = image.load_svg_from_string(source_file.get_as_text(), raster_scale)
	if load_error != OK:
		push_error("[BuildBootSplash] SVG 光栅化失败：%s" % error_string(load_error))
		return load_error

	var save_error: Error = image.save_png(output_path)
	if save_error != OK:
		push_error("[BuildBootSplash] PNG 写入失败：%s" % error_string(save_error))
		return save_error

	print("[BuildBootSplash] 已生成 %s（%dx%d）" % [output_path, image.get_width(), image.get_height()])
	return OK
