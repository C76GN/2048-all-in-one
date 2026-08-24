## GameplayVisualWarmup: 在启动遮罩后预绘制游戏首轮会用到的 2D 原语。
##
## 节点保持可绘制但位于不透明启动背景之后，使 Godot 能在玩家第一次操作前准备
## 方块轮廓、浮字、折纸碎片和合并环等 CanvasItem 管线。
class_name GameplayVisualWarmup
extends Node2D


# --- 常量 ---

const _TILE_SCENE: PackedScene = preload("res://features/themes/scenes/ui/tiles/tile.tscn")
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
var _tile_visual_theme: TileVisualTheme
var _feedback_profile: GameBoardFeedbackProfile
var _transition_materials: Array[ShaderMaterial] = []


# --- 公共方法 ---

## 配置预热需要的当前游戏主题资源。
## @param theme: 提供方块视觉、棋盘反馈与转场材质的已激活游戏主题。
func configure(theme: GameTheme) -> bool:
	if (
		not is_instance_valid(theme)
		or not is_instance_valid(theme.tile_visual_theme)
		or not is_instance_valid(theme.board_feedback_profile)
	):
		return false
	_tile_visual_theme = theme.tile_visual_theme
	_feedback_profile = theme.board_feedback_profile
	_transition_materials.clear()
	for effect: GFScreenTransitionEffect in [
		theme.scene_transition_cover_effect,
		theme.scene_transition_reveal_effect,
	]:
		if effect != null and is_instance_valid(effect.shader_material):
			_transition_materials.append(effect.shader_material)
	return true


func prime() -> void:
	if (
		_primed
		or not is_instance_valid(_tile_visual_theme)
		or not is_instance_valid(_feedback_profile)
	):
		return
	_primed = true
	z_index = -1000
	position = Vector2(24.0, 24.0)

	for index: int in range(_tile_visual_theme.family_styles.size()):
		var style: TileVisualFamilyStyle = _tile_visual_theme.family_styles[index]
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
	for shader_material: ShaderMaterial in _transition_materials:
		_add_canvas_material_probe(shader_material)

	var turn_recipe: GameFeedbackRecipe = _feedback_profile.high_merge_recipe
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
	var tile_recipe: GameFeedbackRecipe = _feedback_profile.tile_merge_recipe
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


# --- 私有/辅助方法 ---

func _add_canvas_material_probe(shader_material: ShaderMaterial) -> void:
	if not is_instance_valid(shader_material):
		return
	var probe: ColorRect = ColorRect.new()
	probe.name = "TransitionMaterialProbe"
	probe.position = Vector2(
		336.0 + float(_transition_materials.find(shader_material)) * 20.0,
		0.0
	)
	probe.size = Vector2(16.0, 16.0)
	probe.color = Color.WHITE
	probe.material = shader_material
	probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(probe)
