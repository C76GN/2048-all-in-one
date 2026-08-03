## GameUiRouterUtility: 配置项目内常用 UI 面板路由。
##
## 作为 GFUIRouterUtility 的项目级 Adapter，从项目资源目录加载类型安全的路由资源。
class_name GameUiRouterUtility
extends "res://addons/gf/standard/utilities/ui/gf_ui_router_utility.gd"


# --- 常量 ---

const DEFAULT_UI_ROUTE_REGISTRY: GFResourceRegistry = preload("res://features/navigation/resources/registries/ui_route_registry.tres")

const ROUTE_PAUSE_MENU: StringName = &"pause_menu"
const ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const ROUTE_TARGET_REACHED_MENU: StringName = &"target_reached_menu"
const ROUTE_SETTINGS_MENU: StringName = &"settings_menu"
const ROUTE_TILE_CATALOG: StringName = &"tile_catalog"
const ROUTE_TILE_LAB: StringName = &"tile_lab"
const ROUTE_ACHIEVEMENTS: StringName = &"achievements"
const ROUTE_BOARD_EDITOR: StringName = &"board_editor"
const ROUTE_PLAYER_PROFILE: StringName = &"player_profile"
const ROUTE_MODAL_DIALOG: StringName = &"modal_dialog"

const MODAL_ACTION_CONFIRM: StringName = &"confirm"
const MODAL_ACTION_CANCEL: StringName = &"cancel"
const MODAL_ACTION_ACKNOWLEDGE: StringName = &"acknowledge"

const _CATALOG_ID: StringName = &"ui_routes"
const _UI_ROUTE_GROUP_ID: StringName = &"ui_routes"
const _UI_ROUTE_RESOURCE_KEY_PREFIX: String = "game.ui_route."
const _ROUTE_TYPE_HINT: String = "Resource"
const _DEFAULT_PRELOAD_PLAN_OPTIONS: Dictionary = {
	"max_depth": 1,
	"max_routes": 4,
	"include_source": true,
}


# --- 私有变量 ---

var _resource_catalog: ProjectResourceCatalogUtility = null
var _route_registry: GFResourceRegistry = DEFAULT_UI_ROUTE_REGISTRY


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFUIUtility, ProjectResourceCatalogUtility]


func ready() -> void:
	_resource_catalog = _resolve_resource_catalog_utility()
	if not is_instance_valid(_resource_catalog):
		push_error("[GameUiRouterUtility] ProjectResourceCatalogUtility 未注册。")
		return

	var report: GFValidationReport = _resource_catalog.register_catalog(
		_CATALOG_ID,
		_route_registry,
		_UI_ROUTE_RESOURCE_KEY_PREFIX,
		_ROUTE_TYPE_HINT,
		_UI_ROUTE_GROUP_ID,
		{"registry": "ui_route_registry"}
	)
	if not report.is_ok():
		push_error("[GameUiRouterUtility] UI 路由目录注册失败：%s" % report.make_summary())
		return

	var ui_utility: GFUIUtility = _resolve_ui_utility()
	if not is_instance_valid(ui_utility):
		push_error("[GameUiRouterUtility] GFUIUtility 未注册。")
		return
	configure(_load_routes_from_registry(), ui_utility)


func dispose() -> void:
	if is_instance_valid(_resource_catalog):
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(_CATALOG_ID, true)
	_resource_catalog = null
	super.dispose()


# --- 公共方法 ---

## 获取 UI 路由注册表中的资源路径列表。
func get_registered_route_paths() -> PackedStringArray:
	if not is_instance_valid(_resource_catalog):
		return PackedStringArray()
	return _resource_catalog.get_registered_paths(_CATALOG_ID)


## 获取项目 UI 路由诊断快照。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	var registry_snapshot: Dictionary = {}
	if is_instance_valid(_route_registry):
		registry_snapshot = _route_registry.get_debug_snapshot()

	var resource_keys: PackedStringArray = PackedStringArray()
	if is_instance_valid(_resource_catalog):
		resource_keys = _resource_catalog.get_registered_resource_keys(_CATALOG_ID)
	snapshot["registry"] = registry_snapshot
	snapshot["route_paths"] = get_registered_route_paths()
	snapshot["route_resource_keys"] = resource_keys
	return snapshot


## 构造项目统一的危险操作确认配置。业务层仍提供完整文案；此处只收口
## 动作 ID、结果状态、默认安全焦点和主题角色。
## @param title: 弹层标题。
## @param message: 确认操作说明。
## @param confirm_label: 危险确认动作文本。
## @param cancel_label: 安全取消动作文本。
## @return 可直接交给 show_modal_async() 的 GF 配置。
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
	cancel_action.metadata = {&"role": GameModalRoutePanel.ACTION_ROLE_PRIMARY}

	var confirm_action: GFModalAction = GFModalAction.new()
	confirm_action.action_id = MODAL_ACTION_CONFIRM
	confirm_action.label = confirm_label
	confirm_action.result_status = GFModalResult.STATUS_CONFIRMED
	confirm_action.metadata = {
		&"role": GameModalRoutePanel.ACTION_ROLE_SECONDARY,
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
## @param title: 弹层标题。
## @param message: 提示正文。
## @param action_label: 唯一确认动作文本。
## @return 可直接交给 show_modal_async() 的 GF 配置。
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
	acknowledge_action.metadata = {&"role": GameModalRoutePanel.ACTION_ROLE_PRIMARY}

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
## 此方法只补充默认相邻路由预算，以及提交完成后 owner 同帧退出时的精确实例回滚。
## @param owner: 持有此次路由操作的活动场景节点。
## @param route_id: 要打开的稳定路由标识。
## @param params: 传给路由场景的业务参数。
## @param option_overrides: 本次路由操作的 GF 选项覆盖。
## @param config_callback: 场景实例化后的可选配置回调。
## @param preload_policy: GF 路由预加载策略。
## @param scope: 可选的协作取消作用域；与 owner 采用 OR 取消语义。
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


## 使用项目主题化路由呈现 GF modal，并返回唯一的 GFModalResult 终态。
##
## 调用方负责配置业务文案、动作语义和危险操作；Router 负责面板栈、焦点、
## ui_cancel 与 owner 生命周期。路由打开失败也会收口成 dismissed/cancelled 结果，
## 调用方无需再猜测日志或原生 Window 状态。
## @param owner: 拥有本次 modal 的场景节点。
## @param config: GF 通用 modal 配置。
## @param context: 原样复制到终态的业务上下文。
## @param scope: 可选的协作取消作用域。
## @return 原面板离场并完成 GF Router 历史清理后的唯一终态。
func show_modal_async(
	owner: Node,
	config: GFModalConfig,
	context: Dictionary = {},
	scope: GFAsyncScope = null
) -> GFModalResult:
	if not _is_live_route_owner(owner):
		return GFModalResult.create(
			GFModalResult.STATUS_CANCELLED,
			&"owner_unavailable",
			null,
			{&"reason": &"invalid_owner"},
			context
		)
	if config == null:
		return GFModalResult.create(
			GFModalResult.STATUS_DISMISSED,
			&"invalid_config",
			null,
			{&"reason": &"invalid_config"},
			context
		)
	var unsupported_action_id: StringName = (
		_find_unsupported_non_closing_action_id(config)
	)
	if unsupported_action_id != &"":
		return GFModalResult.create(
			GFModalResult.STATUS_DISMISSED,
			unsupported_action_id,
			null,
			{
				&"reason": &"unsupported_non_closing_action",
				&"action_id": unsupported_action_id,
			},
			context
		)
	if not _modal_config_has_terminal_path(config):
		return GFModalResult.create(
			GFModalResult.STATUS_DISMISSED,
			&"invalid_config",
			null,
			{&"reason": &"no_terminal_action"},
			context
		)

	var modal_config: GFModalConfig = config.duplicate_config()
	var route_result: GFUIRouteResult = await push_owned_route_async(
		owner,
		ROUTE_MODAL_DIALOG,
		{},
		{
			"dismiss_on_cancel": modal_config.dismiss_on_cancel,
			"focus_on_open": modal_config.auto_focus,
			"modal": true,
			"restore_focus_on_close": modal_config.restore_focus_on_close,
		},
		Callable(self, "_configure_modal_panel").bind(
			modal_config,
			context.duplicate(true),
			owner
		),
		GFUIRouterUtility.PRELOAD_BEST_EFFORT,
		scope
	)
	if route_result == null or not route_result.is_successful():
		return _make_modal_route_failure_result(route_result, context)

	var panel_node: Node = route_result.get_panel()
	if not panel_node is GameModalRoutePanel:
		return _make_modal_route_failure_result(route_result, context, &"invalid_panel")
	var panel: GameModalRoutePanel = panel_node
	var result: GFModalResult = panel.get_result()
	if result == null:
		result = await panel.result_resolved
	return result if result != null else _make_modal_route_failure_result(
		route_result,
		context,
		&"missing_result"
	)


# --- 私有/辅助方法 ---

func _load_routes_from_registry() -> Array[GFUIRoute]:
	var routes: Array[GFUIRoute] = []
	if not is_instance_valid(_route_registry):
		return routes

	for entry: GFResourceRegistryEntry in _route_registry.entries:
		if entry == null or not entry.is_valid_entry():
			continue
		var route: GFUIRoute = _load_route_entry(entry)
		if is_instance_valid(route):
			routes.append(route)
	return routes


func _configure_modal_panel(
	panel_node: Node,
	config: GFModalConfig,
	context: Dictionary,
	owner: Node
) -> void:
	if panel_node is GameModalRoutePanel:
		var panel: GameModalRoutePanel = panel_node
		panel.configure(config, context, owner)


func _make_modal_route_failure_result(
	route_result: GFUIRouteResult,
	context: Dictionary,
	reason: StringName = &"route_failed"
) -> GFModalResult:
	var metadata: Dictionary = {&"reason": reason}
	if route_result != null:
		metadata[&"route_status"] = route_result.get_status()
		metadata[&"route_reason"] = route_result.get_reason()
	return GFModalResult.create(
		GFModalResult.STATUS_DISMISSED,
		&"",
		null,
		metadata,
		context
	)


func _find_unsupported_non_closing_action_id(
	config: GFModalConfig
) -> StringName:
	if config == null:
		return &""
	for action: GFModalAction in config.get_actions():
		if action != null and not action.close_on_pressed:
			return action.action_id
	return &""


func _modal_config_has_terminal_path(config: GFModalConfig) -> bool:
	if config == null:
		return false
	if config.dismiss_on_cancel or config.dismiss_on_backdrop:
		return true
	for action: GFModalAction in config.get_actions():
		if (
			action != null
			and action.close_on_pressed
			and not GFVariantData.get_option_bool(
				action.metadata,
				&"disabled",
				false
			)
		):
			return true
	return false


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


func _load_route_entry(entry: GFResourceRegistryEntry) -> GFUIRoute:
	if not is_instance_valid(_resource_catalog):
		return null
	var resource: Resource = _resource_catalog.load_resource_by_entry(_CATALOG_ID, entry)
	if resource is GFUIRoute:
		var route: GFUIRoute = resource
		return route
	push_error("[GameUiRouterUtility] UI 路由资源加载失败：%s。" % entry.path)
	return null


func _resolve_resource_catalog_utility() -> ProjectResourceCatalogUtility:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = utility_value
		return catalog
	return null


func _resolve_ui_utility() -> GFUIUtility:
	var utility_value: Object = get_utility(GFUIUtility)
	if utility_value is GFUIUtility:
		var ui_utility: GFUIUtility = utility_value
		return ui_utility
	return null
