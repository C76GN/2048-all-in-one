# scripts/global/resource_io_manager.gd

## ResourceIOManager: 提供统一的资源输入输出（IO）逻辑，减少代码重复。
##
## 该类封装了目录检查、资源保存、加载和删除的底层逻辑。
class_name ResourceIOManager
extends RefCounted


# --- 公共方法 ---

## 确保指定的目录存在，如果不存在则创建它。
## @param dir_path: 目标目录路径。
static func ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		var error := DirAccess.make_dir_absolute(dir_path)
		if error == OK:
			print("已创建目录: %s" % dir_path)
		else:
			push_error("创建目录失败: %s (错误码: %d)" % [dir_path, error])


## 将资源保存到指定的文件路径。
## @param resource: 要保存的资源对象。
## @param file_path: 目标文件路径。
## @param type_name: 用于错误提示的类型描述名。
## @return: 如果保存成功返回 OK，否则返回对应的错误码。
static func save_resource(resource: Resource, file_path: String, type_name: String = &"Resource") -> Error:
	if not is_instance_valid(resource):
		push_error("保存%s失败: 无效的资源对象。" % type_name)
		return ERR_INVALID_PARAMETER

	var error := ResourceSaver.save(resource, file_path)
	if error != OK:
		push_error("保存%s文件失败: %s (错误码: %d)" % [type_name, file_path, error])
	else:
		print("%s已成功保存到: %s" % [type_name, file_path])
	
	return error


## 加载指定目录下的所有资源文件。
## @param dir_path: 存放资源文件的目录。
## @param resource_type: 期望加载的资源类型名称（String）。
## @param cache_mode: ResourceLoader 的缓存模式。
## @return: 一个包含加载并检查过的资源实例的数组。
static func load_resources(dir_path: String, resource_type: String, cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_IGNORE) -> Array:
	var loaded_resources: Array = []
	var dir := DirAccess.open(dir_path)

	if not dir:
		push_error("无法打开存储目录: %s" % dir_path)
		return loaded_resources

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var file_path := dir_path.path_join(file_name)
			var loaded_resource := ResourceLoader.load(file_path, resource_type, cache_mode)

			if is_instance_valid(loaded_resource) and loaded_resource.is_class(resource_type) or _matches_custom_class(loaded_resource, resource_type):
				# 克隆实例以确保互不干扰
				var unique_instance := loaded_resource.duplicate()
				# 如果资源类有名为 file_path 的属性，则注入路径
				if &"file_path" in unique_instance:
					unique_instance.file_path = file_path
				loaded_resources.append(unique_instance)
			else:
				push_error("加载资源失败或类型不匹配: %s (期望类型: %s)" % [file_path, resource_type])

		file_name = dir.get_next()

	dir.list_dir_end()
	return loaded_resources


## 删除指定的文件。
## @param file_path: 要删除的文件路径。
## @param type_name: 用于错误提示的类型描述名。
## @return: 如果删除成功返回 OK，否则返回对应的错误码。
static func delete_file(file_path: String, type_name: String = &"文件") -> Error:
	if not FileAccess.file_exists(file_path):
		push_error("删除%s失败: 文件不存在 - %s" % [type_name, file_path])
		return ERR_FILE_NOT_FOUND

	var error := DirAccess.remove_absolute(file_path)
	if error != OK:
		push_error("删除%s文件时出错: %s (错误码: %d)" % [type_name, file_path, error])
	else:
		print("已删除%s文件: %s" % [type_name, file_path])
	
	return error


# --- 私有/辅助方法 ---

## 检查资源是否匹配自定义类名（处理 GDScript 全局类）。
static func _matches_custom_class(resource: Resource, class_name_str: String) -> bool:
	if not resource:
		return false
	# 检查资源是否由该类名标识
	return resource.get_class() == class_name_str or resource.is_class(class_name_str) or (resource.get_script() and resource.get_script().get_global_name() == class_name_str)
