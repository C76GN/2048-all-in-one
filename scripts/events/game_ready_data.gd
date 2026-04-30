## GameReadyData: 游戏初始化完成时发出的事件数据载体。
##
## 该数据包含了所有 GamePlay 视窗需要配置表现层的核心规则、参数与模型状态。
class_name GameReadyData
extends GFPayload


# --- 公共变量 ---

## 当前游戏模式配置。
var mode_config: GameModeConfig

## 当前对局使用的交互规则实例。
var interaction_rule: InteractionRule

## 当前对局使用的移动规则实例。
var movement_rule: MovementRule

## 当前对局使用的结束判定规则实例。
var game_over_rule: GameOverRule

## 当前对局注册到 RuleSystem 的生成规则实例列表。
var all_spawn_rules: Array[SpawnRule] = []

## 当前棋盘尺寸。
var current_grid_size: int = 4

## 当前模式与棋盘尺寸对应的历史最高分。
var initial_high_score: int = 0

## 当前对局初始随机种子。
var initial_seed: int = 0

## 是否为回放模式。
var is_replay_mode: bool = false

## 从书签恢复时携带的书签数据。
var loaded_bookmark_data: BookmarkData = null

## 回放模式下携带的回放数据资源。
var replay_data_resource: ReplayData = null
