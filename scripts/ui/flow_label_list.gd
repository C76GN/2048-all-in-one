# scripts/ui/flow_label_list.gd

## FlowLabelList: 一个可自动换行的标签列表容器。
##
## 该组件负责接收一个包含文本和颜色信息的数据数组，并动态地创建
## 或复用 Label 节点来显示它们。它会自动处理换行逻辑，以确保
## 文本流在容器边界内能像普通段落一样正确折行，同时避免了因
## 内容更新导致的布局抖动问题。
class_name FlowLabelList
extends Control

# --- 可配置的样式 ---

## 数字标签之间的水平间距。
@export var horizontal_spacing: int = 8
## 自动换行后，行与行之间的垂直间距。
@export var vertical_spacing: int = 4
## 标签的基础字体大小。
@export var base_font_size: int = 16

# --- 内部状态 ---

# 用于复用已创建Label节点的池，避免频繁创建和销毁，提高性能。
var _label_pool: Array[Label] = []
# 缓存当前显示的数据，用于性能优化，避免在数据未变时重绘。
var _current_data: Array = []


## Godot生命周期函数：当节点进入场景树时调用。
func _ready():
	# 当本控件的尺寸发生变化时（例如窗口大小改变），重新计算所有标签的布局。
	resized.connect(_recalculate_layout)


# --- 公共接口 ---

## 更新并显示新的数据。这是该组件的核心公共函数。
## @param data: 一个数组，每个元素都是一个字典，格式为 {"text": String, "color": Color}。
func update_data(data: Array):
	# 性能优化：如果传入的数据与当前数据完全相同，则不执行任何操作。
	if data == _current_data:
		return
	
	_current_data = data
	
	# 步骤1: 确保标签池中有足够数量的Label节点以显示所有新数据。
	while _label_pool.size() < data.size():
		var new_label = Label.new()
		new_label.add_theme_font_size_override("font_size", base_font_size)
		add_child(new_label)
		_label_pool.append(new_label)
		
	# 步骤2: 遍历标签池，为需要显示的标签更新内容，并隐藏多余的标签。
	for i in range(_label_pool.size()):
		var label = _label_pool[i]
		if i < data.size():
			var item = data[i]
			label.text = item["text"]
			label.modulate = item["color"] # 使用 modulate 来改变颜色，性能优于覆盖主题
			label.visible = true
		else:
			label.visible = false # 隐藏未被使用的标签
	
	# 步骤3: 在内容更新后，立即重新计算布局。
	_recalculate_layout()


# --- 内部辅助函数 ---

## 重新计算并应用所有可见标签的位置，实现流式布局和自动换行。
func _recalculate_layout():
	var cursor = Vector2.ZERO # 用于追踪下一个标签应该放置的位置
	var line_height = 0.0 # 当前行的最大高度

	for i in range(_current_data.size()):
		var label = _label_pool[i]
		if not label.visible: continue
		
		var label_size = label.get_minimum_size()
		line_height = max(line_height, label_size.y)
		
		# 检查是否需要换行：如果当前光标位置加上新标签的宽度超过了容器宽度，
		# 并且当前行不为空（cursor.x > 0），则换行。
		if cursor.x + label_size.x > self.size.x and cursor.x > 0:
			cursor.x = 0
			cursor.y += line_height + vertical_spacing
			line_height = label_size.y # 新行的行高从当前这个标签的高度开始重新计算
		
		label.position = cursor
		cursor.x += label_size.x + horizontal_spacing
		
	# 更新整个控件的最小高度，以便其父容器（如VBoxContainer）能正确地为它分配空间。
	custom_minimum_size.y = cursor.y + line_height if not _current_data.is_empty() else 0
