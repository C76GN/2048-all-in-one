## 汇总一次 inactive-bank staging 的不可变 typed 终态。
##
## 成功只表示候选 bank 已完整写入；返回的 Manifest 尚未由外部 owner 提交，
## 因而对玩家 Profile 不可见。
class_name ChunkStageResult
extends RefCounted


# --- 常量 ---

## 所有 inactive-bank chunk 均已由 GF Profile 保存，但尚未可见。
const STATUS_STAGED: StringName = &"staged"

## typed request 或 Manifest schema 非法。
const STATUS_INVALID_REQUEST: StringName = &"invalid_request"

## 当前已有 staging，或 outcome-unknown fence 尚未对账。
const STATUS_BUSY: StringName = &"busy"

## 某个 inactive-bank chunk GF Profile 保存失败。
const STATUS_CHUNK_PROFILE_FAILED: StringName = &"chunk_profile_failed"

## GF 无法确认写入副作用，必须保留 reconciliation fence。
const STATUS_OUTCOME_UNKNOWN: StringName = &"outcome_unknown"

## 取消已在已接纳 GF 操作结算后完成。
const STATUS_CANCELLED: StringName = &"cancelled"


# --- 私有变量 ---

var _successful: bool = false
var _status: StringName = &""
var _error_code: Error = FAILED
var _error: String = ""
var _failed_chunk_index: int = -1
var _manifest: ChunkManifest = null
var _profile_result: GFSaveProfileResult = null


# --- 公共方法 ---

## 创建隔离的 staging 终态。
##
## @param status: STATUS_* 常量之一。
## @param error_code: Godot Error 码。
## @param error: 稳定错误摘要。
## @param failed_chunk_index: chunk 失败序号，非 chunk 失败为 -1。
## @param manifest: 尚未由外部 owner 提交的候选 Manifest。
## @param profile_result: 支撑终态的 GF Profile 结果。
## @return 新的 typed 结果。
static func create(
	status: StringName,
	error_code: Error,
	error: String,
	failed_chunk_index: int = -1,
	manifest: ChunkManifest = null,
	profile_result: GFSaveProfileResult = null
) -> ChunkStageResult:
	var result: ChunkStageResult = ChunkStageResult.new()
	result._successful = status == STATUS_STAGED
	result._status = status
	result._error_code = OK if result._successful else error_code
	result._error = "" if result._successful else error.strip_edges()
	result._failed_chunk_index = failed_chunk_index
	result._manifest = (
		manifest.duplicate_manifest()
		if manifest != null
		else null
	)
	result._profile_result = (
		profile_result.duplicate_result()
		if profile_result != null
		else null
	)
	return result


## 查询 inactive bank 是否已完整 staged。
func is_successful() -> bool:
	return _successful


## 获取稳定终态。
func get_status() -> StringName:
	return _status


## 获取 Godot Error 码。
func get_error_code() -> Error:
	return _error_code


## 获取稳定错误摘要。
func get_error() -> String:
	return _error


## 获取失败 chunk 序号。
func get_failed_chunk_index() -> int:
	return _failed_chunk_index


## 获取尚未可见的候选 Manifest 副本。
func get_manifest() -> ChunkManifest:
	return _manifest.duplicate_manifest() if _manifest != null else null


## 获取支撑终态的 GF Profile 结果副本。
func get_profile_result() -> GFSaveProfileResult:
	return (
		_profile_result.duplicate_result()
		if _profile_result != null
		else null
	)


## 创建与当前结果隔离的副本。
func duplicate_result() -> ChunkStageResult:
	return ChunkStageResult.create(
		_status,
		_error_code,
		_error,
		_failed_chunk_index,
		_manifest,
		_profile_result
	)
