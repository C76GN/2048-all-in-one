## LocalAccountSystem: 原子协调设备账号目录与独立玩家 SaveGraph Profile。
class_name LocalAccountSystem
extends GFSystem


# --- 信号 ---

signal active_account_changed(account: LocalPlayerAccount)
signal account_catalog_changed()


# --- 私有变量 ---

var _catalog: LocalAccountCatalogUtility = null
var _save_graph: GameSaveGraphUtility = null
var _last_cleanup_error: Error = OK


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameSaveGraphUtility, LocalAccountCatalogUtility]


func ready() -> void:
	_catalog = _resolve_catalog_utility()
	_save_graph = _resolve_save_graph_utility()
	if not _is_configured():
		push_error("[LocalAccountSystem] 本地账号或 SaveGraph Utility 未注册。")
		return
	var active_account: LocalPlayerAccount = _catalog.get_active_account()
	if active_account == null:
		push_error("[LocalAccountSystem] 本地账号目录没有有效的当前账号。")
		return
	var activate_error: Error = _save_graph.activate_profile(
		LocalAccountCatalogUtility.make_profile_file_name(
			active_account.account_id
		),
		true
	)
	if activate_error != OK:
		push_error(
			"[LocalAccountSystem] 当前账号 Profile 激活失败，错误码：%d。"
			% activate_error
		)


func dispose() -> void:
	_catalog = null
	_save_graph = null
	_last_cleanup_error = OK


# --- 公共方法 ---

## 返回设备账号目录。
func get_accounts() -> Array[LocalPlayerAccount]:
	if not is_instance_valid(_catalog):
		return []
	return _catalog.get_accounts()


## 返回当前账号。
func get_active_account() -> LocalPlayerAccount:
	return _catalog.get_active_account() if is_instance_valid(_catalog) else null


## 返回最近一次孤立 Profile 文件清理错误。
func get_last_cleanup_error() -> Error:
	return _last_cleanup_error


## 创建账号并立即切换到其独立空 Profile。
## @param display_name: 新账号在此设备上的显示名称。
func create_account(display_name: String) -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var previous_account: LocalPlayerAccount = _catalog.get_active_account()
	var account: LocalPlayerAccount = _catalog.create_account(display_name)
	if account == null:
		return _catalog.get_last_error()

	var profile_file_name: String = LocalAccountCatalogUtility.make_profile_file_name(
		account.account_id
	)
	var profile_error: Error = _save_graph.activate_profile(
		profile_file_name,
		false
	)
	if profile_error != OK:
		var catalog_create_rollback_error: Error = _catalog.delete_account(
			account.account_id
		)
		if catalog_create_rollback_error != OK:
			push_error(
				"[LocalAccountSystem] 新账号 Profile 创建失败后目录回滚也失败，错误码：%d。"
				% catalog_create_rollback_error
			)
		return profile_error

	var activate_error: Error = _catalog.set_active_account(account.account_id)
	if activate_error != OK:
		if previous_account != null:
			var _profile_rollback_error: Error = _save_graph.activate_profile(
				LocalAccountCatalogUtility.make_profile_file_name(
					previous_account.account_id
				),
				false
			)
		var catalog_activation_rollback_error: Error = _catalog.delete_account(
			account.account_id
		)
		if catalog_activation_rollback_error != OK:
			push_error(
				"[LocalAccountSystem] 新账号激活失败后目录回滚也失败，错误码：%d。"
				% catalog_activation_rollback_error
			)
		var _profile_cleanup_error: Error = _save_graph.delete_inactive_profile(
			profile_file_name
		)
		return activate_error

	_publish_account_change(
		previous_account.account_id if previous_account != null else "",
		account
	)
	return OK


## 切换到一个既有账号的独立 Profile。
## @param account_id: 要激活的本地账号稳定 ID。
func switch_account(account_id: String) -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var previous_account: LocalPlayerAccount = _catalog.get_active_account()
	if previous_account != null and previous_account.account_id == account_id:
		return OK
	var next_account: LocalPlayerAccount = _catalog.get_account(account_id)
	if next_account == null:
		return ERR_DOES_NOT_EXIST

	var switch_error: Error = _save_graph.activate_profile(
		LocalAccountCatalogUtility.make_profile_file_name(account_id),
		false
	)
	if switch_error != OK:
		return switch_error
	var catalog_error: Error = _catalog.set_active_account(account_id)
	if catalog_error != OK:
		if previous_account != null:
			var _rollback_error: Error = _save_graph.activate_profile(
				LocalAccountCatalogUtility.make_profile_file_name(
					previous_account.account_id
				),
				false
			)
		return catalog_error

	_publish_account_change(
		previous_account.account_id if previous_account != null else "",
		next_account
	)
	return OK


## 修改账号显示名称。
## @param account_id: 要重命名的本地账号稳定 ID。
## @param display_name: 账号的新显示名称。
func rename_account(account_id: String, display_name: String) -> Error:
	if not is_instance_valid(_catalog):
		return ERR_UNCONFIGURED
	var rename_error: Error = _catalog.rename_account(
		account_id,
		display_name
	)
	if rename_error == OK:
		account_catalog_changed.emit()
		var active_account: LocalPlayerAccount = _catalog.get_active_account()
		if active_account != null and active_account.account_id == account_id:
			active_account_changed.emit(active_account)
	return rename_error


## 删除账号；删除当前账号时原子切换到最近使用的其他账号。
## @param account_id: 要删除的本地账号稳定 ID。
func delete_account(account_id: String) -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var accounts: Array[LocalPlayerAccount] = _catalog.get_accounts()
	if accounts.size() <= 1:
		return ERR_BUSY
	var target: LocalPlayerAccount = _catalog.get_account(account_id)
	if target == null:
		return ERR_DOES_NOT_EXIST

	var active_account: LocalPlayerAccount = _catalog.get_active_account()
	var fallback: LocalPlayerAccount = null
	var deleted_active_account: bool = (
		active_account != null
		and active_account.account_id == account_id
	)
	if deleted_active_account:
		for candidate: LocalPlayerAccount in accounts:
			if candidate.account_id != account_id:
				fallback = candidate
				break
		if fallback == null:
			return ERR_BUSY
		var profile_switch_error: Error = _save_graph.activate_profile(
			LocalAccountCatalogUtility.make_profile_file_name(
				fallback.account_id
			),
			false
		)
		if profile_switch_error != OK:
			return profile_switch_error

	var delete_error: Error = (
		_catalog.delete_active_account_with_fallback(
			account_id,
			fallback.account_id
		)
		if deleted_active_account
		else _catalog.delete_account(account_id)
	)
	if delete_error != OK:
		if deleted_active_account and active_account != null:
			var profile_rollback_error: Error = _save_graph.activate_profile(
				LocalAccountCatalogUtility.make_profile_file_name(
					active_account.account_id
				),
				false
			)
			if profile_rollback_error != OK:
				push_error(
					"[LocalAccountSystem] 删除当前账号失败后 Profile 回滚也失败，错误码：%d。"
					% profile_rollback_error
				)
				return profile_rollback_error
		return delete_error
	_last_cleanup_error = _save_graph.delete_inactive_profile(
		LocalAccountCatalogUtility.make_profile_file_name(account_id)
	)
	if _last_cleanup_error != OK:
		push_error(
			"[LocalAccountSystem] 账号已移除，但孤立 Profile 清理失败，错误码：%d。"
			% _last_cleanup_error
		)
	if deleted_active_account and fallback != null and active_account != null:
		_publish_account_change(active_account.account_id, fallback)
	else:
		account_catalog_changed.emit()
	return OK


# --- 私有/辅助方法 ---

func _publish_account_change(
	previous_account_id: String,
	account: LocalPlayerAccount
) -> void:
	var current_account: LocalPlayerAccount = _catalog.get_account(
		account.account_id
	)
	if current_account == null:
		return
	active_account_changed.emit(current_account)
	account_catalog_changed.emit()
	var event_data: ActiveLocalAccountChangedData = (
		ActiveLocalAccountChangedData.create(
			previous_account_id,
			current_account
		)
	)
	if event_data != null:
		send_event(event_data)


func _is_configured() -> bool:
	return is_instance_valid(_catalog) and is_instance_valid(_save_graph)


func _resolve_catalog_utility() -> LocalAccountCatalogUtility:
	var utility_value: Object = get_utility(LocalAccountCatalogUtility)
	if utility_value is LocalAccountCatalogUtility:
		var catalog: LocalAccountCatalogUtility = utility_value
		return catalog
	return null


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = utility_value
		return save_graph
	return null
