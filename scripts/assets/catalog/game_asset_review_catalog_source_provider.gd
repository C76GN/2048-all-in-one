@tool
## GameAssetReviewCatalogSourceProvider: 将项目候选素材评审记录适配为 GFAssetCatalog。
class_name GameAssetReviewCatalogSourceProvider
extends GFAssetCatalogSourceProvider


# --- 常量 ---

const _ASSET_REVIEW_RECORD_SCRIPT: Script = preload("res://scripts/data/asset_review_record.gd")
const _MAX_REVIEW_RECORD_COUNT: int = 20000


# --- 私有变量 ---

var _review_record_root: String = ""
var _last_scan_report: Dictionary = {}


# --- 公共方法 ---

## 配置候选素材记录来源。
## @param review_record_root: AssetReviewRecord 资源根目录。
## @param catalog_source_id: 目录来源稳定 ID。
## @return 当前 provider。
func configure_review_records(
	review_record_root: String,
	catalog_source_id: StringName
) -> GFAssetCatalogSourceProvider:
	_review_record_root = review_record_root
	_last_scan_report.clear()
	return configure(catalog_source_id)


## 构建包含审批状态、评分、标签和记录路径的 GF 标准资产目录。
## @param _options: 保留给后续来源筛选选项。
## @return 候选素材目录。
func build_catalog(_options: Dictionary = {}) -> GFAssetCatalog:
	var catalog: GFAssetCatalog = GFAssetCatalog.new()
	_last_scan_report = _scan_record_paths()
	if not GFVariantData.get_option_bool(_last_scan_report, "ok"):
		push_error("[GameAssetReviewCatalogSourceProvider] 候选素材记录目录无法扫描：%s。" % _review_record_root)
		return catalog
	if GFVariantData.get_option_bool(_last_scan_report, "truncated"):
		push_error("[GameAssetReviewCatalogSourceProvider] 候选素材记录扫描达到安全上限，拒绝构建不完整目录。")
		return catalog

	for record_path: String in GFVariantData.get_option_packed_string_array(_last_scan_report, "paths"):
		var record: Resource = ResourceLoader.load(record_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if record == null or record.get_script() != _ASSET_REVIEW_RECORD_SCRIPT:
			continue
		var entry: GFAssetCatalogEntry = _make_catalog_entry(record, record_path)
		if entry != null:
			var _stored: bool = catalog.set_entry(entry)
	return catalog


## 获取来源诊断状态。
## @return 来源配置快照。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	snapshot["review_record_root"] = _review_record_root
	snapshot["record_count"] = GFVariantData.get_option_int(_last_scan_report, "scanned_count")
	var scan_summary: Dictionary = _last_scan_report.duplicate(true)
	var _erase_result: bool = scan_summary.erase("paths")
	snapshot["scan_report"] = scan_summary
	return snapshot


## 获取最近一次 GF 路径枚举报告。
## @return 扫描报告副本。
func get_scan_report() -> Dictionary:
	return _last_scan_report.duplicate(true)


# --- 私有/辅助方法 ---

func _make_catalog_entry(record: Resource, record_path: String) -> GFAssetCatalogEntry:
	var asset_id: StringName = _get_string_name(record, "asset_id")
	if asset_id == &"":
		return null
	var kind: StringName = _get_string_name(record, "asset_kind", &"other")
	var status: StringName = _get_string_name(record, "review_status", &"inbox")
	var primary_path: String = _get_text(record, "library_path")
	if primary_path.is_empty():
		primary_path = _get_text(record, "source_path")

	var tags: PackedStringArray = _get_packed_strings(record, "tags")
	_append_tag(tags, "kind:%s" % String(kind))
	_append_tag(tags, "status:%s" % String(status))
	_append_tag(tags, "license:%s" % _get_text(record, "license_status", "unknown"))
	var source_pack_id: StringName = _get_string_name(record, "source_pack_id")
	if source_pack_id != &"":
		_append_tag(tags, "source:%s" % String(source_pack_id))

	var metadata: Dictionary = {
		"record_path": record_path,
		"review_status": String(status),
		"rating": _get_int(record, "rating"),
		"source_pack_id": String(source_pack_id),
		"source_path": _get_text(record, "source_path"),
		"library_path": _get_text(record, "library_path"),
		"relative_path": _get_text(record, "relative_path"),
		"license_status": _get_text(record, "license_status"),
		"license_id": _get_text(record, "license"),
		"creator": _get_text(record, "author"),
		"source_url": _get_text(record, "source_url"),
		"suggested_slots": _get_packed_strings(record, "suggested_slots"),
	}
	var entry: GFAssetCatalogEntry = GFAssetCatalogEntry.new()
	return entry.configure(asset_id, primary_path, {
		"title": _get_text(record, "display_name", String(asset_id)),
		"description": _get_text(record, "notes"),
		"tags": tags,
		"category": kind,
		"type_hint": _get_type_hint(kind),
		"preview_path": primary_path,
		"source_id": source_id,
		"metadata": metadata,
	})


func _scan_record_paths() -> Dictionary:
	return GFPathEnumerationTools.scan_files(_review_record_root, {
		"recursive": true,
		"include_hidden": false,
		"extensions": PackedStringArray(["tres"]),
		"max_file_count": _MAX_REVIEW_RECORD_COUNT,
		"sort": true,
	})


func _get_type_hint(kind: StringName) -> String:
	match kind:
		&"audio":
			return "AudioStream"
		&"shader", &"vfx":
			return "Shader"
		&"texture":
			return "Texture2D"
		_:
			return "Resource"


func _get_text(resource: Resource, property_name: String, fallback: String = "") -> String:
	return GFVariantData.to_text(resource.get(property_name), fallback)


func _get_string_name(
	resource: Resource,
	property_name: String,
	fallback: StringName = &""
) -> StringName:
	return GFVariantData.to_string_name(resource.get(property_name), fallback)


func _get_int(resource: Resource, property_name: String, fallback: int = 0) -> int:
	return GFVariantData.to_int(resource.get(property_name), fallback)


func _get_packed_strings(resource: Resource, property_name: String) -> PackedStringArray:
	return GFVariantData.get_option_packed_string_array({"value": resource.get(property_name)}, "value")


func _append_tag(tags: PackedStringArray, tag: String) -> void:
	if not tag.is_empty() and not tags.has(tag):
		var _appended: bool = tags.append(tag)
