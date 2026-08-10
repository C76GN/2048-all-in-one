## ProjectResourceCatalogUtility: 项目资源目录 Adapter。
##
## 将项目 GFResourceRegistry 原子注册到 GFResourceResolverUtility，并统一交给
## GFAssetUtility 分组管理缓存生命周期。业务 Feature 只需要面对目录 ID 和资源路径。
class_name ProjectResourceCatalogUtility
extends GFUtility


# --- 常量 ---

const _RESOLVER_OWNER_PREFIX: String = "project.catalog."


# --- 私有变量 ---

var _asset_utility: GFAssetUtility = null
var _resource_resolver: GFResourceResolverUtility = null
var _catalogs: Dictionary = {}
var _catalog_mutations: Dictionary = {}
var _catalog_preload_sessions: Dictionary = {}
var _catalog_preload_request_ids: Dictionary = {}
var _next_catalog_preload_request_id: int = 1
var _disposing: bool = false
var _disposed: bool = false


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFAssetUtility, GFResourceResolverUtility]


func ready() -> void:
	_asset_utility = _resolve_asset_utility()
	_resource_resolver = _resolve_resource_resolver_utility()
	if not is_instance_valid(_asset_utility):
		push_error("[ProjectResourceCatalogUtility] GFAssetUtility 未注册。")
	if not is_instance_valid(_resource_resolver):
		push_error("[ProjectResourceCatalogUtility] GFResourceResolverUtility 未注册。")


func dispose() -> void:
	if _disposing or _disposed:
		return
	_disposing = true
	var catalog_ids: Array = _catalogs.keys()
	for catalog_id_value: Variant in catalog_ids:
		var catalog_id: StringName = GFVariantData.to_string_name(catalog_id_value, &"")
		if catalog_id != &"":
			var _catalog_unregistered: bool = _unregister_catalog_owned(catalog_id, true)
	_catalogs.clear()
	_catalog_mutations.clear()
	_catalog_preload_sessions.clear()
	_catalog_preload_request_ids.clear()
	_next_catalog_preload_request_id = 1
	_asset_utility = null
	_resource_resolver = null
	_disposed = true
	_disposing = false


# --- 公共方法 ---

## 将一个项目资源注册表原子接入 GF Resolver 与 Asset 分组。
## @param catalog_id: 项目内稳定且唯一的目录 ID。
## @param registry: 要注册的 GF 资源注册表。
## @param resource_key_prefix: 为每个条目生成稳定资源键时使用的前缀。
## @param default_type_hint: 条目未声明类型时使用的 ResourceLoader 类型提示。
## @param group_id: 可选的 GFAssetUtility 资源分组 ID。
## @param metadata: 合并到每个 Resolver 条目的目录级元数据。
## @param pin_group_paths: 是否固定分组中的资源路径。
## @param priority: Resolver 条目的解析优先级。
## @return: 包含注册路径、资源键和错误详情的校验报告。
func register_catalog(
	catalog_id: StringName,
	registry: GFResourceRegistry,
	resource_key_prefix: String,
	default_type_hint: String = "",
	group_id: StringName = &"",
	metadata: Dictionary = {},
	pin_group_paths: bool = true,
	priority: int = 0
) -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"ProjectResourceCatalog",
		{"catalog_id": String(catalog_id)}
	)
	var paths: PackedStringArray = PackedStringArray()
	var resource_keys: PackedStringArray = PackedStringArray()
	report.extra_fields = {
		"paths": paths,
		"resource_keys": resource_keys,
		"registered_count": 0,
	}

	if (
		_disposing
		or _disposed
		or catalog_id == &""
		or not is_instance_valid(registry)
		or resource_key_prefix.is_empty()
	):
		var _invalid_catalog_issue: RefCounted = report.add_error(&"invalid_catalog", "资源目录配置无效。", catalog_id)
		return report
	if _catalog_mutations.has(catalog_id):
		var _busy_catalog_issue: RefCounted = report.add_error(
			&"catalog_mutation_in_progress",
			"资源目录正在变更，不能同步重入注册。",
			catalog_id
		)
		return report
	if not is_instance_valid(_get_asset_utility()):
		var _asset_issue: RefCounted = report.add_error(&"missing_asset_utility", "GFAssetUtility 未注册。", catalog_id)
	if not is_instance_valid(_get_resource_resolver()):
		var _resolver_issue: RefCounted = report.add_error(&"missing_resource_resolver", "GFResourceResolverUtility 未注册。", catalog_id)
	if not report.is_ok():
		return report

	var resolver_entries: Array[Dictionary] = []
	var seen_paths: Dictionary = {}
	var entry_ids_by_path: Dictionary = {}
	for entry: GFResourceRegistryEntry in registry.entries:
		if not _is_valid_registry_entry(entry):
			var _invalid_entry_issue: RefCounted = report.add_error(&"invalid_entry", "资源目录包含无效条目。", catalog_id)
			continue
		if seen_paths.has(entry.path):
			var _duplicate_path_issue: RefCounted = report.add_error(
				&"duplicate_path",
				"资源目录包含重复路径：%s。" % entry.path,
				entry.id,
				entry.path
			)
			continue
		seen_paths[entry.path] = true
		entry_ids_by_path[entry.path] = entry.id

		var resource_key: StringName = make_resource_key(entry, resource_key_prefix)
		var type_hint: String = get_entry_type_hint(entry, default_type_hint)
		resolver_entries.append({
			"resource_key": resource_key,
			"path": entry.path,
			"type_hint": type_hint,
			"priority": priority,
			"metadata": _make_entry_metadata(metadata, catalog_id, entry),
		})
		var _path_appended: bool = paths.append(entry.path)
		var _key_appended: bool = resource_keys.append(String(resource_key))

	report.extra_fields["paths"] = paths
	report.extra_fields["resource_keys"] = resource_keys
	if not report.is_ok():
		return report

	var resolver: GFResourceResolverUtility = _get_resource_resolver()
	var resolver_owner_id: StringName = _make_resolver_owner_id(catalog_id)
	_catalog_mutations[catalog_id] = true
	var replacement: Dictionary = resolver.replace_owner_paths(resolver_owner_id, resolver_entries)
	if not GFResultDictionary.is_ok(replacement):
		_end_catalog_mutation(catalog_id)
		var reason: String = GFVariantData.get_option_string(replacement, "reason", "resolver_registration_failed")
		var failed_index: int = GFVariantData.get_option_int(replacement, "failed_index", -1)
		var _registration_issue: RefCounted = report.add_error(
			&"resolver_registration_failed",
			"资源目录原子注册失败：%s。" % reason,
			failed_index,
			"",
			{"reason": reason}
		)
		return report

	_rollback_catalog_preload_session(catalog_id, &"catalog_replaced")
	if _disposing or _disposed:
		_end_catalog_mutation(catalog_id)
		var _disposed_during_rollback_issue: RefCounted = report.add_error(
			&"catalog_disposed_during_registration",
			"资源目录在替换过程中已销毁。",
			catalog_id
		)
		return report
	_release_catalog_asset_group(_get_catalog(catalog_id), true)
	if _disposing or _disposed:
		_end_catalog_mutation(catalog_id)
		var _disposed_during_release_issue: RefCounted = report.add_error(
			&"catalog_disposed_during_registration",
			"资源目录在释放旧分组时已销毁。",
			catalog_id
		)
		return report
	_catalogs[catalog_id] = {
		"registry": registry,
		"resource_key_prefix": resource_key_prefix,
		"default_type_hint": default_type_hint,
		"group_id": group_id,
		"metadata": metadata.duplicate(true),
		"pin_group_paths": pin_group_paths,
		"priority": priority,
		"paths": paths,
		"resource_keys": resource_keys,
		"entry_ids_by_path": entry_ids_by_path,
		"resolver_owner_id": resolver_owner_id,
	}

	var asset_utility: GFAssetUtility = _get_asset_utility()
	if group_id != &"":
		for path: String in paths:
			asset_utility.register_group_path(group_id, path, pin_group_paths)

	_end_catalog_mutation(catalog_id)
	report.extra_fields["registered_count"] = resolver_entries.size()
	return report


## 注销目录拥有的 Resolver 映射和 Asset 分组。
## @param catalog_id: 要注销的稳定目录 ID。
## @param remove_unreferenced_cache: 是否同时移除分组释放后的无引用缓存。
func unregister_catalog(catalog_id: StringName, remove_unreferenced_cache: bool = true) -> bool:
	if _disposing or _disposed or _catalog_mutations.has(catalog_id):
		return false
	var catalog: Dictionary = _get_catalog(catalog_id)
	if catalog.is_empty():
		return false

	_catalog_mutations[catalog_id] = true
	var unregistered: bool = _unregister_catalog_owned(catalog_id, remove_unreferenced_cache)
	_end_catalog_mutation(catalog_id)
	return unregistered


## 获取目录中的有效资源路径，保持注册表顺序。
## @param catalog_id: 要查询的稳定目录 ID。
## @param check_resolvable: 是否只返回当前 Resolver 可解析的路径。
func get_registered_paths(catalog_id: StringName, check_resolvable: bool = false) -> PackedStringArray:
	var catalog: Dictionary = _get_catalog(catalog_id)
	var paths: PackedStringArray = _get_catalog_paths(catalog)
	if not check_resolvable:
		return paths

	var result: PackedStringArray = PackedStringArray()
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	for path: String in paths:
		var entry: GFResourceRegistryEntry = _get_catalog_entry_by_path(catalog, registry, path)
		if _is_valid_registry_entry(entry) and _is_entry_resolvable(catalog, entry):
			var _path_appended: bool = result.append(path)
	return result


## 获取目录中已注册的稳定资源键，保持注册表顺序。
## @param catalog_id: 要查询的稳定目录 ID。
func get_registered_resource_keys(catalog_id: StringName) -> PackedStringArray:
	return _get_catalog_resource_keys(_get_catalog(catalog_id))


## 通过 GFAssetLoadSession 事务预热目录中的全部资源。
## @param catalog_id: 已注册目录 ID。
## 同一目录只持有一个活动会话；新会话会先回滚尚未结束的旧会话。
## @param options: 支持 plan_id、lane_id、max_concurrent_loads 和 metadata。
## @return: 已启动的框架资产会话；目录未配置时返回 null。
func start_catalog_preload_session(
	catalog_id: StringName,
	options: Dictionary = {}
) -> GFAssetLoadSession:
	if _disposing or _disposed or _catalog_mutations.has(catalog_id):
		return null
	_catalog_mutations[catalog_id] = true
	var session: GFAssetLoadSession = _start_catalog_preload_session_owned(catalog_id, options)
	_end_catalog_mutation(catalog_id)
	return session


## 通过目录资源路径加载资源，并复用 GFAssetUtility 缓存。
## @param catalog_id: 资源所属的稳定目录 ID。
## @param resource_path: 已登记的项目资源路径。
## @param cache_mode: ResourceLoader 缓存模式。
func load_resource_by_path(
	catalog_id: StringName,
	resource_path: String,
	cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	if resource_path.is_empty():
		return null

	var catalog: Dictionary = _get_catalog(catalog_id)
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	var entry: GFResourceRegistryEntry = _get_catalog_entry_by_path(catalog, registry, resource_path)
	if not _is_valid_registry_entry(entry):
		return null
	return load_resource_by_entry(catalog_id, entry, cache_mode)


## 只读取 GFAssetUtility 已完成的缓存，不触发同步 ResourceLoader。
## 适用于已经由启动/页面激活屏障保证预载终态的热路径。
## @param catalog_id: 已注册资源目录的稳定标识。
## @param resource_path: 需要从目录缓存读取的规范资源路径。
func get_cached_resource_by_path(
	catalog_id: StringName,
	resource_path: String
) -> Resource:
	if resource_path.is_empty():
		return null
	var catalog: Dictionary = _get_catalog(catalog_id)
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	var entry: GFResourceRegistryEntry = _get_catalog_entry_by_path(
		catalog,
		registry,
		resource_path
	)
	if not _is_valid_registry_entry(entry):
		return null
	var asset_utility: GFAssetUtility = _get_asset_utility()
	return asset_utility.get_cached(entry.path) if is_instance_valid(asset_utility) else null


## 通过目录条目加载资源，并复用 GFAssetUtility 缓存。
## @param catalog_id: 资源所属的稳定目录 ID。
## @param entry: 已登记的资源条目。
## @param cache_mode: ResourceLoader 缓存模式。
func load_resource_by_entry(
	catalog_id: StringName,
	entry: GFResourceRegistryEntry,
	cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	var catalog: Dictionary = _get_catalog(catalog_id)
	if catalog.is_empty() or not _is_valid_registry_entry(entry):
		return null

	var type_hint: String = get_entry_type_hint(entry, _get_catalog_default_type_hint(catalog))
	var asset_utility: GFAssetUtility = _get_asset_utility()
	var cached: Resource = asset_utility.get_cached(entry.path)
	if is_instance_valid(cached):
		return cached

	var resource: Resource = _get_resource_resolver().load(
		make_resource_key(entry, _get_catalog_resource_key_prefix(catalog)),
		type_hint,
		cache_mode
	)
	if not is_instance_valid(resource):
		return null
	asset_utility.put_cache(entry.path, resource)
	return resource


## 获取项目资源目录诊断快照。
func get_debug_snapshot() -> Dictionary:
	var catalogs: Dictionary = {}
	for catalog_id_value: Variant in _catalogs.keys():
		var catalog_id: StringName = GFVariantData.to_string_name(catalog_id_value, &"")
		var catalog: Dictionary = _get_catalog(catalog_id)
		catalogs[String(catalog_id)] = {
			"paths": _get_catalog_paths(catalog),
			"resource_keys": _get_catalog_resource_keys(catalog),
			"group_id": String(_get_catalog_group_id(catalog)),
			"resolver_owner_id": String(_get_catalog_resolver_owner_id(catalog)),
		}
	return {
		"catalog_count": _catalogs.size(),
		"catalogs": catalogs,
	}


## 通过 GFResourceRegistry 的路径分组查找唯一条目。
## @param registry: 要查询的 GF 资源注册表。
## @param resource_path: 要匹配的完整项目资源路径。
static func find_entry_by_path(registry: GFResourceRegistry, resource_path: String) -> GFResourceRegistryEntry:
	if not is_instance_valid(registry) or resource_path.is_empty():
		return null

	var path_groups: Dictionary = registry.group_entry_ids(GFResourceRegistry.GROUP_SOURCE_PATH)
	var entry_ids: PackedStringArray = GFVariantData.get_option_packed_string_array(
		path_groups,
		resource_path,
		PackedStringArray()
	)
	if entry_ids.size() != 1:
		return null
	var entry_resource: Resource = registry.get_entry(StringName(entry_ids[0]))
	if entry_resource is GFResourceRegistryEntry:
		var entry: GFResourceRegistryEntry = entry_resource
		return entry
	return null


## 根据目录前缀与条目 ID 构造稳定 Resolver 资源键。
## @param entry: 用于生成资源键的注册表条目。
## @param resource_key_prefix: 目录拥有的稳定资源键前缀。
static func make_resource_key(entry: GFResourceRegistryEntry, resource_key_prefix: String) -> StringName:
	if not _is_valid_registry_entry(entry) or resource_key_prefix.is_empty():
		return &""
	return StringName("%s%s" % [resource_key_prefix, String(entry.id)])


## 获取条目的类型提示，未声明时使用目录默认值。
## @param entry: 要查询的注册表条目。
## @param default_type_hint: 条目未声明类型时使用的默认提示。
static func get_entry_type_hint(entry: GFResourceRegistryEntry, default_type_hint: String = "") -> String:
	if _is_valid_registry_entry(entry) and not entry.type_hint.is_empty():
		return entry.type_hint
	return default_type_hint


# --- 私有/辅助方法 ---

func _get_catalog(catalog_id: StringName) -> Dictionary:
	var catalog_value: Variant = _catalogs.get(catalog_id, {})
	if catalog_value is Dictionary:
		return catalog_value
	return {}


func _is_entry_resolvable(catalog: Dictionary, entry: GFResourceRegistryEntry) -> bool:
	var resolver: GFResourceResolverUtility = _get_resource_resolver()
	return resolver.has_registered_key(make_resource_key(entry, _get_catalog_resource_key_prefix(catalog)))


func _get_asset_utility() -> GFAssetUtility:
	if is_instance_valid(_asset_utility):
		return _asset_utility
	_asset_utility = _resolve_asset_utility()
	return _asset_utility


func _get_resource_resolver() -> GFResourceResolverUtility:
	if is_instance_valid(_resource_resolver):
		return _resource_resolver
	_resource_resolver = _resolve_resource_resolver_utility()
	return _resource_resolver


func _resolve_asset_utility() -> GFAssetUtility:
	var utility_value: Object = get_utility(GFAssetUtility)
	if utility_value is GFAssetUtility:
		return utility_value
	return null


func _resolve_resource_resolver_utility() -> GFResourceResolverUtility:
	var utility_value: Object = get_utility(GFResourceResolverUtility)
	if utility_value is GFResourceResolverUtility:
		return utility_value
	return null


func _release_catalog_asset_group(catalog: Dictionary, remove_unreferenced_cache: bool) -> void:
	var group_id: StringName = _get_catalog_group_id(catalog)
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if group_id != &"" and is_instance_valid(asset_utility):
		asset_utility.unload_group(group_id, remove_unreferenced_cache)


func _start_catalog_preload_session_owned(
	catalog_id: StringName,
	options: Dictionary
) -> GFAssetLoadSession:
	var catalog: Dictionary = _get_catalog(catalog_id)
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	var asset_utility: GFAssetUtility = _get_asset_utility()
	var group_id: StringName = _get_catalog_group_id(catalog)
	if (
		catalog.is_empty()
		or not is_instance_valid(registry)
		or not is_instance_valid(asset_utility)
		or group_id == &""
	):
		return null

	_rollback_catalog_preload_session(catalog_id, &"catalog_preload_superseded")
	if _disposing or _disposed:
		return null
	catalog = _get_catalog(catalog_id)
	registry = _get_catalog_registry(catalog)
	asset_utility = _get_asset_utility()
	group_id = _get_catalog_group_id(catalog)
	if (
		catalog.is_empty()
		or not is_instance_valid(registry)
		or not is_instance_valid(asset_utility)
		or group_id == &""
	):
		return null
	var request_id: int = _next_catalog_preload_request_id
	_next_catalog_preload_request_id += 1
	_catalog_preload_request_ids[catalog_id] = request_id
	var session_metadata: Dictionary = GFVariantData.get_option_dictionary(
		options,
		"metadata"
	).duplicate(true)
	session_metadata["catalog_id"] = catalog_id
	session_metadata["catalog_preload_request_id"] = request_id
	var plan_id: StringName = GFVariantData.get_option_string_name(options, "plan_id")
	if plan_id == &"":
		plan_id = StringName("project.catalog.%s.preload" % String(catalog_id))
	var plan: GFAssetPreloadPlan = GFAssetPreloadPlan.new()
	var _configured_plan: GFAssetPreloadPlan = plan.configure(
		group_id,
		registry.make_asset_group_entries(),
		{
			"plan_id": plan_id,
			# register_catalog() 已按目录策略登记并固定目标分组路径；会话负责
			# staging 收敛、typed 终态与回滚，不重复增加同一路径的 pin 计数。
			"pin_cache": false,
			"lane_id": GFVariantData.get_option_string_name(options, "lane_id"),
			"max_concurrent_loads": GFVariantData.get_option_int(
				options,
				"max_concurrent_loads",
				0
			),
			"metadata": session_metadata,
		}
	)
	var session: GFAssetLoadSession = asset_utility.start_preload_session(
		plan,
		{
			"auto_commit": false,
			"metadata": session_metadata,
		}
	)
	if not _is_catalog_preload_request_current(catalog_id, request_id):
		if not session.is_completed():
			var _rollback_started: bool = session.rollback(&"catalog_preload_invalidated")
		return session
	_catalog_preload_sessions[catalog_id] = session
	if session.get_state() == GFAssetLoadSession.State.READY:
		_commit_catalog_preload_session(session, catalog_id, request_id)
	elif session.get_state() in [
		GFAssetLoadSession.State.CREATED,
		GFAssetLoadSession.State.LOADING,
	]:
		var connect_error: int = session.ready_to_commit.connect(
			_on_catalog_preload_ready.bind(catalog_id, request_id),
			CONNECT_ONE_SHOT
		)
		if connect_error != OK:
			_remove_catalog_preload_session_if_current(catalog_id, session, request_id)
			var _rollback_started: bool = session.rollback(&"ready_tracking_failed")
			push_error(
				"[ProjectResourceCatalogUtility] 无法跟踪目录预载 READY 终态：%s。"
				% String(catalog_id)
			)
	return session


func _unregister_catalog_owned(catalog_id: StringName, remove_unreferenced_cache: bool) -> bool:
	var catalog: Dictionary = _get_catalog(catalog_id)
	if catalog.is_empty():
		return false
	_rollback_catalog_preload_session(catalog_id, &"catalog_unregistered")
	var resolver: GFResourceResolverUtility = _get_resource_resolver()
	if is_instance_valid(resolver):
		var _removed_registration_count: int = resolver.unregister_owner(
			_get_catalog_resolver_owner_id(catalog)
		)
	_release_catalog_asset_group(catalog, remove_unreferenced_cache)
	var _catalog_erased: bool = _catalogs.erase(catalog_id)
	return true


func _end_catalog_mutation(catalog_id: StringName) -> void:
	var _mutation_erased: bool = _catalog_mutations.erase(catalog_id)


func _rollback_catalog_preload_session(catalog_id: StringName, reason: StringName) -> void:
	var session_value: Variant = _catalog_preload_sessions.get(catalog_id)
	var _session_erased: bool = _catalog_preload_sessions.erase(catalog_id)
	var _request_erased: bool = _catalog_preload_request_ids.erase(catalog_id)
	if session_value is GFAssetLoadSession:
		var session: GFAssetLoadSession = session_value
		if not session.is_completed():
			var _rollback_started: bool = session.rollback(reason)


func _on_catalog_preload_ready(
	session: GFAssetLoadSession,
	catalog_id: StringName,
	request_id: int
) -> void:
	_commit_catalog_preload_session(session, catalog_id, request_id)


func _commit_catalog_preload_session(
	session: GFAssetLoadSession,
	catalog_id: StringName,
	request_id: int
) -> void:
	if not _is_catalog_preload_session_current(catalog_id, session, request_id):
		if is_instance_valid(session) and not session.is_completed():
			var _rollback_started: bool = session.rollback(&"catalog_preload_invalidated")
		return
	if session.get_state() != GFAssetLoadSession.State.READY:
		return
	var committed: bool = session.commit()
	if not committed:
		push_error(
			"[ProjectResourceCatalogUtility] 目录预载会话无法提交：%s。"
			% String(catalog_id)
		)


func _is_catalog_preload_request_current(catalog_id: StringName, request_id: int) -> bool:
	return (
		_catalogs.has(catalog_id)
		and GFVariantData.get_option_int(_catalog_preload_request_ids, catalog_id, -1)
		== request_id
	)


func _is_catalog_preload_session_current(
	catalog_id: StringName,
	session: GFAssetLoadSession,
	request_id: int
) -> bool:
	if not _is_catalog_preload_request_current(catalog_id, request_id):
		return false
	var current_session_value: Variant = _catalog_preload_sessions.get(catalog_id)
	return current_session_value is GFAssetLoadSession and is_same(current_session_value, session)


func _remove_catalog_preload_session_if_current(
	catalog_id: StringName,
	session: GFAssetLoadSession,
	request_id: int
) -> void:
	if not _is_catalog_preload_session_current(catalog_id, session, request_id):
		return
	var _session_erased: bool = _catalog_preload_sessions.erase(catalog_id)
	var _request_erased: bool = _catalog_preload_request_ids.erase(catalog_id)


func _get_catalog_registry(catalog: Dictionary) -> GFResourceRegistry:
	var registry_value: Variant = catalog.get("registry")
	if registry_value is GFResourceRegistry:
		return registry_value
	return null


func _get_catalog_resource_key_prefix(catalog: Dictionary) -> String:
	return GFVariantData.get_option_string(catalog, "resource_key_prefix")


func _get_catalog_default_type_hint(catalog: Dictionary) -> String:
	return GFVariantData.get_option_string(catalog, "default_type_hint")


func _get_catalog_group_id(catalog: Dictionary) -> StringName:
	return GFVariantData.get_option_string_name(catalog, "group_id")


func _get_catalog_resolver_owner_id(catalog: Dictionary) -> StringName:
	return GFVariantData.get_option_string_name(catalog, "resolver_owner_id")


func _get_catalog_paths(catalog: Dictionary) -> PackedStringArray:
	var paths_value: Variant = catalog.get("paths")
	if paths_value is PackedStringArray:
		var paths: PackedStringArray = paths_value
		return paths.duplicate()
	return PackedStringArray()


func _get_catalog_resource_keys(catalog: Dictionary) -> PackedStringArray:
	var keys_value: Variant = catalog.get("resource_keys")
	if keys_value is PackedStringArray:
		var resource_keys: PackedStringArray = keys_value
		return resource_keys.duplicate()
	return PackedStringArray()


func _get_catalog_entry_by_path(
	catalog: Dictionary,
	registry: GFResourceRegistry,
	resource_path: String
) -> GFResourceRegistryEntry:
	if not is_instance_valid(registry) or resource_path.is_empty():
		return null
	var entry_ids_value: Variant = catalog.get("entry_ids_by_path")
	if not entry_ids_value is Dictionary:
		return null
	var entry_ids_by_path: Dictionary = entry_ids_value
	var entry_id: StringName = GFVariantData.get_option_string_name(entry_ids_by_path, resource_path)
	if entry_id == &"":
		return null
	var entry_resource: Resource = registry.get_entry(entry_id)
	if entry_resource is GFResourceRegistryEntry:
		var entry: GFResourceRegistryEntry = entry_resource
		return entry
	return null


func _make_entry_metadata(metadata: Dictionary, catalog_id: StringName, entry: GFResourceRegistryEntry) -> Dictionary:
	var entry_metadata: Dictionary = metadata.duplicate(true)
	entry_metadata["catalog_id"] = String(catalog_id)
	entry_metadata["entry_id"] = String(entry.id)
	entry_metadata["resource_path"] = entry.path
	return entry_metadata


static func _make_resolver_owner_id(catalog_id: StringName) -> StringName:
	return StringName("%s%s" % [_RESOLVER_OWNER_PREFIX, String(catalog_id)])


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()
