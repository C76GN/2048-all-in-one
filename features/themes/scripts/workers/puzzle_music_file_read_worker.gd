## Puzzle Music 2 本地内容包的纯 IO Worker。
##
## 只接收 `user://` 资源路径和稳定资源键，在线程中读取字节；AudioStream 的创建与
## 播放仍由主线程上的 GameBackgroundMusicUtility 完成。
class_name PuzzleMusicFileReadWorker
extends RefCounted


# --- 公共方法 ---

## @param input_data: 包含 path、resource_key、generation 和 max_bytes 的纯 Dictionary。
## @return 始终返回可应用的纯数据结果；读取失败由 `loaded = false` 表示。
func run(input_data: Variant) -> Dictionary:
	var payload: Dictionary = GFVariantData.as_dictionary(input_data)
	var path: String = GFVariantData.get_option_string(payload, "path").strip_edges()
	var resource_key: StringName = GFVariantData.get_option_string_name(
		payload,
		"resource_key"
	)
	var generation: int = GFVariantData.get_option_int(payload, "generation")
	var max_bytes: int = GFVariantData.get_option_int(payload, "max_bytes")
	if (
		path.is_empty()
		or resource_key == &""
		or max_bytes <= 0
		or not path.begins_with("user://content_packages/puzzle_music_2/")
		or path.contains("/../")
		or path.ends_with("/..")
	):
		return _make_result(false, path, resource_key, generation, 0)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _make_result(false, path, resource_key, generation, 0)
	var byte_count: int = file.get_length()
	if byte_count <= 0 or byte_count > max_bytes:
		file.close()
		return _make_result(false, path, resource_key, generation, byte_count)
	var bytes: PackedByteArray = file.get_buffer(byte_count)
	file.close()
	return {
		"loaded": bytes.size() == byte_count,
		"path": path,
		"resource_key": resource_key,
		"generation": generation,
		"byte_count": byte_count,
		"bytes": bytes,
	}


# --- 私有/辅助方法 ---

func _make_result(
	loaded: bool,
	path: String,
	resource_key: StringName,
	generation: int,
	byte_count: int
) -> Dictionary:
	return {
		"loaded": loaded,
		"path": path,
		"resource_key": resource_key,
		"generation": generation,
		"byte_count": byte_count,
		"bytes": PackedByteArray(),
	}
