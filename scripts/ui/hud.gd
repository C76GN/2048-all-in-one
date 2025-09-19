# scripts/ui/hud.gd

extends VBoxContainer

# --- 节点引用 ---
# HUD 场景内部的子节点
@onready var move_count_label: Label = $MoveCountLabel
@onready var monster_spawn_label: Label = $MonsterSpawnLabel
@onready var time_bonus_label: Label = $TimeBonusLabel
@onready var killed_count_label: Label = $KilledCountLabel
@onready var monster_timer_label: Label = $MonsterTimerLabel


# --- 公共接口 ---

## 一个统一的更新函数，从外部接收所有需要显示的数据。
## 使用字典传递数据可以方便未来扩展，而不用改变函数签名。
func update_stats(stats: Dictionary) -> void:
	move_count_label.text = "移动次数: %d" % stats.get("move_count", 0)
	killed_count_label.text = "消灭怪物: %d" % stats.get("monsters_killed", 0)
	
	var next_move_count = stats.get("move_count", 0) + 1
	var time_bonus_decay = stats.get("time_bonus_decay", 5.0)
	var min_time_bonus = stats.get("min_time_bonus", 0.5)
	var next_move_bonus = min_time_bonus + time_bonus_decay / next_move_count
	time_bonus_label.text = "下次移动奖励: +%.2f s" % next_move_bonus
	
	monster_spawn_label.text = stats.get("monster_spawn_info", "怪物生成概率:\n  - 2: 100%")

## 单独提供一个更新计时器的方法，因为它需要高频更新。
func update_timer(time_left: float) -> void:
	monster_timer_label.text = "怪物将在: %.1f s后出现" % time_left

## 显示游戏结束信息。
func show_game_over() -> void:
	monster_timer_label.text = "游戏结束!"
