## BoardEditorViewportController: 管理编辑画布的缩放、平移与指针仲裁。
##
## 桌面左/右键和移动端单指只产生可取消笔画；中键、滚轮、系统手势与双指
## 交给 GFPointerGestureUtility。第二根手指出现时会取消尚未提交的单指笔画。
class_name BoardEditorViewportController
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 信号 ---

signal view_transform_changed(zoom: float, world_position: Vector2)


# --- 常量 ---

const _ZOOM_STEP: float = 1.15
const _FIT_MARGIN: float = 18.0
const _PAN_EDGE_MARGIN: float = 36.0
const _NO_POINTER: int = -1


# --- 导出变量 ---

@export var world_root_path: NodePath = NodePath("../CanvasWorld")
@export var canvas_path: NodePath = NodePath("../CanvasWorld/BoardEditorCanvas")
@export var zoom_out_button_path: NodePath = NodePath(
	"../ViewControls/Margin/Buttons/ZoomOutButton"
)
@export var fit_button_path: NodePath = NodePath("../ViewControls/Margin/Buttons/FitButton")
@export var zoom_in_button_path: NodePath = NodePath(
	"../ViewControls/Margin/Buttons/ZoomInButton"
)
@export var zoom_label_path: NodePath = NodePath("../ViewControls/Margin/Buttons/ZoomLabel")
@export_range(0.001, 1.0, 0.001) var minimum_zoom: float = 0.04
@export_range(1.0, 8.0, 0.05) var maximum_zoom: float = 4.0


# --- 私有变量 ---

var _host_control: Control
var _world_root: Node2D
var _canvas: BoardEditorCanvas
var _zoom_out_button: Button
var _fit_button: Button
var _zoom_in_button: Button
var _zoom_label: Label
var _viewport_utility: GFViewportUtility
var _gesture_utility: GFPointerGestureUtility
var _signal_utility: GFSignalUtility
var _content_rect: Rect2 = Rect2()
var _zoom: float = 1.0
var _follow_fit: bool = true
var _is_initialized: bool = false
var _is_handling_gesture_event: bool = false
var _last_viewport_size: Vector2 = Vector2.ZERO
var _previous_mouse_button_index: MouseButton = MOUSE_BUTTON_LEFT
var _previous_wheel_zoom_factor: float = 1.1
var _mouse_stroke_button: MouseButton = MOUSE_BUTTON_NONE
var _touch_primary_id: int = _NO_POINTER
var _touch_sequence_blocked: bool = false


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_nodes()
	_resolve_utilities()
	if not _has_required_dependencies():
		return

	_previous_mouse_button_index = _gesture_utility.mouse_button_index
	_previous_wheel_zoom_factor = _gesture_utility.mouse_wheel_zoom_factor
	_gesture_utility.mouse_button_index = MOUSE_BUTTON_MIDDLE
	_gesture_utility.mouse_wheel_zoom_factor = _ZOOM_STEP
	_bind_runtime_signals()
	call_deferred(&"_initialize_view")


func _exit_tree() -> void:
	if is_instance_valid(_canvas):
		_canvas.cancel_stroke()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	if is_instance_valid(_gesture_utility):
		_gesture_utility.mouse_button_index = _previous_mouse_button_index
		_gesture_utility.mouse_wheel_zoom_factor = _previous_wheel_zoom_factor
		_gesture_utility.reset_gesture()
	_reset_pointer_state()
	super._exit_tree()


# --- 公共方法 ---

## 将完整编辑画布聚焦到当前视口，并恢复自动跟随适配。
func fit_to_content() -> void:
	if not _has_valid_geometry():
		return
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		_host_control.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var centered_position: Vector2 = CanvasViewportMath.calculate_centered_world_position(
		_host_control.size,
		_content_rect,
		fit_zoom
	)
	_follow_fit = true
	_set_view_transform(fit_zoom, centered_position)


## 以视口中心为锚点放大一级。
func zoom_in() -> void:
	_zoom_at(_host_control.size * 0.5, _zoom * _ZOOM_STEP)


## 以视口中心为锚点缩小一级。
func zoom_out() -> void:
	_zoom_at(_host_control.size * 0.5, _zoom / _ZOOM_STEP)


## 让编辑世界按屏幕像素增量平移。
## @param screen_delta: 屏幕空间平移增量。
func pan_by(screen_delta: Vector2) -> void:
	if not _has_valid_geometry() or screen_delta.is_zero_approx():
		return
	_follow_fit = false
	_set_view_transform(_zoom, _world_root.position + screen_delta)


## 返回当前编辑画布缩放。
func get_zoom() -> float:
	return _zoom


# --- 私有/辅助方法 ---

func _resolve_nodes() -> void:
	_host_control = _get_control_host()
	_world_root = _get_node_2d(world_root_path)
	_canvas = _get_editor_canvas(canvas_path)
	_zoom_out_button = _get_button(zoom_out_button_path)
	_fit_button = _get_button(fit_button_path)
	_zoom_in_button = _get_button(zoom_in_button_path)
	_zoom_label = _get_label(zoom_label_path)


func _resolve_utilities() -> void:
	_viewport_utility = _get_viewport_utility()
	_gesture_utility = _get_gesture_utility()
	_signal_utility = _get_signal_utility()


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_host_control):
		var _host_appended: bool = missing.append("Control host")
	if not is_instance_valid(_world_root):
		var _world_appended: bool = missing.append("CanvasWorld")
	if not is_instance_valid(_canvas):
		var _canvas_appended: bool = missing.append("BoardEditorCanvas")
	if not is_instance_valid(_viewport_utility):
		var _viewport_appended: bool = missing.append("GFViewportUtility")
	if not is_instance_valid(_gesture_utility):
		var _gesture_appended: bool = missing.append("GFPointerGestureUtility")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
	if missing.is_empty():
		return true
	push_error("[BoardEditorViewportController] 缺少必需依赖：%s。" % ", ".join(missing))
	return false


func _bind_runtime_signals() -> void:
	var _resize_connection: GFSignalConnection = _signal_utility.connect_signal(
		_host_control.resized,
		_on_host_resized,
		self
	)
	var _input_connection: GFSignalConnection = _signal_utility.connect_signal(
		_host_control.gui_input,
		_on_gui_input,
		self
	)
	var _gesture_connection: GFSignalConnection = _signal_utility.connect_signal(
		_gesture_utility.gesture_updated,
		_on_gesture_updated,
		self
	)
	var _content_connection: GFSignalConnection = _signal_utility.connect_signal(
		_canvas.content_rect_changed,
		_on_content_rect_changed,
		self
	)
	if is_instance_valid(_zoom_out_button):
		var _zoom_out_connection: GFSignalConnection = _signal_utility.connect_signal(
			_zoom_out_button.pressed,
			zoom_out,
			self
		)
	if is_instance_valid(_fit_button):
		var _fit_connection: GFSignalConnection = _signal_utility.connect_signal(
			_fit_button.pressed,
			fit_to_content,
			self
		)
	if is_instance_valid(_zoom_in_button):
		var _zoom_in_connection: GFSignalConnection = _signal_utility.connect_signal(
			_zoom_in_button.pressed,
			zoom_in,
			self
		)


func _initialize_view() -> void:
	if not is_inside_tree() or not _has_required_dependencies():
		return
	_last_viewport_size = _host_control.size
	_content_rect = _canvas.get_content_rect()
	_is_initialized = true
	fit_to_content()


func _has_valid_geometry() -> bool:
	return (
		is_instance_valid(_host_control)
		and is_instance_valid(_world_root)
		and is_instance_valid(_canvas)
		and _host_control.visible
		and _host_control.size.x > 0.0
		and _host_control.size.y > 0.0
		and _content_rect.size.x > 0.0
		and _content_rect.size.y > 0.0
	)


func _zoom_at(anchor: Vector2, requested_zoom: float) -> void:
	if not _has_valid_geometry():
		return
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		_host_control.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var effective_minimum: float = minf(maxf(minimum_zoom, 0.0001), fit_zoom)
	var next_zoom: float = clampf(requested_zoom, effective_minimum, maximum_zoom)
	if is_equal_approx(next_zoom, _zoom):
		return
	var next_position: Vector2 = CanvasViewportMath.calculate_zoomed_world_position(
		_world_root.position,
		anchor,
		_zoom,
		next_zoom
	)
	_follow_fit = false
	_set_view_transform(next_zoom, next_position)


func _set_view_transform(next_zoom: float, desired_position: Vector2) -> void:
	if not _has_valid_geometry():
		return
	_zoom = maxf(next_zoom, 0.0001)
	_world_root.scale = Vector2.ONE * _zoom
	_world_root.position = CanvasViewportMath.calculate_clamped_world_position(
		_host_control.size,
		_content_rect,
		_zoom,
		desired_position,
		_PAN_EDGE_MARGIN
	)
	_update_zoom_label()
	view_transform_changed.emit(_zoom, _world_root.position)


func _update_zoom_label() -> void:
	if is_instance_valid(_zoom_label):
		_zoom_label.text = "%d%%" % roundi(_zoom * 100.0)


func _handle_mouse_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if (
			mouse_button.button_index == MOUSE_BUTTON_LEFT
			or mouse_button.button_index == MOUSE_BUTTON_RIGHT
		):
			if mouse_button.pressed:
				var draw_active: bool = (
					_canvas.is_brush_active()
					if mouse_button.button_index == MOUSE_BUTTON_LEFT
					else false
				)
				if _canvas.begin_stroke(_host_to_canvas(mouse_button.position), draw_active):
					_mouse_stroke_button = mouse_button.button_index
					_host_control.grab_focus()
					return true
			elif mouse_button.button_index == _mouse_stroke_button:
				_canvas.finish_stroke()
				_mouse_stroke_button = MOUSE_BUTTON_NONE
				return true
			return false
		return _handle_gesture_event(event)

	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event
		if _mouse_stroke_button != MOUSE_BUTTON_NONE and _canvas.is_stroke_active():
			_canvas.append_stroke(_host_to_canvas(mouse_motion.position))
			return true
		if _gesture_utility.get_active_pointer_count() > 0:
			return _handle_gesture_event(event)
	return false


func _handle_touch_event(event: InputEvent) -> bool:
	var pointer_count_before: int = _gesture_utility.get_active_pointer_count()
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if pointer_count_before == 0 and _touch_primary_id == _NO_POINTER:
				_touch_primary_id = touch.index
				_touch_sequence_blocked = false
				var _stroke_started: bool = _canvas.begin_stroke(
					_host_to_canvas(touch.position),
					_canvas.is_brush_active()
				)
			else:
				_touch_sequence_blocked = true
				_canvas.cancel_stroke()
		elif touch.index == _touch_primary_id:
			if _touch_sequence_blocked:
				_canvas.cancel_stroke()
			else:
				_canvas.finish_stroke()

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if pointer_count_before >= 2:
			_touch_sequence_blocked = true
			_canvas.cancel_stroke()
		elif drag.index == _touch_primary_id and not _touch_sequence_blocked:
			_canvas.append_stroke(_host_to_canvas(drag.position))

	var handled: bool = _handle_gesture_event(event)
	if event is InputEventScreenTouch:
		var completed_touch: InputEventScreenTouch = event
		if not completed_touch.pressed and _gesture_utility.get_active_pointer_count() == 0:
			_touch_primary_id = _NO_POINTER
			_touch_sequence_blocked = false
	return handled or _canvas.is_stroke_active() or pointer_count_before > 0


func _handle_gesture_event(event: InputEvent) -> bool:
	_is_handling_gesture_event = true
	var handled: bool = _gesture_utility.handle_input_event(event)
	_is_handling_gesture_event = false
	return handled


func _host_to_canvas(host_position: Vector2) -> Vector2:
	var screen_position: Vector2 = _viewport_utility.world_to_screen_2d(
		_host_control,
		host_position
	)
	return _viewport_utility.screen_to_world_2d(_canvas, screen_position)


func _reset_pointer_state() -> void:
	_mouse_stroke_button = MOUSE_BUTTON_NONE
	_touch_primary_id = _NO_POINTER
	_touch_sequence_blocked = false


func _get_control_host() -> Control:
	var host_value: Node = get_host_as(Control)
	if host_value is Control:
		var host_control: Control = host_value
		return host_control
	return null


func _get_node_2d(path: NodePath) -> Node2D:
	var node_value: Node = get_node_or_null(path)
	if node_value is Node2D:
		var node_2d: Node2D = node_value
		return node_2d
	return null


func _get_editor_canvas(path: NodePath) -> BoardEditorCanvas:
	var node_value: Node = get_node_or_null(path)
	if node_value is BoardEditorCanvas:
		var editor_canvas: BoardEditorCanvas = node_value
		return editor_canvas
	return null


func _get_button(path: NodePath) -> Button:
	var node_value: Node = get_node_or_null(path)
	if node_value is Button:
		var button: Button = node_value
		return button
	return null


func _get_label(path: NodePath) -> Label:
	var node_value: Node = get_node_or_null(path)
	if node_value is Label:
		var label: Label = node_value
		return label
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility, true)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _get_gesture_utility() -> GFPointerGestureUtility:
	var utility_value: Object = get_utility(GFPointerGestureUtility, true)
	if utility_value is GFPointerGestureUtility:
		var gesture_utility: GFPointerGestureUtility = utility_value
		return gesture_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility, true)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


# --- 信号处理函数 ---

func _on_host_resized() -> void:
	if not _is_initialized or not _has_valid_geometry():
		return
	var previous_size: Vector2 = _last_viewport_size
	_last_viewport_size = _host_control.size
	if _follow_fit or previous_size.x <= 0.0 or previous_size.y <= 0.0:
		fit_to_content()
		return
	var previous_center: Vector2 = previous_size * 0.5
	var world_center: Vector2 = (
		(previous_center - _world_root.position)
		/ maxf(_zoom, 0.0001)
	)
	var desired_position: Vector2 = _host_control.size * 0.5 - world_center * _zoom
	_set_view_transform(_zoom, desired_position)


func _on_content_rect_changed(content_rect: Rect2) -> void:
	_content_rect = content_rect
	if not _is_initialized:
		return
	if _follow_fit:
		fit_to_content()
	else:
		_set_view_transform(_zoom, _world_root.position)


func _on_gui_input(event: InputEvent) -> void:
	var handled: bool = false
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		handled = _handle_touch_event(event)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		handled = _handle_mouse_event(event)
	elif event is InputEventMagnifyGesture or event is InputEventPanGesture:
		handled = _handle_gesture_event(event)
	if handled:
		_host_control.accept_event()


func _on_gesture_updated(snapshot: Dictionary, event: InputEvent) -> void:
	if not _is_handling_gesture_event or not _has_valid_geometry():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var pointer_count: int = GFVariantData.get_option_int(snapshot, &"pointer_count")
		if pointer_count < 2:
			return
		_touch_sequence_blocked = true
		_canvas.cancel_stroke()
	var anchor: Vector2 = GFVariantData.get_option_vector2(
		snapshot,
		&"center",
		_host_control.size * 0.5
	)
	var scale_factor: float = GFVariantData.get_option_float(snapshot, &"scale", 1.0)
	var pan_delta: Vector2 = GFVariantData.get_option_vector2(
		snapshot,
		&"pan_delta",
		Vector2.ZERO
	)
	var requested_zoom: float = _zoom * maxf(scale_factor, 0.0001)
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		_host_control.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var effective_minimum: float = minf(maxf(minimum_zoom, 0.0001), fit_zoom)
	var next_zoom: float = clampf(requested_zoom, effective_minimum, maximum_zoom)
	var next_position: Vector2 = CanvasViewportMath.calculate_zoomed_world_position(
		_world_root.position,
		anchor,
		_zoom,
		next_zoom
	) + pan_delta
	if is_equal_approx(next_zoom, _zoom) and pan_delta.is_zero_approx():
		return
	_follow_fit = false
	_set_view_transform(next_zoom, next_position)
