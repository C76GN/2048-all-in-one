## ProjectStorageRecoveryPolicy: 项目对不可读 GFStorage 文档的统一恢复策略。
##
## 仅物理格式损坏或无法识别时允许删除重建；未来版本和业务 schema 错误必须保留原档并显式失败。
class_name ProjectStorageRecoveryPolicy
extends RefCounted


## 判断失败读取是否允许按项目 reset_allowed 契约重建。
## @param result: GFStorageUtility 返回的强类型失败结果。
## @return 仅物理格式错误允许重建时返回 true。
static func should_reset_failed_read(result: GFStorageReadResult) -> bool:
	if result == null or result.ok:
		return false
	match result.error_code:
		ERR_PARSE_ERROR, ERR_FILE_UNRECOGNIZED, ERR_FILE_CORRUPT:
			return true
		_:
			return false


## 通过 GFStorageUtility 删除不可读文件及其事务伴生文件。
## @param storage: 拥有目标文件及事务语义的 GFStorageUtility。
## @param file_name: 要重置的存储相对文件名。
## @param result: 触发恢复决策的失败读取结果。
## @return 删除结果；不满足重置策略时返回 ERR_INVALID_DATA。
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
