## GameHintResult: 一次只读棋盘提示查询的可审计结果。
##
## 结果只描述建议，不携带命令，也不能直接修改棋盘。调用方必须在展示前再次
## 比对 snapshot_id，避免把过期分析呈现为当前棋盘建议。
class_name GameHintResult
extends RefCounted


# --- 常量 ---

const TERMINATION_COMPLETED: StringName = &"completed"
const TERMINATION_INVALID_SNAPSHOT: StringName = &"invalid_snapshot"
const TERMINATION_CANCELLED: StringName = &"cancelled"
const TERMINATION_TIME_LIMIT: StringName = &"time_limit_exceeded"
const TERMINATION_STEP_LIMIT: StringName = &"step_limit_exceeded"


# --- 公共变量 ---

## 被分析棋盘的稳定语义摘要。
var snapshot_id: String = ""

## 固定为四向单位向量之一。
var suggested_direction: Vector2i = Vector2i.UP

## 决定当前建议的主要评分因素。
var primary_factor: StringName = &"deterministic_fallback"

## 面向玩家的简短、非教学式解释。
var explanation: String = ""

## GFExecutionBudget 记录的查询耗时。
var elapsed_msec: int = 0

## 实际进入方向评分的棋盘节点数。
var nodes_evaluated: int = 0

## completed、预算违规原因、cancelled 或 invalid_snapshot。
var termination_reason: StringName = TERMINATION_INVALID_SNAPSHOT

## 被选方向的结构化评分组成。
var factor_scores: Dictionary = {}

## 四个方向的总分，key 为 up / left / right / down。
var direction_scores: Dictionary = {}


# --- 公共方法 ---

## 当前建议是否为可接受的四向单位向量。
func is_cardinal_direction() -> bool:
	return (
		suggested_direction == Vector2i.UP
		or suggested_direction == Vector2i.DOWN
		or suggested_direction == Vector2i.LEFT
		or suggested_direction == Vector2i.RIGHT
	)


## 当前结果是否仍对应调用方刚刚读取的棋盘快照。
## @param current_snapshot_id: 调用方当前棋盘快照的稳定标识。
func is_fresh_for(current_snapshot_id: String) -> bool:
	return (
		not snapshot_id.is_empty()
		and not current_snapshot_id.is_empty()
		and snapshot_id == current_snapshot_id
	)


## 结果是否可安全显示。
##
## 取消和无效输入不产生玩家可见建议；步数或时间预算终止可以显示明确标注的
## 部分结果。所有情况都必须通过 freshness 校验。
## @param current_snapshot_id: 调用方当前棋盘快照的稳定标识。
func can_display_for(current_snapshot_id: String) -> bool:
	if not is_fresh_for(current_snapshot_id) or not is_cardinal_direction():
		return false
	return termination_reason in [
		TERMINATION_COMPLETED,
		TERMINATION_TIME_LIMIT,
		TERMINATION_STEP_LIMIT,
	]


## 返回便于测试、日志和调试工具读取的无共享容器快照。
func to_dict() -> Dictionary:
	return {
		&"snapshot_id": snapshot_id,
		&"suggested_direction": suggested_direction,
		&"primary_factor": primary_factor,
		&"explanation": explanation,
		&"elapsed_msec": elapsed_msec,
		&"nodes_evaluated": nodes_evaluated,
		&"termination_reason": termination_reason,
		&"factor_scores": factor_scores.duplicate(true),
		&"direction_scores": direction_scores.duplicate(true),
	}
