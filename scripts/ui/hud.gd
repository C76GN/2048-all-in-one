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

## 统一更新所有UI显示。
## 从外部接收一个包含所有需要显示数据的字典，并更新UI。
func update_display(display_data: Dictionary) -> void:
	move_count_label.text = "移动次数: %d" % display_data.get("move_count", 0)
	killed_count_label.text = "消灭怪物: %d" % display_data.get("monsters_killed", 0)
	
	# 从规则中获取的动态数据
	monster_timer_label.text = display_data.get("timer_label", "")
	time_bonus_label.text = display_data.get("bonus_label", "")
	monster_spawn_label.text = display_data.get("spawn_info_label", "")
