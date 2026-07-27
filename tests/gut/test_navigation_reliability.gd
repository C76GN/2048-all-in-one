## 验证主菜单继续流程与历史列表的破坏性操作、焦点可靠性。
extends GutTest


# --- 常量 ---

const _MAIN_MENU_SCENE: PackedScene = preload(
	"res://features/navigation/scenes/menus/main_menu.tscn"
)
const _BOOKMARK_LIST_SCENE: PackedScene = preload(
	"res://features/bookmarks/scenes/menus/bookmark_list.tscn"
)
const _REPLAY_LIST_SCENE: PackedScene = preload(
	"res://features/replays/scenes/menus/replay_list.tscn"
)
const _CLASSIC_MODE_CONFIG: GameModeConfig = preload(
	"res://features/gameplay/resources/modes/classic_mode_config.tres"
)
const _GAME_SCENE_PATH: String = "res://features/gameplay/scenes/game/game_play.tscn"


# --- 测试用例 ---

func test_main_menu_splits_continue_and_load_save_actions() -> void:
	var menu_node: Node = _MAIN_MENU_SCENE.instantiate()
	assert_true(menu_node is MainMenu, "主菜单场景应实例化为 MainMenu。")
	if not menu_node is MainMenu:
		menu_node.free()
		return
	var menu: MainMenu = menu_node
	var continue_button: Node = menu.find_child("ContinueGameButton", true, false)
	var load_button: Node = menu.find_child("LoadBookmarkButton", true, false)
	assert_true(continue_button is Button, "主菜单应提供独立的继续游戏按钮。")
	assert_true(load_button is Button, "主菜单应保留独立的读取存档按钮。")
	assert_ne(continue_button, load_button, "继续游戏与读取存档不得复用同一动作按钮。")
	assert_true(
		menu.game_scene_path == _GAME_SCENE_PATH,
		"继续游戏必须声明目标游戏场景。"
	)
	menu.free()


func test_continue_accepts_only_current_matching_bookmark_contract() -> void:
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()
	var bookmark: BookmarkData = BookmarkData.new()
	bookmark.mode_config_path = _CLASSIC_MODE_CONFIG.resource_path
	bookmark.ruleset_id = _CLASSIC_MODE_CONFIG.ruleset_id
	bookmark.ruleset_version = _CLASSIC_MODE_CONFIG.ruleset_version
	bookmark.ruleset_fingerprint = determinism.calculate_ruleset_fingerprint(
		_CLASSIC_MODE_CONFIG
	)
	bookmark.target_tile_value = _CLASSIC_MODE_CONFIG.target_tile_value

	assert_true(
		MainMenu._is_bookmark_valid_for_resume(
			bookmark,
			_CLASSIC_MODE_CONFIG,
			determinism
		),
		"规则集与目标契约匹配的书签应允许一键继续。"
	)
	bookmark.target_tile_value += 1
	assert_false(
		MainMenu._is_bookmark_valid_for_resume(
			bookmark,
			_CLASSIC_MODE_CONFIG,
			determinism
		),
		"目标契约漂移的书签不得被一键继续。"
	)


func test_resume_bookmark_sets_launch_state_and_routes_to_game() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var app_config: AppConfigModel = AppConfigModel.new()
	var router: _RouteSpy = _RouteSpy.new()
	await architecture.register_model(AppConfigModel, app_config)
	await architecture.register_system(SceneRouterSystem, router)
	await architecture.init()

	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)
	var menu_node: Node = _MAIN_MENU_SCENE.instantiate()
	assert_true(menu_node is MainMenu, "主菜单场景应实例化为 MainMenu。")
	if menu_node is MainMenu:
		var menu: MainMenu = menu_node
		context.add_child(menu)
		await get_tree().process_frame
		var bookmark: BookmarkData = BookmarkData.new()
		bookmark.bookmark_id = GFUuid.generate_v7()
		app_config.current_replay_data.set_value(ReplayData.new())
		menu._resume_bookmark(bookmark)
		var selected_value: Variant = app_config.selected_bookmark_data.get_value()
		assert_true(
			selected_value is BookmarkData,
			"继续游戏必须写入 BookmarkData 启动状态。"
		)
		if selected_value is BookmarkData:
			var selected_bookmark: BookmarkData = selected_value
			assert_same(
				selected_bookmark,
				bookmark,
				"继续游戏必须把最近有效书签写入启动状态。"
			)
		var replay_cleared: bool = app_config.current_replay_data.get_value() == null
		assert_true(
			replay_cleared,
			"继续书签前必须清除回放启动状态。"
		)
		assert_true(
			router.last_scene_path == _GAME_SCENE_PATH,
			"继续游戏应路由到游戏场景。"
		)
	architecture.dispose()


func test_empty_history_lists_focus_back_button() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.init()
	var context: TestArchitectureContext = TestArchitectureContext.new()
	context.test_architecture = architecture
	add_child_autoqfree(context)

	for list_scene: PackedScene in [_BOOKMARK_LIST_SCENE, _REPLAY_LIST_SCENE]:
		var list_node: Node = list_scene.instantiate()
		assert_true(list_node is BaseListMenu, "历史列表场景应继承 BaseListMenu。")
		if not list_node is BaseListMenu:
			list_node.free()
			continue
		var list_menu: BaseListMenu = list_node
		context.add_child(list_menu)
		await get_tree().process_frame
		await get_tree().process_frame
		var back_button: Node = list_menu.find_child("BackButton", true, false)
		assert_true(back_button is Button, "空历史列表必须保留返回按钮。")
		if back_button is Button:
			var back_control: Button = back_button
			assert_true(
				back_control.has_focus(),
				"空历史列表应把键盘/手柄焦点交给返回按钮。"
			)
		assert_true(
			list_menu.find_child("DeleteConfirmationDialog", true, false)
			is ConfirmationDialog,
			"历史列表删除前必须经过确认弹窗。"
		)
		var confirmation_node: Node = list_menu.find_child(
			"DeleteConfirmationDialog",
			true,
			false
		)
		if confirmation_node is ConfirmationDialog:
			var confirmation: ConfirmationDialog = confirmation_node
			assert_true(
				confirmation.has_theme_stylebox_override("panel"),
				"历史列表删除确认弹窗必须使用项目纸张面板样式。"
			)
			assert_true(
				confirmation.has_theme_stylebox_override("embedded_border"),
				"历史列表删除确认弹窗必须使用项目标题栏边框样式。"
			)
			assert_gte(
				confirmation.get_theme_constant("buttons_min_height"),
				roundi(BaseListMenu._MINIMUM_TOUCH_TARGET_SIZE),
				"删除确认弹窗必须在 Window 主题层声明 44px 按钮高度。"
			)
			for action_button: Button in [
				confirmation.get_ok_button(),
				confirmation.get_cancel_button(),
			]:
				assert_gte(
					action_button.custom_minimum_size.x,
					BaseListMenu._DIALOG_ACTION_MINIMUM_WIDTH,
					"历史列表删除确认按钮宽度不得小于 112px。"
				)
				assert_gte(
					action_button.custom_minimum_size.y,
					BaseListMenu._MINIMUM_TOUCH_TARGET_SIZE,
					"历史列表删除确认按钮高度不得小于 44px。"
				)
		var error_node: Node = list_menu.find_child(
			"DeleteErrorDialog",
			true,
			false
		)
		assert_true(error_node is AcceptDialog, "历史列表删除失败必须显示错误弹窗。")
		if error_node is AcceptDialog:
			var error_dialog: AcceptDialog = error_node
			assert_true(
				error_dialog.has_theme_stylebox_override("panel"),
				"历史列表删除失败弹窗必须使用项目纸张面板样式。"
			)
			assert_true(
				error_dialog.ok_button_text == tr("DIALOG_ACKNOWLEDGE_ACTION"),
				"删除失败弹窗确认动作必须使用项目本地化文案。"
			)
			var error_action: Button = error_dialog.get_ok_button()
			assert_gte(
				error_action.custom_minimum_size.x,
				BaseListMenu._DIALOG_ACTION_MINIMUM_WIDTH,
				"历史列表删除失败确认按钮宽度不得小于 112px。"
			)
			assert_gte(
				error_action.custom_minimum_size.y,
				BaseListMenu._MINIMUM_TOUCH_TARGET_SIZE,
				"历史列表删除失败确认按钮高度不得小于 44px。"
			)
		var selected: Resource = Resource.new()
		list_menu._selected_resource = selected
		list_menu._on_delete_button_pressed()
		await get_tree().process_frame
		if confirmation_node is ConfirmationDialog:
			var opened_confirmation: ConfirmationDialog = confirmation_node
			assert_true(opened_confirmation.visible, "删除确认弹窗必须真实打开。")
			assert_true(
				opened_confirmation.get_cancel_button().has_focus(),
				"不可撤销删除弹窗必须把键盘/手柄默认焦点交给取消动作。"
			)
			opened_confirmation.hide()
			list_menu._on_delete_canceled()
		list_menu._show_delete_error(ERR_CANT_CREATE)
		await get_tree().process_frame
		if error_node is AcceptDialog:
			var opened_error: AcceptDialog = error_node
			assert_true(opened_error.visible, "删除失败弹窗必须真实打开。")
			assert_true(
				opened_error.get_ok_button().has_focus(),
				"删除失败弹窗打开后必须把键盘/手柄焦点交给确认动作。"
			)
			opened_error.hide()
		context.remove_child(list_menu)
		list_menu.free()
		await get_tree().process_frame
	architecture.dispose()


func test_delete_failure_preserves_selection_and_skips_refresh() -> void:
	var menu: _DeleteProbeMenu = _DeleteProbeMenu.new()
	var selected: Resource = Resource.new()
	menu._selected_resource = selected
	menu._pending_delete_resource = selected
	menu.delete_result = ERR_CANT_CREATE
	await menu._on_delete_confirmed()
	assert_push_error(
		"删除操作失败",
		"删除持久化失败仍应进入诊断日志。"
	)
	assert_same(menu._selected_resource, selected, "删除失败后必须保留当前选择。")
	assert_true(menu.populate_count == 0, "删除失败后不得刷新并伪装成成功。")

	menu._pending_delete_resource = selected
	menu.delete_result = OK
	await menu._on_delete_confirmed()
	assert_null(menu._selected_resource, "删除成功后应清空旧选择。")
	assert_true(menu.populate_count == 1, "只有删除成功后才能刷新列表。")
	menu.free()


# --- 内部类 ---

class _RouteSpy extends SceneRouterSystem:
	var last_scene_path: String = ""

	func get_required_utilities() -> Array[Script]:
		return []

	func ready() -> void:
		pass

	## 记录最后一次场景导航目标。
	## @param path: 要导航到的 Godot 资源路径。
	func goto_scene(path: String) -> void:
		last_scene_path = path


class _DeleteProbeMenu extends BaseListMenu:
	var delete_result: Error = OK
	var populate_count: int = 0

	func _do_delete_logic(_data: Resource) -> Error:
		return delete_result

	func _populate_list() -> void:
		populate_count += 1
