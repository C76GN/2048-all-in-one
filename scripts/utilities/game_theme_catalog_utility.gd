## GameThemeCatalogUtility: 项目主题内容目录。
##
## 负责把内置主题内容包注册进 GFContentPackageUtility/GFResourceResolverUtility，
## 并提供稳定的主题注册表读取入口。
class_name GameThemeCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const THEME_REGISTRY_RESOURCE_KEY: StringName = &"game.theme_registry"
const CONTENT_PACKAGE_SOURCE_ROOT: String = "res://resources"
const _REGISTRY_PATH: String = "res://resources/registries/game_theme_registry.tres"
const _REGISTRY_TYPE_HINT: String = "GameThemeRegistry"


# --- 私有变量 ---

var _registry: GameThemeRegistry = null
var _resolver: GFResourceResolverUtility = null
var _content_packages: GFContentPackageUtility = null
var _last_registration_report: Dictionary = {}
var _registry_validation_report: GFValidationReport = null


# --- GF 生命周期方法 ---

func init() -> void:
	_registry = null
	_registry_validation_report = null
	_last_registration_report.clear()


func ready() -> void:
	_resolver = _get_resource_resolver_utility()
	_content_packages = _get_content_package_utility()
	_last_registration_report = register_theme_content_package_resources()
	_registry = _load_registry()


func dispose() -> void:
	_registry = null
	_registry_validation_report = null
	_resolver = null
	_content_packages = null
	_last_registration_report.clear()


func release_dependencies() -> void:
	_registry = null
	_registry_validation_report = null
	_resolver = null
	_content_packages = null
	super.release_dependencies()


# --- 公共方法 ---

func get_registry() -> GameThemeRegistry:
	if not is_instance_valid(_registry):
		_registry = _load_registry()
	return _registry


## 获取最近一次主题注册表 GF 校验报告副本。
func get_registry_validation_report() -> GFValidationReport:
	if not is_instance_valid(_registry_validation_report):
		var _registry_value: GameThemeRegistry = get_registry()
	if not is_instance_valid(_registry_validation_report):
		return GFValidationReport.new("GameThemeRegistry")
	var duplicate_value: RefCounted = _registry_validation_report.duplicate_report()
	if duplicate_value is GFValidationReport:
		var duplicate_report: GFValidationReport = duplicate_value
		return duplicate_report
	return GFValidationReport.new("GameThemeRegistry")


func register_theme_content_package_resources() -> Dictionary:
	_last_registration_report = _make_report("theme_content_package")
	if not is_instance_valid(_resolver):
		_add_report_issue(_last_registration_report, "error", "missing_resolver", "缺少 GFResourceResolverUtility。")
		_finalize_report(_last_registration_report)
		return _last_registration_report
	if not is_instance_valid(_content_packages):
		_add_report_issue(_last_registration_report, "error", "missing_content_package_utility", "缺少 GFContentPackageUtility。")
		_finalize_report(_last_registration_report)
		return _last_registration_report

	var _source_registered: bool = _content_packages.register_source_root(CONTENT_PACKAGE_SOURCE_ROOT)
	var catalog_report: Dictionary = _content_packages.rebuild_catalog({"check_resource_exists": true})
	if not _is_report_ok(catalog_report):
		_add_report_issue(
			_last_registration_report,
			"error",
			"catalog_rebuild_failed",
			GFVariantData.get_option_string(catalog_report, "summary", "主题内容包目录构建失败。")
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
			GFVariantData.get_option_string(registration_report, "summary", "主题内容包资源注册失败。")
		)

	_last_registration_report["catalog"] = catalog_report
	_last_registration_report["registration"] = registration_report
	_finalize_report(_last_registration_report)
	return _last_registration_report


func get_debug_snapshot() -> Dictionary:
	var content_package_snapshot: Dictionary = {}
	if is_instance_valid(_content_packages):
		content_package_snapshot = _content_packages.get_debug_snapshot()

	var resolver_snapshot: Dictionary = {}
	if is_instance_valid(_resolver):
		resolver_snapshot = _resolver.get_debug_snapshot()
	var validation_snapshot: Dictionary = {}
	if is_instance_valid(_registry_validation_report):
		validation_snapshot = _registry_validation_report.to_dict()

	return {
		"content_package_source_root": CONTENT_PACKAGE_SOURCE_ROOT,
		"theme_registry_key": THEME_REGISTRY_RESOURCE_KEY,
		"registration_report": _last_registration_report.duplicate(true),
		"registry_validation": validation_snapshot,
		"content_packages": content_package_snapshot,
		"resolver": resolver_snapshot,
	}


# --- 私有/辅助方法 ---

func _load_registry() -> GameThemeRegistry:
	var resource: Resource = null
	if is_instance_valid(_resolver):
		resource = _resolver.load(THEME_REGISTRY_RESOURCE_KEY, _REGISTRY_TYPE_HINT)
	if resource is GameThemeRegistry:
		var registry: GameThemeRegistry = resource
		_registry_validation_report = registry.get_validation_report()
		if _registry_validation_report.is_ok():
			return registry
		_log_registry_validation_issues(_registry_validation_report)
		return GameThemeRegistry.new()

	_registry_validation_report = GFValidationReport.new(
		"GameThemeRegistry",
		{
			"resource_key": THEME_REGISTRY_RESOURCE_KEY,
			"resource_path": _REGISTRY_PATH,
		}
	)
	var _issue: RefCounted = _registry_validation_report.add_error(
		&"theme_registry_load_failed",
		"主题注册表资源键加载失败。",
		THEME_REGISTRY_RESOURCE_KEY,
		_REGISTRY_PATH
	)
	_log_registry_validation_issues(_registry_validation_report)
	return GameThemeRegistry.new()


func _log_registry_validation_issues(report: GFValidationReport) -> void:
	for issue: GFValidationIssue in report.issues:
		if issue == null:
			continue
		if issue.is_error():
			push_error("[GameThemeCatalogUtility] %s" % issue.message)
		elif issue.is_warning():
			push_warning("[GameThemeCatalogUtility] %s" % issue.message)


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


func _is_report_ok(report: Dictionary) -> bool:
	return GFVariantData.get_option_bool(report, "ok", false)


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


func _finalize_report(report: Dictionary) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	report["issue_count"] = issues.size()
	report["ok"] = GFVariantData.get_option_int(report, "error_count", 0) == 0
	report["healthy"] = (
		GFVariantData.get_option_int(report, "error_count", 0) == 0
		and GFVariantData.get_option_int(report, "warning_count", 0) == 0
	)
