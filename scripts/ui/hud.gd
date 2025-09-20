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
## @param stats: 包含游戏统计数据的字典。
func update_stats(stats: Dictionary) -> void:
	# 直接从字典中获取并显示移动次数和消灭怪物数。
	move_count_label.text = "移动次数: %d" % stats.get("move_count", 0)
	killed_count_label.text = "消灭怪物: %d" % stats.get("monsters_killed", 0)
	
	# --- 计算并显示下一次移动的时间奖励 ---
	# 这个计算在HUD脚本中完成，因为它只与显示格式相关。
	var next_move_count = stats.get("move_count", 0) + 1
	var time_bonus_decay = stats.get("time_bonus_decay", 5.0)
	var min_time_bonus = stats.get("min_time_bonus", 0.5)
	# 根据公式计算下一次移动将获得的奖励时间。
	var next_move_bonus = min_time_bonus + time_bonus_decay / next_move_count
	time_bonus_label.text = "下次移动奖励: +%.2f s" % next_move_bonus
	
	# 显示格式化后的怪物生成概率信息。
	monster_spawn_label.text = stats.get("monster_spawn_info", "怪物生成概率:\n  - 2: 100%")

## 单独更新怪物生成倒计时。
##
## 之所以独立成一个函数，是因为计时器需要每帧高频更新，
## 而其他统计数据仅在移动后更新一次即可，这样可以提高效率。
## @param time_left: 计时器剩余的秒数。
func update_timer(time_left: float) -> void:
	monster_timer_label.text = "怪物将在: %.1f s后出现" % time_left
