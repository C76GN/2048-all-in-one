## 验证跨 Feature 对局启动 Port 的值边界、稳定身份解析与失败关闭。
extends GutTest


# --- 常量 ---

const _CLASSIC_MODE_PATH: String = (
	"res://features/gameplay/resources/modes/classic_mode_config.tres"
)


# --- 测试用例 ---

func test_new_game_freezes_topology_snapshot_before_committing_and_routing() -> void:
	var fixture: Dictionary = _make_fixture()
	var launch_system: GameSessionLaunchSystem = fixture[&"launch_system"]
	var app_config: AppConfigModel = fixture[&"app_config"]
	var router: _RouterSpy = fixture[&"router"]
	var topology_snapshot: Dictionary = BoardTopology.create_rectangle(
		Vector2i(4, 4)
	).to_dict()

	assert_true(launch_system.launch_new_game(
		_CLASSIC_MODE_PATH,
		topology_snapshot,
		2048,
		GameSessionMetadata.SEED_SOURCE_MANUAL,
		true
	))
	var caller_cells: Array = GFVariantData.get_option_array(
		topology_snapshot,
		&"active_cells"
	)
	caller_cells.clear()

	var stored_value: Variant = app_config.selected_board_topology.get_value()
	assert_true(stored_value is BoardTopology)
	if stored_value is BoardTopology:
		var stored_topology: BoardTopology = stored_value
		assert_true(stored_topology.get_cell_count() == 16)
	assert_true(
		GFVariantData.to_text(
			app_config.selected_mode_config_path.get_value(),
			""
		) == _CLASSIC_MODE_PATH
	)
	assert_true(GFVariantData.to_int(app_config.selected_seed.get_value(), 0) == 2048)
	assert_true(
		GFVariantData.to_string_name(
			app_config.selected_seed_source.get_value(),
			&""
		)
		== GameSessionMetadata.SEED_SOURCE_MANUAL
	)
	assert_true(
		GFVariantData.to_bool(
			app_config.selected_board_is_custom.get_value(),
			false
		)
	)
	assert_true(router.paths == [GameSessionLaunchSystem.GAME_SCENE_PATH])


func test_invalid_stable_identity_fails_without_mutating_launch_state() -> void:
	var fixture: Dictionary = _make_fixture()
	var launch_system: GameSessionLaunchSystem = fixture[&"launch_system"]
	var app_config: AppConfigModel = fixture[&"app_config"]
	var router: _RouterSpy = fixture[&"router"]
	app_config.selected_mode_config_path.set_value("sentinel")

	assert_false(launch_system.launch_bookmark("not-a-uuid"))
	assert_push_error("书签不存在或不满足当前模式契约")
	assert_true(
		GFVariantData.to_text(
			app_config.selected_mode_config_path.get_value(),
			""
		) == "sentinel"
	)
	assert_true(router.paths.is_empty())


func test_bookmark_and_replay_are_reresolved_by_id_and_copy_isolated() -> void:
	var fixture: Dictionary = _make_fixture()
	var launch_system: GameSessionLaunchSystem = fixture[&"launch_system"]
	var app_config: AppConfigModel = fixture[&"app_config"]
	var bookmarks: _BookmarkSystemStub = fixture[&"bookmarks"]
	var replays: _ReplaySystemStub = fixture[&"replays"]
	var router: _RouterSpy = fixture[&"router"]
	var mode: GameModeConfig = fixture[&"mode"]
	var bookmark: BookmarkData = _make_bookmark(mode)
	var replay: ReplayData = _make_replay(mode)
	bookmarks.items = [bookmark]
	var replay_items: Array[ReplayData] = [replay]
	replays.items = replay_items

	assert_true(
		launch_system.get_latest_resumable_bookmark_id() == bookmark.bookmark_id
	)
	assert_true(launch_system.launch_bookmark(bookmark.bookmark_id))
	var selected_bookmark_value: Variant = app_config.selected_bookmark_data.get_value()
	assert_true(selected_bookmark_value is BookmarkData)
	if selected_bookmark_value is BookmarkData:
		var selected_bookmark: BookmarkData = selected_bookmark_value
		assert_not_same(selected_bookmark, bookmark)
		bookmark.score = 999
		assert_true(selected_bookmark.score == 0)

	assert_true(launch_system.launch_replay(replay.replay_id))
	var selected_replay_value: Variant = app_config.current_replay_data.get_value()
	assert_true(selected_replay_value is ReplayData)
	if selected_replay_value is ReplayData:
		var selected_replay: ReplayData = selected_replay_value
		assert_not_same(selected_replay, replay)
		replay.final_score = 999
		assert_true(selected_replay.final_score == 0)
	var cleared_bookmark_value: Variant = app_config.selected_bookmark_data.get_value()
	assert_true(cleared_bookmark_value == null)
	assert_true(router.paths.size() == 2)


# --- 私有/辅助方法 ---

func _make_fixture() -> Dictionary:
	var mode_value: Resource = load(_CLASSIC_MODE_PATH)
	assert_true(mode_value is GameModeConfig)
	var mode: GameModeConfig = mode_value as GameModeConfig
	var mode_catalog: _ModeCatalogStub = _ModeCatalogStub.new()
	mode_catalog.mode = mode
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	var fixture: Dictionary = {
		&"app_config": AppConfigModel.new(),
		&"bookmarks": _BookmarkSystemStub.new(),
		&"replays": _ReplaySystemStub.new(),
		&"router": _RouterSpy.new(),
		&"mode_catalog": mode_catalog,
		&"determinism": GameDeterminismUtility.new(),
		&"seed_utility": seed_utility,
		&"launch_system": GameSessionLaunchSystem.new(),
		&"mode": mode,
	}
	var launch_system: GameSessionLaunchSystem = fixture[&"launch_system"]
	launch_system._app_config = fixture[&"app_config"]
	launch_system._bookmark_system = fixture[&"bookmarks"]
	launch_system._replay_system = fixture[&"replays"]
	launch_system._scene_router = fixture[&"router"]
	launch_system._mode_catalog = fixture[&"mode_catalog"]
	launch_system._determinism = fixture[&"determinism"]
	launch_system._seed_utility = fixture[&"seed_utility"]
	return fixture


func _make_bookmark(mode: GameModeConfig) -> BookmarkData:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(2048)
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.bookmark_id = GFUuid.generate_v7()
	bookmark.timestamp = 1
	bookmark.mode_config_path = mode.resource_path
	bookmark.ruleset_id = mode.ruleset_id
	bookmark.ruleset_version = mode.ruleset_version
	bookmark.ruleset_fingerprint = (
		GameDeterminismUtility.new().calculate_ruleset_fingerprint(mode)
	)
	bookmark.initial_seed = 2048
	bookmark.rng_full_state = seed_utility.get_full_state()
	bookmark.board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}
	bookmark.target_tile_value = mode.target_tile_value
	bookmark.rules_states = RuleSystem.capture_rule_states(mode.spawn_rules)
	bookmark.game_state_history = {&"undo": [], &"redo": []}
	assert_not_null(BookmarkData.from_dict(bookmark.to_dict()))
	return bookmark


func _make_replay(mode: GameModeConfig) -> ReplayData:
	var topology: BoardTopology = BoardTopology.create_rectangle(Vector2i(4, 4))
	var replay: ReplayData = ReplayData.new()
	replay.replay_id = GFUuid.generate_v7()
	replay.timestamp = 1
	replay.mode_config_path = mode.resource_path
	var _configured: bool = replay.configure_ruleset(
		mode,
		GameDeterminismUtility.new()
	)
	replay.initial_seed = 2048
	replay.initial_board_topology = topology.to_dict()
	replay.final_board_snapshot = {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": topology.to_dict(),
		&"tiles": [],
	}
	assert_not_null(ReplayData.from_dict(replay.to_dict()))
	return replay


# --- 内部类 ---

class _BookmarkSystemStub extends BookmarkSystem:
	var items: Array[BookmarkData] = []

	func load_bookmarks() -> Array[BookmarkData]:
		return items.duplicate()


class _ReplaySystemStub extends ReplaySystem:
	var items: Array[ReplayData] = []

	func load_replays() -> Array[ReplayData]:
		return items.duplicate()


class _ModeCatalogStub extends GameModeCatalogUtility:
	var mode: GameModeConfig = null

	func get_registered_config_paths() -> PackedStringArray:
		return PackedStringArray([mode.resource_path]) if mode != null else PackedStringArray()

	## @param config_path: 要从测试目录解析的模式配置路径。
	func get_config(config_path: String) -> GameModeConfig:
		return mode if mode != null and config_path == mode.resource_path else null


class _RouterSpy extends GameSceneRouterPort:
	var paths: Array[String] = []

	## @param path: 要记录的场景导航目标路径。
	func goto_scene(path: String) -> void:
		paths.append(path)
