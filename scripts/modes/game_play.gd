# scripts/modes/game_play.gd

## GamePlay: 通用的游戏逻辑控制器。
##
## 负责加载 GameModeConfig，设置 RuleManager，并协调核心组件之间的通信。
## 它使用状态机管理游戏生命周期，并作为撤回(Undo)、快照(Snapshot)和
## 游戏回放(Replay)功能的总协调者。
class_name GamePlay
extends Control

# --- 枚举定义 ---

## 定义了 GamePlay 的核心状态。
enum State {
	READY, # 游戏已初始化，等待开始
	PLAYING, # 游戏正在进行中
	GAME_OVER # 游戏已结束
}

const RestartConfirmDialogScene = preload("res://scenes/ui/restart_confirm_dialog.tscn")

# --- 节点引用 ---
@onready var game_board: Control = %GameBoard
@onready var test_panel: VBoxContainer = %TestPanel
@onready var hud: VBoxContainer = %HUD
@onready var background_color_rect: ColorRect = %ColorRect
@onready var input_controller = $InputController
@onready var board_animator: BoardAnimator = $BoardAnimator
@onready var state_machine: StateMachine = $StateMachine
@onready var undo_button: Button = %UndoButton
@onready var snapshot_button: Button = %SnapshotButton
@onready var ui_manager: UIManager = $UIManager
@onready var _hud_message_timer: Timer = $HUDMessageTimer

# --- 状态变量 ---
var mode_config: GameModeConfig
var interaction_rule: InteractionRule
var rule_manager: RuleManager
var all_spawn_rules: Array[SpawnRule] = []
var move_count: int = 0
var monsters_killed: int = 0
var score: int = 0
var current_grid_size: int = 4
var initial_high_score: int = 0
var _current_replay_data: ReplayData
var _game_state_history: Array[Dictionary] = []
var _last_move_direction: Vector2i = Vector2i.ZERO
var _loaded_bookmark_data: BookmarkData = null
var _last_saved_bookmark_state: Dictionary = {}
var _hud_status_message: String = ""
var _is_game_state_tainted_by_test_tools: bool = false

## Godot生命周期函数：在节点进入场景树时被调用。
func _ready() -> void:
	_initialize_game()

## [FSM] 状态机进入一个新状态时被调用。
func _enter_state(new_state, _message: Dictionary = {}) -> void:
	match new_state:
		State.PLAYING:
			pass
		State.GAME_OVER:
			# 通知所有规则进行清理
			for rule in all_spawn_rules:
				rule.teardown()
			
			# 保存分数
			var mode_id = mode_config.resource_path.get_file().get_basename()
			SaveManager.set_high_score(mode_id, current_grid_size, score)
			
			# 保存回放
			if not _is_game_state_tainted_by_test_tools:
				if _current_replay_data.actions.size() > 0:
					_current_replay_data.final_score = score
					ReplayManager.save_replay(_current_replay_data)
			else:
				print("警告: 游戏状态已被测试工具修改，回放将不会被保存。")
			
			ui_manager.show_game_over_menu()

## [FSM] 状态机退出当前状态时被调用。
func _exit_state(_old_state) -> void:
	pass

## [FSM] 状态机在当前状态下每帧被调用。
func _process_state(_delta: float, current_state) -> void:
	match current_state:
		State.PLAYING:
			# 每帧更新UI，因为有些规则（如计时器）是实时变化的。
			_update_and_publish_hud_data()

## [内部函数] 负责整个游戏场景的初始化或重置。
## @param new_grid_size: 如果提供（大于-1），则使用此尺寸，否则从GlobalGameManager获取。
func _initialize_game(new_grid_size: int = -1) -> void:
	state_machine.set_state(State.READY)
	_is_game_state_tainted_by_test_tools = false
	
	_loaded_bookmark_data = GlobalGameManager.selected_bookmark_data
	# 加载后立即清除全局变量，防止下次正常开始游戏时被误用
	GlobalGameManager.selected_bookmark_data = null
	
	_current_replay_data = ReplayData.new()
	_game_state_history.clear()

	# 根据是否存在书签数据，选择不同的初始化路径
	if is_instance_valid(_loaded_bookmark_data):
		if not _setup_game_from_bookmark():
			return # 如果书签加载失败，则中止
	else:
		if not _setup_new_game(new_grid_size):
			return # 如果新游戏设置失败，则中止

	# 执行两种路径共用的最终初始化步骤
	_finalize_initialization()

## [内部函数] 从一个有效的书签数据中设置游戏状态。
func _setup_game_from_bookmark() -> bool:
	mode_config = load(_loaded_bookmark_data.mode_config_path)
	current_grid_size = _loaded_bookmark_data.board_snapshot.get("grid_size")
	RNGManager.initialize_rng(_loaded_bookmark_data.initial_seed)
	RNGManager.set_state(_loaded_bookmark_data.rng_state)
	score = _loaded_bookmark_data.score
	move_count = _loaded_bookmark_data.move_count
	monsters_killed = _loaded_bookmark_data.monsters_killed
	
	if "game_state_history" in _loaded_bookmark_data and not _loaded_bookmark_data.game_state_history.is_empty():
		_game_state_history = _loaded_bookmark_data.game_state_history.duplicate(true) as Array[Dictionary]

	return true

## [内部函数] 根据全局设置或传入参数来配置一个新游戏。
func _setup_new_game(new_grid_size: int = -1) -> bool:
	var initial_seed = RNGManager.get_current_seed() if new_grid_size == -1 else int(Time.get_unix_time_from_system())
	RNGManager.initialize_rng(initial_seed)
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
		# 确保在退出前取消暂停
		get_tree().paused = false
		GlobalGameManager.return_to_main_menu()
		return false
	
	return true

## [内部函数] 在设置好游戏模式和状态后，完成所有节点的实例化和连接。
func _finalize_initialization() -> void:
	# 填充回放元数据 (对新游戏和加载的游戏都适用)
	_current_replay_data.timestamp = int(Time.get_unix_time_from_system())
	_current_replay_data.mode_config_path = mode_config.resource_path
	_current_replay_data.initial_seed = RNGManager.get_current_seed() # 使用当前RNG的种子
	_current_replay_data.grid_size = current_grid_size

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
	
	# 步骤5: 如果是新游戏，则通过管理器触发棋盘初始化事件；
#       如果是从书签加载，则直接恢复棋盘状态。
	if is_instance_valid(_loaded_bookmark_data):
		game_board.restore_from_snapshot(_loaded_bookmark_data.board_snapshot)
		# 恢复后，将当前状态设为最后保存状态，防止一进来就重复保存
		_last_saved_bookmark_state = _get_full_game_state()
	else:
		rule_manager.dispatch_event(RuleManager.Events.INITIALIZE_BOARD)

	_initialize_test_tools()
	_update_and_publish_hud_data()

	# 只有在新游戏时才保存初始状态，加载游戏时历史记录已恢复
	if not is_instance_valid(_loaded_bookmark_data):
		_save_current_state()

	# 初始化完成，进入 PLAYING 状态
	state_machine.set_state(State.PLAYING)

## [内部函数] 集中管理所有信号连接。
func _connect_signals() -> void:
	# 连接来自输入控制器的信号
	if is_instance_valid(input_controller):
		if not input_controller.move_intent_triggered.is_connected(_on_move_intent):
			input_controller.move_intent_triggered.connect(_on_move_intent)
		if not input_controller.pause_toggled.is_connected(_on_pause_toggled):
			input_controller.pause_toggled.connect(_on_pause_toggled)
			
	# 连接来自UIManager的信号
	if not ui_manager.resume_requested.is_connected(_on_resume_game):
		ui_manager.resume_requested.connect(_on_resume_game)
	if not ui_manager.restart_requested.is_connected(_on_restart_game):
		ui_manager.restart_requested.connect(_on_restart_game)
	if not ui_manager.main_menu_requested.is_connected(_on_return_to_main_menu):
		ui_manager.main_menu_requested.connect(_on_return_to_main_menu)
	
	if is_instance_valid(undo_button) and not undo_button.pressed.is_connected(_on_undo_button_pressed):
		undo_button.pressed.connect(_on_undo_button_pressed)
	if is_instance_valid(snapshot_button) and not snapshot_button.pressed.is_connected(_on_snapshot_button_pressed):
		snapshot_button.pressed.connect(_on_snapshot_button_pressed)
	
	if not _hud_message_timer.timeout.is_connected(_on_hud_message_timer_timeout):
		_hud_message_timer.timeout.connect(_on_hud_message_timer_timeout)

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
	if is_instance_valid(game_board) and is_instance_valid(board_animator):
		# 将 GameBoard 的动画请求连接到 BoardAnimator 的播放函数
		if not game_board.play_animations_requested.is_connected(board_animator.play_animation_sequence):
			game_board.play_animations_requested.connect(board_animator.play_animation_sequence)

# --- 信号处理函数 ---

## 当 InputController 发出移动意图时调用。
func _on_move_intent(direction: Vector2i) -> void:
	if state_machine.current_state_name != State.PLAYING: return
	_last_move_direction = direction
	_save_current_state()
	game_board.handle_move(direction)

func _on_move_made(move_data: Dictionary) -> void:
	move_count += 1
	# 记录有效移动到回放数据中
	_current_replay_data.actions.append(_last_move_direction)
	rule_manager.dispatch_event(RuleManager.Events.PLAYER_MOVED, move_data)
	_update_and_publish_hud_data()

## 当 EventBus 发出 game_lost 信号时调用。
func _on_game_lost() -> void:
	state_machine.set_state(State.GAME_OVER)

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

## [内部函数] 聚合所有数据并通过EventBus发布给HUD。
func _update_and_publish_hud_data() -> void:
	var display_data = {}
	
	# --- 1. 核心游戏信息 (由GamePlay自己管理) ---
	display_data["score"] = "分数: %d" % score
	if score > initial_high_score:
		display_data["high_score"] = "最高分: %d [color=yellow](新纪录!)[/color]" % score
	else:
		display_data["high_score"] = "最高分: %d" % initial_high_score
	display_data["highest_tile"] = "最大方块: %d" % game_board.get_max_player_value()
	display_data["move_count"] = "移动次数: %d" % move_count

	# --- 2. 动态规则信息 (向规则请求格式化好的数据) ---
	# 创建一个包含原始数据的上下文，供规则查询使用
	var player_values = game_board.get_all_player_tile_values()
	var player_values_set = {}
	for v in player_values: player_values_set[v] = true
	
	var rule_context = {
		"monsters_killed": monsters_killed, "score": score, "move_count": move_count,
		"all_player_values": player_values, "max_player_value": game_board.get_max_player_value(),
		"player_values_set": player_values_set
	}
	
	# 从交互规则获取其显示数据
	if is_instance_valid(interaction_rule):
		var interaction_data = interaction_rule.get_hud_context_data(rule_context)
		display_data.merge(interaction_data)

	# 从所有生成规则获取它们的显示数据 (如计时器)
	for rule in all_spawn_rules:
		var rule_data = rule.get_display_data()
		if not rule_data.is_empty():
			display_data.merge(rule_data)
	
	# --- 3. 静态帮助信息 ---
	display_data["separator"] = "--------------------"
	if not mode_config.mode_description.is_empty():
		display_data["description"] = mode_config.mode_description
	display_data["controls"] = "操作: W/A/S/D 或 方向键\n暂停: Esc"
	display_data["seed_info"] = "游戏种子: %d" % RNGManager.get_current_seed()
	
	if _is_game_state_tainted_by_test_tools:
		display_data["taint_warning"] = "[color=orange]警告: 调试工具已使用，回放将被禁用。[/color]"
		
	if not _hud_status_message.is_empty():
		display_data["status_message"] = _hud_status_message

	# --- 4. 发布最终数据 ---
	EventBus.hud_update_requested.emit(display_data)

func _on_pause_toggled():
	if state_machine.current_state_name == State.GAME_OVER: return
	
	if get_tree().paused:
		# 如果游戏已暂停，则恢复
		ui_manager.close_current_ui()
		# FSM状态不需要改变，因为暂停不是一个核心游戏逻辑状态
	else:
		# 如果游戏正在进行，则显示暂停菜单
		ui_manager.show_pause_menu()

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
		test_panel.live_expand_requested.connect(func(new_size):
			_is_game_state_tainted_by_test_tools = true
			game_board.live_expand(new_size)
		)
	
	# 2. 使用当前模式的规则来配置TestPanel
	var spawnable_types = interaction_rule.get_spawnable_types()
	test_panel.setup_panel(spawnable_types)
	test_panel.update_coordinate_limits(current_grid_size)

## 响应来自测试面板的生成方块请求。
func _on_test_panel_spawn_requested(grid_pos: Vector2i, value: int, type_id: int) -> void:
	_is_game_state_tainted_by_test_tools = true
	# 将类型ID到TileType枚举的转换委托给当前的交互规则
	var tile_type_enum = interaction_rule.get_tile_type_from_id(type_id)
	game_board.spawn_specific_tile(grid_pos, value, tile_type_enum)

## 响应来自测试面板的、为特定类型请求数值列表的请求。
func _on_test_panel_values_requested(type_id: int) -> void:
	var values = interaction_rule.get_spawnable_values(type_id)
	test_panel.update_value_options(values)

## 响应来自测试面板的重置棋盘请求。
func _on_reset_and_resize_requested(new_size: int):
	_is_game_state_tainted_by_test_tools = true
	# 在重新初始化前，安全地清理所有旧的规则实例和管理器。
	for rule in all_spawn_rules:
		rule.teardown()
	all_spawn_rules.clear()
	
	if is_instance_valid(rule_manager):
		rule_manager.queue_free()

	monsters_killed = 0
	move_count = 0
	score = 0
	
	# 先清理棋盘，但不在这里设置尺寸，交由 _initialize_game 统一处理
	game_board.reset_and_resize(new_size, mode_config.board_theme)
	
	_initialize_game(new_size)

## 响应“继续游戏”事件。
func _on_resume_game():
	state_machine.set_state(State.PLAYING)

## 响应“重新开始”事件。
func _on_restart_game(_from_bookmark: bool):
	if is_instance_valid(_loaded_bookmark_data):
		_show_restart_confirmation()
	else:
		# 对于非书签启动的游戏，直接重启
		get_tree().paused = false # 确保在重载前取消暂停
		get_tree().reload_current_scene()

## 响应“返回主菜单”事件。
func _on_return_to_main_menu():
	get_tree().paused = false
	GlobalGameManager.return_to_main_menu()

# --- 状态管理与UI交互 ---

## 保存当前游戏的完整状态，用于撤回。
func _save_current_state() -> void:
	var state = _get_full_game_state()
	_game_state_history.push_back(state)

## 提取获取完整游戏状态的逻辑为一个独立函数
func _get_full_game_state() -> Dictionary:
	return {
		"board_snapshot": game_board.get_state_snapshot(),
		"rng_state": RNGManager.get_state(),
		"score": score,
		"move_count": move_count,
		"monsters_killed": monsters_killed
	}

## 响应“撤回”按钮的点击事件。
func _on_undo_button_pressed() -> void:
	if state_machine.current_state_name != State.PLAYING or get_tree().paused: return
	
	if _game_state_history.size() > 1:
		# 1. 移除当前状态
		_game_state_history.pop_back()
		# 2. 获取并恢复到上一个状态
		var last_state = _game_state_history.back()
		
		score = last_state["score"]
		move_count = last_state["move_count"]
		monsters_killed = last_state["monsters_killed"]
		RNGManager.set_state(last_state["rng_state"])
		game_board.restore_from_snapshot(last_state["board_snapshot"])
		
		_update_and_publish_hud_data()
	else:
		_show_hud_message("[color=yellow]无法撤回: 已在最初状态。[/color]", 3.0)

func _on_snapshot_button_pressed() -> void:
	if state_machine.current_state_name != State.PLAYING or get_tree().paused: return
	
	if _is_game_state_tainted_by_test_tools:
		_show_hud_message("[color=orange]警告: 正在保存一个被调试工具修改过的状态！[/color]", 4.0)
	
	# 为了进行比较，创建一个包含历史的临时状态字典
	var current_state_for_comparison = _get_full_game_state()
	current_state_for_comparison["game_state_history"] = _game_state_history

	if JSON.stringify(current_state_for_comparison) == JSON.stringify(_last_saved_bookmark_state):
		_show_hud_message("[color=yellow]游戏状态未变，无需重复保存。[/color]", 3.0)
		return
	
	# 创建新的书签实例
	var new_bookmark = BookmarkData.new()
	new_bookmark.timestamp = int(Time.get_unix_time_from_system())
	new_bookmark.mode_config_path = mode_config.resource_path
	new_bookmark.initial_seed = RNGManager.get_current_seed()
	
	# 从最新的原子状态中获取数据
	var latest_atomic_state = _game_state_history.back()
	new_bookmark.score = latest_atomic_state["score"]
	new_bookmark.move_count = latest_atomic_state["move_count"]
	new_bookmark.monsters_killed = latest_atomic_state["monsters_killed"]
	new_bookmark.rng_state = latest_atomic_state["rng_state"]
	new_bookmark.board_snapshot = latest_atomic_state["board_snapshot"]
	
	# 保存完整的、扁平化的历史记录
	new_bookmark.game_state_history = _game_state_history.duplicate(true)
	
	BookmarkManager.save_bookmark(new_bookmark)
	
	# 更新最后保存的状态以用于比较
	_last_saved_bookmark_state = current_state_for_comparison
	_show_hud_message("[color=green]书签已保存！[/color]", 3.0)

## 显示临时HUD消息的函数
func _show_hud_message(message: String, duration: float) -> void:
	_hud_status_message = message
	_update_and_publish_hud_data()
	_hud_message_timer.start(duration)

##  HUD消息计时器到期后的处理函数
func _on_hud_message_timer_timeout() -> void:
	_hud_status_message = ""
	_update_and_publish_hud_data()

## 显示重启确认对话框的逻辑
func _show_restart_confirmation() -> void:
	# 实例化专用的对话框场景
	var dialog: RestartConfirmDialog = RestartConfirmDialogScene.instantiate()
	
	# 1. 连接“从书签重启”的清晰信号
	dialog.restart_from_bookmark.connect(_on_restart_from_bookmark_confirmed)
	
	# 2. 连接“作为新游戏重启”的清晰信号
	dialog.restart_as_new_game.connect(_on_restart_as_new_game_confirmed)
	
	# 3. 连接“被取消”的清晰信号
	dialog.dismissed.connect(func():
		# 如果对话框被取消，我们只需要重新显示暂停菜单即可
		if get_tree().paused and state_machine.current_state_name != State.GAME_OVER:
			ui_manager.show_pause_menu()
	)
	
	# 当对话框从场景树中退出时（无论如何关闭），都确保它被正确释放
	dialog.tree_exited.connect(dialog.queue_free)
	
	ui_manager.close_current_ui() # 关闭暂停菜单
	ui_manager._canvas_layer.add_child(dialog)
	dialog.popup_centered()

## 响应对话框发出的“从书签重启”信号。
func _on_restart_from_bookmark_confirmed() -> void:
	get_tree().paused = false
	GlobalGameManager.selected_bookmark_data = _loaded_bookmark_data
	get_tree().reload_current_scene()

## 响应对话框发出的“作为新游戏重启”信号。
func _on_restart_as_new_game_confirmed() -> void:
	get_tree().paused = false
	var new_seed = int(Time.get_unix_time_from_system())
	
	var current_scene_resource: PackedScene = load(get_tree().current_scene.scene_file_path)
	
	GlobalGameManager.select_mode_and_start(
		_loaded_bookmark_data.mode_config_path,
		current_scene_resource,
		_loaded_bookmark_data.board_snapshot.get("grid_size", 4),
		new_seed
	)
