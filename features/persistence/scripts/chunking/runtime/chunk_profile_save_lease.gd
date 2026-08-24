## 持有一个等待小型 chunk Profile Provider 接管的 bytes 载荷。
##
## Lease 只允许一次 claim；创建成功后，调用方必须放弃源 PackedByteArray。
class_name ChunkProfileSaveLease
extends RefCounted


# --- 常量 ---

## 单个 chunk Profile section 的硬字节上限。
const MAX_PAYLOAD_BYTES: int = 128 * 1024


# --- 私有变量 ---

var _payload: PackedByteArray = PackedByteArray()
var _available: bool = false
var _claimed: bool = false


# --- 公共方法 ---

## 接管一个非空且有界的 chunk 载荷。
##
## @param payload: 调用方移交唯一所有权的 bytes。
## @return 合法时返回新 Lease，否则返回 null。
static func take_ownership(payload: PackedByteArray) -> ChunkProfileSaveLease:
	if not is_valid_payload(payload):
		return null
	var lease: ChunkProfileSaveLease = ChunkProfileSaveLease.new()
	lease._payload = payload
	lease._available = true
	return lease


## 验证 bytes 是否满足单个 chunk 的运行时预算。
## @param payload: 待验证的 chunk bytes。
static func is_valid_payload(payload: PackedByteArray) -> bool:
	return not payload.is_empty() and payload.size() <= MAX_PAYLOAD_BYTES


## 查询载荷是否仍可被 Provider 接管。
func is_available() -> bool:
	return _available and not _claimed


## 查询载荷是否已经被 Provider 接管。
func is_claimed() -> bool:
	return _claimed


## 一次性移出载荷；不可用时返回空数组。
func claim() -> PackedByteArray:
	if not is_available():
		return PackedByteArray()
	var payload: PackedByteArray = _payload
	_payload = PackedByteArray()
	_available = false
	_claimed = true
	return payload
