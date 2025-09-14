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
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var timer_label: Label = %Label

# --- 状态变量 ---

# 记录玩家的总移动次数，用于计算时间奖励。
var move_count: int = 0
# 怪物生成计时器对象。
var monster_spawn_timer: Timer


# Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 建立与 GameBoard 信号的连接

	game_board.move_made.connect(_on_game_board_move_made)
	game_board.game_won.connect(_on_game_won)
	game_board.game_lost.connect(_on_game_lost)
	
	# 初始化并启动怪物生成计时器。
	_setup_monster_timer()

# Godot生命周期函数：每帧调用。
func _process(_delta: float) -> void:
	# 此处负责实时更新UI元素，以反映计时器的当前状态。
	if monster_spawn_timer != null and monster_spawn_timer.time_left > 0:
		progress_bar.max_value = monster_spawn_timer.wait_time
		progress_bar.value = monster_spawn_timer.time_left
		timer_label.text = "Spawning monster in: %.1f s" % monster_spawn_timer.time_left

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

## 根据当前玩家方块的最大值，计算新生成怪物的数值。
## 采用加权随机算法，玩家越强，可能出现的怪物也越强，但低级怪物依然占多数。
## @return: 返回一个2的幂次方整数，作为怪物的数值。
func _calculate_monster_value() -> int:
	# 通过调用 GameBoard 的公共接口获取数据，实现良好封装。
	var max_player_value = game_board.get_max_player_value()
	if max_player_value <= 0: return 2
	
	# 计算最大玩家数值是2的多少次幂（k）。
	var k = int(log(max_player_value) / log(2))
	if k < 1: k = 1
	
	# 生成可能的怪物数值列表和对应的权重列表。
	var weights = []
	var possible_values = []
	for i in range(1, k + 1):
		possible_values.append(pow(2, i))
		weights.append(k - i + 1)
		
	# 执行加权随机选择。
	var total_weight = 0
	for w in weights:
		total_weight += w
	
	if total_weight == 0: return 2 # 避免除零错误
	
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

## 当 GameBoard 发出 `game_won` 信号时被调用。
func _on_game_won() -> void:
	timer_label.text = "YOU WIN!"
	# 暂停整个游戏的场景树。
	get_tree().paused = true

## 当 GameBoard 发出 `game_lost` 信号时被调用。
func _on_game_lost() -> void:
	timer_label.text = "GAME OVER!"
	# 暂停整个游戏的场景树。
	get_tree().paused = true
