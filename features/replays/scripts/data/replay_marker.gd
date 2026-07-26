## ReplayMarker: 回放浏览器中的稳定事件索引。
##
## 标记只引用 0..total_steps 的命令历史步数，不持有或恢复玩法模型快照。
## 事件标记只消费当前 checkpoint 的强类型 TurnResult 摘要，不猜测旧版语义。
class_name ReplayMarker
extends RefCounted


# --- 枚举 ---

enum Kind {
	MERGE,
	CHAIN_OR_TRANSFORM,
	MILESTONE,
	FAILURE,
	OOS,
}


# --- 公共变量 ---

var marker_id: StringName = &""
var kind: Kind = Kind.MERGE
var step_index: int = 0
var score_delta: int = 0
var merge_count: int = 0
var transform_count: int = 0
var ratio_resolution_count: int = 0
var milestone_value: int = 0
var details: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init(
	p_kind: Kind = Kind.MERGE,
	p_step_index: int = 0,
	p_marker_id: StringName = &""
) -> void:
	kind = p_kind
	step_index = maxi(p_step_index, 0)
	marker_id = p_marker_id


# --- 公共方法 ---

## 从持久化回放与可选首个 OOS 报告构建唯一、稳定排序的标记目录。
## @param replay_data: 已通过严格校验的当前回放数据。
## @param oos_report: 可选的首个回放偏离诊断报告。
static func build_catalog(
	replay_data: ReplayData,
	oos_report: Dictionary = {}
) -> Array[ReplayMarker]:
	var result: Array[ReplayMarker] = []
	if not is_instance_valid(replay_data):
		return result

	var previous_score: int = 0
	var previous_target_reached: bool = false
	for index: int in range(replay_data.checkpoints.size()):
		var checkpoint: ReplayCheckpoint = replay_data.checkpoints[index]
		if not is_instance_valid(checkpoint):
			continue
		var marker_step: int = index + 1
		var turn_score_delta: int = maxi(checkpoint.score - previous_score, 0)
		var turn_merge_count: int = checkpoint.merge_count
		var turn_transform_count: int = checkpoint.transform_count
		var turn_ratio_resolution_count: int = checkpoint.ratio_resolution_count
		if not checkpoint.metadata_available:
			previous_score = checkpoint.score
			continue

		if turn_merge_count > 0:
			var merge_marker: ReplayMarker = _make_marker(Kind.MERGE, marker_step)
			merge_marker.score_delta = turn_score_delta
			merge_marker.merge_count = turn_merge_count
			result.append(merge_marker)

		if (
			turn_merge_count > 1
			or turn_transform_count > 0
			or turn_ratio_resolution_count > 0
		):
			var chain_marker: ReplayMarker = _make_marker(
				Kind.CHAIN_OR_TRANSFORM,
				marker_step
			)
			chain_marker.merge_count = turn_merge_count
			chain_marker.transform_count = turn_transform_count
			chain_marker.ratio_resolution_count = turn_ratio_resolution_count
			result.append(chain_marker)

		if checkpoint.target_reached and not previous_target_reached:
			var target_marker: ReplayMarker = _make_marker(
				Kind.MILESTONE,
				marker_step
			)
			target_marker.milestone_value = checkpoint.highest_tile
			result.append(target_marker)
		previous_target_reached = checkpoint.target_reached

		previous_score = checkpoint.score

	if not replay_data.actions.is_empty():
		result.append(_make_marker(Kind.FAILURE, replay_data.actions.size()))

	if not oos_report.is_empty():
		var oos_step: int = clampi(
			GFVariantData.get_option_int(oos_report, &"step_index", 0),
			0,
			replay_data.actions.size()
		)
		var oos_marker: ReplayMarker = _make_marker(Kind.OOS, oos_step)
		oos_marker.details = oos_report.duplicate(true)
		result.append(oos_marker)

	result.sort_custom(_sort_markers)
	return _deduplicate(result)


## 统计标记目录中指定类型的条目数量。
## @param markers: 要统计的回放标记目录。
## @param marker_kind: 要匹配的回放标记类型。
static func count_by_kind(markers: Array[ReplayMarker], marker_kind: Kind) -> int:
	var count: int = 0
	for marker: ReplayMarker in markers:
		if is_instance_valid(marker) and marker.kind == marker_kind:
			count += 1
	return count


# --- 私有/辅助方法 ---

static func _make_marker(marker_kind: Kind, marker_step: int) -> ReplayMarker:
	return ReplayMarker.new(
		marker_kind,
		marker_step,
		StringName("%d:%d" % [marker_step, marker_kind])
	)


static func _sort_markers(left: ReplayMarker, right: ReplayMarker) -> bool:
	if left.step_index != right.step_index:
		return left.step_index < right.step_index
	return left.kind < right.kind


static func _deduplicate(markers: Array[ReplayMarker]) -> Array[ReplayMarker]:
	var result: Array[ReplayMarker] = []
	var seen_ids: Dictionary = {}
	for marker: ReplayMarker in markers:
		if not is_instance_valid(marker) or marker.marker_id == &"":
			continue
		if seen_ids.has(marker.marker_id):
			continue
		seen_ids[marker.marker_id] = true
		result.append(marker)
	return result
