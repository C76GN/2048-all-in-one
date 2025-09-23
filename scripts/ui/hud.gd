# scripts/ui/hud.gd

## HUD: 游戏界面的平视显示器（Heads-Up Display）。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它本身不包含任何游戏逻辑，只作为游戏状态的一个被动视图。
extends VBoxContainer

# --- 节点引用 ---

## 对HUD场景内部各个Label节点的引用（使用唯一名称%）。
@onready var move_count_label: Label = %MoveCountLabel
@onready var monster_spawn_label: Label = %MonsterSpawnLabel
@onready var time_bonus_label: Label = %TimeBonusLabel
@onready var killed_count_label: Label = %KilledCountLabel
@onready var monster_timer_label: Label = %MonsterTimerLabel

# --- 公共接口 ---

## 统一更新所有静态游戏统计信息。
##
## 从外部接收一个包含所有需要显示数据的字典，并更新UI。
## 使用字典作为参数可以方便未来扩展，而无需改变函数签名。
func update_stats(stats: Dictionary) -> void:
	move_count_label.text = "移动次数: %d" % stats.get("move_count", 0)
	killed_count_label.text = "消灭怪物: %d" % stats.get("monsters_killed", 0)
	
	var next_move_bonus = stats.get("next_move_bonus", 0.0)
	if next_move_bonus > 0.0:
		time_bonus_label.text = "下次移动奖励: +%.2f s" % next_move_bonus
	else:
		time_bonus_label.text = "" # 如果没有奖励，则不显示
	
	monster_spawn_label.text = stats.get("monster_spawn_info", "")

## 单独更新怪物生成倒计时。
##
## 之所以独立成一个函数，是因为计时器需要每帧高频更新，
## 而其他统计数据仅在移动后更新一次即可，这样可以提高效率。
func update_timer(time_left: float) -> void:
	if time_left > 0.0:
		monster_timer_label.text = "怪物将在: %.1f s后出现" % time_left
	else:
		monster_timer_label.text = ""
