## TurnResult: 一次有效玩家回合的唯一强类型业务结果。
##
## 规则、撤销、回放校验与表现层都消费该对象，不再从字符串字典反推回合语义。
class_name TurnResult
extends "res://addons/gf/kernel/base/gf_payload.gd"


# --- 公共变量 ---

var direction: Vector2i = Vector2i.ZERO
var moved_lanes: Array = []
var movements: Array[TileMovementResult] = []
var merges: Array[TileMergeResult] = []
var spawns: Array[TileSpawnResult] = []
var transforms: Array[TileTransformResult] = []
var score_delta: int = 0
var ratio_resolution_count: int = 0
var max_merge_value: int = 0


# --- 公共方法 ---

func is_effective() -> bool:
	return direction != Vector2i.ZERO and (not movements.is_empty() or not merges.is_empty())


## 聚合一个有效合并及其分数、统计与最大值。
## @param result: 已通过交互规则验证的合并结果。
func add_merge(result: TileMergeResult) -> void:
	if result == null or not result.is_valid_result():
		return
	merges.append(result)
	score_delta += result.interaction.score_delta
	ratio_resolution_count += result.interaction.ratio_resolution_count
	max_merge_value = maxi(max_merge_value, result.interaction.survivor.value)


## 追加一次确定性生成结果。
## @param result: 已提交到棋盘的生成结果。
func add_spawn(result: TileSpawnResult) -> void:
	if result != null and result.is_valid_result():
		spawns.append(result)


## 追加一次既有方块重组或强化结果。
## @param result: 已提交到棋盘的转化结果。
func add_transform(result: TileTransformResult) -> void:
	if result != null and result.is_valid_result():
		transforms.append(result)


func get_reverse_target_map() -> Dictionary:
	var result: Dictionary = {}
	for movement: TileMovementResult in movements:
		if movement != null and movement.is_valid_result():
			result[_cell_key(movement.from_cell)] = movement.to_cell
	for merge: TileMergeResult in merges:
		if merge == null or not merge.is_valid_result():
			continue
		result[_cell_key(merge.consumed_from_cell)] = merge.to_cell
		result[_cell_key(merge.survivor_from_cell)] = merge.to_cell
	return result


# --- 私有/辅助方法 ---

static func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
