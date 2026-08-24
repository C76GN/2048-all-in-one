## ReplayList: 显示所有已保存回放的菜单界面。
##
## 继承自 BaseListMenu，专门负责回放的加载、播放与管理。
class_name ReplayList
extends BaseListMenu


# --- 常量 ---

const _MARKER_SUMMARY_FORMAT_FALLBACK: String = "%d markers · %d merges · %d key events"


# --- 导出变量 ---

## 回放列表项场景资源。
@export var item_scene: PackedScene


# --- 私有变量 ---

var _marker_summary_by_replay_id: Dictionary = {}


# --- Godot 生命周期方法 ---

func _ready() -> void:
	assert(item_scene != null, "ReplayList: 列表项场景 (item_scene) 未在编辑器中设置。")

	_item_scene = item_scene
	_primary_button = %PlayButton
	_delete_button = %DeleteButton

	super._ready()
	_setup_base_signals()
	_update_ui_text()
	_update_action_buttons()
	await _populate_list()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	_marker_summary_by_replay_id.clear()
	var replay_system: ReplaySystem = _get_replay_system()
	var replays: Array[ReplayData] = []
	if is_instance_valid(replay_system):
		replays = replay_system.load_replays()
	var result: Array = []
	for replay_data: ReplayData in replays:
		result.append(replay_data)
	return result


func _get_data_identity(data: Resource) -> String:
	if data is ReplayData:
		var replay: ReplayData = data
		return replay.replay_id
	return ""


func _setup_item(item: Control, data: Resource) -> void:
	if not item is ReplayListItem or not data is ReplayData:
		return

	var replay_item: ReplayListItem = item
	var replay_data: ReplayData = data
	var marker_summary: Dictionary = _get_marker_summary(replay_data)
	replay_item.setup(
		replay_data,
		_get_mode_display_name(replay_data.mode_config_path),
		GFVariantData.get_option_int(marker_summary, &"total")
	)


func _update_preview(data: Resource) -> void:
	if not data is ReplayData:
		_clear_preview()
		return

	var replay: ReplayData = data
	var mode_config: GameModeConfig = _get_mode_config(replay.mode_config_path)
	if not is_instance_valid(mode_config):
		detail_info_label.text = tr("ERR_LOAD_CONFIG")
		if is_instance_valid(board_preview_node):
			board_preview_node.show_message(tr("ERR_LOAD_CONFIG"))
		return

	var datetime: String = _format_datetime(replay.timestamp)
	var topology: BoardTopology = replay.get_initial_topology()
	var board_label: String = topology.get_size_label() if topology != null else tr("UI_NONE")

	var details: String = ""
	details += "[b]%s[/b] %s   [b]%s[/b] %s\n" % [
		tr("LABEL_MODE"),
		tr(mode_config.mode_name),
		tr("LABEL_BOARD"),
		board_label,
	]
	details += "[b]%s[/b] %s\n" % [tr("LABEL_TIME"), datetime]
	details += "[b]%s[/b] %d   [b]%s[/b] %d\n" % [
		tr("LABEL_FINAL_SCORE"),
		replay.final_score,
		tr("LABEL_TOTAL_MOVES"),
		replay.actions.size(),
	]
	var marker_summary: Dictionary = _get_marker_summary(replay)
	details += "[b]%s[/b] %s\n" % [
		tr("LABEL_REPLAY_MARKERS"),
		GameTextFormatUtility.format_template(
			tr("REPLAY_MARKER_SUMMARY_FORMAT"),
			_MARKER_SUMMARY_FORMAT_FALLBACK,
			[
				GFVariantData.get_option_int(marker_summary, &"total"),
				GFVariantData.get_option_int(marker_summary, &"merges"),
				GFVariantData.get_option_int(marker_summary, &"key_events"),
			]
		),
	]
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

	var left_column: Node = get_node_or_null("%LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label: Label = _get_first_label_child(left_column)
		if is_instance_valid(preview_label):
			preview_label.text = tr("TITLE_REPLAY_PREVIEW")

	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_PLAY_REPLAY")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_REPLAY")
	if is_instance_valid(back_button):
		back_button.text = tr("BTN_RETURN_MAIN")

func _do_delete_logic(data: Resource) -> GameSaveSectionOperation:
	if not data is ReplayData:
		return null

	var replay: ReplayData = data
	var replay_system: ReplaySystem = _get_replay_system()
	if not is_instance_valid(replay_system):
		return null
	return replay_system.request_delete_replay(replay.replay_id)


func _on_primary_action_triggered(data: Resource) -> void:
	if not data is ReplayData:
		return

	var replay: ReplayData = data
	var launch_port: GameSessionLaunchPort = _get_session_launch_port()
	if not is_instance_valid(launch_port):
		push_error("[ReplayList] 缺少 GameSessionLaunchPort，无法启动回放。")
		return
	var _launched: bool = launch_port.launch_replay(replay.replay_id)


func _get_replay_system() -> ReplaySystem:
	var system_value: Object = get_system(ReplaySystem)
	if system_value is ReplaySystem:
		var replay_system: ReplaySystem = system_value
		return replay_system
	return null


func _get_mode_display_name(mode_config_path: String) -> String:
	if mode_config_path.is_empty():
		return tr("UNKNOWN_MODE")

	var mode_config: GameModeConfig = _get_mode_config(mode_config_path)
	if is_instance_valid(mode_config):
		return tr(mode_config.mode_name)

	return tr("CONFIG_MISSING")


func _get_marker_summary(replay: ReplayData) -> Dictionary:
	if not is_instance_valid(replay) or replay.replay_id.is_empty():
		return {}
	var cached_value: Variant = _marker_summary_by_replay_id.get(
		replay.replay_id
	)
	if cached_value is Dictionary:
		var cached_summary: Dictionary = cached_value
		return cached_summary
	var summary: Dictionary = ReplayMarker.summarize_counts(replay)
	_marker_summary_by_replay_id[replay.replay_id] = summary
	return summary


func _get_session_launch_port() -> GameSessionLaunchPort:
	var system_value: Object = get_system(GameSessionLaunchPort)
	if system_value is GameSessionLaunchPort:
		var launch_port: GameSessionLaunchPort = system_value
		return launch_port
	return null


func _get_first_label_child(parent: Node) -> Label:
	if not is_instance_valid(parent) or parent.get_child_count() <= 0:
		return null

	var child: Node = parent.get_child(0)
	if child is Label:
		var label: Label = child
		return label
	return null


func _get_empty_message() -> String:
	return "%s\n%s" % [
		tr("MSG_NO_REPLAYS"),
		tr("MSG_EMPTY_REPLAY_GUIDANCE"),
	]


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_REPLAY")


func _get_empty_detail_message() -> String:
	return tr("MSG_EMPTY_REPLAY_GUIDANCE")


func _on_empty_state_changed(is_empty: bool) -> void:
	var preview_heading: Label = _get_first_label_child(_left_column)
	if is_instance_valid(preview_heading):
		preview_heading.visible = not is_empty
	if is_instance_valid(_preview_container):
		_preview_container.visible = not is_empty
	var preview_separator_node: Node = _left_column.get_node_or_null("HSeparator")
	if preview_separator_node is HSeparator:
		var preview_separator: HSeparator = preview_separator_node
		preview_separator.visible = not is_empty
	if is_instance_valid(detail_info_label):
		detail_info_label.visible = not is_empty
		detail_info_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if is_instance_valid(_primary_button):
		_primary_button.visible = not is_empty
	if is_instance_valid(_delete_button):
		_delete_button.visible = not is_empty


func _get_delete_confirmation_message(_data: Resource) -> String:
	return tr("DELETE_REPLAY_CONFIRMATION")


func _get_delete_failure_message(error: Error) -> String:
	return tr("DELETE_REPLAY_FAILED") % int(error)


func _uses_virtual_list() -> bool:
	return true
