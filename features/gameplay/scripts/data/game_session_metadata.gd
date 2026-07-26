## GameSessionMetadata: 一局游戏的不可变 seed 来源与资格上下文。
class_name GameSessionMetadata
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 2
const SEED_SOURCE_RANDOM: StringName = &"random"
const SEED_SOURCE_MANUAL: StringName = &"manual"
const _VALID_SEED_SOURCES: Array[StringName] = [
	SEED_SOURCE_RANDOM,
	SEED_SOURCE_MANUAL,
]


# --- 私有变量 ---

var _seed_source: StringName = SEED_SOURCE_RANDOM
var _eligibility: GameCompetitionEligibility = GameCompetitionEligibility.new()


# --- 公共方法 ---

static func create(
	seed_source: StringName,
	eligibility: GameCompetitionEligibility = null
) -> GameSessionMetadata:
	var result: GameSessionMetadata = GameSessionMetadata.new()
	result._seed_source = seed_source
	result._eligibility = (
		eligibility
		if eligibility != null
		else GameCompetitionEligibility.create()
	)
	return result if result.is_valid() else null


static func create_default() -> GameSessionMetadata:
	return create(SEED_SOURCE_RANDOM)


static func make_default_dict() -> Dictionary:
	var metadata: GameSessionMetadata = create_default()
	return metadata.to_dict() if metadata != null else {}


static func from_dict(data: Dictionary) -> GameSessionMetadata:
	if not (
		data.size() == 3
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"seed_source") is String
		and GFVariantData.get_option_value(data, &"eligibility") is Dictionary
	):
		return null
	if GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION:
		return null

	var eligibility: GameCompetitionEligibility = GameCompetitionEligibility.from_dict(
		GFVariantData.get_option_dictionary(data, &"eligibility")
	)
	if eligibility == null:
		return null
	return create(
		GFVariantData.get_option_string_name(data, &"seed_source"),
		eligibility
	)


func is_valid() -> bool:
	if not _VALID_SEED_SOURCES.has(_seed_source) or _eligibility == null:
		return false
	if _seed_source == SEED_SOURCE_MANUAL:
		return _eligibility.has_reason(
			GameCompetitionEligibility.REASON_MANUAL_SEED
		)
	return not _eligibility.has_reason(
		GameCompetitionEligibility.REASON_MANUAL_SEED
	)


func get_seed_source() -> StringName:
	return _seed_source


func get_eligibility() -> GameCompetitionEligibility:
	return _eligibility


## 返回添加资格 reason code 后的新会话元数据；原实例保持不变。
func with_eligibility_reason(reason_code: StringName) -> GameSessionMetadata:
	if _eligibility == null:
		return null
	var next_eligibility: GameCompetitionEligibility = _eligibility.with_reason(reason_code)
	if next_eligibility == null:
		return null
	return create(_seed_source, next_eligibility)


func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"seed_source": String(_seed_source),
		&"eligibility": _eligibility.to_dict() if _eligibility != null else {},
	}
