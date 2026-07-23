## GameplayVisualWarmup: 在启动遮罩后预绘制游戏首轮会用到的 2D 原语。
##
## 节点保持可绘制但位于不透明启动背景之后，使 Godot 能在玩家第一次操作前准备
## 方块轮廓、浮字、折纸碎片和合并环等 CanvasItem 管线。
class_name GameplayVisualWarmup
extends Node2D


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://features/gameplay/scenes/components/tile.tscn")
const _TILE_VISUAL_THEME: TileVisualTheme = preload("res://features/themes/resources/themes/game/halftone_atlas_tile_visual_theme.tres")
const _FEEDBACK_PROFILE: GameBoardFeedbackProfile = preload(
	"res://features/themes/resources/themes/game/feedback/halftone_atlas_board_feedback_profile.tres"
)
const _INK_COLOR: Color = Color(0.19215687, 0.2, 0.21568628, 1.0)
const _PAPER_COLOR: Color = Color(0.95686275, 0.94509804, 0.9098039, 1.0)
const _WARMUP_COLORS: Array[Color] = [
	Color(0.95686275, 0.94509804, 0.9098039, 1.0),
	Color(0.9019608, 0.827451, 0.4627451, 1.0),
	Color(0.8156863, 0.6392157, 0.39607844, 1.0),
	Color(0.79607844, 0.5176471, 0.39607844, 1.0),
	Color(0.65882355, 0.34117648, 0.30980393, 1.0),
	Color(0.32156864, 0.42352942, 0.42352942, 1.0),
]


# --- 私有变量 ---

var _primed: bool = false


# --- 公共方法 ---

func prime() -> void:
	if _primed:
		return
	_primed = true
	z_index = -1000
	position = Vector2(24.0, 24.0)

	for index: int in range(_TILE_VISUAL_THEME.family_styles.size()):
		var style: TileVisualFamilyStyle = _TILE_VISUAL_THEME.family_styles[index]
		if style == null:
			continue
		var tile_value: Node = _TILE_SCENE.instantiate()
		if not tile_value is Tile:
			if is_instance_valid(tile_value):
				tile_value.queue_free()
			continue
		var tile: Tile = tile_value
		add_child(tile)
		tile.position = Vector2(float(index % 3) * 104.0, floorf(float(index) / 3.0) * 104.0)
		var layers: Array[StringName] = [&"tile.visual_trait.classic_merge"]
		if index > 1:
			layers.append(&"tile.visual_trait.fibonacci_merge")
		tile.setup(
			2 << index,
			&"tile.warmup",
			_WARMUP_COLORS[index % _WARMUP_COLORS.size()],
			_INK_COLOR if index < 4 else _PAPER_COLOR,
			style.family_id,
			layers,
			style
		)

	var feedback_canvas: BoardFeedbackCanvas = BoardFeedbackCanvas.new()
	feedback_canvas.name = "FeedbackWarmup"
	add_child(feedback_canvas)
	var budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(
		GameAccessibilityState.new()
	)
	var turn_recipe: GameFeedbackRecipe = _FEEDBACK_PROFILE.high_merge_recipe
	var _turn_primitives: int = feedback_canvas.play_turn_impact(
		Rect2(Vector2.ZERO, Vector2(312.0, 208.0)),
		Vector2.RIGHT,
		3,
		mini(turn_recipe.edge_fragment_count, budget.max_edge_fragments),
		turn_recipe.accent_color,
		(turn_recipe.impact_duration + turn_recipe.settle_duration + 0.07)
		* budget.duration_scale,
		budget.motion_scale
	)
	var tile_recipe: GameFeedbackRecipe = _FEEDBACK_PROFILE.tile_merge_recipe
	var _burst_primitives: int = feedback_canvas.play_tile_burst(
		Vector2(156.0, 104.0),
		&"merge",
		"128",
		tile_recipe.accent_color,
		mini(tile_recipe.tile_shard_count, budget.max_tile_shards),
		tile_recipe.tile_burst_duration * budget.duration_scale,
		budget.motion_scale,
		budget.max_active_bursts
	)


func is_primed() -> bool:
	return _primed
