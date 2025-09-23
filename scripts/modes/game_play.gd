# scripts/modes/game_play.gd

## GamePlay: 通用的游戏逻辑控制器。
##
## 作为主游戏场景的脚本，它不包含任何具体的游戏规则。
## 它负责加载一个 GameModeConfig 资源，并根据该配置来设置 GameBoard 和其他组件。
## 它充当了规则模型（Rules）、棋盘模型（GameBoard）和UI视图（HUD）之间的协调者。
class_name GamePlay
extends Control

# --- 节点引用 ---
@onready var game_board: Control = %GameBoard
@onready var test_panel: VBoxContainer = %TestPanel
@onready var hud: VBoxContainer = %HUD
@onready var pause_menu = $PauseMenu
@onready var game_over_menu = $GameOverMenu

# --- 状态变量 ---
var mode_config: GameModeConfig # 当前加载的游戏模式配置资源。
var interaction_rule: InteractionRule # 当前模式下，方块交互的具体规则实例。
var spawn_rules: Array[SpawnRule] = [] # 管理所有方块生成规则的数组，允许一个模式同时拥有多种生成逻辑。
var monsters_killed: int = 0 # 记录已消灭的怪物数量。
var is_game_over: bool = false # 标记游戏是否已结束。

## Godot生命周期函数：在节点进入场景树时被调用，负责整个游戏场景的初始化。
func _ready() -> void:
	# 步骤1: 从 GlobalGameManager 加载所选的游戏模式配置。
	if "selected_mode_config_path" in GlobalGameManager and GlobalGameManager.selected_mode_config_path != "":
		var config_path = GlobalGameManager.selected_mode_config_path
		mode_config = load(config_path)
		assert(is_instance_valid(mode_config), "GameModeConfig未能加载！路径: " + config_path)
	else:
		push_error("错误: 没有找到 selected_mode_config_path。无法加载游戏模式。")
		get_tree().quit()
		return
		
	# 步骤2: 根据配置实例化所有规则（交互、游戏结束、生成）。
	assert(is_instance_valid(mode_config.interaction_rule), "InteractionRule未在配置文件中设置！")
	interaction_rule = mode_config.interaction_rule.duplicate()
	var game_over_rule = mode_config.game_over_rule.duplicate()
	
	if mode_config.spawn_rule_scripts.is_empty():
		push_warning("警告: GameModeConfig 中没有提供任何 Spawn Rule 脚本。")
	else:
		for rule_script in mode_config.spawn_rule_scripts:
			if rule_script and rule_script is Script:
				var new_rule: SpawnRule = rule_script.new()
				spawn_rules.append(new_rule) # 添加到管理列表
				add_child(new_rule)          # 将规则节点添加到场景树
				if new_rule.has_method("setup"):
					new_rule.setup(game_board)
			else:
				push_error("错误: spawn_rule_scripts 数组中包含无效项。")
				get_tree().quit()
				return
		
	# 步骤3: 将实例化好的规则注入 GameBoard。
	game_board.set_rules(interaction_rule, game_over_rule)

	# 步骤4: 集中连接所有必要的信号。
	_connect_signals()
	
	# 步骤5: 由指定的生成规则负责初始化棋盘状态。
	var board_initialized = false
	for rule in spawn_rules:
		if rule.has_method("initialize_board"):
			rule.initialize_board()
			board_initialized = true
			break # 通常只有一个规则负责初始化
	
	# 如果没有任何规则负责初始化，则提供一个默认的开始状态。
	if not board_initialized:
		game_board.spawn_tile({"value": 2, "type": Tile.TileType.PLAYER})
		game_board.spawn_tile({"value": 2, "type": Tile.TileType.PLAYER})

	# 步骤6: 初始化UI和仅在编辑器中使用的测试工具。
	_initialize_test_tools()
	_update_stats_display()

## Godot生命周期函数：每帧调用。用于处理需要高频更新的逻辑，例如UI倒计时。
func _process(_delta: float) -> void:
	for rule in spawn_rules:
		if rule is TimedMonsterSpawnRule and not is_game_over:
			hud.update_timer(rule.get_time_left())

## 处理全局未捕获的输入事件，主要用于玩家移动和打开暂停菜单。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause") and not is_game_over:
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return
	
	if get_tree().paused or is_game_over: return

	var direction = Vector2i.ZERO
	if event.is_action_pressed("move_up"): direction = Vector2i.UP
	elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
	elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
	elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT
	
	if direction != Vector2i.ZERO:
		game_board.handle_move(direction)

## [内部函数] 集中管理所有节点和规则的信号连接。
func _connect_signals() -> void:
	# 连接来自核心组件的信号
	game_board.move_made.connect(_on_game_board_move_made)
	game_board.game_lost.connect(_on_game_lost)
	game_board.board_resized.connect(_on_board_resized)
	
	# 连接来自UI菜单的信号
	pause_menu.resume_game.connect(_on_resume_game)
	pause_menu.restart_game.connect(_on_restart_game)
	pause_menu.return_to_main_menu.connect(_on_return_to_main_menu)
	game_over_menu.restart_game.connect(_on_restart_game)
	game_over_menu.return_to_main_menu.connect(_on_return_to_main_menu)
	
	# 连接来自规则的信号
	if interaction_rule:
		interaction_rule.monster_killed.connect(_on_monster_killed)
	for rule in spawn_rules:
		rule.spawn_tile_requested.connect(_on_spawn_tile_requested)

# --- 信号处理函数 ---

## 当 GameBoard 发出 move_made 信号时调用。将此事件广播给所有生成规则。
func _on_game_board_move_made() -> void:
	for rule in spawn_rules:
		if rule.has_method("on_move_made"):
			rule.on_move_made()
	_update_stats_display()

## 当任意 SpawnRule 请求生成方块时调用。
func _on_spawn_tile_requested(spawn_data: Dictionary) -> void:
	game_board.spawn_tile(spawn_data)
	_update_stats_display()

## 当 GameBoard 发出 game_lost 信号时调用。处理游戏失败逻辑。
func _on_game_lost() -> void:
	is_game_over = true
	# 通知所有规则游戏结束，以便它们停止内部逻辑（如计时器）。
	for rule in spawn_rules:
		if rule.has_method("stop_timer"):
			rule.stop_timer()
	game_over_menu.open()

## 当 InteractionRule 报告有怪物被消灭时调用。
func _on_monster_killed() -> void:
	monsters_killed += 1
	_update_stats_display()

## 当棋盘大小改变时，更新测试面板的坐标限制。
func _on_board_resized(new_size: int):
	if OS.has_feature("editor") and test_panel:
		test_panel.update_coordinate_limits(new_size)

# --- UI 更新 & 菜单逻辑 ---

## [内部函数] 聚合所有规则和状态的数据，并更新HUD显示。
func _update_stats_display() -> void:
	var spawn_info_text = ""
	var next_move_bonus = 0.0
	var total_move_count = 0
	
	# 从所有规则中聚合需要显示的数据
	for rule in spawn_rules:
		if "move_count" in rule:
			total_move_count += rule.get("move_count")
		if rule is TimedMonsterSpawnRule:
			var pool = rule.get_monster_spawn_pool()
			spawn_info_text += "怪物生成概率:\n"
			var total_weight = 0
			for w in pool["weights"]: total_weight += w
			if total_weight > 0:
				for i in range(pool["weights"].size()):
					var p = (float(pool["weights"][i]) / total_weight) * 100
					spawn_info_text += "  - %d: %.1f%%\n" % [pool["values"][i], p]
			next_move_bonus = rule.get_next_move_bonus()
		
	var stats = {
		"move_count": total_move_count,
		"monsters_killed": monsters_killed,
		"monster_spawn_info": spawn_info_text,
		"next_move_bonus": next_move_bonus
	}
	hud.update_stats(stats)

## [内部函数] 切换暂停菜单的可见性及游戏的暂停状态。
func _toggle_pause_menu():
	get_tree().paused = not get_tree().paused
	pause_menu.toggle()

## [内部函数] 初始化仅在编辑器中可见的测试工具面板。
func _initialize_test_tools():
	if OS.has_feature("editor"):
		test_panel.visible = true
		test_panel.spawn_requested.connect(game_board.spawn_specific_tile)
		test_panel.reset_and_resize_requested.connect(_on_reset_and_resize_requested)
		test_panel.live_expand_requested.connect(game_board.live_expand)
	else:
		test_panel.visible = false

## 响应来自测试面板的重置棋盘请求。
func _on_reset_and_resize_requested(new_size: int):
	# 在重新初始化前，安全地清理所有旧的规则实例，防止内存泄漏。
	for rule in spawn_rules:
		if is_instance_valid(rule):
			rule.queue_free()
	spawn_rules.clear() # 清空数组引用
	
	is_game_over = false
	monsters_killed = 0
	game_board.reset_and_resize(new_size)
	
	# 重置后，重新执行完整的初始化流程。
	_ready()

## 响应“继续游戏”事件。
func _on_resume_game(): _toggle_pause_menu()
## 响应“重新开始”事件。
func _on_restart_game(): get_tree().paused = false; get_tree().reload_current_scene()
## 响应“返回主菜单”事件。
func _on_return_to_main_menu(): get_tree().paused = false; GlobalGameManager.goto_scene("res://scenes/main_menu.tscn")
