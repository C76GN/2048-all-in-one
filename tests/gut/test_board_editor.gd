## 验证棋盘编辑草稿、GF 命令历史与严格自定义棋盘 schema。
extends GutTest


# --- 常量 ---

const _BOARD_EDITOR_SCENE: PackedScene = preload(
	"res://features/board_editor/scenes/ui/board_editor_dialog.tscn"
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
		"OuterMargin/EditorPanel/InnerMargin/RootVBox/Content/BoardEditorCanvas"
	)
	var apply_node: Node = panel.get_node_or_null(
		"OuterMargin/EditorPanel/InnerMargin/RootVBox/Footer/ApplyButton"
	)
	assert_true(canvas_node is BoardEditorCanvas, "编辑器应包含可绘制的强类型棋盘画布。")
	assert_true(apply_node is Button, "编辑器应包含显式使用命令。")
	if apply_node is Button:
		var apply_button: Button = apply_node
		assert_false(apply_button.disabled, "有效初始拓扑应允许直接使用。")

	context.remove_child(panel)
	panel.free()
	architecture.dispose()


# --- 私有/辅助方法 ---

func _make_template() -> BoardTopologyTemplate:
	var topology_template: BoardTopologyTemplate = BoardTopologyTemplate.new()
	topology_template.template_id = &"board_template.editor_test"
	topology_template.default_size = Vector2i(4, 4)
	topology_template.min_size = Vector2i(3, 3)
	topology_template.max_size = Vector2i(8, 8)
	topology_template.allow_custom_topology = true
	return topology_template
