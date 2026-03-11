# scripts/events/game_ready_data.gd

## GameReadyData: 游戏初始化完成时发出的事件数据载体。
##
## 该数据包含了所有 GamePlay 视窗需要配置表现层的核心规则、参数与模型状态。
class_name GameReadyData
extends RefCounted

var mode_config: GameModeConfig
var interaction_rule: InteractionRule
var movement_rule: MovementRule
var game_over_rule: GameOverRule
var all_spawn_rules: Array[SpawnRule] = []

var current_grid_size: int = 4
var initial_high_score: int = 0
var initial_seed: int = 0

var is_replay_mode: bool = false
var loaded_bookmark_data: BookmarkData = null
var replay_data_resource: ReplayData = null
