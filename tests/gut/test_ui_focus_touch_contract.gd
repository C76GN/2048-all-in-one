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
const _CONFLICT_RECIPE_ID: StringName = &"tile.recipe.test.conflict"
const _MINIMUM_TOUCH_TARGET_SIZE: float = 44.0
const _PLAYER_VISIBLE_SCENE_PATHS: Array[String] = [
	"res://features/achievements/scenes/ui/achievement_list_dialog.tscn",
	"res://features/board_editor/scenes/ui/board_editor_dialog.tscn",
	"res://features/bookmarks/scenes/menus/bookmark_list.tscn",
	"res://features/bookmarks/scenes/ui/bookmark_list_item.tscn",
	"res://features/gameplay/scenes/game/game_play.tscn",
	"res://features/gameplay/scenes/ui/game_over_menu.tscn",
	"res://features/gameplay/scenes/ui/hud.tscn",
	"res://features/gameplay/scenes/ui/pause_menu.tscn",
	"res://features/gameplay/scenes/ui/target_reached_menu.tscn",
	"res://features/navigation/scenes/menus/main_menu.tscn",
	"res://features/navigation/scenes/menus/mode_selection.tscn",
	"res://features/navigation/scenes/ui/mode_card.tscn",
	"res://features/player_profiles/scenes/ui/player_profile_dialog.tscn",
	"res://features/replays/scenes/menus/replay_list.tscn",
	"res://features/replays/scenes/ui/replay_list_item.tscn",
	"res://features/settings/scenes/menus/settings_menu.tscn",
	"res://features/tile_catalog/scenes/ui/tile_catalog_card.tscn",
	"res://features/tile_catalog/scenes/ui/tile_catalog_dialog.tscn",
	"res://features/tile_lab/scenes/ui/tile_lab_dialog.tscn",
]


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

	var refreshed_button: CheckButton = _find_recipe_button(dialog, _RECIPE_ID)
	assert_not_null(refreshed_button)
	assert_true(
		refreshed_button == original_button,
		"切换 Recipe 应原位更新稳定控件，不得释放并重建同一 recipe_id。"
	)
	if refreshed_button != null:
		assert_true(
			refreshed_button.has_focus(),
			"Recipe 原位刷新后必须保留同一键盘/手柄焦点。"
		)
	tile_lab.dispose()
	architecture.dispose()


func test_tile_lab_recipe_controls_hide_internal_ids_and_keep_checked_text_readable() -> void:
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
	var selected_button: CheckButton = _find_recipe_button(
		dialog,
		_RECIPE_ID
	)
	var conflict_button: CheckButton = _find_recipe_button(
		dialog,
		_CONFLICT_RECIPE_ID
	)
	assert_not_null(selected_button)
	assert_not_null(conflict_button)
	if selected_button != null:
		assert_false(
			selected_button.tooltip_text.contains("tile.recipe"),
			"Recipe tooltip 不得向玩家泄露内部稳定 ID。"
		)
		assert_true(
			selected_button.tooltip_text.contains(selected_button.text),
			"Recipe tooltip 应使用已经本地化的玩家可见名称。"
		)
		assert_true(
			selected_button.has_theme_color_override(
				"font_hover_pressed_color"
			),
			"选中 Recipe 的 hover+pressed 文字颜色必须显式覆盖。"
		)
		assert_true(
			selected_button.get_theme_color("font_hover_pressed_color")
			== selected_button.get_theme_color("font_pressed_color"),
			"选中 Recipe 在鼠标悬停时必须保持可读文字颜色。"
		)
	if conflict_button != null:
		assert_true(conflict_button.disabled)
		assert_false(
			conflict_button.tooltip_text.contains("tile.recipe"),
			"冲突说明不得回退为内部 Recipe ID。"
		)
		assert_true(
			conflict_button.tooltip_text.contains(conflict_button.text),
			"冲突说明应标明玩家尝试选择的 Recipe。"
		)
	tile_lab.dispose()
	architecture.dispose()


func test_tile_lab_uses_one_vertical_scroll_owner_per_layout() -> void:
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

	var body_scroll_node: Node = dialog.find_child(
		"BodyScroll",
		true,
		false
	)
	var recipes_scroll_node: Node = dialog.find_child(
		"RecipesScroll",
		true,
		false
	)
	assert_true(body_scroll_node is ScrollContainer)
	assert_true(recipes_scroll_node is ScrollContainer)
	if (
		not body_scroll_node is ScrollContainer
		or not recipes_scroll_node is ScrollContainer
	):
		architecture.dispose()
		return
	var body_scroll: ScrollContainer = body_scroll_node
	var recipes_scroll: ScrollContainer = recipes_scroll_node

	dialog.size = Vector2(1280.0, 720.0)
	dialog._apply_responsive_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		body_scroll.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_DISABLED,
		"桌面双栏不应再出现页面级纵向滚动。"
	)
	assert_true(
		recipes_scroll.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_AUTO,
		"桌面双栏只允许 Recipe 列表承担纵向滚动。"
	)
	assert_true(recipes_scroll.follow_focus)
	assert_false(body_scroll.follow_focus)
	var workspace_node: Node = dialog.find_child(
		"Workspace",
		true,
		false
	)
	assert_true(workspace_node is Control)
	if workspace_node is Control:
		var workspace: Control = workspace_node
		assert_lte(
			workspace.size.y,
			body_scroll.size.y + 1.0,
			"桌面 720px 高度下工作区必须完整落入可见 Body，不得静默裁切。"
		)

	dialog.size = Vector2(720.0, 720.0)
	dialog._apply_responsive_layout()
	assert_true(
		body_scroll.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_AUTO,
		"紧凑单列应由页面滚动容纳完整工作区。"
	)
	assert_true(
		recipes_scroll.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_DISABLED,
		"紧凑单列必须禁用 Recipe 内层滚动，避免嵌套滚动。"
	)
	assert_true(body_scroll.follow_focus)
	assert_false(recipes_scroll.follow_focus)
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


func test_player_profile_empty_states_center_inside_scroll_content() -> void:
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

	var mode_empty: Node = dialog.find_child("ModeEmptyLabel", true, false)
	var leaderboard_empty: Node = dialog.find_child(
		"LeaderboardEmptyLabel",
		true,
		false
	)
	assert_true(mode_empty is Label)
	assert_true(leaderboard_empty is Label)
	if mode_empty is Label:
		var mode_empty_label: Label = mode_empty
		assert_true(mode_empty_label.visible)
		assert_true(
			mode_empty_label.get_parent() is CenterContainer,
			"个人信息空态必须位于滚动内容区的居中容器内。"
		)
		assert_true(
			String(mode_empty_label.get_parent().get_parent().name) == "ModeContent"
		)
	if leaderboard_empty is Label:
		var leaderboard_empty_label: Label = leaderboard_empty
		assert_true(leaderboard_empty_label.visible)
		assert_true(
			leaderboard_empty_label.get_parent() is CenterContainer,
			"排行榜空态必须位于滚动内容区的居中容器内。"
		)
		assert_true(
			String(leaderboard_empty_label.get_parent().get_parent().name)
			== "LeaderboardContent"
		)

	var leaderboard_filter: Node = dialog.find_child(
		"LeaderboardGroupOption",
		true,
		false
	)
	assert_true(leaderboard_filter is OptionButton)
	if leaderboard_filter is OptionButton:
		var leaderboard_option: OptionButton = leaderboard_filter
		assert_true(leaderboard_option.item_count == 1)
		assert_true(leaderboard_option.selected == 0)
		assert_true(
			leaderboard_option.get_item_text(0) == tr("LOCAL_LEADERBOARD_ALL_MODES"),
			"无成绩时的模式筛选必须明确显示“全部模式”。"
		)
		assert_true(leaderboard_option.disabled)
	architecture.dispose()


func test_player_profile_rows_update_in_place_by_stable_business_id() -> void:
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

	var first_summaries: Array[Dictionary] = [{
		&"mode_id": "classic",
		&"plays": 1,
		&"best_score": 128,
		&"max_tile": 16,
		&"best_duration_msec": 1000,
		&"average_duration_msec": 1000,
	}]
	var created_rows: Array[Control] = dialog._sync_mode_summary_rows(
		first_summaries
	)
	assert_true(created_rows.size() == 1)
	var first_row_value: Variant = dialog._mode_rows_by_id.get("classic")
	assert_true(first_row_value is Control)
	if first_row_value is Control:
		var first_row: Control = first_row_value
		var updated_summaries: Array[Dictionary] = [{
			&"mode_id": "classic",
			&"plays": 2,
			&"best_score": 256,
			&"max_tile": 32,
			&"best_duration_msec": 900,
			&"average_duration_msec": 950,
		}]
		var second_created_rows: Array[Control] = (
			dialog._sync_mode_summary_rows(updated_summaries)
		)
		var refreshed_row_value: Variant = (
			dialog._mode_rows_by_id.get("classic")
		)
		var same_mode_row: bool = refreshed_row_value == first_row
		assert_true(second_created_rows.is_empty())
		assert_true(
			same_mode_row,
			"玩家模式汇总应按 mode_id 原位更新，不得全量重建。"
		)
		var inserted_mode_rows: Array[Control] = dialog._sync_mode_summary_rows([
			{
				&"mode_id": "fibonacci",
				&"plays": 1,
				&"best_score": 128,
				&"max_tile": 16,
				&"best_duration_msec": 1200,
				&"average_duration_msec": 1200,
			},
			updated_summaries[0],
		])
		assert_true(inserted_mode_rows.size() == 1)
		assert_true(
			dialog._mode_list.get_child(0) == inserted_mode_rows[0]
			and dialog._mode_list.get_child(1) == first_row,
			"新模式插入缓存行之前时，服务端顺序与旧行身份都必须保留。"
		)

	var leaderboard_rows: Array[Dictionary] = [{
		&"account_id": "local-player",
		&"rank": 1,
		&"display_name": "Player",
		&"result": null,
	}]
	var first_leaderboard_created: Array[Control] = (
		dialog._sync_leaderboard_rows(leaderboard_rows)
	)
	assert_true(first_leaderboard_created.size() == 1)
	var leaderboard_row_value: Variant = (
		dialog._leaderboard_rows_by_account_id.get("local-player")
	)
	var second_leaderboard_created: Array[Control] = (
		dialog._sync_leaderboard_rows(leaderboard_rows)
	)
	var same_leaderboard_row: bool = (
		dialog._leaderboard_rows_by_account_id.get("local-player")
		== leaderboard_row_value
	)
	assert_true(second_leaderboard_created.is_empty())
	assert_true(
		same_leaderboard_row,
		"本地排行榜应按 account_id 保留同一行实例。"
	)
	var inserted_leaderboard_rows: Array[Control] = (
		dialog._sync_leaderboard_rows([
			{
				&"account_id": "new-player",
				&"rank": 1,
				&"display_name": "New Player",
				&"result": null,
			},
			{
				&"account_id": "local-player",
				&"rank": 2,
				&"display_name": "Player",
				&"result": null,
			},
		])
	)
	assert_true(inserted_leaderboard_rows.size() == 1)
	var inserted_leaderboard_order_preserved: bool = (
		dialog._leaderboard_list.get_child(0) == inserted_leaderboard_rows[0]
		and dialog._leaderboard_list.get_child(1) == leaderboard_row_value
	)
	assert_true(
		inserted_leaderboard_order_preserved,
		"新账号插入缓存行之前时，榜单排名与旧行身份都必须保留。"
	)
	assert_true(
		PlayerProfileDialog._snapshot_matches_account_id(
			{&"active_account_id": "local-player"},
			"local-player"
		)
	)
	assert_false(
		PlayerProfileDialog._snapshot_matches_account_id(
			{&"active_account_id": "previous-player"},
			"local-player"
		),
		"账号切换后不得把旧账号快照投影到新 selector。"
	)
	dialog._account_summary_label.text = "旧账号统计"
	dialog._mode_list.visible = true
	dialog._leaderboard_list.visible = true
	dialog._leaderboard_group_option.clear()
	dialog._leaderboard_group_option.add_item("旧账号榜单")
	dialog._prepare_progress_snapshot_pending()
	assert_true(dialog._account_summary_label.text.is_empty())
	assert_false(dialog._mode_list.visible)
	assert_false(dialog._leaderboard_list.visible)
	assert_true(dialog._leaderboard_group_option.item_count == 0)
	assert_true(dialog._leaderboard_group_option.disabled)
	var mode_row_identity_preserved: bool = (
		dialog._mode_rows_by_id.get("classic") == first_row_value
	)
	assert_true(
		mode_row_identity_preserved,
		"撤下旧数据只隐藏父容器，不能破坏可复用行身份。"
	)

	var stale_completion: GFAsyncCompletion = GFAsyncCompletion.new()
	var _stale_succeeded: bool = stale_completion.succeed(
		{&"active_account_id": "previous-player"}
	)
	dialog._progress_snapshot_generation = 9
	dialog._progress_snapshot_completion = stale_completion
	dialog._on_progress_snapshot_completed(
		stale_completion,
		stale_completion,
		8
	)
	assert_true(
		dialog._progress_snapshot.is_empty(),
		"旧 generation 的迟到账号快照不得恢复已撤下的数据。"
	)

	var loading_cancel_source: GFCancellationSource = GFCancellationSource.new()
	dialog._progress_snapshot_generation = 10
	dialog._progress_snapshot_completion = GFAsyncCompletion.new()
	var _loading_cancelled: bool = loading_cancel_source.cancel(
		&"superseded"
	)
	await dialog._show_progress_loading_after_delay(
		10,
		loading_cancel_source.get_token()
	)
	assert_false(
		dialog._mode_empty_label.visible,
		"被替代请求的延迟协程必须由 cancellation token 立即收束。"
	)
	loading_cancel_source.dispose()
	dialog._progress_snapshot_completion = null
	assert_true(
		is_equal_approx(
			dialog._get_loading_reveal_delay(),
			GameUiMotionProfile.new().loading_indicator_delay
		),
		"异步 Loading 防闪延迟应来自 UI Motion Profile。"
	)
	dialog._set_progress_snapshot_status("旧快照不可用", true, 10)
	dialog._clear_progress_snapshot_status()
	assert_true(
		dialog._status_label.text.is_empty(),
		"新请求开始时必须清除上一代快照拥有的错误状态。"
	)
	dialog._set_status("账号切换成功")
	dialog._clear_progress_snapshot_status(10)
	assert_true(
		dialog._status_label.text == "账号切换成功",
		"快照成功终态不得抹掉账号操作拥有的状态。"
	)
	dialog._set_progress_snapshot_status("正在加载", false, 10)
	dialog._clear_progress_snapshot_status(9)
	assert_true(
		dialog._status_label.text == "正在加载",
		"旧 generation 的终态不得清除当前快照状态。"
	)
	dialog._clear_progress_snapshot_status(10)
	assert_true(dialog._status_label.text.is_empty())
	architecture.dispose()


func test_player_profile_portrait_leaderboard_keeps_header_controls_inside_surface() -> void:
	var architecture: GFArchitecture = await _make_ui_architecture()
	var context: TestArchitectureContext = _make_context(architecture)
	var dialog_node: Node = _PLAYER_PROFILE_SCENE.instantiate()
	assert_true(dialog_node is PlayerProfileDialog)
	if not dialog_node is PlayerProfileDialog:
		dialog_node.free()
		architecture.dispose()
		return
	var dialog: PlayerProfileDialog = dialog_node
	dialog.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dialog.position = Vector2.ZERO
	dialog.size = Vector2(720.0, 960.0)
	context.add_child(dialog)
	await get_tree().process_frame

	# 使用真实稳定身份的长键，确保展示层不会把资源路径/指纹反向撑宽布局。
	dialog._mode_names["classic"] = "MODE_CLASSIC_NAME"
	var long_identity: Dictionary = {
		&"mode_id": "classic",
		&"board_key": "board_template.square.4x4@c9dcaa7fbd0d4a0dbb81d9d5ad1e2a3b",
		&"ruleset_id": "gameplay.classic",
		&"ruleset_version": 1,
		&"ruleset_fingerprint": "f".repeat(64),
	}
	var leaderboard_filter: OptionButton = dialog._leaderboard_group_option
	leaderboard_filter.clear()
	leaderboard_filter.add_item(dialog._make_group_label(long_identity))
	leaderboard_filter.select(0)
	dialog._apply_responsive_layout()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(dialog._header.vertical, "720px 竖屏头部必须改为纵向重排。")
	assert_true(dialog._account_tools.vertical, "720px 竖屏账号管理必须改为纵向重排。")
	assert_false(
		leaderboard_filter.fit_to_longest_item,
		"排行榜分组不得按最长稳定身份文本扩大页面最小宽度。"
	)
	assert_true(
		leaderboard_filter.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"分组筛选在必要时必须以省略号裁切，而非向右溢出。"
	)
	assert_false(
		leaderboard_filter.get_item_text(0).contains("board_template"),
		"排行榜分组不得显示内部棋盘模板 ID。"
	)
	assert_false(
		leaderboard_filter.get_item_text(0).contains("@"),
		"排行榜分组不得显示内容指纹。"
	)
	assert_true(
		leaderboard_filter.get_item_text(0).contains("4×4"),
		"标准棋盘应以玩家可读尺寸显示。"
	)

	var surface_node: Node = dialog.find_child("Surface", true, false)
	assert_true(surface_node is Control)
	if surface_node is Control:
		var surface: Control = surface_node
		_assert_controls_inside_horizontal_bounds(
			surface.get_global_rect(),
			[
				dialog._account_option,
				dialog._back_button,
				dialog._name_input,
				dialog._create_button,
				dialog._rename_button,
				dialog._delete_button,
				leaderboard_filter,
			],
			"720×960 玩家档案"
		)
	architecture.dispose()


func test_player_profile_wide_headers_keep_horizontal_composition() -> void:
	var architecture: GFArchitecture = await _make_ui_architecture()
	var context: TestArchitectureContext = _make_context(architecture)
	var dialog_node: Node = _PLAYER_PROFILE_SCENE.instantiate()
	assert_true(dialog_node is PlayerProfileDialog)
	if not dialog_node is PlayerProfileDialog:
		dialog_node.free()
		architecture.dispose()
		return
	var dialog: PlayerProfileDialog = dialog_node
	dialog.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dialog.position = Vector2.ZERO
	dialog.size = Vector2(960.0, 540.0)
	context.add_child(dialog)
	await get_tree().process_frame
	dialog._apply_responsive_layout()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(dialog._header.vertical, "960×540 应保留桌面横向头部构图。")
	assert_false(dialog._account_tools.vertical, "960×540 应保留横向账号管理构图。")
	var surface_node: Node = dialog.find_child("Surface", true, false)
	assert_true(surface_node is Control)
	if surface_node is Control:
		var surface: Control = surface_node
		_assert_controls_inside_horizontal_bounds(
			surface.get_global_rect(),
			[
				dialog._account_option,
				dialog._back_button,
				dialog._name_input,
				dialog._create_button,
				dialog._rename_button,
				dialog._delete_button,
			],
			"960×540 玩家档案"
		)
	architecture.dispose()


func test_declared_player_controls_meet_touch_target_contract() -> void:
	for scene_path: String in _PLAYER_VISIBLE_SCENE_PATHS:
		var scene_resource: Resource = load(scene_path)
		assert_true(
			scene_resource is PackedScene,
			"玩家场景必须可以加载：%s。" % scene_path
		)
		if not scene_resource is PackedScene:
			continue
		var packed_scene: PackedScene = scene_resource
		var scene_root: Node = packed_scene.instantiate()
		_assert_touch_targets_in_tree(
			scene_root,
			scene_path,
			String(scene_root.name)
		)
		scene_root.free()


func test_responsive_runtime_control_sizes_never_drop_below_touch_contract() -> void:
	assert_gte(
		BaseListMenu._DIALOG_ACTION_MINIMUM_WIDTH,
		112.0,
		"历史列表动态弹窗操作按钮必须保留至少 112px 宽度。"
	)
	assert_gte(
		BaseListMenu._MINIMUM_TOUCH_TARGET_SIZE,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"历史列表动态弹窗操作按钮不得低于 44px 触控高度。"
	)
	assert_gte(
		SettingsMenu._COMPACT_CONTROL_HEIGHT,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"设置页紧凑布局控件高度不得低于 44px。"
	)
	assert_gte(
		SettingsMenu._DESKTOP_CONTROL_HEIGHT,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"设置页桌面布局也必须遵守 44px 触控契约。"
	)
	assert_gte(
		SettingsMenu._COMPACT_BINDING_ROW_HEIGHT,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"设置页紧凑按键映射行不得低于 44px。"
	)
	assert_gte(
		SettingsMenu._DESKTOP_BINDING_ROW_HEIGHT,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"设置页桌面按键映射行也不得低于 44px。"
	)
	assert_gte(
		BoardWorldViewportController._FIT_BUTTON_DESKTOP_MINIMUM.y,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"棋盘桌面视图适配按钮不得回退到 34px。"
	)
	assert_gte(
		BoardWorldViewportController._FIT_BUTTON_COMPACT_MINIMUM.y,
		_MINIMUM_TOUCH_TARGET_SIZE,
		"棋盘紧凑视图适配按钮不得低于 44px。"
	)


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


func _assert_touch_targets_in_tree(
	node: Node,
	scene_path: String,
	node_path: String
) -> void:
	if _is_direct_touch_control(node):
		var control: Control = node
		assert_gte(
			control.custom_minimum_size.y,
			_MINIMUM_TOUCH_TARGET_SIZE,
			"%s 中的 %s 必须保留至少 44px 的触控高度。"
			% [scene_path, node_path]
		)
	for child: Node in node.get_children():
		_assert_touch_targets_in_tree(
			child,
			scene_path,
			"%s/%s" % [node_path, child.name]
		)


func _assert_controls_inside_horizontal_bounds(
	bounds: Rect2,
	controls: Array[Control],
	page_label: String
) -> void:
	for control: Control in controls:
		assert_true(control.visible, "%s 中的 %s 必须可见。" % [page_label, control.name])
		assert_gte(
			control.size.y,
			_MINIMUM_TOUCH_TARGET_SIZE,
			"%s 中的 %s 必须保留至少 44px 的实际触控高度。"
			% [page_label, control.name]
		)
		var rect: Rect2 = control.get_global_rect()
		assert_gte(
			rect.position.x + 0.5,
			bounds.position.x,
			"%s 中的 %s 不得越过左侧安全边界。" % [page_label, control.name]
		)
		assert_lte(
			rect.end.x,
			bounds.end.x + 0.5,
			"%s 中的 %s 不得越过右侧安全边界。" % [page_label, control.name]
		)


func _is_direct_touch_control(node: Node) -> bool:
	return (
		node is BaseButton
		or node is LineEdit
		or node is TextEdit
		or node is ItemList
		or node is Tree
		or node is Slider
		or node is SpinBox
		or node is TabBar
	)


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
		}, {
			&"recipe_id": _CONFLICT_RECIPE_ID,
			&"display_name_key": &"TILE_RECIPE_FIBONACCI_MERGE",
			&"selected": false,
			&"compatible": false,
			&"conflict": {
				&"owner_recipe_id": _RECIPE_ID,
				&"conflicting_recipe_id": _CONFLICT_RECIPE_ID,
			},
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
