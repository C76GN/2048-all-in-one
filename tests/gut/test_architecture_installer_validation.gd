## 验证项目 Installer 不重复装配 GF 扩展已拥有的 Module。
extends GutTest


# --- 常量 ---

const PROJECT_INSTALLER_PATH: String = "res://app/scripts/game_architecture_installer.gd"
const GAME_BOARD_CONTROLLER_PATH: String = "res://features/gameplay/scripts/controllers/game_board_controller.gd"
const GAME_PLAY_CONTROLLER_PATH: String = "res://features/gameplay/scripts/controllers/game_play_controller.gd"
const GAME_PLAY_SCENE_PATH: String = "res://features/gameplay/scenes/game/game_play.tscn"
const GAME_STATUS_MODEL_PATH: String = "res://features/gameplay/scripts/models/game_status_model.gd"
const GAME_STATE_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_state_system.gd"
const GAME_FLOW_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_flow_system.gd"
const GAME_TURN_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/game_turn_system.gd"
const GAME_MOVE_TURN_ACTION_PATH: String = "res://features/gameplay/scripts/actions/game_move_turn_action.gd"
const RULE_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/rule_system.gd"
const PLAYER_INPUT_SYSTEM_PATH: String = "res://features/gameplay/scripts/systems/player_input_system.gd"
const HUD_PATH: String = "res://features/gameplay/scripts/ui/hud.gd"
const BOOKMARK_DATA_PATH: String = "res://features/bookmarks/scripts/data/bookmark_data.gd"
const REMOVED_HUD_PAYLOAD_PATH: String = "res://features/gameplay/scripts/events/hud_message_payload.gd"
const SCENE_ROUTER_SYSTEM_PATH: String = "res://features/navigation/scripts/systems/scene_router_system.gd"
const EVENT_NAMES_PATH: String = "res://shared/scripts/contracts/event_names.gd"
const PROJECT_SETTINGS_PATH: String = "res://project.godot"
const EXTENSION_OWNED_MODULES: Array[Dictionary] = [
	{
		"symbol": "GFLevelUtility",
		"extension": "gf.domain",
		"owner": "addons/gf/extensions/domain/extension.gd",
	},
	{
		"symbol": "GFQuestUtility",
		"extension": "gf.domain",
		"owner": "addons/gf/extensions/domain/extension.gd",
	},
	{
		"symbol": "GFActionQueueSystem",
		"extension": "gf.action_queue",
		"owner": "addons/gf/extensions/action_queue/extension.gd",
	},
	{
		"symbol": "GFContentPackageUtility",
		"extension": "gf.content_package",
		"owner": "addons/gf/extensions/content_package/extension.gd",
	},
	{
		"symbol": "GFTurnFlowSystem",
		"extension": "gf.turn_based",
		"owner": "addons/gf/extensions/turn_based/extension.gd",
	},
]


# --- 测试用例 ---

func test_project_installer_does_not_bind_extension_owned_modules() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var issues: Array[String] = []
	if source.is_empty():
		_append_string(issues, "%s 无法读取或为空。" % PROJECT_INSTALLER_PATH)

	for module: Dictionary in EXTENSION_OWNED_MODULES:
		var symbol: String = _get_dictionary_text(module, "symbol")
		var extension_id: String = _get_dictionary_text(module, "extension")
		var owner_path: String = _get_dictionary_text(module, "owner")
		if _source_binds_symbol(source, symbol):
			_append_string(issues, "%s 不应在项目 Installer 中手动绑定；它由 %s (%s) 自动装配。" % [
				symbol,
				owner_path,
				extension_id,
			])

	assert_true(
		issues.is_empty(),
		"项目 Installer 应只注册项目自身 Module，避免和 GF 扩展 Installer 重复注册：\n%s" % _join_lines(issues)
	)


func test_project_installer_binds_signal_utility_before_theme_consumers() -> void:
	var source: String = _read_text(PROJECT_INSTALLER_PATH)
	var signal_position: int = source.find("bind_utility(GFSignalUtility)")
	var theme_position: int = source.find("bind_utility(_GAME_THEME_UTILITY_SCRIPT)")

	assert_true(signal_position >= 0, "项目 Installer 应注册 GFSignalUtility。")
	assert_true(theme_position >= 0, "项目 Installer 应注册 GameThemeUtility。")
	assert_true(
		signal_position < theme_position,
		"GFSignalUtility 必须先于依赖它的 GameThemeUtility 注册。"
	)


func test_transient_feedback_uses_gf_notification_utility_only() -> void:
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var controller_source: String = _read_text(GAME_PLAY_CONTROLLER_PATH)
	var scene_source: String = _read_text(GAME_PLAY_SCENE_PATH)
	var status_source: String = _read_text(GAME_STATUS_MODEL_PATH)
	var game_state_source: String = _read_text(GAME_STATE_SYSTEM_PATH)
	var flow_source: String = _read_text(GAME_FLOW_SYSTEM_PATH)
	var input_source: String = _read_text(PLAYER_INPUT_SYSTEM_PATH)
	var hud_source: String = _read_text(HUD_PATH)
	var bookmark_source: String = _read_text(BOOKMARK_DATA_PATH)

	assert_true(installer_source.contains("bind_utility(GFNotificationUtility)"), "项目 Installer 应注册 GFNotificationUtility。")
	assert_true(flow_source.contains("push_notification("), "游戏流程反馈应写入 GF 通知队列。")
	assert_true(input_source.contains("push_notification("), "输入反馈应写入 GF 通知队列。")
	assert_true(hud_source.contains("notification_started"), "HUD 应消费 GF 通知生命周期信号。")
	assert_false(FileAccess.file_exists(REMOVED_HUD_PAYLOAD_PATH), "不得保留重复的 HudMessagePayload 协议。")
	assert_false(scene_source.contains("HUDMessageTimer"), "通知超时应由 GFNotificationUtility 管理。")
	assert_false(controller_source.contains("HudMessagePayload"), "游戏控制器不得承担通知队列职责。")
	assert_false(status_source.contains("status_message"), "瞬时通知不得进入运行时统计 Model。")
	assert_false(game_state_source.contains("status_message"), "瞬时通知不得进入撤销或书签状态快照。")
	assert_false(bookmark_source.contains("status_message"), "瞬时通知不得进入书签 schema。")


func test_move_turn_pipeline_uses_gf_turn_action_lifecycle() -> void:
	var settings_source: String = _read_text(PROJECT_SETTINGS_PATH)
	var installer_source: String = _read_text(PROJECT_INSTALLER_PATH)
	var turn_source: String = _read_text(GAME_TURN_SYSTEM_PATH)
	var action_source: String = _read_text(GAME_MOVE_TURN_ACTION_PATH)
	var flow_source: String = _read_text(GAME_FLOW_SYSTEM_PATH)
	var rule_source: String = _read_text(RULE_SYSTEM_PATH)
	var event_source: String = _read_text(EVENT_NAMES_PATH)

	assert_true(settings_source.contains("\"gf.turn_based\""), "项目应显式启用 gf.turn_based 扩展。")
	assert_true(installer_source.contains("bind_system(GameTurnSystem)"), "项目 Installer 应注册移动回合 Adapter。")
	assert_true(turn_source.contains("get_system(GFTurnFlowSystem)"), "回合 Adapter 应使用扩展拥有的 GFTurnFlowSystem。")
	assert_true(turn_source.contains("enqueue_action(GameMoveTurnAction.new"), "有效移动应进入 GF 回合行动队列。")
	assert_true(turn_source.contains("resolve_actions()"), "回合行动只能由 GFTurnFlowSystem 解析。")
	assert_true(action_source.contains("extends GFTurnAction"), "移动回合应实现强类型 GFTurnAction。")
	assert_true(action_source.contains("_inject_dependencies"), "移动回合依赖应由 GF Flow 注入。")
	assert_false(flow_source.contains("register_event(MoveData"), "GameFlowSystem 不得旁路 GF 回合行动消费移动。")
	assert_false(rule_source.contains("register_event(MoveData"), "RuleSystem 不得旁路 GF 回合行动消费移动。")
	assert_false(event_source.contains("TURN_FINISHED"), "不得保留重复的 TURN_FINISHED 项目事件协议。")


func test_required_gf_modules_have_no_manual_runtime_fallbacks() -> void:
	var board_source: String = _read_text(GAME_BOARD_CONTROLLER_PATH)
	var router_source: String = _read_text(SCENE_ROUTER_SYSTEM_PATH)

	assert_true(board_source.contains("_has_required_dependencies"), "棋盘控制器应显式校验 GF 必需依赖。")
	assert_false(board_source.contains("TileScene.instantiate()"), "Tile 只能通过 GFObjectPoolUtility 获取。")
	assert_false(board_source.contains("undo_action.execute()"), "视觉 Action 只能由 GFActionQueueSystem 执行。")
	assert_true(router_source.contains("_has_required_dependencies"), "场景路由应显式校验 GF 必需依赖。")
	assert_false(router_source.contains("change_scene_to_packed("), "场景切换不能绕过 GFSceneUtility。")
	assert_false(router_source.contains("scene_switch_started.connect("), "跨生命周期信号只能由 GFSignalUtility 管理。")


# --- 私有/辅助方法 ---

func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _source_binds_symbol(source: String, symbol: String) -> bool:
	var lines: PackedStringArray = source.split("\n")
	for line_index: int in range(lines.size()):
		var line: String = _get_packed_line(lines, line_index).strip_edges()
		if line.begins_with("#"):
			continue
		if _line_binds_symbol(line, symbol):
			return true
	return false


func _line_binds_symbol(line: String, symbol: String) -> bool:
	var bind_patterns: Array[String] = [
		"bind_utility(%s" % symbol,
		"bind_system(%s" % symbol,
		"register_utility(%s" % symbol,
		"register_system(%s" % symbol,
		"register_utility_instance(%s.new()" % symbol,
		"register_system_instance(%s.new()" % symbol,
	]
	for pattern: String in bind_patterns:
		if line.contains(pattern):
			return true
	return false


func _get_packed_line(lines: PackedStringArray, index: int) -> String:
	if index < 0 or index >= lines.size():
		return ""
	return lines[index]


func _get_dictionary_text(source: Dictionary, key: Variant, fallback: String = "") -> String:
	var value: Variant = fallback
	if source.has(key):
		value = source[key]
	return GFVariantData.to_text(value, fallback)


func _join_lines(lines: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var _append_result: bool = packed.append(line)
	return "\n".join(packed)


func _append_string(target: Array[String], value: String) -> void:
	target.append(value)
