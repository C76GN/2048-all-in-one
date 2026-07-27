## SurfaceVBoxContainer: 为三栏 UI 的信息列绘制印刷纸感背板。
##
## 它保持 VBoxContainer 的布局行为，只在控件背后绘制低权重表面，
## 用于把文字从肌理背景中托起来，不额外改变节点层级。
class_name SurfaceVboxContainer
extends VBoxContainer


# --- 导出变量 ---

@export var surface_color: Color = Color(1.0, 0.972549, 0.9098039, 0.86)
@export var border_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.76)
@export_range(0, 24, 1) var corner_radius: int = 4
@export var outward_padding: Vector2 = Vector2(18.0, 14.0)

@export_group("Raised Print Surface")
@export var raised: bool = true
@export var shadow_color: Color = Color(0.13725491, 0.15294118, 0.16862746, 0.88)
@export var shadow_offset: Vector2 = Vector2(7.0, 7.0)

@export_group("Registration Accents")
@export var show_registration_accents: bool = true
@export var primary_accent_color: Color = Color(0.29411766, 0.7411765, 0.77254903, 1.0)
@export var secondary_accent_color: Color = Color(0.94509804, 0.8392157, 0.5882353, 1.0)
@export_range(2.0, 8.0, 1.0) var accent_height: float = 4.0
@export_range(0.16, 0.56, 0.01) var primary_accent_ratio: float = 0.34


# --- 私有变量 ---

var _surface_style: StyleBoxFlat = StyleBoxFlat.new()
var _shadow_style: StyleBoxFlat = StyleBoxFlat.new()


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_surface_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_SORT_CHILDREN:
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
	if raised:
		draw_style_box(_shadow_style, Rect2(padded_rect.position + shadow_offset, padded_rect.size))
	draw_style_box(_surface_style, padded_rect)
	_draw_registration_accents(padded_rect)


# --- 私有/辅助方法 ---

func _sync_surface_style() -> void:
	_surface_style.bg_color = surface_color
	_surface_style.border_color = border_color
	_surface_style.set_border_width_all(2)
	_surface_style.set_corner_radius_all(corner_radius)
	_surface_style.shadow_color = Color.TRANSPARENT
	_surface_style.shadow_size = 0
	_surface_style.shadow_offset = Vector2.ZERO
	_shadow_style.bg_color = shadow_color
	_shadow_style.border_color = Color.TRANSPARENT
	_shadow_style.set_border_width_all(0)
	_shadow_style.set_corner_radius_all(corner_radius)
	_shadow_style.shadow_color = Color.TRANSPARENT
	_shadow_style.shadow_size = 0
	_shadow_style.shadow_offset = Vector2.ZERO


func _draw_registration_accents(surface_rect: Rect2) -> void:
	if not show_registration_accents or accent_height <= 0.0:
		return
	var inset: float = minf(14.0, surface_rect.size.x * 0.08)
	var available_width: float = maxf(surface_rect.size.x - inset * 2.0, 0.0)
	if available_width <= 0.0:
		return
	var primary_width: float = maxf(available_width * primary_accent_ratio, 28.0)
	primary_width = minf(primary_width, available_width)
	var accent_y: float = surface_rect.position.y
	draw_rect(
		Rect2(
			Vector2(surface_rect.position.x + inset, accent_y),
			Vector2(primary_width, accent_height)
		),
		primary_accent_color
	)
	var secondary_width: float = minf(42.0, maxf(available_width - primary_width - 8.0, 0.0))
	if secondary_width <= 0.0:
		return
	draw_rect(
		Rect2(
			Vector2(
				surface_rect.end.x - inset - secondary_width,
				accent_y
			),
			Vector2(secondary_width, accent_height)
		),
		secondary_accent_color
	)


func _get_visible_content_rect() -> Rect2:
	var result: Rect2 = Rect2()
	var has_visible_content: bool = false
	for child: Node in get_children():
		if not child is Control:
			continue
		var child_control: Control = child
		if not child_control.visible:
			continue
		var child_rect: Rect2 = Rect2(child_control.position, child_control.size)
		if not has_visible_content:
			result = child_rect
			has_visible_content = true
		else:
			result = result.merge(child_rect)

	return result if has_visible_content else Rect2()
