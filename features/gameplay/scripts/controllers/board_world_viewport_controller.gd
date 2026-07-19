## BoardWorldViewportController: 管理棋盘世界画布的视口变换与可见区域。
##
## 棋盘规则和方块动画始终使用稳定的局部世界坐标；本控制器只负责缩放、平移、
## 聚焦、视口裁剪和 GF 指针手势适配。HUD 与诊断界面位于该宿主之外，不参与变换。
class_name BoardWorldViewportController
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 信号 ---

## 世界变换或可见区域更新后发出。
signal view_transform_changed(
	zoom: float,
	world_position: Vector2,
	visible_world_rect: Rect2
)


# --- 常量 ---

const _ZOOM_STEP: float = 1.15
const _DEFAULT_MINIMUM_ZOOM: float = 0.02
const _DEFAULT_MAXIMUM_ZOOM: float = 3.0
const _FIT_MARGIN: float = 18.0
const _PAN_EDGE_MARGIN: float = 36.0
const _TOUCH_INPUT_SOURCE_ID: StringName = &"gameplay.touch_swipe"
const _TOUCH_ACTION_HOLD_SECONDS: float = 0.08
const _NO_TOUCH_POINTER: int = -1
const _KEYBOARD_PAN_STEP: float = 52.0
const _VIEW_CONTROLS_DESKTOP_LEFT_OFFSET: float = -226.0
const _VIEW_CONTROLS_COMPACT_LEFT_OFFSET: float = -80.0
const _VIEW_CONTROLS_DESKTOP_BOTTOM_OFFSET: float = 58.0
const _VIEW_CONTROLS_COMPACT_BOTTOM_OFFSET: float = 68.0
const _FIT_BUTTON_DESKTOP_MINIMUM: Vector2 = Vector2(56.0, 34.0)
const _FIT_BUTTON_COMPACT_MINIMUM: Vector2 = Vector2(64.0, 44.0)


# --- 导出变量 ---

## 承载棋盘局部世界的 Node2D，相对当前 Controller。
@export var world_root_path: NodePath = NodePath("../BoardWorld")

## 受视口控制的棋盘表现节点，相对当前 Controller。
@export var game_board_path: NodePath = NodePath("../BoardWorld/GameBoardHost/GameBoard")

## 用于 GF 屏幕/世界坐标换算的棋盘 CanvasItem 宿主。
@export var game_board_canvas_item_path: NodePath = NodePath("../BoardWorld/GameBoardHost")

## 棋盘视图控制条路径。
@export var view_controls_path: NodePath = NodePath("../ViewControls")

## 缩小按钮路径。
@export var zoom_out_button_path: NodePath = NodePath("../ViewControls/Margin/Buttons/ZoomOutButton")

## 聚焦全部棋盘按钮路径。
@export var fit_button_path: NodePath = NodePath("../ViewControls/Margin/Buttons/FitButton")

## 放大按钮路径。
@export var zoom_in_button_path: NodePath = NodePath("../ViewControls/Margin/Buttons/ZoomInButton")

## 当前缩放百分比标签路径。
@export var zoom_label_path: NodePath = NodePath("../ViewControls/Margin/Buttons/ZoomLabel")

## 用户缩放的常规下限；完整聚焦比例更小时仍允许使用完整聚焦比例。
@export_range(0.001, 1.0, 0.001) var minimum_zoom: float = _DEFAULT_MINIMUM_ZOOM

## 用户缩放上限。
@export_range(1.0, 8.0, 0.05) var maximum_zoom: float = _DEFAULT_MAXIMUM_ZOOM

## 单指滑动被识别为棋盘移动所需的最短屏幕距离。
@export_range(8.0, 160.0, 1.0) var swipe_minimum_distance: float = 48.0

## 单指滑动允许的最长持续时间；长按拖动不会误触发棋盘移动。
@export_range(0.1, 2.0, 0.05) var swipe_maximum_duration: float = 0.75

## 主轴长度相对副轴的最小比例；用于拒绝方向含糊的斜向滑动。
@export_range(1.0, 3.0, 0.05) var swipe_axis_dominance_ratio: float = 1.15


# --- 私有变量 ---

var _host_control: Control
var _world_root: Node2D
var _game_board: GameBoardController
var _game_board_canvas_item: CanvasItem
var _view_controls: PanelContainer
var _zoom_out_button: Button
var _fit_button: Button
var _zoom_in_button: Button
var _zoom_label: Label

var _viewport_utility: GFViewportUtility
var _gesture_utility: GFPointerGestureUtility
var _input_mapping: GFInputMappingUtility
var _signal_utility: GFSignalUtility
var _clock_utility: GameClockUtility
var _touch_input_source: GFVirtualInputSource

var _content_rect: Rect2 = Rect2()
var _visible_world_rect: Rect2 = Rect2()
var _fit_insets: Dictionary = {}
var _zoom: float = 1.0
var _follow_fit: bool = true
var _is_initialized: bool = false
var _is_handling_gesture_event: bool = false
var _last_viewport_size: Vector2 = Vector2.ZERO
var _previous_mouse_button_index: MouseButton = MOUSE_BUTTON_LEFT
var _previous_wheel_zoom_factor: float = 1.1
var _touch_sequence_primary_id: int = _NO_TOUCH_POINTER
var _touch_sequence_start: Vector2 = Vector2.ZERO
var _touch_sequence_last: Vector2 = Vector2.ZERO
var _touch_sequence_started_msec: int = 0
var _touch_sequence_cancelled: bool = false
var _touch_action_tokens: Dictionary = {}


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_nodes()
	_resolve_utilities()
	if is_instance_valid(_input_mapping):
		_touch_input_source = _input_mapping.create_virtual_source(_TOUCH_INPUT_SOURCE_ID)
	if not _has_required_dependencies():
		return

	_previous_mouse_button_index = _gesture_utility.mouse_button_index
	_previous_wheel_zoom_factor = _gesture_utility.mouse_wheel_zoom_factor
	_gesture_utility.mouse_button_index = MOUSE_BUTTON_MIDDLE
	_gesture_utility.mouse_wheel_zoom_factor = _ZOOM_STEP
	_bind_runtime_signals()
	call_deferred(&"_initialize_view")


func _exit_tree() -> void:
	if is_instance_valid(_touch_input_source):
		_touch_input_source.clear_all()
	_touch_input_source = null
	_touch_action_tokens.clear()
	_reset_touch_sequence()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	if is_instance_valid(_gesture_utility):
		_gesture_utility.mouse_button_index = _previous_mouse_button_index
		_gesture_utility.mouse_wheel_zoom_factor = _previous_wheel_zoom_factor
		_gesture_utility.reset_gesture()
	super._exit_tree()


func _process(_delta: float) -> void:
	if not _is_initialized or not is_instance_valid(_input_mapping):
		return
	if _input_mapping.consume_action(GameplayInputActions.VIEW_FIT):
		fit_to_content()
		return
	if _input_mapping.consume_action(GameplayInputActions.VIEW_ZOOM_IN):
		zoom_in()
		return
	if _input_mapping.consume_action(GameplayInputActions.VIEW_ZOOM_OUT):
		zoom_out()
		return

	var pan_delta: Vector2 = Vector2.ZERO
	if _input_mapping.consume_action(GameplayInputActions.VIEW_PAN_UP):
		pan_delta.y = _KEYBOARD_PAN_STEP
	elif _input_mapping.consume_action(GameplayInputActions.VIEW_PAN_DOWN):
		pan_delta.y = -_KEYBOARD_PAN_STEP
	elif _input_mapping.consume_action(GameplayInputActions.VIEW_PAN_LEFT):
		pan_delta.x = _KEYBOARD_PAN_STEP
	elif _input_mapping.consume_action(GameplayInputActions.VIEW_PAN_RIGHT):
		pan_delta.x = -_KEYBOARD_PAN_STEP
	if pan_delta != Vector2.ZERO:
		_follow_fit = false
		_set_view_transform(_zoom, _world_root.position + pan_delta)


# --- 公共方法 ---

## 将完整棋盘聚焦到当前视口，并恢复自动跟随完整聚焦。
func fit_to_content() -> void:
	if not _has_valid_geometry():
		return
	var fit_viewport_rect: Rect2 = _get_fit_viewport_rect()
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		fit_viewport_rect.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var centered_position: Vector2 = fit_viewport_rect.position + CanvasViewportMath.calculate_centered_world_position(
		fit_viewport_rect.size,
		_content_rect,
		fit_zoom
	)
	_follow_fit = true
	_set_view_transform(fit_zoom, centered_position)


## 以视口中心为锚点放大一级。
func zoom_in() -> void:
	_zoom_at(_get_fit_viewport_rect().get_center(), _zoom * _ZOOM_STEP)


## 以视口中心为锚点缩小一级。
func zoom_out() -> void:
	_zoom_at(_get_fit_viewport_rect().get_center(), _zoom / _ZOOM_STEP)


## 设置完整聚焦时需要避开的屏幕空间 HUD 边距。
## @param insets: 包含 top、left、bottom、right 的局部视口内缩字典。
func set_fit_insets(insets: Dictionary) -> void:
	var normalized: Dictionary = _normalize_fit_insets(insets)
	if _fit_insets == normalized:
		return
	_fit_insets = normalized
	if not _is_initialized or not _has_valid_geometry():
		return
	if _follow_fit:
		fit_to_content()
	else:
		_set_view_transform(_zoom, _world_root.position)


## 在窄竖屏只保留完整聚焦按钮；缩放仍可通过手势、键盘、鼠标滚轮和手柄完成。
## @param compact: 是否启用窄竖屏视图控件布局。
func set_compact_view_controls(compact: bool) -> void:
	if is_instance_valid(_zoom_out_button):
		_zoom_out_button.visible = not compact
	if is_instance_valid(_zoom_label):
		_zoom_label.visible = not compact
	if is_instance_valid(_zoom_in_button):
		_zoom_in_button.visible = not compact
	if is_instance_valid(_fit_button):
		_fit_button.custom_minimum_size = (
			_FIT_BUTTON_COMPACT_MINIMUM if compact else _FIT_BUTTON_DESKTOP_MINIMUM
		)
	if is_instance_valid(_view_controls):
		_view_controls.offset_left = (
			_VIEW_CONTROLS_COMPACT_LEFT_OFFSET
			if compact
			else _VIEW_CONTROLS_DESKTOP_LEFT_OFFSET
		)
		_view_controls.offset_bottom = (
			_VIEW_CONTROLS_COMPACT_BOTTOM_OFFSET
			if compact
			else _VIEW_CONTROLS_DESKTOP_BOTTOM_OFFSET
		)


## 计算应用 HUD 边距后的稳定聚焦矩形。
## @param viewport_size: 当前逻辑视口尺寸。
## @param insets: HUD 在四个方向占用的屏幕边距。
## @return 可用于棋盘完整聚焦的逻辑视口矩形。
static func calculate_fit_viewport_rect(
	viewport_size: Vector2,
	insets: Dictionary
) -> Rect2:
	var safe_size: Vector2 = Vector2(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var left: float = maxf(GFVariantData.get_option_float(insets, "left"), 0.0)
	var right: float = maxf(GFVariantData.get_option_float(insets, "right"), 0.0)
	var top: float = maxf(GFVariantData.get_option_float(insets, "top"), 0.0)
	var bottom: float = maxf(GFVariantData.get_option_float(insets, "bottom"), 0.0)
	var horizontal_total: float = left + right
	var vertical_total: float = top + bottom
	if horizontal_total > safe_size.x - 1.0 and horizontal_total > 0.0:
		var horizontal_scale: float = (safe_size.x - 1.0) / horizontal_total
		left *= horizontal_scale
		right *= horizontal_scale
	if vertical_total > safe_size.y - 1.0 and vertical_total > 0.0:
		var vertical_scale: float = (safe_size.y - 1.0) / vertical_total
		top *= vertical_scale
		bottom *= vertical_scale
	return Rect2(
		Vector2(left, top),
		Vector2(
			maxf(safe_size.x - left - right, 1.0),
			maxf(safe_size.y - top - bottom, 1.0)
		)
	)


## 让棋盘世界按屏幕像素增量平移。
## @param screen_delta: 屏幕空间平移量。
func pan_by(screen_delta: Vector2) -> void:
	if not _has_valid_geometry() or screen_delta.is_zero_approx():
		return
	_follow_fit = false
	_set_view_transform(_zoom, _world_root.position + screen_delta)


## 返回当前棋盘世界缩放。
func get_zoom() -> float:
	return _zoom


## 返回最近同步给棋盘表现层的局部可见矩形。
func get_visible_world_rect() -> Rect2:
	return _visible_world_rect


## 将一次单指轨迹分类为四向棋盘移动；无效轨迹返回 Vector2i.ZERO。
## @param start_position: 轨迹起点的屏幕坐标。
## @param end_position: 轨迹终点的屏幕坐标。
## @param duration_seconds: 轨迹持续秒数。
## @param minimum_distance: 有效滑动的最短屏幕距离。
## @param maximum_duration: 有效滑动允许的最长秒数。
## @param axis_dominance_ratio: 主轴相对副轴的最小长度比例。
## @return 四向单位方向或 Vector2i.ZERO。
static func classify_swipe(
	start_position: Vector2,
	end_position: Vector2,
	duration_seconds: float,
	minimum_distance: float = 48.0,
	maximum_duration: float = 0.75,
	axis_dominance_ratio: float = 1.15
) -> Vector2i:
	if duration_seconds < 0.0 or duration_seconds > maxf(maximum_duration, 0.0):
		return Vector2i.ZERO

	var delta: Vector2 = end_position - start_position
	var absolute_delta: Vector2 = delta.abs()
	var safe_minimum_distance: float = maxf(minimum_distance, 0.0)
	var safe_dominance_ratio: float = maxf(axis_dominance_ratio, 1.0)
	if delta.length() < safe_minimum_distance:
		return Vector2i.ZERO

	if (
		absolute_delta.x >= safe_minimum_distance
		and absolute_delta.x >= absolute_delta.y * safe_dominance_ratio
	):
		return Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
	if (
		absolute_delta.y >= safe_minimum_distance
		and absolute_delta.y >= absolute_delta.x * safe_dominance_ratio
	):
		return Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP
	return Vector2i.ZERO


# --- 私有/辅助方法 ---

func _resolve_nodes() -> void:
	_host_control = _get_host_control()
	_world_root = _get_node_2d(world_root_path)
	_game_board = _get_game_board(game_board_path)
	_game_board_canvas_item = _get_canvas_item(game_board_canvas_item_path)
	_view_controls = _get_panel_container(view_controls_path)
	_zoom_out_button = _get_button(zoom_out_button_path)
	_fit_button = _get_button(fit_button_path)
	_zoom_in_button = _get_button(zoom_in_button_path)
	_zoom_label = _get_label(zoom_label_path)


func _resolve_utilities() -> void:
	_viewport_utility = _get_viewport_utility()
	_gesture_utility = _get_gesture_utility()
	_input_mapping = _get_input_mapping_utility()
	_signal_utility = _get_signal_utility()
	_clock_utility = _get_clock_utility()


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_host_control):
		var _host_appended: bool = missing.append("Control host")
	if not is_instance_valid(_world_root):
		var _world_appended: bool = missing.append("BoardWorld")
	if not is_instance_valid(_game_board):
		var _board_appended: bool = missing.append("GameBoardController")
	if not is_instance_valid(_game_board_canvas_item):
		var _canvas_item_appended: bool = missing.append("GameBoard CanvasItem")
	if not is_instance_valid(_viewport_utility):
		var _viewport_appended: bool = missing.append("GFViewportUtility")
	if not is_instance_valid(_gesture_utility):
		var _gesture_appended: bool = missing.append("GFPointerGestureUtility")
	if not is_instance_valid(_input_mapping):
		var _input_appended: bool = missing.append("GFInputMappingUtility")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
	if not is_instance_valid(_clock_utility):
		var _clock_appended: bool = missing.append("GameClockUtility")
	if missing.is_empty():
		return true
	push_error("[BoardWorldViewportController] 缺少必需依赖：%s。" % ", ".join(missing))
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
	var _geometry_connection: GFSignalConnection = _signal_utility.connect_signal(
		_game_board.board_geometry_changed,
		_on_board_geometry_changed,
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
	_content_rect = _game_board.get_board_world_rect()
	_is_initialized = true
	fit_to_content()


func _has_valid_geometry() -> bool:
	return (
		is_instance_valid(_host_control)
		and is_instance_valid(_world_root)
		and is_instance_valid(_game_board)
		and _host_control.size.x > 0.0
		and _host_control.size.y > 0.0
		and _content_rect.size.x > 0.0
		and _content_rect.size.y > 0.0
	)


func _zoom_at(anchor: Vector2, requested_zoom: float) -> void:
	if not _has_valid_geometry():
		return
	var fit_viewport_rect: Rect2 = _get_fit_viewport_rect()
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		fit_viewport_rect.size,
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
	var fit_viewport_rect: Rect2 = _get_fit_viewport_rect()
	_world_root.position = fit_viewport_rect.position + CanvasViewportMath.calculate_clamped_world_position(
		fit_viewport_rect.size,
		_content_rect,
		_zoom,
		desired_position - fit_viewport_rect.position,
		_PAN_EDGE_MARGIN
	)
	_update_zoom_label()
	_sync_visible_world_rect()


func _sync_visible_world_rect() -> void:
	if not _has_valid_geometry():
		return
	var viewport_rect: Rect2 = _host_control.get_global_rect()
	var first_corner: Vector2 = _viewport_utility.screen_to_world_2d(
		_game_board_canvas_item,
		viewport_rect.position
	)
	var second_corner: Vector2 = _viewport_utility.screen_to_world_2d(
		_game_board_canvas_item,
		viewport_rect.position + viewport_rect.size
	)
	var minimum: Vector2 = Vector2(
		minf(first_corner.x, second_corner.x),
		minf(first_corner.y, second_corner.y)
	)
	var maximum: Vector2 = Vector2(
		maxf(first_corner.x, second_corner.x),
		maxf(first_corner.y, second_corner.y)
	)
	_visible_world_rect = Rect2(minimum, maximum - minimum)
	_game_board.set_visible_world_rect(_visible_world_rect, _zoom)
	view_transform_changed.emit(
		_zoom,
		_world_root.position,
		_visible_world_rect
	)


func _update_zoom_label() -> void:
	if is_instance_valid(_zoom_label):
		_zoom_label.text = "%d%%" % roundi(_zoom * 100.0)


func _get_fit_viewport_rect() -> Rect2:
	if not is_instance_valid(_host_control):
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return calculate_fit_viewport_rect(_host_control.size, _fit_insets)


func _normalize_fit_insets(insets: Dictionary) -> Dictionary:
	return {
		"top": maxf(GFVariantData.get_option_float(insets, "top"), 0.0),
		"left": maxf(GFVariantData.get_option_float(insets, "left"), 0.0),
		"bottom": maxf(GFVariantData.get_option_float(insets, "bottom"), 0.0),
		"right": maxf(GFVariantData.get_option_float(insets, "right"), 0.0),
	}


func _should_handle_gesture_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return true
	if event is InputEventMagnifyGesture or event is InputEventPanGesture:
		return true
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		return (
			mouse_button.button_index == MOUSE_BUTTON_MIDDLE
			or mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP
			or mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
	if event is InputEventMouseMotion:
		return _gesture_utility.get_active_pointer_count() > 0
	return false


func _get_host_control() -> Control:
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


func _get_game_board(path: NodePath) -> GameBoardController:
	var node_value: Node = get_node_or_null(path)
	if node_value is GameBoardController:
		var board: GameBoardController = node_value
		return board
	return null


func _get_canvas_item(path: NodePath) -> CanvasItem:
	var node_value: Node = get_node_or_null(path)
	if node_value is CanvasItem:
		var canvas_item: CanvasItem = node_value
		return canvas_item
	return null


func _get_button(path: NodePath) -> Button:
	var node_value: Node = get_node_or_null(path)
	if node_value is Button:
		var button: Button = node_value
		return button
	return null


func _get_panel_container(path: NodePath) -> PanelContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is PanelContainer:
		var panel: PanelContainer = node_value
		return panel
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


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility, true)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility, true)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility, true)
	if utility_value is GameClockUtility:
		var clock_utility: GameClockUtility = utility_value
		return clock_utility
	return null


func _prepare_touch_action(event: InputEvent) -> StringName:
	var pointer_count_before: int = _gesture_utility.get_active_pointer_count()
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if pointer_count_before == 0 and _touch_sequence_primary_id == _NO_TOUCH_POINTER:
				_touch_sequence_primary_id = touch.index
				_touch_sequence_start = touch.position
				_touch_sequence_last = touch.position
				_touch_sequence_started_msec = _clock_utility.get_tick_msec()
				_touch_sequence_cancelled = false
			else:
				_touch_sequence_cancelled = true
			return &""

		if touch.index == _touch_sequence_primary_id:
			_touch_sequence_last = touch.position
			if pointer_count_before == 1 and not _touch_sequence_cancelled:
				var duration_seconds: float = maxf(
					float(_clock_utility.get_tick_msec() - _touch_sequence_started_msec) / 1000.0,
					0.0
				)
				var direction: Vector2i = classify_swipe(
					_touch_sequence_start,
					_touch_sequence_last,
					duration_seconds,
					swipe_minimum_distance,
					swipe_maximum_duration,
					swipe_axis_dominance_ratio
				)
				return GameplayInputActions.action_for_direction(direction)
		_touch_sequence_cancelled = true
		return &""

	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_sequence_primary_id:
			_touch_sequence_last = drag.position
		if pointer_count_before >= 2:
			_touch_sequence_cancelled = true
	return &""


func _finish_touch_event(event: InputEvent) -> void:
	if not event is InputEventScreenTouch:
		return
	var touch: InputEventScreenTouch = event
	if not touch.pressed and _gesture_utility.get_active_pointer_count() == 0:
		_reset_touch_sequence()


func _reset_touch_sequence() -> void:
	_touch_sequence_primary_id = _NO_TOUCH_POINTER
	_touch_sequence_start = Vector2.ZERO
	_touch_sequence_last = Vector2.ZERO
	_touch_sequence_started_msec = 0
	_touch_sequence_cancelled = false


func _inject_touch_action(action_id: StringName) -> void:
	if action_id == &"" or not is_instance_valid(_touch_input_source):
		return
	var next_token: int = GFVariantData.get_option_int(_touch_action_tokens, action_id) + 1
	_touch_action_tokens[action_id] = next_token
	if not _touch_input_source.press(action_id):
		push_warning("[BoardWorldViewportController] 无法注入触控动作：%s。" % action_id)
		return
	var release_timer: SceneTreeTimer = get_tree().create_timer(
		_TOUCH_ACTION_HOLD_SECONDS,
		true,
		false,
		true
	)
	var _release_connection: GFSignalConnection = _signal_utility.connect_once(
		release_timer.timeout,
		_release_touch_action.bind(action_id, next_token),
		self
	)


func _release_touch_action(action_id: StringName, token: int) -> void:
	if GFVariantData.get_option_int(_touch_action_tokens, action_id) != token:
		return
	if is_instance_valid(_touch_input_source):
		var _released: bool = _touch_input_source.release(action_id)
	var _erased_token: bool = _touch_action_tokens.erase(action_id)


# --- 信号处理函数 ---

func _on_host_resized() -> void:
	if not _is_initialized or not _has_valid_geometry():
		return
	var previous_size: Vector2 = _last_viewport_size
	_last_viewport_size = _host_control.size
	if _follow_fit or previous_size.x <= 0.0 or previous_size.y <= 0.0:
		fit_to_content()
		return
	var previous_fit_rect: Rect2 = calculate_fit_viewport_rect(previous_size, _fit_insets)
	var current_fit_rect: Rect2 = _get_fit_viewport_rect()
	var previous_center: Vector2 = previous_fit_rect.get_center()
	var world_center: Vector2 = (
		(previous_center - _world_root.position)
		/ maxf(_zoom, 0.0001)
	)
	var desired_position: Vector2 = current_fit_rect.get_center() - world_center * _zoom
	_set_view_transform(_zoom, desired_position)


func _on_board_geometry_changed(board_rect: Rect2) -> void:
	_content_rect = board_rect
	if not _is_initialized:
		return
	if _follow_fit:
		fit_to_content()
	else:
		_set_view_transform(_zoom, _world_root.position)


func _on_gui_input(event: InputEvent) -> void:
	if not _should_handle_gesture_event(event):
		return
	var pending_touch_action: StringName = &""
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		pending_touch_action = _prepare_touch_action(event)
	_is_handling_gesture_event = true
	var handled: bool = _gesture_utility.handle_input_event(event)
	_is_handling_gesture_event = false
	_finish_touch_event(event)
	if handled:
		_host_control.accept_event()
	if pending_touch_action != &"":
		_inject_touch_action(pending_touch_action)


func _on_gesture_updated(snapshot: Dictionary, event: InputEvent) -> void:
	if not _is_handling_gesture_event or not _has_valid_geometry():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var pointer_count: int = GFVariantData.get_option_int(snapshot, &"pointer_count")
		if pointer_count < 2:
			return
		_touch_sequence_cancelled = true
	var center_screen: Vector2 = GFVariantData.get_option_vector2(
		snapshot,
		&"center",
		_host_control.get_global_rect().get_center()
	)
	var anchor: Vector2 = _viewport_utility.screen_to_world_2d(
		_host_control,
		center_screen
	)
	var scale_factor: float = GFVariantData.get_option_float(snapshot, &"scale", 1.0)
	var pan_delta: Vector2 = GFVariantData.get_option_vector2(
		snapshot,
		&"pan_delta",
		Vector2.ZERO
	)
	var requested_zoom: float = _zoom * maxf(scale_factor, 0.0001)
	var fit_viewport_rect: Rect2 = _get_fit_viewport_rect()
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		fit_viewport_rect.size,
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
