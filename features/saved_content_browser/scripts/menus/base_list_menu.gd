## BaseListMenu: 列表类菜单的通用基类。
##
## 封装了加载数据列表、实例化列表项、焦点导航、预览更新以及通用按钮处理的核心逻辑。
## 子类需继承此类并实现特定的数据加载和预览格式化方法。
class_name BaseListMenu
extends GameUiController


# --- 信号 ---

signal content_ready


# --- 常量 ---

const _LIST_REVEAL_OFFSET: Vector2 = Vector2(16.0, 0.0)
const _LIST_REVEAL_STAGGER: float = 0.03
const _LIST_REPEATER_GROUP: StringName = &"base_list_menu_items"
const _VIRTUAL_LIST_ITEM_INDEX_META: StringName = &"base_list_virtual_item_index"
const _VIRTUAL_LIST_OVERSCAN_ITEMS: int = 3
const _VIRTUAL_LIST_ITEM_SEPARATION: float = 10.0
const _VIRTUAL_LIST_MAX_MATERIALIZED_ITEMS: int = 24
const _VIRTUAL_LIST_MAX_POOLED_ITEMS: int = 24
const _LIST_ITEM_DUPLICATE_FLAGS: int = (
	Node.DUPLICATE_GROUPS
	| Node.DUPLICATE_SCRIPTS
	| Node.DUPLICATE_USE_INSTANTIATION
)
const _DESKTOP_SAFE_AREA_MARGINS: Dictionary = {
	"top": 54.0,
	"left": 56.0,
	"bottom": 54.0,
	"right": 56.0,
}
const _DESKTOP_LIST_SURFACE_MINIMUM: Vector2 = Vector2(580.0, 540.0)
const _COMPACT_LIST_SURFACE_HEIGHT: float = 300.0
const _PORTRAIT_LIST_SURFACE_HEIGHT: float = 440.0
const _EMPTY_DESKTOP_LIST_SURFACE_HEIGHT: float = 260.0
const _EMPTY_COMPACT_LIST_SURFACE_HEIGHT: float = 220.0
const _EMPTY_PORTRAIT_LIST_SURFACE_HEIGHT: float = 260.0
const _DESKTOP_PREVIEW_HEIGHT: float = 248.0
const _COMPACT_PREVIEW_HEIGHT: float = 210.0
const _COMPACT_HORIZONTAL_MARGINS: float = 24.0
const _PORTRAIT_HORIZONTAL_MARGINS: float = 32.0
const _COMPACT_SCROLLBAR_RESERVE: float = 14.0


# --- 私有变量 ---

## 用于实例化列表项的场景资源。由子类在 _ready 中初始化。
var _item_scene: PackedScene

## 当前选中的资源数据（如 BookmarkData 或 ReplayData）。
var _selected_resource: Resource = null

## 主动作按钮（如“加载”或“播放”）。由子类在 _ready 中初始化。
var _primary_button: Button

## 删除动作按钮。由子类在 _ready 中初始化。
var _delete_button: Button

## GFRepeaterBinder 使用的离树模板节点。
var _repeater_template: Control = null
var _viewport_utility: GFViewportUtility = null
var _page_scroll: ScrollContainer = null
var _list_scroll: ScrollContainer = null
var _layout_mode: int = GameTaskPageLayoutUtility.LayoutMode.DESKTOP
var _layout_update_queued: bool = false
var _pending_delete_resource: Resource = null
var _delete_state: GameSaveSectionUiOperationState = (
	GameSaveSectionUiOperationState.new()
)
var _delete_signal_utility: GFSignalUtility = null
var _delete_save_graph: GameSaveGraphUtility = null
var _delete_reconciliation_connection: GFSignalConnection = null
var _virtual_list_model: GFVirtualListModel = null
var _virtual_focus_model: GFVirtualListFocusModel = null
var _virtual_list_binder: GFVirtualListBinder = null
var _virtual_data_list: Array[Resource] = []
var _virtual_item_extent: float = 1.0
var _has_revealed_list_once: bool = false
var _empty_state_active: bool = false
var _content_ready: bool = false
var _last_virtual_population_succeeded: bool = false
var _virtual_population_terminal_pending: bool = false


# --- @onready 变量 (节点引用) ---

@onready var items_container: Control = %ItemsContainer
@onready var board_preview_node: BoardPreview = _find_board_preview_node()
@onready var detail_info_label: RichTextLabel = _find_detail_info_label()
@onready var back_button: Button = %BackButton
@onready var page_title: Label = %PageTitle
@onready var _margin_container: MarginContainer = GameTaskPageLayoutUtility.get_margin_container(
	self,
	NodePath("MarginContainer")
)
@onready var _columns_container: HBoxContainer = GameTaskPageLayoutUtility.get_hbox_container(
	self,
	NodePath("MarginContainer/ColumnsContainer")
)
@onready var _left_column: VBoxContainer = %LeftColumn
@onready var _center_column: VBoxContainer = %CenterColumn
@onready var _center_content_holder: CenterContainer = %CenterContentHolder
@onready var _list_surface: PanelContainer = _find_panel_container("ListSurface")
@onready var _preview_container: PanelContainer = _find_panel_container("PreviewContainer")


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_viewport_utility = _get_viewport_utility()
	_setup_delete_reconciliation()
	_page_scroll = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		_columns_container,
		&"HistoryListPageScroll"
	)
	_list_scroll = _find_scroll_container("ScrollContainer")
	_setup_virtual_list_support()
	_apply_semantic_styles()
	_apply_responsive_layout()
	if is_instance_valid(back_button):
		var _connect_result_43: int = back_button.pressed.connect(_on_back_button_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()
	elif what == NOTIFICATION_RESIZED and is_node_ready():
		_queue_layout_update()


func _exit_tree() -> void:
	_content_ready = false
	_virtual_population_terminal_pending = false
	_delete_state.invalidate()
	if is_instance_valid(_delete_signal_utility):
		_delete_signal_utility.disconnect_owner(self)
	_delete_reconciliation_connection = null
	if is_instance_valid(_virtual_list_binder):
		_virtual_list_binder.dispose()
	if is_instance_valid(_repeater_template):
		_repeater_template.free()
	_repeater_template = null


func _unhandled_input(event: InputEvent) -> void:
	if _try_handle_top_modal_cancel(event):
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		var viewport: Viewport = get_viewport()
		if is_instance_valid(viewport):
			viewport.set_input_as_handled()
		return
	if _handle_unfocused_virtual_navigation(event):
		var viewport: Viewport = get_viewport()
		if is_instance_valid(viewport):
			viewport.set_input_as_handled()


# --- 公共方法 ---

## 返回列表数据、空态或首个虚拟窗口是否已完成物化并可接受交互。
func is_content_ready() -> bool:
	return _content_ready


## 返回历史任务页是否应采用紧凑单列布局。
## @param viewport_size: 当前逻辑视口尺寸。
static func is_compact_layout(viewport_size: Vector2) -> bool:
	return GameTaskPageLayoutUtility.is_compact_layout(viewport_size)


## 返回紧凑布局中列表面板应占用的稳定宽度。
##
## 页面级滚动条由当前页拥有，因此宽度预算需要同时扣除安全区留白和滚动条，
## 避免 CenterContainer 在重排瞬间把列表压缩成仅剩文字最小宽度。
## @param viewport_width: 当前页面可用的逻辑视口宽度。
## @param target_layout_mode: GameTaskPageLayoutUtility 定义的目标布局模式。
## @return: 扣除对应安全留白与滚动条预算后的列表面板宽度。
static func get_compact_list_surface_width(
	viewport_width: float,
	target_layout_mode: int
) -> float:
	var horizontal_margins: float = (
		_PORTRAIT_HORIZONTAL_MARGINS
		if target_layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
		else _COMPACT_HORIZONTAL_MARGINS
	)
	return maxf(
		viewport_width - horizontal_margins - _COMPACT_SCROLLBAR_RESERVE,
		320.0
	)


# --- 虚方法 (需子类覆写) ---

## 获取数据列表。
func _get_data_list() -> Array:
	return []


## 设置列表项显示。
func _setup_item(_item: Control, _data: Resource) -> void:
	pass


## 连接列表项的统一交互信号。
func _connect_item_signals(item: Control, _data: Resource) -> void:
	if not item is BaseListMenuItem:
		push_error("[BaseListMenu] 列表项必须继承 BaseListMenuItem。")
		return

	var list_item: BaseListMenuItem = item
	if not list_item.item_selected.is_connected(_on_item_confirmed):
		var _selected_connect_result: int = list_item.item_selected.connect(_on_item_confirmed)
	if not list_item.item_focused.is_connected(_on_item_focused):
		var _focused_connect_result: int = list_item.item_focused.connect(_on_item_focused)


## 更新预览。
func _update_preview(_data: Resource) -> void:
	pass


## 更新静态 UI 文本。
func _update_ui_text() -> void:
	pass


## 创建具体删除事务；子类必须返回一次性类型化操作。
func _do_delete_logic(_data: Resource) -> GameSaveSectionOperation:
	return null


## 执行主按钮逻辑。
func _on_primary_action_triggered(_data: Resource) -> void:
	pass


## 获取列表为空时的提示。
func _get_empty_message() -> String:
	return tr("MSG_NO_DATA")


## 获取未选中时的提示。
func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_ITEM")


## 获取列表为空时显示在预览说明区的引导。
func _get_empty_detail_message() -> String:
	return _get_empty_message()


## 允许具体列表切换仅在有数据时才有意义的视觉元素。
func _on_empty_state_changed(_is_empty: bool) -> void:
	pass


## 获取删除确认提示。
func _get_delete_confirmation_message(_data: Resource) -> String:
	return tr("DELETE_ITEM_CONFIRMATION")


## 获取删除失败提示。
func _get_delete_failure_message(error: Error) -> String:
	return tr("DELETE_ITEM_FAILED") % int(error)


## 返回列表资源的稳定业务标识，用于 late rollback 后恢复原选择。
func _get_data_identity(_data: Resource) -> String:
	return ""


## 是否为当前列表启用 GF 有界虚拟化。只有长列表子类应覆写为 true。
func _uses_virtual_list() -> bool:
	return false


# --- 私有/辅助方法 ---

func _get_game_ui_router_port() -> GameUiRouterPort:
	var utility_value: Object = _find_optional_utility(GameUiRouterPort)
	if utility_value is GameUiRouterPort:
		var ui_router: GameUiRouterPort = utility_value
		return ui_router
	var aliased_utility: GFUIRouterUtility = _get_ui_router_utility()
	if aliased_utility is GameUiRouterPort:
		var game_ui_router: GameUiRouterPort = aliased_utility
		return game_ui_router
	return null


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_label(page_title, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_panel_container(_list_surface)
	style.style_panel_container(
		_preview_container,
		GameUiStyleUtility.SurfaceRole.FIELD
	)
	style.style_button(back_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	if is_instance_valid(_primary_button):
		style.style_button(
			_primary_button,
			GameUiStyleUtility.ButtonRole.PRIMARY
		)
	if is_instance_valid(_delete_button):
		style.style_button(
			_delete_button,
			GameUiStyleUtility.ButtonRole.QUIET
		)


## 统一连接基础按钮信号。子类在设置完按钮引用后应调用此方法。
func _setup_base_signals() -> void:
	if is_instance_valid(_primary_button):
		var _connect_result_109: int = _primary_button.pressed.connect(_on_primary_button_pressed)
	if is_instance_valid(_delete_button):
		var _connect_result_111: int = _delete_button.pressed.connect(_on_delete_button_pressed)


func _setup_delete_reconciliation() -> void:
	_delete_signal_utility = _get_delete_signal_utility()
	_delete_save_graph = _get_delete_save_graph()
	if (
		not is_instance_valid(_delete_signal_utility)
		or not is_instance_valid(_delete_save_graph)
	):
		return
	_delete_reconciliation_connection = _delete_signal_utility.connect_signal(
		_delete_save_graph.section_reconciliation_settled,
		_on_section_reconciliation_settled,
		self
	)

func _find_board_preview_node() -> BoardPreview:
	var node_value: Node = find_child("BoardPreview", true, false)
	if node_value is BoardPreview:
		var board_preview: BoardPreview = node_value
		return board_preview
	return null


func _find_detail_info_label() -> RichTextLabel:
	var node_value: Node = find_child("DetailInfoLabel", true, false)
	if node_value is RichTextLabel:
		var detail_label: RichTextLabel = node_value
		return detail_label
	return null


func _find_panel_container(node_name: String) -> PanelContainer:
	var node_value: Node = find_child(node_name, true, false)
	if node_value is PanelContainer:
		var panel_container: PanelContainer = node_value
		return panel_container
	return null


func _find_scroll_container(node_name: String) -> ScrollContainer:
	var node_value: Node = find_child(node_name, true, false)
	if node_value is ScrollContainer:
		var scroll_container: ScrollContainer = node_value
		return scroll_container
	return null


func _setup_virtual_list_support() -> void:
	if not _uses_virtual_list():
		return
	_virtual_list_model = GFVirtualListModel.new()
	_virtual_list_model.overscan_items = _VIRTUAL_LIST_OVERSCAN_ITEMS
	_virtual_focus_model = GFVirtualListFocusModel.new()
	_virtual_focus_model.wrap_navigation = false
	_virtual_focus_model.auto_focus_on_count_change = true
	var _prepared_binder: GFVirtualListBinder = _ensure_virtual_list_binder()


func _ensure_virtual_list_binder() -> GFVirtualListBinder:
	if (
		is_instance_valid(_virtual_list_binder)
		and not _virtual_list_binder.is_disposed()
	):
		return _virtual_list_binder
	_virtual_list_binder = GFVirtualListBinder.new()
	_virtual_list_binder.max_materialized_items = (
		_VIRTUAL_LIST_MAX_MATERIALIZED_ITEMS
	)
	_virtual_list_binder.max_pooled_items = _VIRTUAL_LIST_MAX_POOLED_ITEMS
	_virtual_list_binder.auto_measure = true
	_virtual_list_binder.auto_reveal_focus = true
	_virtual_list_binder.fill_cross_axis = true
	var sync_callback: Callable = Callable(
		self,
		"_on_virtual_list_sync_completed"
	)
	if not _virtual_list_binder.sync_completed.is_connected(sync_callback):
		var _sync_connect_result: int = _virtual_list_binder.sync_completed.connect(sync_callback)
	return _virtual_list_binder


func _bind_virtual_list_binder(binder: GFVirtualListBinder) -> bool:
	if (
		not is_instance_valid(binder)
		or binder.is_disposed()
		or binder.is_bound()
		or _virtual_data_list.is_empty()
	):
		return false
	return binder.bind(
		self,
		_list_scroll,
		items_container,
		_virtual_list_model,
		Callable(self, "_create_virtual_list_item"),
		Callable(self, "_bind_virtual_list_item"),
		Callable(self, "_unbind_virtual_list_item"),
		Callable(self, "_get_virtual_list_item_identity"),
		_virtual_focus_model,
		Callable(self, "_measure_virtual_list_item"),
		Callable(self, "_get_virtual_list_focus_target")
	)


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var focused_control: Control = _get_page_focus_owner()
	var next_layout_mode: int = GameTaskPageLayoutUtility.classify_layout(size)
	var compact: bool = (
		next_layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	)
	var page_hierarchy_changes: bool = (
		is_instance_valid(_page_scroll)
		and (
			(compact and _columns_container.get_parent() != _page_scroll)
			or (
				not compact
				and _columns_container.get_parent() == _page_scroll
			)
		)
	)
	var rebind_virtual_list: bool = (
		page_hierarchy_changes
		and is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
		and not _virtual_data_list.is_empty()
	)
	if rebind_virtual_list:
		_virtual_list_binder.unbind()
	_layout_mode = next_layout_mode
	_set_page_scroll_enabled(compact)
	if is_instance_valid(_list_scroll):
		_list_scroll.vertical_scroll_mode = (
			ScrollContainer.SCROLL_MODE_AUTO
			if not compact or _uses_virtual_list()
			else ScrollContainer.SCROLL_MODE_DISABLED
		)
		_list_scroll.follow_focus = not compact and not _uses_virtual_list()
	_set_preview_column_compact(compact)
	_columns_container.add_theme_constant_override("separation", 0 if compact else 34)
	_center_column.add_theme_constant_override("separation", 12 if compact else 5)
	_left_column.custom_minimum_size.x = 0.0 if compact else 380.0
	_left_column.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	)
	_center_content_holder.size_flags_vertical = (
		Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	)
	if is_instance_valid(_list_surface):
		var list_height: float = (
			(
				_EMPTY_PORTRAIT_LIST_SURFACE_HEIGHT
				if _empty_state_active
				else _PORTRAIT_LIST_SURFACE_HEIGHT
			)
			if _layout_mode == GameTaskPageLayoutUtility.LayoutMode.PORTRAIT
			else (
				_EMPTY_COMPACT_LIST_SURFACE_HEIGHT
				if _empty_state_active
				else _COMPACT_LIST_SURFACE_HEIGHT
			)
		)
		var compact_list_width: float = get_compact_list_surface_width(
			size.x,
			_layout_mode
		)
		_list_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_surface.custom_minimum_size = (
			Vector2(compact_list_width, list_height)
			if compact
			else Vector2(
				_DESKTOP_LIST_SURFACE_MINIMUM.x,
				(
					_EMPTY_DESKTOP_LIST_SURFACE_HEIGHT
					if _empty_state_active
					else _DESKTOP_LIST_SURFACE_MINIMUM.y
				)
			)
		)
	if is_instance_valid(_preview_container):
		_preview_container.custom_minimum_size.y = (
			_COMPACT_PREVIEW_HEIGHT if compact else _DESKTOP_PREVIEW_HEIGHT
		)
	if is_instance_valid(board_preview_node):
		board_preview_node.preview_size = 194.0 if compact else 232.0
	if is_instance_valid(detail_info_label):
		detail_info_label.custom_minimum_size.y = 90.0 if compact else 106.0
	if is_instance_valid(page_title):
		page_title.add_theme_font_size_override("font_size", 32 if compact else 40)
	var extra_margins: Dictionary = GameTaskPageLayoutUtility.get_safe_area_extra_margins(
		_layout_mode,
		_DESKTOP_SAFE_AREA_MARGINS
	)
	_apply_safe_area_margins(extra_margins)
	if is_instance_valid(_page_scroll) and not compact:
		_page_scroll.scroll_vertical = 0
	if rebind_virtual_list:
		var rebound: bool = _bind_virtual_list_binder(_virtual_list_binder)
		if rebound:
			var _rebound_result: GFVirtualListSyncResult = (
				_virtual_list_binder.sync_now()
			)
		else:
			push_error(
				"[BaseListMenu] 响应式重排后 GFVirtualListBinder 重新绑定失败。"
			)
	_apply_list_focus_order(_get_list_item_controls())
	_restore_focus_after_responsive_layout(focused_control)
	if (
		not rebind_virtual_list
		and is_instance_valid(_virtual_list_binder)
	):
		var _sync_requested: bool = _virtual_list_binder.request_sync()


func _get_page_focus_owner() -> Control:
	var focused_control: Control = get_viewport().gui_get_focus_owner()
	if (
		is_instance_valid(focused_control)
		and (focused_control == self or is_ancestor_of(focused_control))
	):
		return focused_control
	return null


func _restore_focus_after_responsive_layout(focused_control: Control) -> void:
	if (
		is_instance_valid(focused_control)
		and not focused_control.is_queued_for_deletion()
		and focused_control.focus_mode != Control.FOCUS_NONE
		and focused_control.is_visible_in_tree()
	):
		focused_control.grab_focus()
		return
	if not is_instance_valid(focused_control):
		return
	if (
		_uses_virtual_list()
		and is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	):
		return
	var items: Array[Control] = _get_list_item_controls()
	if not items.is_empty():
		items[0].grab_focus()
	elif is_instance_valid(back_button):
		back_button.grab_focus()


## 桌面双栏由内部记录列表独占滚动；紧凑单栏则由整页滚动独占。
## 这样同一轴线上不会同时出现页面和列表两根滚动条。
func _set_page_scroll_enabled(enabled: bool) -> void:
	if not is_instance_valid(_page_scroll) or not is_instance_valid(_margin_container):
		return
	if enabled:
		if _columns_container.get_parent() != _page_scroll:
			_columns_container.reparent(_page_scroll)
		_page_scroll.visible = true
		_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_page_scroll.follow_focus = true
		return

	if _columns_container.get_parent() == _page_scroll:
		var scroll_index: int = _page_scroll.get_index()
		_columns_container.reparent(_margin_container)
		_margin_container.move_child(_columns_container, scroll_index)
	_page_scroll.visible = false
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.follow_focus = false


func _set_preview_column_compact(compact: bool) -> void:
	if compact:
		if _left_column.get_parent() != _center_column:
			_left_column.reparent(_center_column)
		_center_column.move_child(
			_left_column,
			_center_content_holder.get_index() + 1
		)
		return
	if _left_column.get_parent() != _columns_container:
		_left_column.reparent(_columns_container)
	_columns_container.move_child(_left_column, 0)


func _apply_safe_area_margins(extra_margins: Dictionary) -> void:
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
			_margin_container,
			get_viewport(),
			extra_margins
		)
		return
	GameTaskPageLayoutUtility.apply_margin_fallback(_margin_container, extra_margins)


func _get_list_item_controls() -> Array[Control]:
	var items: Array[Control] = []
	if not is_instance_valid(items_container):
		return items
	if (
		_uses_virtual_list()
		and is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	):
		var sync_result: GFVirtualListSyncResult = (
			_virtual_list_binder.get_last_sync_result()
		)
		for item_index: int in sync_result.get_materialized_indices():
			var row_host: Control = (
				_virtual_list_binder.get_materialized_control(item_index)
			)
			var list_item: Control = _get_virtual_list_item_control(row_host)
			if is_instance_valid(list_item):
				items.append(list_item)
		return items
	for child: Node in items_container.get_children():
		if child is BaseListMenuItem:
			var item_control: Control = child
			items.append(item_control)
	return items


func _apply_list_focus_order(items: Array[Control]) -> void:
	if items.is_empty():
		return
	var focus_order: Array[Control] = items.duplicate()
	var compact: bool = _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	if compact:
		for action_control: Control in [_primary_button, _delete_button, back_button]:
			if is_instance_valid(action_control):
				focus_order.append(action_control)
	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(focus_order, {
		"axis": GFControlFocusUtility.AXIS_VERTICAL,
		"wrap": true,
		"wire_tab_order": true,
		"preserve_unwired_directional_neighbors": true,
	})
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error("[BaseListMenu] GF 列表焦点顺序应用失败：%s" % str(focus_report.get("issues", [])))


## 重新填充列表内容。
func _populate_list() -> void:
	_content_ready = false
	_virtual_population_terminal_pending = false
	if not _item_scene:
		push_error("[BaseListMenu] _item_scene 未在子类中初始化。")
		return

	var preferred_virtual_focus: int = GFVirtualListFocusModel.NO_FOCUS
	if is_instance_valid(_virtual_focus_model):
		preferred_virtual_focus = _virtual_focus_model.focused_index
	var reuse_virtual_binding: bool = (
		_uses_virtual_list()
		and is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	)
	if not reuse_virtual_binding:
		await _clear_list_content()

	var raw_data_list: Array = _get_data_list()
	var data_list: Array[Resource] = []
	for data_value: Variant in raw_data_list:
		if data_value is Resource:
			data_list.append(data_value)

	if data_list.is_empty():
		if reuse_virtual_binding:
			await _clear_list_content()
		_handle_empty_list()
		_mark_content_ready()
		return
	_set_empty_state(false)

	var template: Control = _get_repeater_template()
	if not is_instance_valid(template):
		_handle_empty_list()
		return

	if _uses_virtual_list():
		await _populate_virtual_list(data_list, template, preferred_virtual_focus)
		if _last_virtual_population_succeeded:
			_mark_content_ready()
		return

	var created_nodes: Array[Node] = GFRepeaterBinder.rebuild_container(items_container, template, data_list, {
		"group_key": _LIST_REPEATER_GROUP,
		"hide_template": false,
		"clear_existing": true,
		"duplicate_flags": _LIST_ITEM_DUPLICATE_FLAGS,
		"configure_callable": Callable(self, "_configure_repeated_list_item"),
	})

	var items: Array[Control] = []
	for node: Node in created_nodes:
		if node is Control:
			var item_control: Control = node
			items.append(item_control)

	_apply_list_focus_order(items)

	if not items.is_empty():
		items[0].grab_focus()
		_set_selected_item(data_list[0])
		_bind_and_reveal_list_items()
	else:
		_handle_empty_list()
	_mark_content_ready()


## 处理列表为空的情况。
func _handle_empty_list() -> void:
	_reset_virtual_list_for_empty_state()
	var label: Label = Label.new()
	label.name = "EmptyStateLabel"
	label.text = _get_empty_message()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 180
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var style_utility: GameUiStyleUtility = _get_ui_style_utility()
	if is_instance_valid(style_utility):
		style_utility.style_label(label, GameUiStyleUtility.TextRole.MUTED, 18)
	items_container.add_child(label)
	if _uses_virtual_list():
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clear_preview(false)
	_set_empty_state(true)
	_update_action_focus_return_target(null)
	_bind_and_reveal_list_items()
	if is_instance_valid(back_button):
		back_button.grab_focus()


func _set_empty_state(is_empty: bool) -> void:
	_empty_state_active = is_empty
	_on_empty_state_changed(is_empty)
	_apply_responsive_layout()


func _clear_list_content() -> void:
	_virtual_population_terminal_pending = false
	if (
		_uses_virtual_list()
		and is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	):
		_virtual_list_binder.unbind()
	_virtual_data_list.clear()
	if is_instance_valid(_virtual_list_model):
		_virtual_list_model.clear()
	if is_instance_valid(_virtual_focus_model):
		var _focus_cleared: bool = _virtual_focus_model.set_item_count(0)
	if not _uses_virtual_list():
		var _cleared_clones: int = GFRepeaterBinder.clear_clones(
			items_container,
			{"group_key": _LIST_REPEATER_GROUP}
		)

	for child: Node in items_container.get_children():
		if not child.is_queued_for_deletion():
			child.queue_free()

	var frame_wait: Dictionary = await GFAsyncWaitUtility.next_frame({
		"guard_node": self,
	})
	if not GFVariantData.get_option_bool(frame_wait, "completed", false):
		return


func _configure_repeated_list_item(node: Node, item: Variant, _index: int) -> void:
	if not node is Control or not item is Resource:
		return

	var item_control: Control = node
	var data: Resource = item
	_setup_item(item_control, data)
	_connect_item_signals(item_control, data)


func _populate_virtual_list(
	data_list: Array[Resource],
	template: Control,
	preferred_focus_index: int = GFVirtualListFocusModel.NO_FOCUS
) -> void:
	_last_virtual_population_succeeded = false
	_virtual_population_terminal_pending = false
	if not is_instance_valid(_virtual_list_model):
		_virtual_list_model = GFVirtualListModel.new()
	if not is_instance_valid(_virtual_focus_model):
		_virtual_focus_model = GFVirtualListFocusModel.new()
		_virtual_focus_model.wrap_navigation = false
		_virtual_focus_model.auto_focus_on_count_change = true
	var binder: GFVirtualListBinder = _ensure_virtual_list_binder()
	var reuse_binding: bool = binder.is_bound()

	_virtual_data_list = data_list.duplicate()
	_virtual_item_extent = _estimate_virtual_item_extent(template)
	if not reuse_binding:
		_virtual_list_model.clear()
	_virtual_list_model.estimated_item_extent = _virtual_item_extent
	_virtual_list_model.overscan_items = _VIRTUAL_LIST_OVERSCAN_ITEMS
	_virtual_list_model.set_item_count(_virtual_data_list.size())

	var next_focus_index: int = preferred_focus_index
	if next_focus_index == GFVirtualListFocusModel.NO_FOCUS:
		next_focus_index = 0
	else:
		next_focus_index = mini(
			maxi(next_focus_index, 0),
			_virtual_data_list.size() - 1
		)
	var _configured_focus_model: GFVirtualListFocusModel = (
		_virtual_focus_model.configure(_virtual_data_list.size(), {
			"focused_index": next_focus_index,
			"wrap_navigation": false,
			"auto_focus_on_count_change": true,
		})
	)
	if not _virtual_focus_model.has_focus():
		var _focus_first_changed: bool = _virtual_focus_model.focus_first()

	if reuse_binding:
		if not binder.invalidate_items():
			push_error("[BaseListMenu] GFVirtualListBinder 数据失效请求失败。")
			return
	else:
		var focus_owner: Control = _get_page_focus_owner()
		if is_instance_valid(focus_owner):
			focus_owner.release_focus()
		var bound: bool = _bind_virtual_list_binder(binder)
		if not bound:
			push_error(
				"[BaseListMenu] GFVirtualListBinder 绑定失败；回放列表必须使用 ScrollContainer 的直接 absolute Control 子节点。"
			)
			return
	var sync_result: GFVirtualListSyncResult = binder.sync_now()
	if (
		not sync_result.is_successful()
		and sync_result.get_status() != GFVirtualListSyncResult.STATUS_DEFERRED
	):
		push_error(
			"[BaseListMenu] GFVirtualListBinder 首轮同步失败：%s。"
			% String(sync_result.get_status())
		)
		return
	var frame_wait: Dictionary = await GFAsyncWaitUtility.next_frame({
		"guard_node": self,
	})
	if not GFVariantData.get_option_bool(frame_wait, "completed", false):
		return
	if not binder.is_bound():
		return
	# 第二轮之后才接受内容就绪终态：首轮成功仍可能触发行高测量与下一轮同步。
	# DEFERRED 不是成功，后续由 sync_completed 的首个明确成功结果完成水合屏障。
	_virtual_population_terminal_pending = true
	var settled_result: GFVirtualListSyncResult = binder.sync_now()
	if (
		not settled_result.is_successful()
		and settled_result.get_status() != GFVirtualListSyncResult.STATUS_DEFERRED
	):
		# sync_now() 会同步发出 sync_completed；仅在信号未完成收口时兜底。
		if _virtual_population_terminal_pending:
			_virtual_population_terminal_pending = false
			push_error(
				"[BaseListMenu] GFVirtualListBinder 稳定同步失败：%s。"
				% String(settled_result.get_status())
			)


func _mark_content_ready() -> void:
	if _content_ready:
		return
	_content_ready = true
	content_ready.emit()


func _estimate_virtual_item_extent(template: Control) -> float:
	var row_extent: float = maxf(template.custom_minimum_size.y, 1.0)
	return row_extent + _VIRTUAL_LIST_ITEM_SEPARATION


func _create_virtual_list_item() -> Control:
	var template: Control = _get_repeater_template()
	if not is_instance_valid(template):
		return null
	var duplicate_result: Variant = template.duplicate(_LIST_ITEM_DUPLICATE_FLAGS)
	if not duplicate_result is BaseListMenuItem:
		if duplicate_result is Node and is_instance_valid(duplicate_result):
			var duplicate_node: Node = duplicate_result
			duplicate_node.free()
		return null
	var item_control: BaseListMenuItem = duplicate_result
	var row_host: Control = Control.new()
	row_host.name = "VirtualListRow"
	row_host.focus_mode = Control.FOCUS_NONE
	row_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_host.custom_minimum_size.y = _estimate_virtual_item_extent(item_control)
	row_host.add_child(item_control)
	item_control.set_anchors_preset(Control.PRESET_TOP_WIDE)
	item_control.offset_left = 0.0
	item_control.offset_top = 0.0
	item_control.offset_right = 0.0
	item_control.offset_bottom = maxf(
		item_control.get_combined_minimum_size().y,
		item_control.custom_minimum_size.y
	)
	return row_host


func _get_virtual_list_item_control(row_host: Control) -> Control:
	if not is_instance_valid(row_host):
		return null
	if row_host is BaseListMenuItem:
		return row_host
	for child: Node in row_host.get_children():
		if child is BaseListMenuItem:
			var item_control: Control = child
			return item_control
	return null


func _bind_virtual_list_item(
	row_host: Control,
	item_index: int,
	_item_id: Variant
) -> bool:
	if item_index < 0 or item_index >= _virtual_data_list.size():
		return false
	var item_control: Control = _get_virtual_list_item_control(row_host)
	if not is_instance_valid(item_control):
		return false
	item_control.set_meta(_VIRTUAL_LIST_ITEM_INDEX_META, item_index)
	item_control.set_meta(GFRepeaterBinder.META_INDEX, item_index)
	var input_callback: Callable = Callable(
		self,
		"_on_virtual_item_gui_input"
	).bind(item_control)
	if not item_control.gui_input.is_connected(input_callback):
		var _input_connect_result: int = item_control.gui_input.connect(
			input_callback
		)
	var minimum_changed_callback: Callable = Callable(
		self,
		"_on_virtual_item_minimum_size_changed"
	)
	if not item_control.minimum_size_changed.is_connected(
		minimum_changed_callback
	):
		var _minimum_connect_result: int = item_control.minimum_size_changed.connect(minimum_changed_callback)
	var data: Resource = _virtual_data_list[item_index]
	_setup_item(item_control, data)
	_connect_item_signals(item_control, data)
	return true


func _unbind_virtual_list_item(
	row_host: Control,
	_item_index: int,
	_item_id: Variant
) -> void:
	var item_control: Control = _get_virtual_list_item_control(row_host)
	if not is_instance_valid(item_control):
		return
	item_control.remove_meta(_VIRTUAL_LIST_ITEM_INDEX_META)
	item_control.remove_meta(GFRepeaterBinder.META_INDEX)
	if item_control is BaseListMenuItem:
		var list_item: BaseListMenuItem = item_control
		list_item.on_gf_pool_release()


func _get_virtual_list_item_identity(item_index: int) -> Variant:
	if item_index < 0 or item_index >= _virtual_data_list.size():
		return ""
	return _get_data_identity(_virtual_data_list[item_index])


func _measure_virtual_list_item(
	row_host: Control,
	_item_index: int,
	_item_id: Variant
) -> float:
	var item_control: Control = _get_virtual_list_item_control(row_host)
	if not is_instance_valid(item_control):
		return _virtual_item_extent
	var item_extent: float = maxf(
		maxf(
			item_control.get_combined_minimum_size().y,
			item_control.custom_minimum_size.y
		),
		1.0
	)
	item_control.offset_bottom = item_extent
	return item_extent + _VIRTUAL_LIST_ITEM_SEPARATION


func _get_virtual_list_focus_target(
	row_host: Control,
	_item_index: int,
	_item_id: Variant
) -> Control:
	return _get_virtual_list_item_control(row_host)


func _on_virtual_item_minimum_size_changed() -> void:
	if (
		is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	):
		var _measurement_requested: bool = (
			_virtual_list_binder.request_measurement()
		)


func _on_virtual_list_sync_completed(
	result: GFVirtualListSyncResult
) -> void:
	if result == null:
		return
	if not result.is_successful():
		if (
			_virtual_population_terminal_pending
			and result.get_status() != GFVirtualListSyncResult.STATUS_DEFERRED
		):
			_virtual_population_terminal_pending = false
			push_error(
				"[BaseListMenu] GFVirtualListBinder 延迟同步失败：%s。"
				% String(result.get_status())
			)
		return
	if (
		_virtual_population_terminal_pending
		and is_instance_valid(_virtual_focus_model)
		and _virtual_focus_model.has_focus()
		and _virtual_focus_model.focused_index >= 0
		and _virtual_focus_model.focused_index < _virtual_data_list.size()
	):
		_set_selected_item(
			_virtual_data_list[_virtual_focus_model.focused_index]
		)
	var items: Array[Control] = _get_list_item_controls()
	_apply_list_focus_order(items)
	_apply_virtual_selection_visuals()
	_bind_and_reveal_list_items()
	if _virtual_population_terminal_pending:
		_virtual_population_terminal_pending = false
		_last_virtual_population_succeeded = true
		_mark_content_ready()


func _apply_virtual_selection_visuals() -> void:
	var selected_target: Control = null
	for item_control: Control in _get_list_item_controls():
		if not item_control is BaseListMenuItem:
			continue
		var list_item: BaseListMenuItem = item_control
		var is_selected: bool = list_item.get_data() == _selected_resource
		list_item.set_selected(is_selected)
		if is_selected:
			selected_target = list_item
	_update_action_focus_return_target(selected_target)


func _reset_virtual_list_for_empty_state() -> void:
	if not _uses_virtual_list():
		return
	if (
		is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	):
		_virtual_list_binder.unbind()
	_virtual_data_list.clear()
	if is_instance_valid(_virtual_list_model):
		_virtual_list_model.clear()
	if is_instance_valid(_virtual_focus_model):
		var _focus_changed: bool = _virtual_focus_model.set_item_count(0)


func _get_virtual_item_index(item_control: Control) -> int:
	if (
		not is_instance_valid(item_control)
		or not item_control.has_meta(_VIRTUAL_LIST_ITEM_INDEX_META)
	):
		return GFVirtualListFocusModel.NO_FOCUS
	return GFVariantData.to_int(
		item_control.get_meta(_VIRTUAL_LIST_ITEM_INDEX_META),
		GFVirtualListFocusModel.NO_FOCUS
	)


func _project_virtual_focus(item_index: int) -> void:
	if (
		not is_instance_valid(_virtual_focus_model)
		or not _virtual_focus_model.is_focusable(item_index)
	):
		return
	var _focus_changed: bool = _virtual_focus_model.set_focused_index(
		item_index
	)
	if (
		is_instance_valid(_virtual_list_binder)
		and _virtual_list_binder.is_bound()
	):
		var _scroll_requested: bool = _virtual_list_binder.scroll_to_item(
			item_index,
			GFVirtualListBinder.ScrollAlignment.NEAREST
		)


func _move_virtual_focus_from(item_index: int, step: int) -> bool:
	if not is_instance_valid(_virtual_focus_model):
		return false
	var _focus_changed_to_source: bool = _virtual_focus_model.set_focused_index(
		item_index
	)
	if not _virtual_focus_model.move_focus(step):
		return false
	return true


func _handle_unfocused_virtual_navigation(event: InputEvent) -> bool:
	if (
		not _uses_virtual_list()
		or not is_instance_valid(_virtual_focus_model)
		or not _virtual_focus_model.has_focus()
	):
		return false
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		return false
	if event.is_action_pressed("ui_down"):
		return _move_virtual_focus_from(
			_virtual_focus_model.focused_index,
			1
		)
	if event.is_action_pressed("ui_up"):
		return _move_virtual_focus_from(
			_virtual_focus_model.focused_index,
			-1
		)
	return false


## 集中处理选中逻辑。
func _set_selected_item(data: Resource) -> void:
	var selection_changed: bool = _selected_resource != data
	_selected_resource = data
	_update_preview(data)
	if selection_changed:
		_play_preview_content_switch()
	_update_action_buttons()

	var target_node: Control = null
	for item_control: Control in _get_list_item_controls():
		if not item_control is BaseListMenuItem:
			continue
		var list_item: BaseListMenuItem = item_control
		if list_item.get_data() == data:
			list_item.set_selected(true)
			target_node = list_item
		else:
			list_item.set_selected(false)

	_update_action_focus_return_target(target_node)


## 让右侧动作完成后返回当前选中项；纵向列表顺序由 GFControlFocusUtility 拥有。
func _update_action_focus_return_target(target_node: Control) -> void:
	var target: Control = target_node
	if not is_instance_valid(target):
		var materialized_items: Array[Control] = _get_list_item_controls()
		if not materialized_items.is_empty():
			target = materialized_items[0]

	_set_left_focus_target(_primary_button, target)
	_set_left_focus_target(_delete_button, target)
	_set_left_focus_target(back_button, target)


func _set_left_focus_target(source: Control, target: Control) -> void:
	if not is_instance_valid(source):
		return
	if not is_instance_valid(target):
		source.focus_neighbor_left = NodePath("")
		return
	source.focus_neighbor_left = source.get_path_to(target)


## 更新按钮可用状态。
func _update_action_buttons() -> void:
	var has_selection: bool = _selected_resource != null
	var operation_blocked: bool = _delete_state.is_blocked()
	if is_instance_valid(_primary_button):
		_primary_button.disabled = not has_selection or operation_blocked
	if is_instance_valid(_delete_button):
		_delete_button.disabled = not has_selection or operation_blocked


func _bind_and_reveal_list_items() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var _bound_count: int = motion_utility.bind_interactive_controls(items_container)
	if _has_revealed_list_once:
		return
	var reveal_count: int = motion_utility.play_children_reveal(
		items_container,
		_LIST_REVEAL_OFFSET,
		_LIST_REVEAL_STAGGER
	)
	_has_revealed_list_once = reveal_count > 0


func _play_preview_content_switch() -> void:
	var motion_utility: GameUiMotionUtility = _get_game_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return
	if is_instance_valid(_preview_container) and _preview_container.visible:
		var _preview_tween: Tween = motion_utility.play_content_switch(
			_preview_container
		)


func _get_game_ui_motion_utility() -> GameUiMotionUtility:
	var motion_value: Object = _get_ui_motion_utility()
	if motion_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = motion_value
		return motion_utility
	return null


func _get_mode_catalog_utility() -> GameModeCatalogUtility:
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = utility_value
		return mode_catalog
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _get_delete_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_delete_save_graph() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = utility_value
		return save_graph
	return null


func _format_datetime(timestamp: int) -> String:
	var clock: GameClockUtility = _get_clock_utility()
	if is_instance_valid(clock):
		return clock.format_datetime(timestamp)
	return GameClockUtility.format_datetime_value(timestamp)


func _get_mode_config(config_path: String) -> GameModeConfig:
	if config_path.is_empty():
		return null

	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog_utility()
	if not is_instance_valid(mode_catalog):
		push_error("[BaseListMenu] GameModeCatalogUtility 未注册，无法加载模式配置：%s。" % config_path)
		return null

	return mode_catalog.get_config(config_path)


func _get_scene_router_system() -> GameSceneRouterPort:
	var system_value: Object = get_system(GameSceneRouterPort)
	if system_value is GameSceneRouterPort:
		var scene_router: GameSceneRouterPort = system_value
		return scene_router
	return null


func _get_repeater_template() -> Control:
	if is_instance_valid(_repeater_template):
		return _repeater_template

	var item_node: Node = _item_scene.instantiate()
	if item_node is Control:
		var item_control: Control = item_node
		_repeater_template = item_control
		return _repeater_template

	if is_instance_valid(item_node):
		push_error("[BaseListMenu] 列表项场景必须实例化为 Control。")
		item_node.free()
	return null


## 清空预览区域。
## @param show_selection_hint: true 显示“请选择”提示；空列表时改用空态引导。
func _clear_preview(show_selection_hint: bool = true) -> void:
	detail_info_label.text = (
		_get_select_hint_message()
		if show_selection_hint
		else _get_empty_detail_message()
	)
	if is_instance_valid(board_preview_node):
		board_preview_node.clear()
	_selected_resource = null
	_update_action_buttons()


func _show_delete_error(error: Error) -> GFModalResult:
	return await _show_delete_message(_get_delete_failure_message(error))


func _show_delete_outcome_unknown(
	result: GameSaveSectionResult
) -> GFModalResult:
	if result == null:
		return null
	return await _show_delete_message("%s\n%s" % [
		_get_delete_failure_message(result.get_error_code()),
		tr("LIST_DELETE_PERSISTENCE_OUTCOME_UNKNOWN"),
	])


func _show_delete_reconciliation_result(
	status: StringName,
	candidate_persisted: bool,
	memory_rolled_back: bool
) -> GFModalResult:
	if not _delete_state.claim_reconciliation_prompt():
		return null
	var message: String = ""
	if candidate_persisted and status == &"late_success":
		message = tr(
			"LIST_DELETE_RECONCILIATION_SUCCEEDED"
		)
	elif memory_rolled_back:
		message = tr(
			"LIST_DELETE_RECONCILIATION_ROLLED_BACK"
		)
	else:
		message = tr(
			"LIST_DELETE_RECONCILIATION_UNRESOLVED"
		)
	return await _show_delete_message(message)


func _show_delete_message(message: String) -> GFModalResult:
	var ui_router: GameUiRouterPort = _get_game_ui_router_port()
	if not is_instance_valid(ui_router) or not is_inside_tree():
		return null
	var config: GFModalConfig = (
		GameUiRouterPort.make_acknowledgement_modal_config(
			tr("DELETE_FAILED_TITLE"),
			message,
			tr("DIALOG_ACKNOWLEDGE_ACTION")
		)
	)
	return await ui_router.show_modal_async(
		self,
		config,
		{&"source": &"base_list_delete"}
	)


func _get_materialized_resource_by_identity(identity: String) -> Resource:
	if identity.is_empty():
		return null
	if is_instance_valid(items_container):
		for item_control: Control in _get_list_item_controls():
			if not item_control is BaseListMenuItem:
				continue
			var list_item: BaseListMenuItem = item_control
			var data: Resource = list_item.get_data()
			if is_instance_valid(data) and _get_data_identity(data) == identity:
				return data
	for data: Resource in _virtual_data_list:
		if is_instance_valid(data) and _get_data_identity(data) == identity:
			return data
	return null


func _is_current_delete_operation(token: int) -> bool:
	return _delete_state.is_current(token, self)


# --- 信号处理函数 ---

func _on_section_reconciliation_settled(evidence: Dictionary) -> void:
	var settlement: Dictionary = _delete_state.settle_reconciliation(evidence)
	if settlement.is_empty():
		return
	var operation_token: int = GFVariantData.get_option_int(settlement, &"token", 0)
	var context: Dictionary = GFVariantData.get_option_dictionary(
		settlement,
		&"context"
	)
	var resource_identity: String = GFVariantData.get_option_string(
		context,
		&"resource_identity"
	)
	var status: StringName = GFVariantData.get_option_string_name(
		settlement,
		&"status"
	)
	var candidate_persisted: bool = GFVariantData.get_option_bool(
		settlement,
		&"candidate_persisted",
		false
	)
	var memory_rolled_back: bool = GFVariantData.get_option_bool(
		settlement,
		&"memory_rolled_back",
		false
	)
	if candidate_persisted:
		_selected_resource = null
	await _populate_list()
	if not _is_current_delete_operation(operation_token):
		return
	if memory_rolled_back:
		var restored_resource: Resource = _get_materialized_resource_by_identity(
			resource_identity
		)
		if is_instance_valid(restored_resource):
			_set_selected_item(restored_resource)
	if not _delete_state.finish_reconciliation(operation_token):
		return
	_delete_state.clear_context()
	_update_action_buttons()
	var _modal_result: GFModalResult = await _show_delete_reconciliation_result(
		status,
		candidate_persisted,
		memory_rolled_back
	)
	if not _is_current_delete_operation(operation_token):
		return


func _on_virtual_item_gui_input(
	event: InputEvent,
	item_control: Control
) -> void:
	var item_index: int = _get_virtual_item_index(item_control)
	if item_index == GFVirtualListFocusModel.NO_FOCUS:
		return
	if event.is_action_pressed("ui_down"):
		if _move_virtual_focus_from(item_index, 1):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _move_virtual_focus_from(item_index, -1):
			get_viewport().set_input_as_handled()


func _on_item_focused(data: Resource) -> void:
	if _delete_state.is_blocked():
		return
	if _uses_virtual_list() and is_instance_valid(_virtual_focus_model):
		var item_index: int = _virtual_data_list.find(data)
		if item_index >= 0:
			var _focus_changed: bool = _virtual_focus_model.set_focused_index(
				item_index
			)
	if _selected_resource != data:
		_set_selected_item(data)


func _on_item_confirmed(data: Resource) -> void:
	if _delete_state.is_blocked():
		return
	_set_selected_item(data)


func _on_primary_button_pressed() -> void:
	if not _delete_state.is_blocked() and _selected_resource:
		_on_primary_action_triggered(_selected_resource)


func _on_delete_button_pressed() -> void:
	if _delete_state.is_blocked():
		return
	if not is_instance_valid(_selected_resource):
		return
	if is_instance_valid(_pending_delete_resource):
		return
	_pending_delete_resource = _selected_resource
	var ui_router: GameUiRouterPort = _get_game_ui_router_port()
	if not is_instance_valid(ui_router) or not is_inside_tree():
		_on_delete_canceled()
		return
	var config: GFModalConfig = GameUiRouterPort.make_confirmation_modal_config(
		tr("DELETE_CONFIRM_TITLE"),
		_get_delete_confirmation_message(_pending_delete_resource),
		tr("DELETE_CONFIRM_ACTION"),
		tr("DELETE_CANCEL_ACTION")
	)
	var result: GFModalResult = await ui_router.show_modal_async(
		self,
		config,
		{&"source": &"base_list_delete"}
	)
	if not is_inside_tree():
		return
	if result != null and result.status == GFModalResult.STATUS_CONFIRMED:
		await _on_delete_confirmed()
	else:
		_on_delete_canceled()


func _on_delete_confirmed() -> void:
	if _delete_state.is_blocked():
		return
	var resource_to_delete: Resource = _pending_delete_resource
	_pending_delete_resource = null
	if not is_instance_valid(resource_to_delete):
		return

	var operation_token: int = _delete_state.begin({
		&"resource_identity": _get_data_identity(resource_to_delete),
	})
	_update_action_buttons()
	var operation: GameSaveSectionOperation = _do_delete_logic(
		resource_to_delete
	)
	var result: GameSaveSectionResult = (
		await operation.await_result() if operation != null else null
	)
	if not _is_current_delete_operation(operation_token):
		return
	if not _delete_state.finish_request(operation_token):
		return
	if result == null:
		_delete_state.clear_context()
		_update_action_buttons()
		var _modal_result: GFModalResult = await _show_delete_error(
			ERR_UNAVAILABLE
		)
		if not _is_current_delete_operation(operation_token):
			return
		return
	if result.requires_reconciliation():
		if not _delete_state.begin_reconciliation(result):
			return
		_update_action_buttons()
		var last_evidence: Dictionary = {}
		if is_instance_valid(_delete_save_graph):
			last_evidence = (
				_delete_save_graph.get_last_section_reconciliation_evidence()
			)
		if _delete_state.matches_reconciliation_evidence(last_evidence):
			await _on_section_reconciliation_settled(last_evidence)
		else:
			var _modal_result: GFModalResult = (
				await _show_delete_outcome_unknown(result)
			)
			if not _is_current_delete_operation(operation_token):
				return
		return
	if not result.is_successful():
		_delete_state.clear_context()
		var delete_error: Error = result.get_error_code()
		push_error("[BaseListMenu] 删除操作失败，错误码：%d。" % int(delete_error))
		_update_action_buttons()
		var _modal_result: GFModalResult = await _show_delete_error(delete_error)
		if not _is_current_delete_operation(operation_token):
			return
		return
	_selected_resource = null
	_delete_state.clear_context()
	await _populate_list()
	if _is_current_delete_operation(operation_token):
		_update_action_buttons()


func _on_delete_canceled() -> void:
	_pending_delete_resource = null


func _on_back_button_pressed() -> void:
	var router: GameSceneRouterPort = _get_scene_router_system()
	if is_instance_valid(router):
		router.return_to_main_menu()
