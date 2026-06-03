## 验证时间戳 Resource 集合持久化 Utility 以及书签/回放系统的接入。
extends GutTest


# --- 常量 ---

const _BOOKMARK_DIR_NAME: String = "bookmarks"
const _REPLAY_DIR_NAME: String = "replays"
const _SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT = preload("res://scripts/utilities/saved_resource_collection_utility.gd")


# --- 测试用例 ---

func test_utility_saves_loads_and_sorts_timestamped_resources() -> void:
	var setup: Dictionary = await _create_collection_architecture()
	var architecture := setup["architecture"] as GFArchitecture
	var collection = setup["collection"]
	var saved_paths: Array[String] = []

	var older_bookmark := _make_bookmark(100, 16)
	var newer_bookmark := _make_bookmark(200, 32)
	saved_paths.append(collection.save_timestamped_resource(_BOOKMARK_DIR_NAME, "bookmark", older_bookmark))
	saved_paths.append(collection.save_timestamped_resource(_BOOKMARK_DIR_NAME, "bookmark", newer_bookmark))

	var resources: Array = collection.load_timestamped_resources(_BOOKMARK_DIR_NAME, "BookmarkData", BookmarkData)
	assert_eq(resources.size(), 2, "应能通过 GFStorageUtility 加载已保存的 Resource 集合。")

	var first := resources[0] as BookmarkData
	var second := resources[1] as BookmarkData
	assert_eq(first.timestamp, 200, "Resource 集合应按 timestamp 降序排列。")
	assert_eq(second.timestamp, 100, "较旧 Resource 应排在后面。")
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
	var architecture := setup["architecture"] as GFArchitecture
	var bookmark_system := setup["bookmark_system"] as BookmarkSystem
	var replay_system := setup["replay_system"] as ReplaySystem

	bookmark_system.save_bookmark(_make_bookmark(300, 64))
	replay_system.save_replay(_make_replay(400, 128))

	var bookmarks: Array[BookmarkData] = bookmark_system.load_bookmarks()
	var replays: Array[ReplayData] = replay_system.load_replays()
	assert_eq(bookmarks.size(), 1, "BookmarkSystem 应通过共享 Utility 加载书签 Resource。")
	assert_eq(replays.size(), 1, "ReplaySystem 应通过共享 Utility 加载回放 Resource。")
	assert_eq(bookmarks[0].score, 64, "书签业务字段应完整保留。")
	assert_eq(replays[0].final_score, 128, "回放业务字段应完整保留。")
	assert_false(bookmarks[0].file_path.is_empty(), "书签加载后应带有可删除的文件路径。")
	assert_false(replays[0].file_path.is_empty(), "回放加载后应带有可删除的文件路径。")

	bookmark_system.delete_bookmark(bookmarks[0].file_path)
	replay_system.delete_replay(replays[0].file_path)
	assert_eq(bookmark_system.load_bookmarks().size(), 0, "删除后书签列表应为空。")
	assert_eq(replay_system.load_replays().size(), 0, "删除后回放列表应为空。")

	bookmarks.clear()
	replays.clear()
	architecture.dispose()
	setup.clear()


# --- 私有/辅助方法 ---

func _create_collection_architecture(include_systems: bool = false) -> Dictionary:
	var architecture := GFArchitecture.new()
	var storage := GFStorageUtility.new()
	var collection = _SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT.new()

	storage.save_dir_name = "gut_resource_collection_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true

	architecture.register_utility(GFStorageUtility, storage)
	architecture.register_utility(_SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT, collection)

	var bookmark_system: BookmarkSystem = null
	var replay_system: ReplaySystem = null
	if include_systems:
		bookmark_system = BookmarkSystem.new()
		replay_system = ReplaySystem.new()
		architecture.register_utility(GFCommandHistoryUtility, GFCommandHistoryUtility.new())
		architecture.register_system(BookmarkSystem, bookmark_system)
		architecture.register_system(ReplaySystem, replay_system)

	await architecture.init()
	collection.ensure_collection_directory(_BOOKMARK_DIR_NAME)
	collection.ensure_collection_directory(_REPLAY_DIR_NAME)

	return {
		"architecture": architecture,
		"collection": collection,
		"bookmark_system": bookmark_system,
		"replay_system": replay_system,
	}


func _make_bookmark(timestamp: int, score: int) -> BookmarkData:
	var bookmark := BookmarkData.new()
	bookmark.timestamp = timestamp
	bookmark.score = score
	return bookmark


func _make_replay(timestamp: int, final_score: int) -> ReplayData:
	var replay := ReplayData.new()
	replay.timestamp = timestamp
	replay.final_score = final_score
	replay.actions = [Vector2i.RIGHT]
	return replay
