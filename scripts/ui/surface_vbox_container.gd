## SurfaceVBoxContainer: 为三栏 UI 的信息列绘制柔和的纸感背板。
##
## 它保持 VBoxContainer 的布局行为，只在控件背后绘制低权重表面，
## 用于把文字从肌理背景中托起来，不额外改变节点层级。
class_name SurfaceVboxContainer
extends VBoxContainer


# --- 导出变量 ---

@export var surface_color: Color = Color(0.055, 0.075, 0.12, 0.30)
@export var border_color: Color = Color(0.95, 0.88, 0.72, 0.10)
@export_range(0, 24, 1) var corner_radius: int = 8
@export var outward_padding: Vector2 = Vector2(18.0, 14.0)


# --- 私有变量 ---

var _surface_style: StyleBoxFlat = StyleBoxFlat.new()


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_surface_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	_sync_surface_style()
	var content_rect: Rect2 = _get_visible_content_rect()
	if not content_rect.has_area():
		return

	var padded_rect: Rect2 = content_rect.grow_individual(
		outward_padding.x,
		outward_padding.y,
		outward_padding.x,
		outward_padding.y
	)
	draw_style_box(_surface_style, padded_rect)


# --- 私有/辅助方法 ---

func _sync_surface_style() -> void:
	_surface_style.bg_color = surface_color
	_surface_style.border_color = border_color
	_surface_style.set_border_width_all(1)
	_surface_style.set_corner_radius_all(corner_radius)
	_surface_style.shadow_color = Color.TRANSPARENT
	_surface_style.shadow_size = 0
	_surface_style.shadow_offset = Vector2.ZERO


func _get_visible_content_rect() -> Rect2:
	var result: Rect2 = Rect2()
	var has_visible_content: bool = false
	for child: Node in get_children():
		if not child is Control:
			continue
		var child_control: Control = child as Control
		if not child_control.visible:
			continue
		var child_rect: Rect2 = Rect2(child_control.position, child_control.size)
		if not has_visible_content:
			result = child_rect
			has_visible_content = true
		else:
			result = result.merge(child_rect)

	return result if has_visible_content else Rect2()
