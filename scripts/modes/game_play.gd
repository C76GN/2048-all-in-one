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
@onready var input_controller = $InputController

# --- 状态变量 ---
var mode_config: GameModeConfig
var interaction_rule: InteractionRule
var rule_manager: RuleManager # 规则管理器实例
var all_spawn_rules: Array[SpawnRule] = [] # 持有所有规则实例的引用

var move_count: int = 0
var monsters_killed: int = 0
var is_game_over: bool = false
var score: int = 0
var current_grid_size: int = 4
var initial_high_score: int = 0

## Godot生命周期函数：在节点进入场景树时被调用。
func _ready() -> void:
	_initialize_game()

## [内部函数] 负责整个游戏场景的初始化或重置。
## @param new_grid_size: 如果提供（大于-1），则使用此尺寸，否则从GlobalGameManager获取。
func _initialize_game(new_grid_size: int = -1) -> void:
	# 步骤1: 从 GlobalGameManager 加载所选的游戏模式配置和棋盘大小。
	var config_path = GlobalGameManager.get_selected_mode_config_path()
	if new_grid_size > -1:
		current_grid_size = new_grid_size
	else:
		current_grid_size = GlobalGameManager.get_selected_grid_size()
	
	if config_path != "":
		mode_config = load(config_path)
		assert(is_instance_valid(mode_config), "GameModeConfig未能加载！")
	else:
		push_error("错误: 无法加载游戏模式配置。")
		get_tree().quit()
		return
	
	# 在游戏开始时，获取并存储一次最高分。
	var mode_id = mode_config.resource_path.get_file().get_basename()
	initial_high_score = SaveManager.get_high_score(mode_id, current_grid_size)
		
	# 在初始化GameBoard前，设置其 grid_size 属性
	game_board.grid_size = current_grid_size
		
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
					add_child(new_timer)
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
	_update_and_publish_hud_data()

## Godot生命周期函数：每帧调用。用于处理需要高频更新的逻辑，例如UI倒计时。
func _process(_delta: float) -> void:
	# 每帧更新UI，因为有些规则（如计时器）是实时变化的。
	if not is_game_over:
		_update_and_publish_hud_data()

## [内部函数] 集中管理所有信号连接。
func _connect_signals() -> void:
	# 连接来自输入控制器的信号
	if is_instance_valid(input_controller):
		if not input_controller.move_intent_triggered.is_connected(_on_move_intent):
			input_controller.move_intent_triggered.connect(_on_move_intent)
		if not input_controller.pause_toggled.is_connected(_toggle_pause_menu):
			input_controller.pause_toggled.connect(_toggle_pause_menu)
			
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

	# --- 连接来自规则和EventBus的信号 ---
	if is_instance_valid(rule_manager) and not rule_manager.spawn_tile_requested.is_connected(game_board.spawn_tile):
		rule_manager.spawn_tile_requested.connect(game_board.spawn_tile)

	if not EventBus.move_made.is_connected(_on_move_made):
		EventBus.move_made.connect(_on_move_made)
	if not EventBus.game_lost.is_connected(_on_game_lost):
		EventBus.game_lost.connect(_on_game_lost)
	if not EventBus.score_updated.is_connected(_on_score_updated):
		EventBus.score_updated.connect(_on_score_updated)
	if not EventBus.monster_killed.is_connected(_on_monster_killed):
		EventBus.monster_killed.connect(_on_monster_killed)
	if not EventBus.board_resized.is_connected(_on_board_resized):
		EventBus.board_resized.connect(_on_board_resized)

# --- 信号处理函数 ---

## 当 InputController 发出移动意图时调用。
func _on_move_intent(direction: Vector2i) -> void:
	if is_game_over: return
	game_board.handle_move(direction)

func _on_move_made() -> void:
	move_count += 1
	rule_manager.dispatch_event(RuleManager.Events.PLAYER_MOVED)
	_update_and_publish_hud_data()

## 当 GameBoard 发出 game_lost 信号时调用。
func _on_game_lost() -> void:
	is_game_over = true
	# 通知所有规则进行清理
	for rule in all_spawn_rules:
		rule.teardown()
	
	# 保存分数
	var mode_id = mode_config.resource_path.get_file().get_basename()
	SaveManager.set_high_score(mode_id, current_grid_size, score)
	
	game_over_menu.open()

## 当 InteractionRule 报告有怪物被消灭时调用。
func _on_monster_killed() -> void:
	monsters_killed += 1
	rule_manager.dispatch_event(RuleManager.Events.MONSTER_KILLED)
	_update_and_publish_hud_data()

func _on_score_updated(amount: int) -> void:
	score += amount
	_update_and_publish_hud_data()

## 当棋盘大小改变时，更新测试面板的坐标限制。
func _on_board_resized(new_size: int):
	if OS.has_feature("editor") and is_instance_valid(test_panel):
		test_panel.update_coordinate_limits(new_size)

# --- UI 更新 & 菜单逻辑 ---

## [内部函数] 聚合所有数据，格式化，并通过EventBus发布给HUD。
func _update_and_publish_hud_data() -> void:
	var display_data = {}
	
	# --- 核心游戏信息 ---
	display_data["score"] = "分数: %d" % score
	
	# 使用 initial_high_score 进行实时比较和显示
	if score > initial_high_score:
		display_data["high_score"] = "最高分: %d [color=yellow](新纪录!)[/color]" % score
	else:
		display_data["high_score"] = "最高分: %d" % initial_high_score
		
	display_data["highest_tile"] = "最大方块: %d" % game_board.get_max_player_value()
	display_data["move_count"] = "移动次数: %d" % move_count

	# --- 规则动态信息 ---
	var player_values = game_board.get_all_player_tile_values()
	var player_values_set = {}
	for v in player_values: player_values_set[v] = true
	
	var rule_context = {
		"monsters_killed": monsters_killed, "score": score, "move_count": move_count,
		"all_player_values": player_values, "max_player_value": game_board.get_max_player_value(),
		"player_values_set": player_values_set
	}
	
	if is_instance_valid(interaction_rule):
		var interaction_data = interaction_rule.get_hud_context_data(rule_context)
		_format_interaction_data(display_data, interaction_data)

	# --- 规则动态信息 ---
	# 从所有规则中聚合需要显示的动态数据（如计时器）
	for rule in all_spawn_rules:
		var rule_data = rule.get_display_data()
		if not rule_data.is_empty():
			display_data.merge(rule_data)
	
	# --- 静态帮助信息 ---
	display_data["separator"] = "--------------------"
	if not mode_config.mode_description.is_empty():
		display_data["description"] = mode_config.mode_description
	display_data["controls"] = "操作: W/A/S/D 或 方向键\n暂停: Esc"
	
	EventBus.hud_update_requested.emit(display_data)

## [内部辅助] 将来自规则的原始数据格式化为HUD所需的数据结构。
func _format_interaction_data(p_display_data: Dictionary, p_raw_data: Dictionary):
	# 战斗模式
	if p_raw_data.has("monsters_killed"):
		p_display_data["monsters_killed"] = "消灭怪物: %d" % p_raw_data["monsters_killed"]
	
	# 斐波那契模式
	if p_raw_data.has("fib_sequence"):
		var fib_data_for_ui = [{"text": "合成序列:", "color": Color.WHITE}]
		var player_set = p_raw_data["player_values_set"]
		for num in p_raw_data["fib_sequence"]:
			var item = {"text": str(num), "color": Color.GRAY}
			if player_set.has(num): item["color"] = Color.WHITE
			fib_data_for_ui.append(item)
		p_display_data["fibonacci_sequence"] = fib_data_for_ui
		
	# 卢卡斯-斐波那契模式
	if p_raw_data.has("luc_sequence"):
		var player_set = p_raw_data["player_values_set"]
		var synthesis_data = p_raw_data.get("synthesis_data", {})
		var highlight_fib_components = {}
		var highlight_lucas_set = {}
		
		if not synthesis_data.is_empty():
			highlight_fib_components[synthesis_data["f_minus_1"]] = true
			highlight_fib_components[synthesis_data["f_plus_1"]] = true
			highlight_lucas_set[synthesis_data["l_n"]] = true
			p_display_data["synthesis_tip_display"] = "合成提示: [color=cyan]%d[/color] + [color=cyan]%d[/color] = [color=yellow]%d[/color]" % [synthesis_data["f_minus_1"], synthesis_data["f_plus_1"], synthesis_data["l_n"]]
			
		var fib_data_for_ui = [{"text": "斐波那契:", "color": Color.WHITE}]
		for num in p_raw_data["fib_sequence"]:
			if num > p_raw_data["max_display_value"]: break
			var item = {"text": str(num), "color": Color.GRAY}
			if highlight_fib_components.has(num): item["color"] = Color.CYAN
			elif player_set.has(num): item["color"] = Color.WHITE
			fib_data_for_ui.append(item)
		p_display_data["fib_sequence_display"] = fib_data_for_ui
		
		var luc_data_for_ui = [{"text": "卢卡斯:", "color": Color.WHITE}]
		for num in p_raw_data["luc_sequence"]:
			if num > p_raw_data["max_display_value"]: break
			var item = {"text": str(num), "color": Color.GRAY}
			if highlight_lucas_set.has(num): item["color"] = Color.YELLOW
			elif player_set.has(num): item["color"] = Color.WHITE
			luc_data_for_ui.append(item)
		p_display_data["luc_sequence_display"] = luc_data_for_ui

func _toggle_pause_menu():
	if is_game_over: return
	get_tree().paused = not get_tree().paused
	pause_menu.toggle()

## [内部函数] 初始化测试工具。
func _initialize_test_tools():
	if not OS.has_feature("with_test_panel") and not OS.has_feature("editor"):
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
	test_panel.update_coordinate_limits(current_grid_size)

## 响应来自测试面板的生成方块请求。
func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	# 将类型ID到TileType枚举的转换委托给当前的交互规则
	var tile_type_enum = interaction_rule.get_tile_type_from_id(type_id)
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

	is_game_over = false; monsters_killed = 0; move_count = 0; score = 0
	
	# 先清理棋盘，但不在这里设置尺寸，交由 _initialize_game 统一处理
	game_board.reset_and_resize(new_size, mode_config.board_theme)
	
	# MODIFIED: 将 new_size 传递给初始化函数
	_initialize_game(new_size)

## 响应“继续游戏”事件。
func _on_resume_game(): _toggle_pause_menu()
## 响应“重新开始”事件。
func _on_restart_game(): get_tree().paused = false; get_tree().reload_current_scene()
## 响应“返回主菜单”事件。
func _on_return_to_main_menu():
	get_tree().paused = false
	GlobalGameManager.return_to_main_menu()
