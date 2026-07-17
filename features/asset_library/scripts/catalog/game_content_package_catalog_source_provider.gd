@tool
## GameContentPackageCatalogSourceProvider: 将 GF 内容包目录适配为 GFAssetCatalog。
class_name GameContentPackageCatalogSourceProvider
extends GFAssetCatalogSourceProvider


# --- 私有变量 ---

var _content_catalog: GFContentPackageCatalog = null
var _required_content_type: String = ""


# --- 公共方法 ---

## 配置内容包目录来源。
## @param content_catalog: 已由 ProjectContentCatalogUtility 构建的目录快照。
## @param catalog_source_id: 目录来源稳定 ID。
## @param required_content_type: 可选的内容包类型筛选。
func configure_catalog(
	content_catalog: GFContentPackageCatalog,
	catalog_source_id: StringName,
	required_content_type: String = ""
) -> GFAssetCatalogSourceProvider:
	_content_catalog = content_catalog.duplicate_catalog() if content_catalog != null else null
	_required_content_type = required_content_type
	return configure(catalog_source_id)


## 从内容包资源声明构建 GF 标准资产目录。
## @param _options: 保留的目录构建选项；当前适配器不消费额外选项。
func build_catalog(_options: Dictionary = {}) -> GFAssetCatalog:
	var catalog: GFAssetCatalog = GFAssetCatalog.new()
	if _content_catalog == null:
		return catalog

	for package_id_text: String in _content_catalog.get_ordered_package_ids():
		var manifest: GFContentPackageManifest = _content_catalog.get_manifest(
			StringName(package_id_text)
		)
		if manifest == null:
			continue
		if not _required_content_type.is_empty():
			if not manifest.content_types.has(_required_content_type):
				continue
		_append_manifest_entries(catalog, manifest)
	return catalog


## 获取来源诊断状态。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	snapshot["required_content_type"] = _required_content_type
	snapshot["package_ids"] = (
		_content_catalog.get_package_ids()
		if _content_catalog != null
		else PackedStringArray()
	)
	return snapshot


# --- 私有/辅助方法 ---

func _append_manifest_entries(
	catalog: GFAssetCatalog,
	manifest: GFContentPackageManifest
) -> void:
	for resource_entry: Dictionary in manifest.get_normalized_resources():
		var asset_id: StringName = GFVariantData.get_option_string_name(resource_entry, "key")
		if asset_id == &"":
			continue
		var metadata: Dictionary = GFVariantData.get_option_dictionary(
			resource_entry,
			"metadata"
		).duplicate(true)
		metadata["content_package_id"] = String(manifest.package_id)
		var title: String = GFVariantData.get_option_string(
			metadata,
			"display_name",
			String(asset_id)
		)
		var description: String = GFVariantData.get_option_string(
			metadata,
			"description",
			GFVariantData.get_option_string(metadata, "source")
		)
		var entry: GFAssetCatalogEntry = GFAssetCatalogEntry.new()
		var _configured: GFAssetCatalogEntry = entry.configure(
			asset_id,
			GFVariantData.get_option_string(resource_entry, "path"),
			{
				"title": title,
				"description": description,
				"tags": GFVariantData.get_option_packed_string_array(metadata, "tags"),
				"category": GFVariantData.get_option_string_name(metadata, "category"),
				"type_hint": GFVariantData.get_option_string(resource_entry, "type_hint"),
				"source_id": source_id,
				"metadata": metadata,
			}
		)
		var _stored: bool = catalog.set_entry(entry)
