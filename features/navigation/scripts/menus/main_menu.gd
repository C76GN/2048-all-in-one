## MainMenu: 主菜单界面的 UI 控制器。
##
## 负责处理主菜单中的所有用户交互，
## 并通过 SceneRouterSystem 执行场景切换或退出游戏。
class_name MainMenu
extends GameUiController


# --- 导出变量 ---

## 模式选择场景路径。
@export_file("*.tscn") var mode_selection_scene_path: String = ""

## 回放列表场景路径。
@export_file("*.tscn") var replay_list_scene_path: String = ""

## 书签列表场景路径。
@export_file("*.tscn") var bookmark_list_scene_path: String = ""

## 设置场景路径。
@export_file("*.tscn") var settings_scene_path: String = ""


# --- @onready 变量 (节点引用) ---

@onready var _start_game_button: Button = %StartGameButton
@onready var _load_bookmark_button: Button = %LoadBookmarkButton
@onready var _replays_button: Button = %ReplaysButton
@onready var _tile_catalog_button: Button = %TileCatalogButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _connect_result_36: int = _start_game_button.pressed.connect(_on_start_game_button_pressed)
	var _connect_result_37: int = _load_bookmark_button.pressed.connect(_on_load_bookmark_button_pressed)
	var _connect_result_38: int = _replays_button.pressed.connect(_on_replays_button_pressed)
	var _catalog_connection: int = _tile_catalog_button.pressed.connect(_on_tile_catalog_button_pressed)
	var _connect_result_39: int = _settings_button.pressed.connect(_on_settings_button_pressed)
	var _connect_result_40: int = _quit_button.pressed.connect(_on_quit_button_pressed)

	_start_game_button.grab_focus()
	_update_ui_text()


# --- 私有/辅助方法 ---

func _goto_scene(scene_path: String, property_name: String) -> void:
	if scene_path.is_empty():
		push_error("[MainMenu] 场景路径 %s 未设置。" % property_name)
		return

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.goto_scene(scene_path)


func _update_ui_text() -> void:
	if is_instance_valid(_start_game_button):
		_start_game_button.text = tr("BTN_START_GAME")
	if is_instance_valid(_load_bookmark_button):
		_load_bookmark_button.text = tr("BTN_LOAD_BOOKMARK")
	if is_instance_valid(_replays_button):
		_replays_button.text = tr("BTN_REPLAY_LIST")
	if is_instance_valid(_tile_catalog_button):
		_tile_catalog_button.text = tr("BTN_TILE_CATALOG")
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("SETTINGS_TITLE")
	if is_instance_valid(_quit_button):
		_quit_button.text = tr("BTN_QUIT")


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


# --- 信号处理函数 ---

func _on_start_game_button_pressed() -> void:
	_goto_scene(mode_selection_scene_path, "mode_selection_scene_path")


func _on_load_bookmark_button_pressed() -> void:
	_goto_scene(bookmark_list_scene_path, "bookmark_list_scene_path")


func _on_replays_button_pressed() -> void:
	_goto_scene(replay_list_scene_path, "replay_list_scene_path")


func _on_tile_catalog_button_pressed() -> void:
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[MainMenu] 缺少 GFUIRouterUtility，无法打开方块图鉴。")
		return
	var _catalog_panel: Node = ui_router.push_route(GameUiRouterUtility.ROUTE_TILE_CATALOG)


func _on_settings_button_pressed() -> void:
	_goto_scene(settings_scene_path, "settings_scene_path")


func _on_quit_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.quit_game()
