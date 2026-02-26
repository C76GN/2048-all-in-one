# scripts/menus/replay_list.gd

## ReplayList: 显示所有已保存回放的菜单界面。
##
## 继承自 BaseListMenu，专门负责回放视频的加载、播放与管理。
class_name ReplayList
extends BaseListMenu


# --- 常量 ---

## 游戏场景路径。
const GAME_SCENE_PATH: String = "res://scenes/game/game_play.tscn"


# --- Godot 生命周期方法 ---

func _ready() -> void:
	# 初始化工厂资源和节点引用
	_item_scene = preload("res://scenes/ui/replay_list_item.tscn")
	_primary_button = %PlayButton
	_delete_button = %DeleteButton
	
	# 连接基类基础信号
	_setup_base_signals()
	
	# 初始化 UI
	_update_ui_text()
	_update_action_buttons()
	_populate_list()
	
	# 确保父类连接了 back_button
	super._ready()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var replays: Array[ReplayData] = ReplayManager.load_replays()
	# 显式转换为普通 Array 以适配基类
	var result: Array = []
	for r in replays: result.append(r)
	return result


func _setup_item(item: Control, data: Resource) -> void:
	if item is ReplayListItem and data is ReplayData:
		item.setup(data)


func _connect_item_signals(item: Control, _data: Resource) -> void:
	if item.has_signal("replay_selected"):
		item.replay_selected.connect(_on_item_confirmed)
	if item.has_signal("item_focused"):
		item.item_focused.connect(_on_item_focused)


func _update_preview(data: Resource) -> void:
	var replay = data as ReplayData
	if not is_instance_valid(replay):
		_clear_preview()
		return

	var mode_config := load(replay.mode_config_path) as GameModeConfig
	if not is_instance_valid(mode_config):
		DetailInfoLabel.text = tr("ERR_LOAD_CONFIG")
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

	DetailInfoLabel.text = details

	if is_instance_valid(BoardPreviewNode):
		if "final_board_snapshot" in replay and not replay.final_board_snapshot.is_empty():
			BoardPreviewNode.show_snapshot(replay.final_board_snapshot, mode_config)
		else:
			BoardPreviewNode.show_message(tr("MSG_NO_PREVIEW_REPLAY"))


func _update_ui_text() -> void:
	if is_instance_valid(PageTitle):
		PageTitle.text = tr("TITLE_REPLAY_LIST")
	
	var left_column = get_node_or_null("MarginContainer/ColumnsContainer/LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label = left_column.get_child(0) as Label
		if preview_label:
			preview_label.text = tr("TITLE_REPLAY_PREVIEW")
	
	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_PLAY_REPLAY")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_REPLAY")
	if is_instance_valid(BackButton):
		BackButton.text = tr("BTN_RETURN_MAIN")
	
	var right_column = get_node_or_null("MarginContainer/ColumnsContainer/RightColumn")
	if right_column and right_column.get_child_count() > 0:
		var operations_label = right_column.get_child(0) as Label
		if operations_label:
			operations_label.text = tr("CONTROLS_TITLE")


func _do_delete_logic(data: Resource) -> void:
	var replay = data as ReplayData
	ReplayManager.delete_replay(replay.file_path)


func _on_primary_action_triggered(data: Resource) -> void:
	var replay = data as ReplayData
	GlobalGameManager.current_replay_data = replay
	GlobalGameManager.goto_scene(GAME_SCENE_PATH)


func _get_empty_message() -> String:
	return tr("MSG_NO_REPLAYS")


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_REPLAY")
