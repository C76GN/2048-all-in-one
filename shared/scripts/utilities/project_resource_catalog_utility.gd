## ProjectResourceCatalogUtility: 项目资源目录 Adapter。
##
## 把 GFResourceRegistry、GFResourceResolverUtility 和 GFAssetUtility 的组合用法集中起来，
## 让模式、UI 路由、主题等项目 Module 不再重复实现注册、解析和缓存细节。
class_name ProjectResourceCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 私有变量 ---

var _asset_utility: GFAssetUtility = null
var _resource_resolver: GFResourceResolverUtility = null
var _catalogs: Dictionary = {}


# --- GF 生命周期方法 ---

func ready() -> void:
	_asset_utility = _resolve_asset_utility()
	_resource_resolver = _resolve_resource_resolver_utility()


func dispose() -> void:
	_asset_utility = null
	_resource_resolver = null
	_catalogs.clear()


# --- 公共方法 ---

## 注册一个项目资源目录。
## @param catalog_id: 项目内稳定目录 ID。
## @param registry: 资源注册表。
## @param resource_key_prefix: 写入 GFResourceResolverUtility 的资源键前缀。
## @param default_type_hint: 条目未指定类型时使用的默认类型。
## @param group_id: 写入 GFAssetUtility 的资源分组 ID。
## @param metadata: 附加到解析器注册项的元数据。
## @param pin_group_paths: 是否固定分组路径，避免清理时误卸载。
## @param priority: 写入解析器的解析优先级。
func register_catalog(
	catalog_id: StringName,
	registry: GFResourceRegistry,
	resource_key_prefix: String,
	default_type_hint: String = "",
	group_id: StringName = &"",
	metadata: Dictionary = {},
	pin_group_paths: bool = true,
	priority: int = 0
) -> Dictionary:
	var report: Dictionary = _make_registration_report(catalog_id)
	if catalog_id == &"" or not is_instance_valid(registry) or resource_key_prefix.is_empty():
		_add_report_issue(report, "error", "invalid_catalog", "资源目录配置无效。")
		_finalize_registration_report(report)
		return report

	_catalogs[catalog_id] = {
		"registry": registry,
		"resource_key_prefix": resource_key_prefix,
		"default_type_hint": default_type_hint,
		"group_id": group_id,
		"metadata": metadata.duplicate(true),
		"pin_group_paths": pin_group_paths,
		"priority": priority,
	}

	var asset_utility: GFAssetUtility = _get_asset_utility()
	var resolver: GFResourceResolverUtility = _get_resource_resolver()
	for entry: GFResourceRegistryEntry in registry.entries:
		if not _is_valid_registry_entry(entry):
			_add_report_issue(report, "warning", "invalid_entry", "资源目录包含无效条目。")
			continue

		var resource_key: StringName = make_resource_key(entry, resource_key_prefix)
		var type_hint: String = get_entry_type_hint(entry, default_type_hint)
		if is_instance_valid(asset_utility) and group_id != &"":
			asset_utility.register_group_path(group_id, entry.path, pin_group_paths)
		if is_instance_valid(resolver):
			var registered: bool = resolver.register_path(
				resource_key,
				entry.path,
				type_hint,
				priority,
				_make_entry_metadata(metadata, catalog_id, entry)
			)
			if not registered:
				_add_report_issue(report, "error", "resolver_registration_failed", "资源键注册失败：%s。" % String(resource_key))
				continue

		_append_report_string(report, "paths", entry.path)
		_append_report_string(report, "resource_keys", String(resource_key))

	_finalize_registration_report(report)
	return report


## 获取目录中的有效资源路径，保持注册表顺序。
## @param catalog_id: 项目内稳定目录 ID。
## @param check_resolvable: 是否只返回解析器可解析的条目。
func get_registered_paths(catalog_id: StringName, check_resolvable: bool = false) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var catalog: Dictionary = _get_catalog(catalog_id)
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	if not is_instance_valid(registry):
		return result

	for entry: GFResourceRegistryEntry in registry.entries:
		if not _is_valid_registry_entry(entry):
			continue
		if check_resolvable and not _is_entry_resolvable(catalog, entry):
			continue
		var _append_result: bool = result.append(entry.path)
	return result


## 获取目录中已注册的稳定资源键，保持注册表顺序。
## @param catalog_id: 项目内稳定目录 ID。
func get_registered_resource_keys(catalog_id: StringName) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var catalog: Dictionary = _get_catalog(catalog_id)
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	if not is_instance_valid(registry):
		return result

	var resource_key_prefix: String = _get_catalog_resource_key_prefix(catalog)
	for entry: GFResourceRegistryEntry in registry.entries:
		if not _is_valid_registry_entry(entry):
			continue
		var _append_result: bool = result.append(String(make_resource_key(entry, resource_key_prefix)))
	return result


## 通过目录资源路径加载资源，并复用 GFAssetUtility 缓存。
## @param catalog_id: 项目内稳定目录 ID。
## @param resource_path: 注册表中的资源路径。
## @param cache_mode: 传递给 Godot ResourceLoader 的缓存模式。
func load_resource_by_path(
	catalog_id: StringName,
	resource_path: String,
	cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	if resource_path.is_empty():
		return null

	var catalog: Dictionary = _get_catalog(catalog_id)
	var registry: GFResourceRegistry = _get_catalog_registry(catalog)
	var entry: GFResourceRegistryEntry = find_entry_by_path(registry, resource_path)
	if not _is_valid_registry_entry(entry):
		return null
	return load_resource_by_entry(catalog_id, entry, cache_mode)


## 通过目录条目加载资源，并复用 GFAssetUtility 缓存。
## @param catalog_id: 项目内稳定目录 ID。
## @param entry: 注册表条目。
## @param cache_mode: 传递给 Godot ResourceLoader 的缓存模式。
func load_resource_by_entry(
	catalog_id: StringName,
	entry: GFResourceRegistryEntry,
	cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	if not _is_valid_registry_entry(entry):
		return null

	var catalog: Dictionary = _get_catalog(catalog_id)
	var type_hint: String = get_entry_type_hint(entry, _get_catalog_default_type_hint(catalog))
	var asset_utility: GFAssetUtility = _get_asset_utility()
	if is_instance_valid(asset_utility):
		var cached: Resource = asset_utility.get_cached(entry.path)
		if _is_resource_compatible(cached, type_hint):
			return cached

	var resolver: GFResourceResolverUtility = _get_resource_resolver()
	var resource: Resource = null
	if is_instance_valid(resolver):
		resource = resolver.load(
			make_resource_key(entry, _get_catalog_resource_key_prefix(catalog)),
			type_hint,
			cache_mode
		)
	else:
		var registry: GFResourceRegistry = _get_catalog_registry(catalog)
		if is_instance_valid(registry):
			resource = registry.load_entry(entry.id, type_hint, cache_mode)

	if _is_resource_compatible(resource, type_hint) and is_instance_valid(asset_utility):
		asset_utility.put_cache(entry.path, resource)
	return resource


## 卸载目录关联的 GFAssetUtility 分组。
## @param catalog_id: 项目内稳定目录 ID。
## @param remove_unreferenced_cache: 是否同时移除未被引用的缓存。
func unload_catalog_group(catalog_id: StringName, remove_unreferenced_cache: bool = false) -> void:
	var catalog: Dictionary = _get_catalog(catalog_id)
	var group_id: StringName = _get_catalog_group_id(catalog)
	if group_id == &"":
		return

	var asset_utility: GFAssetUtility = _get_asset_utility()
	if is_instance_valid(asset_utility):
		asset_utility.unload_group(group_id, remove_unreferenced_cache)


func get_debug_snapshot() -> Dictionary:
	var catalogs: Dictionary = {}
	for catalog_id_value: Variant in _catalogs.keys():
		var catalog_id: StringName = GFVariantData.to_string_name(catalog_id_value, &"")
		catalogs[String(catalog_id)] = {
			"paths": get_registered_paths(catalog_id, false),
			"resource_keys": get_registered_resource_keys(catalog_id),
			"group_id": String(_get_catalog_group_id(_get_catalog(catalog_id))),
		}
	return {
		"catalog_count": _catalogs.size(),
		"catalogs": catalogs,
	}


## @param registry: 资源注册表。
## @param resource_path: 要匹配的资源路径。
static func find_entry_by_path(registry: GFResourceRegistry, resource_path: String) -> GFResourceRegistryEntry:
	if not is_instance_valid(registry) or resource_path.is_empty():
		return null

	for entry: GFResourceRegistryEntry in registry.entries:
		if _is_valid_registry_entry(entry) and entry.path == resource_path:
			return entry
	return null


## @param entry: 注册表条目。
## @param resource_key_prefix: 资源键前缀。
static func make_resource_key(entry: GFResourceRegistryEntry, resource_key_prefix: String) -> StringName:
	if not _is_valid_registry_entry(entry) or resource_key_prefix.is_empty():
		return &""
	return StringName("%s%s" % [resource_key_prefix, String(entry.id)])


## @param entry: 注册表条目。
## @param default_type_hint: 条目未指定类型时使用的默认类型。
static func get_entry_type_hint(entry: GFResourceRegistryEntry, default_type_hint: String = "") -> String:
	if entry != null and not entry.type_hint.is_empty():
		return entry.type_hint
	return default_type_hint


# --- 私有/辅助方法 ---

func _get_catalog(catalog_id: StringName) -> Dictionary:
	if _catalogs.has(catalog_id):
		return GFVariantData.as_dictionary(_catalogs[catalog_id])
	return {}


func _is_entry_resolvable(catalog: Dictionary, entry: GFResourceRegistryEntry) -> bool:
	var resolver: GFResourceResolverUtility = _get_resource_resolver()
	if not is_instance_valid(resolver):
		return true

	var report: Dictionary = resolver.resolve(
		make_resource_key(entry, _get_catalog_resource_key_prefix(catalog)),
		get_entry_type_hint(entry, _get_catalog_default_type_hint(catalog))
	)
	return GFVariantData.get_option_bool(report, "ok", false)


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
		var asset_utility: GFAssetUtility = utility_value
		return asset_utility
	return null


func _resolve_resource_resolver_utility() -> GFResourceResolverUtility:
	var utility_value: Object = get_utility(GFResourceResolverUtility)
	if utility_value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = utility_value
		return resolver
	return null


func _get_catalog_registry(catalog: Dictionary) -> GFResourceRegistry:
	var value: Variant = GFVariantData.get_option_value(catalog, "registry")
	if value is GFResourceRegistry:
		var registry: GFResourceRegistry = value
		return registry
	return null


func _get_catalog_resource_key_prefix(catalog: Dictionary) -> String:
	return GFVariantData.get_option_string(catalog, "resource_key_prefix")


func _get_catalog_default_type_hint(catalog: Dictionary) -> String:
	return GFVariantData.get_option_string(catalog, "default_type_hint")


func _get_catalog_group_id(catalog: Dictionary) -> StringName:
	return GFVariantData.get_option_string_name(catalog, "group_id")


func _make_entry_metadata(metadata: Dictionary, catalog_id: StringName, entry: GFResourceRegistryEntry) -> Dictionary:
	var result: Dictionary = metadata.duplicate(true)
	result["catalog_id"] = String(catalog_id)
	result["entry_id"] = String(entry.id)
	return result


func _make_registration_report(catalog_id: StringName) -> Dictionary:
	return {
		"ok": true,
		"healthy": true,
		"catalog_id": String(catalog_id),
		"paths": PackedStringArray(),
		"resource_keys": PackedStringArray(),
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
		"warning_count": 0,
	}


func _add_report_issue(report: Dictionary, severity: String, kind: String, message: String) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	issues.append({
		"severity": severity,
		"kind": kind,
		"message": message,
	})
	report["issues"] = issues
	if severity == "error":
		report["error_count"] = GFVariantData.get_option_int(report, "error_count", 0) + 1
	elif severity == "warning":
		report["warning_count"] = GFVariantData.get_option_int(report, "warning_count", 0) + 1


func _finalize_registration_report(report: Dictionary) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	report["issue_count"] = issues.size()
	report["ok"] = GFVariantData.get_option_int(report, "error_count", 0) == 0
	report["healthy"] = (
		GFVariantData.get_option_int(report, "error_count", 0) == 0
		and GFVariantData.get_option_int(report, "warning_count", 0) == 0
	)


func _append_report_string(report: Dictionary, key: String, value: String) -> void:
	var values: PackedStringArray = GFVariantData.get_option_packed_string_array(
		report,
		key,
		PackedStringArray()
	)
	if value.is_empty() or values.has(value):
		return
	var _append_result: bool = values.append(value)
	report[key] = values


static func _is_valid_registry_entry(entry: GFResourceRegistryEntry) -> bool:
	return entry != null and entry.is_valid_entry()


static func _is_resource_compatible(resource: Resource, type_hint: String) -> bool:
	if resource == null:
		return false
	if type_hint.is_empty() or resource.is_class(type_hint):
		return true

	var script_value: Variant = resource.get_script()
	var script: Script = script_value if script_value is Script else null
	while script != null:
		if GFVariantData.to_text(script.get_global_name()) == type_hint or script.resource_path == type_hint:
			return true
		script = script.get_base_script()
	return false
