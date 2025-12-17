# scripts/ui/flow_label_list.gd

## FlowLabelList: 一个可自动换行的标签列表容器。
class_name FlowLabelList
extends Control


# --- 导出变量 ---

@export_group("样式配置")
## 数字标签之间的水平间距。
@export var horizontal_spacing: int = 8
## 自动换行后，行与行之间的垂直间距。
@export var vertical_spacing: int = 4
## 标签的基础字体大小。
@export var base_font_size: int = 16

## 用于生成标签的场景文件。
@export var label_scene: PackedScene = preload("res://scenes/components/flow_item_label.tscn")


# --- 私有变量 ---

## 用于复用已创建Label节点的池，避免频繁创建和销毁，提高性能。
var _label_pool: Array[Label] = []
## 缓存当前显示的数据，用于性能优化，避免在数据未变时重绘。
var _current_data: Array = []


# --- Godot 生命周期方法 ---

func _ready() -> void:
	resized.connect(_recalculate_layout)


# --- 公共方法 ---

## 更新并显示新的数据。这是该组件的核心公共函数。
## @param data: 一个数组，每个元素都是一个字典，格式为 {"text": String, "color": Color}。
func update_data(data: Array) -> void:
	if data == _current_data:
		return

	_current_data = data

	# 确保标签池中有足够数量的Label节点
	while _label_pool.size() < data.size():
		var new_label: Label
		if is_instance_valid(label_scene):
			new_label = label_scene.instantiate() as Label
		else:
			new_label = Label.new() # 后备方案

		new_label.add_theme_font_size_override("font_size", base_font_size)
		add_child(new_label)
		_label_pool.append(new_label)

	# 更新标签内容并管理可见性
	for i in range(_label_pool.size()):
		var label: Label = _label_pool[i]
		if i < data.size():
			var item: Dictionary = data[i]
			label.text = item["text"]
			label.modulate = item["color"] # 使用 modulate 改变颜色，性能更佳
			label.visible = true
		else:
			label.visible = false # 隐藏未使用的标签

	_recalculate_layout()


# --- 私有/辅助方法 ---

## 重新计算并应用所有可见标签的位置，实现流式布局和自动换行。
func _recalculate_layout() -> void:
	var cursor := Vector2.ZERO
	var line_height: float = 0.0

	for i in range(_current_data.size()):
		var label: Label = _label_pool[i]
		if not label.visible:
			continue

		var label_size: Vector2 = label.get_minimum_size()
		line_height = max(line_height, label_size.y)

		# 检查是否需要换行
		if cursor.x + label_size.x > self.size.x and cursor.x > 0:
			cursor.x = 0
			cursor.y += line_height + vertical_spacing
			line_height = label_size.y

		label.position = cursor
		cursor.x += label_size.x + horizontal_spacing

	# 更新控件的最小高度，以适应父容器布局
	custom_minimum_size.y = cursor.y + line_height if not _current_data.is_empty() else 0.0
