## ReplayList: 显示所有已保存回放的菜单界面。
##
## 继承自 BaseListMenu，专门负责回放的加载、播放与管理。
class_name ReplayList
extends BaseListMenu


# --- 常量 ---

const _MARKER_SUMMARY_FORMAT_FALLBACK: String = "%d markers · %d merges · %d key events"


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

	super._ready()
	_setup_base_signals()
	_update_ui_text()
	_update_action_buttons()
	await _populate_list()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var replay_system: ReplaySystem = _get_replay_system()
	var replays: Array[ReplayData] = []
	if is_instance_valid(replay_system):
		replays = replay_system.load_replays()
	var result: Array = []
	for replay_data: ReplayData in replays:
		result.append(replay_data)
	return result


func _setup_item(item: Control, data: Resource) -> void:
	if not item is ReplayListItem or not data is ReplayData:
		return

	var replay_item: ReplayListItem = item
	var replay_data: ReplayData = data
	replay_item.setup(replay_data, _get_mode_display_name(replay_data.mode_config_path))


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
	var markers: Array[ReplayMarker] = ReplayMarker.build_catalog(replay)
	var merge_markers: int = ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.MERGE)
	var key_event_markers: int = (
		ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.CHAIN_OR_TRANSFORM)
		+ ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.MILESTONE)
		+ ReplayMarker.count_by_kind(markers, ReplayMarker.Kind.FAILURE)
	)
	details += "[b]%s[/b] %s\n" % [
		tr("LABEL_REPLAY_MARKERS"),
		GameTextFormatUtility.format_template(
			tr("REPLAY_MARKER_SUMMARY_FORMAT"),
			_MARKER_SUMMARY_FORMAT_FALLBACK,
			[markers.size(), merge_markers, key_event_markers]
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

func _do_delete_logic(data: Resource) -> Error:
	if not data is ReplayData:
		return ERR_INVALID_PARAMETER

	var replay: ReplayData = data
	var replay_system: ReplaySystem = _get_replay_system()
	if not is_instance_valid(replay_system):
		return ERR_UNCONFIGURED
	return replay_system.delete_replay(replay.replay_id)


func _on_primary_action_triggered(data: Resource) -> void:
	if not data is ReplayData:
		return

	var replay: ReplayData = data
	var app_config: AppConfigModel = _get_app_config_model()
	if is_instance_valid(app_config):
		app_config.selected_bookmark_data.set_value(null)
		app_config.current_replay_data.set_value(replay)

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.goto_scene(game_scene_path)


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


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
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
	return tr("MSG_NO_REPLAYS")


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
	var preview_separator: Node = _left_column.get_node_or_null("HSeparator")
	if is_instance_valid(preview_separator):
		preview_separator.visible = not is_empty
	if is_instance_valid(detail_info_label):
		detail_info_label.vertical_alignment = (
			VERTICAL_ALIGNMENT_CENTER if is_empty else VERTICAL_ALIGNMENT_TOP
		)
		if is_empty:
			detail_info_label.text = "[center]%s[/center]" % tr(
				"MSG_EMPTY_REPLAY_GUIDANCE"
			)
	if is_instance_valid(_primary_button):
		_primary_button.visible = not is_empty
	if is_instance_valid(_delete_button):
		_delete_button.visible = not is_empty


func _get_delete_confirmation_message(_data: Resource) -> String:
	return tr("DELETE_REPLAY_CONFIRMATION")


func _get_delete_failure_message(error: Error) -> String:
	return tr("DELETE_REPLAY_FAILED") % int(error)
