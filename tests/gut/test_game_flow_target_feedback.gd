## 验证 GameFlowSystem 的目标达成提示门控逻辑。
extends GutTest


# --- 测试用例 ---

func test_target_reached_notification_is_gated_once_per_session() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	mode_config.target_tile_value = 2048
	flow_system._mode_config = mode_config

	assert_true(
		not flow_system._should_notify_target_reached(1024),
		"未达到目标值时不应提示目标达成。"
	)
	assert_true(
		flow_system._should_notify_target_reached(2048),
		"首次达到目标值时应提示目标达成。"
	)

	flow_system._target_reached_notified = true
	assert_true(
		not flow_system._should_notify_target_reached(4096),
		"目标达成提示在同一会话中只应出现一次。"
	)


func test_target_reached_notification_is_disabled_without_mode_target() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	flow_system._mode_config = mode_config

	assert_true(
		not flow_system._should_notify_target_reached(4096),
		"没有配置目标值的模式不应触发目标达成提示。"
	)


func test_target_reached_notification_is_disabled_during_replay() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	mode_config.target_tile_value = 2048
	flow_system._mode_config = mode_config
	flow_system._is_replay_mode = true

	assert_true(
		not flow_system._should_notify_target_reached(2048),
		"回放模式不应触发目标达成提示或弹层。"
	)


func test_target_state_sync_writes_status_model() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	mode_config.target_tile_value = 2048
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	flow_system._sync_target_state(false)

	assert_true(
		GFVariantData.to_int(status_model.target_tile_value.get_value(), 0) == 2048,
		"目标同步应写入当前模式的目标方块值。"
	)
	assert_true(
		not GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"未达成时运行时模型应保持 target_reached=false。"
	)

	flow_system._sync_target_state(true)

	assert_true(
		GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"目标达成后运行时模型应记录 target_reached=true。"
	)


func test_session_target_reached_uses_runtime_status_model() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	mode_config.target_tile_value = 2048
	status_model.set_target_state(2048, true)
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	assert_true(
		flow_system._has_reached_target_in_session(1024),
		"本局曾达成目标后，即使当前最高方块低于目标，结算仍应记为已达成。"
	)


func test_session_target_reached_requires_mode_target() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	status_model.set_target_state(2048, true)
	flow_system._mode_config = mode_config
	flow_system._game_status_model = status_model

	assert_true(
		not flow_system._has_reached_target_in_session(4096),
		"未配置目标值的模式不应从运行时状态误判为目标达成。"
	)


func test_resume_request_closes_top_panel_and_unpauses_tree() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()

	var panel: Control = Control.new()
	ui_utility.push_panel_instance(panel)
	var tree: SceneTree = get_tree()
	tree.paused = true

	architecture.send_simple_event(EventNames.RESUME_GAME_REQUESTED)
	var paused_after_resume: bool = tree.paused
	var open_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	tree.paused = false
	await _dispose_architecture_and_flush(architecture)

	assert_true(not paused_after_resume, "继续挑战应恢复 SceneTree 暂停状态。")
	assert_true(open_panel_count == 0, "继续挑战应关闭当前目标达成弹层。")


func test_restart_request_clears_all_panels_and_delegates_restart() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: _TestGameFlowSystem = _TestGameFlowSystem.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.init()

	var popup_panel: Control = Control.new()
	var top_panel: Control = Control.new()
	ui_utility.push_panel_instance(popup_panel, GFUIUtility.Layer.POPUP)
	ui_utility.push_panel_instance(top_panel, GFUIUtility.Layer.TOP)

	architecture.send_simple_event(EventNames.RESTART_GAME_REQUESTED)
	var popup_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	var top_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.TOP).size()
	var restart_count: int = flow_system.restart_count
	await _dispose_architecture_and_flush(architecture)

	assert_true(popup_panel_count == 0, "重新开始应清空弹层栈。")
	assert_true(top_panel_count == 0, "重新开始应清空顶层提示栈。")
	assert_true(restart_count == 1, "重新开始请求应委托 GameFlowSystem.restart_game()。")


func test_return_to_main_menu_request_clears_panels_unpauses_and_routes() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var ui_utility: GFUIUtility = GFUIUtility.new()
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var router: _TestSceneRouterSystem = _TestSceneRouterSystem.new()
	await architecture.register_utility(GFUIUtility, ui_utility)
	await architecture.register_system(GameFlowSystem, flow_system)
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()

	var popup_panel: Control = Control.new()
	var top_panel: Control = Control.new()
	ui_utility.push_panel_instance(popup_panel, GFUIUtility.Layer.POPUP)
	ui_utility.push_panel_instance(top_panel, GFUIUtility.Layer.TOP)
	var tree: SceneTree = get_tree()
	tree.paused = true

	architecture.send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)
	var paused_after_return: bool = tree.paused
	var popup_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.POPUP).size()
	var top_panel_count: int = ui_utility.get_panel_stack(GFUIUtility.Layer.TOP).size()
	var route_count: int = router.return_to_main_menu_count
	tree.paused = false
	await _dispose_architecture_and_flush(architecture)

	assert_true(not paused_after_return, "返回主界面应恢复 SceneTree 暂停状态。")
	assert_true(popup_panel_count == 0, "返回主界面应清空弹层栈。")
	assert_true(top_panel_count == 0, "返回主界面应清空顶层提示栈。")
	assert_true(route_count == 1, "返回主界面应调用 SceneRouterSystem.return_to_main_menu()。")


func test_game_ready_preserves_target_reached_for_legacy_bookmark() -> void:
	var flow_system: GameFlowSystem = GameFlowSystem.new()
	var mode_config: GameModeConfig = GameModeConfig.new()
	var status_model: GameStatusModel = GameStatusModel.new()
	var ready_data: GameReadyData = GameReadyData.new()
	var bookmark: BookmarkData = BookmarkData.new()
	mode_config.target_tile_value = 2048
	bookmark.highest_tile = 4096
	bookmark.target_reached = false
	ready_data.mode_config = mode_config
	ready_data.loaded_bookmark_data = bookmark
	flow_system._game_status_model = status_model

	flow_system._on_game_ready(ready_data)

	assert_true(
		GFVariantData.to_bool(status_model.target_reached.get_value(), false),
		"旧书签没有 target_reached 字段时，应从最高方块兼容推断已达成目标。"
	)
	assert_true(
		flow_system._target_reached_notified,
		"恢复已达成目标的局面时不应再次弹出首次达成提示。"
	)


# --- 私有/辅助方法 ---

func _dispose_architecture_and_flush(architecture: GFArchitecture) -> void:
	architecture.dispose()
	await get_tree().process_frame
	await get_tree().process_frame


# --- 内部类 ---

class _TestSceneRouterSystem:
	extends SceneRouterSystem

	var return_to_main_menu_count: int = 0

	func return_to_main_menu() -> void:
		return_to_main_menu_count += 1


class _TestGameFlowSystem:
	extends GameFlowSystem

	var restart_count: int = 0

	func restart_game() -> void:
		restart_count += 1
