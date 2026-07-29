## GameResultRecordedData: 写入统一 Profile 后发布的规范对局结果。
##
## 结果冻结 seed、最终状态 hash 和不可变比赛资格快照。客户端本地榜
## 只消费 is_competition_eligible() 为 true 的记录；它不代表线上权威证明。
class_name GameResultRecordedData
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 2


# --- 公共变量 ---

var schema_version: int = SCHEMA_VERSION
var result_hash: String = ""
var mode_id: StringName = &""
var board_key: String = ""
var ruleset_id: StringName = &""
var ruleset_version: int = 0
var ruleset_fingerprint: String = ""
var initial_seed: int = 0
var final_state_hash: String = ""
var competition_eligibility: GameCompetitionEligibility = null
var score: int = 0
var steps: int = 0
var max_tile: int = 0
var played_at: int = 0
var target_value: int = 0
var target_reached: bool = false


# --- 公共方法 ---

## 构造经过严格校验的规范对局结果。
## @param p_mode_id: 对局模式的稳定 ID。
## @param p_board_key: 棋盘拓扑的稳定键。
## @param p_ruleset_id: 玩法规则集的稳定 ID。
## @param p_ruleset_version: 玩法规则集版本。
## @param p_ruleset_fingerprint: 完整玩法内容的 SHA-256 指纹。
## @param p_initial_seed: 对局初始随机种子。
## @param p_final_state_hash: 最终确定性状态的 SHA-256 摘要。
## @param p_competition_eligibility: 对局结束时冻结的比赛资格快照。
## @param p_score: 对局最终分数。
## @param p_steps: 已完成的有效移动次数。
## @param p_max_tile: 对局达到的最高方块值。
## @param p_played_at: 对局结束时的 Unix 时间戳。
## @param p_target_value: 当前模式的目标方块值；无目标时为 0。
## @param p_target_reached: 对局是否达到目标方块值。
static func create(
	p_mode_id: StringName,
	p_board_key: String,
	p_ruleset_id: StringName,
	p_ruleset_version: int,
	p_ruleset_fingerprint: String,
	p_initial_seed: int,
	p_final_state_hash: String,
	p_competition_eligibility: GameCompetitionEligibility,
	p_score: int,
	p_steps: int,
	p_max_tile: int,
	p_played_at: int,
	p_target_value: int = 0,
	p_target_reached: bool = false
) -> GameResultRecordedData:
	var result: GameResultRecordedData = GameResultRecordedData.new()
	result.mode_id = p_mode_id
	result.board_key = p_board_key
	result.ruleset_id = p_ruleset_id
	result.ruleset_version = p_ruleset_version
	result.ruleset_fingerprint = p_ruleset_fingerprint
	result.initial_seed = p_initial_seed
	result.final_state_hash = p_final_state_hash
	result.competition_eligibility = p_competition_eligibility
	result.score = p_score
	result.steps = p_steps
	result.max_tile = p_max_tile
	result.played_at = p_played_at
	result.target_value = p_target_value
	result.target_reached = p_target_reached
	result.result_hash = result._calculate_result_hash()
	return result if result.is_valid() else null


## 从当前严格持久化结构恢复规范对局结果。
## @param data: 当前版本的完整结果字典。
static func from_dict(data: Dictionary) -> GameResultRecordedData:
	if not _has_strict_shape(data):
		return null
	if GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION:
		return null

	var eligibility: GameCompetitionEligibility = GameCompetitionEligibility.from_dict(
		GFVariantData.get_option_dictionary(data, &"eligibility")
	)
	if eligibility == null:
		return null
	var result: GameResultRecordedData = create(
		GFVariantData.get_option_string_name(data, &"mode_id"),
		GFVariantData.get_option_string(data, &"board_key"),
		GFVariantData.get_option_string_name(data, &"ruleset_id"),
		GFVariantData.get_option_int(data, &"ruleset_version", 0),
		GFVariantData.get_option_string(data, &"ruleset_fingerprint"),
		GFVariantData.get_option_int(data, &"initial_seed"),
		GFVariantData.get_option_string(data, &"final_state_hash"),
		eligibility,
		GFVariantData.get_option_int(data, &"score"),
		GFVariantData.get_option_int(data, &"steps"),
		GFVariantData.get_option_int(data, &"max_tile"),
		GFVariantData.get_option_int(data, &"played_at"),
		GFVariantData.get_option_int(data, &"target_value"),
		GFVariantData.get_option_bool(data, &"target_reached")
	)
	if result == null:
		return null
	var persisted_hash: String = GFVariantData.get_option_string(data, &"result_hash")
	return result if result.result_hash == persisted_hash else null


func is_valid() -> bool:
	if (
		schema_version != SCHEMA_VERSION
		or mode_id == &""
		or board_key.is_empty()
		or ruleset_id == &""
		or ruleset_version <= 0
		or not _is_sha256_text(ruleset_fingerprint)
		or not _is_sha256_text(final_state_hash)
		or competition_eligibility == null
		or score < 0
		or steps < 0
		or max_tile < 0
		or played_at <= 0
		or target_value < 0
		or (target_value <= 0 and target_reached)
	):
		return false
	return _is_sha256_text(result_hash) and result_hash == _calculate_result_hash()


func is_competition_eligible() -> bool:
	return competition_eligibility != null and competition_eligibility.is_eligible()


## Debug 改写不进入既有进度统计或成就投影，但仍保留为可解释结果。
func counts_toward_progress() -> bool:
	return (
		competition_eligibility != null
		and not competition_eligibility.has_reason(
			GameCompetitionEligibility.REASON_DEBUG
		)
	)


func get_leaderboard_identity() -> Dictionary:
	return {
		&"mode_id": String(mode_id),
		&"board_key": board_key,
		&"ruleset_id": String(ruleset_id),
		&"ruleset_version": ruleset_version,
		&"ruleset_fingerprint": ruleset_fingerprint,
	}


func get_leaderboard_group_key() -> String:
	return calculate_leaderboard_group_key(get_leaderboard_identity())


## 从规范榜单身份计算稳定分组键。
## @param identity: 模式、拓扑与规则集组成的完整榜单身份。
static func calculate_leaderboard_group_key(identity: Dictionary) -> String:
	if not is_leaderboard_identity_valid(identity):
		return ""
	return GFDeterministicVariantSerializer.sha256(identity)


## 校验榜单身份是否符合当前严格 schema。
## @param identity: 待校验的榜单身份字典。
static func is_leaderboard_identity_valid(identity: Dictionary) -> bool:
	return (
		identity.size() == 5
		and GFVariantData.get_option_value(identity, &"mode_id") is String
		and GFVariantData.get_option_value(identity, &"board_key") is String
		and GFVariantData.get_option_value(identity, &"ruleset_id") is String
		and GFVariantData.get_option_value(identity, &"ruleset_version") is int
		and GFVariantData.get_option_value(identity, &"ruleset_fingerprint") is String
		and not GFVariantData.get_option_string(identity, &"mode_id").is_empty()
		and not GFVariantData.get_option_string(identity, &"board_key").is_empty()
		and not GFVariantData.get_option_string(identity, &"ruleset_id").is_empty()
		and GFVariantData.get_option_int(identity, &"ruleset_version", 0) > 0
		and _is_sha256_text(
			GFVariantData.get_option_string(identity, &"ruleset_fingerprint")
		)
	)


func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"result_hash": result_hash,
		&"mode_id": String(mode_id),
		&"board_key": board_key,
		&"ruleset_id": String(ruleset_id),
		&"ruleset_version": ruleset_version,
		&"ruleset_fingerprint": ruleset_fingerprint,
		&"initial_seed": initial_seed,
		&"final_state_hash": final_state_hash,
		&"eligibility": (
			competition_eligibility.to_dict()
			if competition_eligibility != null
			else {}
		),
		&"score": score,
		&"steps": steps,
		&"max_tile": max_tile,
		&"played_at": played_at,
		&"target_value": target_value,
		&"target_reached": target_reached,
	}


# --- 私有/辅助方法 ---


func _calculate_result_hash() -> String:
	var hash_payload: Dictionary = {
		&"mode_id": String(mode_id),
		&"board_key": board_key,
		&"ruleset_id": String(ruleset_id),
		&"ruleset_version": ruleset_version,
		&"ruleset_fingerprint": ruleset_fingerprint,
		&"initial_seed": initial_seed,
		&"final_state_hash": final_state_hash,
		&"eligibility": (
			competition_eligibility.to_dict()
			if competition_eligibility != null
			else {}
		),
		&"score": score,
		&"steps": steps,
		&"max_tile": max_tile,
		&"played_at": played_at,
		&"target_value": target_value,
		&"target_reached": target_reached,
	}
	return GFDeterministicVariantSerializer.sha256(hash_payload)


static func _has_strict_shape(data: Dictionary) -> bool:
	return (
		data.size() == 16
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"result_hash") is String
		and GFVariantData.get_option_value(data, &"mode_id") is String
		and GFVariantData.get_option_value(data, &"board_key") is String
		and GFVariantData.get_option_value(data, &"ruleset_id") is String
		and GFVariantData.get_option_value(data, &"ruleset_version") is int
		and GFVariantData.get_option_value(data, &"ruleset_fingerprint") is String
		and GFVariantData.get_option_value(data, &"initial_seed") is int
		and GFVariantData.get_option_value(data, &"final_state_hash") is String
		and GFVariantData.get_option_value(data, &"eligibility") is Dictionary
		and GFVariantData.get_option_value(data, &"score") is int
		and GFVariantData.get_option_value(data, &"steps") is int
		and GFVariantData.get_option_value(data, &"max_tile") is int
		and GFVariantData.get_option_value(data, &"played_at") is int
		and GFVariantData.get_option_value(data, &"target_value") is int
		and GFVariantData.get_option_value(data, &"target_reached") is bool
	)


static func _is_sha256_text(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1).to_lower()
		if not (
			(character >= "0" and character <= "9")
			or (character >= "a" and character <= "f")
		):
			return false
	return true
