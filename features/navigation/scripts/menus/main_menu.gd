## MainMenu: 主菜单界面的 UI 控制器。
##
## 负责处理主菜单中的所有用户交互，
## 并通过 SceneRouterSystem 执行场景切换或退出游戏。
class_name MainMenu
extends GameUiController


# --- 常量 ---

const _COMPACT_BREAKPOINT: float = 900.0
const _COMPACT_HEIGHT_BREAKPOINT: float = 620.0


# --- 导出变量 ---

## 模式选择场景路径。
@export_file("*.tscn") var mode_selection_scene_path: String = ""

## 回放列表场景路径。
@export_file("*.tscn") var replay_list_scene_path: String = ""

## 书签列表场景路径。
@export_file("*.tscn") var bookmark_list_scene_path: String = ""

## 设置场景路径。
@export_file("*.tscn") var settings_scene_path: String = ""


# --- 私有变量 ---

var _layout_update_queued: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _start_game_button: Button = %StartGameButton
@onready var _load_bookmark_button: Button = %LoadBookmarkButton
@onready var _replays_button: Button = %ReplaysButton
@onready var _tile_catalog_button: Button = %TileCatalogButton
@onready var _achievements_button: Button = %AchievementsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _safe_margin: MarginContainer = %SafeMargin
@onready var _content: BoxContainer = %Content
@onready var _showcase: VBoxContainer = %Showcase
@onready var _board_preview_frame: Panel = %BoardPreviewFrame
@onready var _menu_column: VBoxContainer = %MenuColumn
@onready var _title_label: Label = %TitleLabel
@onready var _edition_label: Label = %EditionLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _kicker_label: Label = %KickerLabel
@onready var _menu_kicker_label: Label = %MenuKickerLabel
@onready var _collection_label: Label = %CollectionLabel
@onready var _system_label: Label = %SystemLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _connect_result_36: int = _start_game_button.pressed.connect(_on_start_game_button_pressed)
	var _connect_result_37: int = _load_bookmark_button.pressed.connect(_on_load_bookmark_button_pressed)
	var _connect_result_38: int = _replays_button.pressed.connect(_on_replays_button_pressed)
	var _catalog_connection: int = _tile_catalog_button.pressed.connect(_on_tile_catalog_button_pressed)
	var _achievements_connection: int = _achievements_button.pressed.connect(_on_achievements_button_pressed)
	var _connect_result_39: int = _settings_button.pressed.connect(_on_settings_button_pressed)
	var _connect_result_40: int = _quit_button.pressed.connect(_on_quit_button_pressed)
	var _resize_connection: int = resized.connect(_queue_layout_update)

	_apply_semantic_styles()
	_queue_layout_update()
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
	if is_instance_valid(_kicker_label):
		_kicker_label.text = tr("MAIN_MENU_KICKER")
	if is_instance_valid(_subtitle_label):
		_subtitle_label.text = tr("MAIN_MENU_SUBTITLE")
	if is_instance_valid(_menu_kicker_label):
		_menu_kicker_label.text = tr("MAIN_MENU_PLAY")
	if is_instance_valid(_collection_label):
		_collection_label.text = tr("MAIN_MENU_COLLECTION")
	if is_instance_valid(_system_label):
		_system_label.text = tr("MAIN_MENU_SYSTEM")
	if is_instance_valid(_start_game_button):
		_start_game_button.text = tr("BTN_START_GAME")
	if is_instance_valid(_load_bookmark_button):
		_load_bookmark_button.text = tr("BTN_CONTINUE_GAME")
	if is_instance_valid(_replays_button):
		_replays_button.text = tr("BTN_REPLAY_LIST")
	if is_instance_valid(_tile_catalog_button):
		_tile_catalog_button.text = tr("BTN_TILE_CATALOG")
	if is_instance_valid(_achievements_button):
		_achievements_button.text = tr("BTN_ACHIEVEMENTS")
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("SETTINGS_TITLE")
	if is_instance_valid(_quit_button):
		_quit_button.text = tr("BTN_QUIT")


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_edition_label, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_subtitle_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_kicker_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_menu_kicker_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_collection_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_system_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_button(_start_game_button, GameUiStyleUtility.ButtonRole.PRIMARY)
	style.style_button(_load_bookmark_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_replays_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_tile_catalog_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_achievements_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_settings_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_quit_button, GameUiStyleUtility.ButtonRole.QUIET)


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var compact: bool = size.x < _COMPACT_BREAKPOINT or size.y < _COMPACT_HEIGHT_BREAKPOINT
	_content.vertical = compact
	_board_preview_frame.visible = not compact
	_showcase.size_flags_vertical = (
		Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL
	)
	_menu_column.size_flags_vertical = (
		Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_SHRINK_CENTER
	)
	_showcase.custom_minimum_size.x = 0.0 if compact else 520.0
	_menu_column.custom_minimum_size.x = 0.0 if compact else 360.0
	_content.add_theme_constant_override("separation", 18 if compact else 56)
	_menu_column.add_theme_constant_override("separation", 8 if compact else 10)
	_safe_margin.add_theme_constant_override("margin_left", 20 if compact else 56)
	_safe_margin.add_theme_constant_override("margin_right", 20 if compact else 56)
	_safe_margin.add_theme_constant_override("margin_top", 26 if compact else 44)
	_safe_margin.add_theme_constant_override("margin_bottom", 22 if compact else 42)
	_title_label.add_theme_font_size_override("font_size", 56 if compact else 104)
	_edition_label.add_theme_font_size_override("font_size", 18 if compact else 24)
	_subtitle_label.add_theme_font_size_override("font_size", 13 if compact else 16)
	_subtitle_label.custom_minimum_size.x = 180.0 if compact else 220.0
	_start_game_button.custom_minimum_size.y = 58.0 if compact else 68.0
	_load_bookmark_button.custom_minimum_size.y = 48.0 if compact else 54.0


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


func _on_achievements_button_pressed() -> void:
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[MainMenu] 缺少 GFUIRouterUtility，无法打开成就列表。")
		return
	var _achievements_panel: Node = ui_router.push_route(
		GameUiRouterUtility.ROUTE_ACHIEVEMENTS
	)


func _on_settings_button_pressed() -> void:
	_goto_scene(settings_scene_path, "settings_scene_path")


func _on_quit_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.quit_game()
