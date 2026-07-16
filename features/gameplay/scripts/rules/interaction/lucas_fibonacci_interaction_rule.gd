## LucasFibonacciInteractionRule: 斐波那契与卢卡斯数列结合的交互规则。
##
## 规则定义:
## 1. 斐波那契规则: 两个 '1' 合并成 '2'; 两个相邻斐波那契数合并成它们的和。
## 2. 卢卡斯规则: 两个相邻卢卡斯数合并成它们的和 (例如 1+3=4, 3+4=7)。
## 3. 混合规则: 一个斐波那契数 F(n-1) 和 F(n+1) 可以合并成卢卡斯数 L(n)。
## 4. 配色规则: 斐波那契数使用配色方案0，卢卡斯数使用配色方案1。
class_name LucasFibonacciInteractionRule
extends InteractionRule


# --- 常量 ---

const _SYNTHESIS_TIP_FORMAT_FALLBACK: String = "合成提示: [color=#2f7674]%d[/color] + [color=#2f7674]%d[/color] = [color=#944431]%d[/color]"
const _HUD_TEXT_COLOR: Color = Color(0.34901962, 0.2901961, 0.27058825, 1.0)
const _HUD_MUTED_COLOR: Color = Color(0.4, 0.35686275, 0.32156864, 1.0)
const _HUD_TEAL_COLOR: Color = Color(0.18431373, 0.4627451, 0.45490196, 1.0)
const _HUD_ACCENT_COLOR: Color = Color(0.5803922, 0.26666668, 0.19215687, 1.0)


# --- 私有变量 ---

var _fib_sequence: Array[int] = []
var _luc_sequence: Array[int] = []
var _fib_set: Dictionary = {}
var _luc_set: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init() -> void:
	_generate_sequences()


# --- 公共方法 ---

## 根据数值返回其在数列中的等级（索引）。
## @param value: 方块数值。
func get_level_by_value(value: int) -> int:
	var index: int = _luc_sequence.find(value)
	if index != -1:
		return index

	index = _fib_sequence.find(value)
	if index != -1:
		return index

	return 15


## 根据数值判断应该使用哪个配色方案。
## @param value: 方块数值。
## @param _definition_id: 方块定义 ID；该数列规则只按数值选择色阶。
func get_color_scheme_index(value: int, _definition_id: StringName) -> int:
	if value > 3 and _luc_set.has(value) and not _fib_set.has(value):
		return 1
	return 0


## 将卢卡斯斯波那契模式相关的HUD显示数据写入传入的 stats 字典。
##
## @param context: 包含当前游戏统计信息的 Dictionary 对象。
## @param stats: 要写入显示数据的 Dictionary 对象。
func get_hud_stats(context: Dictionary, stats: Dictionary) -> void:
	var max_tile_value: int = GFVariantData.to_int(context.get(&"max_tile_value", 0), 0)
	var max_display_value: int = 5 + max_tile_value * 2
	var tile_values_value: Variant = context.get(&"tile_values_set", {})
	var tile_values_set: Dictionary = tile_values_value if tile_values_value is Dictionary else {}

	var synthesis_data: Dictionary = {}

	for i: int in range(1, _fib_sequence.size() - 1):
		var f_n_minus_1: int = _fib_sequence[i - 1]
		var f_n_plus_1: int = _fib_sequence[i + 1]
		if tile_values_set.has(f_n_minus_1) and tile_values_set.has(f_n_plus_1):
			var l_n: int = f_n_minus_1 + f_n_plus_1
			if _luc_set.has(l_n):
				synthesis_data = {&"f_minus_1": f_n_minus_1, &"f_plus_1": f_n_plus_1, &"l_n": l_n}
				break

	var highlight_fib_components: Dictionary = {}
	var highlight_lucas_set: Dictionary = {}
	if not synthesis_data.is_empty():
		highlight_fib_components[synthesis_data[&"f_minus_1"]] = true
		highlight_fib_components[synthesis_data[&"f_plus_1"]] = true
		highlight_lucas_set[synthesis_data[&"l_n"]] = true
		stats[&"synthesis_tip_display"] = GameTextFormatUtility.format_template(
			tr("TIP_SYNTHESIS_FORMAT"),
			_SYNTHESIS_TIP_FORMAT_FALLBACK,
			[
				synthesis_data[&"f_minus_1"],
				synthesis_data[&"f_plus_1"],
				synthesis_data[&"l_n"],
			]
		)

	var fib_data_for_ui: Array[Dictionary] = [{&"text": tr("LABEL_FIB_SEQ"), &"color": _HUD_TEXT_COLOR}]
	for num: int in _fib_sequence:
		if num > max_display_value:
			break
		var item: Dictionary = {&"text": str(num), &"color": _HUD_MUTED_COLOR}
		if highlight_fib_components.has(num):
			item[&"color"] = _HUD_TEAL_COLOR
		elif tile_values_set.has(num):
			item[&"color"] = _HUD_TEXT_COLOR
		fib_data_for_ui.append(item)
	stats[&"fibonacci_sequence_display"] = fib_data_for_ui

	var luc_display_sequence: Array[int] = _luc_sequence.slice(1)
	luc_display_sequence.sort()
	var luc_data_for_ui: Array[Dictionary] = [{&"text": tr("LABEL_LUC_SEQ"), &"color": _HUD_TEXT_COLOR}]
	for num: int in luc_display_sequence:
		if num > max_display_value:
			break
		var item: Dictionary = {&"text": str(num), &"color": _HUD_MUTED_COLOR}
		if highlight_lucas_set.has(num):
			item[&"color"] = _HUD_ACCENT_COLOR
		elif tile_values_set.has(num):
			item[&"color"] = _HUD_TEXT_COLOR
		luc_data_for_ui.append(item)
	stats[&"lucas_sequence_display"] = luc_data_for_ui


## 获取诊断工具可选择的数列生成选项。
func get_spawnable_options() -> Dictionary:
	return {
		0: tr("RULE_FIBONACCI"),
		1: tr("RULE_LUCAS")
	}


## 根据生成选项 ID 获取可生成数值。
## @param option_id: 测试面板传入的生成选项 ID。
func get_spawnable_values(option_id: int) -> Array[int]:
	match option_id:
		0: return _fib_sequence
		1:
			var luc_display: Array[int] = _luc_sequence.duplicate()
			luc_display.sort()
			return luc_display
	return []


## 两个数列选项都使用同一个复合方块定义。
## @param _option_id: UI 传入的局部生成选项 ID。
func get_spawn_definition(_option_id: int) -> TileDefinition:
	return get_default_tile_definition()


# --- 私有/辅助方法 ---

## 生成并缓存数列内容。
func _generate_sequences() -> void:
	_fib_sequence = SequenceMath.generate_fibonacci()
	_luc_sequence = SequenceMath.generate_lucas()

	for num: int in _fib_sequence:
		_fib_set[num] = true
	for num: int in _luc_sequence:
		_luc_set[num] = true
