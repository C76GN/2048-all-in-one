# addons/theme_importer/theme_importer.gd
@tool

## ThemeImporter: 一个用于从JSON文件生成主题资源的编辑器工具。
##
## 该脚本仅在Godot编辑器内运行。它会在顶部的“工具”菜单中添加一个
## 菜单项。点击后，它会读取 `json_config/themes` 目录下的所有
## .json 文件，并在 `resources/themes` 目录中创建或更新对应的
## .tres 资源文件。
## 这使得主题创建过程自动化，并保持了视觉样式的数据驱动性。
extends EditorPlugin


# --- 常量 ---

## 包含主题配置JSON文件的源目录。
const SOURCE_DIR: String = "res://json_config/themes/"

## 生成的.tres主题资源的目标目录。
const TARGET_DIR: String = "res://resources/themes/"


# --- Godot 生命周期方法 ---

func _enter_tree() -> void:
	add_tool_menu_item("Generate Themes from JSON", Callable(self, "_on_menu_item_pressed"))


func _exit_tree() -> void:
	remove_tool_menu_item("Generate Themes from JSON")


# --- 私有/辅助方法 ---

## 处理单个JSON文件，解析其内容并分发给相应的创建函数。
## @param file_path: 要处理的JSON文件的完整路径。
func _process_json_file(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		push_error("无法读取文件: %s" % file_path)
		return

	var content: String = file.get_as_text()
	var json_data: Variant = JSON.parse_string(content)

	if json_data == null:
		push_error("解析JSON文件失败: %s" % file_path)
		return

	var theme_type: String = json_data.get("type")
	var theme_name: String = json_data.get("name")

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
## @param p_name: 资源名称。
## @param data: 从JSON文件解析出的字典数据。
func _create_tile_color_scheme(p_name: String, data: Dictionary) -> void:
	var scheme := TileColorScheme.new()
	var styles_data: Array = data.get("styles", [])

	for style_json in styles_data:
		var style := TileLevelStyle.new()
		style.background_color = Color(style_json.get("bg", "#FFFFFF"))
		style.font_color = Color(style_json.get("font", "#000000"))
		scheme.styles.append(style)

	_save_resource(scheme, "tile_schemes/" + p_name)


## 根据JSON数据创建一个 BoardTheme 资源。
## @param p_name: 资源名称。
## @param data: 从JSON文件解析出的字典数据。
func _create_board_theme(p_name: String, data: Dictionary) -> void:
	var theme := BoardTheme.new()
	theme.game_background_color = Color(data.get("game_background", "#000000"))
	theme.board_panel_color = Color(data.get("board_panel", "#808080"))
	theme.empty_cell_color = Color(data.get("empty_cell", "#C0C0C0"))

	_save_resource(theme, "board/" + p_name)


## 将生成的资源保存到目标目录中的文件。
## @param resource: 要保存的资源对象。
## @param p_name: 资源的文件名（不含扩展名）。
func _save_resource(resource: Resource, p_name: String) -> void:
	var target_path: String = TARGET_DIR.path_join(p_name + ".tres")
	var base_dir: String = target_path.get_base_dir()

	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)

	var error: Error = ResourceSaver.save(resource, target_path)

	if error != OK:
		push_error("保存资源失败: %s (错误码: %d)" % [target_path, error])
	else:
		print("已成功生成资源: %s" % target_path)


# --- 信号处理函数 ---

## 当菜单按钮被点击时调用的主函数。
func _on_menu_item_pressed() -> void:
	print("开始从JSON生成主题资源...")

	if not DirAccess.dir_exists_absolute(SOURCE_DIR):
		push_error("源文件夹 %s 不存在!" % SOURCE_DIR)
		return

	var dir := DirAccess.open(SOURCE_DIR)

	if not dir:
		push_error("无法打开源文件夹: %s" % SOURCE_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	var generated_count: int = 0

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_process_json_file(SOURCE_DIR.path_join(file_name))
			generated_count += 1
		file_name = dir.get_next()

	if generated_count > 0:
		print("主题生成完毕！共处理了 %d 个JSON文件。" % generated_count)
	else:
		push_warning("在 %s 中没有找到任何 .json 文件。" % SOURCE_DIR)
