## GameModalRoutePanel: 项目主题化的 GF 通用 modal 路由面板。
##
## GFModalConfig 是唯一输入协议，GFModalResult 是唯一输出协议。面板只解释项目
## 视觉角色；路由栈、取消请求与焦点恢复仍由 GFUIUtility / GameUiRouterUtility 管理。
class_name GameModalRoutePanel
extends GameUiController


# --- 信号 ---

signal result_resolved(result: GFModalResult)


# --- 常量 ---

const ACTION_ROLE_PRIMARY: StringName = &"primary"
const ACTION_ROLE_SECONDARY: StringName = &"secondary"
const ACTION_ROLE_QUIET: StringName = &"quiet"
const _MINIMUM_TOUCH_TARGET_SIZE: float = 44.0
const _MINIMUM_ACTION_WIDTH: float = 112.0
const _PREFERRED_SURFACE_WIDTH: float = 520.0
const _PREFERRED_MESSAGE_WIDTH: float = 420.0
const _OUTER_HORIZONTAL_MARGIN: float = 24.0
const _INNER_HORIZONTAL_MARGIN: float = 24.0
const _ACTION_SEPARATION: float = 12.0


# --- 私有变量 ---

var _config: GFModalConfig = null
var _context: Dictionary = {}
var _resolved_result: GFModalResult = null
var _pending_result: GFModalResult = null
var _closing: bool = false
var _close_retry_queued: bool = false
var _waiting_for_top_to_close: bool = false
var _responsive_layout_update_queued: bool = false


# --- @onready 变量 ---

@onready var _backdrop: ColorRect = %DimBackground
@onready var _surface: PanelContainer = %Surface
@onready var _title_label: Label = %TitleLabel
@onready var _message_label: Label = %MessageLabel
@onready var _action_row: BoxContainer = %ActionRow


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _backdrop_connection: int = _backdrop.gui_input.connect(
		_on_backdrop_gui_input
	)
	var _resized_connection: int = resized.connect(
		_queue_responsive_layout_update
	)
	_apply_config()
	_queue_responsive_layout_update()


func _exit_tree() -> void:
	_disconnect_close_retry()
	if _resolved_result != null:
		return
	var result: GFModalResult = _pending_result
	if result == null:
		result = GFModalResult.create(
			GFModalResult.STATUS_DISMISSED,
			&"",
			null,
			{&"reason": &"route_closed"},
			_context
		)
	# GF Router 会先同步 detach panel，再清理自己的历史。延迟兜底结算，
	# 避免 await 续体在 back() 尚未完成时重入同一路由；正常项目关闭路径会
	# 在 _on_popup_route_closed() 中更早且确定地结算。
	call_deferred(&"_publish_result", result)


# --- 公共方法 ---

## 在 GF Router 的 config_callback 阶段配置面板。
## @param config: 要渲染的 GF modal 配置。
## @param context: 原样返回给终态的业务上下文。
## @param route_owner: 拥有本次弹层操作的场景节点。
func configure(
	config: GFModalConfig,
	context: Dictionary = {},
	route_owner: Node = null
) -> void:
	_config = config.duplicate_config() if config != null else GFModalConfig.new()
	_context = context.duplicate(true)
	_bind_owner_lifecycle(route_owner)
	if is_node_ready():
		_apply_config()


## 返回已解析结果；仍在等待用户操作时返回 null。
func get_result() -> GFModalResult:
	return _resolved_result


## 响应 GFUIUtility.request_dismiss_top() 的统一取消协议。
func resolve_cancel() -> void:
	if _resolved_result != null or _closing:
		return
	if _config != null and not _config.dismiss_on_cancel:
		return
	_resolve_and_close(GFModalResult.create(
		GFModalResult.STATUS_CANCELLED,
		&"cancel",
		null,
		{},
		_context
	))


# --- 私有/辅助方法 ---

func _apply_config() -> void:
	if not is_node_ready() or _config == null:
		return
	_title_label.text = _config.title
	_title_label.visible = not _config.title.is_empty()
	_message_label.text = _config.message
	_rebuild_action_buttons(_config.get_actions())
	_apply_semantic_styles()
	_queue_responsive_layout_update()
	if _config.auto_focus:
		call_deferred(&"_focus_initial_action")


func _rebuild_action_buttons(actions: Array[GFModalAction]) -> void:
	for child: Node in _action_row.get_children():
		_action_row.remove_child(child)
		child.queue_free()
	for action: GFModalAction in actions:
		if action == null or action.action_id == &"":
			continue
		var button: Button = Button.new()
		button.name = StringName(
			"Action_%s" % String(action.action_id).to_pascal_case()
		)
		button.text = action.label
		button.custom_minimum_size = Vector2(
			_MINIMUM_ACTION_WIDTH,
			_MINIMUM_TOUCH_TARGET_SIZE
		)
		button.disabled = GFVariantData.get_option_bool(
			action.metadata,
			&"disabled",
			false
		)
		button.set_meta(&"modal_action_id", action.action_id)
		button.set_meta(&"modal_action_grab_focus", action.grab_focus)
		button.set_meta(&"modal_action_disabled", button.disabled)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_action_row.add_child(button)
		var _pressed_connection: int = button.pressed.connect(
			_on_action_pressed.bind(action)
		)
	_queue_responsive_layout_update()


func _queue_responsive_layout_update() -> void:
	if _responsive_layout_update_queued:
		return
	_responsive_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_responsive_layout_update_queued = false
	if not is_node_ready() or not is_inside_tree():
		return
	var available_width: float = maxf(
		size.x - _OUTER_HORIZONTAL_MARGIN * 2.0,
		0.0
	)
	var surface_width: float = minf(_PREFERRED_SURFACE_WIDTH, available_width)
	_surface.custom_minimum_size.x = surface_width
	var content_width: float = maxf(
		surface_width - _INNER_HORIZONTAL_MARGIN * 2.0,
		0.0
	)
	_message_label.custom_minimum_size.x = minf(
		_PREFERRED_MESSAGE_WIDTH,
		content_width
	)
	var action_count: int = _action_row.get_child_count()
	var required_action_width: float = (
		float(action_count) * _MINIMUM_ACTION_WIDTH
		+ float(maxi(action_count - 1, 0)) * _ACTION_SEPARATION
	)
	_action_row.vertical = (
		action_count > 1
		and content_width + 0.5 < required_action_width
	)


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_panel_container(
		_surface,
		GameUiStyleUtility.SurfaceRole.SHELL,
		GameUiStyleUtility.BorderRole.DEFAULT,
		2
	)
	style.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY, 28)
	style.style_label(_message_label, GameUiStyleUtility.TextRole.PRIMARY, 18)
	var actions: Array[GFModalAction] = _config.get_actions()
	for index: int in range(mini(actions.size(), _action_row.get_child_count())):
		var child: Node = _action_row.get_child(index)
		if child is Button:
			var button: Button = child
			style.style_button(button, _get_button_role(actions[index]))


func _get_button_role(action: GFModalAction) -> int:
	var role: StringName = GFVariantData.get_option_string_name(
		action.metadata,
		&"role",
		ACTION_ROLE_SECONDARY
	)
	match role:
		ACTION_ROLE_PRIMARY:
			return GameUiStyleUtility.ButtonRole.PRIMARY
		ACTION_ROLE_QUIET:
			return GameUiStyleUtility.ButtonRole.QUIET
		_:
			return GameUiStyleUtility.ButtonRole.SECONDARY


func _focus_initial_action() -> void:
	if not is_inside_tree() or _resolved_result != null or _closing:
		return
	var fallback: Button = null
	for child: Node in _action_row.get_children():
		if not child is Button:
			continue
		var button: Button = child
		if button.disabled or not button.visible:
			continue
		if fallback == null:
			fallback = button
		if GFVariantData.to_bool(
			button.get_meta(&"modal_action_grab_focus", false),
			false
		):
			button.grab_focus()
			return
	if is_instance_valid(fallback):
		fallback.grab_focus()


func _bind_owner_lifecycle(route_owner: Node) -> void:
	if not is_instance_valid(route_owner):
		return
	var callback: Callable = Callable(self, "_on_owner_tree_exiting")
	if not route_owner.tree_exiting.is_connected(callback):
		var _owner_connection: int = route_owner.tree_exiting.connect(
			callback,
			CONNECT_ONE_SHOT
		)


func _publish_result(result: GFModalResult) -> void:
	if _resolved_result != null or result == null:
		return
	_resolved_result = result
	result_resolved.emit(result)


func _resolve_and_close(
	result: GFModalResult,
	wait_until_top: bool = false
) -> void:
	if result == null or _resolved_result != null or _closing:
		return
	_pending_result = result
	_closing = true
	_set_interaction_enabled(false)
	if not _is_top_popup_panel():
		if wait_until_top:
			_wait_for_top_then_close()
			return
		_on_popup_route_close_failed(GameUiRouterUtility.ROUTE_MODAL_DIALOG)
		return
	if _close_current_popup_route(
		GameUiRouterUtility.ROUTE_MODAL_DIALOG
	):
		return
	_on_popup_route_close_failed(GameUiRouterUtility.ROUTE_MODAL_DIALOG)


func _set_interaction_enabled(enabled: bool) -> void:
	for child: Node in _action_row.get_children():
		if child is Button:
			var button: Button = child
			button.disabled = (
				not enabled
				or GFVariantData.to_bool(
					button.get_meta(&"modal_action_disabled", false),
					false
				)
			)


func _on_popup_route_closed(_expected_route_id: StringName) -> void:
	if not _closing or _pending_result == null:
		return
	var result: GFModalResult = _pending_result
	_pending_result = null
	_closing = false
	_waiting_for_top_to_close = false
	_disconnect_close_retry()
	_publish_result(result)


func _on_popup_route_close_failed(_expected_route_id: StringName) -> void:
	if not _closing:
		return
	if _pending_result != null and not _is_top_popup_panel():
		_wait_for_top_then_close()
		return
	_closing = false
	_pending_result = null
	_waiting_for_top_to_close = false
	_disconnect_close_retry()
	_set_interaction_enabled(true)
	if _config != null and _config.auto_focus:
		call_deferred(&"_focus_initial_action")


func _is_top_popup_panel() -> bool:
	var ui_utility: GFUIUtility = _get_ui_utility()
	return (
		is_instance_valid(ui_utility)
		and ui_utility.get_top_panel(GFUIUtility.Layer.POPUP) == self
	)


func _wait_for_top_then_close() -> void:
	_waiting_for_top_to_close = true
	var ui_utility: GFUIUtility = _get_ui_utility()
	if not is_instance_valid(ui_utility):
		_waiting_for_top_to_close = false
		_closing = false
		_pending_result = null
		_set_interaction_enabled(true)
		if _config != null and _config.auto_focus:
			call_deferred(&"_focus_initial_action")
		return
	var callback: Callable = Callable(self, "_on_ui_navigation_changed")
	if not ui_utility.navigation_changed.is_connected(callback):
		var _navigation_connection: int = ui_utility.navigation_changed.connect(
			callback
		)


func _disconnect_close_retry() -> void:
	_close_retry_queued = false
	var ui_utility: GFUIUtility = _get_ui_utility()
	if not is_instance_valid(ui_utility):
		return
	var callback: Callable = Callable(self, "_on_ui_navigation_changed")
	if ui_utility.navigation_changed.is_connected(callback):
		ui_utility.navigation_changed.disconnect(callback)


func _on_ui_navigation_changed(layer: int, top_panel: Node) -> void:
	if (
		not _waiting_for_top_to_close
		or layer != GFUIUtility.Layer.POPUP
		or top_panel != self
		or _close_retry_queued
	):
		return
	# navigation_changed 在 GF Router.back() 的历史清理前同步发出；下一轮
	# 再重试，避免嵌套 back() 改写上一轮保存的 history_index。
	_close_retry_queued = true
	call_deferred(&"_retry_close_after_becoming_top")


func _retry_close_after_becoming_top() -> void:
	_close_retry_queued = false
	if not _waiting_for_top_to_close or not _closing:
		return
	if not _is_top_popup_panel():
		return
	_waiting_for_top_to_close = false
	_disconnect_close_retry()
	if _close_current_popup_route(GameUiRouterUtility.ROUTE_MODAL_DIALOG):
		return
	_on_popup_route_close_failed(GameUiRouterUtility.ROUTE_MODAL_DIALOG)


# --- 信号处理函数 ---

func _on_action_pressed(action: GFModalAction) -> void:
	if action == null or _resolved_result != null or _closing:
		return
	var result: GFModalResult = action.make_result(_context)
	# 项目适配器只支持“一次动作对应一个终态”。Router 会拒绝非关闭动作；
	# 面板仍做防御性归一化，避免直接配置时留下已结算但无法关闭的弹层。
	_resolve_and_close(result)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if (
		_config == null
		or not _config.dismiss_on_backdrop
		or not event is InputEventMouseButton
	):
		return
	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		if not _closing:
			resolve_cancel()
		accept_event()


func _on_owner_tree_exiting() -> void:
	if _resolved_result != null or _closing:
		return
	_resolve_and_close(GFModalResult.create(
		GFModalResult.STATUS_CANCELLED,
		&"owner_exited",
		null,
		{&"reason": &"owner_exited"},
		_context
	), true)
