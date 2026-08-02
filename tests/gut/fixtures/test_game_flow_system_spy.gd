## TestGameFlowSystemSpy: 记录流程系统重启调用的测试替身。
class_name TestGameFlowSystemSpy
extends GameFlowSystem


var restart_count: int = 0
var fixture_router: SceneRouterSystem = null


# --- 公共方法 ---

## 窄流程替身只声明并使用测试显式注入的依赖。
func get_required_models() -> Array[Script]:
	return []


func get_required_systems() -> Array[Script]:
	return []


func get_required_utilities() -> Array[Script]:
	return []


## 注入当前窄测试实际读取的依赖，避免伪造整套生产 Composition Root。
## @param grid_model: 可选棋盘模型。
## @param status_model: 可选对局状态模型。
## @param clock: 可选测试时钟。
## @param notifications: 可选通知工具。
## @param pause_utility: 可选暂停工具。
## @param determinism: 可选确定性工具。
## @param accessibility_summary: 可选无障碍摘要工具。
## @param router: 可选场景路由替身。
func configure_dependencies(
	grid_model: GridModel = null,
	status_model: GameStatusModel = null,
	clock: GameClockUtility = null,
	notifications: GFNotificationUtility = null,
	pause_utility: GamePauseUtility = null,
	determinism: GameDeterminismUtility = null,
	accessibility_summary: GameAccessibilitySummaryUtility = null,
	router: SceneRouterSystem = null
) -> void:
	_grid_model = grid_model
	_game_status_model = status_model
	_clock = clock
	_notifications = notifications
	_pause_utility = pause_utility
	_determinism = determinism
	_accessibility_summary = accessibility_summary
	fixture_router = router


## 只绑定这些流程测试会触发的事件，不读取未声明的生产依赖。
func ready() -> void:
	_persistence_epoch += 1
	_persistence_owner_active = true
	_bookmark_save_in_progress = false
	register_simple_event(
		EventNames.RATIO_RESOLVED,
		GFEventListener.from_method(self, &"_on_ratio_resolved", 1)
	)
	register_simple_event(
		EventNames.SCORE_UPDATED,
		GFEventListener.from_method(self, &"_on_score_updated", 1)
	)
	register_event(
		GameReadyData,
		GFEventListener.from_method(self, &"_on_game_ready", 1)
	)
	register_simple_event(
		EventNames.RESUME_GAME_REQUESTED,
		GFEventListener.from_method(self, &"_on_resume_game_requested", 1)
	)
	register_simple_event(
		EventNames.RESTART_GAME_REQUESTED,
		GFEventListener.from_method(self, &"_on_restart_game_requested", 1)
	)
	register_simple_event(
		EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED,
		GFEventListener.from_method(self, &"_on_return_to_main_menu_from_game", 1)
	)


func restart_game() -> void:
	restart_count += 1


# --- 私有/辅助方法 ---

func _get_current_game_model() -> CurrentGameModel:
	return null


func _get_scene_router_system() -> SceneRouterSystem:
	return fixture_router
