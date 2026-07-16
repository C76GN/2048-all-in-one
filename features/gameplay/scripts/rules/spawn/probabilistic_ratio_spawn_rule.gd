## ProbabilisticRatioSpawnRule: 按递增概率生成另一种比值方块定义。
##
## 规则行为:
## 1. 监听移动事件 (ON_MOVE)。
## 2. 每次移动后，有较低概率生成指定的替代定义；失败时交给后续规则生成默认定义。
## 3. 失败会提高下次概率，成功后恢复基础概率。
## 4. 生成数值根据当前棋盘最大值动态调整。
class_name ProbabilisticRatioSpawnRule
extends SpawnRule


# --- 常量 ---

const _ALTERNATE_CHANCE_FORMAT_FALLBACK: String = "下次出现比值方块概率: %.1f%%"
const _RATIO_PROBABILITY_FORMAT_FALLBACK: String = "  - %d (概率: %.1f%%)\n"


# --- 导出变量 ---

@export_group("概率配置")

## 生成替代定义的基础概率（0.0 到 1.0 之间）。
@export_range(0.0, 1.0) var base_probability: float = 0.05

## 每次生成失败后，概率增加的量。
@export_range(0.0, 1.0) var increase_on_failure: float = 0.02

## 生成概率可以达到的最大值。
@export_range(0.0, 1.0) var max_probability: float = 0.5

## 成功触发时请求生成的稳定方块定义 ID。
@export var alternate_definition_id: StringName = &""


# --- 私有变量 ---

## 当前动态生成概率。
var _current_probability: float = 0.0


# --- 公共方法 ---

## 初始化此规则，设置初始概率。
func setup() -> void:
	_current_probability = base_probability


## RuleSystem调用此函数来执行概率生成逻辑。
## @param context: 包含 grid_model 的上下文。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(context: RuleContext) -> bool:
	if (
		alternate_definition_id == &""
		or not is_instance_valid(context)
		or not is_instance_valid(context.grid_model)
	):
		return false

	if context.grid_model.get_empty_cells().is_empty():
		return false

	var random_stream: GFDeterministicRandom = context.get_random_stream("probabilistic_ratio_spawn_rule")
	if random_stream == null:
		return false

	if random_stream.next_float_unit() < _current_probability:
		var alternate_value: int = _calculate_alternate_value(context.grid_model, context)
		var spawn_data: SpawnData = SpawnData.new()
		spawn_data.value = alternate_value
		spawn_data.definition_id = alternate_definition_id
		spawn_data.is_priority = true
		context.request_spawn(spawn_data)

		_current_probability = base_probability

		return true

	_current_probability = min(_current_probability + increase_on_failure, max_probability)
	return false


## 将 HUD 显示数据写入传入的 stats 字典。
## @param context: 包含 grid_model 的上下文。
## @param stats: 要写入显示数据的字典。
func get_hud_stats(context: RuleContext, stats: Dictionary) -> void:
	stats[&"ratio_chance_label"] = GameTextFormatUtility.format_template(
		tr("RATIO_ALTERNATE_CHANCE"),
		_ALTERNATE_CHANCE_FORMAT_FALLBACK,
		[_current_probability * 100]
	)

	var grid_model: GridModel = context.grid_model if is_instance_valid(context) else null
	var pool: Dictionary = get_alternate_spawn_pool(grid_model)
	var values: Array[int] = GFVariantData.to_int_array(pool.get(&"values", pool.get("values", [])))
	var weights: Array[int] = GFVariantData.to_int_array(pool.get(&"weights", pool.get("weights", [])))
	var spawn_info_text: String = tr("RATIO_SPAWN_INFO")
	var total_weight: int = 0
	for w: int in weights:
		total_weight += w
	if total_weight > 0:
		for i: int in range(weights.size()):
			var p: float = (float(weights[i]) / total_weight) * 100
			spawn_info_text += GameTextFormatUtility.format_template(
				tr("FORMAT_RATIO_PROBABILITY"),
				_RATIO_PROBABILITY_FORMAT_FALLBACK,
				[values[i], p]
			)
	stats[&"spawn_info_label"] = spawn_info_text


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = super.get_validation_report()
	if alternate_definition_id == &"":
		var _definition_issue: RefCounted = report.add_error(
			&"missing_alternate_definition_id",
			"ProbabilisticRatioSpawnRule.alternate_definition_id 不能为空。",
			&"alternate_definition_id",
			resource_path
		)
	if base_probability > max_probability:
		var _probability_issue: RefCounted = report.add_error(
			&"invalid_probability_range",
			"base_probability 不能大于 max_probability。",
			&"base_probability",
			resource_path
		)
	return report


func get_referenced_definition_ids() -> Array[StringName]:
	return [alternate_definition_id] if alternate_definition_id != &"" else []


## 获取规则当前的内部状态，用于保存。
## @return: 一个包含规则状态的可序列化变量 (如字典或基础类型)。
func get_state() -> Variant:
	return {"current_probability": _current_probability}


## 从一个状态值恢复规则的内部状态。
## @param state: 从历史记录中加载的状态值。
func set_state(state: Variant) -> void:
	if not state is Dictionary:
		return

	var state_dict: Dictionary = state
	if state_dict.has("current_probability"):
		_current_probability = clampf(
			GFVariantData.to_float(state_dict["current_probability"], base_probability),
			base_probability,
			max_probability
		)


## 动态计算并获取当前的替代定义生成池。
## @param grid_model: 网格模型引用。
## @return: 一个包含 "values" 和 "weights" 数组的字典。
func get_alternate_spawn_pool(grid_model: GridModel = null) -> Dictionary:
	if not is_instance_valid(grid_model):
		return {"values": [2], "weights": [1]}

	var max_tile_value: int = grid_model.get_max_tile_value()
	if max_tile_value <= 0:
		return {"values": [2], "weights": [1]}

	var k: int = int(log(max_tile_value) / log(2))
	if k < 1:
		k = 1

	var weights: Array[int] = []
	var possible_values: Array[int] = []
	for i: int in range(1, k + 1):
		possible_values.append(int(pow(2, i)))
		weights.append(k - i + 1)

	return {"values": possible_values, "weights": weights}


# --- 私有/辅助方法 ---

## 根据动态生成池计算本次要生成的数值。
## @param grid_model: 网格模型引用。
## @param context: 当前规则上下文；提供确定性随机分支。
## @return: 计算出的替代定义方块数值。
func _calculate_alternate_value(grid_model: GridModel, context: RuleContext) -> int:
	var spawn_pool: Dictionary = get_alternate_spawn_pool(grid_model)
	var possible_values: Array[int] = GFVariantData.to_int_array(spawn_pool.get(&"values", spawn_pool.get("values", [])))
	var weights: Array[int] = GFVariantData.to_int_array(spawn_pool.get(&"weights", spawn_pool.get("weights", [])))

	if possible_values.is_empty():
		return 2

	var total_weight: int = 0
	for w: int in weights:
		total_weight += w
	if total_weight == 0:
		return 2

	if not is_instance_valid(context):
		push_error("[ProbabilisticRatioSpawnRule] 缺少 RuleContext，无法选择生成数值。")
		return 2
	var random_stream: GFDeterministicRandom = context.get_random_stream("probabilistic_ratio_spawn_rule")
	if random_stream == null:
		return 2
	var random_pick: int = random_stream.next_int_range(1, total_weight)

	var cumulative_weight: int = 0
	for i: int in range(weights.size()):
		cumulative_weight += weights[i]
		if random_pick <= cumulative_weight:
			return possible_values[i]

	return 2
