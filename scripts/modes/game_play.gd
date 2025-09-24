# scripts/modes/game_play.gd

## GamePlay: 通用的游戏逻辑控制器。
##
## 负责加载 GameModeConfig，设置 RuleManager，并协调核心组件之间的通信。
class_name GamePlay
extends Control

# --- 节点引用 ---
@onready var game_board: Control = %GameBoard
@onready var test_panel: VBoxContainer = %TestPanel
@onready var hud: VBoxContainer = %HUD
@onready var pause_menu = $PauseMenu
@onready var game_over_menu = $GameOverMenu

# --- 状态变量 ---
var mode_config: GameModeConfig
var interaction_rule: InteractionRule
var rule_manager: RuleManager # 规则管理器实例
var all_spawn_rules: Array[SpawnRule] = [] # 持有所有规则实例的引用

var move_count: int = 0
var monsters_killed: int = 0
var is_game_over: bool = false

## Godot生命周期函数：在节点进入场景树时被调用，负责整个游戏场景的初始化。
func _ready() -> void:
	# 步骤1: 从 GlobalGameManager 加载所选的游戏模式配置。
	if "selected_mode_config_path" in GlobalGameManager and GlobalGameManager.selected_mode_config_path != "":
		mode_config = load(GlobalGameManager.selected_mode_config_path)
		assert(is_instance_valid(mode_config), "GameModeConfig未能加载！")
	else:
		push_error("错误: 无法加载游戏模式配置。")
		get_tree().quit()
		return
		
	# 步骤2: 实例化规则管理器和核心交互/结束规则。
	rule_manager = RuleManager.new()
	add_child(rule_manager)
	
	interaction_rule = mode_config.interaction_rule.duplicate()
	var game_over_rule = mode_config.game_over_rule.duplicate()
	game_board.set_rules(interaction_rule, game_over_rule, mode_config.color_scheme, mode_config.monster_color_scheme)
	
	# 步骤3: 初始化所有在配置中定义的生成规则。
	for rule_resource in mode_config.spawn_rules:
		var rule_instance: SpawnRule = rule_resource.duplicate()
		all_spawn_rules.append(rule_instance)
		
		# 检查规则是否需要额外的节点（如Timer），并为它创建。
		var required_nodes = rule_instance.get_required_nodes()
		var created_nodes = {}
		if not required_nodes.is_empty():
			for node_key in required_nodes:
				if required_nodes[node_key] == "Timer":
					var new_timer = Timer.new()
					add_child(new_timer) # 将Timer添加到场景树以使其运行
					created_nodes[node_key] = new_timer
		
		# 将所有依赖项（棋盘、创建的节点）注入规则实例。
		rule_instance.setup(game_board, created_nodes)

	# 步骤4: 注册所有规则到管理器并连接所有信号。
	rule_manager.register_rules(all_spawn_rules)
	_connect_signals()
	
	# 步骤5: 通过管理器触发棋盘初始化事件。
	rule_manager.dispatch_event(RuleManager.Events.INITIALIZE_BOARD)

	_initialize_test_tools()
	_update_stats_display()

## Godot生命周期函数：每帧调用。用于处理需要高频更新的逻辑，例如UI倒计时。
func _process(_delta: float) -> void:
	if not is_game_over:
		# 从所有规则中找到计时器规则并更新HUD。
		for rule in all_spawn_rules:
			if rule is TimedMonsterSpawnRule:
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
	rule_manager.spawn_tile_requested.connect(game_board.spawn_tile)
	if is_instance_valid(interaction_rule):
		interaction_rule.monster_killed.connect(_on_monster_killed)

# --- 信号处理函数 ---

## 当 GameBoard 发出 move_made 信号时调用。
func _on_game_board_move_made() -> void:
	move_count += 1
	
	# 通过管理器分发“玩家移动”事件，让相关规则按优先级执行。
	rule_manager.dispatch_event(RuleManager.Events.PLAYER_MOVED)
	
	# 特殊处理：手动调用那些需要响应移动，但不是通过触发器工作的逻辑（如计时器奖励）。
	for rule in all_spawn_rules:
		if rule.has_method("on_move_made"):
			rule.on_move_made()
			
	_update_stats_display()

## 当 GameBoard 发出 game_lost 信号时调用。
func _on_game_lost() -> void:
	is_game_over = true
	# 通知所有规则进行清理（如停止计时器）。
	for rule in all_spawn_rules:
		rule.teardown()
	game_over_menu.open()

## 当 InteractionRule 报告有怪物被消灭时调用。
func _on_monster_killed() -> void:
	monsters_killed += 1
	# 分发“怪物被消灭”事件，未来可以用于实现“消灭怪物后生成宝箱”等规则。
	rule_manager.dispatch_event(RuleManager.Events.MONSTER_KILLED)
	_update_stats_display()

## 当棋盘大小改变时，更新测试面板的坐标限制。
func _on_board_resized(new_size: int):
	if OS.has_feature("editor") and is_instance_valid(test_panel):
		test_panel.update_coordinate_limits(new_size)

# --- UI 更新 & 菜单逻辑 ---

## [内部函数] 聚合所有规则和状态的数据，并更新HUD显示。
func _update_stats_display() -> void:
	var spawn_info_text = ""
	var next_move_bonus = 0.0
	
	# 从所有规则中聚合需要显示的数据
	for rule in all_spawn_rules:
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
		"move_count": move_count, # 直接使用 GamePlay 的 move_count
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
	# 在重新初始化前，安全地清理所有旧的规则实例和管理器。
	for rule in all_spawn_rules:
		rule.teardown()
	all_spawn_rules.clear()
	
	if is_instance_valid(rule_manager):
		rule_manager.queue_free()

	is_game_over = false
	monsters_killed = 0
	move_count = 0
	game_board.reset_and_resize(new_size)
	
	# 重置后，重新执行完整的初始化流程。
	_ready()

## 响应“继续游戏”事件。
func _on_resume_game(): _toggle_pause_menu()
## 响应“重新开始”事件。
func _on_restart_game(): get_tree().paused = false; get_tree().reload_current_scene()
## 响应“返回主菜单”事件。
func _on_return_to_main_menu(): get_tree().paused = false; GlobalGameManager.goto_scene("res://scenes/main_menu.tscn")
