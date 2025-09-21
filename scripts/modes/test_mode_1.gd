# scripts/modes/test_mode_1.gd

## TestMode1: "测试模式1"的游戏逻辑控制器。
##
## 该脚本作为此模式的主场景脚本，负责协调游戏的所有核心部分。它监听玩家输入，
## 管理游戏的核心流程（如暂停、重启），处理本模式特有的怪物生成和时间奖励机制，
## 并作为 `GameBoard` (模型) 与 `HUD`、`PauseMenu` 等UI视图 (视图) 之间的桥梁。
class_name TestMode1
extends Control

# --- 常量配置 ---

# 怪物生成的初始倒计时长（秒）。
const INITIAL_SPAWN_INTERVAL: float = 10.0
# 每次有效移动后奖励的最小时间（秒）。
const MIN_TIME_BONUS: float = 0.5
# 时间奖励衰减因子。移动次数越多，每次奖励的时间会越少。
const TIME_BONUS_DECAY_FACTOR: float = 5.0

# --- 节点引用 ---

## 对场景中核心节点的引用（使用唯一名称%）。
@onready var game_board: Control = %GameBoard
@onready var test_panel: VBoxContainer = %TestPanel
@onready var hud: VBoxContainer = %HUD
@onready var pause_menu = $PauseMenu
@onready var game_over_menu = $GameOverMenu

# --- 状态变量 ---

# 记录玩家的总移动次数，用于计算时间奖励的衰减。
var move_count: int = 0
# 记录被消灭的怪物总数。
var monsters_killed: int = 0
# 管理怪物生成倒计时的 Timer 节点实例。
var monster_spawn_timer: Timer
# 标记游戏是否已结束，用于停止输入和计时器等。
var is_game_over: bool = false

## Godot生命周期函数：当节点进入场景树时调用，用于初始化。
func _ready() -> void:
	# 步骤1: 连接来自核心组件的信号。
	game_board.move_made.connect(_on_game_board_move_made)
	game_board.game_lost.connect(_on_game_lost)
	game_board.monster_killed.connect(_on_monster_killed)
	pause_menu.resume_game.connect(_on_resume_game)
	pause_menu.restart_game.connect(_on_restart_game)
	pause_menu.return_to_main_menu.connect(_on_return_to_main_menu)
	game_over_menu.restart_game.connect(_on_restart_game)
	game_over_menu.return_to_main_menu.connect(_on_return_to_main_menu)
	game_board.board_resized.connect(_on_board_resized)
	
	# 步骤2: 初始化并启动游戏核心机制。
	_setup_monster_timer()
	_initialize_test_tools()
	
	# 步骤3: 在游戏开始时，初始化一次所有UI显示。
	_update_stats_display()

## Godot生命周期函数：每帧调用。
## 在此处专门处理需要高频更新的UI元素。
func _process(_delta: float) -> void:
	# 为提高性能，仅在游戏未结束且计时器运行时，才更新HUD上的倒计时显示。
	if monster_spawn_timer != null and monster_spawn_timer.time_left > 0 and not is_game_over:
		hud.update_timer(monster_spawn_timer.time_left)

## Godot输入处理函数：捕获未被UI消耗的输入事件。
## 优先处理暂停输入，在游戏运行时处理玩家的移动输入。
func _unhandled_input(event: InputEvent) -> void:
	# 处理暂停输入
	if event.is_action_pressed("ui_pause") and not is_game_over:
		_toggle_pause_menu()
		# 标记事件已处理，防止移动输入在同一帧触发
		get_viewport().set_input_as_handled()
		return
	
	# 游戏结束或暂停时，忽略所有游戏输入。
	if get_tree().paused or is_game_over:
		return

	# 将 "move_*" 输入动作映射为方向向量。
	var direction = Vector2i.ZERO
	if event.is_action_pressed("move_up"): direction = Vector2i.UP
	elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
	elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
	elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT
	
	# 如果捕获到了有效的移动方向，则委托 GameBoard 处理。
	# TestMode1 本身不关心移动的具体逻辑，只负责分派指令。
	if direction != Vector2i.ZERO:
		game_board.handle_move(direction)

# --- 暂停菜单逻辑 ---

## 切换游戏的暂停状态和暂停菜单的可见性。
func _toggle_pause_menu() -> void:
	# 切换游戏树的暂停状态
	get_tree().paused = not get_tree().paused
	# 切换暂停菜单的可见性
	pause_menu.toggle()

## 初始化测试工具。
## 该工具仅在Godot编辑器环境中可见并启用。
func _initialize_test_tools() -> void:
	# `OS.has_feature("editor")` 是判断当前是否在编辑器中运行的标准方法。
	if OS.has_feature("editor"):
		test_panel.visible = true
		test_panel.spawn_requested.connect(_on_test_panel_spawn_requested)
		test_panel.reset_and_resize_requested.connect(_on_reset_and_resize_requested)
		test_panel.live_expand_requested.connect(_on_live_expand_requested)
	else:
		# 在导出的游戏中，自动隐藏测试面板。
		test_panel.visible = false

# --- 怪物生成逻辑 ---

## 创建、配置并启动怪物生成的计时器。
func _setup_monster_timer() -> void:
	monster_spawn_timer = Timer.new()
	monster_spawn_timer.wait_time = INITIAL_SPAWN_INTERVAL
	monster_spawn_timer.timeout.connect(_on_monster_timer_timeout)
	add_child(monster_spawn_timer)
	monster_spawn_timer.start()

## 怪物生成计时器倒计时结束时调用的函数。
func _on_monster_timer_timeout() -> void:
	var monster_value = _calculate_monster_value()
	game_board.spawn_monster(monster_value)
	_update_stats_display()
	# 重置并重启计时器，开始新一轮倒计时。
	monster_spawn_timer.start(INITIAL_SPAWN_INTERVAL)

## 使用加权随机算法，从怪物生成池中选择一个最终的怪物数值。
##
## @return: 返回一个2的幂次方整数，作为新生成怪物的数值。
func _calculate_monster_value() -> int:
	# 获取基于当前游戏状态的怪物数值池和权重。
	var spawn_pool = _get_monster_spawn_pool()
	var possible_values = spawn_pool["values"]
	var weights = spawn_pool["weights"]

	if possible_values.is_empty(): return 2

	# 计算总权重，用于随机数范围。
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
			
	return 2 # 作为保底返回值，防止意外情况。

# --- 信号处理函数 ---

## 当 GameBoard 发出 `move_made` 信号时被调用。
## 负责处理移动成功后的逻辑：增加时间奖励并更新UI。
func _on_game_board_move_made() -> void:
	move_count += 1
	# 奖励的时间会随着移动次数的增加而衰减，以增加游戏挑战性。
	var time_to_add = MIN_TIME_BONUS + TIME_BONUS_DECAY_FACTOR / move_count
	# 在计时器剩余时间的基础上增加奖励时间，并以此为新时长重启计时器。
	monster_spawn_timer.start(monster_spawn_timer.time_left + time_to_add)
	# 移动成功后，刷新整个UI面板。
	_update_stats_display()

## 当 GameBoard 发出 `game_lost` 信号时被调用。
## 负责处理游戏失败状态，停止计时器并显示游戏结束菜单。
func _on_game_lost() -> void:
	is_game_over = true
	monster_spawn_timer.stop() # 停止怪物计时器
	# 显示游戏结束菜单
	game_over_menu.open()

## 当 GameBoard 发出 `monster_killed` 信号时被调用。
func _on_monster_killed() -> void:
	monsters_killed += 1
	_update_stats_display()

## 当 TestPanel 发出 `spawn_requested` 信号时被调用。
func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_index: int) -> void:
	# 将从UI接收到的整数索引转换为实际的 TileType 枚举。
	var type = Tile.TileType.PLAYER if type_index == 0 else Tile.TileType.MONSTER
	
	# 委托 GameBoard 在指定位置生成方块。
	game_board.spawn_specific_tile(grid_pos, value, type)
	
	# 操作完成后更新统计信息。
	_update_stats_display()

## 当TestPanel请求重置并调整大小时调用。
func _on_reset_and_resize_requested(new_size: int) -> void:
	# 这是一个完整的游戏重置
	is_game_over = false
	move_count = 0
	monsters_killed = 0
	
	# 调用GameBoard的重置函数
	game_board.reset_and_resize(new_size)
	
	# 重启计时器和UI
	monster_spawn_timer.start(INITIAL_SPAWN_INTERVAL)
	_update_stats_display()
	game_over_menu.close()

## 当TestPanel请求在游戏中扩建时调用。
func _on_live_expand_requested(new_size: int) -> void:
	# 仅在游戏未结束且未暂停时允许扩建
	if not is_game_over and not get_tree().paused:
		game_board.live_expand(new_size)

# --- 菜单信号处理 ---

## 响应 PauseMenu 发出的 `resume_game` 信号。
func _on_resume_game() -> void:
	# 调用切换函数来取消暂停和隐藏菜单
	_toggle_pause_menu()

## 响应 PauseMenu 或 GameOverMenu 发出的 `restart_game` 信号。
func _on_restart_game() -> void:
	# 在切换场景前，务必取消暂停状态
	get_tree().paused = false
	# 重新加载当前场景以实现重启
	get_tree().reload_current_scene()

## 响应 PauseMenu 或 GameOverMenu 发出的 `return_to_main_menu` 信号。
func _on_return_to_main_menu() -> void:
	# 同样，在切换场景前取消暂停
	get_tree().paused = false
	GlobalGameManager.goto_scene("res://scenes/main_menu.tscn")

# --- 棋盘信号处理 ---

## 当 GameBoard 发出 `board_resized` 信号时被调用。
func _on_board_resized(new_size: int) -> void:
	# 将尺寸变化通知给测试面板，让它更新UI
	if OS.has_feature("editor") and test_panel:
		test_panel.update_coordinate_limits(new_size)

# --- UI 更新 ---

## 统一更新UI显示。
## 将所有当前的游戏状态数据打包，并调用 HUD 的方法来更新显示。
func _update_stats_display() -> void:
	# 准备一个包含所有需要显示的数据的字典。
	var stats = {
		"move_count": move_count,
		"monsters_killed": monsters_killed,
		"monster_spawn_info": _get_monster_spawn_info_text(),
		"time_bonus_decay": TIME_BONUS_DECAY_FACTOR,
		"min_time_bonus": MIN_TIME_BONUS
	}
	# 将数据字典传递给 HUD 进行显示。
	hud.update_stats(stats)

## [辅助函数] 生成用于显示的怪物生成概率文本。
func _get_monster_spawn_info_text() -> String:
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
	
	return spawn_info_text

## [辅助函数] 根据当前玩家最大方块值，计算出所有可能的怪物数值及其权重。
## 逻辑：玩家分数越高，高数值怪物的出现权重也越高。
##
## @return: 返回一个包含 "values" (Array[int]) 和 "weights" (Array[int]) 的字典。
func _get_monster_spawn_pool() -> Dictionary:
	var max_player_value = game_board.get_max_player_value()
	if max_player_value <= 0:
		return {"values": [2], "weights": [1]}
		
	# 计算最大玩家数值是2的多少次幂（k），作为难度因子。
	var k = int(log(max_player_value) / log(2))
	if k < 1: k = 1
	
	# 生成可能的怪物数值列表和对应的权重列表。
	var weights = []
	var possible_values = []
	for i in range(1, k + 1):
		possible_values.append(pow(2, i))
		# 权重与数值成反比：数值越小，权重越高。
		weights.append(k - i + 1)
	
	return {"values": possible_values, "weights": weights}
