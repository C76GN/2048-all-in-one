## GameChallengeUtility: 使用项目统一时钟和 GF 稳定 seed 派生 Daily Challenge。
##
## UTC 日期是唯一墙上时间输入；玩法结果仍只消费派生后的固定 seed。
class_name GameChallengeUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const DAILY_CHALLENGE_SCHEMA_VERSION: int = 1
const _DAILY_SEED_NAMESPACE: String = "2048.daily.challenge"


# --- 私有变量 ---

var _clock: GameClockUtility = null
var _determinism: GameDeterminismUtility = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameClockUtility, GameDeterminismUtility]


func ready() -> void:
	_clock = _resolve_clock_utility()
	_determinism = _resolve_determinism_utility()


func dispose() -> void:
	_clock = null
	_determinism = null


# --- 公共方法 ---

## 按注入的 GameClockUtility 当前 UTC 日期创建 Daily Challenge。
func get_current_daily_challenge(
	mode_config: GameModeConfig,
	topology: BoardTopology
) -> GameChallengeMetadata:
	var clock: GameClockUtility = _get_clock()
	if clock == null:
		return null
	return build_daily_challenge(mode_config, topology, clock.get_utc_date())


## 按给定 UTC 日期构造挑战；公开入口主要用于离线验证固定 corpus。
func build_daily_challenge(
	mode_config: GameModeConfig,
	topology: BoardTopology,
	utc_date: String
) -> GameChallengeMetadata:
	var determinism: GameDeterminismUtility = _get_determinism()
	if (
		not is_instance_valid(mode_config)
		or not is_instance_valid(topology)
		or utc_date.is_empty()
		or determinism == null
	):
		return null
	var ruleset_fingerprint: String = determinism.calculate_ruleset_fingerprint(
		mode_config
	)
	var topology_key: String = topology.get_stable_key()
	if ruleset_fingerprint.is_empty() or topology_key.is_empty():
		return null

	var seed_parts: Array = [
		_DAILY_SEED_NAMESPACE,
		DAILY_CHALLENGE_SCHEMA_VERSION,
		utc_date,
		String(mode_config.ruleset_id),
		mode_config.ruleset_version,
		ruleset_fingerprint,
		topology_key,
	]
	var seed_result: Dictionary = GFSeedUtility.try_make_stable_seed(seed_parts)
	if not GFVariantData.get_option_bool(seed_result, &"ok", false):
		return null
	var canonical_identity: String = GFDeterministicVariantSerializer.to_canonical_json(
		seed_parts
	)
	if canonical_identity.is_empty():
		return null
	return GameChallengeMetadata.create_daily(
		DAILY_CHALLENGE_SCHEMA_VERSION,
		utc_date,
		mode_config.ruleset_id,
		mode_config.ruleset_version,
		ruleset_fingerprint,
		topology_key,
		GFVariantData.get_option_int(seed_result, &"seed", -1),
		canonical_identity.sha256_text()
	)


# --- 私有/辅助方法 ---

func _get_clock() -> GameClockUtility:
	if is_instance_valid(_clock):
		return _clock
	_clock = _resolve_clock_utility()
	return _clock


func _get_determinism() -> GameDeterminismUtility:
	if is_instance_valid(_determinism):
		return _determinism
	_determinism = _resolve_determinism_utility()
	return _determinism


func _resolve_clock_utility() -> GameClockUtility:
	var value: Object = get_utility(GameClockUtility)
	return value if value is GameClockUtility else null


func _resolve_determinism_utility() -> GameDeterminismUtility:
	var value: Object = get_utility(GameDeterminismUtility)
	return value if value is GameDeterminismUtility else null
