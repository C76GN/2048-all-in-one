## LocalAccountCatalogUtility: 持有设备本地账号目录与当前账号选择。
##
## 账号目录是进入任一玩家 Profile 之前必须可用的设备级身份索引；
## 每个账号的业务数据仍由独立 GameSaveGraph Profile 拥有。
class_name LocalAccountCatalogUtility
extends GFUtility


# --- 信号 ---

signal account_catalog_changed()
signal active_account_changed(account_id: String)


# --- 常量 ---

const CATALOG_FILE_NAME: String = "local_accounts.save"
const MAX_ACCOUNTS: int = 8
const CATALOG_SCHEMA_VERSION: int = 1
const PROFILE_DIRECTORY: String = "profiles"
const PROFILE_EXTENSION: String = ".save"


# --- 私有变量 ---

var _storage: GFStorageUtility = null
var _clock: GameClockUtility = null
var _accounts: Array[LocalPlayerAccount] = []
var _active_account_id: String = ""
var _last_error: Error = OK


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameClockUtility, GFStorageUtility]


func ready() -> void:
	_storage = _resolve_storage_utility()
	_clock = _resolve_clock_utility()
	_last_error = _load_catalog()
	if _last_error != OK:
		push_error(
			"[LocalAccountCatalogUtility] 本地账号目录加载失败，错误码：%d。"
			% _last_error
		)


func dispose() -> void:
	_storage = null
	_clock = null
	_accounts.clear()
	_active_account_id = ""
	_last_error = OK


# --- 公共方法 ---

## 返回账号目录最近一次错误。
func get_last_error() -> Error:
	return _last_error


## 返回当前账号目录的只读副本。
func get_accounts() -> Array[LocalPlayerAccount]:
	var result: Array[LocalPlayerAccount] = []
	for account: LocalPlayerAccount in _accounts:
		var copy: LocalPlayerAccount = LocalPlayerAccount.from_dict(account.to_dict())
		if copy != null:
			result.append(copy)
	return result


## 返回当前激活账号。
func get_active_account() -> LocalPlayerAccount:
	return get_account(_active_account_id)


## 返回当前激活账号 ID。
func get_active_account_id() -> String:
	return _active_account_id


## 按稳定 ID 返回账号只读副本。
func get_account(account_id: String) -> LocalPlayerAccount:
	var account: LocalPlayerAccount = _find_account(account_id)
	return (
		LocalPlayerAccount.from_dict(account.to_dict())
		if account != null
		else null
	)


## 创建但不自动激活一个账号。
func create_account(display_name: String) -> LocalPlayerAccount:
	if not _is_configured():
		_last_error = ERR_UNCONFIGURED
		return null
	if _accounts.size() >= MAX_ACCOUNTS:
		_last_error = ERR_OUT_OF_MEMORY
		return null
	var normalized_name: String = LocalPlayerAccount.normalize_display_name(
		display_name
	)
	if normalized_name.is_empty() or _has_display_name(normalized_name):
		_last_error = ERR_ALREADY_EXISTS if not normalized_name.is_empty() else ERR_INVALID_PARAMETER
		return null

	var account: LocalPlayerAccount = LocalPlayerAccount.create(
		normalized_name,
		_get_unix_timestamp()
	)
	if account == null:
		_last_error = ERR_INVALID_DATA
		return null
	_accounts.append(account)
	_sort_accounts()
	var save_error: Error = _save_catalog()
	if save_error != OK:
		_remove_account_from_memory(account.account_id)
		_last_error = save_error
		return null

	_last_error = OK
	account_catalog_changed.emit()
	return LocalPlayerAccount.from_dict(account.to_dict())


## 修改账号显示名称。
func rename_account(account_id: String, display_name: String) -> Error:
	var account: LocalPlayerAccount = _find_account(account_id)
	var normalized_name: String = LocalPlayerAccount.normalize_display_name(
		display_name
	)
	if account == null or normalized_name.is_empty():
		_last_error = ERR_INVALID_PARAMETER
		return _last_error
	if (
		account.display_name.to_lower() != normalized_name.to_lower()
		and _has_display_name(normalized_name)
	):
		_last_error = ERR_ALREADY_EXISTS
		return _last_error

	var previous_name: String = account.display_name
	account.display_name = normalized_name
	var save_error: Error = _save_catalog()
	if save_error != OK:
		account.display_name = previous_name
		_last_error = save_error
		return save_error

	_last_error = OK
	account_catalog_changed.emit()
	return OK


## 激活一个已存在的账号并持久化最近使用时间。
func set_active_account(account_id: String) -> Error:
	var account: LocalPlayerAccount = _find_account(account_id)
	if account == null:
		_last_error = ERR_DOES_NOT_EXIST
		return _last_error
	if _active_account_id == account_id:
		_last_error = OK
		return OK

	var previous_id: String = _active_account_id
	var previous_active_at: int = account.last_active_at
	_active_account_id = account_id
	account.last_active_at = maxi(_get_unix_timestamp(), account.created_at)
	var save_error: Error = _save_catalog()
	if save_error != OK:
		_active_account_id = previous_id
		account.last_active_at = previous_active_at
		_last_error = save_error
		return save_error

	_last_error = OK
	_sort_accounts()
	active_account_changed.emit(account_id)
	account_catalog_changed.emit()
	return OK


## 删除一个非当前账号；必须始终保留至少一个账号。
func delete_account(account_id: String) -> Error:
	if (
		_accounts.size() <= 1
		or account_id.is_empty()
		or account_id == _active_account_id
	):
		_last_error = ERR_BUSY
		return _last_error
	var index: int = _find_account_index(account_id)
	if index < 0:
		_last_error = ERR_DOES_NOT_EXIST
		return _last_error

	var removed: LocalPlayerAccount = _accounts[index]
	_accounts.remove_at(index)
	var save_error: Error = _save_catalog()
	if save_error != OK:
		_accounts.insert(index, removed)
		_last_error = save_error
		return save_error

	_last_error = OK
	account_catalog_changed.emit()
	return OK


## 返回账号独立 SaveGraph Profile 的存储相对路径。
static func make_profile_file_name(account_id: String) -> String:
	if not GFUuid.is_valid(account_id, 7):
		return ""
	return "%s/%s%s" % [PROFILE_DIRECTORY, account_id, PROFILE_EXTENSION]


# --- 私有/辅助方法 ---

func _load_catalog() -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var read_result: GFStorageReadResult = _storage.load_data(CATALOG_FILE_NAME)
	if not read_result.ok:
		if read_result.error_code == ERR_FILE_NOT_FOUND:
			return _create_default_catalog()
		if ProjectStorageRecoveryPolicy.should_reset_failed_read(read_result):
			var reset_error: Error = ProjectStorageRecoveryPolicy.reset_failed_file(
				_storage,
				CATALOG_FILE_NAME,
				read_result
			)
			return _create_default_catalog() if reset_error == OK else reset_error
		return read_result.error_code
	return _apply_catalog_payload(read_result.payload)


func _apply_catalog_payload(payload: Dictionary) -> Error:
	if not (
		payload.size() == 3
		and GFVariantData.get_option_value(payload, &"schema_version") is int
		and GFVariantData.get_option_value(payload, &"active_account_id") is String
		and GFVariantData.get_option_value(payload, &"accounts") is Array
		and GFVariantData.get_option_int(payload, &"schema_version", 0)
		== CATALOG_SCHEMA_VERSION
	):
		return ERR_INVALID_DATA

	var account_values: Array = GFVariantData.get_option_array(
		payload,
		&"accounts"
	)
	if account_values.is_empty() or account_values.size() > MAX_ACCOUNTS:
		return ERR_INVALID_DATA
	var next_accounts: Array[LocalPlayerAccount] = []
	var seen_ids: Dictionary = {}
	var seen_names: Dictionary = {}
	for account_value: Variant in account_values:
		if not account_value is Dictionary:
			return ERR_INVALID_DATA
		var account: LocalPlayerAccount = LocalPlayerAccount.from_dict(
			GFVariantData.as_dictionary(account_value)
		)
		if account == null:
			return ERR_INVALID_DATA
		var normalized_name_key: String = account.display_name.to_lower()
		if seen_ids.has(account.account_id) or seen_names.has(normalized_name_key):
			return ERR_INVALID_DATA
		seen_ids[account.account_id] = true
		seen_names[normalized_name_key] = true
		next_accounts.append(account)

	var next_active_id: String = GFVariantData.get_option_string(
		payload,
		&"active_account_id"
	)
	if not seen_ids.has(next_active_id):
		return ERR_INVALID_DATA
	_accounts = next_accounts
	_active_account_id = next_active_id
	_sort_accounts()
	return OK


func _create_default_catalog() -> Error:
	var timestamp: int = _get_unix_timestamp()
	var translated_name: String = TranslationServer.translate(
		&"PLAYER_DEFAULT_NAME"
	)
	if translated_name == "PLAYER_DEFAULT_NAME":
		translated_name = "Player 1"
	var account: LocalPlayerAccount = LocalPlayerAccount.create(
		translated_name,
		timestamp
	)
	if account == null:
		return ERR_INVALID_DATA
	_accounts.clear()
	_accounts.append(account)
	_active_account_id = account.account_id
	return _save_catalog()


func _save_catalog() -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var account_data: Array[Dictionary] = []
	for account: LocalPlayerAccount in _accounts:
		if account == null or not account.is_valid():
			return ERR_INVALID_DATA
		account_data.append(account.to_dict())
	return _storage.save_data(
		CATALOG_FILE_NAME,
		{
			&"schema_version": CATALOG_SCHEMA_VERSION,
			&"active_account_id": _active_account_id,
			&"accounts": account_data,
		}
	)


func _find_account(account_id: String) -> LocalPlayerAccount:
	var index: int = _find_account_index(account_id)
	return _accounts[index] if index >= 0 else null


func _find_account_index(account_id: String) -> int:
	for index: int in range(_accounts.size()):
		if _accounts[index].account_id == account_id:
			return index
	return -1


func _remove_account_from_memory(account_id: String) -> void:
	var index: int = _find_account_index(account_id)
	if index >= 0:
		_accounts.remove_at(index)


func _has_display_name(display_name: String) -> bool:
	var normalized_key: String = display_name.to_lower()
	for account: LocalPlayerAccount in _accounts:
		if account.display_name.to_lower() == normalized_key:
			return true
	return false


func _sort_accounts() -> void:
	_accounts.sort_custom(func(left: LocalPlayerAccount, right: LocalPlayerAccount) -> bool:
		if left.last_active_at != right.last_active_at:
			return left.last_active_at > right.last_active_at
		return left.account_id < right.account_id
	)


func _get_unix_timestamp() -> int:
	return maxi(_clock.get_unix_timestamp(), 1) if is_instance_valid(_clock) else 1


func _is_configured() -> bool:
	return is_instance_valid(_storage) and is_instance_valid(_clock)


func _resolve_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage: GFStorageUtility = utility_value
		return storage
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock: GameClockUtility = utility_value
		return clock
	return null
