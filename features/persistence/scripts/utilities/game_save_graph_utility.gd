## GameSaveGraphUtility: 玩家数据 SaveGraph 事务工作流。
##
## 组合 Feature 提供的 GameSaveSectionData，通过 GFSaveGraphUtility 统一执行
## 图检查、严格加载、Source 快照回滚和单文件原子保存。业务字段仍由各 Feature 拥有。
class_name GameSaveGraphUtility
extends GFUtility


# --- 常量 ---

const PROFILE_FILE_NAME: String = "player_data.save"
const PROFILE_SCHEMA_ID: StringName = &"player_data"
const PROFILE_SCHEMA_VERSION: int = 1
const ROOT_SCOPE_ID: StringName = &"player_data"
const PROGRESS_SECTION_ID: StringName = &"progress"
const BOOKMARKS_SECTION_ID: StringName = &"bookmarks"
const REPLAYS_SECTION_ID: StringName = &"replays"
const _PROJECT_VERSION_SETTING: String = "application/config/version"
const _LOG_TAG: String = "GameSaveGraphUtility"


# --- 私有变量 ---

var _section_definitions: Dictionary = {}
var _section_providers: Dictionary = {}
var _root_scope: GFSaveScope = null
var _save_graph: GFSaveGraphUtility = null
var _storage: GFStorageUtility = null
var _log: GFLogUtility = null
var _loaded: bool = false
var _last_load_result: Dictionary = {}
var _last_save_result: Dictionary = {}


# --- GF 生命周期方法 ---

func init() -> void:
	_build_scope_graph()


func ready() -> void:
	_save_graph = _resolve_save_graph_utility()
	_storage = _resolve_storage_utility()
	_log = _resolve_log_utility()
	var load_error: Error = load_profile()
	if load_error != OK and is_instance_valid(_log):
		_log.error(_LOG_TAG, "玩家数据图加载失败，错误码：%d" % load_error)


func dispose() -> void:
	if is_instance_valid(_root_scope):
		_root_scope.free()
	_root_scope = null
	_section_providers.clear()
	_section_definitions.clear()
	_last_load_result.clear()
	_last_save_result.clear()
	_loaded = false
	_save_graph = null
	_storage = null
	_log = null


# --- 公共方法 ---

## 在 GF init 前登记一个 Feature section。
## @param section_id: SaveGraph 中的稳定子作用域标识。
## @param provider: 由业务 Feature 拥有的严格 section Provider。
## @param phase: section 在整图采集和应用时的阶段。
func register_section(
	section_id: StringName,
	provider: GameSaveSectionData,
	phase: GFSaveScope.Phase = GFSaveScope.Phase.NORMAL
) -> bool:
	if is_instance_valid(_root_scope):
		push_error("[GameSaveGraphUtility] register_section 只能在 init 前调用。")
		return false
	if section_id == &"" or provider == null:
		return false
	if provider.section_id != section_id or provider.schema_version <= 0:
		push_error("[GameSaveGraphUtility] section provider 契约不匹配：%s。" % String(section_id))
		return false
	var key: String = String(section_id)
	if _section_definitions.has(key):
		push_error("[GameSaveGraphUtility] section 重复：%s。" % key)
		return false

	_section_definitions[key] = {
		"provider": provider,
		"phase": phase,
	}
	return true


## 获取 section 业务数据副本。
## @param section_id: 要读取的稳定 section 标识。
func get_section_data(section_id: StringName) -> Dictionary:
	var provider: GameSaveSectionData = _get_section_provider(section_id)
	return provider.get_section_data() if provider != null else {}


## 原子替换一个 section，并把完整玩家数据图保存到同一事务文件。
## @param section_id: 要替换的稳定 section 标识。
## @param data: 当前版本的完整 section 业务数据。
func replace_section_data(section_id: StringName, data: Dictionary) -> Error:
	return replace_sections_data({
		String(section_id): data,
	})


## 原子替换多个 section；任一校验或保存失败都会恢复所有内存快照。
## @param sections: 以 section ID 为 key、完整业务数据字典为 value 的替换集合。
func replace_sections_data(sections: Dictionary) -> Error:
	if not _is_configured() or not _loaded:
		return ERR_UNCONFIGURED
	if sections.is_empty():
		return ERR_INVALID_PARAMETER

	var section_keys: Array[String] = []
	var replacements_by_key: Dictionary = {}
	for key_variant: Variant in sections.keys():
		var key: String = GFVariantData.to_text(key_variant).strip_edges()
		if key.is_empty() or section_keys.has(key):
			return ERR_INVALID_PARAMETER
		if _get_section_provider(StringName(key)) == null:
			return ERR_DOES_NOT_EXIST
		if not (sections[key_variant] is Dictionary):
			return ERR_INVALID_DATA
		section_keys.append(key)
		replacements_by_key[key] = GFVariantData.as_dictionary(sections[key_variant])
	section_keys.sort()

	var snapshots: Dictionary = {}
	var applied_keys: Array[String] = []
	for key: String in section_keys:
		var provider: GameSaveSectionData = _get_section_provider(StringName(key))
		snapshots[key] = provider.to_dict()
		var replacement: Dictionary = GFVariantData.get_option_dictionary(replacements_by_key, key)
		var replace_error: Error = provider.replace_section_data(replacement)
		if replace_error != OK:
			_rollback_sections(applied_keys, snapshots)
			return replace_error
		applied_keys.append(key)

	var save_error: Error = save_profile()
	if save_error != OK:
		_rollback_sections(applied_keys, snapshots)
	return save_error


## 生成带项目 metadata 的当前 SaveGraph 预览载荷。
func preview_profile_payload() -> Dictionary:
	if not _is_configured():
		return {}
	var pipeline_context: GFSavePipelineContext = _save_graph.create_pipeline_context(&"gather", _root_scope)
	var payload: Dictionary = _save_graph.gather_scope(_root_scope, {
		"pipeline_context": pipeline_context,
	})
	pipeline_context.finish()
	if payload.is_empty() or not pipeline_context.errors.is_empty():
		return {}
	payload["metadata"] = _build_profile_metadata()
	return payload


## 保存完整玩家数据图。
func save_profile() -> Error:
	if not _is_configured():
		return ERR_UNCONFIGURED
	var pipeline_context: GFSavePipelineContext = _save_graph.create_pipeline_context(&"gather", _root_scope)
	var error: Error = _save_graph.save_scope(
		PROFILE_FILE_NAME,
		_root_scope,
		_build_profile_metadata(),
		{
			"pipeline_context": pipeline_context,
		}
	)
	pipeline_context.finish()
	_last_save_result = {
		"ok": error == OK,
		"error_code": error,
		"pipeline": pipeline_context.to_dict(true),
	}
	return error


## 严格加载完整玩家数据图；首次运行没有文件时保留各 section 默认值。
func load_profile() -> Error:
	_loaded = false
	if not _is_configured():
		_last_load_result = {
			"ok": false,
			"error_code": ERR_UNCONFIGURED,
			"error": "Save graph or storage utility is unavailable.",
		}
		return ERR_UNCONFIGURED

	var storage_result: Dictionary = _storage.load_data_result(PROFILE_FILE_NAME)
	if not GFVariantData.get_option_bool(storage_result, "ok", false):
		var storage_error: String = GFVariantData.get_option_string(storage_result, "error")
		if storage_error == "File not found":
			_loaded = true
			_last_load_result = {
				"ok": true,
				"first_run": true,
				"applied": 0,
			}
			return OK
		_last_load_result = {
			"ok": false,
			"error_code": ERR_FILE_CORRUPT,
			"error": storage_error,
			"integrity_valid": GFVariantData.get_option_bool(storage_result, "integrity_valid", true),
		}
		return ERR_FILE_CORRUPT

	var payload_value: Variant = GFVariantData.get_option_value(storage_result, "data")
	if not (payload_value is Dictionary):
		_last_load_result = {
			"ok": false,
			"error_code": ERR_INVALID_DATA,
			"error": "Player data payload must be a Dictionary.",
		}
		return ERR_INVALID_DATA
	var payload: Dictionary = GFVariantData.as_dictionary(payload_value)
	if not _has_current_profile_metadata(payload):
		_last_load_result = {
			"ok": false,
			"error_code": ERR_INVALID_DATA,
			"error": "Player data schema does not match the current profile schema.",
		}
		return ERR_INVALID_DATA

	var validation: Dictionary = _save_graph.validate_payload_for_scope(_root_scope, payload, true)
	if not GFVariantData.get_option_bool(validation, "ok", false):
		_last_load_result = {
			"ok": false,
			"error_code": ERR_INVALID_DATA,
			"error": GFVariantData.get_option_string(validation, "summary", "SaveGraph validation failed."),
			"validation": validation,
		}
		return ERR_INVALID_DATA

	var pipeline_context: GFSavePipelineContext = _save_graph.create_pipeline_context(&"apply", _root_scope)
	var apply_result: Dictionary = _save_graph.apply_scope(
		_root_scope,
		payload,
		{
			"pipeline_context": pipeline_context,
			"transactional_apply": true,
		},
		true
	)
	pipeline_context.finish()
	var ok: bool = GFVariantData.get_option_bool(apply_result, "ok", false)
	_last_load_result = apply_result.duplicate(true)
	_last_load_result["pipeline"] = pipeline_context.to_dict(true)
	_last_load_result["first_run"] = false
	_last_load_result["error_code"] = OK if ok else ERR_INVALID_DATA
	_loaded = ok
	return OK if ok else ERR_INVALID_DATA


## 当前图是否已经完成首次加载决策。
func is_profile_loaded() -> bool:
	return _loaded


## 返回 SaveGraph 结构、schema 和最近事务诊断。
func get_debug_snapshot() -> Dictionary:
	var health: Dictionary = {}
	if _save_graph != null and is_instance_valid(_root_scope):
		health = _save_graph.build_scope_health_report(_root_scope)
	return {
		"profile_file": PROFILE_FILE_NAME,
		"schema_id": String(PROFILE_SCHEMA_ID),
		"schema_version": PROFILE_SCHEMA_VERSION,
		"loaded": _loaded,
		"section_ids": _get_registered_section_ids(),
		"graph_health": health,
		"last_load": _last_load_result.duplicate(true),
		"last_save": _last_save_result.duplicate(true),
	}


# --- 私有/辅助方法 ---

func _build_scope_graph() -> void:
	_root_scope = GFSaveScope.new()
	_root_scope.name = "PlayerData"
	_root_scope.scope_key = ROOT_SCOPE_ID
	_root_scope.restore_policy = GFSaveScope.RestorePolicy.APPLY_ONLY_EXISTING

	var section_ids: Array[String] = []
	for section_id_variant: Variant in _section_definitions.keys():
		section_ids.append(GFVariantData.to_text(section_id_variant))
	section_ids.sort_custom(func(left: String, right: String) -> bool:
		var left_phase: int = GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(_section_definitions, left),
			"phase",
			GFSaveScope.Phase.NORMAL
		)
		var right_phase: int = GFVariantData.get_option_int(
			GFVariantData.get_option_dictionary(_section_definitions, right),
			"phase",
			GFSaveScope.Phase.NORMAL
		)
		return left < right if left_phase == right_phase else left_phase < right_phase
	)

	for section_id: String in section_ids:
		var definition: Dictionary = GFVariantData.get_option_dictionary(_section_definitions, section_id)
		var provider: GameSaveSectionData = _get_provider_value(GFVariantData.get_option_value(definition, "provider"))
		if provider == null:
			continue
		var phase: GFSaveScope.Phase = _get_scope_phase(definition)
		var scope: GFSaveScope = GFSaveScope.new()
		scope.name = section_id.to_pascal_case()
		scope.scope_key = StringName(section_id)
		scope.phase = phase

		var source: GFSaveDataSource = GFSaveDataSource.new()
		source.name = "State"
		source.source_key = &"state"
		source.phase = phase
		source.data = provider
		source.gather_method = &"to_dict"
		source.apply_method = &"replace_from_dict"
		scope.add_child(source)
		_root_scope.add_child(scope)
		_section_providers[section_id] = provider


func _is_configured() -> bool:
	return (
		_save_graph != null
		and _storage != null
		and is_instance_valid(_root_scope)
		and not _section_providers.is_empty()
	)


func _get_scope_phase(definition: Dictionary) -> GFSaveScope.Phase:
	match GFVariantData.get_option_int(definition, "phase", GFSaveScope.Phase.NORMAL):
		GFSaveScope.Phase.EARLY:
			return GFSaveScope.Phase.EARLY
		GFSaveScope.Phase.LATE:
			return GFSaveScope.Phase.LATE
		_:
			return GFSaveScope.Phase.NORMAL


func _get_section_provider(section_id: StringName) -> GameSaveSectionData:
	return _get_provider_value(GFVariantData.get_option_value(_section_providers, String(section_id)))


func _get_provider_value(value: Variant) -> GameSaveSectionData:
	if value is GameSaveSectionData:
		var provider: GameSaveSectionData = value
		return provider
	return null


func _rollback_sections(applied_keys: Array[String], snapshots: Dictionary) -> void:
	for index: int in range(applied_keys.size() - 1, -1, -1):
		var key: String = applied_keys[index]
		var provider: GameSaveSectionData = _get_section_provider(StringName(key))
		if provider == null:
			continue
		var snapshot: Dictionary = GFVariantData.get_option_dictionary(snapshots, key)
		var rollback_error: Error = provider.replace_from_dict(snapshot)
		if rollback_error != OK:
			push_error("[GameSaveGraphUtility] section 回滚失败：%s，错误码：%d。" % [key, rollback_error])


func _build_profile_metadata() -> Dictionary:
	return {
		"schema_id": String(PROFILE_SCHEMA_ID),
		"schema_version": PROFILE_SCHEMA_VERSION,
		"app_version": GFVariantData.to_text(ProjectSettings.get_setting(_PROJECT_VERSION_SETTING, "")),
	}


func _has_current_profile_metadata(payload: Dictionary) -> bool:
	var metadata_value: Variant = GFVariantData.get_option_value(payload, "metadata")
	if not (metadata_value is Dictionary):
		return false
	var metadata: Dictionary = GFVariantData.as_dictionary(metadata_value)
	return (
		GFVariantData.get_option_string_name(metadata, "schema_id") == PROFILE_SCHEMA_ID
		and GFVariantData.get_option_int(metadata, "schema_version") == PROFILE_SCHEMA_VERSION
	)


func _get_registered_section_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for section_id_variant: Variant in _section_providers.keys():
		var _append_result: bool = result.append(GFVariantData.to_text(section_id_variant))
	result.sort()
	return result


func _resolve_save_graph_utility() -> GFSaveGraphUtility:
	var utility_value: Object = get_utility(GFSaveGraphUtility)
	if utility_value is GFSaveGraphUtility:
		var utility: GFSaveGraphUtility = utility_value
		return utility
	return null


func _resolve_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility)
	if utility_value is GFStorageUtility:
		var utility: GFStorageUtility = utility_value
		return utility
	return null


func _resolve_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var utility: GFLogUtility = utility_value
		return utility
	return null
