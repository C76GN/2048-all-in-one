## 验证棋盘编辑草稿、GF 命令历史与严格自定义棋盘 schema。
extends GutTest


# --- 常量 ---

const _BOARD_EDITOR_SCENE: PackedScene = preload(
	"res://features/board_editor/scenes/ui/board_editor_dialog.tscn"
)
const _BOARD_EDITOR_INPUT_CONTEXT: GFInputContext = preload(
	"res://features/board_editor/resources/input/board_editor_input_context.tres"
)
const _BOARD_EDITOR_SCRIPT_PATH: String = (
	"res://features/board_editor/scripts/ui/board_editor_dialog.gd"
)
const _BOARD_EDITOR_VIEWPORT_SCRIPT_PATH: String = (
	"res://features/board_editor/scripts/ui/board_editor_viewport_controller.gd"
)
const _BOARD_EDITOR_CONTEXT_SCRIPT_PATH: String = (
	"res://features/board_editor/scripts/contexts/board_editor_context.gd"
)


# --- 测试用例 ---

func test_draft_reports_disconnected_regions_and_normalizes_submission() -> void:
	var topology_template: BoardTopologyTemplate = _make_template()
	var draft: BoardTopologyDraftModel = BoardTopologyDraftModel.new()
	var configured: bool = draft.configure(topology_template)
	var replaced: bool = draft.replace_cells([
		Vector2i(2, 1),
		Vector2i(4, 1),
		Vector2i(2, 3),
		Vector2i(4, 3),
	])
	var state: Dictionary = draft.get_validation_state()
	var topology: BoardTopology = draft.create_topology()

	assert_true(configured and replaced, "有效模板应能建立可编辑草稿。")
	assert_true(GFVariantData.get_option_bool(state, "valid"), "断开区域仍是可玩的稀疏棋盘。")
	assert_true(GFVariantData.get_option_int(state, "component_count") == 4, "诊断应报告四个连通分量。")
	assert_true(GFVariantData.get_option_string_name(state, "reason") == &"disconnected", "断开状态应作为提示暴露。")
	assert_true(topology != null, "模板接受的草稿应可提交。")
	if topology != null:
		assert_true(topology.get_bounds_size() == Vector2i(3, 3), "提交拓扑应移除画布左上空白。")
		assert_true(topology.contains_cell(Vector2i.ZERO), "规范化后最小坐标应为原点。")


func test_draft_rejects_shape_outside_template_bounds() -> void:
	var draft: BoardTopologyDraftModel = BoardTopologyDraftModel.new()
	var configured: bool = draft.configure(_make_template())
	var replaced: bool = draft.replace_cells([Vector2i.ZERO, Vector2i(1, 0)])
	var state: Dictionary = draft.get_validation_state()

	assert_true(configured and replaced, "无效最终形状仍应允许留在草稿中继续编辑。")
	assert_false(GFVariantData.get_option_bool(state, "valid"), "小于模板最小包围盒的草稿不能提交。")
	assert_true(GFVariantData.get_option_string_name(state, "reason") == &"template_rejected", "应给出模板拒绝原因。")
	assert_null(draft.create_topology(), "无效草稿不得越过模板直接生成拓扑。")


func test_local_gf_command_history_undoes_and_redoes_draft_edits() -> void:
	var draft: BoardTopologyDraftModel = BoardTopologyDraftModel.new()
	var configured: bool = draft.configure(_make_template())
	var initial_cells: Array[Vector2i] = draft.get_active_cells()
	var next_cells: Array[Vector2i] = BoardTopology.create_cross(2).get_active_cells()
	var history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	history.max_history_size = 8
	history.init()
	var command: BoardDraftEditCommand = BoardDraftEditCommand.new().configure(
		draft,
		next_cells,
		"cross"
	)
	var execute_result: Variant = await history.execute_command(command)
	var executed: bool = false
	if execute_result is bool:
		executed = execute_result

	assert_true(configured, "命令测试草稿应配置成功。")
	assert_true(executed, "GF 命令历史应执行草稿替换。")
	assert_true(history.can_undo(), "执行后应产生一条局部撤销记录。")
	assert_true(draft.get_active_cells() == next_cells, "执行结果应采用目标单元。")
	assert_true(history.undo_last(), "局部历史应能撤销。")
	assert_true(draft.get_active_cells() == initial_cells, "撤销必须恢复命令前纯数据快照。")
	assert_true(history.redo(), "局部历史应能重做。")
	assert_true(draft.get_active_cells() == next_cells, "重做必须再次应用目标单元。")
	history.dispose()


func test_board_editor_context_owns_isolated_gf_command_history() -> void:
	var parent_architecture: GFArchitecture = GFArchitecture.new()
	var global_history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	await parent_architecture.register_utility(GFCommandHistoryUtility, global_history)
	await parent_architecture.init()
	var parent_context: TestArchitectureContext = TestArchitectureContext.new()
	parent_context.test_architecture = parent_architecture
	add_child_autoqfree(parent_context)
	var editor_context: BoardEditorContext = BoardEditorContext.new()
	parent_context.add_child(editor_context)
	var scoped_architecture: GFArchitecture = await editor_context.wait_until_ready()
	var local_history: GFCommandHistoryUtility = editor_context.get_history()

	assert_not_null(scoped_architecture, "编辑器 scoped 架构应完成初始化。")
	assert_not_null(local_history, "编辑器 scoped 架构应注册局部命令历史。")
	assert_ne(local_history, global_history, "编辑器不得复用全局对局命令历史。")
	if is_instance_valid(local_history):
		assert_true(local_history.max_history_size == 128, "编辑器应使用独立历史容量。")

	parent_context.remove_child(editor_context)
	editor_context.free()
	assert_false(is_instance_valid(editor_context), "编辑器离树后应释放 scoped Context 节点。")
	parent_architecture.dispose()


func test_custom_board_schema_requires_uuid_owned_topology_identity() -> void:
	var board_id: String = GFUuid.generate_v7(1_000_000)
	var data: CustomBoardData = CustomBoardData.new()
	data.custom_board_id = board_id
	data.display_name = "Cross Five"
	data.created_at = 1000
	data.updated_at = 1001
	data.topology = BoardTopology.create_cross(2, 1, CustomBoardData.get_topology_id(board_id))
	var serialized: Dictionary = data.to_dict()

	assert_true(CustomBoardData.from_dict(serialized) != null, "当前严格玩家棋盘 schema 应可往返。")
	var wrong_identity: Dictionary = serialized.duplicate(true)
	var wrong_topology: Dictionary = GFVariantData.get_option_dictionary(wrong_identity, "topology")
	wrong_topology[&"topology_id"] = "board.custom.wrong"
	wrong_identity["topology"] = wrong_topology
	assert_null(CustomBoardData.from_dict(wrong_identity), "玩家棋盘必须由 UUID 派生稳定拓扑 ID。")
	var legacy_field: Dictionary = serialized.duplicate(true)
	legacy_field["grid_size"] = Vector2i(5, 5)
	assert_null(CustomBoardData.from_dict(legacy_field), "严格 schema 不得接受旧尺寸旁路字段。")


func test_custom_board_catalog_rejects_duplicate_ids_atomically() -> void:
	var board_id: String = GFUuid.generate_v7(2_000_000)
	var data: CustomBoardData = CustomBoardData.new()
	data.custom_board_id = board_id
	data.display_name = "Duplicate Probe"
	data.created_at = 2000
	data.updated_at = 2000
	data.topology = BoardTopology.create_rectangle(
		Vector2i(3, 3),
		CustomBoardData.get_topology_id(board_id)
	)
	var provider: CustomBoardCatalogSaveData = CustomBoardCatalogSaveData.new()
	var replace_error: Error = provider.replace_section_data({
		"items": [data.to_dict(), data.to_dict()],
	})

	assert_true(replace_error == ERR_INVALID_DATA, "目录必须拒绝重复稳定 ID。")
	assert_true(provider.get_section_data() == {"items": []}, "失败替换不得泄漏部分目录状态。")


func test_board_editor_scene_initializes_with_injected_topology_context() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.register_utility(GFPlatformRuntime, GFPlatformRuntime.new())
	await architecture.register_utility(GamePlatformUtility, GamePlatformUtility.new())
	await architecture.register_utility(GFInputMappingUtility, GFInputMappingUtility.new())
	await architecture.register_utility(GFPointerGestureUtility, GFPointerGestureUtility.new())
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GFViewportUtility, GFViewportUtility.new())
	await architecture.init()
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var panel_node: Node = _BOARD_EDITOR_SCENE.instantiate()
	assert_true(panel_node is BoardEditorDialog, "棋盘编辑器场景根节点应使用强类型控制器。")
	if not panel_node is BoardEditorDialog:
		architecture.dispose()
		return
	var panel: BoardEditorDialog = panel_node
	panel.configure(_make_template(), BoardTopology.create_rectangle(Vector2i(4, 4)))
	context.add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame

	var canvas_node: Node = panel.get_node_or_null(
		"OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/CanvasViewport/CanvasWorld/BoardEditorCanvas"
	)
	var canvas_viewport: Control = panel.get_node_or_null(
		"OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/CanvasViewport"
	) as Control
	var viewport_controller: Node = canvas_viewport.get_node_or_null(
		"BoardEditorViewportController"
	)
	var responsive_controller: Node = panel.get_node_or_null(
		"BoardEditorResponsiveLayoutController"
	)
	var apply_node: Node = panel.get_node_or_null(
		"OuterMargin/EditorPanel/InnerMargin/RootVBox/Footer/ApplyButton"
	)
	assert_true(canvas_node is BoardEditorCanvas, "编辑器应包含可绘制的强类型棋盘画布。")
	assert_true(canvas_viewport.clip_contents, "编辑画布必须由独立裁剪视口承载。")
	assert_true(
		canvas_node.get_parent() is Node2D,
		"编辑画布必须位于可统一缩放平移的稳定世界节点下。"
	)
	assert_true(
		viewport_controller is BoardEditorViewportController,
		"编辑画布必须使用 GF 手势驱动的专用视口控制器。"
	)
	assert_true(
		responsive_controller is BoardEditorResponsiveLayoutController,
		"编辑器必须使用专用安全区与断点控制器。"
	)
	assert_true(apply_node is Button, "编辑器应包含显式使用命令。")
	if apply_node is Button:
		var apply_button: Button = apply_node
		assert_false(apply_button.disabled, "有效初始拓扑应允许直接使用。")
	if responsive_controller is BoardEditorResponsiveLayoutController:
		var responsive: BoardEditorResponsiveLayoutController = responsive_controller
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.size = Vector2(390.0, 844.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var content: BoxContainer = panel.get_node(
			"OuterMargin/EditorPanel/InnerMargin/RootVBox/Content"
		) as BoxContainer
		var mobile_sections: HBoxContainer = panel.get_node(
			"OuterMargin/EditorPanel/InnerMargin/RootVBox/MobileSections"
		) as HBoxContainer
		var tools: VBoxContainer = content.get_node("Tools") as VBoxContainer
		var library: VBoxContainer = content.get_node("Library") as VBoxContainer
		assert_true(
			responsive.get_layout_mode()
			== BoardEditorResponsiveLayoutController.LayoutMode.PORTRAIT
		)
		assert_true(content.vertical, "竖屏编辑区必须改为纵向排列。")
		assert_true(mobile_sections.visible, "竖屏必须显示编辑/模板分区切换。")
		assert_true(tools.visible and canvas_viewport.visible and not library.visible)
		responsive.show_library_section()
		assert_true(not tools.visible and not canvas_viewport.visible and library.visible)

	context.remove_child(panel)
	panel.free()
	architecture.dispose()
	await get_tree().process_frame


func test_board_editor_uses_feature_owned_gf_input_and_signal_contracts() -> void:
	var action_ids: Array[StringName] = []
	for mapping: GFInputMapping in _BOARD_EDITOR_INPUT_CONTEXT.mappings:
		action_ids.append(mapping.get_action_id())
	var source: String = _read_text(_BOARD_EDITOR_SCRIPT_PATH)

	assert_true(_BOARD_EDITOR_INPUT_CONTEXT.get_context_id() == &"board_editor")
	assert_true(action_ids.has(&"board_editor_undo"))
	assert_true(action_ids.has(&"board_editor_redo"))
	assert_true(source.contains("GFInputMappingUtility"))
	assert_true(source.contains("GFSignalUtility"))
	assert_true(source.contains("_board_editor_context.get_history()"))
	assert_false(source.contains("GFCommandHistoryUtility.new()"))
	var context_source: String = _read_text(_BOARD_EDITOR_CONTEXT_SCRIPT_PATH)
	assert_true(context_source.contains("GFNodeContext.ScopeMode.SCOPED"))
	assert_true(context_source.contains("bind_utility(GFCommandHistoryUtility)"))
	assert_false(source.contains("is_action_pressed(\"undo\")"))
	assert_false(source.contains("is_action_pressed(\"redo\")"))


func test_editor_canvas_has_stable_large_world_extent_and_continuous_strokes() -> void:
	var canvas: BoardEditorCanvas = BoardEditorCanvas.new()
	canvas.cell_size = 32.0
	canvas.content_padding = 10.0
	canvas.set_grid_size(Vector2i(64, 48))
	var content_rect: Rect2 = canvas.get_content_rect()
	var line: Array[Vector2i] = BoardEditorCanvas.rasterize_grid_line(
		Vector2i.ZERO,
		Vector2i(7, 3)
	)
	var first_cell: Vector2i = line[0] if not line.is_empty() else Vector2i(-1, -1)
	var last_cell: Vector2i = line[line.size() - 1] if not line.is_empty() else Vector2i(-1, -1)

	assert_true(
		content_rect.size.is_equal_approx(Vector2(2068.0, 1556.0)),
		"超大草稿应扩展稳定世界尺寸，而不是压缩单格命中区域。"
	)
	assert_true(first_cell == Vector2i.ZERO)
	assert_true(last_cell == Vector2i(7, 3))
	for index: int in range(1, line.size()):
		var step: Vector2i = line[index] - line[index - 1]
		assert_true(
			absi(step.x) <= 1 and absi(step.y) <= 1,
			"快速拖动的相邻采样之间不得漏格。"
		)
	canvas.free()


func test_editor_responsive_layout_uses_mobile_sections() -> void:
	assert_true(
		BoardEditorResponsiveLayoutController.classify_layout(Vector2(1440.0, 900.0))
		== BoardEditorResponsiveLayoutController.LayoutMode.DESKTOP
	)
	assert_true(
		BoardEditorResponsiveLayoutController.classify_layout(Vector2(900.0, 560.0))
		== BoardEditorResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE
	)
	assert_true(
		BoardEditorResponsiveLayoutController.classify_layout(Vector2(390.0, 844.0))
		== BoardEditorResponsiveLayoutController.LayoutMode.PORTRAIT
	)


func test_editor_viewport_reserves_single_touch_for_drawing_and_multitouch_for_gf_gestures() -> void:
	var source: String = _read_text(_BOARD_EDITOR_VIEWPORT_SCRIPT_PATH)

	assert_true(source.contains("GFPointerGestureUtility"))
	assert_true(source.contains("GFViewportUtility"))
	assert_true(source.contains("pointer_count < 2"))
	assert_true(source.contains("_canvas.cancel_stroke()"))


# --- 私有/辅助方法 ---

func _make_template() -> BoardTopologyTemplate:
	var topology_template: BoardTopologyTemplate = BoardTopologyTemplate.new()
	topology_template.template_id = &"board_template.editor_test"
	topology_template.default_size = Vector2i(4, 4)
	topology_template.min_size = Vector2i(3, 3)
	topology_template.max_size = Vector2i(8, 8)
	topology_template.allow_custom_topology = true
	return topology_template


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
