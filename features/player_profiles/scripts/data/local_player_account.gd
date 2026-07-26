## LocalPlayerAccount: 设备本地玩家账号的严格身份记录。
class_name LocalPlayerAccount
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const MAX_DISPLAY_NAME_LENGTH: int = 24


# --- 公共变量 ---

var schema_version: int = SCHEMA_VERSION
var account_id: String = ""
var display_name: String = ""
var created_at: int = 0
var last_active_at: int = 0


# --- 公共方法 ---

## 创建一个当前 schema 的本地玩家账号。
## @param p_display_name: 玩家在此设备上的显示名称。
## @param timestamp: 创建时间的 Unix 时间戳。
## @param p_account_id: 可选的既有 UUID v7。
static func create(
	p_display_name: String,
	timestamp: int,
	p_account_id: String = ""
) -> LocalPlayerAccount:
	var normalized_name: String = normalize_display_name(p_display_name)
	if normalized_name.is_empty() or timestamp <= 0:
		return null
	var normalized_id: String = p_account_id
	if normalized_id.is_empty():
		normalized_id = GFUuid.generate_v7(timestamp * 1000)
	if not GFUuid.is_valid(normalized_id, 7):
		return null

	var result: LocalPlayerAccount = LocalPlayerAccount.new()
	result.account_id = normalized_id
	result.display_name = normalized_name
	result.created_at = timestamp
	result.last_active_at = timestamp
	return result if result.is_valid() else null


## 从严格字典恢复本地玩家账号。
## @param data: 当前 schema 的完整账号持久化字典。
static func from_dict(data: Dictionary) -> LocalPlayerAccount:
	if not (
		data.size() == 5
		and GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"account_id") is String
		and GFVariantData.get_option_value(data, &"display_name") is String
		and GFVariantData.get_option_value(data, &"created_at") is int
		and GFVariantData.get_option_value(data, &"last_active_at") is int
	):
		return null
	if GFVariantData.get_option_int(data, &"schema_version", 0) != SCHEMA_VERSION:
		return null

	var result: LocalPlayerAccount = LocalPlayerAccount.new()
	result.account_id = GFVariantData.get_option_string(data, &"account_id")
	result.display_name = GFVariantData.get_option_string(data, &"display_name")
	result.created_at = GFVariantData.get_option_int(data, &"created_at")
	result.last_active_at = GFVariantData.get_option_int(data, &"last_active_at")
	return result if result.is_valid() else null


## 返回账号是否满足当前严格身份契约。
func is_valid() -> bool:
	return (
		schema_version == SCHEMA_VERSION
		and GFUuid.is_valid(account_id, 7)
		and display_name == normalize_display_name(display_name)
		and not display_name.is_empty()
		and created_at > 0
		and last_active_at >= created_at
	)


## 生成可持久化的严格字典。
func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"account_id": account_id,
		&"display_name": display_name,
		&"created_at": created_at,
		&"last_active_at": last_active_at,
	}


## 返回不超过长度上限且不含控制字符的显示名称。
## @param value: 玩家输入的原始显示名称。
static func normalize_display_name(value: String) -> String:
	var stripped: String = value.strip_edges()
	var normalized: String = ""
	for index: int in range(stripped.length()):
		var codepoint: int = stripped.unicode_at(index)
		if codepoint < 32 or codepoint == 127:
			continue
		normalized += stripped.substr(index, 1)
		if normalized.length() >= MAX_DISPLAY_NAME_LENGTH:
			break
	return normalized.strip_edges()
