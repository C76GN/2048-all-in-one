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


# --- 导出变量 ---

## 承载棋盘局部世界的 Node2D，相对当前 Controller。
@export var world_root_path: NodePath = NodePath("../BoardWorld")

## 受视口控制的棋盘表现节点，相对当前 Controller。
@export var game_board_path: NodePath = NodePath("../BoardWorld/GameBoardHost/GameBoard")

## 用于 GF 屏幕/世界坐标换算的棋盘 CanvasItem 宿主。
@export var game_board_canvas_item_path: NodePath = NodePath("../BoardWorld/GameBoardHost")

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


# --- 私有变量 ---

var _host_control: Control
var _world_root: Node2D
var _game_board: GameBoardController
var _game_board_canvas_item: CanvasItem
var _zoom_out_button: Button
var _fit_button: Button
var _zoom_in_button: Button
var _zoom_label: Label

var _viewport_utility: GFViewportUtility
var _gesture_utility: GFPointerGestureUtility
var _signal_utility: GFSignalUtility

var _content_rect: Rect2 = Rect2()
var _visible_world_rect: Rect2 = Rect2()
var _zoom: float = 1.0
var _follow_fit: bool = true
var _is_initialized: bool = false
var _is_handling_gesture_event: bool = false
var _last_viewport_size: Vector2 = Vector2.ZERO
var _previous_mouse_button_index: MouseButton = MOUSE_BUTTON_LEFT
var _previous_wheel_zoom_factor: float = 1.1


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
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	if is_instance_valid(_gesture_utility):
		_gesture_utility.mouse_button_index = _previous_mouse_button_index
		_gesture_utility.mouse_wheel_zoom_factor = _previous_wheel_zoom_factor
		_gesture_utility.reset_gesture()
	super._exit_tree()


# --- 公共方法 ---

## 将完整棋盘聚焦到当前视口，并恢复自动跟随完整聚焦。
func fit_to_content() -> void:
	if not _has_valid_geometry():
		return
	var fit_zoom: float = calculate_fit_zoom(
		_host_control.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var centered_position: Vector2 = calculate_centered_world_position(
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


## 计算完整内容适配视口时的缩放比例。
## @param viewport_size: 视口逻辑尺寸。
## @param content_rect: 棋盘局部世界包围盒。
## @param margin: 四周屏幕空间留白。
## @param max_zoom: 允许的最大适配比例。
static func calculate_fit_zoom(
	viewport_size: Vector2,
	content_rect: Rect2,
	margin: float,
	max_zoom: float
) -> float:
	if (
		viewport_size.x <= 0.0
		or viewport_size.y <= 0.0
		or content_rect.size.x <= 0.0
		or content_rect.size.y <= 0.0
	):
		return 1.0
	var safe_margin: float = maxf(margin, 0.0)
	var available_size: Vector2 = Vector2(
		maxf(viewport_size.x - safe_margin * 2.0, 1.0),
		maxf(viewport_size.y - safe_margin * 2.0, 1.0)
	)
	return minf(
		minf(
			available_size.x / content_rect.size.x,
			available_size.y / content_rect.size.y
		),
		maxf(max_zoom, 0.0001)
	)


## 计算让内容中心与视口中心重合时的世界根节点位置。
## @param viewport_size: 视口逻辑尺寸。
## @param content_rect: 棋盘局部世界包围盒。
## @param zoom: 目标缩放。
static func calculate_centered_world_position(
	viewport_size: Vector2,
	content_rect: Rect2,
	zoom: float
) -> Vector2:
	return viewport_size * 0.5 - content_rect.get_center() * zoom


## 计算围绕屏幕锚点缩放后保持锚点下世界位置不变的根节点位置。
## @param current_position: 当前世界根节点位置。
## @param anchor: 视口局部屏幕锚点。
## @param current_zoom: 当前缩放。
## @param next_zoom: 目标缩放。
static func calculate_zoomed_world_position(
	current_position: Vector2,
	anchor: Vector2,
	current_zoom: float,
	next_zoom: float
) -> Vector2:
	var safe_current_zoom: float = maxf(current_zoom, 0.0001)
	var world_anchor: Vector2 = (anchor - current_position) / safe_current_zoom
	return anchor - world_anchor * next_zoom


## 把世界根节点位置限制到内容不会完全离开视口的范围。
## @param viewport_size: 视口逻辑尺寸。
## @param content_rect: 棋盘局部世界包围盒。
## @param zoom: 当前缩放。
## @param desired_position: 未约束的目标位置。
## @param edge_margin: 大内容在视口边缘至少保留的屏幕像素。
static func calculate_clamped_world_position(
	viewport_size: Vector2,
	content_rect: Rect2,
	zoom: float,
	desired_position: Vector2,
	edge_margin: float
) -> Vector2:
	var result: Vector2 = desired_position
	result.x = _clamp_world_axis(
		viewport_size.x,
		content_rect.position.x,
		content_rect.size.x,
		zoom,
		desired_position.x,
		edge_margin
	)
	result.y = _clamp_world_axis(
		viewport_size.y,
		content_rect.position.y,
		content_rect.size.y,
		zoom,
		desired_position.y,
		edge_margin
	)
	return result


# --- 私有/辅助方法 ---

func _resolve_nodes() -> void:
	_host_control = _get_host_control()
	_world_root = _get_node_2d(world_root_path)
	_game_board = _get_game_board(game_board_path)
	_game_board_canvas_item = _get_canvas_item(game_board_canvas_item_path)
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
		var _world_appended: bool = missing.append("BoardWorld")
	if not is_instance_valid(_game_board):
		var _board_appended: bool = missing.append("GameBoardController")
	if not is_instance_valid(_game_board_canvas_item):
		var _canvas_item_appended: bool = missing.append("GameBoard CanvasItem")
	if not is_instance_valid(_viewport_utility):
		var _viewport_appended: bool = missing.append("GFViewportUtility")
	if not is_instance_valid(_gesture_utility):
		var _gesture_appended: bool = missing.append("GFPointerGestureUtility")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
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
	var fit_zoom: float = calculate_fit_zoom(
		_host_control.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var effective_minimum: float = minf(maxf(minimum_zoom, 0.0001), fit_zoom)
	var next_zoom: float = clampf(requested_zoom, effective_minimum, maximum_zoom)
	if is_equal_approx(next_zoom, _zoom):
		return
	var next_position: Vector2 = calculate_zoomed_world_position(
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
	_world_root.position = calculate_clamped_world_position(
		_host_control.size,
		_content_rect,
		_zoom,
		desired_position,
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


func _should_handle_gesture_event(event: InputEvent) -> bool:
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


static func _clamp_world_axis(
	viewport_extent: float,
	content_start: float,
	content_extent: float,
	zoom: float,
	desired_position: float,
	edge_margin: float
) -> float:
	if viewport_extent <= 0.0 or content_extent <= 0.0:
		return desired_position
	var scaled_extent: float = content_extent * zoom
	var scaled_start: float = content_start * zoom
	var safe_margin: float = minf(maxf(edge_margin, 0.0), viewport_extent * 0.5)
	if scaled_extent <= maxf(viewport_extent - safe_margin * 2.0, 0.0):
		return (viewport_extent - scaled_extent) * 0.5 - scaled_start
	var minimum_position: float = (
		viewport_extent
		- safe_margin
		- (content_start + content_extent) * zoom
	)
	var maximum_position: float = safe_margin - scaled_start
	return clampf(desired_position, minimum_position, maximum_position)


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
	_is_handling_gesture_event = true
	var handled: bool = _gesture_utility.handle_input_event(event)
	_is_handling_gesture_event = false
	if handled:
		_host_control.accept_event()


func _on_gesture_updated(snapshot: Dictionary, _event: InputEvent) -> void:
	if not _is_handling_gesture_event or not _has_valid_geometry():
		return
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
	var fit_zoom: float = calculate_fit_zoom(
		_host_control.size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var effective_minimum: float = minf(maxf(minimum_zoom, 0.0001), fit_zoom)
	var next_zoom: float = clampf(requested_zoom, effective_minimum, maximum_zoom)
	var next_position: Vector2 = calculate_zoomed_world_position(
		_world_root.position,
		anchor,
		_zoom,
		next_zoom
	) + pan_delta
	if is_equal_approx(next_zoom, _zoom) and pan_delta.is_zero_approx():
		return
	_follow_fit = false
	_set_view_transform(next_zoom, next_position)
