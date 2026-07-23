## GameBoardFeedbackProfile: 主题拥有的完整反馈配方集合。
class_name GameBoardFeedbackProfile
extends Resource


# --- 常量 ---

const TIER_MOVE: StringName = &"move"
const TIER_MERGE: StringName = &"merge"
const TIER_HIGH_MERGE: StringName = &"high_merge"
const TIER_RECORD: StringName = &"record"
const TILE_SPAWN: StringName = &"spawn"
const TILE_MERGE: StringName = &"merge"
const TILE_TRANSFORM: StringName = &"transform"


# --- 导出变量 ---

@export var move_recipe: GameFeedbackRecipe
@export var turn_merge_recipe: GameFeedbackRecipe
@export var high_merge_recipe: GameFeedbackRecipe
@export var record_recipe: GameFeedbackRecipe
@export var spawn_recipe: GameFeedbackRecipe
@export var tile_merge_recipe: GameFeedbackRecipe
@export var transform_recipe: GameFeedbackRecipe


# --- 公共方法 ---

## 获取一次完整回合的语义反馈配方。
## @param tier_id: `TIER_*` 常量之一。
func get_turn_recipe(tier_id: StringName) -> GameFeedbackRecipe:
	match tier_id:
		TIER_MOVE:
			return move_recipe
		TIER_MERGE:
			return turn_merge_recipe
		TIER_HIGH_MERGE:
			return high_merge_recipe
		TIER_RECORD:
			return record_recipe
		_:
			return null


## 获取单方块生成、合并或转化反馈配方。
## @param feedback_type: `TILE_*` 常量之一。
func get_tile_recipe(feedback_type: StringName) -> GameFeedbackRecipe:
	match feedback_type:
		TILE_SPAWN:
			return spawn_recipe
		TILE_MERGE:
			return tile_merge_recipe
		TILE_TRANSFORM:
			return transform_recipe
		_:
			return null


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameBoardFeedbackProfile",
		{"resource_path": resource_path}
	)
	_validate_turn_recipe(report, TIER_MOVE, move_recipe)
	_validate_turn_recipe(report, TIER_MERGE, turn_merge_recipe)
	_validate_turn_recipe(report, TIER_HIGH_MERGE, high_merge_recipe)
	_validate_turn_recipe(report, TIER_RECORD, record_recipe)
	_validate_tile_recipe(report, TILE_SPAWN, spawn_recipe)
	_validate_tile_recipe(report, TILE_MERGE, tile_merge_recipe)
	_validate_tile_recipe(report, TILE_TRANSFORM, transform_recipe)
	return report


# --- 私有/辅助方法 ---

func _validate_turn_recipe(
	report: GFValidationReport,
	semantic_id: StringName,
	recipe: GameFeedbackRecipe
) -> void:
	_validate_recipe(report, semantic_id, recipe)
	if recipe == null:
		return
	if recipe.shake_preset == null:
		_add_error(report, &"missing_shake_preset", semantic_id)
	elif recipe.shake_preset.get_duration_seconds() <= 0.0:
		_add_error(report, &"invalid_shake_duration", semantic_id)
	if recipe.haptic_preset == null:
		_add_error(report, &"missing_haptic_preset", semantic_id)
	elif recipe.haptic_preset.get_duration_seconds() <= 0.0:
		_add_error(report, &"invalid_haptic_duration", semantic_id)


func _validate_tile_recipe(
	report: GFValidationReport,
	semantic_id: StringName,
	recipe: GameFeedbackRecipe
) -> void:
	_validate_recipe(report, semantic_id, recipe)


func _validate_recipe(
	report: GFValidationReport,
	semantic_id: StringName,
	recipe: GameFeedbackRecipe
) -> void:
	if recipe == null:
		_add_error(report, &"missing_feedback_recipe", semantic_id)
		return
	if not recipe.is_valid_recipe():
		_add_error(report, &"invalid_feedback_recipe", semantic_id)


func _add_error(
	report: GFValidationReport,
	kind: StringName,
	semantic_id: StringName
) -> void:
	var _issue: RefCounted = report.add_error(
		kind,
		"反馈语义缺少有效完整配方：%s。" % String(semantic_id),
		semantic_id,
		resource_path
	)
