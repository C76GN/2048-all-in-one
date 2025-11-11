# scripts/core/board_animator.gd

## BoardAnimator: 游戏棋盘动画的专属播放器。
##
## 该节点负责接收一个包含动画指令的列表，并根据这些指令创建、
## 播放和管理所有的视觉动画（Tweens）。它将动画表现与游戏逻辑
## (GameBoard) 完全解耦。
class_name BoardAnimator
extends Node


# --- 私有变量 ---

## 一个字典，用于存储正在播放的动画，键是方块的实例ID，值是Tween对象。
var _active_tweens: Dictionary = {}


# --- 公共方法 ---

## 播放一个包含多条动画指令的序列，支持中断和重定向。
## @param instructions: 一个包含动画指令字典的数组。
func play_animation_sequence(instructions: Array) -> void:
	var tiles_to_consume: Array[Tile] = []

	for instruction in instructions:
		var current_instruction: Dictionary = instruction

		if current_instruction.type == "SPAWN":
			var tile: Tile = current_instruction.tile
			tile.animate_spawn()

	for instruction in instructions:
		var current_instruction: Dictionary = instruction
		var tile: Tile
		var target_pos: Vector2

		match current_instruction.type:
			"MOVE":
				tile = current_instruction.tile
				target_pos = current_instruction.to_pos

			"MERGE":
				var consumed: Tile = current_instruction.consumed_tile
				var merged: Tile = current_instruction.merged_tile
				target_pos = current_instruction.to_pos

				if is_instance_valid(consumed):
					_retarget_animation(consumed, target_pos)
					tiles_to_consume.append(consumed)

				tile = merged

				if is_instance_valid(tile):
					tile.animate_merge()

			_:
				continue

		if is_instance_valid(tile):
			_retarget_animation(tile, target_pos)

	for tile_to_free in tiles_to_consume:
		if is_instance_valid(tile_to_free):
			var tile_tween: Tween = _active_tweens.get(tile_to_free.get_instance_id())

			if is_instance_valid(tile_tween):
				await tile_tween.finished

				if is_instance_valid(tile_to_free):
					tile_to_free.queue_free()


# --- 私有/辅助方法 ---

## 核心的重定向函数，为一个方块创建或更新其移动动画。
## 如果一个方块已有一个移动动画在播放，此函数会平滑地中止旧动画并开始新动画。
## @param tile: 要执行动画的方块节点。
## @param new_target_pos: 新的目标位置。
func _retarget_animation(tile: Tile, new_target_pos: Vector2) -> void:
	var instance_id: int = tile.get_instance_id()

	if _active_tweens.has(instance_id):
		var old_tween: Tween = _active_tweens[instance_id]

		if is_instance_valid(old_tween):
			old_tween.kill()

	var new_tween: Tween = create_tween()
	new_tween.tween_property(tile, "position", new_target_pos, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tweens[instance_id] = new_tween

	new_tween.finished.connect(
		func():
			if _active_tweens.has(instance_id) and _active_tweens[instance_id] == new_tween:
				_active_tweens.erase(instance_id)
	)
