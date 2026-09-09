## BoardWorldViewportController: 管理棋盘世界画布的视口变换与可见区域。
##
## 棋盘规则和方块动画始终使用稳定的局部世界坐标；本控制器只负责缩放、平移、
## 聚焦、视口裁剪和 GF 指针手势适配。HUD 与诊断界面位于该宿主之外，不参与变换。
class_name BoardWorldViewportController
extends GFController


# --- 信号 ---

## 世界变换或可见区域更新后发出。
signal view_transform_changed(
	zoom: float,
	world_position: Vector2,
	visible_world_rect: Rect2
)

## 棋盘世界包围盒变化后发出，供屏幕空间布局重新计算安全区。
signal content_geometry_changed(content_rect: Rect2)

## 棋盘世界已挂到 GFSpatialCanvas 的稳定内容根，可安全开始对局初始化。
signal world_view_initialized


# --- 常量 ---

const _ZOOM_STEP: float = 1.15
const _DEFAULT_MINIMUM_ZOOM: float = 0.02
const _DEFAULT_MAXIMUM_ZOOM: float = 3.0
const _FIT_MARGIN: float = 18.0
const _PAN_EDGE_MARGIN: float = 36.0
## 玩法触控虚拟输入源稳定标识，供支持报告按玩家作用域采样。
const TOUCH_INPUT_SOURCE_ID: StringName = &"gameplay.touch_swipe"
const _TOUCH_ACTION_HOLD_SECONDS: float = 0.08
const _NO_TOUCH_POINTER: int = -1
const _KEYBOARD_PAN_STEP: float = 52.0
const _VIEW_CONTROLS_DESKTOP_LEFT_OFFSET: float = -240.0
const _VIEW_CONTROLS_COMPACT_LEFT_OFFSET: float = -88.0
const _VIEW_CONTROLS_DESKTOP_TOP_OFFSET: float = 12.0
const _VIEW_CONTROLS_COMPACT_TOP_OFFSET: float = 92.0
const _VIEW_CONTROLS_DESKTOP_BOTTOM_OFFSET: float = 64.0
const _VIEW_CONTROLS_COMPACT_BOTTOM_OFFSET: float = 148.0
const _FIT_BUTTON_DESKTOP_MINIMUM: Vector2 = Vector2(64.0, 44.0)
const _FIT_BUTTON_COMPACT_MINIMUM: Vector2 = Vector2(64.0, 44.0)
const _GAMEPLAY_GRID_OPTIONS: Dictionary = { "visible": false }


# --- 导出变量 ---

## 承载棋盘局部世界的 Node2D，相对当前 Controller。
@export var world_root_path: NodePath = NodePath("../BoardWorld")

## 受视口控制的棋盘表现节点，相对当前 Controller。
@export var game_board_path: NodePath = NodePath("../BoardWorld/BoardFeedbackRoot/BoardShakeRoot/GameBoardHost/GameBoard")

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
var _spatial_canvas: GFSpatialCanvas2D
var _world_root: Node2D
var _game_board: GameBoardController
var _view_controls: PanelContainer
var _zoom_out_button: Button
var _fit_button: Button
var _zoom_in_button: Button
var _zoom_label: Label

var _input_mapping: GFInputMappingUtility
var _signal_utility: GFSignalUtility
var _clock_utility: GameClockUtility
var _realtime_timer: GameRealtimeTimerUtility
var _performance_trace_utility: GamePerformanceTraceUtility
var _touch_input_source: GFVirtualInputSource
var _touch_action_pulse: GameVirtualActionPulseUtility

var _content_rect: Rect2 = Rect2()
var _visible_world_rect: Rect2 = Rect2()
var _fit_insets: Dictionary = {}
var _zoom: float = 1.0
var _follow_fit: bool = true
var _compact_view_controls: bool = false
var _is_initialized: bool = false
var _is_applying_project_view: bool = false
var _is_reconciling_spatial_view: bool = false
var _spatial_reconciliation_queued: bool = false
var _last_viewport_size: Vector2 = Vector2.ZERO
var _active_touch_ids: Dictionary[int, bool] = {}
var _touch_sequence_primary_id: int = _NO_TOUCH_POINTER
var _touch_sequence_start: Vector2 = Vector2.ZERO
var _touch_sequence_last: Vector2 = Vector2.ZERO
var _touch_sequence_started_msec: int = 0
var _touch_sequence_cancelled: bool = false
var _touch_sequence_action_emitted: bool = false
var _spatial_input_suppressed_by_touch_action: bool = false


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_nodes()
	_resolve_utilities()
	if is_instance_valid(_input_mapping) and is_instance_valid(_realtime_timer):
		_touch_input_source = _input_mapping.create_virtual_source(
			TOUCH_INPUT_SOURCE_ID,
			-1,
			_realtime_timer
		)
		_touch_action_pulse = GameVirtualActionPulseUtility.new().configure(_touch_input_source)
	if not _has_required_dependencies():
		return

	_bind_runtime_signals()
	call_deferred(&"_initialize_view")


func _exit_tree() -> void:
	if is_instance_valid(_touch_action_pulse):
		_touch_action_pulse.dispose()
	_touch_action_pulse = null
	_touch_input_source = null
	_reset_touch_sequence()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	super._exit_tree()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_OUT
		or what == NOTIFICATION_APPLICATION_PAUSED
	):
		# 微信切后台、系统弹窗或失焦时可能不再补发 ScreenTouch release。
		# 主动清理整个序列，避免旧 pointer 永久把后续首指判成多指，或让
		# 已提交滑动后的 GFSpatialCanvas2D 一直保持禁用。
		_reset_touch_sequence()


func _process(_delta: float) -> void:
	if not _is_initialized:
		return
	_record_acceptance_frame()
	if not is_instance_valid(_input_mapping):
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
		_set_view_transform(_zoom, _get_content_position() + pan_delta)


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
		_set_view_transform(_zoom, _get_content_position())


## 在窄竖屏只保留完整聚焦按钮；缩放仍可通过手势、键盘、鼠标滚轮和手柄完成。
## @param compact: 是否启用窄竖屏视图控件布局。
func set_compact_view_controls(compact: bool) -> void:
	_compact_view_controls = compact
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
		_view_controls.visible = not compact or not _follow_fit
		_view_controls.offset_left = (
			_VIEW_CONTROLS_COMPACT_LEFT_OFFSET
			if compact
			else _VIEW_CONTROLS_DESKTOP_LEFT_OFFSET
		)
		_view_controls.offset_top = (
			_VIEW_CONTROLS_COMPACT_TOP_OFFSET
			if compact
			else _VIEW_CONTROLS_DESKTOP_TOP_OFFSET
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


## 按完整聚焦规则预测棋盘内容在屏幕空间中的矩形。
## @param viewport_size: 棋盘宿主视口的逻辑尺寸。
## @param insets: 完整聚焦使用的四向屏幕内缩。
## @param content_aspect_ratio: 当前棋盘世界包围盒的实际宽高比。
## @return 完整聚焦后的棋盘屏幕空间矩形。
static func calculate_fitted_content_screen_rect(
	viewport_size: Vector2,
	insets: Dictionary,
	content_aspect_ratio: float
) -> Rect2:
	var fit_viewport_rect: Rect2 = calculate_fit_viewport_rect(viewport_size, insets)
	var safe_aspect_ratio: float = maxf(content_aspect_ratio, 0.0001)
	var available_size: Vector2 = Vector2(
		maxf(fit_viewport_rect.size.x - _FIT_MARGIN * 2.0, 1.0),
		maxf(fit_viewport_rect.size.y - _FIT_MARGIN * 2.0, 1.0)
	)
	var fitted_height: float = minf(
		available_size.y,
		available_size.x / safe_aspect_ratio
	)
	var fitted_size: Vector2 = Vector2(fitted_height * safe_aspect_ratio, fitted_height)
	return Rect2(fit_viewport_rect.get_center() - fitted_size * 0.5, fitted_size)


## 让棋盘世界按屏幕像素增量平移。
## @param screen_delta: 屏幕空间平移量。
func pan_by(screen_delta: Vector2) -> void:
	if not _has_valid_geometry() or screen_delta.is_zero_approx():
		return
	_follow_fit = false
	_set_view_transform(_zoom, _get_content_position() + screen_delta)


## 返回当前棋盘世界缩放。
func get_zoom() -> float:
	return _zoom


## 返回最近同步给棋盘表现层的局部可见矩形。
func get_visible_world_rect() -> Rect2:
	return _visible_world_rect


## 返回棋盘世界是否已经完成稳定挂载与视图初始化。
func is_view_initialized() -> bool:
	return _is_initialized


## 返回当前棋盘内容的实际宽高比；几何尚未初始化时返回方形基线。
func get_content_aspect_ratio() -> float:
	var content_size: Vector2 = _content_rect.size
	if (
		(content_size.x <= 0.0 or content_size.y <= 0.0)
		and is_instance_valid(_game_board)
	):
		content_size = _game_board.get_board_world_rect().size
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return 1.0
	return content_size.x / content_size.y


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
	_spatial_canvas = null
	if _host_control is GFSpatialCanvas2D:
		_spatial_canvas = _host_control
	_world_root = _get_node_2d(world_root_path)
	_game_board = _get_game_board(game_board_path)
	_view_controls = _get_panel_container(view_controls_path)
	_zoom_out_button = _get_button(zoom_out_button_path)
	_fit_button = _get_button(fit_button_path)
	_zoom_in_button = _get_button(zoom_in_button_path)
	_zoom_label = _get_label(zoom_label_path)


func _prepare_spatial_canvas() -> void:
	if not is_instance_valid(_spatial_canvas) or not is_instance_valid(_world_root):
		return
	_spatial_canvas.set_input_enabled(false)
	var policy: GFSpatialCanvasInputPolicy = _create_spatial_input_policy()
	if not _spatial_canvas.set_input_policy(policy):
		push_error("[BoardWorldViewportController] 无法配置 GF 空间画布输入策略。")
		return
	_spatial_canvas.set_input_enabled(true)
	var grid_configured: bool = _spatial_canvas.configure_grid(
		_spatial_canvas.get_grid_origin(),
		_spatial_canvas.get_grid_size(),
		_GAMEPLAY_GRID_OPTIONS
	)
	if not grid_configured:
		push_error("[BoardWorldViewportController] 无法关闭 GF 空间画布编辑网格。")
	var content_root: Node2D = _spatial_canvas.get_content_root()
	if _world_root.get_parent() != content_root:
		var previous_sibling_index: int = _world_root.get_index()
		_world_root.reparent(content_root)
		_spatial_canvas.move_child(
			content_root,
			clampi(previous_sibling_index, 0, _spatial_canvas.get_child_count() - 1)
		)
	_world_root.position = Vector2.ZERO
	_world_root.scale = Vector2.ONE
	var limits_set: bool = _spatial_canvas.set_zoom_limits(0.0001, maximum_zoom)
	if not limits_set:
		push_error("[BoardWorldViewportController] 无法配置 GF 空间画布缩放边界。")


func _get_content_position() -> Vector2:
	if is_instance_valid(_spatial_canvas):
		return _spatial_canvas.get_content_root().position
	return Vector2.ZERO


func _record_acceptance_frame() -> void:
	if (
		not is_instance_valid(_performance_trace_utility)
		or not _performance_trace_utility.is_acceptance_measurement_active()
	):
		return
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return
	_performance_trace_utility.record_player_visible_frame(
		Vector2i(viewport.get_visible_rect().size.round())
	)


func _resolve_utilities() -> void:
	_input_mapping = _get_input_mapping_utility()
	_signal_utility = _get_signal_utility()
	_clock_utility = _get_clock_utility()
	_realtime_timer = _get_realtime_timer_utility()
	_performance_trace_utility = _get_performance_trace_utility()


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_host_control):
		var _host_appended: bool = missing.append("Control host")
	if not is_instance_valid(_spatial_canvas):
		var _spatial_appended: bool = missing.append("GFSpatialCanvas2D")
	if not is_instance_valid(_world_root):
		var _world_appended: bool = missing.append("BoardWorld")
	if not is_instance_valid(_game_board):
		var _board_appended: bool = missing.append("GameBoardController")
	if not is_instance_valid(_input_mapping):
		var _input_appended: bool = missing.append("GFInputMappingUtility")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
	if not is_instance_valid(_clock_utility):
		var _clock_appended: bool = missing.append("GameClockUtility")
	if not is_instance_valid(_realtime_timer):
		var _timer_appended: bool = missing.append("GameRealtimeTimerUtility")
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
	var _view_connection: GFSignalConnection = _signal_utility.connect_signal(
		_spatial_canvas.view_changed,
		_on_spatial_view_changed,
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
	if not is_inside_tree() or _is_initialized:
		return
	_prepare_spatial_canvas()
	if not _has_required_dependencies():
		return
	_last_viewport_size = _host_control.size
	_content_rect = _game_board.get_board_world_rect()
	_refresh_spatial_zoom_limits()
	_is_initialized = true
	content_geometry_changed.emit(_content_rect)
	fit_to_content()
	world_view_initialized.emit()


func _has_valid_geometry() -> bool:
	return (
		is_instance_valid(_host_control)
		and is_instance_valid(_spatial_canvas)
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
		_get_content_position(),
		anchor,
		_zoom,
		next_zoom
	)
	_follow_fit = false
	_set_view_transform(next_zoom, next_position)


func _set_view_transform(next_zoom: float, desired_position: Vector2) -> void:
	if not _has_valid_geometry():
		return
	var requested_zoom: float = maxf(next_zoom, 0.0001)
	var fit_viewport_rect: Rect2 = _get_fit_viewport_rect()
	var clamped_position: Vector2 = fit_viewport_rect.position + CanvasViewportMath.calculate_clamped_world_position(
		fit_viewport_rect.size,
		_content_rect,
		requested_zoom,
		desired_position - fit_viewport_rect.position,
		_PAN_EDGE_MARGIN
	)
	var world_center: Vector2 = (
		(_host_control.size * 0.5 - clamped_position)
		/ requested_zoom
	)
	_is_applying_project_view = true
	var view_set: bool = _spatial_canvas.set_view(world_center, requested_zoom)
	_is_applying_project_view = false
	if not view_set:
		push_error("[BoardWorldViewportController] GF 空间画布拒绝了无效视图状态。")
		return
	_zoom = _spatial_canvas.get_zoom()
	_update_zoom_label()
	_sync_visible_world_rect()


func _refresh_spatial_zoom_limits() -> void:
	if not _has_valid_geometry():
		return
	var fit_zoom: float = CanvasViewportMath.calculate_fit_zoom(
		_get_fit_viewport_rect().size,
		_content_rect,
		_FIT_MARGIN,
		maximum_zoom
	)
	var effective_minimum: float = minf(maxf(minimum_zoom, 0.0001), fit_zoom)
	_is_applying_project_view = true
	var limits_set: bool = _spatial_canvas.set_zoom_limits(effective_minimum, maximum_zoom)
	_is_applying_project_view = false
	if not limits_set:
		push_error("[BoardWorldViewportController] 无法刷新 GF 空间画布缩放边界。")


func _sync_visible_world_rect() -> void:
	if not _has_valid_geometry():
		return
	_visible_world_rect = _spatial_canvas.get_visible_world_rect()
	_game_board.set_visible_world_rect(_visible_world_rect, _zoom)
	view_transform_changed.emit(
		_zoom,
		_get_content_position(),
		_visible_world_rect
	)


func _update_zoom_label() -> void:
	if is_instance_valid(_zoom_label):
		_zoom_label.text = "%d%%" % roundi(_zoom * 100.0)
	if is_instance_valid(_view_controls):
		# In portrait, the recovery action appears only after manual pan/zoom.
		_view_controls.visible = not _compact_view_controls or not _follow_fit


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


func _create_spatial_input_policy() -> GFSpatialCanvasInputPolicy:
	return GameSpatialCanvasInputPolicy.create_navigation_policy(_ZOOM_STEP)


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


func _get_realtime_timer_utility() -> GameRealtimeTimerUtility:
	var utility_value: Object = get_utility(GameRealtimeTimerUtility, true)
	if utility_value is GameRealtimeTimerUtility:
		var timer_utility: GameRealtimeTimerUtility = utility_value
		return timer_utility
	return null


func _get_performance_trace_utility() -> GamePerformanceTraceUtility:
	var utility_value: Object = get_utility(GamePerformanceTraceUtility, true)
	if utility_value is GamePerformanceTraceUtility:
		var performance_trace: GamePerformanceTraceUtility = utility_value
		return performance_trace
	return null


func _prepare_touch_action(event: InputEvent) -> StringName:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _active_touch_ids.has(touch.index):
				return &""
			var starts_primary_sequence: bool = _active_touch_ids.is_empty()
			_active_touch_ids[touch.index] = true
			if starts_primary_sequence and _touch_sequence_primary_id == _NO_TOUCH_POINTER:
				_touch_sequence_primary_id = touch.index
				_touch_sequence_start = touch.position
				_touch_sequence_last = touch.position
				_touch_sequence_started_msec = _clock_utility.get_tick_msec()
				_touch_sequence_cancelled = false
				_touch_sequence_action_emitted = false
			else:
				_touch_sequence_cancelled = true
			return &""

		if not _active_touch_ids.has(touch.index):
			return &""
		if touch.index == _touch_sequence_primary_id:
			_touch_sequence_last = touch.position
			if (
				_active_touch_ids.size() == 1
				and not _touch_sequence_cancelled
				and not _touch_sequence_action_emitted
			):
				return _try_commit_touch_swipe()
		_touch_sequence_cancelled = true
		return &""

	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if not _active_touch_ids.has(drag.index):
			return &""
		if drag.index == _touch_sequence_primary_id:
			_touch_sequence_last = drag.position
		if _active_touch_ids.size() >= 2:
			_touch_sequence_cancelled = true
		elif (
			drag.index == _touch_sequence_primary_id
			and not _touch_sequence_cancelled
			and not _touch_sequence_action_emitted
		):
			return _try_commit_touch_swipe()
	return &""


func _try_commit_touch_swipe() -> StringName:
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
	var action_id: StringName = GameplayInputActions.action_for_direction(direction)
	if action_id != &"":
		_touch_sequence_action_emitted = true
		_suppress_spatial_input_for_committed_touch_action()
	return action_id


func _finish_touch_event(event: InputEvent) -> void:
	if not event is InputEventScreenTouch:
		return
	var touch: InputEventScreenTouch = event
	if touch.pressed:
		return
	var _erased_touch: bool = _active_touch_ids.erase(touch.index)
	if _active_touch_ids.is_empty():
		_reset_touch_sequence()


func _reset_touch_sequence() -> void:
	_active_touch_ids.clear()
	_touch_sequence_primary_id = _NO_TOUCH_POINTER
	_touch_sequence_start = Vector2.ZERO
	_touch_sequence_last = Vector2.ZERO
	_touch_sequence_started_msec = 0
	_touch_sequence_cancelled = false
	_touch_sequence_action_emitted = false
	_restore_spatial_input_after_touch_action()


func _suppress_spatial_input_for_committed_touch_action() -> void:
	if (
		_spatial_input_suppressed_by_touch_action
		or not is_instance_valid(_spatial_canvas)
	):
		return
	_spatial_input_suppressed_by_touch_action = true
	# GFSpatialCanvas2D 会同时清理已经追踪的首指瞬态状态。这样玩法滑动一旦
	# 提交，同一触控序列后来加入的第二指也不能再把它改解释为画布导航。
	_spatial_canvas.set_input_enabled(false)


func _restore_spatial_input_after_touch_action() -> void:
	if not _spatial_input_suppressed_by_touch_action:
		return
	_spatial_input_suppressed_by_touch_action = false
	if is_instance_valid(_spatial_canvas):
		_spatial_canvas.set_input_enabled(true)


func _inject_touch_action(action_id: StringName) -> void:
	if action_id == &"" or not is_instance_valid(_touch_action_pulse):
		return
	var input_receipt_id: int = 0
	if is_instance_valid(_performance_trace_utility):
		# 先冻结项目接收触控的时刻，再进入 GF virtual pulse；指标因此包含
		# 脉冲注入、PlayerInputSystem 轮询与同步回合计算，而非从命令入口起算。
		input_receipt_id = _performance_trace_utility.capture_move_input(
			action_id,
			GamePerformanceTraceUtility.MOVE_INPUT_SOURCE_TOUCH
		)
	if not _touch_action_pulse.pulse(action_id, self, _TOUCH_ACTION_HOLD_SECONDS):
		if is_instance_valid(_performance_trace_utility):
			_performance_trace_utility.cancel_move_input_receipt(
				input_receipt_id,
				&"virtual_pulse_rejected"
			)
		push_warning("[BoardWorldViewportController] 无法注入触控动作：%s。" % action_id)


func _should_reconcile_spatial_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			return false
		return (
			mouse_button.pressed
			and mouse_button.button_index in [
				MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_DOWN,
			]
		)
	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event
		return (mouse_motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _spatial_input_suppressed_by_touch_action:
			return false
		return _active_touch_ids.size() >= 2
	return event is InputEventMagnifyGesture or event is InputEventPanGesture


func _queue_spatial_input_reconciliation() -> void:
	_follow_fit = false
	if _spatial_reconciliation_queued:
		return
	_spatial_reconciliation_queued = true
	call_deferred(&"_reconcile_spatial_input_view")


func _reconcile_spatial_input_view() -> void:
	_spatial_reconciliation_queued = false
	if not is_inside_tree() or not _is_initialized or not _has_valid_geometry():
		return
	_is_reconciling_spatial_view = true
	_set_view_transform(_spatial_canvas.get_zoom(), _get_content_position())
	_is_reconciling_spatial_view = false


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
		(previous_center - _get_content_position())
		/ maxf(_zoom, 0.0001)
	)
	var desired_position: Vector2 = current_fit_rect.get_center() - world_center * _zoom
	_set_view_transform(_zoom, desired_position)


func _on_board_geometry_changed(board_rect: Rect2) -> void:
	_content_rect = board_rect
	content_geometry_changed.emit(_content_rect)
	if not _is_initialized:
		return
	_refresh_spatial_zoom_limits()
	if _follow_fit:
		fit_to_content()
	else:
		_set_view_transform(_zoom, _get_content_position())


func _on_gui_input(event: InputEvent) -> void:
	var pending_touch_action: StringName = &""
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		pending_touch_action = _prepare_touch_action(event)
	if _should_reconcile_spatial_input(event):
		_queue_spatial_input_reconciliation()
	_finish_touch_event(event)
	if pending_touch_action != &"":
		_inject_touch_action(pending_touch_action)


func _on_spatial_view_changed(_snapshot: Dictionary) -> void:
	if not _is_initialized or _is_applying_project_view or _is_reconciling_spatial_view:
		return
	_zoom = _spatial_canvas.get_zoom()
	_update_zoom_label()
	_sync_visible_world_rect()
