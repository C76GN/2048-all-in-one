## GameSettingsUtility: 项目设置定义入口。
class_name GameSettingsUtility
extends GFSettingsUtility


# --- 信号 ---

## 设置持久化健康状态发生变化时发出。
## @param snapshot: 由 get_persistence_health_snapshot() 返回的只读快照。
signal persistence_health_changed(snapshot: Dictionary)


# --- 常量 ---

const DEFAULT_LOCALE: String = "zh"
const AUDIO_BUS_MASTER: String = "Master"
const AUDIO_BUS_BGM: String = "BGM"
const AUDIO_BUS_SFX: String = "SFX"
const LOCAL_PERFORMANCE_TRACE_SETTING_KEY: StringName = (
	&"diagnostics/local_performance_trace_enabled"
)


# --- 私有变量 ---

var _last_storage_recovery: Dictionary = {}
var _persistence_blocked_error: Error = OK
var _last_persistence_error: Error = OK
var _clock: GFClock = GFClock.new()
var _operation_diagnostics: GFOperationDiagnosticsUtility = null
var _pending_startup_load_diagnostic: Dictionary = {}


# --- GF 生命周期方法 ---

func ready() -> void:
	super.ready()
	_operation_diagnostics = _get_operation_diagnostics_utility()


## 在 GF 完成 Store ready 与 Settings 准入激活后，应用项目恢复策略并归档诊断。
## @param scope: 当前架构激活阶段的协作取消作用域。
## @return GF Settings 生命周期激活终态；设置文件的产品级恢复结果另行诊断。
func begin_activation(scope: GFAsyncScope) -> GFAsyncCompletion:
	var should_auto_load: bool = auto_load_on_init
	# GF 的 Architecture 自动加载入口使用严格恢复策略；项目需要显式提供只允许
	# corrupt -> reset_to_defaults 的恢复政策，因此由同一 activation 边界接管一次加载。
	auto_load_on_init = false
	var completion: GFAsyncCompletion = super.begin_activation(scope)
	auto_load_on_init = should_auto_load
	if completion != null and completion.is_successful() and should_auto_load:
		var started_ticks_usec: int = _clock.get_monotonic_usec()
		var recovery_policy: GFSettingsRecoveryPolicy = GFSettingsRecoveryPolicy.new()
		recovery_policy.missing_file_action = (
			GFSettingsRecoveryPolicy.ACTION_RESET_TO_DEFAULTS
		)
		recovery_policy.corrupt_file_action = (
			GFSettingsRecoveryPolicy.ACTION_RESET_TO_DEFAULTS
		)
		var load_result: GFSettingsLoadResult = super.load_settings("", recovery_policy)
		_finalize_explicit_storage_recovery(load_result)
		_capture_startup_load_diagnostic(started_ticks_usec, load_result)
	_record_pending_startup_load_diagnostic()
	return completion


func release_dependencies() -> void:
	_operation_diagnostics = null
	_pending_startup_load_diagnostic.clear()
	super.release_dependencies()


# --- 公共方法 ---

func get_required_utilities() -> Array[Script]:
	var dependencies: Array[Script] = super.get_required_utilities()
	dependencies.append(GFOperationDiagnosticsUtility)
	return dependencies


## 注入 Composition Root 拥有的共享单调时钟；测试可使用 GFManualClock。
## @param clock: 项目共享的 GF 时钟。
func set_clock(clock: GFClock) -> bool:
	if clock == null:
		return false
	_clock = clock
	return true


## 返回最近一次设置物理存储恢复诊断。
func get_storage_recovery_snapshot() -> Dictionary:
	return _last_storage_recovery.duplicate(true)


## 返回设置物理存储当前是否可以正常写入。
func is_persistence_healthy() -> bool:
	return _get_effective_persistence_error() == OK


## 返回设置持久化健康快照，供 UI 和支持报告展示。
func get_persistence_health_snapshot() -> Dictionary:
	var error: Error = _get_effective_persistence_error()
	return {
		"healthy": error == OK,
		"error_code": error,
		"persistence_blocked": _persistence_blocked_error != OK,
		"blocked_error_code": _persistence_blocked_error,
		"last_write_error_code": _last_persistence_error,
	}


## 读取设置，并仅在 GF 已确认显式 reset_to_defaults 恢复后尝试重建持久化载荷。
##
## 严格读取和 use_current_state 恢复不得删除底层证据；GFSettingsLoadResult 先决定
## 是否恢复，项目存储策略再通过同一 Store 执行获授权的覆写。若 GF 私有 family
## 结构损坏导致 Store 拒绝覆写，保留内存默认值但把持久化明确标记为失败关闭。
## @param file_name: 可选文件名；为空时使用 GF 设置工具配置的默认文件。
## @param recovery_policy: 可选显式恢复策略；null 保持 GF 严格失败语义。
## @return: GF 返回的结构化加载终态。
func load_settings(
	file_name: String = "",
	recovery_policy: GFSettingsRecoveryPolicy = null
) -> GFSettingsLoadResult:
	var diagnostic_id: StringName = _begin_persistence_diagnostic(&"load")
	var load_result: GFSettingsLoadResult = super.load_settings(
		file_name,
		recovery_policy
	)
	_finalize_explicit_storage_recovery(load_result)
	var error_code: Error = (
		load_result.get_error_code()
		if load_result != null
		else ERR_CANT_ACQUIRE_RESOURCE
	)
	var successful: bool = load_result != null and load_result.is_successful()
	var persistence_error: Error = _get_effective_persistence_error()
	if successful and persistence_error != OK:
		successful = false
		error_code = persistence_error
	_finish_persistence_diagnostic(
		diagnostic_id,
		successful,
		error_code
	)
	return load_result


## 保存当前设置，并把序列化前置失败也纳入项目持久化健康状态。
##
## GFSettingsUtility 会在循环引用等数据无法序列化时于写入钩子之前返回；
## 项目必须在公共保存边界统一记录最终结果，避免 UI 继续宣称自动保存可用。
## @param file_name: 可选文件名；为空时使用 GF 设置工具配置的默认文件。
## @return: GF 保存边界返回的 Godot 错误码。
func save_settings(file_name: String = "") -> Error:
	var diagnostic_id: StringName = _begin_persistence_diagnostic(&"save")
	var error: Error = super.save_settings(file_name)
	_finish_persistence_diagnostic(diagnostic_id, error == OK, error)
	_record_persistence_result(error)
	return error


## 注册项目设置定义。
func register_project_defaults() -> void:
	var _locale_setting: GFSettingDefinition = register_setting(
		GFDisplaySettingsUtility.LOCALE_KEY,
		DEFAULT_LOCALE,
		GFSettingDefinition.ValueType.STRING,
		true,
		{"group": "language", "label": "LANGUAGE_LABEL"}
	)
	var _master_volume_setting: GFSettingDefinition = register_setting(
		StringName("audio/%s/volume" % AUDIO_BUS_MASTER),
		1.0,
		GFSettingDefinition.ValueType.FLOAT,
		true,
		{"group": "audio", "label": "MASTER_VOLUME_LABEL"}
	)
	var _bgm_volume_setting: GFSettingDefinition = register_setting(
		StringName("audio/%s/volume" % AUDIO_BUS_BGM),
		1.0,
		GFSettingDefinition.ValueType.FLOAT,
		true,
		{"group": "audio", "label": "BGM_VOLUME_LABEL"}
	)
	var _sfx_volume_setting: GFSettingDefinition = register_setting(
		StringName("audio/%s/volume" % AUDIO_BUS_SFX),
		1.0,
		GFSettingDefinition.ValueType.FLOAT,
		true,
		{"group": "audio", "label": "SFX_VOLUME_LABEL"}
	)
	var _visual_theme_setting: GFSettingDefinition = register_setting(
		GameThemeUtility.VISUAL_THEME_SETTING_KEY,
		GameThemeUtility.DEFAULT_THEME_ID,
		GFSettingDefinition.ValueType.STRING_NAME,
		true,
		{"group": "appearance", "label": "VISUAL_THEME_LABEL"}
	)
	var _sound_theme_setting: GFSettingDefinition = register_setting(
		GameThemeUtility.SOUND_THEME_SETTING_KEY,
		GameThemeUtility.DEFAULT_SOUND_THEME_ID,
		GFSettingDefinition.ValueType.STRING_NAME,
		true,
		{"group": "audio", "label": "SOUND_THEME_LABEL"}
	)
	var _input_remap_setting: GFSettingDefinition = register_setting(
		GameInputProfileUtility.INPUT_REMAP_SETTING_KEY,
		{
			"remapped_events": {},
			"custom_data": {},
		},
		GFSettingDefinition.ValueType.DICTIONARY,
		true,
		{"group": "input", "label": "INPUT_BINDINGS_TITLE"}
	)
	var _input_timing_setting: GFSettingDefinition = register_setting(
		GameInputProfileUtility.INPUT_TIMING_SETTING_KEY,
		GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET,
		GFSettingDefinition.ValueType.INT,
		true,
		{"group": "input", "label": "INPUT_TIMING_MODE_LABEL"}
	)
	var _reduced_motion_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.REDUCED_MOTION_SETTING_KEY,
		false,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "REDUCED_MOTION_LABEL"}
	)
	var _high_contrast_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.HIGH_CONTRAST_FEEDBACK_SETTING_KEY,
		false,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "HIGH_CONTRAST_FEEDBACK_LABEL"}
	)
	var _haptics_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.HAPTICS_ENABLED_SETTING_KEY,
		true,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "HAPTICS_ENABLED_LABEL"}
	)
	var _shader_effects_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.SHADER_EFFECTS_ENABLED_SETTING_KEY,
		true,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "SHADER_EFFECTS_LABEL"}
	)
	var _vfx_quality_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.VFX_QUALITY_SETTING_KEY,
		GameAccessibilityState.VfxQuality.FULL,
		GFSettingDefinition.ValueType.INT,
		true,
		{"group": "accessibility", "label": "VFX_QUALITY_LABEL"}
	)
	var _turn_subtitles_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.TURN_SUBTITLES_ENABLED_SETTING_KEY,
		true,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "TURN_SUBTITLES_LABEL"}
	)
	var _local_performance_trace_setting: GFSettingDefinition = register_setting(
		LOCAL_PERFORMANCE_TRACE_SETTING_KEY,
		false,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{
			"group": "diagnostics",
			"label": "LOCAL_PERFORMANCE_TRACE_LABEL",
		}
	)


# --- 可重写钩子 ---

func _read_persisted_data(file_name: String) -> GFStorageReadResult:
	# 复用 GFSettingsStoreUtility 的统一读取边界；项目层只叠加健康状态，
	# 不解析或缓存具体 Storage adapter。
	var read_result: GFStorageReadResult = super._read_persisted_data(file_name)
	if read_result.ok:
		_last_storage_recovery.clear()
		_persistence_blocked_error = OK
		_last_persistence_error = OK
		_emit_persistence_health_changed()
		return read_result.duplicate_result()
	if read_result.failure_kind == GFStorageReadResult.FailureKind.NOT_FOUND:
		_last_storage_recovery.clear()
		_persistence_blocked_error = OK
		_last_persistence_error = OK
		_emit_persistence_health_changed()
		return read_result.duplicate_result()
	_persistence_blocked_error = (
		read_result.error_code
		if read_result.error_code != OK
		else ERR_INVALID_DATA
	)
	_last_storage_recovery = {
		"ok": false,
		"recovered": false,
		"persistence_blocked": true,
		"file_name": file_name,
		"error_code": _persistence_blocked_error,
		"error": read_result.error,
		"failure_kind": int(read_result.failure_kind),
	}
	_last_persistence_error = _persistence_blocked_error
	_emit_persistence_health_changed()
	return read_result.duplicate_result()


func _write_persisted_data(file_name: String, data: Dictionary) -> Error:
	var error: Error = OK
	if _persistence_blocked_error != OK:
		error = _persistence_blocked_error
	else:
		error = super._write_persisted_data(file_name, data)
	_record_persistence_result(error)
	return error


# --- 私有/辅助方法 ---

func _finalize_explicit_storage_recovery(
	load_result: GFSettingsLoadResult
) -> void:
	if (
		load_result == null
		or not load_result.is_successful()
		or not load_result.was_recovered()
		or (
			load_result.get_recovery_action()
			!= GFSettingsRecoveryPolicy.ACTION_RESET_TO_DEFAULTS
		)
	):
		return
	var read_result: GFStorageReadResult = load_result.get_storage_result()
	if not ProjectStorageRecoveryPolicy.should_reset_failed_read(read_result):
		return
	# GF 已将 reset_to_defaults 应用到内存权威状态。通过同一 Settings Store
	# 覆盖目标 logical family，避免项目绕过 Store 再管理 Storage 物理生命周期。
	# 该路径可修复 payload/envelope 损坏；catalog、owner 或事务身份等 family
	# 结构损坏会由 Store 明确拒绝。项目此时保留内存默认值，但把持久化标记为
	# 不健康并阻断后续写入，直到 GF 提供 logical-family 授权重建 API。
	_persistence_blocked_error = OK
	# 重建属于当前 load/recovery 的同一业务终态；直接委托 GF save 边界，避免把
	# 一次 activation 恢复拆成额外的项目级 save 诊断。持久化健康仍由写入钩子记录。
	var recreate_error: Error = super.save_settings(load_result.get_file_name())
	_last_storage_recovery = {
		"ok": recreate_error == OK,
		"recovered": recreate_error == OK,
		"load_recovered": true,
		"recovery_action": load_result.get_recovery_action(),
		"file_name": load_result.get_file_name(),
		"discarded_error_code": read_result.error_code,
		"discarded_error": read_result.error,
		"discarded_failure_kind": int(read_result.failure_kind),
		"recreate_error_code": recreate_error,
		"persistence_blocked": recreate_error != OK,
	}
	_persistence_blocked_error = recreate_error
	_last_persistence_error = recreate_error
	_emit_persistence_health_changed()
	if recreate_error != OK:
		push_error(
			"[GameSettingsUtility] 无法按当前 GFStorage 格式重建设置，错误码：%d。"
			% recreate_error
		)


func _record_persistence_result(error: Error) -> void:
	if _last_persistence_error == error:
		return
	_last_persistence_error = error
	_emit_persistence_health_changed()


func _get_effective_persistence_error() -> Error:
	if _persistence_blocked_error != OK:
		return _persistence_blocked_error
	return _last_persistence_error


func _emit_persistence_health_changed() -> void:
	persistence_health_changed.emit(get_persistence_health_snapshot())


func _capture_startup_load_diagnostic(
	started_ticks_usec: int,
	load_result: GFSettingsLoadResult
) -> void:
	var ended_ticks_usec: int = _clock.get_monotonic_usec()
	var error_code: Error = ERR_CANT_ACQUIRE_RESOURCE
	var load_success: bool = load_result != null and load_result.is_successful()
	var status: StringName = &"missing_result"
	var recovered: bool = false
	var recovery_action: StringName = &""
	if load_result != null:
		error_code = load_result.get_error_code()
		status = load_result.get_status()
		recovered = load_result.was_recovered()
		recovery_action = load_result.get_recovery_action()
	var persistence_error: Error = _get_effective_persistence_error()
	var success: bool = load_success and persistence_error == OK
	if load_success and persistence_error != OK:
		error_code = persistence_error
	_pending_startup_load_diagnostic = {
		&"started_ticks_usec": started_ticks_usec,
		&"ended_ticks_usec": ended_ticks_usec,
		&"success": success,
		&"error_code": int(error_code),
		&"status": status,
		&"recovered": recovered,
		&"recovery_action": recovery_action,
	}


func _record_pending_startup_load_diagnostic() -> void:
	if (
		_pending_startup_load_diagnostic.is_empty()
		or not is_instance_valid(_operation_diagnostics)
	):
		return
	var started_ticks_usec: int = GFVariantData.get_option_int(
		_pending_startup_load_diagnostic,
		&"started_ticks_usec"
	)
	var ended_ticks_usec: int = GFVariantData.get_option_int(
		_pending_startup_load_diagnostic,
		&"ended_ticks_usec",
		started_ticks_usec
	)
	var duration_ms: float = maxf(
		float(ended_ticks_usec - started_ticks_usec) / 1000.0,
		0.0
	)
	var _record: Dictionary = _operation_diagnostics.record_completed_operation(
		&"game.settings_persistence",
		duration_ms,
		GFVariantData.get_option_bool(
			_pending_startup_load_diagnostic,
			&"success"
		),
		{
			&"component": &"game_settings",
			&"label": "Load local settings during startup",
			&"started_ticks_usec": started_ticks_usec,
			&"ended_ticks_usec": ended_ticks_usec,
			&"metadata": {
				&"action": &"startup_load",
				&"error_code": GFVariantData.get_option_int(
					_pending_startup_load_diagnostic,
					&"error_code"
				),
				&"load_status": GFVariantData.get_option_string_name(
					_pending_startup_load_diagnostic,
					&"status"
				),
				&"recovered": GFVariantData.get_option_bool(
					_pending_startup_load_diagnostic,
					&"recovered"
				),
				&"recovery_action": GFVariantData.get_option_string_name(
					_pending_startup_load_diagnostic,
					&"recovery_action"
				),
			},
		}
	)
	_pending_startup_load_diagnostic.clear()


func _begin_persistence_diagnostic(action: StringName) -> StringName:
	if not is_instance_valid(_operation_diagnostics):
		return &""
	return _operation_diagnostics.begin_operation(
		&"game.settings_persistence",
		{
			&"component": &"game_settings",
			&"label": "Persist local settings",
			&"metadata": {&"action": action},
		}
	)


func _finish_persistence_diagnostic(
	operation_id: StringName,
	success: bool,
	error_code: Error
) -> void:
	if operation_id == &"" or not is_instance_valid(_operation_diagnostics):
		return
	var _record: Dictionary = _operation_diagnostics.finish_operation(
		operation_id,
		success,
		{&"metadata": {&"error_code": int(error_code)}}
	)


func _get_operation_diagnostics_utility() -> GFOperationDiagnosticsUtility:
	var utility_value: Object = get_utility(GFOperationDiagnosticsUtility)
	if utility_value is GFOperationDiagnosticsUtility:
		var diagnostics: GFOperationDiagnosticsUtility = utility_value
		return diagnostics
	return null
