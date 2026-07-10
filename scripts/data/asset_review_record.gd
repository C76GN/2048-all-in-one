## AssetReviewRecord: 单个候选素材的评审、授权和用途备注记录。
class_name AssetReviewRecord
extends Resource


# --- 常量 ---

const STATUS_INBOX: StringName = &"inbox"
const STATUS_CANDIDATE: StringName = &"candidate"
const STATUS_APPROVED: StringName = &"approved"
const STATUS_REJECTED: StringName = &"rejected"
const STATUS_BLOCKED_LICENSE: StringName = &"blocked_license"
const STATUS_ARCHIVED: StringName = &"archived"

const KIND_AUDIO: StringName = &"audio"
const KIND_SHADER: StringName = &"shader"
const KIND_TEXTURE: StringName = &"texture"
const KIND_VFX: StringName = &"vfx"
const KIND_OTHER: StringName = &"other"


# --- 导出变量 ---

@export var asset_id: StringName = &""
@export var source_pack_id: StringName = &""
@export var display_name: String = ""
@export var asset_kind: StringName = KIND_OTHER
@export var review_status: StringName = STATUS_INBOX
@export var tags: PackedStringArray = PackedStringArray()
@export var notes: String = ""
@export_range(0, 5, 1) var rating: int = 0

@export var source_path: String = ""
@export var library_path: String = ""
@export var relative_path: String = ""
@export var extension: String = ""
@export var file_size_bytes: int = 0
@export var sha256: String = ""

@export var author: String = ""
@export var license: String = ""
@export var source_url: String = ""
@export var license_status: StringName = &"unknown"
@export var preview_supported: bool = false
@export var suggested_slots: PackedStringArray = PackedStringArray()
@export var imported_at: String = ""
@export var reviewed_at: String = ""


# --- 公共方法 ---

func is_approved() -> bool:
	return review_status == STATUS_APPROVED


func is_audio() -> bool:
	return asset_kind == KIND_AUDIO


func is_shader() -> bool:
	return asset_kind == KIND_SHADER


func has_known_license() -> bool:
	return license_status == &"known" and not license.strip_edges().is_empty()


func get_summary_text() -> String:
	var status_text: String = String(review_status)
	var kind_text: String = String(asset_kind)
	return "%s [%s/%s]" % [display_name, kind_text, status_text]
