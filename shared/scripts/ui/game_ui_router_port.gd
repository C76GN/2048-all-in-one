## GameUiRouterPort: 跨 Feature 的项目 UI Router Interface。
##
## Feature 只依赖此 Port；navigation 提供实际 Adapter。Port 继承 GF Router 的
## 栈、预加载与回退能力，并收口项目稳定 route id、modal 配置以及 owner-aware
## 异步打开语义。
class_name GameUiRouterPort
extends GFUIRouterUtility


# --- 常量 ---

const ROUTE_PAUSE_MENU: StringName = &"pause_menu"
const ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const ROUTE_TARGET_REACHED_MENU: StringName = &"target_reached_menu"
const ROUTE_SETTINGS_MENU: StringName = &"settings_menu"
const ROUTE_TILE_LAB: StringName = &"tile_lab"
const ROUTE_PLAYER_PROFILE: StringName = &"player_profile"
const ROUTE_MODAL_DIALOG: StringName = &"modal_dialog"

const PARAM_SETTINGS_RETURN_TO_MAIN_MENU_ON_BACK: StringName = (
	&"settings_return_to_main_menu_on_back"
)

const MODAL_ACTION_CONFIRM: StringName = &"confirm"
const MODAL_ACTION_CANCEL: StringName = &"cancel"
const MODAL_ACTION_ACKNOWLEDGE: StringName = &"acknowledge"
const MODAL_ACTION_ROLE_PRIMARY: StringName = &"primary"
const MODAL_ACTION_ROLE_SECONDARY: StringName = &"secondary"

const _DEFAULT_PRELOAD_PLAN_OPTIONS: Dictionary = {
	"max_depth": 1,
	"max_routes": 4,
	"include_source": true,
}


# --- 公共方法 ---

## 构造项目统一的危险操作确认配置。业务 Feature 仍提供完整文案；Port 只收口
## 动作 ID、结果状态、默认安全焦点和主题角色。
## @param title: 危险操作确认框的标题。
## @param message: 需要向玩家说明的操作内容与风险。
## @param confirm_label: 确认执行危险操作的按钮文案。
## @param cancel_label: 保持当前状态的取消按钮文案。
static func make_confirmation_modal_config(
	title: String,
	message: String,
	confirm_label: String,
	cancel_label: String
) -> GFModalConfig:
	var cancel_action: GFModalAction = GFModalAction.new()
	cancel_action.action_id = MODAL_ACTION_CANCEL
	cancel_action.label = cancel_label
	cancel_action.result_status = GFModalResult.STATUS_CANCELLED
	cancel_action.grab_focus = true
	cancel_action.metadata = {&"role": MODAL_ACTION_ROLE_PRIMARY}

	var confirm_action: GFModalAction = GFModalAction.new()
	confirm_action.action_id = MODAL_ACTION_CONFIRM
	confirm_action.label = confirm_label
	confirm_action.result_status = GFModalResult.STATUS_CONFIRMED
	confirm_action.metadata = {
		&"role": MODAL_ACTION_ROLE_SECONDARY,
		&"intent": &"danger",
	}

	var config: GFModalConfig = GFModalConfig.new()
	config.title = title
	config.message = message
	var actions: Array[GFModalAction] = [cancel_action, confirm_action]
	config.actions = actions
	config.dismiss_on_backdrop = false
	config.dismiss_on_cancel = true
	config.auto_focus = true
	config.restore_focus_on_close = true
	return config


## 构造项目统一的单动作信息提示配置。
## @param title: 信息提示框的标题。
## @param message: 需要向玩家展示的消息。
## @param action_label: 关闭提示框的单一确认按钮文案。
static func make_acknowledgement_modal_config(
	title: String,
	message: String,
	action_label: String
) -> GFModalConfig:
	var acknowledge_action: GFModalAction = GFModalAction.new()
	acknowledge_action.action_id = MODAL_ACTION_ACKNOWLEDGE
	acknowledge_action.label = action_label
	acknowledge_action.result_status = GFModalResult.STATUS_DISMISSED
	acknowledge_action.grab_focus = true
	acknowledge_action.metadata = {&"role": MODAL_ACTION_ROLE_PRIMARY}

	var config: GFModalConfig = GFModalConfig.new()
	config.title = title
	config.message = message
	var actions: Array[GFModalAction] = [acknowledge_action]
	config.actions = actions
	config.dismiss_on_backdrop = false
	config.dismiss_on_cancel = true
	config.auto_focus = true
	config.restore_focus_on_close = true
	return config


## 以项目统一策略异步打开路由，并把调用方生命周期交给 GF 管理。
##
## GFUIRouterUtility 负责提交前的 owner/scope 取消、预加载、并发去重与唯一终态；
## Port 补充默认相邻路由预算，以及提交完成后 owner 同帧退出时的精确实例回滚。
## @param owner: 拥有本次路由请求的场景节点。
## @param route_id: 要打开的稳定项目路由 ID。
## @param params: 传递给路由面板的业务参数。
## @param option_overrides: 覆盖路由定义的本次导航选项。
## @param config_callback: 面板提交前用于完成实例配置的回调。
## @param preload_policy: 本次请求的 GF 路由预加载策略。
## @param scope: 可选的调用方异步生命周期作用域。
func push_owned_route_async(
	owner: Node,
	route_id: StringName,
	params: Dictionary = {},
	option_overrides: Dictionary = {},
	config_callback: Callable = Callable(),
	preload_policy: StringName = GFUIRouterUtility.PRELOAD_BEST_EFFORT,
	scope: GFAsyncScope = null
) -> GFUIRouteResult:
	if not _is_live_route_owner(owner):
		return null

	var owner_ref: WeakRef = weakref(owner)
	var async_options: Dictionary = {
		"preload_policy": preload_policy,
		"preload_plan_options": _DEFAULT_PRELOAD_PLAN_OPTIONS.duplicate(true),
		"owner": owner,
		"metadata": {
			"owner_instance_id": owner.get_instance_id(),
			"owner_path": String(owner.get_path()),
		},
	}
	if scope != null:
		async_options["scope"] = scope
	var operation: GFUIRouteOperation = push_route_async(
		route_id,
		params,
		option_overrides,
		config_callback,
		async_options
	)
	if operation == null:
		return null

	var result: GFUIRouteResult = operation.get_result()
	if result == null:
		result = await operation.completed
	if _is_live_route_owner_ref(owner_ref):
		return result

	# GF 的 owner/scope 只约束 panel_submitted 之前。若 owner 恰好在 GF 提交后、
	# 类型化终态返回前退出，只回滚本次结果实际提交且仍位于栈顶的实例。
	_rollback_stale_route_result(result)
	return result


## 使用项目主题化路由呈现 GF modal。navigation Adapter 必须实现此 Interface，
## 并以唯一 GFModalResult 收口路由失败、owner 取消与用户动作。
## @param _owner: 拥有 modal 请求的场景节点；基础 Port 的失败关闭实现不使用它。
## @param _config: 要呈现的 GF modal 配置；基础 Port 的失败关闭实现不使用它。
## @param context: 透传到唯一 modal 终态的调用上下文。
## @param _scope: 可选的调用方异步作用域；基础 Port 的失败关闭实现不使用它。
func show_modal_async(
	_owner: Node,
	_config: GFModalConfig,
	context: Dictionary = {},
	_scope: GFAsyncScope = null
) -> GFModalResult:
	# 保持 Port 的异步 Interface；未安装 Adapter 时下一帧失败关闭，避免调用方把
	# 同步占位结果误当成实际 modal 终态。
	var _frame_wait: Dictionary = await GFAsyncWaitUtility.next_frame()
	return GFModalResult.create(
		GFModalResult.STATUS_DISMISSED,
		&"router_unavailable",
		null,
		{&"reason": &"router_port_not_implemented"},
		context
	)


# --- 私有/辅助方法 ---

func _is_live_route_owner(owner: Node) -> bool:
	return is_instance_valid(owner) and owner.is_inside_tree()


func _is_live_route_owner_ref(owner_ref: WeakRef) -> bool:
	if owner_ref == null:
		return false
	var value: Object = owner_ref.get_ref()
	if value is Node:
		var owner: Node = value
		return _is_live_route_owner(owner)
	return false


func _rollback_stale_route_result(result: GFUIRouteResult) -> void:
	if result == null or not result.is_successful():
		return
	var result_panel: Node = result.get_panel()
	if result_panel == null:
		return
	var ui_utility: GFUIUtility = _get_ui_utility()
	if ui_utility == null:
		return
	var current_panel: Node = ui_utility.get_top_panel(
		_get_ui_layer(result.get_layer())
	)
	# 同一路由可以在迟到请求完成后再次打开。只允许回滚本次结果实际提交的
	# 面板实例，不能仅凭 route_id 关闭后来打开的新实例。
	if current_panel != result_panel:
		return
	var _closed: bool = back(result.get_layer())
