## 验证动态重建控件的焦点连续性与确认弹窗的触控目标契约。
extends GutTest


# --- 常量 ---

const _TILE_LAB_SCENE: PackedScene = preload(
	"res://features/tile_lab/scenes/ui/tile_lab_dialog.tscn"
)
const _PLAYER_PROFILE_SCENE: PackedScene = preload(
	"res://features/player_profiles/scenes/ui/player_profile_dialog.tscn"
)
const _RECIPE_ID: StringName = &"tile.recipe.test.focus"
const _MINIMUM_TOUCH_TARGET_SIZE: float = 44.0


# --- 测试用例 ---

func test_tile_lab_recipe_rebuild_restores_same_recipe_focus() -> void:
	var architecture: GFArchitecture = await _make_ui_architecture()
	var context: TestArchitectureContext = _make_context(architecture)
	var dialog_node: Node = _TILE_LAB_SCENE.instantiate()
	assert_true(dialog_node is TileLabDialog)
	if not dialog_node is TileLabDialog:
		dialog_node.free()
		architecture.dispose()
		return
	var dialog: TileLabDialog = dialog_node
	context.add_child(dialog)
	await get_tree().process_frame

	var tile_lab: _TileLabStub = _TileLabStub.new()
	dialog._tile_lab = tile_lab
	dialog._selected_recipe_ids = [_RECIPE_ID]
	dialog._rebuild_recipe_buttons()
	var original_button: CheckButton = _find_recipe_button(dialog, _RECIPE_ID)
	assert_not_null(original_button)
	if original_button == null:
		architecture.dispose()
		return
	original_button.grab_focus()
	assert_true(original_button.has_focus())

	original_button.toggled.emit(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var rebuilt_button: CheckButton = _find_recipe_button(dialog, _RECIPE_ID)
	assert_not_null(rebuilt_button)
	assert_ne(
		rebuilt_button,
		original_button,
		"切换 Recipe 后应由新控件接管已释放控件的焦点。"
	)
	if rebuilt_button != null:
		assert_true(
			rebuilt_button.has_focus(),
			"Recipe 列表重建后必须恢复到同一 Recipe 的键盘/手柄焦点。"
		)
	tile_lab.dispose()
	architecture.dispose()


func test_player_profile_delete_confirmation_buttons_meet_touch_contract() -> void:
	var architecture: GFArchitecture = await _make_ui_architecture()
	var context: TestArchitectureContext = _make_context(architecture)
	var dialog_node: Node = _PLAYER_PROFILE_SCENE.instantiate()
	assert_true(dialog_node is PlayerProfileDialog)
	if not dialog_node is PlayerProfileDialog:
		dialog_node.free()
		architecture.dispose()
		return
	var dialog: PlayerProfileDialog = dialog_node
	context.add_child(dialog)
	await get_tree().process_frame

	var confirmation_node: Node = dialog.find_child(
		"DeleteConfirmation",
		true,
		false
	)
	assert_true(confirmation_node is ConfirmationDialog)
	if confirmation_node is ConfirmationDialog:
		var confirmation: ConfirmationDialog = confirmation_node
		for button: Button in [
			confirmation.get_ok_button(),
			confirmation.get_cancel_button(),
		]:
			assert_not_null(button)
			if button == null:
				continue
			assert_gte(
				button.custom_minimum_size.x,
				112.0,
				"确认弹窗操作按钮宽度不得小于 112px。"
			)
			assert_gte(
				button.custom_minimum_size.y,
				_MINIMUM_TOUCH_TARGET_SIZE,
				"确认弹窗操作按钮高度不得小于 44px。"
			)
	architecture.dispose()


# --- 私有/辅助方法 ---

func _make_ui_architecture() -> GFArchitecture:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.init()
	return architecture


func _make_context(
	architecture: GFArchitecture
) -> TestArchitectureContext:
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	return context


func _find_recipe_button(
	dialog: TileLabDialog,
	recipe_id: StringName
) -> CheckButton:
	var recipe_list: Node = dialog.find_child("RecipeList", true, false)
	if recipe_list == null:
		return null
	for child: Node in recipe_list.get_children():
		if not child is CheckButton:
			continue
		var metadata_value: Variant = child.get_meta(&"recipe_id", &"")
		if metadata_value is StringName and metadata_value == recipe_id:
			var button: CheckButton = child
			return button
	return null


# --- 内部类 ---

class _TileLabStub extends TileLabSystem:
	## 返回固定 Recipe 条目并反映当前选择状态。
	## @param selected_recipe_ids: 当前保持顺序的 Recipe 清单。
	func get_recipe_entries(
		selected_recipe_ids: Array[StringName] = []
	) -> Array[Dictionary]:
		return [{
			&"recipe_id": _RECIPE_ID,
			&"display_name_key": &"TILE_RECIPE_CLASSIC_MERGE",
			&"selected": selected_recipe_ids.has(_RECIPE_ID),
			&"compatible": true,
			&"conflict": {},
		}]


	## 返回始终成功的组合校验报告。
	## @param base_definition_id: 要校验的基底定义稳定 ID。
	## @param recipe_ids: 按应用顺序排列的 Recipe 稳定 ID。
	func validate_composition(
		base_definition_id: StringName,
		recipe_ids: Array[StringName]
	) -> GFValidationReport:
		return GFValidationReport.new(
			"TileLabFocusContract",
			{
				"base_definition_id": base_definition_id,
				"recipe_ids": recipe_ids.duplicate(),
			}
		)
