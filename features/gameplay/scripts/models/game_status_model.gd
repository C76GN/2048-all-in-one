## GameStatusModel: 负责游戏运行时的状态统计 (分数、步数、击杀数等)。
class_name GameStatusModel
extends "res://addons/gf/kernel/base/gf_model.gd"


# --- 公共变量 ---

## 当前分数
var score: GFBindableProperty = GFBindableProperty.new(0)

## 最高分
var high_score: GFBindableProperty = GFBindableProperty.new(0)

## 最大方块值
var highest_tile: GFBindableProperty = GFBindableProperty.new(0)

## 当前模式的目标方块值；为 0 表示未定义目标。
var target_tile_value: GFBindableProperty = GFBindableProperty.new(0)

## 当前对局是否已经达成目标。
var target_reached: GFBindableProperty = GFBindableProperty.new(false)

## 游戏中的移动总步数。
var move_count: GFBindableProperty = GFBindableProperty.new(0)

## 游戏中击杀的怪物数量。
var monsters_killed: GFBindableProperty = GFBindableProperty.new(0)

## 规则特定的额外统计数据 (Dictionary 或 Array)
var extra_stats: GFBindableProperty = GFBindableProperty.new({})


# --- 公共方法 ---

## 重置一局游戏的运行时统计，并保留传入的历史最高分。
## @param saved_high_score: 当前模式和棋盘尺寸下已保存的最高分。
func reset_for_new_game(saved_high_score: int = 0) -> void:
	score.set_value(0)
	move_count.set_value(0)
	monsters_killed.set_value(0)
	highest_tile.set_value(0)
	target_tile_value.set_value(0)
	target_reached.set_value(false)
	extra_stats.set_value({})
	high_score.set_value(saved_high_score)


## 应用分数变化，并同步局内最高分显示。
## @param amount: 本次增加的分数。
func add_score(amount: int) -> void:
	var current_score: int = GFVariantData.to_int(score.get_value(), 0)
	var current_high_score: int = GFVariantData.to_int(high_score.get_value(), 0)
	var new_score: int = current_score + amount
	score.set_value(new_score)
	if new_score > current_high_score:
		high_score.set_value(new_score)


## 增加有效移动步数。
## @param amount: 要增加的步数。
func increment_move_count(amount: int = 1) -> void:
	var current_move_count: int = GFVariantData.to_int(move_count.get_value(), 0)
	move_count.set_value(current_move_count + max(amount, 0))


## 增加击杀怪物数量。
## @param amount: 要增加的击杀数量。
func increment_monsters_killed(amount: int = 1) -> void:
	var current_monsters_killed: int = GFVariantData.to_int(monsters_killed.get_value(), 0)
	monsters_killed.set_value(current_monsters_killed + max(amount, 0))


## 从棋盘模型同步最高玩家方块。
## @param grid_model: 当前棋盘模型。
func sync_highest_tile_from_grid(grid_model: GridModel) -> void:
	if not is_instance_valid(grid_model):
		return

	highest_tile.set_value(grid_model.get_max_player_value())


## 设置当前对局的目标上下文。
## @param value: 当前模式定义的目标方块值；为 0 表示未定义目标。
## @param reached: 当前状态是否已达成目标。
func set_target_state(value: int, reached: bool = false) -> void:
	var normalized_value: int = max(value, 0)
	target_tile_value.set_value(normalized_value)
	target_reached.set_value(reached if normalized_value > 0 else false)


## 标记当前对局已经达成目标。
func mark_target_reached() -> void:
	if GFVariantData.to_int(target_tile_value.get_value(), 0) <= 0:
		return
	target_reached.set_value(true)
