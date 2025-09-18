# scripts/main.gd

# 该脚本是游戏的主控制器（或称为“协调者”）。
# 它负责处理全局的游戏逻辑，包括：
# 1. 监听和处理玩家的输入。
# 2. 管理怪物生成计时器和相关的UI显示。
# 3. 接收来自 GameBoard 的信号，并据此更新游戏状态（如增加时间、处理胜负）。
# 4. 控制游戏的暂停与恢复。
extends Control

# --- 常量配置 ---

# 怪物生成的初始倒计时长（秒）。
const INITIAL_SPAWN_INTERVAL: float = 10.0
# 每次移动后奖励的最小时间（秒）。
const MIN_TIME_BONUS: float = 0.5
# 时间奖励衰减因子。移动次数越多，每次奖励的时间会变少。
const TIME_BONUS_DECAY_FACTOR: float = 5.0

# --- 节点引用 ---

# 使用唯一名称(%)获取节点引用
@onready var game_board = %GameBoard
@onready var monster_timer_label: Label = %MonsterTimerLabel
@onready var move_count_label: Label = %MoveCountLabel
@onready var killed_count_label: Label = %KilledCountLabel
@onready var time_bonus_label: Label = %TimeBonusLabel
@onready var monster_spawn_label: Label = %MonsterSpawnLabel
@onready var test_panel: VBoxContainer = $MarginContainer/MainLayoutContainer/RightPanel/TestPanel
@onready var pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var value_option_button: OptionButton = %ValueOptionButton
@onready var type_option_button: OptionButton = %TypeOptionButton
@onready var spawn_button: Button = %SpawnButton

# --- 状态变量 ---

# 记录玩家的总移动次数，用于计算时间奖励。
var move_count: int = 0
var monsters_killed: int = 0
# 怪物生成计时器对象。
var monster_spawn_timer: Timer

# Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 建立与 GameBoard 信号的连接
	game_board.move_made.connect(_on_game_board_move_made)
	game_board.game_lost.connect(_on_game_lost)
	game_board.monster_killed.connect(_on_monster_killed)
	
	# 初始化并启动怪物生成计时器。
	_setup_monster_timer()
	# 根据环境显示测试工具
	_initialize_test_tools() 
	# 游戏开始时，初始化一次所有UI显示
	_update_stats_display()

# Godot生命周期函数：每帧调用。
func _process(_delta: float) -> void:
	# 此处负责实时更新UI元素，以反映计时器的当前状态。
	if monster_spawn_timer != null and monster_spawn_timer.time_left > 0:
		monster_timer_label.text = "怪物将在: %.1f s后出现" % monster_spawn_timer.time_left

# Godot输入处理函数：当有未被处理的输入事件时调用。
func _unhandled_input(event: InputEvent) -> void:
	# 如果游戏已暂停（例如胜利或失败后），则忽略所有输入。
	if get_tree().paused:
		return

	# 将 "move_*" 输入动作映射为方向向量。
	var direction = Vector2i.ZERO
	if event.is_action_pressed("move_up"): direction = Vector2i.UP
	elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
	elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
	elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT
	
	# 如果捕获到了有效的移动方向...
	if direction != Vector2i.ZERO:
		# ...则通知 GameBoard 节点去处理这个移动。
		# Main.gd 不关心移动的具体逻辑，只负责分派指令。
		game_board.handle_move(direction)

# 初始化测试工具的函数
func _initialize_test_tools() -> void:
	# 只有在Godot编辑器环境中运行时，才显示测试面板并连接信号
	if OS.has_feature("editor"):
		test_panel.visible = true
		spawn_button.pressed.connect(_on_spawn_button_pressed)
		# 动态填充数值下拉列表
		var current_power_of_two = 2
		
		while current_power_of_two <= 65536:
			value_option_button.add_item(str(current_power_of_two))
			current_power_of_two *= 2
	else:
		# 在导出后的游戏中，隐藏测试面板
		test_panel.visible = false

# 当“生成方块”按钮被点击时调用的函数
func _on_spawn_button_pressed() -> void:
	# 从UI控件获取所有输入值
	var pos = Vector2i(int(pos_x_spinbox.value), int(pos_y_spinbox.value))
	# 从下拉列表中获取选中的文本，并转换为整数
	var value_text = value_option_button.get_item_text(value_option_button.selected)
	var value = int(value_text)
	var type_index = type_option_button.selected
	var type = Tile.TileType.PLAYER if type_index == 0 else Tile.TileType.MONSTER
	
	# 调用 game_board 的新函数来生成方块
	game_board.spawn_specific_tile(pos, value, type)

# --- 怪物生成逻辑 ---

## 创建、配置并启动怪物生成的计时器。
func _setup_monster_timer() -> void:
	monster_spawn_timer = Timer.new()
	monster_spawn_timer.wait_time = INITIAL_SPAWN_INTERVAL
	# 当计时器时间到，连接到 _on_monster_timer_timeout 方法。
	monster_spawn_timer.timeout.connect(_on_monster_timer_timeout)
	add_child(monster_spawn_timer)
	monster_spawn_timer.start()

## 计时器倒计时结束时调用的函数。
func _on_monster_timer_timeout() -> void:
	# 计算新生成怪物的数值。
	var monster_value = _calculate_monster_value()
	# 指示 GameBoard 在棋盘上生成这个怪物。
	game_board.spawn_monster(monster_value)
	# 重置并重启计时器
	monster_spawn_timer.start(INITIAL_SPAWN_INTERVAL)

## 使用加权随机算法，从怪物生成池中选择一个最终的怪物数值。
## @return: 返回一个2的幂次方整数，作为怪物的数值。
func _calculate_monster_value() -> int:
	# 调用辅助函数获取可能的数值和对应的权重。
	var spawn_pool = _get_monster_spawn_pool()
	var possible_values = spawn_pool["values"]
	var weights = spawn_pool["weights"]

	if possible_values.is_empty(): return 2

	# 计算总权重。
	var total_weight = 0
	for w in weights:
		total_weight += w
	if total_weight == 0: return 2

	# 执行加权随机选择。
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var random_pick = rng.randi_range(1, total_weight)
	
	var cumulative_weight = 0
	for i in range(weights.size()):
		cumulative_weight += weights[i]
		if random_pick <= cumulative_weight:
			return possible_values[i]
			
	return 2 # 作为保底返回值。

# --- 信号处理函数 ---
# 这些函数响应来自 GameBoard 的信号。

## 当 GameBoard 发出 `move_made` 信号时被调用。
func _on_game_board_move_made() -> void:
	# 玩家每成功移动一步，就获得时间奖励。
	move_count += 1
	# 奖励的时间会随着移动次数的增加而衰减，增加游戏挑战性。
	var time_to_add = MIN_TIME_BONUS + TIME_BONUS_DECAY_FACTOR / move_count
	# 在计时器剩余时间的基础上增加奖励时间，并重新启动。
	monster_spawn_timer.start(monster_spawn_timer.time_left + time_to_add)
	# 移动成功后，刷新整个UI面板
	_update_stats_display()

## 当 GameBoard 发出 `game_lost` 信号时被调用。
func _on_game_lost() -> void:
	monster_timer_label.text = "游戏结束!"
	# 暂停整个游戏的场景树。
	get_tree().paused = true

func _on_monster_killed() -> void:
	monsters_killed += 1

# --- UI 更新 ---

## 统一更新左侧所有数据标签的显示内容。
func _update_stats_display() -> void:
	# 更新移动次数
	move_count_label.text = "移动次数: %d" % move_count
	# 更新消灭怪物数量
	killed_count_label.text = "消灭怪物: %d" % monsters_killed
	# 更新下一次移动奖励时间
	# “下次移动”的计数应该是当前的移动次数加一
	var next_move_count = move_count + 1
	var next_move_bonus = MIN_TIME_BONUS + TIME_BONUS_DECAY_FACTOR / next_move_count
	time_bonus_label.text = "下次移动奖励: +%.2f s" % next_move_bonus
	# 更新怪物生成概率
	var spawn_info_text = "怪物生成概率:\n"
	var spawn_pool = _get_monster_spawn_pool()
	var possible_values = spawn_pool["values"]
	var weights = spawn_pool["weights"]
	
	var total_weight = 0
	for w in weights:
		total_weight += w

	if total_weight > 0:
		for i in range(weights.size()):
			var percentage = (float(weights[i]) / total_weight) * 100
			spawn_info_text += "  - %d: %.1f%%\n" % [possible_values[i], percentage]
	else:
		spawn_info_text += "  - 2: 100%"
		
	monster_spawn_label.text = spawn_info_text

## [注释优化] 辅助函数，根据当前玩家最大方块值，计算出所有可能的怪物数值及其权重。
## 玩家分数越高，高数值怪物的权重也越高。
## @return: 返回一个包含 "values" (Array[int]) 和 "weights" (Array[int]) 的字典。
func _get_monster_spawn_pool() -> Dictionary:
	var max_player_value = game_board.get_max_player_value()
	if max_player_value <= 0:
		return {"values": [2], "weights": [1]}
	# 计算最大玩家数值是2的多少次幂（k）。
	var k = int(log(max_player_value) / log(2))
	if k < 1: k = 1
	
	# 生成可能的怪物数值列表和对应的权重列表。
	var weights = []
	var possible_values = []
	for i in range(1, k + 1):
		possible_values.append(pow(2, i))
		weights.append(k - i + 1) # 数值越小，权重越高
	
	return {"values": possible_values, "weights": weights}
