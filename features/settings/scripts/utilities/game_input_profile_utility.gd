## GameInputProfileUtility: 项目输入配置的唯一持久化入口。
##
## 默认绑定继续由 GFInputContext 声明；本工具只保存玩家覆盖，并复用 GF 的
## 检测、格式化和冲突分析数据结构。玩法动画响应策略也作为输入体验设置管理。
class_name GameInputProfileUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal bindings_changed
signal input_timing_mode_changed(mode: InputTimingMode)


# --- 枚举 ---

enum InputTimingMode {
	BUFFERED,
	BLOCK_WHILE_ANIMATING,
	REALTIME_RETARGET,
}


# --- 常量 ---

const INPUT_REMAP_SETTING_KEY: StringName = &"input/remap_config"
const INPUT_TIMING_SETTING_KEY: StringName = &"gameplay/input_timing_mode"
const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload(
	"res://features/gameplay/resources/input/gameplay_input_context.tres"
)


# --- 私有变量 ---

var _settings: GameSettingsUtility
var _input_mapping: GFInputMappingUtility


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameSettingsUtility, GFInputMappingUtility]


func ready() -> void:
	_settings = _get_settings_utility()
	_input_mapping = _get_input_mapping_utility()
	if not is_instance_valid(_settings) or not is_instance_valid(_input_mapping):
		push_error("[GameInputProfileUtility] 缺少设置或输入映射依赖。")
		return
	_load_persisted_remap()


func dispose() -> void:
	_settings = null
	_input_mapping = null


# --- 公共方法 ---

func get_input_timing_mode() -> InputTimingMode:
	if not is_instance_valid(_settings):
		return InputTimingMode.REALTIME_RETARGET
	return _normalize_timing_mode(GFVariantData.to_int(
		_settings.get_value(INPUT_TIMING_SETTING_KEY, InputTimingMode.REALTIME_RETARGET),
		InputTimingMode.REALTIME_RETARGET
	))


## 修改并持久化玩法输入响应策略。
## @param mode: 新的输入响应模式。
func set_input_timing_mode(mode: InputTimingMode) -> void:
	var normalized_mode: InputTimingMode = _normalize_timing_mode(int(mode))
	if get_input_timing_mode() == normalized_mode:
		return
	if not is_instance_valid(_settings):
		return
	_settings.set_value(INPUT_TIMING_SETTING_KEY, int(normalized_mode))
	input_timing_mode_changed.emit(normalized_mode)


## 返回玩法上下文中每个有效绑定的 GF 标准审计记录。
func get_gameplay_binding_items() -> Array[Dictionary]:
	var config: GFInputRemapConfig = _get_remap_config()
	return GFInputConflictAnalyzer.collect_binding_items(
		[GAMEPLAY_INPUT_CONTEXT],
		config,
		true
	)


## 尝试替换绑定。冲突时保持原配置不变并返回结构化 GF 报告。
## @param context_id: 输入上下文标识。
## @param action_id: 抽象动作标识。
## @param binding_index: 要替换的绑定槽位。
## @param input_event: 新的物理输入事件。
## @return GF 冲突分析报告。
func try_set_binding(
	context_id: StringName,
	action_id: StringName,
	binding_index: int,
	input_event: InputEvent
) -> Dictionary:
	if context_id == &"" or action_id == &"" or binding_index < 0 or input_event == null:
		return {"ok": false, "conflicts": [], "reason": "invalid_binding"}

	var current_config: GFInputRemapConfig = _get_remap_config()
	var candidate: GFInputRemapConfig = (
		current_config.duplicate_config()
		if current_config != null
		else GFInputRemapConfig.new()
	)
	candidate.set_binding(context_id, action_id, binding_index, input_event)
	var report: Dictionary = GFInputConflictAnalyzer.build_rebind_report(
		[GAMEPLAY_INPUT_CONTEXT],
		candidate,
		false,
		true
	)
	if not GFVariantData.get_option_bool(report, "ok"):
		return report

	_commit_remap(candidate)
	return report


## 清除单个玩家覆盖，使该槽位回退到上下文默认绑定。
## @param context_id: 输入上下文标识。
## @param action_id: 抽象动作标识。
## @param binding_index: 要恢复的绑定槽位。
func reset_binding(context_id: StringName, action_id: StringName, binding_index: int) -> void:
	var current_config: GFInputRemapConfig = _get_remap_config()
	if current_config == null or not current_config.has_binding(context_id, action_id, binding_index):
		return
	var candidate: GFInputRemapConfig = current_config.duplicate_config()
	candidate.clear_binding(context_id, action_id, binding_index)
	_commit_remap(candidate)


func reset_all_bindings() -> void:
	_commit_remap(GFInputRemapConfig.new())


# --- 私有/辅助方法 ---

func _load_persisted_remap() -> void:
	var config: GFInputRemapConfig = GFInputRemapConfig.new()
	var data: Dictionary = GFVariantData.to_dictionary(
		_settings.get_value(INPUT_REMAP_SETTING_KEY, {})
	)
	var report: Dictionary = config.apply_dict(data)
	if not GFVariantData.get_option_bool(report, "ok"):
		push_warning("[GameInputProfileUtility] 输入映射存档无效，已回退默认绑定。")
		config = GFInputRemapConfig.new()
	_input_mapping.set_remap_config(config)


func _commit_remap(config: GFInputRemapConfig) -> void:
	if not is_instance_valid(_input_mapping) or not is_instance_valid(_settings):
		return
	_input_mapping.set_remap_config(config)
	_settings.set_value(INPUT_REMAP_SETTING_KEY, config.to_dict(true))
	bindings_changed.emit()


func _get_remap_config() -> GFInputRemapConfig:
	if not is_instance_valid(_input_mapping):
		return null
	return _input_mapping.get_remap_config(true)


static func _normalize_timing_mode(value: int) -> InputTimingMode:
	match value:
		InputTimingMode.BUFFERED:
			return InputTimingMode.BUFFERED
		InputTimingMode.BLOCK_WHILE_ANIMATING:
			return InputTimingMode.BLOCK_WHILE_ANIMATING
		_:
			return InputTimingMode.REALTIME_RETARGET


func _get_settings_utility() -> GameSettingsUtility:
	var utility_value: Object = get_utility(GameSettingsUtility)
	if utility_value is GameSettingsUtility:
		var settings: GameSettingsUtility = utility_value
		return settings
	return null


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null
