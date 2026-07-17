## 验证对局暂停 Adapter 同步 GF 逻辑时间与 Godot 场景树。
extends GutTest


# --- 测试用例 ---

func test_pause_and_resume_keep_time_provider_and_scene_tree_synchronized() -> void:
	var architecture: GFArchitecture = await _make_architecture()
	var pause_utility: GamePauseUtility = _get_pause_utility(architecture)
	var time_utility: GFTimeUtility = _get_time_utility(architecture)
	var tree: SceneTree = get_tree()

	assert_true(pause_utility.pause(), "暂停 Adapter 应成功暂停对局。")
	var paused_state: bool = pause_utility.is_paused()
	var paused_synchronized: bool = pause_utility.is_synchronized()
	var gf_paused: bool = time_utility.is_time_paused()
	var tree_paused: bool = tree.paused

	assert_true(pause_utility.resume(), "暂停 Adapter 应成功恢复对局。")
	var resumed_synchronized: bool = pause_utility.is_synchronized()
	var gf_resumed: bool = not time_utility.is_time_paused()
	var tree_resumed: bool = not tree.paused

	architecture.dispose()
	await get_tree().process_frame

	assert_true(paused_state, "暂停 Adapter 应以 GFTimeUtility 状态作为查询结果。")
	assert_true(paused_synchronized, "暂停后 GF 时间与 SceneTree 必须同步。")
	assert_true(gf_paused, "暂停后 GFTimeUtility 必须停止逻辑时间。")
	assert_true(tree_paused, "暂停后 SceneTree 必须停止节点处理。")
	assert_true(resumed_synchronized, "恢复后 GF 时间与 SceneTree 必须同步。")
	assert_true(gf_resumed, "恢复后 GFTimeUtility 必须继续逻辑时间。")
	assert_true(tree_resumed, "恢复后 SceneTree 必须继续节点处理。")


func test_scene_change_event_always_resumes_game_time() -> void:
	var architecture: GFArchitecture = await _make_architecture()
	var pause_utility: GamePauseUtility = _get_pause_utility(architecture)
	var time_utility: GFTimeUtility = _get_time_utility(architecture)

	assert_true(pause_utility.pause(), "测试前应成功暂停对局。")
	architecture.send_simple_event(EventNames.SCENE_WILL_CHANGE)

	var resumed: bool = not pause_utility.is_paused()
	var synchronized: bool = pause_utility.is_synchronized()
	var gf_resumed: bool = not time_utility.is_time_paused()
	var tree_resumed: bool = not get_tree().paused

	architecture.dispose()
	await get_tree().process_frame

	assert_true(resumed, "场景切换必须清除对局暂停状态。")
	assert_true(synchronized, "场景切换后两套时间状态必须保持同步。")
	assert_true(gf_resumed, "场景切换后 GFTimeUtility 必须恢复。")
	assert_true(tree_resumed, "场景切换后 SceneTree 必须恢复。")


# --- 私有/辅助方法 ---

func _make_architecture() -> GFArchitecture:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.register_utility(GFTimeUtility, GFTimeUtility.new())
	await architecture.register_utility(GamePauseUtility, GamePauseUtility.new())
	await architecture.init()
	return architecture


func _get_pause_utility(architecture: GFArchitecture) -> GamePauseUtility:
	var utility_value: Object = architecture.get_utility(GamePauseUtility)
	if utility_value is GamePauseUtility:
		var pause_utility: GamePauseUtility = utility_value
		return pause_utility
	return null


func _get_time_utility(architecture: GFArchitecture) -> GFTimeUtility:
	var utility_value: Object = architecture.get_utility(GFTimeUtility)
	if utility_value is GFTimeUtility:
		var time_utility: GFTimeUtility = utility_value
		return time_utility
	return null
