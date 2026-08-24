## 跨账号 progress 聚合在一次请求内消费的严格目录值对象。
##
## 该对象由 player_profiles 在调用边界冻结；progress 只读取这里的稳定身份、
## 展示元数据与规范 Profile logical identity，不反向解析账号目录实现。构造与
## 所有读取入口都会隔离 Dictionary/Array alias，创建后不提供任何修改入口。
class_name DeviceProgressAccountCatalogSnapshot
extends RefCounted


# --- 常量 ---

## 当前产品允许参与一次设备聚合的账号上限。
const MAX_ACCOUNT_COUNT: int = 8

## 展示名在快照契约内的防御性长度上限。
const MAX_DISPLAY_NAME_LENGTH: int = 24

const _PROFILE_DIRECTORY: String = "profiles"
const _PROFILE_EXTENSION: String = ".save"
const _DESCRIPTOR_FIELDS: Array[StringName] = [
	&"account_id",
	&"display_name",
	&"last_active_at",
	&"profile_file_name",
]


# --- 私有变量 ---

var _active_account_id: String = ""
var _account_descriptors: Array[Dictionary] = []


# --- 公共方法 ---

## 从规范账号描述符创建与调用方完全隔离的只读快照。
##
## @param active_account_id: 快照时刻目录中的活动账号 UUID v7。
## @param account_descriptors: 规范顺序的账号描述符；每项只能包含
## account_id、display_name、last_active_at 与 profile_file_name。
## @return 全部字段、身份、路径与唯一性合法时返回快照，否则返回 null。
static func create(
	active_account_id: String,
	account_descriptors: Array[Dictionary]
) -> DeviceProgressAccountCatalogSnapshot:
	if (
		not GFUuid.is_valid(active_account_id, 7)
		or account_descriptors.is_empty()
		or account_descriptors.size() > MAX_ACCOUNT_COUNT
	):
		return null

	var frozen_descriptors: Array[Dictionary] = []
	var seen_account_ids: Dictionary = {}
	for descriptor: Dictionary in account_descriptors:
		if not _is_valid_descriptor(descriptor):
			return null
		var account_id: String = GFVariantData.get_option_string(
			descriptor,
			&"account_id"
		)
		if seen_account_ids.has(account_id):
			return null
		seen_account_ids[account_id] = true
		frozen_descriptors.append(_freeze_descriptor(descriptor))
	if not seen_account_ids.has(active_account_id):
		return null

	var snapshot: DeviceProgressAccountCatalogSnapshot = (
		DeviceProgressAccountCatalogSnapshot.new()
	)
	snapshot._active_account_id = active_account_id
	snapshot._account_descriptors = frozen_descriptors
	return snapshot if snapshot.is_valid() else null


## 验证内部冻结值仍满足完整目录契约。
func is_valid() -> bool:
	if (
		not GFUuid.is_valid(_active_account_id, 7)
		or _account_descriptors.is_empty()
		or _account_descriptors.size() > MAX_ACCOUNT_COUNT
	):
		return false
	var seen_account_ids: Dictionary = {}
	for descriptor: Dictionary in _account_descriptors:
		if not _is_valid_descriptor(descriptor):
			return false
		var account_id: String = GFVariantData.get_option_string(
			descriptor,
			&"account_id"
		)
		if seen_account_ids.has(account_id):
			return false
		seen_account_ids[account_id] = true
	return seen_account_ids.has(_active_account_id)


## 返回快照时刻的活动账号身份。
func get_active_account_id() -> String:
	return _active_account_id


## 返回规范顺序的账号描述符深副本。
func get_account_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for descriptor: Dictionary in _account_descriptors:
		result.append(descriptor.duplicate(true))
	return result


## 返回指定账号的描述符深副本；不存在时返回空字典。
## @param account_id: 待查询的规范本地账号 ID。
func get_account_descriptor(account_id: String) -> Dictionary:
	for descriptor: Dictionary in _account_descriptors:
		if (
			GFVariantData.get_option_string(descriptor, &"account_id")
			== account_id
		):
			return descriptor.duplicate(true)
	return {}


# --- 私有/辅助方法 ---

static func _is_valid_descriptor(descriptor: Dictionary) -> bool:
	if not _has_exact_fields(descriptor):
		return false
	var account_id_value: Variant = descriptor.get(&"account_id")
	var display_name_value: Variant = descriptor.get(&"display_name")
	var last_active_at_value: Variant = descriptor.get(&"last_active_at")
	var profile_file_name_value: Variant = descriptor.get(&"profile_file_name")
	if (
		not account_id_value is String
		or not display_name_value is String
		or not last_active_at_value is int
		or not profile_file_name_value is String
	):
		return false
	var account_id: String = account_id_value
	var display_name: String = display_name_value
	var last_active_at: int = last_active_at_value
	var profile_file_name: String = profile_file_name_value
	return (
		GFUuid.is_valid(account_id, 7)
		and _is_valid_display_name(display_name)
		and last_active_at > 0
		and profile_file_name == _make_expected_profile_file_name(account_id)
	)


static func _has_exact_fields(descriptor: Dictionary) -> bool:
	if descriptor.size() != _DESCRIPTOR_FIELDS.size():
		return false
	for field_name: StringName in _DESCRIPTOR_FIELDS:
		if not descriptor.has(field_name):
			return false
	return true


static func _is_valid_display_name(display_name: String) -> bool:
	if (
		display_name.is_empty()
		or display_name != display_name.strip_edges()
		or display_name.length() > MAX_DISPLAY_NAME_LENGTH
	):
		return false
	for index: int in range(display_name.length()):
		var codepoint: int = display_name.unicode_at(index)
		if codepoint < 32 or codepoint == 127:
			return false
	return true


static func _make_expected_profile_file_name(account_id: String) -> String:
	return "%s/%s%s" % [
		_PROFILE_DIRECTORY,
		account_id,
		_PROFILE_EXTENSION,
	]


static func _freeze_descriptor(descriptor: Dictionary) -> Dictionary:
	return {
		&"account_id": GFVariantData.get_option_string(
			descriptor,
			&"account_id"
		),
		&"display_name": GFVariantData.get_option_string(
			descriptor,
			&"display_name"
		),
		&"last_active_at": GFVariantData.get_option_int(
			descriptor,
			&"last_active_at"
		),
		&"profile_file_name": GFVariantData.get_option_string(
			descriptor,
			&"profile_file_name"
		),
	}
