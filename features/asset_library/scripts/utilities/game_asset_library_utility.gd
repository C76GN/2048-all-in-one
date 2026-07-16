## GameAssetLibraryUtility: 项目运行时素材解析 Adapter。
##
## 通过 GF 内容包、资源解析器与标准素材目录隐藏素材路径，并只暴露稳定素材键。
class_name GameAssetLibraryUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const ASSET_LIBRARY_PACKAGE_ID: StringName = &"c76.asset_library.core"
const ASSET_LIBRARY_SOURCE_ROOT: String = "res://features/asset_library/resources"
const ASSET_LIBRARY_MANIFEST_PATH: String = (
	"res://features/asset_library/resources/gf_content_package.json"
)
const _CONTENT_PACKAGE_CATALOG_SOURCE_SCRIPT = preload(
	"res://features/asset_library/scripts/catalog/game_content_package_catalog_source_provider.gd"
)


# --- 私有变量 ---

var _resolver: GFResourceResolverUtility = null
var _content_packages: GFContentPackageUtility = null
var _last_registration_report: Dictionary = {}
var _catalog_sources: GFAssetCatalogSourceRegistry = null
var _runtime_catalog_provider: GameContentPackageCatalogSourceProvider = null
var _runtime_catalog: GFAssetCatalog = null


# --- GF 生命周期方法 ---

func init() -> void:
	_last_registration_report.clear()
	_ensure_catalog_source()


func get_required_utilities() -> Array[Script]:
	return [GFContentPackageUtility, GFResourceResolverUtility]


func ready() -> void:
	_resolver = _get_resource_resolver_utility()
	_content_packages = _get_content_package_utility()
	_last_registration_report = register_asset_library_content_package_resources()
	_rebuild_runtime_catalog()


func dispose() -> void:
	_resolver = null
	_content_packages = null
	_last_registration_report.clear()
	if _catalog_sources != null:
		_catalog_sources.clear_sources()
	_catalog_sources = null
	_runtime_catalog_provider = null
	_runtime_catalog = null


func release_dependencies() -> void:
	_resolver = null
	_content_packages = null
	super.release_dependencies()


# --- 公共方法 ---

func register_asset_library_content_package_resources() -> Dictionary:
	_last_registration_report = _make_report("asset_library_content_package")
	if not is_instance_valid(_resolver):
		_add_report_issue(
			_last_registration_report,
			"error",
			"missing_resolver",
			"缺少 GFResourceResolverUtility。"
		)
		_finalize_report(_last_registration_report)
		return _last_registration_report
	if not is_instance_valid(_content_packages):
		_add_report_issue(
			_last_registration_report,
			"error",
			"missing_content_package_utility",
			"缺少 GFContentPackageUtility。"
		)
		_finalize_report(_last_registration_report)
		return _last_registration_report

	var _source_registered: bool = _content_packages.register_source_root(
		ASSET_LIBRARY_SOURCE_ROOT
	)
	var catalog_report: Dictionary = _content_packages.rebuild_catalog(
		{"check_resource_exists": true}
	)
	if not _is_report_ok(catalog_report):
		_add_report_issue(
			_last_registration_report,
			"error",
			"catalog_rebuild_failed",
			GFVariantData.get_option_string(
				catalog_report,
				"summary",
				"素材库内容包目录构建失败。"
			)
		)

	var registration_report: Dictionary = _content_packages.register_resources(
		_resolver,
		{"check_resource_exists": true}
	)
	if not _is_report_ok(registration_report):
		_add_report_issue(
			_last_registration_report,
			"error",
			"resource_registration_failed",
			GFVariantData.get_option_string(
				registration_report,
				"summary",
				"素材库资源注册失败。"
			)
		)

	_last_registration_report["catalog"] = catalog_report
	_last_registration_report["registration"] = registration_report
	_finalize_report(_last_registration_report)
	return _last_registration_report.duplicate(true)


## 解析稳定素材键到 Godot 资源路径。
## @param asset_key: 内容包中注册的稳定素材键。
## @param type_hint: 可选资源类型约束。
func resolve_asset_path(asset_key: StringName, type_hint: String = "") -> String:
	var resolver: GFResourceResolverUtility = _get_resolver()
	if not is_instance_valid(resolver):
		return ""
	return resolver.resolve_path(asset_key, type_hint)


## 通过稳定素材键同步加载资源。
## @param asset_key: 内容包中注册的稳定素材键。
## @param type_hint: 可选资源类型约束。
## @param cache_mode: Godot ResourceLoader 缓存策略。
func load_asset(
	asset_key: StringName,
	type_hint: String = "",
	cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	var resolver: GFResourceResolverUtility = _get_resolver()
	if not is_instance_valid(resolver):
		return null
	return resolver.load(asset_key, type_hint, cache_mode)


## 获取内容包 manifest 对应的 GF 标准运行时素材目录副本。
func get_runtime_catalog() -> GFAssetCatalog:
	if _runtime_catalog == null:
		_rebuild_runtime_catalog()
	if _runtime_catalog == null:
		return GFAssetCatalog.new()
	return GFAssetCatalog.from_dict(_runtime_catalog.to_dict())


## 查询已注册到运行时内容包的素材目录。
## @param query: 匹配素材键、路径、类型和标签的查询文本。
## @param options: GFAssetCatalog 搜索选项。
func search_runtime_assets(query: String, options: Dictionary = {}) -> Array[Dictionary]:
	return get_runtime_catalog().search(query, options)


func get_debug_snapshot() -> Dictionary:
	var content_package_snapshot: Dictionary = {}
	if is_instance_valid(_content_packages):
		content_package_snapshot = _content_packages.get_debug_snapshot()

	var resolver_snapshot: Dictionary = {}
	if is_instance_valid(_resolver):
		resolver_snapshot = _resolver.get_debug_snapshot()

	return {
		"asset_library_source_root": ASSET_LIBRARY_SOURCE_ROOT,
		"asset_library_manifest_path": ASSET_LIBRARY_MANIFEST_PATH,
		"asset_library_package_id": String(ASSET_LIBRARY_PACKAGE_ID),
		"registration_report": _last_registration_report.duplicate(true),
		"content_packages": content_package_snapshot,
		"resolver": resolver_snapshot,
		"catalog_sources": (
			_catalog_sources.get_source_records() if _catalog_sources != null else []
		),
		"runtime_catalog": (
			_runtime_catalog.get_debug_snapshot() if _runtime_catalog != null else {}
		),
	}


# --- 私有方法 ---

func _get_resolver() -> GFResourceResolverUtility:
	if is_instance_valid(_resolver):
		return _resolver
	_resolver = _get_resource_resolver_utility()
	return _resolver


func _get_resource_resolver_utility() -> GFResourceResolverUtility:
	var utility_value: Object = get_utility(GFResourceResolverUtility)
	if utility_value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = utility_value
		return resolver
	return null


func _get_content_package_utility() -> GFContentPackageUtility:
	var utility_value: Object = get_utility(GFContentPackageUtility)
	if utility_value is GFContentPackageUtility:
		var content_package_utility: GFContentPackageUtility = utility_value
		return content_package_utility
	return null


func _ensure_catalog_source() -> void:
	if _catalog_sources != null:
		return
	_catalog_sources = GFAssetCatalogSourceRegistry.new()
	_runtime_catalog_provider = _CONTENT_PACKAGE_CATALOG_SOURCE_SCRIPT.new()
	var _configured: GFAssetCatalogSourceProvider = (
		_runtime_catalog_provider.configure_manifest(
			ASSET_LIBRARY_MANIFEST_PATH,
			&"content_package"
		)
	)
	var _registered: bool = _catalog_sources.register_source(
		_runtime_catalog_provider,
		{"priority": 100}
	)


func _rebuild_runtime_catalog() -> void:
	_ensure_catalog_source()
	_runtime_catalog = GFAssetCatalog.new()
	if _catalog_sources == null or _runtime_catalog_provider == null:
		return
	_runtime_catalog = _catalog_sources.build_catalog({
		"source_ids": PackedStringArray(["content_package"]),
	})


func _make_report(report_id: String) -> Dictionary:
	return {
		"ok": true,
		"healthy": true,
		"report_id": report_id,
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
		"warning_count": 0,
	}


func _add_report_issue(
	report: Dictionary,
	severity: String,
	kind: String,
	message: String
) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	issues.append({
		"severity": severity,
		"kind": kind,
		"message": message,
	})
	report["issues"] = issues
	if severity == "error":
		report["error_count"] = GFVariantData.get_option_int(report, "error_count") + 1
	elif severity == "warning":
		report["warning_count"] = GFVariantData.get_option_int(report, "warning_count") + 1


func _finalize_report(report: Dictionary) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	report["issue_count"] = issues.size()
	report["ok"] = GFVariantData.get_option_int(report, "error_count") == 0
	report["healthy"] = (
		GFVariantData.get_option_int(report, "error_count") == 0
		and GFVariantData.get_option_int(report, "warning_count") == 0
	)


func _is_report_ok(report: Dictionary) -> bool:
	return GFVariantData.get_option_bool(report, "ok", false)
