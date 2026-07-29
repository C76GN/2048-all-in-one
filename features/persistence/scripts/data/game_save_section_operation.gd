## GameSaveSectionOperation: 项目 section 持久化事务的一次性异步句柄。
##
## GFSaveProfileOperation 只描述框架保存 generation；本句柄额外覆盖项目内存
## 替换、失败回滚和补偿保存，调用方只消费一个最终业务终态。
class_name GameSaveSectionOperation
extends RefCounted


# --- 信号 ---

## section 事务进入唯一终态时发出一次。
signal completed(result: GameSaveSectionResult)


# --- 私有变量 ---

var _transaction_id: int = 0
var _profile_id: StringName = &""
var _section_ids: PackedStringArray = PackedStringArray()
var _result: GameSaveSectionResult = null


# --- 公共方法 ---

## 返回项目内单调递增的 section 事务标识。
func get_transaction_id() -> int:
	return _transaction_id


## 返回事务开始时冻结的 GF Profile 标识。
func get_profile_id() -> StringName:
	return _profile_id


## 返回按字典序冻结的 section 标识副本。
func get_section_ids() -> PackedStringArray:
	return _section_ids.duplicate()


## 返回操作是否仍在等待唯一终态。
func is_pending() -> bool:
	return _transaction_id > 0 and _result == null


## 返回操作是否已经进入唯一终态。
func is_completed() -> bool:
	return _result != null


## 返回隔离的终态副本；尚未完成时返回 null。
func get_result() -> GameSaveSectionResult:
	return _result.duplicate_result() if _result != null else null


# --- 公共方法（GameSaveGraphUtility 协议） ---

## 由 GameSaveGraphUtility 初始化一次性句柄。
##
## @param transaction_id: 项目内单调递增且大于零的事务标识。
## @param profile_id: 请求时的 GF Profile 标识；配置失败时可为空。
## @param section_ids: 按字典序排列且不包含空值的 section 标识。
func configure_for_utility(
	transaction_id: int,
	profile_id: StringName,
	section_ids: PackedStringArray
) -> bool:
	if _transaction_id > 0 or transaction_id <= 0 or section_ids.is_empty():
		return false
	var canonical_ids: PackedStringArray = section_ids.duplicate()
	canonical_ids.sort()
	for section_id: String in canonical_ids:
		if section_id.strip_edges().is_empty():
			return false
	_transaction_id = transaction_id
	_profile_id = profile_id
	_section_ids = canonical_ids
	return true


## 由 GameSaveGraphUtility 写入唯一终态并发布完成信号。
##
## @param result: 事务标识和 section 集合均与本句柄一致的不可变终态。
func complete_for_utility(result: GameSaveSectionResult) -> bool:
	if not is_pending() or result == null:
		return false
	if (
		result.get_transaction_id() != _transaction_id
		or result.get_section_ids() != _section_ids
	):
		return false
	_result = result.duplicate_result()
	completed.emit(_result.duplicate_result())
	return true
