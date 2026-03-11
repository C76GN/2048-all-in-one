# scripts/data/hud_display_data.gd

## HUDDisplayData: 用于向 HUD 传递完整显示数据的强类型数据对象。
##
## 用于向 HUD 传递更新状态的强类型数据模型。
## 中使用的裸 Dictionary。
## 通过 to_display_dict() 方法可将自身转换为字典，供 HUD 内部的动态渲染逻辑使用。
class_name HUDDisplayData
extends GFPayload


# --- 公共变量 ---

## 回放专用：步骤进度信息（如 "步骤 3 / 10"）。
var step_info: String = ""

## 最高分显示文本。
var high_score: String = ""

## 当前最大方块数值显示文本。
var highest_tile: String = ""

## 分隔线文本。
var separator: String = ""

## 模式说明文本。
var description: String = ""

## 操作提示标题。
var controls_title: String = ""

## 移动操作提示文本。
var controls_move: String = ""

## 功能操作提示文本。
var controls_actions: String = ""

## 随机种子信息文本。
var seed_info: String = ""

## 测试工具已将游戏状态污染时的警告文本。
var taint_warning: String = ""

## HUD 顶部的临时状态消息。
var status_message: String = ""

## 战斗模式：已消灭怪物数量显示文本。
var monsters_killed_display: String = ""

## 斐波那契模式：斐波那契数列显示数据。Array[Dictionary{text: String, color: Color}]
var fibonacci_sequence_display: Array = []

## 卢卡斯斐波那契模式：斐波那契数列显示数据。Array[Dictionary{text: String, color: Color}]
var fib_sequence_display: Array = []

## 卢卡斯斐波那契模式：卢卡斯数列显示数据。Array[Dictionary{text: String, color: Color}]
var luc_sequence_display: Array = []

## 卢卡斯斐波那契模式：合成提示文本。
var synthesis_tip_display: String = ""

## 战斗模式：当前怪物生成概率标签。
var monster_chance_label: String = ""

## 战斗模式：生成池信息标签。
var spawn_info_label: String = ""


# --- 内部统计上下文（供 InteractionRule 读取，不直接渲染到HUD）---

## 当前棋盘上玩家方块的最大数值，由 GamePlay 写入，供规则读取。
var stat_max_player_value: int = 0

## 当前棋盘上所有玩家方块数值的集合（用于快速查找），由 GamePlay 写入，供规则读取。
var stat_player_values_set: Dictionary = {}

## 当前游戏消灭的怪物数量，由 GamePlay 写入，供规则读取。
var stat_monsters_killed: int = 0


# --- 公共方法 ---

## 将此对象中所有非空字段序列化为 Dictionary，供 HUD 的动态渲染逻辑使用。
##
## 字段为空字符串、null 或空数组时将被忽略（不加入结果字典），
## 这与 HUD 原有逻辑中隐藏空数据节点的行为保持一致。
## @return: 一个仅包含有效显示数据的字典。
func to_display_dict() -> Dictionary:
	var result: Dictionary = {}

	_put_string(result, &"step_info", step_info)
	_put_string(result, &"high_score", high_score)
	_put_string(result, &"highest_tile", highest_tile)
	_put_string(result, &"separator", separator)
	_put_string(result, &"description", description)
	_put_string(result, &"controls_title", controls_title)
	_put_string(result, &"controls_move", controls_move)
	_put_string(result, &"controls_actions", controls_actions)
	_put_string(result, &"seed_info", seed_info)
	_put_string(result, &"taint_warning", taint_warning)
	_put_string(result, &"status_message", status_message)
	_put_string(result, &"monsters_killed_display", monsters_killed_display)
	_put_array(result, &"fibonacci_sequence_display", fibonacci_sequence_display)
	_put_array(result, &"fib_sequence_display", fib_sequence_display)
	_put_array(result, &"luc_sequence_display", luc_sequence_display)
	_put_string(result, &"synthesis_tip_display", synthesis_tip_display)
	_put_string(result, &"monster_chance_label", monster_chance_label)
	_put_string(result, &"spawn_info_label", spawn_info_label)

	return result


# --- 私有/辅助方法 ---

func _put_string(dict: Dictionary, key: StringName, value: String) -> void:
	if not value.is_empty():
		dict[key] = value


func _put_array(dict: Dictionary, key: StringName, value: Array) -> void:
	if not value.is_empty():
		dict[key] = value
