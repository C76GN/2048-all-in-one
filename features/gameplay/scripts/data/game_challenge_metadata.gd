## GameChallengeMetadata: 一次 Daily Challenge 的不可变确定性身份。
class_name GameChallengeMetadata
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const KIND_DAILY: StringName = &"daily"


# --- 私有变量 ---

var _challenge_schema_version: int = 0
var _utc_date: String = ""
var _ruleset_id: StringName = &""
var _ruleset_version: int = 0
var _ruleset_fingerprint: String = ""
var _topology_key: String = ""
var _seed: int = 0
var _challenge_hash: String = ""


# --- 公共方法 ---

static func create_daily(
	challenge_schema_version: int,
	utc_date: String,
	ruleset_id: StringName,
	ruleset_version: int,
	ruleset_fingerprint: String,
	topology_key: String,
	seed_value: int,
	challenge_hash: String
) -> GameChallengeMetadata:
	var result: GameChallengeMetadata = GameChallengeMetadata.new()
	result._challenge_schema_version = challenge_schema_version
	result._utc_date = utc_date
	result._ruleset_id = ruleset_id
	result._ruleset_version = ruleset_version
	result._ruleset_fingerprint = ruleset_fingerprint
	result._topology_key = topology_key
	result._seed = seed_value
	result._challenge_hash = challenge_hash
	return result if result.is_valid() else null


static func from_dict(data: Dictionary) -> GameChallengeMetadata:
	if not (
		data.size() == 10
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"kind") is String
		and GFVariantData.get_option_value(data, &"challenge_schema_version") is int
		and GFVariantData.get_option_value(data, &"utc_date") is String
		and GFVariantData.get_option_value(data, &"ruleset_id") is String
		and GFVariantData.get_option_value(data, &"ruleset_version") is int
		and GFVariantData.get_option_value(data, &"ruleset_fingerprint") is String
		and GFVariantData.get_option_value(data, &"topology_key") is String
		and GFVariantData.get_option_value(data, &"seed") is int
		and GFVariantData.get_option_value(data, &"challenge_hash") is String
	):
		return null
	if (
		GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION
		or GFVariantData.get_option_string_name(data, &"kind") != KIND_DAILY
	):
		return null
	return create_daily(
		GFVariantData.get_option_int(data, &"challenge_schema_version", 0),
		GFVariantData.get_option_string(data, &"utc_date"),
		GFVariantData.get_option_string_name(data, &"ruleset_id"),
		GFVariantData.get_option_int(data, &"ruleset_version", 0),
		GFVariantData.get_option_string(data, &"ruleset_fingerprint"),
		GFVariantData.get_option_string(data, &"topology_key"),
		GFVariantData.get_option_int(data, &"seed", -1),
		GFVariantData.get_option_string(data, &"challenge_hash")
	)


func is_valid() -> bool:
	return (
		_challenge_schema_version > 0
		and _is_utc_date_valid(_utc_date)
		and _ruleset_id != &""
		and _ruleset_version > 0
		and _is_sha256_text(_ruleset_fingerprint)
		and not _topology_key.is_empty()
		and _seed >= 0
		and _seed <= 0xffffffff
		and _is_sha256_text(_challenge_hash)
	)


func get_challenge_schema_version() -> int:
	return _challenge_schema_version


func get_utc_date() -> String:
	return _utc_date


func get_ruleset_id() -> StringName:
	return _ruleset_id


func get_ruleset_version() -> int:
	return _ruleset_version


func get_ruleset_fingerprint() -> String:
	return _ruleset_fingerprint


func get_topology_key() -> String:
	return _topology_key


func get_seed() -> int:
	return _seed


func get_challenge_hash() -> String:
	return _challenge_hash


func get_group_key() -> String:
	return "daily:%d:%s:%s" % [
		_challenge_schema_version,
		_utc_date,
		_challenge_hash,
	]


func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"kind": String(KIND_DAILY),
		&"challenge_schema_version": _challenge_schema_version,
		&"utc_date": _utc_date,
		&"ruleset_id": String(_ruleset_id),
		&"ruleset_version": _ruleset_version,
		&"ruleset_fingerprint": _ruleset_fingerprint,
		&"topology_key": _topology_key,
		&"seed": _seed,
		&"challenge_hash": _challenge_hash,
	}


# --- 私有/辅助方法 ---

static func _is_utc_date_valid(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9]:
		var character: String = value.substr(index, 1)
		if character < "0" or character > "9":
			return false
	var month: int = value.substr(5, 2).to_int()
	var day: int = value.substr(8, 2).to_int()
	return month >= 1 and month <= 12 and day >= 1 and day <= 31


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
