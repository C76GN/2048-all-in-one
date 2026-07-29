## ProfileFileCleanupUtility: GFBackgroundWorkUtility 使用的无状态文件清理工具。
##
## 实例只由后台任务 Callable 持有，不引用 Architecture、Utility 或 Resource
## 业务状态，因此架构 dispose 取消任务后不会回调已经释放的 GameSaveGraphUtility。
class_name ProfileFileCleanupUtility
extends RefCounted


# --- 公共方法 ---

## 删除后台任务输入中列出的 Profile 临时文件。
## @param input_data: 含绝对文件路径数组 `paths` 的纯数据载荷。
func run(input_data: Variant) -> Dictionary:
	var input: Dictionary = GFVariantData.as_dictionary(input_data)
	var paths: PackedStringArray = (
		GFVariantData.get_option_packed_string_array(
			input,
			&"paths"
		)
	)
	if paths.is_empty():
		return GFResultDictionary.make_failure(
			"profile cleanup paths are empty",
			{&"error_code": int(ERR_INVALID_PARAMETER)}
		)
	for path: String in paths:
		if not FileAccess.file_exists(path):
			continue
		var delete_error: Error = DirAccess.remove_absolute(path)
		if delete_error != OK:
			return GFResultDictionary.make_failure(
				"profile artifact delete failed",
				{
					&"error_code": int(delete_error),
					&"path": path,
				}
			)
	return GFResultDictionary.make_success({
		&"error_code": int(OK),
		&"deleted_path_count": paths.size(),
	})
