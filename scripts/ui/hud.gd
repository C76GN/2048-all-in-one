# scripts/ui/hud.gd

## HUD: 游戏界面的平视显示器（Heads-Up Display）。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键（key）动态创建或复用标签，实现对不同游戏模式的自适应。
extends VBoxContainer

const FlowLabelListScene = preload("res://scenes/ui/flow_label_list.tscn")

# --- 节点引用 ---

## 对动态生成统计信息标签的容器节点的引用。
@onready var stats_container: VBoxContainer = $StatsContainer

# --- 内部状态 ---

# 一个字典，用于缓存已创建的UI节点，以避免每帧重复创建。
# 结构: { "data_key": ControlNode }
var _stat_labels: Dictionary = {}

## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 订阅事件总线上的HUD更新请求。
	EventBus.hud_update_requested.connect(update_display)

# --- 公共接口 ---

## 统一更新所有UI显示。
## 从外部接收一个包含所有需要显示数据的字典，并动态更新UI。
func update_display(display_data: Dictionary) -> void:
	# 定义哪些key需要使用FlowLabelList组件来显示
	var flow_label_keys = ["fibonacci_sequence", "fib_sequence_display", "luc_sequence_display"]
	
	# 步骤1: 遍历当前所有缓存的UI节点，如果其key不在新的数据中，则隐藏它。
	for key in _stat_labels:
		if not display_data.has(key):
			_stat_labels[key].visible = false

	# 步骤2: 遍历传入的新数据，更新或创建对应的UI节点。
	for key in display_data:
		var data_to_display = display_data[key]
		
		# 如果数据为空，则确保对应的UI节点是隐藏的。
		if data_to_display == null or (data_to_display is String and data_to_display.is_empty()):
			if _stat_labels.has(key):
				_stat_labels[key].visible = false
			continue

		var ui_node: Control
		
		if not _stat_labels.has(key):
			# 如果是数字序列，实例化 FlowLabelList。
			if key in flow_label_keys:
				ui_node = FlowLabelListScene.instantiate()
			# 其他的，如分数、合成提示等，使用 RichTextLabel 以支持BBCode。
			else:
				var new_label = RichTextLabel.new()
				new_label.bbcode_enabled = true
				new_label.fit_content = true
				# 对于普通文本，允许其在单词边界自动换行。
				new_label.autowrap_mode = TextServer.AUTOWRAP_WORD
				ui_node = new_label
				
			stats_container.add_child(ui_node)
			_stat_labels[key] = ui_node
		else:
			ui_node = _stat_labels[key]

		# 步骤3: 根据节点类型，使用不同的方式更新内容。
		if ui_node is FlowLabelList:
			# 如果是FlowLabelList，调用它的update_data函数来更新。
			ui_node.update_data(data_to_display)
		elif ui_node is RichTextLabel:
			# 如果是RichTextLabel，直接设置text属性。
			ui_node.text = str(data_to_display)
		
		ui_node.visible = true
