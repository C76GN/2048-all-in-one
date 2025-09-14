# main.gd
# (阶段四：引入怪物生成机制)
extends Node2D

const TileScene = preload("res://scenes/tile.tscn")

const GRID_SIZE: int = 4
const CELL_SIZE: int = 100
const SPACING: int = 15

# --- 新增：计时器和怪物逻辑的配置 ---
const INITIAL_SPAWN_INTERVAL: float = 2.0 # 初始生成间隔（秒）
const MIN_TIME_BONUS: float = 0.5 # 最小时间奖励
const TIME_BONUS_DECAY_FACTOR: float = 5.0 # 时间奖励衰减系数

var grid = []
var move_count: int = 0 # 记录有效移动次数
var monster_spawn_timer: Timer # 怪物生成计时器

# --- 新增：UI节点引用 ---
@onready var board_container: Node2D = $BoardContainer
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var timer_label: Label = $Label


func _ready() -> void:
	_initialize_grid()
	_draw_board()
	_center_board()
	
	# 初始化怪物计时器
	_setup_monster_timer()
	
	# 初始生成2个玩家方块
	_spawn_tile()
	_spawn_tile()

# 新增：Godot的 _process 函数每帧都会被调用
func _process(delta: float) -> void:
	# 在这里持续更新UI，让玩家看到倒计时
	if monster_spawn_timer != null:
		progress_bar.max_value = monster_spawn_timer.wait_time
		progress_bar.value = monster_spawn_timer.time_left
		timer_label.text = "Spawning monster in: %.1f s" % monster_spawn_timer.time_left

func _unhandled_input(event: InputEvent) -> void:
	var direction = Vector2i.ZERO
	if event.is_action_pressed("move_up"): direction = Vector2i.UP
	elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
	elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
	elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT
	
	if direction != Vector2i.ZERO:
		_handle_move(direction)

# --- 计时器与生成逻辑 ---

func _setup_monster_timer() -> void:
	monster_spawn_timer = Timer.new()
	monster_spawn_timer.wait_time = INITIAL_SPAWN_INTERVAL
	monster_spawn_timer.one_shot = false # 让它可以重复触发
	monster_spawn_timer.timeout.connect(_on_monster_timer_timeout) # 关键：连接信号
	add_child(monster_spawn_timer)
	monster_spawn_timer.start()

func _on_monster_timer_timeout() -> void:
	# 计时器归零时，生成一个怪物！
	_spawn_monster()
	# 重置计时器的时间（虽然它会自动重启，但我们可以动态改变下一次的 wait_time）
	monster_spawn_timer.wait_time = INITIAL_SPAWN_INTERVAL

func _spawn_tile() -> void:
	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty(): return
	
	var spawn_pos: Vector2i = empty_cells.pick_random()
	var new_tile = TileScene.instantiate()
	
	board_container.add_child(new_tile)
	grid[spawn_pos.x][spawn_pos.y] = new_tile
	new_tile.position = _grid_to_pixel(spawn_pos)
	# 调用新的 setup 函数，明确类型为 PLAYER
	new_tile.setup(2, new_tile.TileType.PLAYER)

func _spawn_monster() -> void:
	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty(): return

	# 1. 计算要生成的怪物数值
	var monster_value = _calculate_monster_value()
	
	# 2. 生成怪物
	var spawn_pos: Vector2i = empty_cells.pick_random()
	var new_monster = TileScene.instantiate()
	
	board_container.add_child(new_monster)
	grid[spawn_pos.x][spawn_pos.y] = new_monster
	new_monster.position = _grid_to_pixel(spawn_pos)
	# 调用 setup 函数，类型为 MONSTER
	new_monster.setup(monster_value, new_monster.TileType.MONSTER)

# 新增：实现您设计的怪物数值概率算法
func _calculate_monster_value() -> int:
	# a. 找到当前玩家拥有的最大数值
	var max_player_value = 0
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER and tile.value > max_player_value:
				max_player_value = tile.value
	
	if max_player_value <= 0: return 2 # 如果场上没玩家方块了，就生成2

	# b. 计算 k (max_value = 2^k)
	var k = int(log(max_player_value) / log(2))
	if k < 1: k = 1
	
	# c. 构建概率权重数组
	var weights = []
	var possible_values = []
	for i in range(1, k + 1):
		possible_values.append(pow(2, i))
		weights.append(k - i + 1)
	
	# d. 根据权重随机选择一个值
	var total_weight = weights.reduce(func(acc, w): return acc + w, 0)
	var random_pick = randi_range(1, total_weight)
	
	var cumulative_weight = 0
	for i in weights.size():
		cumulative_weight += weights[i]
		if random_pick <= cumulative_weight:
			return possible_values[i]
			
	return 2 # 备用，理论上不会执行到

# --- 核心移动逻辑 (有修改) ---

func _handle_move(direction: Vector2i) -> void:
	var moved = false
	# ... (此函数前半部分不变) ...
	var grid_copy_for_move = _get_rotated_grid(direction)
	var new_grid_after_move = []
	for row_index in GRID_SIZE:
		var current_row = grid_copy_for_move[row_index]
		var result = _process_line(current_row)
		var processed_row = result[0]
		var has_moved_in_row = result[1]
		new_grid_after_move.append(processed_row)
		if has_moved_in_row:
			moved = true
	
	if moved:
		move_count += 1
		var time_to_add = MIN_TIME_BONUS + TIME_BONUS_DECAY_FACTOR / move_count
		monster_spawn_timer.start(monster_spawn_timer.time_left + time_to_add)

		grid = _unrotate_grid(new_grid_after_move, direction)
		_update_board_visuals()
		await get_tree().create_timer(0.1).timeout
		_spawn_tile()
		_check_game_over() # <--- 在移动和生成后检查游戏状态
	else:
		# 如果玩家尝试移动但棋盘状态没变，也检查一下是否是死局
		_check_game_over()


# --- 其余函数 (基本无变化) ---

func _initialize_grid(): # ...
	grid.resize(GRID_SIZE)
	for x in GRID_SIZE:
		grid[x] = []
		grid[x].resize(GRID_SIZE)
		grid[x].fill(null)

func _draw_board(): # ...
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var cell_bg = ColorRect.new()
			cell_bg.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell_bg.position = _grid_to_pixel(Vector2i(x, y))
			cell_bg.color = Color("8f8f8f")
			board_container.add_child(cell_bg)

func _center_board(): # ...
	var viewport_size = get_viewport_rect().size
	var board_total_size = (GRID_SIZE * CELL_SIZE) + (GRID_SIZE - 1) * SPACING
	var top_left_position = (viewport_size - Vector2(board_total_size, board_total_size)) / 2.0
	board_container.position = top_left_position

func _get_empty_cells() -> Array: # 抽离成独立函数
	var empty_cells = []
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if grid[x][y] == null:
				empty_cells.append(Vector2i(x, y))
	return empty_cells

func _get_rotated_grid(direction: Vector2i) -> Array: # ...
	var rotated_grid = []
	rotated_grid.resize(GRID_SIZE)
	for i in GRID_SIZE:
		var line = []
		for j in GRID_SIZE:
			match direction:
				Vector2i.LEFT: line.append(grid[j][i])
				Vector2i.RIGHT: line.append(grid[GRID_SIZE - 1 - j][i])
				Vector2i.UP: line.append(grid[i][j])
				Vector2i.DOWN: line.append(grid[i][GRID_SIZE - 1 - j])
		rotated_grid[i] = line
	return rotated_grid

func _unrotate_grid(rotated_grid: Array, direction: Vector2i) -> Array: # ...
	var new_grid = []
	new_grid.resize(GRID_SIZE)
	for i in GRID_SIZE: new_grid[i] = []; new_grid[i].resize(GRID_SIZE)
	for i in GRID_SIZE:
		for j in GRID_SIZE:
			match direction:
				Vector2i.LEFT: new_grid[j][i] = rotated_grid[i][j]
				Vector2i.RIGHT: new_grid[GRID_SIZE - 1 - j][i] = rotated_grid[i][j]
				Vector2i.UP: new_grid[i][j] = rotated_grid[i][j]
				Vector2i.DOWN: new_grid[i][GRID_SIZE - 1 - j] = rotated_grid[i][j]
	return new_grid

# 处理单行/单列的核心算法 (战斗升级版)
func _process_line(line: Array) -> Array:
	# 1. 滑动：移除所有空格(null)
	var slid_line = []
	for tile in line:
		if tile != null:
			slid_line.append(tile)
	
	# 2. 合并与战斗
	var merged_line = []
	var i = 0
	while i < slid_line.size():
		var current_tile = slid_line[i]
		
		# 检查是否有下一个方块可供碰撞
		if i + 1 < slid_line.size():
			var next_tile = slid_line[i+1]
			
			# 分情况讨论碰撞
			if current_tile.type == next_tile.type:
				# --- 情况A: 同类碰撞 (玩家+玩家 或 怪物+怪物) ---
				if current_tile.value == next_tile.value:
					# 数值相等，合并
					next_tile.setup(current_tile.value * 2, current_tile.type)
					merged_line.append(next_tile)
					current_tile.queue_free() # 删除被合并的
					i += 2 # 跳过两个方块
					continue
			else:
				# --- 情况B: 异类碰撞 (玩家 vs 怪物) ---
				var player_tile = current_tile if current_tile.type == current_tile.TileType.PLAYER else next_tile
				var monster_tile = current_tile if current_tile.type == current_tile.TileType.MONSTER else next_tile
				
				if player_tile.value > monster_tile.value:
					# 玩家胜：玩家数值变为 P/M，怪物消失
					var new_value = int(player_tile.value / monster_tile.value)
					player_tile.setup(new_value, player_tile.type)
					merged_line.append(player_tile)
					monster_tile.queue_free()
				elif player_tile.value < monster_tile.value:
					# 怪物胜：怪物数值变为 M/P，玩家消失
					var new_value = int(monster_tile.value / player_tile.value)
					monster_tile.setup(new_value, monster_tile.type)
					merged_line.append(monster_tile)
					player_tile.queue_free()
				else: # player_tile.value == monster_tile.value
					# 同归于尽：双方都消失
					player_tile.queue_free()
					monster_tile.queue_free()
				
				i += 2 # 跳过两个方块
				continue

		# 如果没有发生碰撞或合并，直接将当前方块加入结果
		merged_line.append(current_tile)
		i += 1

	# 3. 填充
	var result_line = merged_line.duplicate()
	while result_line.size() < GRID_SIZE:
		result_line.append(null)
	
	# 4. 判断是否发生了移动 (逻辑不变)
	var has_moved = false
	if result_line.size() != line.size(): has_moved = true
	else:
		for idx in result_line.size():
			if (result_line[idx] == null and line[idx] != null) or \
			   (result_line[idx] != null and line[idx] == null) or \
			   (result_line[idx] != null and line[idx] != null and result_line[idx].get_instance_id() != line[idx].get_instance_id()):
				has_moved = true
				break
				
	return [result_line, has_moved]

func _update_board_visuals(): # ...
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if grid[x][y] != null:
				var tile = grid[x][y]
				tile.position = _grid_to_pixel(Vector2i(x, y))

func _grid_to_pixel(grid_pos: Vector2i) -> Vector2: # ...
	return Vector2(grid_pos.x * (CELL_SIZE + SPACING), grid_pos.y * (CELL_SIZE + SPACING))

# --- 新增：游戏结束判断 ---
func _check_game_over() -> void:
	# 1. 检查胜利条件 (合成4096)
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var tile = grid[x][y]
			if tile != null and tile.type == tile.TileType.PLAYER and tile.value >= 4096:
				print("YOU WIN!") # 打印胜利信息到控制台
				timer_label.text = "YOU WIN!"
				get_tree().paused = true # 暂停整个游戏
				return

	# 2. 检查失败条件 (棋盘已满且无法移动)
	if _get_empty_cells().is_empty():
		# 棋盘满了，我们还需要检查是否还有任何可能的合并
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				var current_tile = grid[x][y]
				# 检查右边是否有可合并/战斗
				if x + 1 < GRID_SIZE:
					var right_tile = grid[x+1][y]
					if current_tile.type != right_tile.type or current_tile.value == right_tile.value:
						return # 找到了一个可能的移动，游戏没结束
				# 检查下边是否有可合并/战斗
				if y + 1 < GRID_SIZE:
					var down_tile = grid[x][y+1]
					if current_tile.type != down_tile.type or current_tile.value == down_tile.value:
						return # 找到了一个可能的移动，游戏没结束
		
		# 如果循环跑完都没找到任何可移动的组合，游戏失败
		print("GAME OVER!")
		timer_label.text = "GAME OVER!"
		get_tree().paused = true # 暂停整个游戏
