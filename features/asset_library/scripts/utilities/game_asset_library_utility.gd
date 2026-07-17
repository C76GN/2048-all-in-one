## GameAssetLibraryUtility: 项目运行时素材解析 Adapter。
##
## 消费 ProjectContentCatalogUtility 已构建的内容目录，通过 GF Resolver 和 GFAssetCatalog
## 暴露稳定素材键；不再修改全局内容包 source root 或触发目录重建。
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
var _project_content_catalog: ProjectContentCatalogUtility = null
var _last_catalog_report: Dictionary = {}
var _catalog_sources: GFAssetCatalogSourceRegistry = null
var _runtime_catalog_provider: GameContentPackageCatalogSourceProvider = null
var _runtime_catalog: GFAssetCatalog = null


# --- GF 生命周期方法 ---

func init() -> void:
	_last_catalog_report.clear()


func get_required_utilities() -> Array[Script]:
	return [ProjectContentCatalogUtility, GFResourceResolverUtility]


func ready() -> void:
	_resolver = _get_resource_resolver_utility()
	_project_content_catalog = _get_project_content_catalog_utility()
	if is_instance_valid(_project_content_catalog):
		_last_catalog_report = _project_content_catalog.get_last_refresh_report()
	_rebuild_runtime_catalog()


func dispose() -> void:
	_resolver = null
	_project_content_catalog = null
	_last_catalog_report.clear()
	_clear_runtime_catalog()


func release_dependencies() -> void:
	_resolver = null
	_project_content_catalog = null
	super.release_dependencies()


# --- 公共方法 ---

## 解析稳定素材键到 Godot 资源路径。
## @param asset_key: 内容包中声明的稳定素材键。
## @param type_hint: 可选的资源类型约束。
func resolve_asset_path(asset_key: StringName, type_hint: String = "") -> String:
	var resolver: GFResourceResolverUtility = _get_resolver()
	if not is_instance_valid(resolver):
		return ""
	return resolver.resolve_path(asset_key, type_hint)


## 通过稳定素材键同步加载资源。
## @param asset_key: 内容包中声明的稳定素材键。
## @param type_hint: 可选的资源类型约束。
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


## 获取全部 asset_library 内容包对应的 GF 标准运行时素材目录副本。
func get_runtime_catalog() -> GFAssetCatalog:
	if _runtime_catalog == null:
		_rebuild_runtime_catalog()
	if _runtime_catalog == null:
		return GFAssetCatalog.new()
	return GFAssetCatalog.from_dict(_runtime_catalog.to_dict())


## 查询已注册运行时素材目录。
## @param query: 标题、标签或素材键搜索文本。
## @param options: GFAssetCatalog 搜索选项。
func search_runtime_assets(query: String, options: Dictionary = {}) -> Array[Dictionary]:
	return get_runtime_catalog().search(query, options)


func get_debug_snapshot() -> Dictionary:
	var content_catalog_snapshot: Dictionary = {}
	if is_instance_valid(_project_content_catalog):
		content_catalog_snapshot = _project_content_catalog.get_debug_snapshot()

	return {
		"asset_library_source_root": ASSET_LIBRARY_SOURCE_ROOT,
		"asset_library_manifest_path": ASSET_LIBRARY_MANIFEST_PATH,
		"asset_library_package_id": String(ASSET_LIBRARY_PACKAGE_ID),
		"catalog_report": _last_catalog_report.duplicate(true),
		"project_content_catalog": content_catalog_snapshot,
		"catalog_sources": (
			_catalog_sources.get_source_records() if _catalog_sources != null else []
		),
		"runtime_catalog": (
			_runtime_catalog.get_debug_snapshot() if _runtime_catalog != null else {}
		),
	}


# --- 私有/辅助方法 ---

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


func _get_project_content_catalog_utility() -> ProjectContentCatalogUtility:
	var utility_value: Object = get_utility(ProjectContentCatalogUtility)
	if utility_value is ProjectContentCatalogUtility:
		var catalog: ProjectContentCatalogUtility = utility_value
		return catalog
	return null


func _rebuild_runtime_catalog() -> void:
	_clear_runtime_catalog()
	_runtime_catalog = GFAssetCatalog.new()
	if not is_instance_valid(_project_content_catalog):
		return

	_catalog_sources = GFAssetCatalogSourceRegistry.new()
	_runtime_catalog_provider = _CONTENT_PACKAGE_CATALOG_SOURCE_SCRIPT.new()
	var _configured: GFAssetCatalogSourceProvider = (
		_runtime_catalog_provider.configure_catalog(
			_project_content_catalog.get_catalog(),
			&"content_package",
			"asset_library"
		)
	)
	var _registered: bool = _catalog_sources.register_source(
		_runtime_catalog_provider,
		{"priority": 100}
	)
	_runtime_catalog = _catalog_sources.build_catalog({
		"source_ids": PackedStringArray(["content_package"]),
	})


func _clear_runtime_catalog() -> void:
	if _catalog_sources != null:
		_catalog_sources.clear_sources()
	_catalog_sources = null
	_runtime_catalog_provider = null
	_runtime_catalog = null
