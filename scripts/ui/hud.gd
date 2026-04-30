## HUD: 游戏界面的平视显示器（Heads-Up Display）。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键（key）动态创建或复用标签，实现对不同游戏模式的自适应。
class_name HUD
extends GFController


# --- 常量 ---

## 动态流程标签列表场景。
const FLOW_LABEL_LIST_SCENE: PackedScene = preload("res://scenes/ui/flow_label_list.tscn")
const _GET_HUD_STATS_QUERY_SCRIPT = preload("res://scripts/queries/get_hud_stats_query.gd")


# --- 私有变量 ---

## 一个字典，用于缓存已创建的UI节点，以避免每帧重复创建。
## 结构: { "data_key": ControlNode }
var _stat_labels: Dictionary = {}

var _is_dirty: bool = false
var _game_status_model: GameStatusModel


# --- @onready 变量 (节点引用) ---

@onready var _stats_container: VBoxContainer = $StatsContainer
@onready var _title_label: Label = $TitleLabel

var _score_value_label: Label
var _move_count_value_label: Label
var _status_message_label: RichTextLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = get_model(GameStatusModel) as GameStatusModel
	
	_score_value_label = get_node_or_null("%ScoreValueLabel") as Label
	_move_count_value_label = get_node_or_null("%MoveCountValueLabel") as Label
	var status_msg_node = get_node_or_null("%StatusMessageLabel")
	if status_msg_node is RichTextLabel:
		_status_message_label = status_msg_node
	
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


# --- 公共方法 ---

func _on_high_score_changed(_old: int, _new_value: int) -> void:
	_mark_dirty()


func _on_highest_tile_changed(_old: int, _new_value: int) -> void:
	_mark_dirty()


func _on_status_message_changed(_old: String, new_value: String) -> void:
	if is_instance_valid(_status_message_label):
		_status_message_label.text = new_value
		_status_message_label.visible = not new_value.is_empty()
	else:
		_mark_dirty()


## 全局刷新 UI 显示。
func _refresh_all() -> void:
	if not is_instance_valid(_game_status_model):
		return

	# 1. 更新显式标签
	if is_instance_valid(_score_value_label):
		_score_value_label.text = str(_game_status_model.score.get_value())
	
	if is_instance_valid(_move_count_value_label):
		_move_count_value_label.text = str(_game_status_model.move_count.get_value())
	
	if is_instance_valid(_status_message_label):
		var msg: String = _game_status_model.status_message.get_value()
		_status_message_label.text = msg
		_status_message_label.visible = not msg.is_empty()

	var local_dict: Dictionary = {}
	
	if not is_instance_valid(_score_value_label):
		var score_text := tr("LABEL_SCORE")
		if score_text == "LABEL_SCORE" or not ":" in score_text:
			score_text = tr("SCORE_LABEL")
		local_dict[&"score"] = (
			score_text % _game_status_model.score.get_value()
			if "%" in score_text
			else score_text + " [b]" + str(_game_status_model.score.get_value()) + "[/b]"
		)
	
	if not is_instance_valid(_move_count_value_label):
		var move_text := tr("LABEL_MOVES")
		if move_text == "LABEL_MOVES" or not ":" in move_text:
			move_text = tr("MOVE_COUNT_LABEL")
		local_dict[&"move_count"] = (
			move_text % _game_status_model.move_count.get_value()
			if "%" in move_text
			else move_text + " [b]" + str(_game_status_model.move_count.get_value()) + "[/b]"
		)

	local_dict[&"high_score"] = tr("HIGH_SCORE_LABEL") % _game_status_model.high_score.get_value()
	local_dict[&"highest_tile"] = tr("HIGHEST_TILE_LABEL") % _game_status_model.highest_tile.get_value()
	
	if not is_instance_valid(_status_message_label):
		var msg: String = _game_status_model.status_message.get_value()
		if not msg.is_empty():
			local_dict[&"status_message"] = "[color=yellow]" + msg + "[/color]"

	var query_result: Variant = send_query(_GET_HUD_STATS_QUERY_SCRIPT.new())
	if query_result is Dictionary:
		local_dict.merge(query_result)

	_update_dynamic_list(local_dict)


func _on_monsters_killed_changed(_old: int, _new: int) -> void:
	_mark_dirty()


## 响应式更新动态统计数据。
## @param _old: 旧数据字典。
## @param dict: 新数据字典。结构: { "key": "Display String" 或 Array[Dict] }
func _on_extra_stats_changed(_old: Dictionary, _dict: Dictionary) -> void:
	_mark_dirty()


func _update_dynamic_list(dict: Dictionary) -> void:
	# 1. 隐藏不再存在的 key
	for key in _stat_labels:
		if not dict.has(key):
			_stat_labels[key].visible = false

	var keys_in_order: Array = dict.keys()

	# 2. 动态创建或更新 UI 节点
	for key in keys_in_order:
		var data_to_display: Variant = dict[key]

		if (
			data_to_display == null
			or (data_to_display is String and data_to_display.is_empty())
			or (data_to_display is Array and data_to_display.is_empty())
		):
			if _stat_labels.has(key):
				_stat_labels[key].visible = false
			continue

		var ui_node: Control
		var needs_recreation: bool = false
		
		if _stat_labels.has(key):
			var existing_node: Control = _stat_labels[key]
			if (
				(data_to_display is Array and not existing_node is FlowLabelList)
				or (not data_to_display is Array and existing_node is FlowLabelList)
			):
				existing_node.queue_free()
				needs_recreation = true
		else:
			needs_recreation = true

		if needs_recreation:
			if data_to_display is Array:
				ui_node = FLOW_LABEL_LIST_SCENE.instantiate()
			else:
				var new_label := RichTextLabel.new()
				new_label.bbcode_enabled = true
				new_label.fit_content = true
				new_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				ui_node = new_label

			_stats_container.add_child(ui_node)
			_stat_labels[key] = ui_node
		else:
			ui_node = _stat_labels[key]

		if ui_node is FlowLabelList:
			(ui_node as FlowLabelList).update_data(data_to_display)
		elif ui_node is RichTextLabel:
			(ui_node as RichTextLabel).text = str(data_to_display)

		ui_node.visible = true


# --- 私有/辅助方法 ---

func _on_hud_update_requested(_p: Variant = null) -> void:
	_mark_dirty()


func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_GAME_STATUS")


func _on_score_changed(_old_value: int, _new_value: int) -> void:
	_mark_dirty()


func _on_move_count_changed(_old_value: int, _new_value: int) -> void:
	_mark_dirty()

func _mark_dirty() -> void:
	if not _is_dirty:
		_is_dirty = true
		call_deferred("_deferred_refresh")

func _deferred_refresh() -> void:
	if _is_dirty:
		_is_dirty = false
		_refresh_all()
