## ProjectStorageRecoveryPolicy: 项目对不可读 GFStorage logical family 的统一恢复策略。
##
## 仅 GF 已分类为 CORRUPT 的读取允许尝试重建；未来版本和业务 schema 错误必须
## 保留原档并显式失败。若损坏位于 GF 私有 catalog/owner 等结构身份，公开删除
## 入口也会失败，调用方必须保留证据并失败关闭，不能直接修改私有 family 成员。
class_name ProjectStorageRecoveryPolicy
extends RefCounted


## 判断失败读取是否允许按项目 reset_allowed 契约重建。
## @param result: GFStorageUtility 返回的强类型失败结果。
## @return 仅 GF 已把读取分类为 CORRUPT、允许尝试授权重建时返回 true。
static func should_reset_failed_read(result: GFStorageReadResult) -> bool:
	if result == null or result.ok:
		return false
	return result.failure_kind == GFStorageReadResult.FailureKind.CORRUPT


## 通过 GFStorageUtility 的 logical identity 删除入口尝试清理不可读 family。
## @param storage: 拥有目标文件及事务语义的 GFStorageUtility。
## @param file_name: 要重置的存储相对文件名。
## @param result: 触发恢复决策的失败读取结果。
## @return 删除结果；不满足重置策略时返回 ERR_INVALID_DATA。结构身份损坏时会
## 原样返回 GF 的失败码，调用方必须失败关闭。
static func reset_failed_file(
	storage: GFStorageUtility,
	file_name: String,
	result: GFStorageReadResult
) -> Error:
	if storage == null or file_name.is_empty():
		return ERR_INVALID_PARAMETER
	if not should_reset_failed_read(result):
		return ERR_INVALID_DATA
	var delete_error: Error = storage.delete_file(file_name)
	return OK if delete_error == OK or delete_error == ERR_FILE_NOT_FOUND else delete_error
