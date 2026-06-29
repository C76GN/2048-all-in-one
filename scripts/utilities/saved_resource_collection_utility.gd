## SavedResourceCollectionUtility: 基于 GFStorageUtility 管理时间戳 Resource 集合。
##
## 统一处理“保存到目录、按时间戳加载、写回文件路径、删除文件”这类持久化流程。
## 适用于书签、回放等数量不固定的项目资源集合，避免各 System 重复存储细节。
class_name SavedResourceCollectionUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const _DEFAULT_EXTENSION: String = "tres"


# --- 私有变量 ---

var _storage: GFStorageUtility = null


# --- Godot 生命周期方法 ---

func ready() -> void:
	_storage = _resolve_storage_utility()


func dispose() -> void:
	_storage = null


# --- 公共方法 ---

## 确保资源集合目录存在。
## @param directory_name: 存储相对目录。
## @return: Godot Error 结果码。
func ensure_collection_directory(directory_name: String) -> Error:
	var storage: GFStorageUtility = _get_storage()
	if not is_instance_valid(storage):
		push_error("[SavedResourceCollectionUtility] ensure_collection_directory 失败：GFStorageUtility 未注册。")
		return FAILED

	return storage.ensure_directory(directory_name)


## 保存一个带时间戳的 Resource，并返回存储相对路径。
## @param directory_name: 存储相对目录。
## @param file_prefix: 文件名前缀。
## @param resource: 要保存的 Resource。
## @param timestamp_property: 用于生成文件名和排序的时间戳属性。
## @param file_path_property: 保存成功后写回资源的文件路径属性。
## @return: 保存成功后的存储相对路径；失败时返回空字符串。
func save_timestamped_resource(
	directory_name: String,
	file_prefix: String,
	resource: Resource,
	timestamp_property: StringName = &"timestamp",
	file_path_property: StringName = &"file_path"
) -> String:
	if directory_name.is_empty() or file_prefix.is_empty() or resource == null:
		push_error("[SavedResourceCollectionUtility] save_timestamped_resource 失败：参数无效。")
		return ""

	var storage: GFStorageUtility = _get_storage()
	if not is_instance_valid(storage):
		push_error("[SavedResourceCollectionUtility] save_timestamped_resource 失败：GFStorageUtility 未注册。")
		return ""

	var timestamp: int = _read_int_property(resource, timestamp_property, int(Time.get_unix_time_from_system()))
	var file_path: String = directory_name.path_join("%s_%d_%d.%s" % [
		file_prefix,
		timestamp,
		Time.get_ticks_msec(),
		_DEFAULT_EXTENSION,
	])
	var error: int = storage.save_resource(file_path, resource)
	if error != OK:
		push_error("[SavedResourceCollectionUtility] 保存 Resource 失败：%s，错误码：%s" % [file_path, error])
		return ""

	_write_property_if_present(resource, file_path_property, file_path)
	return file_path


## 加载指定目录下的时间戳 Resource 集合，并按时间戳降序排列。
## @param directory_name: 存储相对目录。
## @param type_hint: ResourceLoader 类型提示。
## @param required_script: 可选脚本类型过滤；为空时不过滤。
## @param file_path_property: 加载后写回资源的文件路径属性。
## @param timestamp_property: 排序使用的时间戳属性。
## @return: 已加载并排序的资源数组。
func load_timestamped_resources(
	directory_name: String,
	type_hint: String = "",
	required_script: Script = null,
	file_path_property: StringName = &"file_path",
	timestamp_property: StringName = &"timestamp"
) -> Array[Resource]:
	var result: Array[Resource] = []
	var storage: GFStorageUtility = _get_storage()
	if not is_instance_valid(storage):
		return result

	for path: String in storage.list_files(directory_name, _DEFAULT_EXTENSION):
		var resource: Resource = storage.load_resource(path, type_hint)
		if not _is_valid_collection_resource(resource, required_script):
			continue

		_write_property_if_present(resource, file_path_property, path)
		result.append(resource)

	result.sort_custom(func(a: Resource, b: Resource) -> bool:
		return _read_int_property(a, timestamp_property, 0) > _read_int_property(b, timestamp_property, 0)
	)
	return result


## 删除一个集合资源文件。
## @param file_path: 存储相对文件路径。
## @return: Godot Error 结果码。
func delete_resource_file(file_path: String) -> Error:
	if file_path.is_empty():
		return ERR_INVALID_PARAMETER

	var storage: GFStorageUtility = _get_storage()
	if not is_instance_valid(storage):
		return FAILED

	return storage.delete_file(file_path)


# --- 私有/辅助方法 ---

func _get_storage() -> GFStorageUtility:
	if is_instance_valid(_storage):
		return _storage

	_storage = _resolve_storage_utility()
	return _storage


func _resolve_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var storage_utility: GFStorageUtility = utility_value
		return storage_utility
	return null


func _is_valid_collection_resource(resource: Resource, required_script: Script) -> bool:
	if resource == null:
		return false
	if required_script == null:
		return true
	return resource.get_script() == required_script


func _read_int_property(resource: Resource, property_name: StringName, fallback: int) -> int:
	if resource == null or property_name == &"":
		return fallback
	if not GFObjectPropertyTools.has_property(resource, property_name):
		return fallback

	var value: Variant = GFObjectPropertyTools.read_property(resource, NodePath(String(property_name)), fallback)
	return GFVariantData.to_int(value, fallback)


func _write_property_if_present(resource: Resource, property_name: StringName, value: Variant) -> void:
	if resource == null or property_name == &"":
		return
	if not GFObjectPropertyTools.has_property(resource, property_name):
		return

	var _write_result: Dictionary = GFObjectPropertyTools.write_property(
		resource,
		NodePath(String(property_name)),
		value
	)
