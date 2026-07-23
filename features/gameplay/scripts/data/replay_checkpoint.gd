## ReplayCheckpoint: 回放每个已结算回合的确定性校验点。
class_name ReplayCheckpoint
extends Resource


# --- 常量 ---

const SCHEMA_VERSION: int = 1


# --- 导出变量 ---

@export var step_index: int = 0
@export var state_checksum: String = ""
@export var board_checksum: String = ""
@export var rng_checksum: String = ""
@export var score: int = 0


# --- 公共方法 ---

func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"step_index": step_index,
		&"state_checksum": state_checksum,
		&"board_checksum": board_checksum,
		&"rng_checksum": rng_checksum,
		&"score": score,
	}


func is_valid_checkpoint() -> bool:
	return (
		step_index > 0
		and _is_sha256(state_checksum)
		and _is_sha256(board_checksum)
		and _is_sha256(rng_checksum)
	)


## 从严格持久化字典恢复回放校验点。
## @param data: schema v1 的完整 checkpoint 字典。
static func from_dict(data: Dictionary) -> ReplayCheckpoint:
	if (
		data.size() != 6
		or GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION
	):
		return null
	var result: ReplayCheckpoint = ReplayCheckpoint.new()
	result.step_index = GFVariantData.get_option_int(data, &"step_index", 0)
	result.state_checksum = GFVariantData.get_option_string(data, &"state_checksum")
	result.board_checksum = GFVariantData.get_option_string(data, &"board_checksum")
	result.rng_checksum = GFVariantData.get_option_string(data, &"rng_checksum")
	result.score = GFVariantData.get_option_int(data, &"score", 0)
	return result if result.is_valid_checkpoint() else null


# --- 私有/辅助方法 ---

static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	return value.to_lower().is_valid_hex_number()
