# scripts/ui/hud.gd

## HUD: 游戏界面的平视显示器（Heads-Up Display）。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键（key）动态创建或复用标签，实现对不同游戏模式的自适应。
extends VBoxContainer


# --- 常量 ---

const FLOW_LABEL_LIST_SCENE: PackedScene = preload("res://scenes/ui/flow_label_list.tscn")


# --- 私有变量 ---

## 一个字典，用于缓存已创建的UI节点，以避免每帧重复创建。
## 结构: { "data_key": ControlNode }
var _stat_labels: Dictionary = {}


# --- @onready 变量 (节点引用) ---

@onready var _stats_container: VBoxContainer = $StatsContainer
@onready var _title_label: Label = $TitleLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	EventBus.hud_update_requested.connect(update_display)
	_update_ui_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 公共方法 ---

## 统一更新所有UI显示。
##
## 从外部接收一个包含所有需要显示数据的 HUDDisplayData 对象，并动态更新UI。
## @param display_data: 包含所有要在HUD上显示信息的强类型数据对象。
func update_display(display_data: HUDDisplayData) -> void:
	if not is_instance_valid(display_data):
		return

	var dict: Dictionary = display_data.to_display_dict()

	for key in _stat_labels:
		if not dict.has(key):
			_stat_labels[key].visible = false

	var keys_in_order: Array = dict.keys()
	if dict.has(&"status_message"):
		keys_in_order.erase(&"status_message")
		keys_in_order.insert(0, &"status_message")

	for key in keys_in_order:
		var data_to_display: Variant = dict[key]

		if data_to_display == null or \
		  (data_to_display is String and data_to_display.is_empty()) or \
		  (data_to_display is Array and data_to_display.is_empty()):
			if _stat_labels.has(key):
				_stat_labels[key].visible = false
			continue

		var ui_node: Control

		var needs_recreation: bool = false
		if _stat_labels.has(key):
			var existing_node: Control = _stat_labels[key]
			if (data_to_display is Array and not existing_node is FlowLabelList) or \
			   (not data_to_display is Array and existing_node is FlowLabelList):
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

		if key == &"status_message":
			_stats_container.move_child(ui_node, 0)

		if ui_node is FlowLabelList:
			(ui_node as FlowLabelList).update_data(data_to_display)
		elif ui_node is RichTextLabel:
			(ui_node as RichTextLabel).text = str(data_to_display)

		ui_node.visible = true


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_GAME_STATUS")
