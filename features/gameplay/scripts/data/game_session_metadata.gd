## GameSessionMetadata: 一局游戏的不可变 seed 来源、挑战与资格上下文。
class_name GameSessionMetadata
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const SEED_SOURCE_RANDOM: StringName = &"random"
const SEED_SOURCE_MANUAL: StringName = &"manual"
const SEED_SOURCE_DAILY: StringName = &"daily"
const _VALID_SEED_SOURCES: Array[StringName] = [
	SEED_SOURCE_RANDOM,
	SEED_SOURCE_MANUAL,
	SEED_SOURCE_DAILY,
]


# --- 私有变量 ---

var _seed_source: StringName = SEED_SOURCE_RANDOM
var _challenge: GameChallengeMetadata = null
var _eligibility: GameCompetitionEligibility = GameCompetitionEligibility.new()


# --- 公共方法 ---

static func create(
	seed_source: StringName,
	challenge: GameChallengeMetadata = null,
	eligibility: GameCompetitionEligibility = null
) -> GameSessionMetadata:
	var result: GameSessionMetadata = GameSessionMetadata.new()
	result._seed_source = seed_source
	result._challenge = challenge
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
		data.size() == 4
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"seed_source") is String
		and GFVariantData.get_option_value(data, &"challenge") is Dictionary
		and GFVariantData.get_option_value(data, &"eligibility") is Dictionary
	):
		return null
	if GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION:
		return null

	var challenge_data: Dictionary = GFVariantData.get_option_dictionary(data, &"challenge")
	var challenge: GameChallengeMetadata = null
	if not challenge_data.is_empty():
		challenge = GameChallengeMetadata.from_dict(challenge_data)
		if challenge == null:
			return null
	var eligibility: GameCompetitionEligibility = GameCompetitionEligibility.from_dict(
		GFVariantData.get_option_dictionary(data, &"eligibility")
	)
	if eligibility == null:
		return null
	return create(
		GFVariantData.get_option_string_name(data, &"seed_source"),
		challenge,
		eligibility
	)


func is_valid() -> bool:
	if not _VALID_SEED_SOURCES.has(_seed_source) or _eligibility == null:
		return false
	if _seed_source == SEED_SOURCE_DAILY:
		return (
			_challenge != null
			and _challenge.is_valid()
			and _eligibility.has_reason(GameCompetitionEligibility.REASON_DAILY)
			and not _eligibility.has_reason(
				GameCompetitionEligibility.REASON_MANUAL_SEED
			)
		)
	if _challenge != null or _eligibility.has_reason(
		GameCompetitionEligibility.REASON_DAILY
	):
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


func get_challenge() -> GameChallengeMetadata:
	return _challenge


func get_eligibility() -> GameCompetitionEligibility:
	return _eligibility


## 返回添加资格 reason code 后的新会话元数据；原实例保持不变。
func with_eligibility_reason(reason_code: StringName) -> GameSessionMetadata:
	if _eligibility == null:
		return null
	var next_eligibility: GameCompetitionEligibility = _eligibility.with_reason(reason_code)
	if next_eligibility == null:
		return null
	return create(_seed_source, _challenge, next_eligibility)


func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"seed_source": String(_seed_source),
		&"challenge": _challenge.to_dict() if _challenge != null else {},
		&"eligibility": _eligibility.to_dict() if _eligibility != null else {},
	}
