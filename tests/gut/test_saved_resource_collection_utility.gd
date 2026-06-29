## 验证时间戳 Resource 集合持久化 Utility 以及书签/回放系统的接入。
extends GutTest


# --- 常量 ---

const _BOOKMARK_DIR_NAME: String = "bookmarks"
const _REPLAY_DIR_NAME: String = "replays"


# --- 测试用例 ---

func test_utility_saves_loads_and_sorts_timestamped_resources() -> void:
	var setup: Dictionary = await _create_collection_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var collection: SavedResourceCollectionUtility = _get_collection(setup)
	var saved_paths: Array[String] = []

	var older_bookmark: BookmarkData = _make_bookmark(100, 16)
	var newer_bookmark: BookmarkData = _make_bookmark(200, 32)
	_append_string(saved_paths, collection.save_timestamped_resource(_BOOKMARK_DIR_NAME, "bookmark", older_bookmark))
	_append_string(saved_paths, collection.save_timestamped_resource(_BOOKMARK_DIR_NAME, "bookmark", newer_bookmark))

	var resources: Array = collection.load_timestamped_resources(_BOOKMARK_DIR_NAME, "BookmarkData", BookmarkData)
	assert_true(resources.size() == 2, "应能通过 GFStorageUtility 加载已保存的 Resource 集合。")

	var first: BookmarkData = _get_bookmark_data(resources[0])
	var second: BookmarkData = _get_bookmark_data(resources[1])
	assert_true(first.timestamp == 200, "Resource 集合应按 timestamp 降序排列。")
	assert_true(second.timestamp == 100, "较旧 Resource 应排在后面。")
	assert_true(first.file_path.begins_with(_BOOKMARK_DIR_NAME.path_join("bookmark_")), "加载后应写回文件路径。")

	for path: String in saved_paths:
		var _delete_error: Error = collection.delete_resource_file(path)
	resources.clear()
	saved_paths.clear()
	older_bookmark = null
	newer_bookmark = null
	first = null
	second = null
	architecture.dispose()
	setup.clear()


func test_bookmark_and_replay_systems_use_shared_resource_collection_utility() -> void:
	var setup: Dictionary = await _create_collection_architecture(true)
	var architecture: GFArchitecture = _get_architecture(setup)
	var bookmark_system: BookmarkSystem = _get_bookmark_system(setup)
	var replay_system: ReplaySystem = _get_replay_system(setup)

	bookmark_system.save_bookmark(_make_bookmark(300, 64))
	replay_system.save_replay(_make_replay(400, 128))

	var bookmarks: Array[BookmarkData] = bookmark_system.load_bookmarks()
	var replays: Array[ReplayData] = replay_system.load_replays()
	assert_true(bookmarks.size() == 1, "BookmarkSystem 应通过共享 Utility 加载书签 Resource。")
	assert_true(replays.size() == 1, "ReplaySystem 应通过共享 Utility 加载回放 Resource。")
	var first_bookmark: BookmarkData = bookmarks[0]
	var first_replay: ReplayData = replays[0]
	assert_true(first_bookmark.score == 64, "书签业务字段应完整保留。")
	assert_true(first_replay.final_score == 128, "回放业务字段应完整保留。")
	assert_false(first_bookmark.file_path.is_empty(), "书签加载后应带有可删除的文件路径。")
	assert_false(first_replay.file_path.is_empty(), "回放加载后应带有可删除的文件路径。")

	bookmark_system.delete_bookmark(first_bookmark.file_path)
	replay_system.delete_replay(first_replay.file_path)
	assert_true(bookmark_system.load_bookmarks().size() == 0, "删除后书签列表应为空。")
	assert_true(replay_system.load_replays().size() == 0, "删除后回放列表应为空。")

	bookmarks.clear()
	replays.clear()
	architecture.dispose()
	setup.clear()


# --- 私有/辅助方法 ---

func _create_collection_architecture(include_systems: bool = false) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = GFStorageUtility.new()
	var collection: SavedResourceCollectionUtility = SavedResourceCollectionUtility.new()

	storage.save_dir_name = "gut_resource_collection_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.allow_resource_loads = true
	storage.allowed_resource_load_extensions = PackedStringArray(["tres"])
	storage.allowed_resource_load_type_hints = PackedStringArray(["BookmarkData", "ReplayData"])
	storage.create_directories_for_nested_paths = true

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(SavedResourceCollectionUtility, collection)

	var bookmark_system: BookmarkSystem = null
	var replay_system: ReplaySystem = null
	if include_systems:
		bookmark_system = BookmarkSystem.new()
		replay_system = ReplaySystem.new()
		await architecture.register_utility(GFCommandHistoryUtility, GFCommandHistoryUtility.new())
		await architecture.register_system(BookmarkSystem, bookmark_system)
		await architecture.register_system(ReplaySystem, replay_system)

	await architecture.init()
	var bookmark_directory_error: Error = collection.ensure_collection_directory(_BOOKMARK_DIR_NAME)
	var replay_directory_error: Error = collection.ensure_collection_directory(_REPLAY_DIR_NAME)
	assert_true(bookmark_directory_error == OK, "测试书签目录应创建成功。")
	assert_true(replay_directory_error == OK, "测试回放目录应创建成功。")

	return {
		"architecture": architecture,
		"collection": collection,
		"bookmark_system": bookmark_system,
		"replay_system": replay_system,
	}


func _make_bookmark(timestamp: int, score: int) -> BookmarkData:
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.timestamp = timestamp
	bookmark.score = score
	return bookmark


func _make_replay(timestamp: int, final_score: int) -> ReplayData:
	var replay: ReplayData = ReplayData.new()
	replay.timestamp = timestamp
	replay.final_score = final_score
	replay.actions = [Vector2i.RIGHT]
	return replay


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		return value
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_collection(setup: Dictionary) -> SavedResourceCollectionUtility:
	var value: Variant = setup.get("collection")
	if value is SavedResourceCollectionUtility:
		return value
	assert_true(false, "测试 setup 缺少 SavedResourceCollectionUtility。")
	return SavedResourceCollectionUtility.new()


func _get_bookmark_system(setup: Dictionary) -> BookmarkSystem:
	var value: Variant = setup.get("bookmark_system")
	if value is BookmarkSystem:
		return value
	assert_true(false, "测试 setup 缺少 BookmarkSystem。")
	return BookmarkSystem.new()


func _get_replay_system(setup: Dictionary) -> ReplaySystem:
	var value: Variant = setup.get("replay_system")
	if value is ReplaySystem:
		return value
	assert_true(false, "测试 setup 缺少 ReplaySystem。")
	return ReplaySystem.new()


func _get_bookmark_data(value: Variant) -> BookmarkData:
	if value is BookmarkData:
		return value
	assert_true(false, "测试资源集合中缺少 BookmarkData。")
	return BookmarkData.new()
