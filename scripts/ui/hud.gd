## HUD: 游戏界面的状态显示器。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键动态创建或复用标签，实现对不同游戏模式的自适应。
class_name HUD
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 常量 ---

## 动态流程标签列表场景。
const FLOW_LABEL_LIST_SCENE: PackedScene = preload("res://scenes/ui/flow_label_list.tscn")
const _FEEDBACK_TWEEN_META: StringName = &"_hud_feedback_tween"
const _FEEDBACK_SCALE: float = 1.035
const _FEEDBACK_DURATION: float = 0.22
const _SCORE_FORMAT_FALLBACK: String = "分数: %d"
const _MOVE_COUNT_FORMAT_FALLBACK: String = "移动次数: %d"
const _HIGH_SCORE_FORMAT_FALLBACK: String = "最高分: %d"
const _HIGHEST_TILE_FORMAT_FALLBACK: String = "最大方块: %d"
const _TEXT_PRIMARY_COLOR: Color = Color(0.34901962, 0.2901961, 0.27058825, 1.0)
const _TEXT_ACCENT_COLOR_HEX: String = "#944431"


# --- 私有变量 ---

## 一个字典，用于缓存已创建的UI节点，以避免每帧重复创建。
## 结构: { "data_key": ControlNode }
var _stat_labels: Dictionary = {}

var _is_dirty: bool = false
var _game_status_model: GameStatusModel
var _score_value_label: Label
var _move_count_value_label: Label
var _status_message_label: RichTextLabel
var _last_display_values: Dictionary = {}


# --- @onready 变量 (节点引用) ---

@onready var _stats_container: VBoxContainer = $StatsContainer
@onready var _title_label: Label = $TitleLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = _get_game_status_model()
	
	_score_value_label = _get_label_node("%ScoreValueLabel")
	_move_count_value_label = _get_label_node("%MoveCountValueLabel")
	var status_msg_node: Node = get_node_or_null("%StatusMessageLabel")
	if status_msg_node is RichTextLabel:
		var status_label: RichTextLabel = status_msg_node
		_status_message_label = status_label
	
	if is_instance_valid(_game_status_model):
		_game_status_model.score.bind_to(self, _on_score_changed)
		_game_status_model.move_count.bind_to(self, _on_move_count_changed)
		_game_status_model.high_score.bind_to(self, _on_high_score_changed)
		_game_status_model.highest_tile.bind_to(self, _on_highest_tile_changed)
		_game_status_model.monsters_killed.bind_to(self, _on_monsters_killed_changed)
		_game_status_model.status_message.bind_to(self, _on_status_message_changed)
		_game_status_model.extra_stats.bind_to(self, _on_extra_stats_changed)
		
		_refresh_all()
		
	register_simple_event(EventNames.HUD_UPDATE_REQUESTED, _on_hud_update_requested)
	_update_ui_text()


func _exit_tree() -> void:
	unregister_simple_event(EventNames.HUD_UPDATE_REQUESTED, _on_hud_update_requested)
	super._exit_tree()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


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
	var status_message: String = GFVariantData.to_text(_game_status_model.status_message.get_value(), "")

	if is_instance_valid(_score_value_label):
		_score_value_label.text = str(score_value)
	
	if is_instance_valid(_move_count_value_label):
		_move_count_value_label.text = str(move_count_value)
	
	if is_instance_valid(_status_message_label):
		_status_message_label.text = status_message
		_status_message_label.visible = not status_message.is_empty()

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
	local_dict[&"highest_tile"] = GameTextFormatUtility.format_template(
		tr("HIGHEST_TILE_LABEL"),
		_HIGHEST_TILE_FORMAT_FALLBACK,
		[highest_tile_value]
	)
	
	if not is_instance_valid(_status_message_label):
		if not status_message.is_empty():
			local_dict[&"status_message"] = "[color=%s]%s[/color]" % [_TEXT_ACCENT_COLOR_HEX, status_message]

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
	if not is_instance_valid(control):
		return

	control.pivot_offset = control.size * 0.5
	_kill_feedback_tween(control)
	control.scale = Vector2.ONE * _FEEDBACK_SCALE
	control.modulate = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
	if not control.is_inside_tree():
		control.scale = Vector2.ONE
		control.modulate = Color.WHITE
		return

	var tween: Tween = control.create_tween()
	var _parallel_tween: Tween = tween.set_parallel(true)
	var _trans_tween: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_tween: Tween = tween.set_ease(Tween.EASE_OUT)
	var _scale_tweener: PropertyTweener = tween.tween_property(control, "scale", Vector2.ONE, _FEEDBACK_DURATION)
	var _modulate_tweener: PropertyTweener = tween.tween_property(control, "modulate", Color.WHITE, _FEEDBACK_DURATION)
	control.set_meta(_FEEDBACK_TWEEN_META, tween)


func _kill_feedback_tween(control: Control) -> void:
	var tween: Tween = null
	if is_instance_valid(control) and control.has_meta(_FEEDBACK_TWEEN_META):
		tween = _get_tween_value(control.get_meta(_FEEDBACK_TWEEN_META))
	if tween != null and tween.is_valid():
		tween.kill()
	control.set_meta(_FEEDBACK_TWEEN_META, null)


func _get_tween_value(value: Variant) -> Tween:
	if value is Tween:
		var tween: Tween = value
		return tween
	return null


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


func _get_label_node(path: NodePath) -> Label:
	var node_value: Node = get_node_or_null(path)
	if node_value is Label:
		var label: Label = node_value
		return label
	return null


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
	_mark_dirty()


func _on_status_message_changed(_old: String, new_value: String) -> void:
	if is_instance_valid(_status_message_label):
		_status_message_label.text = new_value
		_status_message_label.visible = not new_value.is_empty()
		if not new_value.is_empty():
			_pulse_control(_status_message_label)
	else:
		_mark_dirty()


func _on_monsters_killed_changed(_old: int, _new: int) -> void:
	_mark_dirty()


## 响应式更新动态统计数据。
## @param _old: 旧数据字典。
## @param _dict: 新数据字典。结构：{ "key": "显示文本" 或 Array[Dictionary] }
func _on_extra_stats_changed(_old: Dictionary, _dict: Dictionary) -> void:
	_mark_dirty()
