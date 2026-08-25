## GameSaveSectionUiOperationState: UI 对 section 持久化事务的有界生命周期投影。
##
## 页面只向本状态提交操作上下文，并消费类型化终态与对账证据；token、busy、
## outcome-unknown 和迟到证据匹配只在一个 Implementation 中维护。业务页面继续
## 拥有刷新、选择恢复和本地化文案，不把 UI 规则放入 persistence Module。
class_name GameSaveSectionUiOperationState
extends RefCounted


# --- 私有变量 ---

var _token: int = 0
var _busy: bool = false
var _reconciling: bool = false
var _transaction_id: int = 0
var _context: Dictionary = {}
var _reconciliation_prompted: bool = false


# --- 公共方法 ---

## 开始一次新的页面持久化操作，并返回用于拒绝迟到终态的单调 token。
## @param context: 页面拥有的浅层上下文；本状态不解释其中业务字段。
func begin(context: Dictionary = {}) -> int:
	_token += 1
	_busy = true
	_reconciling = false
	_transaction_id = 0
	_context = context.duplicate(false)
	_reconciliation_prompted = false
	return _token


## 使全部在途回调失效，并释放页面上下文。
func invalidate() -> void:
	_token += 1
	_busy = false
	_reconciling = false
	_transaction_id = 0
	_context.clear()
	_reconciliation_prompted = false


## 返回页面是否必须阻止新的持久化或选择操作。
func is_blocked() -> bool:
	return _busy or _reconciling


## 返回页面是否正在刷新、保存或等待异步终态。
func is_busy() -> bool:
	return _busy


## 返回页面是否正在等待 outcome-unknown 对账。
func is_reconciling() -> bool:
	return _reconciling


## 返回当前单调 token。
func get_token() -> int:
	return _token


## 返回当前对账事务标识；未对账时为零。
func get_transaction_id() -> int:
	return _transaction_id


## 返回页面上下文的浅副本。
func get_context() -> Dictionary:
	return _context.duplicate(false)


## 返回 token 与 owner 是否仍代表当前页面操作。
## @param token: 发起页面操作时取得的单调 token。
## @param owner: 可选页面节点；传入时还必须有效且位于场景树中。
func is_current(token: int, owner: Node = null) -> bool:
	if token != _token:
		return false
	return owner == null or (is_instance_valid(owner) and owner.is_inside_tree())


## 标记一次请求已取得类型化终态；outcome-unknown 可随后进入对账状态。
## @param token: 发起页面操作时取得的单调 token。
## @param owner: 可选页面节点；传入时还必须有效且位于场景树中。
func finish_request(token: int, owner: Node = null) -> bool:
	if not _busy or _reconciling or not is_current(token, owner):
		return false
	_busy = false
	return true


## 从需要对账的类型化结果进入 outcome-unknown 状态。
## @param result: 声明需要对账且携带有效事务标识的 Section 终态。
func begin_reconciliation(result: GameSaveSectionResult) -> bool:
	if (
		_busy
		or _reconciling
		or result == null
		or not result.requires_reconciliation()
	):
		return false
	var transaction_id: int = result.get_transaction_id()
	if transaction_id <= 0:
		return false
	_busy = false
	_reconciling = true
	_transaction_id = transaction_id
	return true


## 判断 SaveGraph 证据是否属于当前 outcome-unknown 事务。
## @param evidence: SaveGraph 发布的事务终态证据字典。
func matches_reconciliation_evidence(evidence: Dictionary) -> bool:
	return (
		_reconciling
		and _transaction_id > 0
		and GFVariantData.get_option_int(evidence, &"transaction_id", 0)
		== _transaction_id
	)


## 接管匹配的对账证据并冻结页面完成刷新所需的通用字段。
## 不匹配时返回空 Dictionary，且保持当前状态不变。
## @param evidence: SaveGraph 发布的事务终态证据字典。
func settle_reconciliation(evidence: Dictionary) -> Dictionary:
	if not matches_reconciliation_evidence(evidence):
		return {}
	var settlement: Dictionary = {
		&"token": _token,
		&"context": _context.duplicate(false),
		&"status": GFVariantData.get_option_string_name(evidence, &"status"),
		&"candidate_persisted": GFVariantData.get_option_bool(
			evidence,
			&"candidate_persisted",
			false
		),
		&"memory_rolled_back": GFVariantData.get_option_bool(
			evidence,
			&"memory_rolled_back",
			false
		),
	}
	_transaction_id = 0
	_reconciling = false
	_busy = true
	return settlement


## 完成对账后的页面刷新并解除 busy；页面可随后清理业务上下文。
## @param token: 发起页面操作时取得的单调 token。
## @param owner: 可选页面节点；传入时还必须有效且位于场景树中。
func finish_reconciliation(token: int, owner: Node = null) -> bool:
	if not _busy or _reconciling or not is_current(token, owner):
		return false
	_busy = false
	return true


## 清理页面拥有的业务上下文；不改变当前 token。
func clear_context() -> void:
	_transaction_id = 0
	_context.clear()


## 仅允许一次展示当前对账终态提示。
func claim_reconciliation_prompt() -> bool:
	if is_blocked() or _reconciliation_prompted:
		return false
	_reconciliation_prompted = true
	return true
