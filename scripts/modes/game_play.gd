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
@onready var background_color_rect: ColorRect = %ColorRect

# --- 状态变量 ---
var mode_config: GameModeConfig
var interaction_rule: InteractionRule
var rule_manager: RuleManager # 规则管理器实例
var all_spawn_rules: Array[SpawnRule] = [] # 持有所有规则实例的引用

var move_count: int = 0
var monsters_killed: int = 0
var is_game_over: bool = false
var score: int = 0

## Godot生命周期函数：在节点进入场景树时被调用，负责整个游戏场景的初始化。
func _ready() -> void:
	# 步骤1: 从 GlobalGameManager 加载所选的游戏模式配置。
	var config_path = GlobalGameManager.get_selected_mode_config_path()
	if config_path != "":
		mode_config = load(config_path)
		assert(is_instance_valid(mode_config), "GameModeConfig未能加载！")
	else:
		push_error("错误: 无法加载游戏模式配置。")
		get_tree().quit()
		return
		
	# 步骤2: 实例化规则管理器和核心交互/结束规则。
	rule_manager = RuleManager.new()
	add_child(rule_manager)
	
	interaction_rule = mode_config.interaction_rule.duplicate()
	interaction_rule.setup(game_board)
	var game_over_rule = mode_config.game_over_rule.duplicate()
	# 应用棋盘主题
	if is_instance_valid(mode_config.board_theme):
		background_color_rect.color = mode_config.board_theme.game_background_color
		game_board.set_rules(interaction_rule, game_over_rule, mode_config.color_schemes, mode_config.board_theme)
	else:
		push_warning("当前游戏模式没有配置BoardTheme，将使用默认颜色。")
		game_board.set_rules(interaction_rule, game_over_rule, mode_config.color_schemes, null)
	
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
	game_board.initialize_board()
	_connect_signals()
	
	# 步骤5: 通过管理器触发棋盘初始化事件。
	rule_manager.dispatch_event(RuleManager.Events.INITIALIZE_BOARD)

	_initialize_test_tools()
	_update_stats_display()

## Godot生命周期函数：每帧调用。用于处理需要高频更新的逻辑，例如UI倒计时。
func _process(_delta: float) -> void:
	# 每帧更新UI，因为有些规则（如计时器）是实时变化的。
	if not is_game_over:
		_update_stats_display()

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
	if not game_board.move_made.is_connected(_on_game_board_move_made):
		game_board.move_made.connect(_on_game_board_move_made)
	
	if not game_board.game_lost.is_connected(_on_game_lost):
		game_board.game_lost.connect(_on_game_lost)
		
	if not game_board.board_resized.is_connected(_on_board_resized):
		game_board.board_resized.connect(_on_board_resized)
		
	if not game_board.score_updated.is_connected(_on_score_updated):
		game_board.score_updated.connect(_on_score_updated)
	
	# 连接来自UI菜单的信号
	if not pause_menu.resume_game.is_connected(_on_resume_game):
		pause_menu.resume_game.connect(_on_resume_game)
		
	if not pause_menu.restart_game.is_connected(_on_restart_game):
		pause_menu.restart_game.connect(_on_restart_game)
		
	if not pause_menu.return_to_main_menu.is_connected(_on_return_to_main_menu):
		pause_menu.return_to_main_menu.connect(_on_return_to_main_menu)
		
	if not game_over_menu.restart_game.is_connected(_on_restart_game):
		game_over_menu.restart_game.connect(_on_restart_game)
		
	if not game_over_menu.return_to_main_menu.is_connected(_on_return_to_main_menu):
		game_over_menu.return_to_main_menu.connect(_on_return_to_main_menu)
	
	# 连接来自规则的信号
	if is_instance_valid(rule_manager) and not rule_manager.spawn_tile_requested.is_connected(game_board.spawn_tile):
		rule_manager.spawn_tile_requested.connect(game_board.spawn_tile)
		
	if is_instance_valid(interaction_rule) and not interaction_rule.monster_killed.is_connected(_on_monster_killed):
		interaction_rule.monster_killed.connect(_on_monster_killed)

# --- 信号处理函数 ---

## 当 GameBoard 发出 move_made 信号时调用。
func _on_game_board_move_made() -> void:
	move_count += 1
	
	# 通过管理器分发“玩家移动”事件，让所有相关规则按优先级执行。
	# 时间奖励逻辑现在也由RuleManager通过ON_MOVE事件统一处理。
	rule_manager.dispatch_event(RuleManager.Events.PLAYER_MOVED)
			
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

## 当 GameBoard 发出 score_updated 信号时调用。
func _on_score_updated(amount: int) -> void:
	score += amount
	_update_stats_display() # 分数变化后立即更新显示

# --- UI 更新 & 菜单逻辑 ---

## [内部函数] 聚合所有规则和状态的数据，并更新HUD显示。
func _update_stats_display() -> void:
	var display_data = {}
	
	# --- 核心游戏信息 ---
	display_data["score"] = "分数: %d" % score
	display_data["highest_tile"] = "最大方块: %d" % game_board.get_max_player_value()
	display_data["move_count"] = "移动次数: %d" % move_count

	# --- 模式特定信息 ---
	# 只有在战斗模式下才显示消灭怪物数
	if interaction_rule is BattleInteractionRule:
		display_data["monsters_killed"] = "消灭怪物: %d" % monsters_killed
	
	# --- 从交互规则获取动态信息 (例如数列) ---
	if is_instance_valid(interaction_rule):
		var interaction_data = interaction_rule.get_display_data()
		if not interaction_data.is_empty():
			display_data.merge(interaction_data)

	# --- 规则动态信息 ---
	# 从所有规则中聚合需要显示的动态数据（如计时器）
	for rule in all_spawn_rules:
		var rule_data = rule.get_display_data()
		if not rule_data.is_empty():
			display_data.merge(rule_data)
	
	# --- 静态帮助信息 ---
	display_data["separator"] = "--------------------" # 分隔符
	if not mode_config.mode_description.is_empty():
		display_data["description"] = mode_config.mode_description
		
	display_data["controls"] = "操作: W/A/S/D 或 方向键\n暂停: Esc"
	
	hud.update_display(display_data)

## [内部函数] 切换暂停菜单的可见性及游戏的暂停状态。
func _toggle_pause_menu():
	get_tree().paused = not get_tree().paused
	pause_menu.toggle()

## [内部函数] 初始化仅在编辑器中可见的测试工具面板。
func _initialize_test_tools():
	if not OS.has_feature("editor"):
		test_panel.visible = false
		return
		
	test_panel.visible = true
	
	# 1. 连接TestPanel发出的请求信号
	if not test_panel.spawn_requested.is_connected(_on_test_panel_spawn_requested):
		test_panel.spawn_requested.connect(_on_test_panel_spawn_requested)
	
	if not test_panel.values_requested_for_type.is_connected(_on_test_panel_values_requested):
		test_panel.values_requested_for_type.connect(_on_test_panel_values_requested)
		
	if not test_panel.reset_and_resize_requested.is_connected(_on_reset_and_resize_requested):
		test_panel.reset_and_resize_requested.connect(_on_reset_and_resize_requested)
		
	if not test_panel.live_expand_requested.is_connected(game_board.live_expand):
		test_panel.live_expand_requested.connect(game_board.live_expand)
	
	# 2. 使用当前模式的规则来配置TestPanel
	var spawnable_types = interaction_rule.get_spawnable_types()
	test_panel.setup_panel(spawnable_types)

## 响应来自测试面板的生成方块请求。
func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	var tile_type_enum: Tile.TileType
	
	# 核心转换逻辑：将来自TestPanel的通用type_id转换为引擎可识别的Tile.TileType枚举。
	# 对于卢卡斯-斐波那契模式，所有“类型”实际上都是PLAYER类型。
	if interaction_rule is LucasFibonacciInteractionRule:
		tile_type_enum = Tile.TileType.PLAYER
	else:
		# 对于其他模式，我们假设 type_id 直接对应 Tile.TileType 枚举值 (0=PLAYER, 1=MONSTER)
		tile_type_enum = type_id as Tile.TileType
		
	game_board.spawn_specific_tile(grid_pos, value, tile_type_enum)

## 响应来自测试面板的、为特定类型请求数值列表的请求。
func _on_test_panel_values_requested(type_id: int) -> void:
	var values = interaction_rule.get_spawnable_values(type_id)
	test_panel.update_value_options(values)

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
	score = 0
	game_board.reset_and_resize(new_size, mode_config.board_theme)
	
	# 重置后，重新执行完整的初始化流程。
	_ready()

## 响应“继续游戏”事件。
func _on_resume_game(): _toggle_pause_menu()
## 响应“重新开始”事件。
func _on_restart_game(): get_tree().paused = false; get_tree().reload_current_scene()
## 响应“返回主菜单”事件。
func _on_return_to_main_menu():
	get_tree().paused = false
	GlobalGameManager.return_to_main_menu()
