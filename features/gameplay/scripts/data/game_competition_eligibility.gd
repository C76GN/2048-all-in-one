## GameCompetitionEligibility: 对局比赛资格的不可变快照。
##
## reason code 同时承载可解释的会话上下文（例如 daily）与失格原因。
## 所有变更都会返回新实例，已经进入结果、书签或回放的快照不会被后续操作改写。
class_name GameCompetitionEligibility
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1

const REASON_DEBUG: StringName = &"debug"
const REASON_REPLAY_CONTINUATION: StringName = &"replay_continuation"
const REASON_BOOKMARK: StringName = &"bookmark"
const REASON_UNDO_REDO: StringName = &"undo_redo"
const REASON_CUSTOM_BOARD: StringName = &"custom_board"
const REASON_MANUAL_SEED: StringName = &"manual_seed"
const REASON_DAILY: StringName = &"daily"

const _KNOWN_REASON_CODES: Array[StringName] = [
	REASON_DEBUG,
	REASON_REPLAY_CONTINUATION,
	REASON_BOOKMARK,
	REASON_UNDO_REDO,
	REASON_CUSTOM_BOARD,
	REASON_MANUAL_SEED,
	REASON_DAILY,
]
const _DISQUALIFYING_REASON_CODES: Array[StringName] = [
	REASON_DEBUG,
	REASON_REPLAY_CONTINUATION,
	REASON_BOOKMARK,
	REASON_UNDO_REDO,
	REASON_CUSTOM_BOARD,
	REASON_MANUAL_SEED,
]


# --- 私有变量 ---

var _reason_codes: Array[StringName] = []


# --- 构造方法 ---

func _init(reason_codes: Array = []) -> void:
	_reason_codes = _normalize_reason_codes(reason_codes)


# --- 公共方法 ---

## 构造严格资格快照；包含未知 reason code 时返回 null。
static func create(reason_codes: Array = []) -> GameCompetitionEligibility:
	if not _are_reason_codes_valid(reason_codes):
		return null
	return GameCompetitionEligibility.new(reason_codes)


## 从严格持久化结构恢复资格快照。
static func from_dict(data: Dictionary) -> GameCompetitionEligibility:
	if not (
		data.size() == 3
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"eligible") is bool
		and GFVariantData.get_option_value(data, &"reason_codes") is Array
	):
		return null
	if GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION:
		return null

	var reason_codes: Array = GFVariantData.get_option_array(data, &"reason_codes")
	for reason_value: Variant in reason_codes:
		if not reason_value is String:
			return null
	var result: GameCompetitionEligibility = create(reason_codes)
	if result == null:
		return null
	if result.is_eligible() != GFVariantData.get_option_bool(data, &"eligible", false):
		return null
	return result


## 返回添加 reason code 后的新快照；原快照保持不变。
func with_reason(reason_code: StringName) -> GameCompetitionEligibility:
	if not is_known_reason_code(reason_code):
		return null
	var next_reason_codes: Array[StringName] = _reason_codes.duplicate()
	if not next_reason_codes.has(reason_code):
		next_reason_codes.append(reason_code)
	return GameCompetitionEligibility.new(next_reason_codes)


func is_eligible() -> bool:
	for reason_code: StringName in _reason_codes:
		if _DISQUALIFYING_REASON_CODES.has(reason_code):
			return false
	return true


func has_reason(reason_code: StringName) -> bool:
	return _reason_codes.has(reason_code)


func get_reason_codes() -> Array[StringName]:
	return _reason_codes.duplicate()


func get_disqualifying_reason_codes() -> Array[StringName]:
	var result: Array[StringName] = []
	for reason_code: StringName in _reason_codes:
		if _DISQUALIFYING_REASON_CODES.has(reason_code):
			result.append(reason_code)
	return result


func to_dict() -> Dictionary:
	var serialized_codes: Array[String] = []
	for reason_code: StringName in _reason_codes:
		serialized_codes.append(String(reason_code))
	return {
		&"schema_version": SCHEMA_VERSION,
		&"eligible": is_eligible(),
		&"reason_codes": serialized_codes,
	}


static func is_known_reason_code(reason_code: StringName) -> bool:
	return _KNOWN_REASON_CODES.has(reason_code)


# --- 私有/辅助方法 ---

static func _are_reason_codes_valid(reason_codes: Array) -> bool:
	for reason_value: Variant in reason_codes:
		if not (reason_value is String or reason_value is StringName):
			return false
		if not is_known_reason_code(StringName(str(reason_value))):
			return false
	return true


static func _normalize_reason_codes(reason_codes: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for reason_value: Variant in reason_codes:
		var reason_code: StringName = StringName(str(reason_value))
		if is_known_reason_code(reason_code) and not result.has(reason_code):
			result.append(reason_code)
	result.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return result
