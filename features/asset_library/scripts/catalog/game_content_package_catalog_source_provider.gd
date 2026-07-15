@tool
## GameContentPackageCatalogSourceProvider: 将 GF 内容包 manifest 适配为 GFAssetCatalog。
class_name GameContentPackageCatalogSourceProvider
extends GFAssetCatalogSourceProvider


# --- 私有变量 ---

var _manifest_path: String = ""


# --- 公共方法 ---

## 配置内容包目录来源。
## @param manifest_path: GFContentPackageManifest JSON 路径。
## @param catalog_source_id: 目录来源稳定 ID。
## @return 当前 provider。
func configure_manifest(
	manifest_path: String,
	catalog_source_id: StringName
) -> GFAssetCatalogSourceProvider:
	_manifest_path = manifest_path
	return configure(catalog_source_id)


## 从内容包资源声明构建 GF 标准资产目录。
## @param _options: 保留给后续来源筛选选项。
## @return 内容包资产目录。
func build_catalog(_options: Dictionary = {}) -> GFAssetCatalog:
	var catalog: GFAssetCatalog = GFAssetCatalog.new()
	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(_manifest_path)
	if manifest == null:
		return catalog

	for resource_entry: Dictionary in manifest.get_normalized_resources():
		var asset_id: StringName = GFVariantData.get_option_string_name(resource_entry, "key")
		if asset_id == &"":
			continue
		var metadata: Dictionary = GFVariantData.get_option_dictionary(resource_entry, "metadata").duplicate(true)
		metadata["content_package_id"] = String(manifest.package_id)
		var title: String = GFVariantData.get_option_string(metadata, "display_name", String(asset_id))
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
				"tags": GFVariantData.get_option_packed_string_array(resource_entry, "tags"),
				"category": GFVariantData.get_option_string_name(metadata, "category"),
				"type_hint": GFVariantData.get_option_string(resource_entry, "type_hint"),
				"source_id": source_id,
				"metadata": metadata,
			}
		)
		var _stored: bool = catalog.set_entry(entry)
	return catalog


## 获取来源诊断状态。
## @return 来源配置快照。
func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_debug_snapshot()
	snapshot["manifest_path"] = _manifest_path
	snapshot["manifest_exists"] = FileAccess.file_exists(_manifest_path)
	return snapshot
