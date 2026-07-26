## ReplayCheckpoint: 回放每个已结算回合的确定性校验点。
class_name ReplayCheckpoint
extends Resource


# --- 常量 ---

const SCHEMA_VERSION: int = 2
const LEGACY_SCHEMA_VERSION: int = 1


# --- 导出变量 ---

@export var step_index: int = 0
@export var state_checksum: String = ""
@export var board_checksum: String = ""
@export var rng_checksum: String = ""
@export var score: int = 0
@export var metadata_available: bool = false
@export var merge_count: int = 0
@export var transform_count: int = 0
@export var ratio_resolution_count: int = 0
@export var max_merge_value: int = 0
@export var highest_tile: int = 0
@export var target_reached: bool = false


# --- 公共方法 ---

func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"step_index": step_index,
		&"state_checksum": state_checksum,
		&"board_checksum": board_checksum,
		&"rng_checksum": rng_checksum,
		&"score": score,
		&"metadata_available": metadata_available,
		&"merge_count": merge_count,
		&"transform_count": transform_count,
		&"ratio_resolution_count": ratio_resolution_count,
		&"max_merge_value": max_merge_value,
		&"highest_tile": highest_tile,
		&"target_reached": target_reached,
	}


func is_valid_checkpoint() -> bool:
	return (
		step_index > 0
		and _is_sha256(state_checksum)
		and _is_sha256(board_checksum)
		and _is_sha256(rng_checksum)
		and score >= 0
		and merge_count >= 0
		and transform_count >= 0
		and ratio_resolution_count >= 0
		and max_merge_value >= 0
		and highest_tile >= 0
	)


## 从严格持久化字典恢复回放校验点。
##
## schema v1 只包含确定性摘要；读取后使用 score 差值生成稳定降级标记。
## schema v2 额外冻结强类型 TurnResult 摘要，供回放浏览器精确生成事件标记。
## @param data: schema v1 或 v2 的完整 checkpoint 字典。
static func from_dict(data: Dictionary) -> ReplayCheckpoint:
	var schema_version: int = GFVariantData.get_option_int(data, &"schema_version", 0)
	if schema_version == LEGACY_SCHEMA_VERSION:
		return _from_legacy_dict(data)
	if not _has_current_shape(data):
		return null
	var result: ReplayCheckpoint = ReplayCheckpoint.new()
	result.step_index = GFVariantData.get_option_int(data, &"step_index", 0)
	result.state_checksum = GFVariantData.get_option_string(data, &"state_checksum")
	result.board_checksum = GFVariantData.get_option_string(data, &"board_checksum")
	result.rng_checksum = GFVariantData.get_option_string(data, &"rng_checksum")
	result.score = GFVariantData.get_option_int(data, &"score", 0)
	result.metadata_available = GFVariantData.get_option_bool(
		data,
		&"metadata_available",
		false
	)
	result.merge_count = GFVariantData.get_option_int(data, &"merge_count", 0)
	result.transform_count = GFVariantData.get_option_int(data, &"transform_count", 0)
	result.ratio_resolution_count = GFVariantData.get_option_int(
		data,
		&"ratio_resolution_count",
		0
	)
	result.max_merge_value = GFVariantData.get_option_int(data, &"max_merge_value", 0)
	result.highest_tile = GFVariantData.get_option_int(data, &"highest_tile", 0)
	result.target_reached = GFVariantData.get_option_bool(data, &"target_reached", false)
	return result if result.is_valid_checkpoint() else null


# --- 私有/辅助方法 ---

static func _from_legacy_dict(data: Dictionary) -> ReplayCheckpoint:
	if not (
		data.size() == 6
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"step_index") is int
		and GFVariantData.get_option_value(data, &"state_checksum") is String
		and GFVariantData.get_option_value(data, &"board_checksum") is String
		and GFVariantData.get_option_value(data, &"rng_checksum") is String
		and GFVariantData.get_option_value(data, &"score") is int
	):
		return null
	var result: ReplayCheckpoint = ReplayCheckpoint.new()
	result.step_index = GFVariantData.get_option_int(data, &"step_index", 0)
	result.state_checksum = GFVariantData.get_option_string(data, &"state_checksum")
	result.board_checksum = GFVariantData.get_option_string(data, &"board_checksum")
	result.rng_checksum = GFVariantData.get_option_string(data, &"rng_checksum")
	result.score = GFVariantData.get_option_int(data, &"score", 0)
	result.metadata_available = false
	return result if result.is_valid_checkpoint() else null


static func _has_current_shape(data: Dictionary) -> bool:
	return (
		data.size() == 13
		and GFVariantData.get_option_int(data, &"schema_version", 0) == SCHEMA_VERSION
		and GFVariantData.get_option_value(data, &"step_index") is int
		and GFVariantData.get_option_value(data, &"state_checksum") is String
		and GFVariantData.get_option_value(data, &"board_checksum") is String
		and GFVariantData.get_option_value(data, &"rng_checksum") is String
		and GFVariantData.get_option_value(data, &"score") is int
		and GFVariantData.get_option_value(data, &"metadata_available") is bool
		and GFVariantData.get_option_value(data, &"merge_count") is int
		and GFVariantData.get_option_value(data, &"transform_count") is int
		and GFVariantData.get_option_value(data, &"ratio_resolution_count") is int
		and GFVariantData.get_option_value(data, &"max_merge_value") is int
		and GFVariantData.get_option_value(data, &"highest_tile") is int
		and GFVariantData.get_option_value(data, &"target_reached") is bool
	)


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	return value.to_lower().is_valid_hex_number()
