## PlayerInputSystem: 负责处理标准模式下的玩家输入，并将抽象动作转换为游戏命令。
class_name PlayerInputSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const GAMEPLAY_INPUT_CONTEXT: GFInputContext = preload("res://features/gameplay/resources/input/gameplay_input_context.tres")
const _MOVE_FAIL_MESSAGE_FALLBACK: String = "[color=yellow]这个方向无法移动。[/color]"
const _MOVE_FAIL_MESSAGE_DURATION: float = 1.6


# --- 私有变量 ---

var _input_mapping: GFInputMappingUtility
var _notifications: GFNotificationUtility
var _pause_utility: GamePauseUtility
var _board_animation_utility: GameBoardAnimationUtility
var _is_playing: bool = false
var _is_active: bool = false


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GamePauseUtility,
		GameBoardAnimationUtility,
		GFCommandHistoryUtility,
		GFInputMappingUtility,
		GFNotificationUtility,
	]


func init() -> void:
	# 暂停期间仍需消费“恢复”输入，其余玩法动作由本 System 显式门控。
	ignore_pause = true
	ignore_time_scale = true


func ready() -> void:
	_input_mapping = _get_input_mapping_utility()
	_notifications = _get_notification_utility()
	_pause_utility = _get_pause_utility()
	_board_animation_utility = _get_board_animation_utility()
	if is_instance_valid(_input_mapping):
		_input_mapping.enable_context(GAMEPLAY_INPUT_CONTEXT, 100)
	else:
		push_error("[PlayerInputSystem] 缺少 GFInputMappingUtility，玩法输入不可用。")
	if not is_instance_valid(_notifications):
		push_error("[PlayerInputSystem] 缺少 GFNotificationUtility，玩法反馈不可用。")
	if not is_instance_valid(_pause_utility):
		push_error("[PlayerInputSystem] 缺少 GamePauseUtility，暂停输入门控不可用。")
	if not is_instance_valid(_board_animation_utility):
		push_error("[PlayerInputSystem] 缺少 GameBoardAnimationUtility，动画输入策略不可用。")

	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready", 1))
	register_simple_event(EventNames.GAME_STATE_CHANGED, GFEventListener.from_method(self, &"_on_game_state_changed", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change", 1))
	register_simple_event(EventNames.REPLAY_CONTINUED_AS_GAME, GFEventListener.from_method(self, &"_on_replay_continued_as_game", 1))


func dispose() -> void:
	if is_instance_valid(_input_mapping):
		_input_mapping.disable_context(GAMEPLAY_INPUT_CONTEXT)
	_input_mapping = null
	_notifications = null
	_pause_utility = null
	_board_animation_utility = null


## 轮询玩法输入上下文并派发对应游戏命令。
## @param _delta: 当前帧间隔；该系统使用输入缓冲，不直接依赖该值。
func tick(_delta: float) -> void:
	if not _is_active or not is_instance_valid(_input_mapping):
		return

	if _consume_action(GameplayInputActions.PAUSE):
		send_simple_event(EventNames.UI_PAUSE_REQUESTED)
		return

	if is_instance_valid(_pause_utility) and _pause_utility.is_paused():
		_input_mapping.clear_input_state()
		return

	if not _is_playing:
		return

	if _consume_action(GameplayInputActions.UNDO):
		send_simple_event(EventNames.UNDO_REQUESTED)
		return

	if _consume_action(GameplayInputActions.REDO):
		send_simple_event(EventNames.REDO_REQUESTED)
		return

	if _consume_action(GameplayInputActions.SAVE_BOOKMARK):
		send_simple_event(EventNames.SAVE_BOOKMARK_REQUESTED)
		return

	var direction: Vector2i = Vector2i.ZERO
	if _consume_action(GameplayInputActions.MOVE_UP):
		direction = Vector2i.UP
	elif _consume_action(GameplayInputActions.MOVE_DOWN):
		direction = Vector2i.DOWN
	elif _consume_action(GameplayInputActions.MOVE_LEFT):
		direction = Vector2i.LEFT
	elif _consume_action(GameplayInputActions.MOVE_RIGHT):
		direction = Vector2i.RIGHT

	if direction != Vector2i.ZERO:
		if (
			is_instance_valid(_board_animation_utility)
			and not _board_animation_utility.prepare_for_move()
		):
			return
		call_deferred(&"_execute_move_command", direction)


# --- 私有/辅助方法 ---

func _execute_move_command(direction: Vector2i) -> void:
	var history: GFCommandHistoryUtility = _get_command_history_utility()
	if not is_instance_valid(history):
		return

	var result: Variant = await history.execute_command(MoveCommand.new(direction))
	if result == null:
		_show_invalid_move_feedback()
		return

	send_simple_event(EventNames.HUD_UPDATE_REQUESTED)


func _consume_action(action_id: StringName) -> bool:
	if not is_instance_valid(_input_mapping):
		return false

	return _input_mapping.consume_action(action_id)


func _show_invalid_move_feedback() -> void:
	if not is_instance_valid(_notifications):
		push_error("[PlayerInputSystem] GFNotificationUtility 未注册，无法显示无效移动反馈。")
		return
	var _notification_id: int = _notifications.push_notification(
		_translate_with_fallback("MOVE_FAIL_MSG", _MOVE_FAIL_MESSAGE_FALLBACK),
		"",
		GFNotificationUtility.Level.WARNING,
		{
			"duration_seconds": _MOVE_FAIL_MESSAGE_DURATION,
			"key": "gameplay.invalid_move",
			"metadata": {"surface": "gameplay_hud"},
		}
	)


func _translate_with_fallback(key: String, fallback: String) -> String:
	var text: String = tr(key)
	if text == key:
		return fallback
	return text


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
	return null


func _get_notification_utility() -> GFNotificationUtility:
	var utility_value: Object = get_utility(GFNotificationUtility)
	if utility_value is GFNotificationUtility:
		var notification_utility: GFNotificationUtility = utility_value
		return notification_utility
	return null


func _get_pause_utility() -> GamePauseUtility:
	var utility_value: Object = get_utility(GamePauseUtility)
	if utility_value is GamePauseUtility:
		var pause_utility: GamePauseUtility = utility_value
		return pause_utility
	return null


func _get_board_animation_utility() -> GameBoardAnimationUtility:
	var utility_value: Object = get_utility(GameBoardAnimationUtility)
	if utility_value is GameBoardAnimationUtility:
		var animation_utility: GameBoardAnimationUtility = utility_value
		return animation_utility
	return null


# --- 信号处理函数 ---

func _on_game_ready(data: GameReadyData) -> void:
	_is_active = not data.is_replay_mode


func _on_game_state_changed(state: StringName) -> void:
	_is_playing = state == EventNames.STATE_PLAYING


func _on_scene_will_change(_payload: Variant = null) -> void:
	_is_active = false
	_is_playing = false
	if is_instance_valid(_input_mapping):
		_input_mapping.clear_input_state()


func _on_replay_continued_as_game(_payload: Variant = null) -> void:
	_is_active = true
	_is_playing = true
	if is_instance_valid(_input_mapping):
		_input_mapping.clear_input_state()
