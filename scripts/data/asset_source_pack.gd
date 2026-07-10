## AssetSourcePack: 记录一次外部素材包的来源、授权和导入摘要。
class_name AssetSourcePack
extends Resource


# --- 导出变量 ---

@export var source_pack_id: StringName = &""
@export var display_name: String = ""
@export var original_source_path: String = ""
@export var library_root_path: String = ""
@export var author: String = ""
@export var license: String = ""
@export var source_url: String = ""
@export var license_status: StringName = &"unknown"
@export var imported_at: String = ""
@export var file_count: int = 0
@export var review_record_count: int = 0
@export var byte_count: int = 0
@export var tags: PackedStringArray = PackedStringArray()
@export var notes: String = ""


# --- 公共方法 ---

func has_known_license() -> bool:
	return license_status == &"known" and not license.strip_edges().is_empty()


func get_summary_text() -> String:
	return "%s: %d files, %d review records" % [display_name, file_count, review_record_count]
