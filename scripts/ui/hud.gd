# scripts/ui/hud.gd

## HUD: 游戏界面的平视显示器（Heads-Up Display）。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键（key）动态创建或复用标签，实现对不同游戏模式的自适应。
extends VBoxContainer

# --- 节点引用 ---

## 对动态生成统计信息标签的容器节点的引用。
@onready var stats_container: VBoxContainer = $StatsContainer

# --- 内部状态 ---

# 一个字典，用于缓存已创建的标签节点，以避免每帧重复创建。
# 结构: { "data_key": LabelNode }
var _stat_labels: Dictionary = {}


# --- 公共接口 ---

## 统一更新所有UI显示。
## 从外部接收一个包含所有需要显示数据的字典，并动态更新UI。
func update_display(display_data: Dictionary) -> void:
	# 步骤1: 遍历当前所有缓存的标签，如果其key不在新的数据中，则隐藏它。
	for key in _stat_labels:
		if not display_data.has(key):
			_stat_labels[key].visible = false

	# 步骤2: 遍历传入的新数据，更新或创建对应的标签。
	for key in display_data:
		var text_to_display = display_data[key]
		
		# 如果文本为空，则确保对应的标签是隐藏的。
		if text_to_display == "":
			if _stat_labels.has(key):
				_stat_labels[key].visible = false
			continue

		var label_node: Label
		# 如果这个key的标签还未被创建...
		if not _stat_labels.has(key):
			label_node = Label.new() # 创建一个新的Label
			label_node.autowrap_mode = TextServer.AUTOWRAP_WORD
			stats_container.add_child(label_node) # 将其添加到容器中
			_stat_labels[key] = label_node # 缓存起来以便复用
		else:
			label_node = _stat_labels[key] # 从缓存中获取

		# 更新标签的文本内容并确保其可见。
		label_node.text = str(text_to_display)
		label_node.visible = true
