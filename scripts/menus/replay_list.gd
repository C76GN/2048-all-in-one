# scripts/menus/replay_list.gd

## ReplayList: 显示所有已保存回放的菜单界面。
##
## 继承自 BaseListMenu，专门负责回放的加载、播放与管理。
class_name ReplayList
extends BaseListMenu


# --- 常量 ---

const GAME_MODE_CONFIG_CACHE = preload("res://scripts/utilities/game_mode_config_cache.gd")


# --- 导出变量 ---

## 游戏主场景路径。
@export_file("*.tscn") var game_scene_path: String = ""

## 回放列表项场景资源。
@export var item_scene: PackedScene


# --- Godot 生命周期方法 ---

func _ready() -> void:
	assert(not game_scene_path.is_empty(), "ReplayList: 游戏场景路径 (game_scene_path) 未在编辑器中设置。")
	assert(item_scene != null, "ReplayList: 列表项场景 (item_scene) 未在编辑器中设置。")

	_item_scene = item_scene
	_primary_button = %PlayButton
	_delete_button = %DeleteButton

	_setup_base_signals()
	_update_ui_text()
	_update_action_buttons()
	_populate_list()

	super._ready()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var replay_system := get_system(ReplaySystem) as ReplaySystem
	var replays: Array[ReplayData] = []
	if replay_system:
		replays = replay_system.load_replays()
	var result: Array = []
	for replay_data in replays:
		result.append(replay_data)
	return result


func _setup_item(item: Control, data: Resource) -> void:
	if item is ReplayListItem and data is ReplayData:
		item.setup(data)


func _connect_item_signals(item: Control, _data: Resource) -> void:
	if item.has_signal("replay_selected"):
		if not item.replay_selected.is_connected(_on_item_confirmed):
			item.replay_selected.connect(_on_item_confirmed)
	if item.has_signal("item_focused"):
		if not item.item_focused.is_connected(_on_item_focused):
			item.item_focused.connect(_on_item_focused)


func _update_preview(data: Resource) -> void:
	var replay = data as ReplayData
	if not is_instance_valid(replay):
		_clear_preview()
		return

	var mode_config: GameModeConfig = GAME_MODE_CONFIG_CACHE.get_config(replay.mode_config_path)
	if not is_instance_valid(mode_config):
		detail_info_label.text = tr("ERR_LOAD_CONFIG")
		if is_instance_valid(board_preview_node):
			board_preview_node.show_message(tr("ERR_LOAD_CONFIG"))
		return

	var datetime: String = Time.get_datetime_string_from_unix_time(replay.timestamp)
	var grid_size: int = replay.grid_size

	var details: String = ""
	details += "[b]%s[/b] %s\n" % [tr("LABEL_MODE"), tr(mode_config.mode_name)]
	details += "[b]%s[/b] %s\n" % [tr("LABEL_TIME"), datetime.replace("T", " ")]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_FINAL_SCORE"), replay.final_score]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_TOTAL_MOVES"), replay.actions.size()]
	details += "[b]%s[/b] %dx%d\n" % [tr("LABEL_BOARD"), grid_size, grid_size]
	details += "[b]%s[/b] %d" % [tr("LABEL_SEED"), replay.initial_seed]

	detail_info_label.text = details

	if is_instance_valid(board_preview_node):
		if "final_board_snapshot" in replay and not replay.final_board_snapshot.is_empty():
			board_preview_node.show_snapshot(replay.final_board_snapshot, mode_config)
		else:
			board_preview_node.show_message(tr("MSG_NO_PREVIEW_REPLAY"))


func _update_ui_text() -> void:
	if is_instance_valid(page_title):
		page_title.text = tr("TITLE_REPLAY_LIST")

	var left_column := get_node_or_null("MarginContainer/ColumnsContainer/LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label := left_column.get_child(0) as Label
		if preview_label:
			preview_label.text = tr("TITLE_REPLAY_PREVIEW")

	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_PLAY_REPLAY")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_REPLAY")
	if is_instance_valid(back_button):
		back_button.text = tr("BTN_RETURN_MAIN")

	var right_column := get_node_or_null("MarginContainer/ColumnsContainer/RightColumn")
	if right_column and right_column.get_child_count() > 0:
		var operations_label := right_column.get_child(0) as Label
		if operations_label:
			operations_label.text = tr("CONTROLS_TITLE")


func _do_delete_logic(data: Resource) -> void:
	var replay = data as ReplayData
	var replay_system := get_system(ReplaySystem) as ReplaySystem
	if replay_system:
		replay_system.delete_replay(replay.file_path)


func _on_primary_action_triggered(data: Resource) -> void:
	var replay = data as ReplayData
	var app_config := get_model(AppConfigModel) as AppConfigModel
	if app_config:
		app_config.selected_bookmark_data.set_value(null)
		app_config.current_replay_data.set_value(replay)

	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.goto_scene(game_scene_path)


func _get_empty_message() -> String:
	return tr("MSG_NO_REPLAYS")


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_REPLAY")
