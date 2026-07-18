## Hud: 游戏界面的状态显示器。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键动态创建或复用标签，实现对不同游戏模式的自适应。
class_name Hud
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 常量 ---

## 动态流程标签列表场景。
const FLOW_LABEL_LIST_SCENE: PackedScene = preload("res://shared/scenes/ui/flow_label_list.tscn")
const _FEEDBACK_SCALE: float = 1.035
const _FEEDBACK_DURATION: float = 0.22
const _FEEDBACK_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _SCORE_FORMAT_FALLBACK: String = "分数: %d"
const _MOVE_COUNT_FORMAT_FALLBACK: String = "移动次数: %d"
const _HIGH_SCORE_FORMAT_FALLBACK: String = "最高分: %d"
const _HIGHEST_TILE_FORMAT_FALLBACK: String = "最大方块: %d"
const _TEXT_PRIMARY_COLOR: Color = Color(0.34901962, 0.2901961, 0.27058825, 1.0)


# --- 私有变量 ---

## 一个字典，用于缓存已创建的UI节点，以避免每帧重复创建。
## 结构: { "data_key": ControlNode }
var _stat_labels: Dictionary = {}

var _is_dirty: bool = false
var _game_status_model: GameStatusModel
var _notification_utility: GFNotificationUtility
var _signal_utility: GFSignalUtility
var _ui_motion_utility: GameUiMotionUtility
var _score_value_label: Label
var _move_count_value_label: Label
var _highest_tile_value_label: Label
var _score_caption_label: Label
var _moves_caption_label: Label
var _highest_tile_caption_label: Label
var _notification_label: RichTextLabel
var _details_panel: VBoxContainer
var _details_toggle_button: Button
var _active_notification_id: int = 0
var _last_display_values: Dictionary = {}
var _is_compact_mode: bool = false
var _details_expanded: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _stats_container: VBoxContainer = $DetailsPanel/StatsContainer
@onready var _title_label: Label = $DetailsPanel/TitleLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = _get_game_status_model()
	_notification_utility = _get_notification_utility()
	_signal_utility = _get_signal_utility()
	_ui_motion_utility = _get_ui_motion_utility()
	if not is_instance_valid(_ui_motion_utility):
		push_error("[Hud] 缺少 GameUiMotionUtility，无法播放状态反馈动效。")
	
	_score_value_label = _get_label_node("%ScoreValueLabel")
	_move_count_value_label = _get_label_node("%MoveCountValueLabel")
	_highest_tile_value_label = _get_label_node("%HighestTileValueLabel")
	_score_caption_label = _get_label_node("%ScoreCaptionLabel")
	_moves_caption_label = _get_label_node("%MovesCaptionLabel")
	_highest_tile_caption_label = _get_label_node("%HighestTileCaptionLabel")
	_notification_label = _get_rich_text_label_node("%NotificationLabel")
	_details_panel = _get_vbox_container_node("%DetailsPanel")
	_details_toggle_button = _get_button_node("%DetailsToggleButton")
	if not is_instance_valid(_notification_label):
		push_error("[Hud] 缺少 NotificationLabel，无法呈现 GF 通知。")
	
	if is_instance_valid(_game_status_model):
		_game_status_model.score.bind_to(self, _on_score_changed)
		_game_status_model.move_count.bind_to(self, _on_move_count_changed)
		_game_status_model.high_score.bind_to(self, _on_high_score_changed)
		_game_status_model.highest_tile.bind_to(self, _on_highest_tile_changed)
		_game_status_model.ratio_resolutions.bind_to(self, _on_ratio_resolutions_changed)
		_game_status_model.extra_stats.bind_to(self, _on_extra_stats_changed)
		
		_refresh_all()

	_connect_notification_signals()
	_connect_compact_hud_signals()
	_sync_active_notification()
	register_simple_event(EventNames.HUD_UPDATE_REQUESTED, GFEventListener.from_method(self, &"_on_hud_update_requested", 1))
	_update_ui_text()
	_apply_details_visibility()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	super._exit_tree()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 公共方法 ---

## 切换移动端紧凑状态；紧凑状态默认折叠低频详情。
## @param enabled: 是否启用紧凑状态。
func set_compact_mode(enabled: bool) -> void:
	if enabled and not _is_compact_mode:
		_details_expanded = false
	_is_compact_mode = enabled
	_apply_details_visibility()


# --- 私有/辅助方法 ---

## 全局刷新 UI 显示。
func _refresh_all() -> void:
	if not is_instance_valid(_game_status_model):
		return

	# 1. 更新显式标签
	var score_value: int = GFVariantData.to_int(_game_status_model.score.get_value(), 0)
	var move_count_value: int = GFVariantData.to_int(_game_status_model.move_count.get_value(), 0)
	var high_score_value: int = GFVariantData.to_int(_game_status_model.high_score.get_value(), 0)
	var highest_tile_value: int = GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)

	if is_instance_valid(_score_value_label):
		_score_value_label.text = str(score_value)
	
	if is_instance_valid(_move_count_value_label):
		_move_count_value_label.text = str(move_count_value)

	if is_instance_valid(_highest_tile_value_label):
		_highest_tile_value_label.text = str(highest_tile_value)
	
	var local_dict: Dictionary = {}
	
	if not is_instance_valid(_score_value_label):
		var score_text: String = tr("LABEL_SCORE")
		if score_text == "LABEL_SCORE" or not ":" in score_text:
			score_text = tr("SCORE_LABEL")
		local_dict[&"score"] = _format_stat_text(
			score_text,
			_SCORE_FORMAT_FALLBACK,
			score_value
		)
	
	if not is_instance_valid(_move_count_value_label):
		var move_text: String = tr("LABEL_MOVES")
		if move_text == "LABEL_MOVES" or not ":" in move_text:
			move_text = tr("MOVE_COUNT_LABEL")
		local_dict[&"move_count"] = _format_stat_text(
			move_text,
			_MOVE_COUNT_FORMAT_FALLBACK,
			move_count_value
		)

	local_dict[&"high_score"] = GameTextFormatUtility.format_template(
		tr("HIGH_SCORE_LABEL"),
		_HIGH_SCORE_FORMAT_FALLBACK,
		[high_score_value]
	)
	if not is_instance_valid(_highest_tile_value_label):
		local_dict[&"highest_tile"] = GameTextFormatUtility.format_template(
			tr("HIGHEST_TILE_LABEL"),
			_HIGHEST_TILE_FORMAT_FALLBACK,
			[highest_tile_value]
		)
	
	var query_result: Variant = send_query(GetHudStatsQuery.new())
	if query_result is Dictionary:
		var query_dict: Dictionary = GFVariantData.to_dictionary(query_result)
		local_dict.merge(query_dict)

	_update_dynamic_list(local_dict)


func _update_dynamic_list(dict: Dictionary) -> void:
	# 1. 隐藏不再存在的 key
	for key: Variant in _stat_labels:
		if not dict.has(key):
			var stale_node: Control = _get_stat_label_node(key)
			if is_instance_valid(stale_node):
				stale_node.visible = false

	var keys_in_order: Array = dict.keys()

	# 2. 动态创建或更新 UI 节点
	for key: Variant in keys_in_order:
		var data_to_display: Variant = dict[key]

		if _is_display_value_empty(data_to_display):
			if _stat_labels.has(key):
				var hidden_node: Control = _get_stat_label_node(key)
				if is_instance_valid(hidden_node):
					hidden_node.visible = false
			continue

		var ui_node: Control
		var needs_recreation: bool = false
		
		if _stat_labels.has(key):
			var existing_node: Control = _get_stat_label_node(key)
			if not is_instance_valid(existing_node):
				needs_recreation = true
			elif (
				(data_to_display is Array and not existing_node is FlowLabelList)
				or (not data_to_display is Array and existing_node is FlowLabelList)
			):
				existing_node.queue_free()
				needs_recreation = true
		else:
			needs_recreation = true

		if needs_recreation:
			if data_to_display is Array:
				var flow_label_node: Node = FLOW_LABEL_LIST_SCENE.instantiate()
				if not flow_label_node is Control:
					continue
				var flow_control: Control = flow_label_node
				ui_node = flow_control
			else:
				var new_label: RichTextLabel = RichTextLabel.new()
				new_label.bbcode_enabled = true
				new_label.fit_content = true
				new_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_style_dynamic_rich_label(new_label)
				ui_node = new_label

			_stats_container.add_child(ui_node)
			_stat_labels[key] = ui_node
		else:
			ui_node = _get_stat_label_node(key)
			if not is_instance_valid(ui_node):
				continue

		if ui_node is FlowLabelList:
			var data_array: Array = GFVariantData.to_array(data_to_display)
			var flow_label_list: FlowLabelList = ui_node
			flow_label_list.update_data(data_array)
		elif ui_node is RichTextLabel:
			var rich_label: RichTextLabel = ui_node
			_style_dynamic_rich_label(rich_label)
			rich_label.text = str(data_to_display)

		ui_node.visible = true
		var display_signature: String = _make_display_signature(data_to_display)
		if not _last_display_values.has(key) or _last_display_values[key] != display_signature:
			_pulse_control(ui_node)
		_last_display_values[key] = display_signature


func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_GAME_STATUS")
	if is_instance_valid(_score_caption_label):
		_score_caption_label.text = _extract_caption(tr("LABEL_SCORE"), "分数", "LABEL_SCORE")
	if is_instance_valid(_moves_caption_label):
		_moves_caption_label.text = _extract_caption(tr("LABEL_MOVES"), "步数", "LABEL_MOVES")
	if is_instance_valid(_highest_tile_caption_label):
		_highest_tile_caption_label.text = _extract_caption(
			tr("HIGHEST_TILE_LABEL"),
			"最大方块",
			"HIGHEST_TILE_LABEL"
		)
	_update_details_toggle_button()


func _extract_caption(template: String, fallback: String, missing_key: String) -> String:
	if template.is_empty() or template == missing_key:
		return fallback
	var result: String = template
	var placeholder_index: int = result.find("%")
	if placeholder_index >= 0:
		result = result.left(placeholder_index)
	result = result.strip_edges().trim_suffix(":").trim_suffix("：").strip_edges()
	return result if not result.is_empty() else fallback


func _format_stat_text(template: String, fallback: String, value: int) -> String:
	if template.contains("%"):
		return GameTextFormatUtility.format_template(template, fallback, [value])
	return template + " [b]" + str(value) + "[/b]"


func _style_dynamic_rich_label(label: RichTextLabel) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_color_override("default_color", _TEXT_PRIMARY_COLOR)
	label.add_theme_color_override("font_selected_color", _TEXT_PRIMARY_COLOR)
	label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	label.modulate = Color.WHITE


func _mark_dirty() -> void:
	if not _is_dirty:
		_is_dirty = true
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	if _is_dirty:
		_is_dirty = false
		_refresh_all()


func _pulse_control(control: Control) -> void:
	if not is_instance_valid(control) or not is_instance_valid(_ui_motion_utility):
		return
	var _feedback_tween: Tween = _ui_motion_utility.play_control_pulse(
		control,
		_FEEDBACK_SCALE,
		_FEEDBACK_COLOR,
		_FEEDBACK_DURATION
	)


func _get_stat_label_node(key: Variant) -> Control:
	var node_value: Variant = _stat_labels[key] if _stat_labels.has(key) else null
	if node_value is Control:
		var control: Control = node_value
		return control
	return null


func _get_game_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_notification_utility() -> GFNotificationUtility:
	var utility_value: Object = get_utility(GFNotificationUtility)
	if utility_value is GFNotificationUtility:
		var notification_utility: GFNotificationUtility = utility_value
		return notification_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = get_utility(GameUiMotionUtility)
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_label_node(path: NodePath) -> Label:
	var node_value: Node = get_node_or_null(path)
	if node_value is Label:
		var label: Label = node_value
		return label
	return null


func _get_rich_text_label_node(path: NodePath) -> RichTextLabel:
	var node_value: Node = get_node_or_null(path)
	if node_value is RichTextLabel:
		var label: RichTextLabel = node_value
		return label
	return null


func _get_vbox_container_node(path: NodePath) -> VBoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is VBoxContainer:
		var container: VBoxContainer = node_value
		return container
	return null


func _get_button_node(path: NodePath) -> Button:
	var node_value: Node = get_node_or_null(path)
	if node_value is Button:
		var button: Button = node_value
		return button
	return null


func _connect_notification_signals() -> void:
	if not is_instance_valid(_notification_utility):
		push_error("[Hud] 缺少 GFNotificationUtility，无法读取通知队列。")
		return
	if not is_instance_valid(_signal_utility):
		push_error("[Hud] 缺少 GFSignalUtility，无法管理通知信号生命周期。")
		return

	var _started_connection: GFSignalConnection = _signal_utility.connect_signal(
		_notification_utility.notification_started,
		_on_notification_started,
		self
	)
	var _finished_connection: GFSignalConnection = _signal_utility.connect_signal(
		_notification_utility.notification_finished,
		_on_notification_finished,
		self
	)


func _connect_compact_hud_signals() -> void:
	if not is_instance_valid(_signal_utility) or not is_instance_valid(_details_toggle_button):
		return
	var _toggle_connection: GFSignalConnection = _signal_utility.connect_signal(
		_details_toggle_button.pressed,
		_on_details_toggle_pressed,
		self
	)


func _apply_details_visibility() -> void:
	if is_instance_valid(_details_panel):
		_details_panel.visible = not _is_compact_mode or _details_expanded
	if is_instance_valid(_details_toggle_button):
		_details_toggle_button.visible = _is_compact_mode
	_update_details_toggle_button()


func _update_details_toggle_button() -> void:
	if not is_instance_valid(_details_toggle_button):
		return
	_details_toggle_button.text = "-" if _details_expanded else "+"
	var tooltip_key: String = "HUD_DETAILS_COLLAPSE" if _details_expanded else "HUD_DETAILS_EXPAND"
	var fallback: String = "收起详细状态" if _details_expanded else "展开详细状态"
	var translated_tooltip: String = tr(tooltip_key)
	_details_toggle_button.tooltip_text = (
		fallback if translated_tooltip == tooltip_key else translated_tooltip
	)


func _sync_active_notification() -> void:
	if not is_instance_valid(_notification_utility):
		_set_notification_message(0, "")
		return
	var notification_record: Dictionary = _notification_utility.get_active_notification()
	if notification_record.is_empty():
		_set_notification_message(0, "")
		return
	_on_notification_started(notification_record)


func _set_notification_message(notification_id: int, message: String) -> void:
	_active_notification_id = notification_id
	if not is_instance_valid(_notification_label):
		return
	_notification_label.text = message
	_notification_label.visible = not message.is_empty()
	if not message.is_empty():
		_pulse_control(_notification_label)


static func _is_display_value_empty(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		var text_value: String = value
		return text_value.is_empty()
	if value is Array:
		var array_value: Array = value
		return array_value.is_empty()
	return false


func _make_display_signature(value: Variant) -> String:
	return var_to_str(value)


# --- 信号处理函数 ---

func _on_hud_update_requested(_p: Variant = null) -> void:
	_mark_dirty()


func _on_score_changed(_old_value: int, _new_value: int) -> void:
	_pulse_control(_score_value_label)
	_mark_dirty()


func _on_move_count_changed(_old_value: int, _new_value: int) -> void:
	_pulse_control(_move_count_value_label)
	_mark_dirty()


func _on_high_score_changed(_old: int, _new_value: int) -> void:
	_mark_dirty()


func _on_highest_tile_changed(_old: int, _new_value: int) -> void:
	_pulse_control(_highest_tile_value_label)
	_mark_dirty()


func _on_details_toggle_pressed() -> void:
	if not _is_compact_mode:
		return
	_details_expanded = not _details_expanded
	_apply_details_visibility()


func _on_notification_started(notification_record: Dictionary) -> void:
	_set_notification_message(
		GFVariantData.get_option_int(notification_record, "id"),
		GFVariantData.get_option_string(notification_record, "message")
	)


func _on_notification_finished(notification_record: Dictionary, _reason: String) -> void:
	var notification_id: int = GFVariantData.get_option_int(notification_record, "id")
	if notification_id == _active_notification_id:
		_set_notification_message(0, "")


func _on_ratio_resolutions_changed(_old: int, _new: int) -> void:
	_mark_dirty()


## 响应式更新动态统计数据。
## @param _old: 旧数据字典。
## @param _dict: 新数据字典。结构：{ "key": "显示文本" 或 Array[Dictionary] }
func _on_extra_stats_changed(_old: Dictionary, _dict: Dictionary) -> void:
	_mark_dirty()
