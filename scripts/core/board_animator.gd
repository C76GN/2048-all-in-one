# scripts/core/board_animator.gd

## BoardAnimator: 游戏棋盘动画的专属播放器。
##
## 该节点负责接收一个包含动画指令的列表，并根据这些指令创建、
## 播放和管理所有的视觉动画（Tweens）。它将动画表现与游戏逻辑
## (GameBoard) 完全解耦。动画播放完成后，它会发出信号通知逻辑层
## 可以继续执行下一步操作。
class_name BoardAnimator
extends Node

var _active_tweens: Dictionary = {}

## 播放一个包含多条动画指令的序列，支持中断和重定向。
func play_animation_sequence(instructions: Array) -> void:
	var tiles_to_consume: Array[Tile] = []

	# 1. 分离出需要立即处理的指令 (SPAWN)
	for instruction in instructions:
		if instruction.type == "SPAWN":
			var tile: Tile = instruction.tile
			tile.animate_spawn()

	# 2. 处理 MOVE 和 MERGE 指令
	for instruction in instructions:
		var tile: Tile
		var target_pos: Vector2

		match instruction.type:
			"MOVE":
				tile = instruction.tile
				target_pos = instruction.to_pos

			"MERGE":
				# 对于合并，我们有两个动画要处理：
				# a) 被消耗的方块移动到目标位置
				var consumed: Tile = instruction.consumed_tile
				var merged: Tile = instruction.merged_tile
				target_pos = instruction.to_pos

				# 确保 consumed_tile 是有效的实例
				if is_instance_valid(consumed):
					_retarget_animation(consumed, target_pos)
					# 将其加入待清理列表
					tiles_to_consume.append(consumed)

				# b) 合并后存活的方块也要处理，因为它可能也在移动
				tile = merged
				# 触发合并的视觉效果
				tile.animate_merge()

			_:
				continue # 跳过非移动/合并指令

		# 确保 tile 是有效的实例
		if is_instance_valid(tile):
			_retarget_animation(tile, target_pos)

	# 3. 安全地清理被消耗的方块
	# 不能立即 queue_free，必须等待它们的移动动画结束。
	for tile in tiles_to_consume:
		if is_instance_valid(tile):
			# 获取该方块的最新动画
			var tile_tween = _active_tweens.get(tile.get_instance_id())
			if is_instance_valid(tile_tween):
				# 等待这个特定方块的动画完成后，再安全释放它
				await tile_tween.finished
				if is_instance_valid(tile):
					tile.queue_free()

## 核心的重定向函数
func _retarget_animation(tile: Node2D, new_target_pos: Vector2) -> void:
	var instance_id = tile.get_instance_id()

	# 如果这个方块已经有一个正在播放的动画，先停止它
	if _active_tweens.has(instance_id):
		var old_tween = _active_tweens[instance_id]
		if is_instance_valid(old_tween):
			old_tween.kill() # kill() 会立即停止动画

	# 创建一个新的 Tween，从方块的 *当前* 视觉位置开始
	var new_tween = create_tween()
	# new_tween.tween_property(tile, "position", new_target_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	new_tween.tween_property(tile, "position", new_target_pos, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 记录这个新的 Tween
	_active_tweens[instance_id] = new_tween

	# 动画完成后，从字典中移除，避免内存泄漏
	new_tween.finished.connect(func():
		if _active_tweens.has(instance_id) and _active_tweens[instance_id] == new_tween:
			_active_tweens.erase(instance_id)
	)
