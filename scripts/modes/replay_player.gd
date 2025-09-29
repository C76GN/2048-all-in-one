# scripts/modes/replay_player.gd

## ReplayPlayer: 负责播放单个游戏回放的控制器。
##
## 它加载一个 ReplayData 资源，重置游戏到初始状态，然后
## 允许用户通过UI按钮逐步执行记录中的每一步操作。
class_name ReplayPlayer
extends Control

# --- 节点引用 ---
@onready var game_board: Control = %GameBoard
@onready var hud: VBoxContainer = %HUD
@onready var background_color_rect: ColorRect = %ColorRect
@onready var board_animator: BoardAnimator = $BoardAnimator
@onready var prev_step_button: Button = $MarginContainer/MainLayoutContainer/RightPanel/HBoxContainer/PrevStepButton
@onready var next_step_button: Button = $MarginContainer/MainLayoutContainer/RightPanel/HBoxContainer/NextStepButton
@onready var back_button: Button = $MarginContainer/MainLayoutContainer/RightPanel/BackButton

# --- 状态变量 ---
var replay_data: ReplayData
var interaction_rule: InteractionRule # 只用于视觉更新
var game_state_history: Array[Dictionary] = []
var current_step: int = -1 # -1 代表初始状态

func _ready() -> void:
	# 在开始播放前，必须验证 GlobalGameManager 中是否存在一个有效的 ReplayData 实例，以防止因数据缺失导致的崩溃。
	if not is_instance_valid(GlobalGameManager.current_replay_data):
		push_error("无法播放回放：没有提供有效的ReplayData。")
		GlobalGameManager.return_to_main_menu() # 安全地返回
		return

	replay_data = GlobalGameManager.current_replay_data
	
	# 连接UI信号
	prev_step_button.pressed.connect(func(): _go_to_step(current_step - 1))
	next_step_button.pressed.connect(func(): _go_to_step(current_step + 1))
	back_button.pressed.connect(func():
		# 在切换场景前，清除全局管理器中的引用，释放资源。
		GlobalGameManager.current_replay_data = null
		GlobalGameManager.goto_scene("res://scenes/replay_list.tscn")
	)

	_initialize_replay()

## 初始化回放播放器状态。
func _initialize_replay() -> void:
	# 步骤1: 加载模式配置以获取完整的游戏规则和主题。
	var mode_config: GameModeConfig = load(replay_data.mode_config_path)
	interaction_rule = mode_config.interaction_rule.duplicate()
	
	# 即使在回放中，GameBoard也需要所有规则的有效实例（特别是`game_over_rule`）
	# 来确保其内部逻辑的完整性。
	var game_over_rule = mode_config.game_over_rule.duplicate()
	
	game_board.grid_size = replay_data.grid_size
	
	background_color_rect.color = mode_config.board_theme.game_background_color
	
	game_board.set_rules(interaction_rule, game_over_rule, mode_config.color_schemes, mode_config.board_theme)
	
	game_board.initialize_board()
	game_board.play_animations_requested.connect(board_animator.play_animation_sequence)
	
	# 步骤2: 重建整个游戏过程的状态历史
	_build_state_history()

	# 步骤3: 跳转到初始状态 (第0步)
	_go_to_step(0, true)

## 通过在内存中完整地模拟一次游戏过程，来构建一个包含每一步棋盘状态的数组。
## 这是实现任意步骤跳转的核心。
func _build_state_history() -> void:
	# 设置到初始状态
	RNGManager.initialize_rng(replay_data.initial_seed)
	
	# 创建一个临时的规则管理器，用于在内存中模拟游戏逻辑，而不影响场景本身。
	var temp_rule_manager = RuleManager.new()
	var spawn_rules: Array[SpawnRule] = []
	var mode_config: GameModeConfig = load(replay_data.mode_config_path)
	for rule_res in mode_config.spawn_rules:
		var rule_instance = rule_res.duplicate()
		# 使用一个简化的 setup，因为在模拟中我们不需要像计时器这样的动态节点。
		rule_instance.setup(game_board)
		spawn_rules.append(rule_instance)
	temp_rule_manager.register_rules(spawn_rules)

	# 捕获临时规则管理器发出的生成信号，以便我们可以手动将方块应用到棋盘上。
	var spawn_queue = []
	temp_rule_manager.spawn_tile_requested.connect(func(data): spawn_queue.append(data))
	
	# --- 初始状态 ---
	# 触发棋盘初始化事件，并应用生成的方块。
	temp_rule_manager.dispatch_event(RuleManager.Events.INITIALIZE_BOARD)
	for data in spawn_queue: game_board.spawn_tile(data)
	spawn_queue.clear()
	# 将初始状态存入历史记录。
	game_state_history.append(game_board.get_state_snapshot())
	
	# --- 模拟每一步 ---
	for action in replay_data.actions:
		# 模拟一次移动。
		game_board.handle_move(action)
		
		# 模拟移动后触发的方块生成事件。
		temp_rule_manager.dispatch_event(RuleManager.Events.PLAYER_MOVED)
		for data in spawn_queue: game_board.spawn_tile(data)
		spawn_queue.clear()
		
		# 将这一步之后的状态存入历史记录。
		game_state_history.append(game_board.get_state_snapshot())
		
	# 模拟完成后，清理临时管理器。
	temp_rule_manager.queue_free()

## 跳转到指定的步骤。
func _go_to_step(step_index: int, _is_initial: bool = false) -> void:
	if step_index < 0 or step_index >= game_state_history.size():
		return
		
	current_step = step_index
	
	# 从历史记录中恢复棋盘状态。
	game_board.restore_from_snapshot(game_state_history[current_step])

	# 更新UI元素，如步数显示和按钮状态。
	_update_hud()
	prev_step_button.disabled = (current_step == 0)
	next_step_button.disabled = (current_step == game_state_history.size() - 1)

## 更新HUD显示。
func _update_hud() -> void:
	# 这是一个为回放模式简化的HUD更新，只显示最关键的信息。
	var display_data = {}
	display_data["step_info"] = "步骤: %d / %d" % [current_step, replay_data.actions.size()]
	display_data["seed_info"] = "种子: %d" % replay_data.initial_seed
	# 当播放到最后一步时，显示最终分数。
	if current_step == replay_data.actions.size():
		display_data["final_score"] = "最终分数: %d" % replay_data.final_score

	EventBus.hud_update_requested.emit(display_data)
