## 接收一个小型 chunk GF Profile 的严格一次性读取结果。
##
## Sink 只允许一次写入和一次 claim；事务回滚会永久关闭未提交候选。
class_name ChunkProfileLoadSink
extends RefCounted


# --- 常量 ---

const STATE_PENDING: StringName = &"pending"
const STATE_WRITTEN: StringName = &"written"
const STATE_CLAIMED: StringName = &"claimed"
const STATE_ROLLED_BACK: StringName = &"rolled_back"


# --- 私有变量 ---

var _state: StringName = STATE_PENDING
var _payload: PackedByteArray = PackedByteArray()


# --- 公共方法 ---

## 查询 Sink 是否仍接受唯一一次 Provider 写入。
func can_accept() -> bool:
	return _state == STATE_PENDING


## 查询 Provider 是否已经写入候选 bytes。
func is_written() -> bool:
	return _state == STATE_WRITTEN


## 查询载荷是否已经被物化 owner 接管。
func is_claimed() -> bool:
	return _state == STATE_CLAIMED


## 查询 GF load 事务是否已经回滚候选。
func is_rolled_back() -> bool:
	return _state == STATE_ROLLED_BACK


## 获取当前稳定状态。
func get_state() -> StringName:
	return _state


## 接管 Provider 验证后的唯一 chunk bytes。
##
## @param payload: Provider 移交唯一所有权的非空有界 bytes。
## @return 首次合法写入返回 OK。
func write_once(payload: PackedByteArray) -> Error:
	if not can_accept():
		return ERR_ALREADY_IN_USE
	if not ChunkProfileSaveLease.is_valid_payload(payload):
		return ERR_INVALID_DATA
	_payload = payload
	_state = STATE_WRITTEN
	return OK


## 一次性移出已写入载荷；其余状态返回空数组。
func claim() -> PackedByteArray:
	if _state != STATE_WRITTEN:
		return PackedByteArray()
	var payload: PackedByteArray = _payload
	_payload = PackedByteArray()
	_state = STATE_CLAIMED
	return payload


## 响应 GF Provider 事务回滚并永久丢弃候选。
##
## pending 表示 apply 在写入前失败，同样必须关闭该次 load Sink。
func rollback_for_provider() -> Error:
	if _state not in [STATE_PENDING, STATE_WRITTEN]:
		return ERR_ALREADY_IN_USE
	_payload = PackedByteArray()
	_state = STATE_ROLLED_BACK
	return OK
