## GameplayResponsiveLayoutController: 管理棋盘画布与屏幕空间 HUD 的安全区。
##
## 玩法页不使用共享三栏布局的侧栏。棋盘始终扩展到可用画面，HUD 保持在
## 根屏幕空间并只随安全区调整位置，避免设备变化时反复改挂父节点。
class_name GameplayResponsiveLayoutController
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 枚举 ---

enum LayoutMode {
	DESKTOP,
	COMPACT_LANDSCAPE,
	PORTRAIT,
}


# --- 常量 ---

const _DESKTOP_MINIMUM_WIDTH: float = 1180.0
const _DESKTOP_MINIMUM_HEIGHT: float = 620.0
const _PORTRAIT_HEIGHT_RATIO: float = 1.08
const _DESKTOP_GUTTER: float = 16.0
const _COMPACT_GUTTER: float = 10.0
const _PORTRAIT_GUTTER: float = 8.0
const _DESKTOP_BOARD_FIT_INSETS: Dictionary = {
	"top": 92.0,
	"left": 10.0,
	"bottom": 10.0,
	"right": 10.0,
}
const _COMPACT_BOARD_FIT_INSETS: Dictionary = {
	"top": 86.0,
	"left": 8.0,
	"bottom": 8.0,
	"right": 8.0,
}
const _PORTRAIT_BOARD_FIT_INSETS: Dictionary = {
	"top": 92.0,
	"left": 8.0,
	"bottom": 176.0,
	"right": 8.0,
}


# --- 导出变量 ---

@export var margin_container_path: NodePath = NodePath("../MarginContainer")
@export var columns_container_path: NodePath = NodePath("../MarginContainer/ColumnsContainer")
@export var left_column_path: NodePath = NodePath("../MarginContainer/ColumnsContainer/LeftColumn")
@export var right_column_path: NodePath = NodePath("../MarginContainer/ColumnsContainer/RightColumn")
@export var board_viewport_path: NodePath = NodePath(
	"../MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/BoardViewport"
)
@export var board_world_viewport_controller_path: NodePath = NodePath(
	"../MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/BoardViewport/BoardWorldViewportController"
)
@export var hud_path: NodePath = NodePath("../HUD")
@export var replay_controls_path: NodePath = NodePath("../ReplayControlsContainer")

## 触屏运行时即使横屏尺寸足够，也采用紧凑信息密度。
@export var prefer_compact_layout_on_touch: bool = true


# --- 私有变量 ---

var _root_control: Control
var _margin_container: MarginContainer
var _columns_container: HBoxContainer
var _left_column: VBoxContainer
var _right_column: VBoxContainer
var _board_viewport: Control
var _board_world_viewport_controller: BoardWorldViewportController
var _hud: Hud
var _replay_controls: PanelContainer
var _signal_utility: GFSignalUtility
var _viewport_utility: GFViewportUtility
var _platform_utility: GamePlatformUtility
var _current_layout_mode: LayoutMode = LayoutMode.DESKTOP
var _layout_update_queued: bool = false
var _replay_mode_active: bool = false


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_nodes()
	_signal_utility = _get_signal_utility()
	_viewport_utility = _get_viewport_utility()
	_platform_utility = _get_platform_utility()
	if not _has_required_dependencies():
		return
	var _resize_connection: GFSignalConnection = _signal_utility.connect_signal(
		_root_control.resized,
		_queue_layout_update,
		self
	)
	var _platform_context_connection: GFSignalConnection = _signal_utility.connect_signal(
		_platform_utility.context_changed,
		_on_platform_context_changed,
		self
	)
	_queue_layout_update()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	super._exit_tree()


# --- 公共方法 ---

## 根据逻辑视口尺寸与移动设备偏好选择玩法布局。
## @param viewport_size: 当前逻辑视口尺寸。
## @param prefer_compact: 是否强制使用紧凑横屏信息密度。
## @return 选中的布局模式。
static func classify_layout(
	viewport_size: Vector2,
	prefer_compact: bool = false
) -> LayoutMode:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return LayoutMode.DESKTOP
	if viewport_size.y >= viewport_size.x * _PORTRAIT_HEIGHT_RATIO:
		return LayoutMode.PORTRAIT
	if (
		prefer_compact
		or viewport_size.x < _DESKTOP_MINIMUM_WIDTH
		or viewport_size.y < _DESKTOP_MINIMUM_HEIGHT
	):
		return LayoutMode.COMPACT_LANDSCAPE
	return LayoutMode.DESKTOP


func get_layout_mode() -> LayoutMode:
	return _current_layout_mode


## 通知布局控制器回放运输控件是否参与当前安全区计算。
## @param is_active: true 表示当前为回放模式，需要为运输控件预留棋盘安全区。
func set_replay_mode_active(is_active: bool) -> void:
	if _replay_mode_active == is_active:
		return
	_replay_mode_active = is_active
	_queue_layout_update()


## 返回当前布局用于棋盘完整聚焦的 HUD 屏幕边距。
## @param mode: 要查询的响应式布局模式。
## @return 对应布局的四向 HUD 屏幕边距。
static func get_board_fit_insets(mode: LayoutMode) -> Dictionary:
	match mode:
		LayoutMode.COMPACT_LANDSCAPE:
			return _COMPACT_BOARD_FIT_INSETS.duplicate(true)
		LayoutMode.PORTRAIT:
			return _PORTRAIT_BOARD_FIT_INSETS.duplicate(true)
		_:
			return _DESKTOP_BOARD_FIT_INSETS.duplicate(true)


## 计算棋盘视口在安全区和玩法留白内应占用的稳定尺寸。
## @param viewport_size: 当前逻辑视口尺寸。
## @param safe_area: GFViewportUtility 返回的四向安全区边距。
## @param gutter: 当前布局模式的玩法留白。
## @return 不小于一个逻辑像素的棋盘视口最小尺寸。
static func calculate_board_viewport_minimum(
	viewport_size: Vector2,
	safe_area: Dictionary,
	gutter: float
) -> Vector2:
	var horizontal_insets: float = (
		GFVariantData.get_option_float(safe_area, "left")
		+ GFVariantData.get_option_float(safe_area, "right")
		+ maxf(gutter, 0.0) * 2.0
	)
	var vertical_insets: float = (
		GFVariantData.get_option_float(safe_area, "top")
		+ GFVariantData.get_option_float(safe_area, "bottom")
		+ maxf(gutter, 0.0) * 2.0
	)
	return Vector2(
		maxf(viewport_size.x - horizontal_insets, 1.0),
		maxf(viewport_size.y - vertical_insets, 1.0)
	)


# --- 私有/辅助方法 ---

func _resolve_nodes() -> void:
	var host_value: Node = get_host_as(Control)
	if host_value is Control:
		_root_control = host_value
	_margin_container = _get_margin_container(margin_container_path)
	_columns_container = _get_hbox_container(columns_container_path)
	_left_column = _get_vbox_container(left_column_path)
	_right_column = _get_vbox_container(right_column_path)
	_board_viewport = _get_control(board_viewport_path)
	_board_world_viewport_controller = _get_board_world_viewport_controller(
		board_world_viewport_controller_path
	)
	_hud = _get_hud(hud_path)
	var replay_controls_value: Node = get_node_or_null(replay_controls_path)
	if replay_controls_value is PanelContainer:
		_replay_controls = replay_controls_value


func _has_required_dependencies() -> bool:
	var dependencies: Array[Object] = [
		_root_control,
		_margin_container,
		_columns_container,
		_left_column,
		_right_column,
		_board_viewport,
		_board_world_viewport_controller,
		_hud,
		_replay_controls,
		_signal_utility,
		_viewport_utility,
		_platform_utility,
	]
	for dependency: Object in dependencies:
		if not is_instance_valid(dependency):
			push_error("[GameplayResponsiveLayoutController] 缺少玩法响应式布局依赖。")
			return false
	return true


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_current_layout")


func _apply_current_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree() or not _has_required_dependencies():
		return
	_current_layout_mode = classify_layout(
		_root_control.size,
		prefer_compact_layout_on_touch and _has_touch_capability()
	)
	_left_column.visible = false
	_right_column.visible = false
	_columns_container.add_theme_constant_override("separation", 0)
	var gutter: float = _get_layout_gutter(_current_layout_mode)
	var extra_margins: Dictionary = {
		"top": gutter,
		"left": gutter,
		"bottom": gutter,
		"right": gutter,
	}
	var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
		_margin_container,
		_root_control.get_viewport(),
		extra_margins
	)
	var safe_area: Dictionary = _viewport_utility.get_display_safe_area_margins(
		_root_control.get_viewport()
	)
	_board_viewport.custom_minimum_size = calculate_board_viewport_minimum(
		_root_control.size,
		safe_area,
		gutter
	)
	_hud.apply_screen_insets({
		"top": GFVariantData.get_option_float(safe_area, "top") + gutter,
		"left": GFVariantData.get_option_float(safe_area, "left") + gutter,
		"bottom": GFVariantData.get_option_float(safe_area, "bottom") + gutter,
		"right": GFVariantData.get_option_float(safe_area, "right") + gutter,
	})
	_hud.set_compact_mode(_current_layout_mode != LayoutMode.DESKTOP)
	_hud.set_portrait_mode(_current_layout_mode == LayoutMode.PORTRAIT)
	_apply_replay_controls_layout(_current_layout_mode)
	var board_fit_insets: Dictionary = get_board_fit_insets(_current_layout_mode)
	if _replay_mode_active and _current_layout_mode != LayoutMode.DESKTOP:
		board_fit_insets["bottom"] = maxf(
			GFVariantData.get_option_float(board_fit_insets, "bottom"),
			176.0
		)
	_board_world_viewport_controller.set_fit_insets(board_fit_insets)
	_board_world_viewport_controller.set_compact_view_controls(
		_current_layout_mode == LayoutMode.PORTRAIT
	)


func _apply_replay_controls_layout(mode: LayoutMode) -> void:
	if not is_instance_valid(_replay_controls):
		return
	if mode == LayoutMode.DESKTOP:
		_replay_controls.anchor_left = 0.0
		_replay_controls.anchor_top = 0.5
		_replay_controls.anchor_right = 0.0
		_replay_controls.anchor_bottom = 0.5
		_replay_controls.offset_left = 28.0
		_replay_controls.offset_top = -74.0
		_replay_controls.offset_right = 328.0
		_replay_controls.offset_bottom = 74.0
		return
	_replay_controls.anchor_left = 0.5
	_replay_controls.anchor_top = 1.0
	_replay_controls.anchor_right = 0.5
	_replay_controls.anchor_bottom = 1.0
	_replay_controls.offset_left = -150.0
	_replay_controls.offset_top = -172.0
	_replay_controls.offset_right = 150.0
	_replay_controls.offset_bottom = -24.0


static func _get_layout_gutter(mode: LayoutMode) -> float:
	match mode:
		LayoutMode.COMPACT_LANDSCAPE:
			return _COMPACT_GUTTER
		LayoutMode.PORTRAIT:
			return _PORTRAIT_GUTTER
		_:
			return _DESKTOP_GUTTER


func _on_platform_context_changed(_context: GFPlatformRuntimeContext) -> void:
	_queue_layout_update()


func _has_touch_capability() -> bool:
	return (
		is_instance_valid(_platform_utility)
		and _platform_utility.has_capability(GamePlatformUtility.CAPABILITY_TOUCH)
	)


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility, true)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility, true)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _get_platform_utility() -> GamePlatformUtility:
	var utility_value: Object = get_utility(GamePlatformUtility, true)
	if utility_value is GamePlatformUtility:
		var platform_utility: GamePlatformUtility = utility_value
		return platform_utility
	return null


func _get_control(path: NodePath) -> Control:
	var node_value: Node = get_node_or_null(path)
	if node_value is Control:
		var control: Control = node_value
		return control
	return null


func _get_margin_container(path: NodePath) -> MarginContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is MarginContainer:
		var container: MarginContainer = node_value
		return container
	return null


func _get_hbox_container(path: NodePath) -> HBoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is HBoxContainer:
		var container: HBoxContainer = node_value
		return container
	return null


func _get_vbox_container(path: NodePath) -> VBoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is VBoxContainer:
		var container: VBoxContainer = node_value
		return container
	return null


func _get_hud(path: NodePath) -> Hud:
	var node_value: Node = get_node_or_null(path)
	if node_value is Hud:
		var hud: Hud = node_value
		return hud
	return null


func _get_board_world_viewport_controller(path: NodePath) -> BoardWorldViewportController:
	var node_value: Node = get_node_or_null(path)
	if node_value is BoardWorldViewportController:
		var controller: BoardWorldViewportController = node_value
		return controller
	return null
