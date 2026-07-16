## GameSettingsStorageMigrationUtility: 将项目已知的旧版设置载荷一次性迁移到当前 GF 存储格式。
class_name GameSettingsStorageMigrationUtility
extends RefCounted


# --- 公共方法 ---

## 尝试把旧版“XOR + Base64 JSON”设置迁移为当前存储格式。
## 未命中旧格式时不读取当前 codec，交由 GFSettingsUtility 正常加载。
## @param storage: 当前注册的 GFStorageUtility。
## @param file_name: 设置文件的安全 basename。
static func migrate_legacy_json(storage: GFStorageUtility, file_name: String) -> Dictionary:
	var report: Dictionary = _make_report()
	if storage == null:
		report["error"] = "storage is null"
		return report
	if storage.file_format != GFStorageCodec.Format.BINARY:
		return report
	if not _is_safe_settings_file_name(file_name):
		report["error"] = "invalid settings file name"
		return report

	var storage_directory: String = storage.get_storage_directory_path()
	if storage_directory.is_empty():
		report["error"] = "storage directory is empty"
		return report
	var file_path: String = storage_directory.path_join(file_name)
	if not FileAccess.file_exists(file_path):
		return report

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		report["error"] = "legacy settings file cannot be opened"
		return report
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return report
	if storage.use_compression or not _looks_like_legacy_json_payload(bytes, storage.encrypt_key):
		return report

	var legacy_codec: GFStorageCodec = _make_legacy_codec(storage)
	var decode_result: Dictionary = legacy_codec.decode(bytes)
	if not GFVariantData.get_option_bool(decode_result, "ok"):
		return report

	var data: Dictionary = GFVariantData.get_option_dictionary(decode_result, "data")
	var _metadata_erased: bool = data.erase(GFStorageCodec.META_KEY)
	report["matched"] = true
	report["data"] = data.duplicate(true)
	var save_error: Error = storage.save_data(file_name, data)
	report["save_error"] = save_error
	report["migrated"] = save_error == OK
	if save_error != OK:
		report["error"] = "save_data failed with error %d" % save_error
	return report


# --- 私有/辅助方法 ---

static func _make_legacy_codec(storage: GFStorageUtility) -> GFStorageCodec:
	var codec: GFStorageCodec = GFStorageCodec.new()
	codec.format = GFStorageCodec.Format.JSON
	codec.use_compression = storage.use_compression
	codec.obfuscation_key = storage.encrypt_key
	codec.use_integrity_checksum = storage.use_integrity_checksum
	codec.strict_integrity = storage.strict_integrity
	codec.require_integrity_checksum = storage.require_integrity_checksum
	codec.include_metadata = storage.include_storage_metadata
	codec.normalize_json_numbers = storage.normalize_json_numbers
	return codec


static func _looks_like_legacy_json_payload(bytes: PackedByteArray, key: int) -> bool:
	var payload: PackedByteArray = PackedByteArray(bytes)
	if key != 0:
		var encoded_text: String = bytes.get_string_from_utf8().strip_edges()
		if not _looks_like_base64_text(encoded_text):
			return false
		payload = Marshalls.base64_to_raw(encoded_text)
		if payload.is_empty():
			return false
		var key_byte: int = key & 0xff
		for index: int in range(payload.size()):
			payload[index] = payload[index] ^ key_byte

	var json_text: String = payload.get_string_from_utf8().strip_edges()
	return json_text.begins_with("{") and json_text.ends_with("}")


static func _looks_like_base64_text(text: String) -> bool:
	if text.is_empty() or text.length() % 4 != 0:
		return false

	var padding_count: int = 0
	var padding_started: bool = false
	for index: int in range(text.length()):
		var code: int = text.unicode_at(index)
		if code == 61:
			padding_started = true
			padding_count += 1
			if padding_count > 2:
				return false
			continue
		if padding_started or not _is_base64_code(code):
			return false
	return true


static func _is_base64_code(code: int) -> bool:
	return (
		(code >= 65 and code <= 90)
		or (code >= 97 and code <= 122)
		or (code >= 48 and code <= 57)
		or code == 43
		or code == 47
	)


static func _is_safe_settings_file_name(file_name: String) -> bool:
	if file_name.is_empty() or file_name.is_absolute_path():
		return false
	return file_name == file_name.get_file()


static func _make_report() -> Dictionary:
	return {
		"matched": false,
		"migrated": false,
		"data": {},
		"save_error": OK,
		"error": "",
	}
