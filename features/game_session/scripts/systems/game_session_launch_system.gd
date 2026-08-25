## GameSessionLaunchSystem: 统一解析、验证并提交下一局启动状态。
##
## navigation、bookmarks 与 replays 只提交稳定值或 ID；本 System 在路由前
## 重新读取当前玩家目录并冻结独立副本，避免 UI Resource、持久化缓存与
## AppConfigModel 共享可变别名。
class_name GameSessionLaunchSystem
extends GameSessionLaunchPort


# --- 常量 ---

const GAME_SCENE_PATH: String = "res://features/game_session/scenes/game/game_play.tscn"


# --- 私有变量 ---

var _app_config: AppConfigModel = null
var _bookmark_system: BookmarkSystem = null
var _replay_system: ReplaySystem = null
var _scene_router: GameSceneRouterPort = null
var _mode_catalog: GameModeCatalogUtility = null
var _determinism: GameDeterminismUtility = null
var _seed_utility: GFSeedUtility = null


# --- GF 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [AppConfigModel]


func get_required_systems() -> Array[Script]:
	return [BookmarkSystem, ReplaySystem, GameSceneRouterPort]


func get_required_utilities() -> Array[Script]:
	return [GameModeCatalogUtility, GameDeterminismUtility, GFSeedUtility]


func ready() -> void:
	_app_config = _resolve_app_config_model()
	_bookmark_system = _resolve_bookmark_system()
	_replay_system = _resolve_replay_system()
	_scene_router = _resolve_scene_router()
	_mode_catalog = _resolve_mode_catalog()
	_determinism = _resolve_determinism_utility()
	_seed_utility = _resolve_seed_utility()
	if not _has_required_dependencies():
		push_error("[GameSessionLaunchSystem] 对局启动依赖不完整，所有启动请求将失败关闭。")


func dispose() -> void:
	_app_config = null
	_bookmark_system = null
	_replay_system = null
	_scene_router = null
	_mode_catalog = null
	_determinism = null
	_seed_utility = null


# --- 公共方法 ---

## 校验并提交一个新对局的冻结启动状态。
## @param mode_config_path: 待启动模式的稳定资源路径。
## @param board_topology_snapshot: 待复制并验证的棋盘拓扑快照。
## @param seed_value: 新对局使用的确定性随机种子。
## @param seed_source: 随机种子的规范来源标识。
## @param board_is_custom: 棋盘是否来自玩家自定义内容。
func launch_new_game(
	mode_config_path: String,
	board_topology_snapshot: Dictionary,
	seed_value: int,
	seed_source: StringName,
	board_is_custom: bool
) -> bool:
	if not _has_required_dependencies():
		push_error("[GameSessionLaunchSystem] 缺少必需依赖，拒绝启动新对局。")
		return false
	if seed_source not in [
		GameSessionMetadata.SEED_SOURCE_RANDOM,
		GameSessionMetadata.SEED_SOURCE_MANUAL,
	]:
		push_error("[GameSessionLaunchSystem] 新对局 seed_source 非法：%s。" % seed_source)
		return false

	var mode_config: GameModeConfig = _get_valid_mode_config(mode_config_path)
	if not is_instance_valid(mode_config):
		push_error("[GameSessionLaunchSystem] 模式配置不可用，拒绝启动：%s。" % mode_config_path)
		return false
	var topology_snapshot_copy: Dictionary = board_topology_snapshot.duplicate(true)
	var topology: BoardTopology = BoardTopology.from_dict(topology_snapshot_copy)
	topology_snapshot_copy = {}
	if (
		not _is_topology_playable_for_mode(topology, mode_config)
	):
		push_error("[GameSessionLaunchSystem] 棋盘拓扑不满足当前模式契约，拒绝启动。")
		return false

	_commit_new_game_launch(
		mode_config_path,
		topology,
		seed_value,
		seed_source,
		board_is_custom
	)
	_seed_utility.set_global_seed(seed_value)
	_scene_router.goto_scene(GAME_SCENE_PATH)
	return true


## 从当前账号目录解析并启动指定书签。
## @param bookmark_id: 待启动书签的稳定业务 ID。
func launch_bookmark(bookmark_id: String) -> bool:
	if not _has_required_dependencies():
		push_error("[GameSessionLaunchSystem] 缺少必需依赖，拒绝启动书签。")
		return false
	var bookmark: BookmarkData = _resolve_valid_bookmark(bookmark_id)
	if not is_instance_valid(bookmark):
		push_error("[GameSessionLaunchSystem] 书签不存在或不满足当前模式契约：%s。" % bookmark_id)
		return false

	_commit_bookmark_launch(bookmark)
	_scene_router.goto_scene(GAME_SCENE_PATH)
	return true


## 从当前账号目录解析并启动指定回放。
## @param replay_id: 待启动回放的稳定业务 ID。
func launch_replay(replay_id: String) -> bool:
	if not _has_required_dependencies():
		push_error("[GameSessionLaunchSystem] 缺少必需依赖，拒绝启动回放。")
		return false
	var replay: ReplayData = _resolve_valid_replay(replay_id)
	if not is_instance_valid(replay):
		push_error("[GameSessionLaunchSystem] 回放不存在或不满足当前模式契约：%s。" % replay_id)
		return false

	_commit_replay_launch(replay)
	_scene_router.goto_scene(GAME_SCENE_PATH)
	return true


func get_latest_resumable_bookmark_id() -> String:
	if not _has_required_dependencies():
		return ""
	for bookmark: BookmarkData in _bookmark_system.load_bookmarks():
		if _is_bookmark_valid_for_launch(bookmark):
			return bookmark.bookmark_id
	return ""


# --- 私有/辅助方法 ---

func _commit_new_game_launch(
	mode_config_path: String,
	topology: BoardTopology,
	seed_value: int,
	seed_source: StringName,
	board_is_custom: bool
) -> void:
	_app_config.current_replay_data.set_value(null)
	_app_config.selected_bookmark_data.set_value(null)
	_app_config.selected_mode_config_path.set_value(mode_config_path)
	_app_config.selected_board_topology.set_value(topology)
	_app_config.selected_seed.set_value(seed_value)
	_app_config.selected_seed_source.set_value(seed_source)
	_app_config.selected_board_is_custom.set_value(board_is_custom)


func _commit_bookmark_launch(bookmark: BookmarkData) -> void:
	_app_config.current_replay_data.set_value(null)
	_app_config.selected_bookmark_data.set_value(bookmark)
	_clear_new_game_selection()


func _commit_replay_launch(replay: ReplayData) -> void:
	_app_config.selected_bookmark_data.set_value(null)
	_app_config.current_replay_data.set_value(replay)
	_clear_new_game_selection()


func _clear_new_game_selection() -> void:
	_app_config.selected_mode_config_path.set_value("")
	_app_config.selected_board_topology.set_value(null)
	_app_config.selected_seed.set_value(0)
	_app_config.selected_seed_source.set_value(
		GameSessionMetadata.SEED_SOURCE_RANDOM
	)
	_app_config.selected_board_is_custom.set_value(false)


func _resolve_valid_bookmark(bookmark_id: String) -> BookmarkData:
	if not GFUuid.is_valid(bookmark_id, 7):
		return null
	for bookmark: BookmarkData in _bookmark_system.load_bookmarks():
		if bookmark.bookmark_id != bookmark_id:
			continue
		if not _is_bookmark_valid_for_launch(bookmark):
			return null
		return BookmarkData.from_dict(bookmark.to_dict())
	return null


func _resolve_valid_replay(replay_id: String) -> ReplayData:
	if not GFUuid.is_valid(replay_id, 7):
		return null
	for replay: ReplayData in _replay_system.load_replays():
		if replay.replay_id != replay_id:
			continue
		if not _is_replay_valid_for_launch(replay):
			return null
		return ReplayData.from_dict(replay.to_dict())
	return null


func _is_bookmark_valid_for_launch(bookmark: BookmarkData) -> bool:
	if not is_instance_valid(bookmark) or not GFUuid.is_valid(bookmark.bookmark_id, 7):
		return false
	var mode_config: GameModeConfig = _get_valid_mode_config(bookmark.mode_config_path)
	if (
		not is_instance_valid(mode_config)
		or bookmark.target_tile_value != maxi(mode_config.target_tile_value, 0)
		or not bookmark.matches_ruleset(mode_config, _determinism)
	):
		return false
	var topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(bookmark.board_snapshot, &"topology").duplicate(true)
	)
	return _is_topology_playable_for_mode(topology, mode_config)


func _is_replay_valid_for_launch(replay: ReplayData) -> bool:
	if not is_instance_valid(replay) or not GFUuid.is_valid(replay.replay_id, 7):
		return false
	var mode_config: GameModeConfig = _get_valid_mode_config(replay.mode_config_path)
	if (
		not is_instance_valid(mode_config)
		or not replay.matches_ruleset(mode_config, _determinism)
	):
		return false
	var topology: BoardTopology = replay.get_initial_topology()
	return _is_topology_playable_for_mode(topology, mode_config)


func _is_topology_playable_for_mode(
	topology: BoardTopology,
	mode_config: GameModeConfig
) -> bool:
	return (
		is_instance_valid(topology)
		and topology.get_playable_validation_report().is_ok()
		and is_instance_valid(mode_config)
		and is_instance_valid(mode_config.board_topology_template)
		and mode_config.board_topology_template.accepts_topology(topology)
	)


func _get_valid_mode_config(mode_config_path: String) -> GameModeConfig:
	if mode_config_path.is_empty():
		return null
	var registered_paths: PackedStringArray = _mode_catalog.get_registered_config_paths()
	if not registered_paths.has(mode_config_path):
		return null
	var mode_config: GameModeConfig = _mode_catalog.get_config(mode_config_path)
	return mode_config if is_instance_valid(mode_config) and mode_config.validate() else null


func _has_required_dependencies() -> bool:
	return (
		is_instance_valid(_app_config)
		and is_instance_valid(_bookmark_system)
		and is_instance_valid(_replay_system)
		and is_instance_valid(_scene_router)
		and is_instance_valid(_mode_catalog)
		and is_instance_valid(_determinism)
		and is_instance_valid(_seed_utility)
	)


func _resolve_app_config_model() -> AppConfigModel:
	var value: Object = get_model(AppConfigModel)
	return value if value is AppConfigModel else null


func _resolve_bookmark_system() -> BookmarkSystem:
	var value: Object = get_system(BookmarkSystem)
	return value if value is BookmarkSystem else null


func _resolve_replay_system() -> ReplaySystem:
	var value: Object = get_system(ReplaySystem)
	return value if value is ReplaySystem else null


func _resolve_scene_router() -> GameSceneRouterPort:
	var value: Object = get_system(GameSceneRouterPort)
	return value if value is GameSceneRouterPort else null


func _resolve_mode_catalog() -> GameModeCatalogUtility:
	var value: Object = get_utility(GameModeCatalogUtility)
	return value if value is GameModeCatalogUtility else null


func _resolve_determinism_utility() -> GameDeterminismUtility:
	var value: Object = get_utility(GameDeterminismUtility)
	return value if value is GameDeterminismUtility else null


func _resolve_seed_utility() -> GFSeedUtility:
	var value: Object = get_utility(GFSeedUtility)
	return value if value is GFSeedUtility else null
