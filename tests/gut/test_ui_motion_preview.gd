## 验证隔离 UI Motion Profile 预览器的开发期契约。
extends GutTest


# --- 常量 ---

const _PREVIEW_SCENE_PATH: String = (
	"res://features/themes/tools/ui_motion_preview.tscn"
)
const _PREVIEW_SCENE: PackedScene = preload(
	"res://features/themes/tools/ui_motion_preview.tscn"
)
const _PROFILE_PATH: String = (
	"res://features/themes/resources/themes/game/"
	+ "halftone_atlas_ui_motion_profile.tres"
)
const _UI_ROUTE_REGISTRY_PATH: String = (
	"res://features/navigation/resources/registries/ui_route_registry.tres"
)
const _MINIMUM_TOUCH_TARGET: float = 44.0


# --- 测试用例 ---

func test_preview_instantiates_with_real_valid_motion_profile() -> void:
	var preview: UiMotionPreview = await _instantiate_preview()
	assert_not_null(preview)
	if preview == null:
		return

	var profile: GameUiMotionProfile = preview.get_motion_profile()
	assert_not_null(profile, "开发预览器必须加载主题默认 Motion Profile。")
	assert_true(profile.resource_path == _PROFILE_PATH)
	assert_true(
		profile.get_validation_report().is_ok(),
		"预览使用的默认 Motion Profile 必须保持有效。"
	)
	var motion: GameUiMotionUtility = preview.get_motion_utility()
	assert_not_null(motion, "预览器应只复用真实 GameUiMotionUtility。")
	assert_false(
		motion.is_ready_in_architecture(),
		"隔离作者预览不得伪装成玩家运行时 GFArchitecture 模块。"
	)
	assert_true(
		motion.get_profile() == profile,
		"预览 Utility 必须直接使用主题资源，不能复制一套参数。"
	)
	assert_true(
		preview.get_current_preset_id()
		== GameUiMotionProfile.PRESET_PANEL_ENTER
	)
	assert_gt(preview.get_current_duration_seconds(), 0.0)
	var status_node: Node = preview.get_node("%CurrentPresetLabel")
	assert_true(status_node is Label)
	if not status_node is Label:
		return
	var status: Label = status_node
	assert_true(status.text.contains("ui.panel.enter"))
	assert_true(status.text.contains("ms"))


func test_preview_buttons_respect_touch_target_contract() -> void:
	var preview: UiMotionPreview = await _instantiate_preview()
	assert_not_null(preview)
	if preview == null:
		return

	var buttons: Array[BaseButton] = []
	_collect_buttons(preview, buttons)
	assert_true(buttons.size() == 6, "预览器应暴露六个清晰可操作控件。")
	for button: BaseButton in buttons:
		assert_gte(
			button.custom_minimum_size.y,
			_MINIMUM_TOUCH_TARGET,
			"%s 的触控高度必须至少为 44px。" % button.name
		)


func test_reduced_motion_preview_commits_static_terminal_state() -> void:
	var preview: UiMotionPreview = await _instantiate_preview()
	assert_not_null(preview)
	if preview == null:
		return

	preview.preview_reduced_motion_static()
	assert_true(preview.is_reduced_motion_preview_enabled())
	for target: Control in preview.get_static_preview_targets():
		assert_true(
			target.scale.is_equal_approx(Vector2.ONE),
			"%s 应直接落到基础缩放。" % target.name
		)
		assert_true(
			is_equal_approx(target.modulate.a, 1.0),
			"%s 应直接落到完全可见终态。" % target.name
		)

	var delta_label_node: Node = preview.get_node("%DeltaLabel")
	assert_true(delta_label_node is Label)
	if not delta_label_node is Label:
		return
	var delta_label: Label = delta_label_node
	assert_false(delta_label.visible, "Reduced Motion 不应留下数值飘字。")
	var number_label_node: Node = preview.get_node("%NumberLabel")
	assert_true(number_label_node is Label)
	if not number_label_node is Label:
		return
	var number_label: Label = number_label_node
	assert_true(number_label.text.is_valid_int())
	var presenter: GameButtonMotionPresenter = (
		preview.get_sample_button_presenter()
	)
	assert_not_null(presenter, "按钮预览必须复用现有 Presenter。")
	if presenter != null:
		var face_node: Node = presenter.get_node_or_null(
			GameButtonMotionPresenter.FACE_NODE_NAME
		)
		assert_true(face_node is Panel)
		if not face_node is Panel:
			return
		var face: Panel = face_node
		assert_not_null(face)
		assert_true(is_zero_approx(face.rotation))
		assert_true(face.modulate.is_equal_approx(Color.WHITE))


func test_preview_is_not_registered_as_runtime_route_or_boot_scene() -> void:
	var route_registry_source: String = _read_text(_UI_ROUTE_REGISTRY_PATH)
	var project_source: String = _read_text("res://project.godot")
	assert_false(
		route_registry_source.contains(_PREVIEW_SCENE_PATH),
		"开发预览器不得进入玩家 UI Route Registry。"
	)
	assert_false(
		project_source.contains('run/main_scene="%s"' % _PREVIEW_SCENE_PATH),
		"开发预览器不得成为项目启动场景。"
	)


# --- 私有/辅助方法 ---

func _instantiate_preview() -> UiMotionPreview:
	var node: Node = _PREVIEW_SCENE.instantiate()
	assert_true(node is UiMotionPreview)
	if not node is UiMotionPreview:
		node.free()
		return null
	var preview: UiMotionPreview = node
	add_child_autoqfree(preview)
	await get_tree().process_frame
	await get_tree().process_frame
	return preview


func _collect_buttons(root: Node, output: Array[BaseButton]) -> void:
	for child: Node in root.get_children():
		if child is BaseButton:
			output.append(child)
		_collect_buttons(child, output)


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
