## GameTaskPageLayoutUtility: 为菜单与任务页提供统一的响应式布局判定。
##
## 该工具只拥有项目 UI 的布局策略；设备安全区的实际换算和应用继续交给
## GFViewportUtility。缺少框架 Utility 时显式报告且拒绝写入，禁止退回第二套原生实现。
class_name GameTaskPageLayoutUtility
extends RefCounted


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
const _COMPACT_LANDSCAPE_MARGINS: Dictionary = {
	"top": 10.0,
	"left": 12.0,
	"bottom": 10.0,
	"right": 12.0,
}
const _PORTRAIT_MARGINS: Dictionary = {
	"top": 16.0,
	"left": 16.0,
	"bottom": 16.0,
	"right": 16.0,
}


# --- 公共方法 ---

## 根据逻辑视口尺寸选择菜单任务页布局。
## @param viewport_size: 当前逻辑视口尺寸。
## @return: 桌面、紧凑横屏或纵屏布局。
static func classify_layout(viewport_size: Vector2) -> LayoutMode:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return LayoutMode.DESKTOP
	if viewport_size.y >= viewport_size.x * _PORTRAIT_HEIGHT_RATIO:
		return LayoutMode.PORTRAIT
	if (
		viewport_size.x < _DESKTOP_MINIMUM_WIDTH
		or viewport_size.y < _DESKTOP_MINIMUM_HEIGHT
	):
		return LayoutMode.COMPACT_LANDSCAPE
	return LayoutMode.DESKTOP


## 返回指定尺寸是否需要单列或可滚动的紧凑布局。
## @param viewport_size: 当前逻辑视口尺寸。
static func is_compact_layout(viewport_size: Vector2) -> bool:
	return classify_layout(viewport_size) != LayoutMode.DESKTOP


## 从指定根节点安全取得 MarginContainer。
## @param root: 查询起点节点。
## @param node_path: 相对于查询起点的节点路径。
static func get_margin_container(root: Node, node_path: NodePath) -> MarginContainer:
	if not is_instance_valid(root):
		return null
	var node_value: Node = root.get_node_or_null(node_path)
	if node_value is MarginContainer:
		var margin_container: MarginContainer = node_value
		return margin_container
	return null


## 从指定根节点安全取得 HBoxContainer。
## @param root: 查询起点节点。
## @param node_path: 相对于查询起点的节点路径。
static func get_hbox_container(root: Node, node_path: NodePath) -> HBoxContainer:
	if not is_instance_valid(root):
		return null
	var node_value: Node = root.get_node_or_null(node_path)
	if node_value is HBoxContainer:
		var hbox_container: HBoxContainer = node_value
		return hbox_container
	return null


## 返回应叠加在设备安全区之外的页面留白。
## @param mode: 当前响应式布局模式。
## @param desktop_margins: 页面原有桌面留白。
## @return: 可直接传给 GFViewportUtility 的四向边距。
static func get_safe_area_extra_margins(
	mode: LayoutMode,
	desktop_margins: Dictionary
) -> Dictionary:
	match mode:
		LayoutMode.COMPACT_LANDSCAPE:
			return _COMPACT_LANDSCAPE_MARGINS.duplicate(true)
		LayoutMode.PORTRAIT:
			return _PORTRAIT_MARGINS.duplicate(true)
		_:
			return desktop_margins.duplicate(true)


## 在不改写场景资源层级的前提下，为页面内容补一个纵向滚动视口。
## 已经位于 ScrollContainer 下时直接复用原节点。
## @param content: 需要获得纵向滚动父级的页面内容节点。
## @param scroll_name: 新建滚动容器使用的稳定节点名。
static func ensure_vertical_scroll_parent(
	content: Control,
	scroll_name: StringName = &"ResponsiveScroll"
) -> ScrollContainer:
	if not is_instance_valid(content):
		return null
	var current_parent: Node = content.get_parent()
	if current_parent is ScrollContainer:
		var existing_scroll: ScrollContainer = current_parent
		return existing_scroll
	if not current_parent is Container:
		return null

	var parent_container: Container = current_parent
	var content_index: int = content.get_index()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = scroll_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent_container.add_child(scroll)
	parent_container.move_child(scroll, content_index)
	content.reparent(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


## 通过必需的 GFViewportUtility 叠加设备安全区与页面留白。
## @param viewport_utility: Composition Root 注册的 GF 视口 Utility。
## @param margin_container: 要写入主题边距的页面容器。
## @param viewport: 页面所在的逻辑视口。
## @param extra_margins: 包含 left、top、right、bottom 的额外边距。
## @return: GF 报告同时确认 ok 与 applied 时返回 true。
static func apply_required_safe_area_margins(
	viewport_utility: GFViewportUtility,
	margin_container: MarginContainer,
	viewport: Viewport,
	extra_margins: Dictionary
) -> bool:
	if not is_instance_valid(viewport_utility):
		push_warning(
			"[GameTaskPageLayoutUtility] 缺少必需的 GFViewportUtility，拒绝静默降级安全区布局。"
		)
		return false
	var report: Dictionary = viewport_utility.apply_display_safe_area_margins(
		margin_container,
		viewport,
		extra_margins
	)
	var applied: bool = (
		GFVariantData.get_option_bool(report, "ok")
		and GFVariantData.get_option_bool(report, "applied")
	)
	if not applied:
		push_warning(
			"[GameTaskPageLayoutUtility] GFViewportUtility 未能应用安全区布局。"
		)
	return applied
