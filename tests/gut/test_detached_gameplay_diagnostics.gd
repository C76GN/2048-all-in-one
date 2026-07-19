## 验证对局诊断工作区与玩家场景彻底解耦。
extends GutTest


# --- 常量 ---

const _GAME_SCENE: PackedScene = preload("res://features/gameplay/scenes/game/game_play.tscn")
const _WORKSPACE_SCENE: PackedScene = preload("res://features/diagnostics/scenes/windows/gameplay_diagnostics_window.tscn")
const _INPUT_CONTEXT: GFInputContext = preload("res://features/diagnostics/resources/input/diagnostics_input_context.tres")
const _GAMEPLAY_CONTROLLER_PATH: String = "res://features/gameplay/scripts/controllers/game_play_controller.gd"
const _TEST_TOOL_UTILITY_PATH: String = "res://features/diagnostics/scripts/utilities/test_tool_utility.gd"


# --- 测试用例 ---

func test_diagnostics_workspace_is_a_detached_non_transient_window() -> void:
	var workspace: Node = _WORKSPACE_SCENE.instantiate()

	assert_true(workspace is GameplayDiagnosticsWindow)
	var diagnostics_window: GameplayDiagnosticsWindow = workspace as GameplayDiagnosticsWindow
	assert_false(diagnostics_window.transient, "诊断工作区不得绑定为玩家窗口的临时弹层。")
	assert_false(diagnostics_window.exclusive, "诊断工作区不得阻塞玩家窗口输入。")
	assert_not_null(diagnostics_window.get_test_panel(), "独立工作区必须承载规则驱动 TestPanel。")

	workspace.free()


func test_gameplay_scene_has_no_diagnostics_resource_or_reserved_column() -> void:
	var scene_root: Node = _GAME_SCENE.instantiate()
	var right_column: VBoxContainer = scene_root.get_node(
		"MarginContainer/ColumnsContainer/RightColumn"
	) as VBoxContainer

	assert_false(right_column.visible)
	assert_null(right_column.get_node_or_null("TestPanel"))
	assert_false(
		_get_scene_text().contains("features/diagnostics"),
		"玩法场景资源不得反向引用 diagnostics feature。"
	)

	scene_root.free()


func test_diagnostics_input_context_uses_gf_mapping_contract() -> void:
	assert_true(_INPUT_CONTEXT.get_context_id() == &"diagnostics")
	assert_true(_INPUT_CONTEXT.mappings.size() == 1)
	assert_true(
		_INPUT_CONTEXT.mappings[0].get_action_id() == &"toggle_diagnostics_workspace"
	)


func test_gameplay_publishes_context_while_diagnostics_owns_window_lifecycle() -> void:
	var gameplay_source: String = _read_text(_GAMEPLAY_CONTROLLER_PATH)
	var diagnostics_source: String = _read_text(_TEST_TOOL_UTILITY_PATH)

	assert_true(gameplay_source.contains("send_event(GameplayBoardReadyData.new(game_board))"))
	assert_false(gameplay_source.contains("TestToolUtility"))
	assert_false(gameplay_source.contains("TestPanel"))
	assert_true(diagnostics_source.contains("register_event(GameplayBoardReadyData"))
	assert_true(diagnostics_source.contains("GFInputMappingUtility"))
	assert_true(diagnostics_source.contains("GFSignalUtility"))
	assert_true(diagnostics_source.contains("GFConsoleUtility"))
	assert_true(
		diagnostics_source.contains("var open_on_gameplay_context: bool = false"),
		"开发诊断窗口必须按需打开，不得在每次进入对局时遮挡玩家画面。"
	)


# --- 私有/辅助方法 ---

func _get_scene_text() -> String:
	return _read_text("res://features/gameplay/scenes/game/game_play.tscn")


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
