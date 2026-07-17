## ProjectContentCatalogUtility: 项目内容包目录 Adapter。
##
## Composition Root 只配置内容包 source root；本 Utility 统一负责 GF 内容包目录重建、
## Resolver 原子注册和资源查询。业务 Feature 不再直接修改全局 GFContentPackageUtility。
class_name ProjectContentCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal catalog_refreshed(report: Dictionary)


# --- 私有变量 ---

var _configured_source_roots: PackedStringArray = PackedStringArray()
var _owned_source_roots: PackedStringArray = PackedStringArray()
var _content_packages: GFContentPackageUtility = null
var _resolver: GFResourceResolverUtility = null
var _last_refresh_report: Dictionary = {}


# --- GF 生命周期方法 ---

func init() -> void:
	_owned_source_roots.clear()
	_last_refresh_report.clear()


func get_required_utilities() -> Array[Script]:
	return [GFContentPackageUtility, GFResourceResolverUtility]


func ready() -> void:
	_content_packages = _resolve_content_package_utility()
	_resolver = _resolve_resource_resolver_utility()
	_last_refresh_report = refresh()
	_log_report_issues(_last_refresh_report)


func dispose() -> void:
	if is_instance_valid(_content_packages):
		for source_root: String in _owned_source_roots:
			var _unregistered: bool = _content_packages.unregister_source_root(source_root)
	_owned_source_roots.clear()
	_last_refresh_report.clear()
	_content_packages = null
	_resolver = null


func release_dependencies() -> void:
	_content_packages = null
	_resolver = null
	super.release_dependencies()


# --- 公共方法 ---

## 配置项目拥有的内容包 source root。应由 Composition Root 在注册 Utility 前调用。
## @param source_roots: 项目需要集中发现的内容包根目录。
func configure_source_roots(source_roots: PackedStringArray) -> ProjectContentCatalogUtility:
	_configured_source_roots.clear()
	for source_root: String in source_roots:
		var normalized_root: String = source_root.strip_edges().trim_suffix("/")
		if normalized_root.is_empty() or _configured_source_roots.has(normalized_root):
			continue
		var _appended: bool = _configured_source_roots.append(normalized_root)
	return self


## 原子重建全部已注册内容包，并把资源键同步到 GF Resolver。
func refresh() -> Dictionary:
	var report: Dictionary = {
		"subject": "Project content catalog",
		"issues": [],
		"source_roots": _configured_source_roots.duplicate(),
	}
	if not is_instance_valid(_content_packages):
		var _content_issue: Dictionary = GFValidationReportDictionary.append_issue(
			report,
			"error",
			&"missing_content_package_utility",
			"GFContentPackageUtility 未注册。"
		)
		return _finalize_refresh_report(report)
	if not is_instance_valid(_resolver):
		var _resolver_issue: Dictionary = GFValidationReportDictionary.append_issue(
			report,
			"error",
			&"missing_resource_resolver",
			"GFResourceResolverUtility 未注册。"
		)
		return _finalize_refresh_report(report)

	var registered_roots: PackedStringArray = _content_packages.get_source_roots()
	for source_root: String in _configured_source_roots:
		if registered_roots.has(source_root):
			continue
		if _content_packages.register_source_root(source_root):
			var _owned_root_appended: bool = _owned_source_roots.append(source_root)
			var _registered_root_appended: bool = registered_roots.append(source_root)
			continue
		var _root_issue: Dictionary = GFValidationReportDictionary.append_issue(
			report,
			"error",
			&"source_root_registration_failed",
			"内容包 source root 注册失败：%s。" % source_root,
			{"path": source_root}
		)

	var catalog_report: Dictionary = _content_packages.rebuild_catalog({
		"check_resource_exists": true,
	})
	var _catalog_merged: Dictionary = GFValidationReportDictionary.merge_report(
		report,
		catalog_report,
		{
			"copy_fields": PackedStringArray([
				"package_count",
				"package_ids",
				"ordered_package_ids",
				"duplicate_package_ids",
			]),
		}
	)
	report["catalog"] = catalog_report.duplicate(true)

	if GFVariantData.get_option_bool(catalog_report, "ok", false):
		var registration_report: Dictionary = _content_packages.register_resources(
			_resolver,
			{"check_resource_exists": true}
		)
		var _registration_merged: Dictionary = GFValidationReportDictionary.merge_report(
			report,
			registration_report,
			{"copy_fields": PackedStringArray(["registered_count"])}
		)
		report["registration"] = registration_report.duplicate(true)

	return _finalize_refresh_report(report)


## 获取最近一次目录刷新报告副本。
func get_last_refresh_report() -> Dictionary:
	return _last_refresh_report.duplicate(true)


## 获取当前 GF 内容包目录的隔离快照。
func get_catalog() -> GFContentPackageCatalog:
	if not is_instance_valid(_content_packages):
		return GFContentPackageCatalog.new()
	return _content_packages.get_catalog()


## 按内容包、类型、资源键前缀和 metadata 查询资源声明。
## @param options: 内容包、类型、键前缀和 metadata 筛选条件。
## @schema options: Dictionary，可包含 package_ids、required_content_type、type_hint、key_prefix 和 metadata。
func query_resources(options: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog: GFContentPackageCatalog = get_catalog()
	var package_filter: PackedStringArray = GFVariantData.get_option_packed_string_array(
		options,
		"package_ids",
		PackedStringArray()
	)
	var required_content_type: String = GFVariantData.get_option_string(
		options,
		"required_content_type"
	)
	var required_type_hint: String = GFVariantData.get_option_string(options, "type_hint")
	var key_prefix: String = GFVariantData.get_option_string(options, "key_prefix")
	var metadata_filter: Dictionary = GFVariantData.get_option_dictionary(options, "metadata")

	for package_id_text: String in catalog.get_ordered_package_ids():
		if not package_filter.is_empty() and not package_filter.has(package_id_text):
			continue
		var manifest: GFContentPackageManifest = catalog.get_manifest(StringName(package_id_text))
		if manifest == null:
			continue
		if not required_content_type.is_empty() and not manifest.content_types.has(required_content_type):
			continue
		for entry: Dictionary in manifest.get_normalized_resources():
			if not _resource_entry_matches(entry, required_type_hint, key_prefix, metadata_filter):
				continue
			result.append(entry.duplicate(true))
	return result


## 通过稳定资源键加载已注册内容包资源。
## @param resource_key: 内容包中声明的稳定资源键。
## @param type_hint: 可选的资源类型约束。
## @param cache_mode: Godot ResourceLoader 缓存策略。
func load_resource(
	resource_key: StringName,
	type_hint: String = "",
	cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	if resource_key == &"" or not is_instance_valid(_resolver):
		return null
	return _resolver.load(resource_key, type_hint, cache_mode)


func get_debug_snapshot() -> Dictionary:
	return {
		"configured_source_roots": _configured_source_roots.duplicate(),
		"owned_source_roots": _owned_source_roots.duplicate(),
		"refresh_report": _last_refresh_report.duplicate(true),
		"content_packages": (
			_content_packages.get_debug_snapshot()
			if is_instance_valid(_content_packages)
			else {}
		),
		"resolver": _resolver.get_debug_snapshot() if is_instance_valid(_resolver) else {},
	}


# --- 私有/辅助方法 ---

func _finalize_refresh_report(report: Dictionary) -> Dictionary:
	_last_refresh_report = GFValidationReportDictionary.finalize_report(
		report,
		"Project content catalog",
		{
			"fallback_action": "检查首个内容包目录问题。",
			"no_action": "项目内容包目录已就绪。",
		}
	).duplicate(true)
	catalog_refreshed.emit(_last_refresh_report.duplicate(true))
	return _last_refresh_report.duplicate(true)


func _resource_entry_matches(
	entry: Dictionary,
	required_type_hint: String,
	key_prefix: String,
	metadata_filter: Dictionary
) -> bool:
	if not required_type_hint.is_empty():
		if GFVariantData.get_option_string(entry, "type_hint") != required_type_hint:
			return false
	if not key_prefix.is_empty():
		var resource_key: String = String(GFVariantData.get_option_string_name(entry, "key"))
		if not resource_key.begins_with(key_prefix):
			return false
	var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, "metadata")
	for filter_key: Variant in metadata_filter.keys():
		if not metadata.has(filter_key) or metadata[filter_key] != metadata_filter[filter_key]:
			return false
	return true


func _log_report_issues(report: Dictionary) -> void:
	for issue_variant: Variant in GFVariantData.get_option_array(report, "issues"):
		var issue: Dictionary = GFVariantData.as_dictionary(issue_variant)
		var message: String = GFVariantData.get_option_string(issue, "message")
		match GFVariantData.get_option_string(issue, "severity"):
			"error":
				push_error("[ProjectContentCatalogUtility] %s" % message)
			"warning":
				push_warning("[ProjectContentCatalogUtility] %s" % message)


func _resolve_content_package_utility() -> GFContentPackageUtility:
	var utility_value: Object = get_utility(GFContentPackageUtility)
	if utility_value is GFContentPackageUtility:
		var content_packages: GFContentPackageUtility = utility_value
		return content_packages
	return null


func _resolve_resource_resolver_utility() -> GFResourceResolverUtility:
	var utility_value: Object = get_utility(GFResourceResolverUtility)
	if utility_value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = utility_value
		return resolver
	return null
