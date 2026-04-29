## GameStatusModel: 负责游戏运行时的状态统计 (分数、步数、击杀数等)。
class_name GameStatusModel
extends GFModel


# --- 公共变量 ---

## 当前分数
var score: BindableProperty = BindableProperty.new(0)

## 最高分
var high_score: BindableProperty = BindableProperty.new(0)

## 最大方块值
var highest_tile: BindableProperty = BindableProperty.new(0)

## 游戏中的移动总步数。
var move_count: BindableProperty = BindableProperty.new(0)

## 游戏中击杀的怪物数量。
var monsters_killed: BindableProperty = BindableProperty.new(0)

## 顶端状态消息
var status_message: BindableProperty = BindableProperty.new("")

## 规则特定的额外统计数据 (Dictionary 或 Array)
var extra_stats: BindableProperty = BindableProperty.new({})


# --- 公共方法 ---

## 重置一局游戏的运行时统计，并保留传入的历史最高分。
func reset_for_new_game(saved_high_score: int = 0) -> void:
	score.set_value(0)
	move_count.set_value(0)
	monsters_killed.set_value(0)
	highest_tile.set_value(0)
	status_message.set_value("")
	extra_stats.set_value({})
	high_score.set_value(saved_high_score)


## 应用分数变化，并同步局内最高分显示。
func add_score(amount: int) -> void:
	var new_score: int = score.get_value() + amount
	score.set_value(new_score)
	if new_score > high_score.get_value():
		high_score.set_value(new_score)


## 增加有效移动步数。
func increment_move_count(amount: int = 1) -> void:
	move_count.set_value(move_count.get_value() + max(amount, 0))


## 增加击杀怪物数量。
func increment_monsters_killed(amount: int = 1) -> void:
	monsters_killed.set_value(monsters_killed.get_value() + max(amount, 0))


## 从棋盘模型同步最高玩家方块。
func sync_highest_tile_from_grid(grid_model: GridModel) -> void:
	if not is_instance_valid(grid_model):
		return

	highest_tile.set_value(grid_model.get_max_player_value())
