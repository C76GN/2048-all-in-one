## BaseListMenuItem: 列表项组件的抽象基类。
##
## 封装了列表项的通焦点、点击以及选中高亮的通用逻辑。
## 继承类应重写 `setup()` 和 `_update_display()` 方法。
class_name BaseListMenuItem
extends Button


# --- 信号 ---

## 当此列表项获得焦点时发出，用于触发预览或其它联动。
## @param data: 关联的数据资源。
signal item_focused(data: Resource)

## 当此列表项被按下（选中确认）时发出。
## @param data: 关联的数据资源。
signal item_selected(data: Resource)


# --- 常量 ---

const _SELECTED_SURFACE_COLOR: Color = Color(0.62, 0.18, 0.25, 0.36)
const _SELECTED_BORDER_COLOR: Color = Color(0.93, 0.80, 0.54, 0.58)


# --- 私有变量 ---

var _item_data: Resource
var _is_selected_manually: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _selection_highlight: Control = $SelectionHighlight


# --- Godot 生命周期方法 ---

func _ready() -> void:
	toggle_mode = true
	_apply_selection_highlight_style()
	var _connect_result_42: int = pressed.connect(_on_pressed)
	var _connect_result_43: int = focus_entered.connect(_on_focus_entered)


# --- 公共方法 ---

## 设置此列表项关联的数据并刷新显示。
## @param new_data: 关联的数据资源。
func setup_item(new_data: Resource) -> void:
	_item_data = new_data
	button_pressed = false
	set_selected(false)
	_update_display()


## 设置显式的选中状态（通过 SelectionHighlight 节点表示）。
## @param is_selected: true 表示设为选中高亮。
func set_selected(is_selected: bool) -> void:
	_is_selected_manually = is_selected
	if _selection_highlight:
		_selection_highlight.visible = is_selected


## 获取关联的数据。
## @return: 关联的 Resource 资源。
func get_data() -> Resource:
	return _item_data


## GFObjectPoolUtility 取出列表项时调用，确保复用节点没有残留选中态。
func on_gf_pool_acquire() -> void:
	button_pressed = false
	set_selected(false)


## GFObjectPoolUtility 归还列表项时调用，清理资源引用和视觉状态。
func on_gf_pool_release() -> void:
	_item_data = null
	button_pressed = false
	set_selected(false)


# --- 虚方法 (由子类重写) ---

## [虚方法] 更新 UI 元素的显示。
func _update_display() -> void:
	pass


# --- 私有/辅助方法 ---

func _apply_selection_highlight_style() -> void:
	if not _selection_highlight is Panel:
		return

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = _SELECTED_SURFACE_COLOR
	style.border_color = _SELECTED_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	(_selection_highlight as Panel).add_theme_stylebox_override("panel", style)


# --- 信号处理函数 ---

func _on_pressed() -> void:
	item_selected.emit(_item_data)


func _on_focus_entered() -> void:
	item_focused.emit(_item_data)
