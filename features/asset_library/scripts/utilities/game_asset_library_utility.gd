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
const _RUNTIME_CATALOG_OWNER_ID: StringName = &"game.asset_library"
const _RUNTIME_CATALOG_MOUNT_ID: StringName = &"runtime_content_packages"
const _RUNTIME_CATALOG_SOURCE_ID: StringName = &"content_package"


# --- 私有变量 ---

var _resolver: GFResourceResolverUtility = null
var _project_content_catalog: ProjectContentCatalogUtility = null
var _last_catalog_report: Dictionary = {}
var _catalog_runtime: GFAssetCatalogRuntime = null
var _runtime_catalog_provider: GFContentPackageAssetCatalogProvider = null
var _runtime_catalog_mount: GFAssetCatalogMount = null


# --- GF 生命周期方法 ---

func init() -> void:
	_last_catalog_report.clear()
	_catalog_runtime = GFAssetCatalogRuntime.new().configure(
		GFAssetCatalogRuntime.CONFLICT_REJECT
	)


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
	_catalog_runtime = null


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
##
## 目录采用 GF 10 的规范 asset ID：`package_id/resource_key`。业务加载仍使用原有
## 稳定 resource key；需要读取目录条目时应调用 get_runtime_catalog_entry()。
func get_runtime_catalog() -> GFAssetCatalog:
	if _catalog_runtime == null or _runtime_catalog_mount == null:
		_rebuild_runtime_catalog()
	if _catalog_runtime == null:
		return GFAssetCatalog.new()
	return _catalog_runtime.get_catalog()


## 通过稳定 resource key 获取 GF 规范目录条目。
## @param asset_key: 内容包中声明的稳定素材键。
func get_runtime_catalog_entry(asset_key: StringName) -> GFAssetCatalogEntry:
	if asset_key == &"":
		return null
	return get_runtime_catalog().get_entry(make_runtime_catalog_asset_id(asset_key))


## 把项目稳定 resource key 转换为 GF 内容包目录规范 asset ID。
## @param asset_key: 内容包中声明的稳定素材键。
static func make_runtime_catalog_asset_id(asset_key: StringName) -> StringName:
	if asset_key == &"":
		return &""
	return StringName("%s/%s" % [String(ASSET_LIBRARY_PACKAGE_ID), String(asset_key)])


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
		"catalog_runtime": (
			_catalog_runtime.get_debug_snapshot() if _catalog_runtime != null else {}
		),
		"runtime_catalog_mount": (
			_runtime_catalog_mount.to_dict() if _runtime_catalog_mount != null else {}
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
	if not is_instance_valid(_project_content_catalog):
		return
	if _catalog_runtime == null:
		_catalog_runtime = GFAssetCatalogRuntime.new().configure(
			GFAssetCatalogRuntime.CONFLICT_REJECT
		)

	var query: GFContentPackageQuery = GFContentPackageQuery.new()
	query.query_id = &"game.asset_library.runtime"
	query.package_ids = PackedStringArray([String(ASSET_LIBRARY_PACKAGE_ID)])
	query.required_content_types = PackedStringArray(["asset_library"])
	var candidate_provider: GFContentPackageAssetCatalogProvider = (
		GFContentPackageAssetCatalogProvider.new()
	)
	var _configured: GFContentPackageAssetCatalogProvider = (
		candidate_provider.configure_catalog(
			_project_content_catalog.get_catalog(),
			_RUNTIME_CATALOG_SOURCE_ID,
			query,
			{"priority": 100}
		)
	)

	if _runtime_catalog_mount != null and _runtime_catalog_mount.is_active():
		var candidate_catalog: GFAssetCatalog = candidate_provider.build_catalog()
		if candidate_catalog == null:
			push_error("[GameAssetLibraryUtility] GF 内容包 Provider 构建目录失败，保留上一 revision。")
			return
		if not _catalog_runtime.replace_mount_catalog(
			_runtime_catalog_mount,
			candidate_catalog
		):
			push_error("[GameAssetLibraryUtility] GF 运行时目录原子替换失败，保留上一 revision。")
			return
		_runtime_catalog_provider = candidate_provider
		return

	var candidate_mount: GFAssetCatalogMount = _catalog_runtime.mount_provider(
		_RUNTIME_CATALOG_OWNER_ID,
		_RUNTIME_CATALOG_MOUNT_ID,
		candidate_provider
	)
	if not candidate_mount.is_active():
		push_error(
			"[GameAssetLibraryUtility] GF 运行时目录挂载失败：%s。"
			% String(candidate_mount.get_status())
		)
		return
	_runtime_catalog_provider = candidate_provider
	_runtime_catalog_mount = candidate_mount


func _clear_runtime_catalog() -> void:
	if _catalog_runtime != null:
		var _unmounted_count: int = _catalog_runtime.unmount_owner(
			_RUNTIME_CATALOG_OWNER_ID
		)
	_runtime_catalog_provider = null
	_runtime_catalog_mount = null
