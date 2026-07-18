## GameplayResponsiveLayoutController: 管理玩法页的响应式分栏与安全区。
##
## 桌面宽屏保留三栏，紧凑横屏隐藏诊断栏，竖屏则把 HUD 移到棋盘上方的
## 独立屏幕空间。该控制器不改变共享三栏场景，避免玩法约束影响其他功能页。
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
const _DESKTOP_MARGIN_HORIZONTAL: float = 56.0
const _DESKTOP_MARGIN_VERTICAL: float = 54.0
const _COMPACT_MARGIN_HORIZONTAL: float = 24.0
const _COMPACT_MARGIN_VERTICAL: float = 20.0
const _PORTRAIT_MARGIN_HORIZONTAL: float = 16.0
const _PORTRAIT_MARGIN_BOTTOM: float = 16.0
const _MOBILE_HUD_TOP_GAP: float = 12.0
const _MOBILE_HUD_BOARD_GAP: float = 14.0
const _MOBILE_HUD_MINIMUM_HEIGHT: float = 72.0
const _DESKTOP_LEFT_COLUMN_WIDTH: float = 310.0
const _COMPACT_LEFT_COLUMN_WIDTH: float = 230.0
const _DESKTOP_COLUMN_SEPARATION: int = 34
const _COMPACT_COLUMN_SEPARATION: int = 18
const _DESKTOP_BOARD_MINIMUM: Vector2 = Vector2(450.0, 450.0)
const _COMPACT_BOARD_MINIMUM: Vector2 = Vector2(360.0, 360.0)
const _PORTRAIT_BOARD_MINIMUM: Vector2 = Vector2(0.0, 360.0)


# --- 导出变量 ---

@export var margin_container_path: NodePath = NodePath("../MarginContainer")
@export var columns_container_path: NodePath = NodePath("../MarginContainer/ColumnsContainer")
@export var left_column_path: NodePath = NodePath("../MarginContainer/ColumnsContainer/LeftColumn")
@export var right_column_path: NodePath = NodePath("../MarginContainer/ColumnsContainer/RightColumn")
@export var board_viewport_path: NodePath = NodePath(
	"../MarginContainer/ColumnsContainer/CenterColumn/CenterContentHolder/BoardViewport"
)
@export var hud_path: NodePath = NodePath("../MarginContainer/ColumnsContainer/LeftColumn/HUD")
@export var replay_controls_path: NodePath = NodePath(
	"../MarginContainer/ColumnsContainer/LeftColumn/ReplayControlsContainer"
)
@export var mobile_hud_host_path: NodePath = NodePath("../MobileHudHost")
@export var mobile_hud_content_path: NodePath = NodePath(
	"../MobileHudHost/Margin/MobileHudContent"
)

## 在触屏 Web 或原生移动平台上，即使横屏尺寸足够也使用紧凑横屏布局。
@export var prefer_compact_layout_on_mobile: bool = true


# --- 私有变量 ---

var _root_control: Control
var _margin_container: MarginContainer
var _columns_container: HBoxContainer
var _left_column: VBoxContainer
var _right_column: VBoxContainer
var _board_viewport: Control
var _hud: Hud
var _replay_controls: VBoxContainer
var _mobile_hud_host: PanelContainer
var _mobile_hud_content: VBoxContainer
var _signal_utility: GFSignalUtility
var _viewport_utility: GFViewportUtility
var _current_layout_mode: LayoutMode = LayoutMode.DESKTOP
var _layout_update_queued: bool = false


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_nodes()
	_resolve_utilities()
	if not _has_required_dependencies():
		return
	_bind_runtime_signals()
	_queue_layout_update()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	super._exit_tree()


# --- 公共方法 ---

## 根据逻辑视口尺寸和设备偏好选择玩法布局。
## @param viewport_size: 当前逻辑视口尺寸。
## @param prefer_compact: 是否优先采用触屏紧凑横屏布局。
## @return 应应用的玩法布局模式。
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


## 返回最近一次应用的布局模式。
func get_layout_mode() -> LayoutMode:
	return _current_layout_mode


# --- 私有/辅助方法 ---

func _resolve_nodes() -> void:
	_root_control = _get_control_host()
	_margin_container = _get_margin_container(margin_container_path)
	_columns_container = _get_hbox_container(columns_container_path)
	_left_column = _get_vbox_container(left_column_path)
	_right_column = _get_vbox_container(right_column_path)
	_board_viewport = _get_control(board_viewport_path)
	_hud = _get_hud(hud_path)
	_replay_controls = _get_vbox_container(replay_controls_path)
	_mobile_hud_host = _get_panel_container(mobile_hud_host_path)
	_mobile_hud_content = _get_vbox_container(mobile_hud_content_path)


func _resolve_utilities() -> void:
	_signal_utility = _get_signal_utility()
	_viewport_utility = _get_viewport_utility()


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_root_control):
		var _root_appended: bool = missing.append("GamePlay Control host")
	if not is_instance_valid(_margin_container):
		var _margin_appended: bool = missing.append("MarginContainer")
	if not is_instance_valid(_columns_container):
		var _columns_appended: bool = missing.append("ColumnsContainer")
	if not is_instance_valid(_left_column):
		var _left_appended: bool = missing.append("LeftColumn")
	if not is_instance_valid(_right_column):
		var _right_appended: bool = missing.append("RightColumn")
	if not is_instance_valid(_board_viewport):
		var _board_appended: bool = missing.append("BoardViewport")
	if not is_instance_valid(_hud):
		var _hud_appended: bool = missing.append("Hud")
	if not is_instance_valid(_replay_controls):
		var _replay_appended: bool = missing.append("ReplayControlsContainer")
	if not is_instance_valid(_mobile_hud_host):
		var _mobile_host_appended: bool = missing.append("MobileHudHost")
	if not is_instance_valid(_mobile_hud_content):
		var _mobile_content_appended: bool = missing.append("MobileHudContent")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
	if not is_instance_valid(_viewport_utility):
		var _viewport_appended: bool = missing.append("GFViewportUtility")
	if missing.is_empty():
		return true
	push_error("[GameplayResponsiveLayoutController] 缺少必需依赖：%s。" % ", ".join(missing))
	return false


func _bind_runtime_signals() -> void:
	var _root_resize_connection: GFSignalConnection = _signal_utility.connect_signal(
		_root_control.resized,
		_queue_layout_update,
		self
	)
	var _mobile_minimum_connection: GFSignalConnection = _signal_utility.connect_signal(
		_mobile_hud_content.minimum_size_changed,
		_queue_layout_update,
		self
	)
	var _replay_visibility_connection: GFSignalConnection = _signal_utility.connect_signal(
		_replay_controls.visibility_changed,
		_queue_layout_update,
		self
	)


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_current_layout")


func _apply_current_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree() or not _has_required_dependencies():
		return
	var prefer_compact: bool = prefer_compact_layout_on_mobile and _is_mobile_runtime()
	var next_mode: LayoutMode = classify_layout(_root_control.size, prefer_compact)
	_current_layout_mode = next_mode
	match next_mode:
		LayoutMode.DESKTOP:
			_apply_desktop_layout()
		LayoutMode.COMPACT_LANDSCAPE:
			_apply_compact_landscape_layout()
		LayoutMode.PORTRAIT:
			_apply_portrait_layout()


func _apply_desktop_layout() -> void:
	_restore_status_to_left_column()
	_mobile_hud_host.visible = false
	_left_column.visible = true
	_right_column.visible = false
	_columns_container.add_theme_constant_override("separation", _DESKTOP_COLUMN_SEPARATION)
	_left_column.custom_minimum_size.x = _DESKTOP_LEFT_COLUMN_WIDTH
	_board_viewport.custom_minimum_size = _DESKTOP_BOARD_MINIMUM
	_apply_main_safe_area_margins({
		"top": _DESKTOP_MARGIN_VERTICAL,
		"left": _DESKTOP_MARGIN_HORIZONTAL,
		"bottom": _DESKTOP_MARGIN_VERTICAL,
		"right": _DESKTOP_MARGIN_HORIZONTAL,
	})


func _apply_compact_landscape_layout() -> void:
	_restore_status_to_left_column()
	_mobile_hud_host.visible = false
	_left_column.visible = true
	_right_column.visible = false
	_columns_container.add_theme_constant_override("separation", _COMPACT_COLUMN_SEPARATION)
	_left_column.custom_minimum_size.x = _COMPACT_LEFT_COLUMN_WIDTH
	_board_viewport.custom_minimum_size = _COMPACT_BOARD_MINIMUM
	_apply_main_safe_area_margins({
		"top": _COMPACT_MARGIN_VERTICAL,
		"left": _COMPACT_MARGIN_HORIZONTAL,
		"bottom": _COMPACT_MARGIN_VERTICAL,
		"right": _COMPACT_MARGIN_HORIZONTAL,
	})


func _apply_portrait_layout() -> void:
	_move_status_to_mobile_host()
	_left_column.visible = false
	_right_column.visible = false
	_columns_container.add_theme_constant_override("separation", 0)
	_board_viewport.custom_minimum_size = _PORTRAIT_BOARD_MINIMUM
	_mobile_hud_host.visible = true
	_sync_mobile_hud_geometry()


func _restore_status_to_left_column() -> void:
	if _hud.get_parent() != _left_column:
		_hud.reparent(_left_column, false)
	if _replay_controls.get_parent() != _left_column:
		_replay_controls.reparent(_left_column, false)
	_left_column.move_child(_hud, 0)
	_left_column.move_child(_replay_controls, 1)
	_hud.set_compact_mode(false)


func _move_status_to_mobile_host() -> void:
	if _hud.get_parent() != _mobile_hud_content:
		_hud.reparent(_mobile_hud_content, false)
	if _replay_controls.get_parent() != _mobile_hud_content:
		_replay_controls.reparent(_mobile_hud_content, false)
	_mobile_hud_content.move_child(_hud, 0)
	_mobile_hud_content.move_child(_replay_controls, 1)
	_hud.set_compact_mode(true)


func _sync_mobile_hud_geometry() -> void:
	var safe_area: Dictionary = _viewport_utility.get_display_safe_area_margins(
		_root_control.get_viewport()
	)
	var safe_top: float = GFVariantData.get_option_float(safe_area, "top")
	var safe_left: float = GFVariantData.get_option_float(safe_area, "left")
	var safe_right: float = GFVariantData.get_option_float(safe_area, "right")
	var host_height: float = maxf(
		_mobile_hud_host.get_combined_minimum_size().y,
		_MOBILE_HUD_MINIMUM_HEIGHT
	)
	var host_top: float = safe_top + _MOBILE_HUD_TOP_GAP
	_mobile_hud_host.offset_left = safe_left + _PORTRAIT_MARGIN_HORIZONTAL
	_mobile_hud_host.offset_top = host_top
	_mobile_hud_host.offset_right = -(safe_right + _PORTRAIT_MARGIN_HORIZONTAL)
	_mobile_hud_host.offset_bottom = host_top + host_height
	_apply_main_safe_area_margins({
		"top": _MOBILE_HUD_TOP_GAP + host_height + _MOBILE_HUD_BOARD_GAP,
		"left": _PORTRAIT_MARGIN_HORIZONTAL,
		"bottom": _PORTRAIT_MARGIN_BOTTOM,
		"right": _PORTRAIT_MARGIN_HORIZONTAL,
	})


func _apply_main_safe_area_margins(extra_margins: Dictionary) -> void:
	var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
		_margin_container,
		_root_control.get_viewport(),
		extra_margins
	)


func _is_mobile_runtime() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("android")
		or OS.has_feature("ios")
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())
	)


func _get_control_host() -> Control:
	var host_value: Node = get_host_as(Control)
	if host_value is Control:
		var control: Control = host_value
		return control
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


func _get_panel_container(path: NodePath) -> PanelContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is PanelContainer:
		var container: PanelContainer = node_value
		return container
	return null


func _get_hud(path: NodePath) -> Hud:
	var node_value: Node = get_node_or_null(path)
	if node_value is Hud:
		var hud: Hud = node_value
		return hud
	return null


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
