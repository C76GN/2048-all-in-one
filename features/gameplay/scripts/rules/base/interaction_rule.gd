## InteractionRule: 方块交互规则的基类蓝图。
##
## 所有具体的交互逻辑都应继承此类。它定义了所有交互规则
## 必须遵循的公共接口，但本身不包含任何具体实现。
class_name InteractionRule
extends Resource


# --- 导出变量 ---

## 当前模式可创建的方块定义；行为由各定义的 GF Capability Recipe 组合。
@export var tile_definitions: Array[TileDefinition] = []

## 未显式指定方块定义时使用的稳定定义 ID。
@export var default_definition_id: StringName = &""


# --- 私有变量 ---

var _tile_composition_utility: TileCompositionUtility = null


# --- 公共方法 ---

## 注入统一的方块组合与交互解析工具。
## @param tile_composition_utility: 当前架构注册的方块组合工具。
func setup(tile_composition_utility: TileCompositionUtility) -> void:
	_tile_composition_utility = tile_composition_utility


## 处理两个方块之间的交互。
##
## @param tile_a: 参与交互的第一个方块。
## @param tile_b: 参与交互的第二个方块（通常是移动的目标方块）。
## @param _p_rule: 对当前交互规则实例的引用，用于更新新方块的状态。
## @return: 一个描述交互结果的字典，可能包含 "merged_tile" 和 "consumed_tile"。
func process_interaction(tile_a: TileState, tile_b: TileState, _p_rule: InteractionRule) -> Dictionary:
	if _tile_composition_utility == null:
		return {}
	return _tile_composition_utility.apply_interaction(tile_a, tile_b)


## 判断两个方块是否可以发生交互，但不实际执行。
##
## 此方法主要由游戏结束规则调用，以检查是否存在任何可能的移动。
## @param tile_a: 第一个方块。
## @param tile_b: 第二个方块。
## @return: 如果可以交互则返回 true。
func can_interact(tile_a: TileState, tile_b: TileState) -> bool:
	return (
		_tile_composition_utility != null
		and _tile_composition_utility.can_interact(tile_a, tile_b)
	)


## 按稳定 ID 解析当前模式的方块定义。
## @param definition_id: 方块定义的稳定 ID。
func get_tile_definition(definition_id: StringName) -> TileDefinition:
	if definition_id == &"":
		return null
	for definition: TileDefinition in tile_definitions:
		if definition != null and definition.definition_id == definition_id:
			return definition
	return null


## 获取当前模式未显式指定身份时使用的方块定义。
func get_default_tile_definition() -> TileDefinition:
	return get_tile_definition(default_definition_id)


## 生成当前模式方块定义的聚合校验报告。
func get_tile_definition_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"InteractionRule:%s" % get_class(),
		{&"resource_path": resource_path}
	)
	if tile_definitions.is_empty():
		var _empty_issue: RefCounted = report.add_error(
			&"empty_tile_definitions",
			"InteractionRule.tile_definitions 不能为空。",
			&"tile_definitions",
			resource_path
		)
		return report
	if default_definition_id == &"":
		var _default_id_issue: RefCounted = report.add_error(
			&"missing_default_definition_id",
			"InteractionRule.default_definition_id 不能为空。",
			&"default_definition_id",
			resource_path
		)

	var seen_ids: Dictionary = {}
	for definition: TileDefinition in tile_definitions:
		if definition == null:
			var _null_issue: RefCounted = report.add_error(
				&"null_tile_definition",
				"InteractionRule 包含空 TileDefinition。",
				&"tile_definitions",
				resource_path
			)
			continue
		if seen_ids.has(definition.definition_id):
			var _duplicate_issue: RefCounted = report.add_error(
				&"duplicate_tile_definition_id",
				"InteractionRule 包含重复 definition_id：%s。" % definition.definition_id,
				definition.definition_id,
				definition.resource_path
			)
		seen_ids[definition.definition_id] = true
		if not definition.get_validation_report().is_ok():
			var _invalid_issue: RefCounted = report.add_error(
				&"invalid_tile_definition",
				"TileDefinition 校验失败：%s。" % definition.definition_id,
				definition.definition_id,
				definition.resource_path
			)
	if default_definition_id != &"" and get_tile_definition(default_definition_id) == null:
		var _unknown_default_issue: RefCounted = report.add_error(
			&"unknown_default_definition_id",
			"default_definition_id 不在 tile_definitions 中：%s。" % default_definition_id,
			&"default_definition_id",
			resource_path
		)
	return report


## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## 例如，在经典模式中，2->0, 4->1, 8->2。此方法主要用于确定方块的视觉样式。
## @param _value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(_value: int) -> int:
	return 0


## 根据方块的数值，返回其应使用的配色方案索引。
##
## 默认返回0。子类可以重写此方法以支持多配色方案。
## @param _value: 方块的数值。
## @param definition_id: 方块的稳定定义 ID。
## @return: 配色方案的索引。
func get_color_scheme_index(_value: int, definition_id: StringName) -> int:
	var definition: TileDefinition = get_tile_definition(definition_id)
	return definition.color_scheme_index if definition != null else 0


## 将此规则相关的统计数据写入传入的 stats 字典。
##
## @param _context: 包含当前游戏状态信息的字典。
## @param _stats: 要写入显示数据的字典。
func get_hud_stats(_context: Dictionary, _stats: Dictionary) -> void:
	pass


## 获取诊断工具可选择的生成选项。
## @return: 键为局部选项 ID、值为可读名称的字典。
func get_spawnable_options() -> Dictionary:
	var options: Dictionary = {}
	for index: int in range(tile_definitions.size()):
		var definition: TileDefinition = tile_definitions[index]
		if definition == null:
			continue
		var display_name: String = tr(definition.display_name_key)
		if display_name == String(definition.display_name_key):
			display_name = String(definition.definition_id)
		options[index] = display_name
	return options


## 根据指定的生成选项 ID，获取所有可生成的方块数值。
##
## @param _option_id: 诊断面板的局部生成选项 ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_option_id: int) -> Array[int]:
	return []


## 根据诊断工具的局部选项 ID 解析稳定方块定义。
## @param option_id: 诊断面板的局部生成选项 ID。
func get_spawn_definition(option_id: int) -> TileDefinition:
	if option_id < 0 or option_id >= tile_definitions.size():
		return null
	return tile_definitions[option_id]
