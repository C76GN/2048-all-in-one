# scripts/modes/lucas_fibonacci_interaction_rule.gd

## LucasFibonacciInteractionRule: 斐波那契与卢卡斯数列结合的交互规则。
##
## 规则定义:
## 1. 斐波那契规则: 两个 '1' 合并成 '2'; 两个相邻斐波那契数合并成它们的和。
## 2. 卢卡斯规则: 两个相邻卢卡斯数合并成它们的和 (例如 1+3=4, 3+4=7)。
## 3. 混合规则: 一个斐波那契数 F(n-1) 和 F(n+1) 可以合并成卢卡斯数 L(n)。
## 4. 配色规则: 斐波那契数使用配色方案0，卢卡斯数使用配色方案1。
class_name LucasFibonacciInteractionRule
extends InteractionRule

# 预先计算并缓存数列，以提高性能。
var _fib_sequence: Array[int] = []
var _luc_sequence: Array[int] = []
# 用于快速查找数值是否在数列中。
var _fib_set: Dictionary = {}
var _luc_set: Dictionary = {}

const MAX_SEQUENCE_VALUE = 65536 # 限制数列生成的大小

func _init():
	_generate_sequences()

## [内部辅助函数] 生成并缓存斐波那契和卢卡斯数列。
func _generate_sequences():
	# 生成斐波那契数列
	_fib_sequence = [1, 2]
	while _fib_sequence[-1] < MAX_SEQUENCE_VALUE:
		_fib_sequence.append(_fib_sequence[-1] + _fib_sequence[-2])
	
	# 生成卢卡斯数列
	_luc_sequence = [2, 1] # L0, L1
	var l_n_minus_2 = 2
	var l_n_minus_1 = 1
	while l_n_minus_1 < MAX_SEQUENCE_VALUE:
		var next_luc = l_n_minus_1 + l_n_minus_2
		if next_luc > MAX_SEQUENCE_VALUE: break
		_luc_sequence.append(next_luc)
		l_n_minus_2 = l_n_minus_1
		l_n_minus_1 = next_luc
		
	# 为了快速查找，将数组转换为字典（作为集合使用）
	for num in _fib_sequence: _fib_set[num] = true
	for num in _luc_sequence: _luc_set[num] = true

## 判断两个方块是否具备可交互性。
func can_interact(tile_a: Tile, tile_b: Tile) -> bool:
	if tile_a == null or tile_b == null:
		return false
	if tile_a.type != Tile.TileType.PLAYER or tile_b.type != Tile.TileType.PLAYER:
		return false
	
	var v1 = tile_a.value
	var v2 = tile_b.value

	# 规则1: 两个 '1' 可以合并成 '2' (斐波那契基础)
	if v1 == 1 and v2 == 1:
		return true

	# 规则2: 斐波那契数列内部合并
	var idx1_fib = _fib_sequence.find(v1)
	var idx2_fib = _fib_sequence.find(v2)
	if idx1_fib != -1 and idx2_fib != -1 and abs(idx1_fib - idx2_fib) == 1:
		return true

	# 规则3: 卢卡斯数列内部合并
	var idx1_luc = _luc_sequence.find(v1)
	var idx2_luc = _luc_sequence.find(v2)
	if idx1_luc != -1 and idx2_luc != -1:
		if _luc_sequence.has(v1 + v2):
			if (idx1_luc > 0 and _luc_sequence[idx1_luc - 1] == v2) or \
			   (idx1_luc < _luc_sequence.size() - 1 and _luc_sequence[idx1_luc + 1] == v2):
				return true

	# 规则4: 混合规则 Ln = Fn-1 + Fn+1
	if idx1_fib != -1 and idx2_fib != -1 and abs(idx1_fib - idx2_fib) == 2:
		return true
		
	return false

## 处理两个方块之间的合并交互。
func process_interaction(tile_a: Tile, tile_b: Tile, p_rule: InteractionRule) -> Dictionary:
	if can_interact(tile_a, tile_b):
		var new_value = tile_a.value + tile_b.value
		tile_b.setup(new_value, tile_a.type, p_rule, tile_a.color_schemes)
		tile_a.queue_free()
		return {"merged_tile": tile_b, "consumed_tile": tile_a, "score": new_value}
	
	return {}

## 根据数值返回其在数列中的等级（索引），用于着色。
func get_level_by_value(value: int) -> int:
	# 优先检查卢卡斯数列，因为有些数是重叠的
	var index = _luc_sequence.find(value)
	if index != -1:
		return index

	index = _fib_sequence.find(value)
	if index != -1:
		return index

	# 如果不是标准数，返回一个高级别的颜色
	return 15

## 根据数值判断应该使用哪个配色方案（0 for Fib, 1 for Luc）。
func get_color_scheme_index(value: int) -> int:
	# 规则：如果一个数只存在于卢卡斯数列中（且不是斐波那契数），则使用卢卡斯配色。
	if value > 3 and _luc_set.has(value) and not _fib_set.has(value):
		return 1
	
	return 0

## 获取用于在HUD上显示的格式化好的上下文数据。
func get_hud_context_data(context: Dictionary = {}) -> Dictionary:
	var max_player_value = context.get("max_player_value", 0)
	var max_display_value = 5 + max_player_value * 2
	var player_tiles_set = context.get("player_values_set", {})
	
	var display_data = {}

	# 查找可合成的提示
	var synthesis_data = {}
	for i in range(1, _fib_sequence.size() - 1):
		var f_n_minus_1 = _fib_sequence[i - 1]
		var f_n_plus_1 = _fib_sequence[i + 1]
		if player_tiles_set.has(f_n_minus_1) and player_tiles_set.has(f_n_plus_1):
			var l_n = f_n_minus_1 + f_n_plus_1
			synthesis_data = {
				"f_minus_1": f_n_minus_1, "f_plus_1": f_n_plus_1, "l_n": l_n
			}
			break

	# 格式化合成提示字符串
	var highlight_fib_components = {}
	var highlight_lucas_set = {}
	if not synthesis_data.is_empty():
		highlight_fib_components[synthesis_data["f_minus_1"]] = true
		highlight_fib_components[synthesis_data["f_plus_1"]] = true
		highlight_lucas_set[synthesis_data["l_n"]] = true
		display_data["synthesis_tip_display"] = "合成提示: [color=cyan]%d[/color] + [color=cyan]%d[/color] = [color=yellow]%d[/color]" % [synthesis_data["f_minus_1"], synthesis_data["f_plus_1"], synthesis_data["l_n"]]

	# 格式化斐波那契序列
	var fib_data_for_ui = [{"text": "斐波那契:", "color": Color.WHITE}]
	for num in _fib_sequence:
		if num > max_display_value: break
		var item = {"text": str(num), "color": Color.GRAY}
		if highlight_fib_components.has(num): item["color"] = Color.CYAN
		elif player_tiles_set.has(num): item["color"] = Color.WHITE
		fib_data_for_ui.append(item)
	display_data["fib_sequence_display"] = fib_data_for_ui
	
	# 格式化卢卡斯序列
	var luc_display_sequence = _luc_sequence.slice(1)
	luc_display_sequence.sort()
	var luc_data_for_ui = [{"text": "卢卡斯:", "color": Color.WHITE}]
	for num in luc_display_sequence:
		if num > max_display_value: break
		var item = {"text": str(num), "color": Color.GRAY}
		if highlight_lucas_set.has(num): item["color"] = Color.YELLOW
		elif player_tiles_set.has(num): item["color"] = Color.WHITE
		luc_data_for_ui.append(item)
	display_data["luc_sequence_display"] = luc_data_for_ui
		
	return display_data

## 获取此规则下所有可生成的方块“类型”。
func get_spawnable_types() -> Dictionary:
	# 在这个模式中，用 0 代表斐波那契，1 代表卢卡斯，这与 get_color_scheme_index 的逻辑一致
	return {
		0: "斐波那契数",
		1: "卢卡斯数"
	}

## 根据指定的类型ID，获取所有可生成的方块“数值”。
func get_spawnable_values(type_id: int) -> Array[int]:
	match type_id:
		0: # 斐波那契数
			return _fib_sequence
		1: # 卢卡斯数
			var luc_display = _luc_sequence.duplicate()
			luc_display.sort()
			return luc_display
	return []

## 重写基类方法，将所有来自测试面板的类型ID都转换为PLAYER类型。
## 在这个模式中，无论是斐波那契数(id=0)还是卢卡斯数(id=1)，它们都属于PLAYER方块。
func get_tile_type_from_id(_type_id: int) -> Tile.TileType:
	return Tile.TileType.PLAYER
