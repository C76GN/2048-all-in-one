@tool
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

const PROMOTION_GATE_ELIGIBLE: StringName = &"eligible"
const PROMOTION_GATE_QUALITY_NOT_APPROVED: StringName = &"quality_not_approved"
const PROMOTION_GATE_BLOCKED_LICENSE: StringName = &"blocked_license"

const KIND_AUDIO: StringName = &"audio"
const KIND_SHADER: StringName = &"shader"
const KIND_TEXTURE: StringName = &"texture"
const KIND_VFX: StringName = &"vfx"
const KIND_OTHER: StringName = &"other"

const REVIEW_GROUP_PREFIX: String = "review.group"
const _PLACEHOLDER_LICENSE_IDS: PackedStringArray = [
	"unknown",
	"unknown license",
	"unspecified",
	"unspecified license",
	"tbd",
	"todo",
	"pending",
	"license pending",
	"pending license",
	"n/a",
	"na",
	"none",
	"not specified",
	"not applicable",
	"unlicensed",
]


# --- 导出变量 ---

@export var asset_id: StringName = &""
@export var source_pack_id: StringName = &""
@export var display_name: String = ""
@export var asset_kind: StringName = KIND_OTHER
@export var review_group_id: StringName = &""
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

## 为来源包显式声明的音频编码目录生成稳定评审组 ID。
## @param pack_id: 候选素材所属来源包。
## @param source_relative_path: 素材在来源包内的相对路径。
## @param variant_roots: 已人工确认承载同源编码变体的一级目录名。
## @return 未命中声明目录时为空，否则为同一声音跨格式共享的稳定 ID。
static func make_audio_variant_group_id(
	pack_id: StringName,
	source_relative_path: String,
	variant_roots: PackedStringArray
) -> StringName:
	var pack_text: String = String(pack_id).strip_edges().to_lower()
	var normalized_path: String = source_relative_path.replace("\\", "/").strip_edges()
	if (
		pack_text.is_empty()
		or normalized_path.is_empty()
		or normalized_path.is_absolute_path()
		or normalized_path.contains("../")
	):
		return &""
	var path_parts: PackedStringArray = normalized_path.split("/", false)
	if path_parts.size() < 2:
		return &""
	if not _contains_case_insensitive(variant_roots, path_parts[0]):
		return &""

	var logical_parts: PackedStringArray = PackedStringArray()
	for index: int in range(1, path_parts.size()):
		var part: String = path_parts[index].strip_edges()
		if part.is_empty():
			return &""
		if index == path_parts.size() - 1:
			part = part.get_basename()
		if part.is_empty():
			return &""
		var _append_result: bool = logical_parts.append(part.to_lower())
	var logical_path: String = "/".join(logical_parts)
	var pack_token: String = _make_id_token(pack_text)
	var path_token: String = _make_id_token(logical_path)
	if pack_token.is_empty() or path_token.is_empty():
		return &""
	if path_token.length() > 56:
		path_token = path_token.substr(0, 56).trim_suffix(".")
	var fingerprint: String = ("%s|%s" % [pack_text, logical_path]).sha256_text().substr(0, 12)
	return StringName(
		"%s.%s.%s.%s" % [
			REVIEW_GROUP_PREFIX,
			pack_token,
			path_token,
			fingerprint,
		]
	)


## 判断许可证标识是否为空或仅为待办占位文本。
## @param license_id: 候选或运行时素材声明的许可证标识。
## @return 许可证不可作为晋升证据时返回 true。
static func is_placeholder_license_id(license_id: String) -> bool:
	var normalized: String = license_id.strip_edges().to_lower()
	normalized = normalized.replace("_", " ").replace("-", " ")
	normalized = " ".join(normalized.split(" ", false))
	return normalized.is_empty() or _PLACEHOLDER_LICENSE_IDS.has(normalized)


## 仅根据质量结论与授权字段派生运行时晋升门禁，不读取或修改资源状态。
## @param quality_status: 人工质量结论。
## @param declared_license_status: 授权确认状态。
## @param license_id: 候选素材声明的许可证标识。
## @return eligible、quality_not_approved 或 blocked_license。
static func derive_promotion_gate(
	quality_status: StringName,
	declared_license_status: StringName,
	license_id: String
) -> StringName:
	if quality_status != STATUS_APPROVED:
		return PROMOTION_GATE_QUALITY_NOT_APPROVED
	if (
		declared_license_status != &"known"
		or is_placeholder_license_id(license_id)
	):
		return PROMOTION_GATE_BLOCKED_LICENSE
	return PROMOTION_GATE_ELIGIBLE


## 复制同一声音可共享的评审状态，不覆盖编码版本自己的评分、备注或标签。
## @param source: 提供人工评审状态的可试听格式记录。
## @param synchronized_reviewed_at: 可选的统一批次时间；为空时沿用来源记录时间。
## @return 仅当来源可信、目标仍为 inbox 且组 ID 一致时返回 true。
func copy_review_status_from(
	source: AssetReviewRecord,
	synchronized_reviewed_at: String = ""
) -> bool:
	if (
		source == null
		or not is_audio()
		or not preview_supported
		or review_status != STATUS_INBOX
		or not source.can_drive_audio_variant_review()
		or review_group_id == &""
		or review_group_id != source.review_group_id
	):
		return false
	review_status = source.review_status
	reviewed_at = (
		synchronized_reviewed_at
		if not synchronized_reviewed_at.is_empty()
		else source.reviewed_at
	)
	return true


## 返回当前记录能否作为跨格式评审状态的可信来源。
func can_drive_audio_variant_review() -> bool:
	return (
		is_audio()
		and preview_supported
		and review_group_id != &""
		and review_status != STATUS_INBOX
		and not reviewed_at.is_empty()
	)


func is_approved() -> bool:
	return review_status == STATUS_APPROVED


func is_audio() -> bool:
	return asset_kind == KIND_AUDIO


func is_shader() -> bool:
	return asset_kind == KIND_SHADER


func has_known_license() -> bool:
	return (
		license_status == &"known"
		and not is_placeholder_license_id(license)
	)


## 返回由质量结论和授权证据派生的运行时晋升门禁。
## @return eligible、quality_not_approved 或 blocked_license。
func get_promotion_gate() -> StringName:
	return derive_promotion_gate(review_status, license_status, license)


## 返回当前候选是否同时满足质量通过和已知非占位授权。
func is_promotion_eligible() -> bool:
	return get_promotion_gate() == PROMOTION_GATE_ELIGIBLE


func get_summary_text() -> String:
	var status_text: String = String(review_status)
	var kind_text: String = String(asset_kind)
	return "%s [%s/%s]" % [display_name, kind_text, status_text]


# --- 私有/辅助方法 ---

static func _contains_case_insensitive(values: PackedStringArray, target: String) -> bool:
	var normalized_target: String = target.strip_edges().to_lower()
	for value: String in values:
		if value.strip_edges().to_lower() == normalized_target:
			return true
	return false


static func _make_id_token(text: String) -> String:
	var result: String = ""
	var previous_was_separator: bool = false
	var normalized: String = text.strip_edges().to_lower()
	for index: int in range(normalized.length()):
		var code: int = normalized.unicode_at(index)
		var is_letter: bool = code >= 97 and code <= 122
		var is_digit: bool = code >= 48 and code <= 57
		if is_letter or is_digit:
			result += normalized.substr(index, 1)
			previous_was_separator = false
		elif not previous_was_separator:
			result += "."
			previous_was_separator = true
	return result.trim_prefix(".").trim_suffix(".")
