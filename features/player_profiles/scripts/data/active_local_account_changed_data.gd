## ActiveLocalAccountChangedData: 本地账号 Profile 完成切换后的领域事件。
class_name ActiveLocalAccountChangedData
extends RefCounted


# --- 公共变量 ---

var previous_account_id: String = ""
var account: LocalPlayerAccount = null


# --- 公共方法 ---

## 创建一个账号切换完成事件。
## @param p_previous_account_id: 切换前的账号稳定 ID；首次激活时为空。
## @param p_account: 已成功激活的新账号快照。
static func create(
	p_previous_account_id: String,
	p_account: LocalPlayerAccount
) -> ActiveLocalAccountChangedData:
	if p_account == null or not p_account.is_valid():
		return null
	var result: ActiveLocalAccountChangedData = ActiveLocalAccountChangedData.new()
	result.previous_account_id = p_previous_account_id
	result.account = LocalPlayerAccount.from_dict(p_account.to_dict())
	return result
