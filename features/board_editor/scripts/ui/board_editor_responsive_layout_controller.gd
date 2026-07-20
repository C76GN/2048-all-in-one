## BoardEditorResponsiveLayoutController: 管理棋盘编辑器断点、安全区与移动分区。
##
## 桌面同时展示工具、画布和模板库；紧凑横屏与竖屏使用编辑/模板分区，避免
## 固定三栏压缩画布。竖屏把工具放在画布上方，并为系统安全区保留物理边距。
class_name BoardEditorResponsiveLayoutController
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 枚举 ---

enum LayoutMode {
	DESKTOP,
	COMPACT_LANDSCAPE,
	PORTRAIT,
}

enum MobileSection {
	EDITOR,
	LIBRARY,
}


# --- 常量 ---

const _DESKTOP_MINIMUM_WIDTH: float = 1180.0
const _DESKTOP_MINIMUM_HEIGHT: float = 650.0
const _PORTRAIT_HEIGHT_RATIO: float = 1.06
const _DESKTOP_TOOLS_WIDTH: float = 180.0
const _DESKTOP_LIBRARY_WIDTH: float = 280.0
const _COMPACT_TOOLS_WIDTH: float = 168.0
const _DESKTOP_CANVAS_MINIMUM: Vector2 = Vector2(480.0, 420.0)
const _COMPACT_CANVAS_MINIMUM: Vector2 = Vector2(320.0, 320.0)
const _PORTRAIT_CANVAS_MINIMUM: Vector2 = Vector2(0.0, 300.0)
const _DESKTOP_CANCEL_MINIMUM: Vector2 = Vector2(150.0, 48.0)
const _DESKTOP_APPLY_MINIMUM: Vector2 = Vector2(220.0, 48.0)


# --- 导出变量 ---

@export var outer_margin_path: NodePath = NodePath("../OuterMargin")
@export var content_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content"
)
@export var tools_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/Tools"
)
@export var canvas_viewport_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/CanvasViewport"
)
@export var library_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/Library"
)
@export var mobile_sections_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/MobileSections"
)
@export var editor_section_button_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/MobileSections/EditorSectionButton"
)
@export var library_section_button_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/MobileSections/LibrarySectionButton"
)
@export var canvas_hint_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Header/CanvasHintLabel"
)
@export var tool_title_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/Tools/ToolTitle"
)
@export var tool_separator_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/Tools/ToolSeparator"
)
@export var tool_spacer_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/Tools/ToolSpacer"
)
@export var tool_info_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/Tools/ToolInfo"
)
@export var cancel_button_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Footer/CancelButton"
)
@export var apply_button_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Footer/ApplyButton"
)
@export var viewport_controller_path: NodePath = NodePath(
	"../OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/CanvasViewport/BoardEditorViewportController"
)
@export var prefer_compact_layout_on_touch: bool = true


# --- 私有变量 ---

var _root_control: Control
var _outer_margin: MarginContainer
var _content: BoxContainer
var _tools: VBoxContainer
var _canvas_viewport: Control
var _library: VBoxContainer
var _mobile_sections: HBoxContainer
var _editor_section_button: Button
var _library_section_button: Button
var _canvas_hint: CanvasItem
var _tool_title: CanvasItem
var _tool_separator: CanvasItem
var _tool_spacer: CanvasItem
var _tool_info: CanvasItem
var _cancel_button: Button
var _apply_button: Button
var _viewport_controller: BoardEditorViewportController
var _signal_utility: GFSignalUtility
var _viewport_utility: GFViewportUtility
var _platform_utility: GamePlatformUtility
var _current_layout_mode: LayoutMode = LayoutMode.DESKTOP
var _current_mobile_section: MobileSection = MobileSection.EDITOR
var _layout_update_queued: bool = false


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_nodes()
	_resolve_utilities()
	if not _has_required_dependencies():
		return
	_setup_section_buttons()
	_bind_runtime_signals()
	_queue_layout_update()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	super._exit_tree()


# --- 公共方法 ---

## 根据逻辑视口尺寸和设备偏好选择编辑器布局。
## @param viewport_size: 当前逻辑视口尺寸。
## @param prefer_compact: 是否优先采用触屏紧凑布局。
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


## 返回紧凑布局当前显示的功能分区。
func get_mobile_section() -> MobileSection:
	return _current_mobile_section


## 在紧凑布局中显示绘制工具与画布。
func show_editor_section() -> void:
	_current_mobile_section = MobileSection.EDITOR
	_apply_section_visibility()


## 在紧凑布局中显示玩家模板库。
func show_library_section() -> void:
	_current_mobile_section = MobileSection.LIBRARY
	_apply_section_visibility()


# --- 私有/辅助方法 ---

func _resolve_nodes() -> void:
	_root_control = _get_control_host()
	_outer_margin = _get_margin_container(outer_margin_path)
	_content = _get_box_container(content_path)
	_tools = _get_vbox_container(tools_path)
	_canvas_viewport = _get_control(canvas_viewport_path)
	_library = _get_vbox_container(library_path)
	_mobile_sections = _get_hbox_container(mobile_sections_path)
	_editor_section_button = _get_button(editor_section_button_path)
	_library_section_button = _get_button(library_section_button_path)
	_canvas_hint = _get_canvas_item(canvas_hint_path)
	_tool_title = _get_canvas_item(tool_title_path)
	_tool_separator = _get_canvas_item(tool_separator_path)
	_tool_spacer = _get_canvas_item(tool_spacer_path)
	_tool_info = _get_canvas_item(tool_info_path)
	_cancel_button = _get_button(cancel_button_path)
	_apply_button = _get_button(apply_button_path)
	_viewport_controller = _get_viewport_controller(viewport_controller_path)


func _resolve_utilities() -> void:
	_signal_utility = _get_signal_utility()
	_viewport_utility = _get_viewport_utility()
	_platform_utility = _get_platform_utility()


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_root_control):
		var _root_appended: bool = missing.append("BoardEditorDialog")
	if not is_instance_valid(_outer_margin):
		var _margin_appended: bool = missing.append("OuterMargin")
	if not is_instance_valid(_content):
		var _content_appended: bool = missing.append("Content")
	if not is_instance_valid(_tools):
		var _tools_appended: bool = missing.append("Tools")
	if not is_instance_valid(_canvas_viewport):
		var _canvas_appended: bool = missing.append("CanvasViewport")
	if not is_instance_valid(_library):
		var _library_appended: bool = missing.append("Library")
	if not is_instance_valid(_mobile_sections):
		var _sections_appended: bool = missing.append("MobileSections")
	if not is_instance_valid(_editor_section_button):
		var _editor_button_appended: bool = missing.append("EditorSectionButton")
	if not is_instance_valid(_library_section_button):
		var _library_button_appended: bool = missing.append("LibrarySectionButton")
	if not is_instance_valid(_cancel_button):
		var _cancel_appended: bool = missing.append("CancelButton")
	if not is_instance_valid(_apply_button):
		var _apply_appended: bool = missing.append("ApplyButton")
	if not is_instance_valid(_viewport_controller):
		var _controller_appended: bool = missing.append("BoardEditorViewportController")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
	if not is_instance_valid(_viewport_utility):
		var _viewport_appended: bool = missing.append("GFViewportUtility")
	if not is_instance_valid(_platform_utility):
		var _platform_appended: bool = missing.append("GamePlatformUtility")
	if missing.is_empty():
		return true
	push_error("[BoardEditorResponsiveLayoutController] 缺少必需依赖：%s。" % ", ".join(missing))
	return false


func _setup_section_buttons() -> void:
	var section_group: ButtonGroup = ButtonGroup.new()
	section_group.allow_unpress = false
	_editor_section_button.button_group = section_group
	_library_section_button.button_group = section_group
	_editor_section_button.toggle_mode = true
	_library_section_button.toggle_mode = true
	_editor_section_button.set_pressed_no_signal(true)


func _bind_runtime_signals() -> void:
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
	var _editor_connection: GFSignalConnection = _signal_utility.connect_signal(
		_editor_section_button.pressed,
		show_editor_section,
		self
	)
	var _library_connection: GFSignalConnection = _signal_utility.connect_signal(
		_library_section_button.pressed,
		show_library_section,
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
	var prefer_compact: bool = prefer_compact_layout_on_touch and _has_touch_capability()
	_current_layout_mode = classify_layout(_root_control.size, prefer_compact)
	match _current_layout_mode:
		LayoutMode.DESKTOP:
			_apply_desktop_layout()
		LayoutMode.COMPACT_LANDSCAPE:
			_apply_compact_landscape_layout()
		LayoutMode.PORTRAIT:
			_apply_portrait_layout()
	_apply_section_visibility()


func _apply_desktop_layout() -> void:
	_content.vertical = false
	_mobile_sections.visible = false
	_set_tool_support_visible(true)
	_tools.custom_minimum_size = Vector2(_DESKTOP_TOOLS_WIDTH, 0.0)
	_canvas_viewport.custom_minimum_size = _DESKTOP_CANVAS_MINIMUM
	_library.custom_minimum_size = Vector2(_DESKTOP_LIBRARY_WIDTH, 0.0)
	_cancel_button.custom_minimum_size = _DESKTOP_CANCEL_MINIMUM
	_apply_button.custom_minimum_size = _DESKTOP_APPLY_MINIMUM
	_cancel_button.size_flags_horizontal = Control.SIZE_FILL
	_apply_button.size_flags_horizontal = Control.SIZE_FILL
	_apply_safe_area_margins({"top": 24.0, "left": 28.0, "bottom": 24.0, "right": 28.0})


func _apply_compact_landscape_layout() -> void:
	_content.vertical = false
	_mobile_sections.visible = true
	_set_tool_support_visible(false)
	_tools.custom_minimum_size = Vector2(_COMPACT_TOOLS_WIDTH, 0.0)
	_canvas_viewport.custom_minimum_size = _COMPACT_CANVAS_MINIMUM
	_library.custom_minimum_size = Vector2.ZERO
	_cancel_button.custom_minimum_size = Vector2(120.0, 44.0)
	_apply_button.custom_minimum_size = Vector2(180.0, 44.0)
	_cancel_button.size_flags_horizontal = Control.SIZE_FILL
	_apply_button.size_flags_horizontal = Control.SIZE_FILL
	_apply_safe_area_margins({"top": 14.0, "left": 18.0, "bottom": 14.0, "right": 18.0})


func _apply_portrait_layout() -> void:
	_content.vertical = true
	_mobile_sections.visible = true
	_set_tool_support_visible(false)
	_tools.custom_minimum_size = Vector2.ZERO
	_canvas_viewport.custom_minimum_size = _PORTRAIT_CANVAS_MINIMUM
	_library.custom_minimum_size = Vector2.ZERO
	_cancel_button.custom_minimum_size = Vector2(0.0, 44.0)
	_apply_button.custom_minimum_size = Vector2(0.0, 44.0)
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_safe_area_margins({"top": 10.0, "left": 12.0, "bottom": 10.0, "right": 12.0})


func _apply_section_visibility() -> void:
	if _current_layout_mode == LayoutMode.DESKTOP:
		_tools.visible = true
		_canvas_viewport.visible = true
		_library.visible = true
		_queue_canvas_fit()
		return

	var show_editor: bool = _current_mobile_section == MobileSection.EDITOR
	_editor_section_button.set_pressed_no_signal(show_editor)
	_library_section_button.set_pressed_no_signal(not show_editor)
	_tools.visible = show_editor
	_canvas_viewport.visible = show_editor
	_library.visible = not show_editor
	if show_editor:
		_queue_canvas_fit()


func _set_tool_support_visible(is_visible: bool) -> void:
	if is_instance_valid(_canvas_hint):
		_canvas_hint.visible = is_visible
	if is_instance_valid(_tool_title):
		_tool_title.visible = is_visible
	if is_instance_valid(_tool_separator):
		_tool_separator.visible = is_visible
	if is_instance_valid(_tool_spacer):
		_tool_spacer.visible = is_visible
	if is_instance_valid(_tool_info):
		_tool_info.visible = is_visible


func _queue_canvas_fit() -> void:
	if is_instance_valid(_viewport_controller):
		_viewport_controller.call_deferred(&"fit_to_content")


func _apply_safe_area_margins(extra_margins: Dictionary) -> void:
	var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
		_outer_margin,
		_root_control.get_viewport(),
		extra_margins
	)


func _on_platform_context_changed(_context: GFPlatformRuntimeContext) -> void:
	_queue_layout_update()


func _has_touch_capability() -> bool:
	return (
		is_instance_valid(_platform_utility)
		and _platform_utility.has_capability(GamePlatformUtility.CAPABILITY_TOUCH)
	)


func _get_control_host() -> Control:
	var host_value: Node = get_host_as(Control)
	if host_value is Control:
		var host_control: Control = host_value
		return host_control
	return null


func _get_control(path: NodePath) -> Control:
	var node_value: Node = get_node_or_null(path)
	if node_value is Control:
		var control: Control = node_value
		return control
	return null


func _get_canvas_item(path: NodePath) -> CanvasItem:
	var node_value: Node = get_node_or_null(path)
	if node_value is CanvasItem:
		var canvas_item: CanvasItem = node_value
		return canvas_item
	return null


func _get_margin_container(path: NodePath) -> MarginContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is MarginContainer:
		var margin: MarginContainer = node_value
		return margin
	return null


func _get_box_container(path: NodePath) -> BoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is BoxContainer:
		var box: BoxContainer = node_value
		return box
	return null


func _get_hbox_container(path: NodePath) -> HBoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is HBoxContainer:
		var hbox: HBoxContainer = node_value
		return hbox
	return null


func _get_vbox_container(path: NodePath) -> VBoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is VBoxContainer:
		var vbox: VBoxContainer = node_value
		return vbox
	return null


func _get_button(path: NodePath) -> Button:
	var node_value: Node = get_node_or_null(path)
	if node_value is Button:
		var button: Button = node_value
		return button
	return null


func _get_viewport_controller(path: NodePath) -> BoardEditorViewportController:
	var node_value: Node = get_node_or_null(path)
	if node_value is BoardEditorViewportController:
		var controller: BoardEditorViewportController = node_value
		return controller
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


func _get_platform_utility() -> GamePlatformUtility:
	var utility_value: Object = get_utility(GamePlatformUtility, true)
	if utility_value is GamePlatformUtility:
		var platform_utility: GamePlatformUtility = utility_value
		return platform_utility
	return null
