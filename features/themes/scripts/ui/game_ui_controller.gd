## GameUiController: 主题化游戏 UI 宿主，通过内部 GFController 连接 GF 架构。
##
## 适用于菜单、弹窗等 Control 派生节点。主题 Feature 拥有该表现层宿主，
## GFController 负责架构上下文和事件生命周期，主题 Utility 负责视觉与交互动效。
class_name GameUiController
extends Control


# --- 常量 ---

const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload(
	"res://features/themes/scripts/utilities/game_ui_motion_utility.gd"
)
const _GAME_UI_STYLE_UTILITY_SCRIPT: Script = preload(
	"res://features/themes/scripts/utilities/game_ui_style_utility.gd"
)
const _GAME_THEME_UTILITY_SCRIPT: Script = preload(
	"res://features/themes/scripts/utilities/game_theme_utility.gd"
)


# --- 私有变量 ---

var _gf_controller: GFController
var _popup_close_in_progress: bool = false
var _modal_focus_update_queued: bool = false
var _pending_popup_event_architecture: GFArchitecture = null
var _pending_popup_event_id: StringName = &""
var _pending_popup_event_payload: Variant = null


# --- Godot 生命周期方法 ---

func _init() -> void:
	_gf_controller = GFController.new()
	_gf_controller.name = "GFController"
	add_child(_gf_controller, false, Node.INTERNAL_MODE_BACK)


func _enter_tree() -> void:
	call_deferred(&"_apply_default_ui_motion")
	call_deferred(&"_bind_modal_focus_bridge")


func _unhandled_input(event: InputEvent) -> void:
	var _handled: bool = _try_handle_top_modal_cancel(event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_ui_text()


# --- 获取方法 ---

## 获取当前 UI 所属架构；未初始化时返回 null。
func get_architecture_or_null() -> GFArchitecture:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_architecture_or_null()


## 通过类型获取 Model 实例。
## @param model_type: 要查找的 Model 脚本类型。
func get_model(model_type: Script) -> Object:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_model(model_type)


## 通过类型获取 System 实例。
## @param system_type: 要查找的 System 脚本类型。
func get_system(system_type: Script) -> Object:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_system(system_type)


## 通过类型获取 Utility 实例。
## @param utility_type: 要查找的 Utility 脚本类型。
func get_utility(utility_type: Script) -> Object:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_utility(utility_type)


# --- 命令与查询 ---

## 向架构发送命令。
## @param command: 要执行的命令对象。
func send_command(command: Object) -> Variant:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.send_command(command)


## 执行查询并返回结果。
## @param query: 要执行的查询对象。
func send_query(query: Object) -> Variant:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.send_query(query)


# --- 事件系统 ---

## 注册类型事件监听器。
## @param event_type: 类型事件的脚本类型。
## @param listener: 显式的 GF 事件监听契约。
## @param priority: 监听器优先级。
func register_event(event_type: Script, listener: GFEventListener, priority: int = 0) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.register_event(event_type, listener, priority)


## 注销类型事件监听器。
## @param event_type: 类型事件的脚本类型。
## @param listener: 注册时使用的监听契约。
func unregister_event(event_type: Script, listener: GFEventListener) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.unregister_event(event_type, listener)


## 发送类型事件。
## @param event_instance: 要派发的事件对象。
func send_event(event_instance: Object) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.send_event(event_instance)


## 注册轻量级 StringName 事件监听器。
## @param event_id: 简单事件标识。
## @param listener: 显式的 GF 事件监听契约。
func register_simple_event(event_id: StringName, listener: GFEventListener) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.register_simple_event(event_id, listener)


## 注销轻量级 StringName 事件监听器。
## @param event_id: 简单事件标识。
## @param listener: 注册时使用的监听契约。
func unregister_simple_event(event_id: StringName, listener: GFEventListener) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.unregister_simple_event(event_id, listener)


## 发送轻量级 StringName 事件。
## @param event_id: 简单事件标识。
## @param payload: 可选事件载荷。
func send_simple_event(event_id: StringName, payload: Variant = null) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.send_simple_event(event_id, payload)


# --- 虚方法 ---

## 更新 UI 文本，子类应在此实现本地化逻辑。
func _update_ui_text() -> void:
	pass


## 处理 GFUIUtility 发给栈顶弹层的取消请求。
##
## 普通项目弹层默认关闭自身；需要业务确认的弹层可覆写本方法。所有关闭仍经由
## GameUiController 的统一退场动效和 GF Router 出栈，避免直接 queue_free 破坏焦点恢复。
func resolve_cancel() -> void:
	var ui_utility: GFUIUtility = _get_ui_utility()
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_utility) or not is_instance_valid(ui_router):
		return
	if ui_utility.get_top_panel(GFUIUtility.Layer.POPUP) != self:
		return
	var route_id: StringName = ui_router.get_current_route_id(
		GFUIUtility.Layer.POPUP
	)
	if route_id != &"":
		var _closed: bool = _close_current_popup_route(route_id)


# --- 私有/辅助方法 ---

func _apply_default_ui_motion() -> void:
	if not is_inside_tree():
		return

	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var theme_utility: GameThemeUtility = _get_theme_utility()
	if is_instance_valid(theme_utility):
		var _theme_apply_count: int = theme_utility.apply_current_theme_to_tree(self)

	var _bound_count: int = motion_utility.bind_interactive_controls(self)
	var modal_backdrop: Control = _find_modal_backdrop()
	var modal_surface: Control = _find_modal_surface()
	if is_instance_valid(modal_backdrop) and is_instance_valid(modal_surface):
		var _modal_intro_tween: Tween = motion_utility.play_modal_intro(
			modal_backdrop,
			modal_surface
		)
	else:
		var _intro_tween: Tween = motion_utility.play_panel_intro(self)


## 让页面级 `_unhandled_input` 在处理自己的返回逻辑前，先把 ui_cancel 交给
## GF 弹层栈。全屏页面应调用此方法；弹层页面直接继承本类实现即可。
func _try_handle_top_modal_cancel(event: InputEvent) -> bool:
	if event == null or not event.is_action_pressed(&"ui_cancel"):
		return false
	var ui_utility: GFUIUtility = _get_ui_utility()
	if not is_instance_valid(ui_utility):
		return false
	var top_panel: Node = ui_utility.get_top_panel(GFUIUtility.Layer.POPUP)
	if top_panel == null:
		return false
	var viewport: Viewport = get_viewport()
	if is_instance_valid(viewport):
		viewport.set_input_as_handled()
	var _dismiss_requested: bool = ui_utility.request_dismiss_top(
		GFUIUtility.Layer.POPUP,
		"ui_cancel"
	)
	# 只要存在顶层 modal，取消输入就不能继续落到下层完整页面。即使该
	# modal 明确拒绝取消，下层页面也必须保持原位。
	return true


func _bind_modal_focus_bridge() -> void:
	if not is_inside_tree():
		return
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return
	var callback: Callable = Callable(self, "_on_viewport_gui_focus_changed")
	if not viewport.gui_focus_changed.is_connected(callback):
		var _connection_error: int = viewport.gui_focus_changed.connect(callback)


func _on_viewport_gui_focus_changed(_focused_control: Control) -> void:
	if _modal_focus_update_queued:
		return
	_modal_focus_update_queued = true
	call_deferred(&"_keep_focus_inside_owned_top_modal")


func _keep_focus_inside_owned_top_modal() -> void:
	_modal_focus_update_queued = false
	if not is_inside_tree():
		return
	var ui_utility: GFUIUtility = _get_ui_utility()
	if not is_instance_valid(ui_utility):
		return
	if ui_utility.get_top_panel(GFUIUtility.Layer.POPUP) != self:
		return
	var _focus_repaired: bool = ui_utility.keep_focus_inside_top_modal(
		GFUIUtility.Layer.POPUP
	)


func _get_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = _find_optional_utility(_GAME_UI_MOTION_UTILITY_SCRIPT)
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_ui_style_utility() -> GameUiStyleUtility:
	var utility_value: Object = _find_optional_utility(_GAME_UI_STYLE_UTILITY_SCRIPT)
	if utility_value is GameUiStyleUtility:
		var style_utility: GameUiStyleUtility = utility_value
		return style_utility
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = _find_optional_utility(_GAME_THEME_UTILITY_SCRIPT)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _get_ui_router_utility() -> GFUIRouterUtility:
	var utility_value: Object = _find_optional_utility(GFUIRouterUtility)
	if utility_value is GFUIRouterUtility:
		var ui_router: GFUIRouterUtility = utility_value
		return ui_router
	return null


func _get_ui_utility() -> GFUIUtility:
	var utility_value: Object = _find_optional_utility(GFUIUtility)
	if utility_value is GFUIUtility:
		var ui_utility: GFUIUtility = utility_value
		return ui_utility
	return null


func _get_game_ui_router_utility() -> GameUiRouterUtility:
	var utility_value: Object = _find_optional_utility(GameUiRouterUtility)
	if utility_value is GameUiRouterUtility:
		var ui_router: GameUiRouterUtility = utility_value
		return ui_router
	var aliased_utility: GFUIRouterUtility = _get_ui_router_utility()
	if aliased_utility is GameUiRouterUtility:
		var game_ui_router: GameUiRouterUtility = aliased_utility
		return game_ui_router
	return null


## 表现层宿主的主题/路由能力允许在编辑器预览与最小测试架构中缺席；使用
## GFArchitecture.find_utility 避免把可选能力误报为 strict dependency miss。
func _find_optional_utility(utility_type: Script) -> Object:
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		return null
	return architecture.find_utility(utility_type)


## 关闭当前弹层路由，并校验关闭目标仍是调用方拥有的路由。
func _close_current_popup_route(expected_route_id: StringName) -> bool:
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	var ui_utility: GFUIUtility = _get_ui_utility()
	if not is_instance_valid(ui_router) or not is_instance_valid(ui_utility):
		push_error("[GameUiController] 缺少 GFUIRouterUtility，无法关闭路由 %s。" % expected_route_id)
		return false

	var current_route_id: StringName = ui_router.get_current_route_id(GFUIUtility.Layer.POPUP)
	var current_panel: Node = ui_utility.get_top_panel(GFUIUtility.Layer.POPUP)
	if current_route_id != expected_route_id or current_panel != self:
		push_error(
			"[GameUiController] 拒绝关闭非当前路由实例：expected=%s, current=%s。" % [
				expected_route_id,
				current_route_id,
			]
		)
		return false

	if _popup_close_in_progress:
		return true

	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	var modal_backdrop: Control = _find_modal_backdrop()
	var modal_surface: Control = _find_modal_surface()
	var outro_tween: Tween = null
	if is_instance_valid(motion_utility) and is_instance_valid(modal_surface):
		outro_tween = motion_utility.play_modal_outro(
			modal_backdrop,
			modal_surface
		)
	if outro_tween != null and outro_tween.is_valid():
		_popup_close_in_progress = true
		set_process_unhandled_input(false)
		var _finished_connection: int = outro_tween.finished.connect(
			_finish_popup_close.bind(expected_route_id),
			CONNECT_ONE_SHOT
		)
		return true
	return _pop_popup_route(expected_route_id)


func _pop_popup_route(expected_route_id: StringName) -> bool:
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	var ui_utility: GFUIUtility = _get_ui_utility()
	if not is_instance_valid(ui_router) or not is_instance_valid(ui_utility):
		return false
	if (
		ui_router.get_current_route_id(GFUIUtility.Layer.POPUP)
		!= expected_route_id
		or ui_utility.get_top_panel(GFUIUtility.Layer.POPUP) != self
	):
		return false
	if not ui_router.back(GFUIUtility.Layer.POPUP):
		push_error("[GameUiController] GF UI 路由关闭失败：%s。" % expected_route_id)
		return false
	_flush_pending_popup_event()
	_on_popup_route_closed(expected_route_id)
	return true


func _finish_popup_close(expected_route_id: StringName) -> void:
	_popup_close_in_progress = false
	if _pop_popup_route(expected_route_id):
		return
	_clear_pending_popup_event()
	set_process_unhandled_input(true)
	_on_popup_route_close_failed(expected_route_id)
	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	var modal_surface: Control = _find_modal_surface()
	if is_instance_valid(motion_utility) and is_instance_valid(modal_surface):
		var _restore_tween: Tween = motion_utility.play_modal_intro(
			_find_modal_backdrop(),
			modal_surface
		)


## 捕获当前架构后关闭弹层，再通过该架构派发业务事件。
func _close_current_popup_route_and_send_event(
	expected_route_id: StringName,
	event_id: StringName,
	payload: Variant = null
) -> bool:
	if _popup_close_in_progress or _pending_popup_event_id != &"":
		return false
	var architecture: GFArchitecture = get_architecture_or_null()
	if architecture == null:
		push_error("[GameUiController] 缺少 GFArchitecture，无法派发事件 %s。" % event_id)
		return false
	_pending_popup_event_architecture = architecture
	_pending_popup_event_id = event_id
	_pending_popup_event_payload = payload
	if not _close_current_popup_route(expected_route_id):
		_clear_pending_popup_event()
		return false
	return true


func _flush_pending_popup_event() -> void:
	var architecture: GFArchitecture = _pending_popup_event_architecture
	var event_id: StringName = _pending_popup_event_id
	var payload: Variant = _pending_popup_event_payload
	_clear_pending_popup_event()
	if architecture != null and event_id != &"":
		architecture.send_simple_event(event_id, payload)


func _clear_pending_popup_event() -> void:
	_pending_popup_event_architecture = null
	_pending_popup_event_id = &""
	_pending_popup_event_payload = null


## 精确路由实例已完成出栈且 GF Router 历史已落定后的项目覆写点。
func _on_popup_route_closed(_expected_route_id: StringName) -> void:
	pass


## 路由退场动画结束后仍无法精确弹出自身时的项目覆写点。
func _on_popup_route_close_failed(_expected_route_id: StringName) -> void:
	pass


func _find_modal_backdrop() -> Control:
	var node: Node = find_child("DimBackground", true, false)
	if node is Control:
		var control: Control = node
		return control
	return null


func _find_modal_surface() -> Control:
	for node_name: String in ["Surface", "CatalogPanel", "EditorPanel"]:
		var node: Node = find_child(node_name, true, false)
		if node is Control:
			var control: Control = node
			return control
	return null
