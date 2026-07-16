## RatioInteractionRule: 同定义方块翻倍、不同定义方块求商的交互规则。
class_name RatioInteractionRule
extends InteractionRule


# --- 常量 ---

const _RATIO_RESOLUTIONS_FORMAT_FALLBACK: String = "求商次数: %d"


# --- 公共方法 ---

## 根据方块的数值，返回它在当前模式数值序列中的索引（等级）。
##
## @param value: 方块的数值。
## @return: 对应的等级索引。
func get_level_by_value(value: int) -> int:
	if value <= 0:
		return 0
	var level: int = int(log(value) / log(2))
	return max(0, level)


## 获取比值模式可生成的方块数值。
##
## @param _option_id: 诊断面板的局部生成选项 ID。
## @return: 一个包含所有合法数值(int)的数组。
func get_spawnable_values(_option_id: int) -> Array[int]:
	var values: Array[int] = []
	var current_power_of_two: int = 2
	while current_power_of_two <= 8192:
		values.append(current_power_of_two)
		current_power_of_two *= 2
	return values


## 将比值规则相关的 HUD 显示数据写入传入的 stats 对象。
##
## @param context: 包含当前游戏统计信息的 Dictionary 对象。
## @param stats: 要写入显示数据的 Dictionary 对象。
func get_hud_stats(context: Dictionary, stats: Dictionary) -> void:
	var ratio_resolutions: int = GFVariantData.to_int(context.get(&"ratio_resolutions", 0), 0)
	if ratio_resolutions >= 0:
		stats[&"ratio_resolutions_display"] = GameTextFormatUtility.format_template(
			tr("RATIO_RESOLUTIONS_DISPLAY"),
			_RATIO_RESOLUTIONS_FORMAT_FALLBACK,
			[ratio_resolutions]
		)
