# addons/theme_importer/theme_importer.gd

## ThemeImporter: 一个用于从JSON文件生成主题资源的编辑器工具。
##
## 该脚本仅在Godot编辑器内运行。它会在顶部的“工具”菜单中添加一个
## 菜单项。点击后，它会读取 `json_config/themes` 目录下的所有
## .json 文件，并在 `resources/themes` 目录中创建或更新对应的
## .tres 资源文件。
## 这使得主题创建过程自动化，并保持了视觉样式的数据驱动性。
@tool
extends EditorPlugin

const SOURCE_DIR = "res://json_config/themes/"
const TARGET_DIR = "res://resources/themes/"

func _enter_tree():
	# 在编辑器顶部的 "工具" 菜单中添加一个新选项。
	add_tool_menu_item("Generate Themes from JSON", Callable(self, "_on_menu_item_pressed"))

func _exit_tree():
	# 当插件被禁用时，移除菜单选项。
	remove_tool_menu_item("Generate Themes from JSON")

## 当菜单按钮被点击时调用的主函数。
func _on_menu_item_pressed():
	print("开始从JSON生成主题资源...")
	
	if not DirAccess.dir_exists_absolute(SOURCE_DIR):
		push_error("源文件夹 %s 不存在!" % SOURCE_DIR)
		return
		
	if not DirAccess.dir_exists_absolute(TARGET_DIR):
		DirAccess.make_dir_absolute(TARGET_DIR)
		print("已创建目标文件夹: %s" % TARGET_DIR)
		
	var dir = DirAccess.open(SOURCE_DIR)
	if not dir:
		push_error("无法打开源文件夹: %s" % SOURCE_DIR)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var generated_count = 0
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_process_json_file(SOURCE_DIR + file_name)
			generated_count += 1
		file_name = dir.get_next()
		
	dir.list_dir_end()
	
	if generated_count > 0:
		print("主题生成完毕！共处理了 %d 个JSON文件。" % generated_count)
	else:
		push_warning("在 %s 中没有找到任何 .json 文件。" % SOURCE_DIR)

## 处理单个JSON文件。
func _process_json_file(file_path: String):
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("无法读取文件: %s" % file_path)
		return
	
	var content = file.get_as_text()
	file.close()
	
	var json_data = JSON.parse_string(content)
	if json_data == null:
		push_error("解析JSON文件失败: %s" % file_path)
		return
		
	var theme_type = json_data.get("type")
	var theme_name = json_data.get("name")
	
	if not theme_type or not theme_name:
		push_warning("JSON文件 %s 缺少 'type' 或 'name' 字段，已跳过。" % file_path)
		return

	match theme_type:
		"TileColorScheme":
			_create_tile_color_scheme(theme_name, json_data)
		"BoardTheme":
			_create_board_theme(theme_name, json_data)
		_:
			push_warning("在 %s 中发现未知的主题类型 '%s'，已跳过。" % [file_path, theme_type])
			
## 根据JSON数据创建一个 TileColorScheme 资源。
func _create_tile_color_scheme(p_name: String, data: Dictionary):
	var scheme = TileColorScheme.new()
	var styles_data = data.get("styles", [])
	
	for style_json in styles_data:
		var style = TileLevelStyle.new()
		style.background_color = Color(style_json.get("bg", "#FFFFFF"))
		style.font_color = Color(style_json.get("font", "#000000"))
		scheme.styles.append(style)
		
	_save_resource(scheme, p_name)

## 根据JSON数据创建一个 BoardTheme 资源。
func _create_board_theme(p_name: String, data: Dictionary):
	var theme = BoardTheme.new()
	theme.game_background_color = Color(data.get("game_background", "#000000"))
	theme.board_panel_color = Color(data.get("board_panel", "#808080"))
	theme.empty_cell_color = Color(data.get("empty_cell", "#C0C0C0"))
	
	_save_resource(theme, p_name)
	
## 将生成的资源保存到文件。
func _save_resource(resource: Resource, p_name: String):
	var target_path = TARGET_DIR + p_name + ".tres"
	var error = ResourceSaver.save(resource, target_path)
	if error != OK:
		push_error("保存资源失败: %s (错误码: %d)" % [target_path, error])
	else:
		print("已成功生成资源: %s" % target_path)
