## UiMotionPreview: 可单独运行的主题 UI Motion Profile 开发预览器。
##
## 本场景只在开发期实例化项目已有的 GameUiMotionUtility，不注册 GF 架构模块、
## 不进入玩家 UI 路由，也不持有第二套动效实现。
class_name UiMotionPreview
extends Control


# --- 枚举 ---

enum PreviewPreset {
	PANEL,
	CONTENT,
	LIST,
	NUMBER,
	BUTTON,
}


# --- 常量 ---

const DEFAULT_PROFILE: GameUiMotionProfile = preload(
	"res://features/themes/resources/themes/game/halftone_atlas_ui_motion_profile.tres"
)
const DEFAULT_PALETTE: GameUiPalette = preload(
	"res://features/themes/resources/themes/game/halftone_atlas_ui_palette.tres"
)
const _PRESET_IDS: Array[StringName] = [
	GameUiMotionProfile.PRESET_PANEL_ENTER,
	GameUiMotionProfile.PRESET_CONTENT_SWITCH,
	GameUiMotionProfile.PRESET_CONTROL_REVEAL,
	GameUiMotionProfile.PRESET_NUMERIC_CHANGE,
	GameUiMotionProfile.PRESET_BUTTON_DEAL,
]
const _PRESET_LABELS: PackedStringArray = [
	"Panel · 入场",
	"Content · 切换",
	"List · 出现",
	"Number · 变化",
	"Button · 发牌",
]
const _TOUCH_TARGET_MINIMUM: float = 44.0


# --- 私有变量 ---

var _motion_utility: _PreviewMotionRuntime = null
var _style_utility: GameUiStyleUtility = null
var _accessibility_utility: _PreviewAccessibilityRuntime = null
var _motion_profile: GameUiMotionProfile = DEFAULT_PROFILE
var _content_variant: int = 0
var _number_value: int = 128
var _sequence_generation: int = 0


# --- @onready 变量 (节点引用) ---

@onready var _preset_picker: OptionButton = %PresetPicker
@onready var _play_button: Button = %PlayButton
@onready var _replay_all_button: Button = %ReplayAllButton
@onready var _reverse_button: Button = %ReverseButton
@onready var _reduced_motion_button: Button = %ReducedMotionButton
@onready var _current_preset_label: Label = %CurrentPresetLabel
@onready var _activity_label: Label = %ActivityLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _preview_surface: PanelContainer = %PreviewSurface
@onready var _content_card: PanelContainer = %ContentCard
@onready var _content_title: Label = %ContentTitle
@onready var _list_rows: VBoxContainer = %ListRows
@onready var _number_label: Label = %NumberLabel
@onready var _delta_label: Label = %DeltaLabel
@onready var _sample_button: Button = %SampleButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_configure_motion_runtime()
	_populate_preset_picker()
	_connect_controls()
	_bind_button_presenters()
	_update_selected_preset_status()
	_play_button.grab_focus()
	call_deferred(&"replay_all")


func _exit_tree() -> void:
	_sequence_generation += 1
	_settle_preview()
	if is_instance_valid(_motion_utility):
		_motion_utility.dispose()
	if is_instance_valid(_style_utility):
		_style_utility.dispose()
	if is_instance_valid(_accessibility_utility):
		_accessibility_utility.dispose()
	_motion_utility = null
	_style_utility = null
	_accessibility_utility = null


# --- 公共方法 ---

## 返回预览器正在使用的真实主题 Motion Profile。
func get_motion_profile() -> GameUiMotionProfile:
	return _motion_profile


## 返回本预览场景唯一的 Motion owner，供开发检查和契约测试使用。
func get_motion_utility() -> GameUiMotionUtility:
	return _motion_utility


## 返回当前下拉选中的语义预设。
func get_current_preset_id() -> StringName:
	var selected_index: int = clampi(
		_preset_picker.selected,
		0,
		_PRESET_IDS.size() - 1
	)
	return _PRESET_IDS[selected_index]


## 返回当前选中语义的主时长。
func get_current_duration_seconds() -> float:
	return _motion_profile.get_duration(get_current_preset_id())


## 选择指定预览语义，不自动播放。
## @param preset: 要在作者预览器中选中的代表性语义。
func select_preview_preset(preset: PreviewPreset) -> void:
	var selected_index: int = clampi(int(preset), 0, _PRESET_IDS.size() - 1)
	_preset_picker.select(selected_index)
	_update_selected_preset_status()


## 播放当前下拉选中的代表性语义。
func play_selected_preview() -> void:
	_sequence_generation += 1
	_settle_preview()
	_update_selected_preset_status()
	_activity_label.text = "正在预览单个语义"
	_play_preset(_preset_picker.selected)


## 同时重播 Panel、Content、List、Number 与 Button 的代表性语义。
func replay_all() -> void:
	_sequence_generation += 1
	_settle_preview()
	_swap_content()
	var old_value: int = _number_value
	_number_value = _next_number_value(_number_value)
	var _panel_tween: Tween = _motion_utility.play_panel_intro(
		_preview_surface
	)
	var _content_tween: Tween = _motion_utility.play_content_switch(
		_content_card,
		_content_direction()
	)
	var _revealed_count: int = _motion_utility.play_children_reveal(
		_list_rows,
		Vector2.ZERO,
		-1.0,
		0.06
	)
	var _number_tween: Tween = _motion_utility.play_numeric_change(
		_number_label,
		old_value,
		_number_value,
		_delta_label
	)
	var _dealt_count: int = _motion_utility.play_button_deal_sequence(
		[_sample_button]
	)
	_update_selected_preset_status()
	_activity_label.text = (
		"完整序列 · 5 类语义"
		if not is_reduced_motion_preview_enabled()
		else "Reduced Motion · 全部直接终态"
	)


## 快速打断 Content 切换并反向，随后主动 complete_now 收束到最终状态。
func play_quick_reverse_and_settle() -> void:
	_set_reduced_motion_preview(false)
	select_preview_preset(PreviewPreset.CONTENT)
	_sequence_generation += 1
	var generation: int = _sequence_generation
	_settle_preview()
	_swap_content()
	var first_tween: Tween = _motion_utility.play_content_switch(
		_content_card,
		_content_direction()
	)
	_activity_label.text = "快速反向 · 第一次切换"
	await get_tree().create_timer(
		_motion_profile.content_switch_duration * 0.28
	).timeout
	if generation != _sequence_generation or not is_instance_valid(first_tween):
		return
	_swap_content()
	var second_tween: Tween = _motion_utility.play_content_switch(
		_content_card,
		_content_direction()
	)
	_activity_label.text = "快速反向 · 从当前画面重定向"
	await get_tree().create_timer(
		_motion_profile.content_switch_duration * 0.36
	).timeout
	if generation != _sequence_generation or not is_instance_valid(second_tween):
		return
	_motion_utility.complete_control_motion(_content_card)
	_activity_label.text = "快速反向 · 已收束到终态"


## 立即切到 Reduced Motion，并让所有代表控件落到静态终态。
func preview_reduced_motion_static() -> void:
	_set_reduced_motion_preview(true)
	replay_all()


## 设置预览器的 Reduced Motion 状态；此状态只存在于隔离预览器中。
## @param enabled: true 时用静态终态预览减少动态模式。
func set_reduced_motion_preview(enabled: bool) -> void:
	_set_reduced_motion_preview(enabled)


func is_reduced_motion_preview_enabled() -> bool:
	if not is_instance_valid(_accessibility_utility):
		return false
	return _accessibility_utility.get_state().reduced_motion


## 立即提交所有预览控件的最终画面，模拟高频输入时的主动收束。
func settle_preview_now() -> void:
	_sequence_generation += 1
	_settle_preview()
	_activity_label.text = "所有动效已主动收束"


## 返回用于验证 Reduced Motion 静态终态的代表控件。
func get_static_preview_targets() -> Array[Control]:
	var targets: Array[Control] = [
		_preview_surface,
		_content_card,
		_number_label,
	]
	for child: Node in _list_rows.get_children():
		if child is Control:
			targets.append(child)
	return targets


func get_sample_button_presenter() -> GameButtonMotionPresenter:
	if not is_instance_valid(_style_utility):
		return null
	return _style_utility.get_button_motion_presenter(_sample_button)


# --- 私有/辅助方法 ---

func _configure_motion_runtime() -> void:
	_motion_utility = _PreviewMotionRuntime.new()
	_style_utility = GameUiStyleUtility.new()
	_accessibility_utility = _PreviewAccessibilityRuntime.new()
	_style_utility.apply_palette(DEFAULT_PALETTE)
	if not _motion_utility.configure_detached_preview(
		_style_utility,
		_accessibility_utility
	):
		push_error("[UiMotionPreview] 无法配置隔离的作者预览依赖。")
	if not _motion_utility.apply_profile(_motion_profile):
		push_error("[UiMotionPreview] 默认 GameUiMotionProfile 无效。")


func _populate_preset_picker() -> void:
	_preset_picker.clear()
	for index: int in range(_PRESET_LABELS.size()):
		_preset_picker.add_item(_PRESET_LABELS[index], index)
		_preset_picker.set_item_metadata(index, _PRESET_IDS[index])
	_preset_picker.select(PreviewPreset.PANEL)


func _connect_controls() -> void:
	var _preset_connection: int = _preset_picker.item_selected.connect(
		_on_preset_selected
	)
	var _play_connection: int = _play_button.pressed.connect(
		play_selected_preview
	)
	var _replay_connection: int = _replay_all_button.pressed.connect(replay_all)
	var _reverse_connection: int = _reverse_button.pressed.connect(
		play_quick_reverse_and_settle
	)
	var _reduced_connection: int = _reduced_motion_button.toggled.connect(
		_on_reduced_motion_toggled
	)
	var _sample_connection: int = _sample_button.pressed.connect(
		_on_sample_button_pressed
	)


func _bind_button_presenters() -> void:
	for button: BaseButton in _get_preview_buttons():
		button.custom_minimum_size.y = maxf(
			button.custom_minimum_size.y,
			_TOUCH_TARGET_MINIMUM
		)
		var role: GameUiStyleUtility.ButtonRole = (
			GameUiStyleUtility.ButtonRole.PRIMARY
			if button in [_play_button, _sample_button]
			else GameUiStyleUtility.ButtonRole.SECONDARY
		)
		_style_utility.style_button(button, role)
		var _bound: bool = _motion_utility.bind_button(button)


func _get_preview_buttons() -> Array[BaseButton]:
	return [
		_preset_picker,
		_play_button,
		_replay_all_button,
		_reverse_button,
		_reduced_motion_button,
		_sample_button,
	]


func _play_preset(index: int) -> void:
	match clampi(index, 0, _PRESET_IDS.size() - 1):
		PreviewPreset.PANEL:
			var _panel_tween: Tween = _motion_utility.play_panel_intro(
				_preview_surface
			)
		PreviewPreset.CONTENT:
			_swap_content()
			var _content_tween: Tween = _motion_utility.play_content_switch(
				_content_card,
				_content_direction()
			)
		PreviewPreset.LIST:
			var _count: int = _motion_utility.play_children_reveal(
				_list_rows
			)
		PreviewPreset.NUMBER:
			var old_value: int = _number_value
			_number_value = _next_number_value(_number_value)
			var _tween: Tween = _motion_utility.play_numeric_change(
				_number_label,
				old_value,
				_number_value,
				_delta_label
			)
		PreviewPreset.BUTTON:
			var _count: int = _motion_utility.play_button_deal_sequence(
				[_sample_button]
			)


func _set_reduced_motion_preview(enabled: bool) -> void:
	if not is_instance_valid(_accessibility_utility):
		return
	_settle_preview()
	_accessibility_utility.set_preview_reduced_motion(enabled)
	_reduced_motion_button.set_pressed_no_signal(enabled)
	_reduced_motion_button.text = (
		"减少动态：开" if enabled else "减少动态：关"
	)
	_update_mode_status()


func _settle_preview() -> void:
	if not is_instance_valid(_motion_utility):
		return
	_motion_utility.complete_control_motion(_preview_surface)
	_motion_utility.complete_control_motion(_content_card)
	_motion_utility.complete_children_motion(_list_rows)
	_motion_utility.complete_numeric_motion(_number_label)
	_motion_utility.complete_button_motion(_sample_button)
	_delta_label.visible = false


func _swap_content() -> void:
	_content_variant = 1 - _content_variant
	if _content_variant == 0:
		_content_title.text = "稳定身份 · 局部更新"
	else:
		_content_title.text = "可中断 · 从当前画面重定向"


func _content_direction() -> float:
	return -1.0 if _content_variant == 0 else 1.0


func _next_number_value(value: int) -> int:
	return 128 if value >= 2048 else value * 2


func _update_selected_preset_status() -> void:
	var preset_id: StringName = get_current_preset_id()
	var duration_msec: int = roundi(
		_motion_profile.get_duration(preset_id) * 1000.0
	)
	_current_preset_label.text = "%s · %d ms" % [
		GFVariantData.to_text(preset_id),
		duration_msec,
	]
	_update_mode_status()


func _update_mode_status() -> void:
	_mode_label.text = (
		"REDUCED · STATIC"
		if is_reduced_motion_preview_enabled()
		else "LIVE · INTERRUPTIBLE"
	)


# --- 信号处理函数 ---

func _on_preset_selected(_index: int) -> void:
	_update_selected_preset_status()
	_activity_label.text = "已选择语义，等待播放"


func _on_reduced_motion_toggled(enabled: bool) -> void:
	_set_reduced_motion_preview(enabled)
	replay_all()


func _on_sample_button_pressed() -> void:
	select_preview_preset(PreviewPreset.BUTTON)
	_activity_label.text = "按钮确认 · Presenter 局部响应"


# --- 内部类 ---

## 仅供隔离作者场景使用的显式 seam；玩家运行时仍由 GFArchitecture 注入依赖。
class _PreviewMotionRuntime extends GameUiMotionUtility:
	## 注入作者预览场景的隔离依赖；架构内实例会拒绝此入口。
	## @param style: 只服务预览控件的项目样式 Utility。
	## @param accessibility: 只维护预览 Reduced Motion 状态的无障碍 Utility。
	## @return: 仅在两个依赖有效且尚未进入 GF 生命周期时返回 true。
	func configure_detached_preview(
		style: GameUiStyleUtility,
		accessibility: GameAccessibilityUtility
	) -> bool:
		if (
			not is_instance_valid(style)
			or not is_instance_valid(accessibility)
			or is_ready_in_architecture()
		):
			return false
		_style = style
		_accessibility = accessibility
		return true


## 隔离预览没有 GFSettingsUtility；此 seam 只维护临时无障碍状态，不写玩家设置。
class _PreviewAccessibilityRuntime extends GameAccessibilityUtility:
	## 更新隔离预览器的减少动态状态。
	## @param enabled: true 时启用 Reduced Motion 静态终态。
	func set_preview_reduced_motion(enabled: bool) -> void:
		var next_state: GameAccessibilityState = get_state()
		next_state.reduced_motion = enabled
		_state = next_state
		state_changed.emit(get_state())
