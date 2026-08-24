## GameUiRouterUtility: 配置项目内常用 UI 面板路由。
##
## 作为 GameUiRouterPort 的 navigation Adapter，从项目资源目录加载类型安全的
## 路由资源，并实现主题化 modal。
class_name GameUiRouterUtility
extends GameUiRouterPort


# --- 常量 ---

const DEFAULT_UI_ROUTE_REGISTRY: GFResourceRegistry = preload("res://features/navigation/resources/registries/ui_route_registry.tres")

const _CATALOG_ID: StringName = &"ui_routes"
const _UI_ROUTE_GROUP_ID: StringName = &"ui_routes"
const _UI_ROUTE_RESOURCE_KEY_PREFIX: String = "game.ui_route."
const _ROUTE_TYPE_HINT: String = "Resource"


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
		var _catalog_unregistered: bool = _resource_catalog.unregister_catalog(_CATALOG_ID)
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
