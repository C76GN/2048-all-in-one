## ReplayTimeline: 回放运输控件中的有界、可操作过程时间带。
##
## 组件只投影 ReplaySystem 已有的步数与 ReplayMarker；选择结果通过信号交回
## GamePlayController，绝不持有或重建玩法状态。标记过密时按视觉桶折叠，
## 精确标记文本仍由相邻的 ReplayMarkerPicker 提供。
class_name ReplayTimeline
extends HSlider


# --- 信号 ---

## 玩家确认希望跳转到的 0-based 回放步骤。
signal step_requested(step_index: int)


# --- 常量 ---

const MAX_VISIBLE_NOTCHES: int = 96
const _TRACK_HORIZONTAL_INSET: float = 10.0
const _MARKER_BASE_HEIGHT: float = 7.0
const _FAILURE_COLOR: Color = Color(0.827451, 0.384314, 0.294118, 1.0)


# --- 私有变量 ---

var _authoritative_step: int = 0
var _total_steps: int = 0
var _markers: Array[ReplayMarker] = []
var _visible_notches: Array[Dictionary] = []
var _dragging: bool = false
var _interaction_enabled: bool = false
var _label_fallback: String = "过程时间带"
var _hint_fallback: String = "拖动跳转；方向键选择步骤后按确认。"
var _track_color: Color = Color(0.937255, 0.819608, 0.364706, 0.56)
var _merge_color: Color = Color(0.294118, 0.741176, 0.772549, 1.0)
var _chain_color: Color = Color(0.937255, 0.819608, 0.364706, 1.0)
var _milestone_color: Color = Color(0.87451, 0.294118, 0.603922, 1.0)


# --- Godot 生命周期方法 ---

func _ready() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 1.0
	allow_greater = false
	allow_lesser = false
	tick_count = 0
	ticks_on_borders = false
	custom_minimum_size.y = maxf(custom_minimum_size.y, 44.0)
	focus_mode = Control.FOCUS_ALL
	editable = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	var _started_connection: int = drag_started.connect(_on_drag_started)
	var _ended_connection: int = drag_ended.connect(_on_drag_ended)
	var _value_connection: int = value_changed.connect(_on_value_changed)
	_update_tooltip()


func _gui_input(event: InputEvent) -> void:
	if not _interaction_enabled or event == null:
		return
	if event.is_action_pressed(&"ui_accept"):
		var _requested: bool = request_selected_step()
		accept_event()
	elif (
		event.is_action_pressed(&"ui_left")
		or event.is_action_pressed(&"ui_right")
	):
		var direction: float = (
			-1.0
			if event.is_action_pressed(&"ui_left")
			else 1.0
		)
		value = clampf(value + direction * step, min_value, max_value)
		# 候选值停留在 HSlider；终止事件，避免继续进入全局 transport。
		accept_event()


func _draw() -> void:
	if _total_steps <= 0 or size.x <= _TRACK_HORIZONTAL_INSET * 2.0:
		return
	var track_start: float = _TRACK_HORIZONTAL_INSET
	var track_width: float = size.x - _TRACK_HORIZONTAL_INSET * 2.0
	var marker_baseline: float = maxf(size.y * 0.31, 12.0)
	draw_line(
		Vector2(track_start, marker_baseline),
		Vector2(track_start + track_width, marker_baseline),
		_track_color,
		1.0,
		true
	)
	for notch: Dictionary in _visible_notches:
		var bucket_count: int = GFVariantData.get_option_int(
			notch,
			&"bucket_count",
			1
		)
		var bucket_index: int = GFVariantData.get_option_int(
			notch,
			&"bucket_index",
			0
		)
		var fraction: float = (
			float(bucket_index) / float(bucket_count - 1)
			if bucket_count > 1
			else 0.0
		)
		var marker_kind: int = GFVariantData.get_option_int(
			notch,
			&"kind",
			ReplayMarker.Kind.MERGE
		)
		var marker_height: float = _MARKER_BASE_HEIGHT + _marker_priority(marker_kind)
		var x: float = track_start + track_width * fraction
		draw_line(
			Vector2(x, marker_baseline - marker_height),
			Vector2(x, marker_baseline + 2.0),
			_marker_color(marker_kind),
			2.0,
			true
		)


# --- 公共方法 ---

## 更新完整时间域和标记投影；标记绘制始终保持固定上界。
## @param total_step_count: ReplaySystem 提供的总步骤数。
## @param markers: ReplaySystem 提供的强类型语义标记目录。
func configure(total_step_count: int, markers: Array[ReplayMarker]) -> void:
	_total_steps = clampi(total_step_count, 0, ReplayData.MAX_STEP_COUNT)
	_markers.clear()
	for marker: ReplayMarker in markers:
		if not is_instance_valid(marker):
			continue
		if marker.step_index < 0 or marker.step_index > _total_steps:
			continue
		_markers.append(marker)
	min_value = 0.0
	max_value = maxf(float(_total_steps), 1.0)
	_rebuild_visible_notches()
	set_progress(_authoritative_step)


## 同步 ReplaySystem 的权威位置，不触发跳转请求。
## @param current_step: ReplaySystem 当前的 0-based 权威步骤。
func set_progress(current_step: int) -> void:
	_authoritative_step = clampi(current_step, 0, _total_steps)
	if not _dragging:
		value = float(_authoritative_step)
	_update_tooltip()
	queue_redraw()


## 跳转期间或 OOS 后禁用编辑，但保留可读的当前步骤与标记结构。
## @param enabled: 为 true 时允许提交合法步骤选择。
func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled and _total_steps > 0
	editable = _interaction_enabled
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if _interaction_enabled
		else Control.CURSOR_ARROW
	)
	_update_tooltip()


## 返回当前是否允许玩家提交步骤选择。
func is_interaction_enabled() -> bool:
	return _interaction_enabled


## 更新本地化语义；缺少 key 时由 Controller 提供稳定回退文本。
## @param label_text: 控件的可读语义名称。
## @param hint_text: 键盘、手柄与触摸操作提示。
func set_context_text(label_text: String, hint_text: String) -> void:
	if not label_text.is_empty():
		_label_fallback = label_text
	if not hint_text.is_empty():
		_hint_fallback = hint_text
	_update_tooltip()


## 应用当前项目 UI 色板；时间带仍使用形状高度区分标记，不依赖颜色 alone。
## @param palette: 当前 GameTheme 持有的 UI 色板。
func apply_palette(palette: GameUiPalette) -> void:
	if not is_instance_valid(palette):
		return
	_track_color = palette.slider_track_color
	_merge_color = palette.slider_grabber_color
	_chain_color = palette.button_pressed_color
	_milestone_color = palette.slider_grabber_highlight_color
	queue_redraw()


## 供键盘确认、拖动结束和测试使用；实际跳转仍由 ReplaySystem 验证。
func request_selected_step() -> bool:
	if not _interaction_enabled:
		return false
	var selected_step: int = clampi(roundi(value), 0, _total_steps)
	if selected_step == _authoritative_step:
		return false
	step_requested.emit(selected_step)
	return true


## 返回有界视觉投影的副本，供合同测试和诊断读取。
func get_visible_notches() -> Array[Dictionary]:
	return _visible_notches.duplicate(true)


# --- 私有/辅助方法 ---

func _rebuild_visible_notches() -> void:
	_visible_notches.clear()
	if _total_steps <= 0 or _markers.is_empty():
		queue_redraw()
		return
	var bucket_count: int = mini(MAX_VISIBLE_NOTCHES, _total_steps + 1)
	var notch_by_bucket: Dictionary = {}
	for marker: ReplayMarker in _markers:
		var bucket_index: int = (
			roundi(
				float(marker.step_index)
				/ float(_total_steps)
				* float(bucket_count - 1)
			)
			if bucket_count > 1
			else 0
		)
		var existing_value: Variant = notch_by_bucket.get(bucket_index)
		var collapsed_count: int = 1
		var selected_kind: int = marker.kind
		var selected_step: int = marker.step_index
		if existing_value is Dictionary:
			var existing: Dictionary = existing_value
			collapsed_count = GFVariantData.get_option_int(
				existing,
				&"collapsed_count",
				1
			) + 1
			var existing_kind: int = GFVariantData.get_option_int(
				existing,
				&"kind",
				ReplayMarker.Kind.MERGE
			)
			if _marker_priority(existing_kind) >= _marker_priority(marker.kind):
				selected_kind = existing_kind
				selected_step = GFVariantData.get_option_int(
					existing,
					&"step_index",
					marker.step_index
				)
		notch_by_bucket[bucket_index] = {
			&"bucket_index": bucket_index,
			&"bucket_count": bucket_count,
			&"step_index": selected_step,
			&"kind": selected_kind,
			&"collapsed_count": collapsed_count,
		}
	var bucket_indices: Array = notch_by_bucket.keys()
	bucket_indices.sort()
	for bucket_index_value: Variant in bucket_indices:
		if bucket_index_value is int:
			_visible_notches.append(notch_by_bucket[bucket_index_value])
	queue_redraw()


func _marker_priority(marker_kind: int) -> int:
	match marker_kind:
		ReplayMarker.Kind.OOS:
			return 5
		ReplayMarker.Kind.MILESTONE:
			return 4
		ReplayMarker.Kind.FAILURE:
			return 3
		ReplayMarker.Kind.CHAIN_OR_TRANSFORM:
			return 2
		_:
			return 1


func _marker_color(marker_kind: int) -> Color:
	match marker_kind:
		ReplayMarker.Kind.OOS, ReplayMarker.Kind.FAILURE:
			return _FAILURE_COLOR
		ReplayMarker.Kind.MILESTONE:
			return _milestone_color
		ReplayMarker.Kind.CHAIN_OR_TRANSFORM:
			return _chain_color
		_:
			return _merge_color


func _update_tooltip() -> void:
	var selected_step: int = clampi(roundi(value), 0, _total_steps)
	tooltip_text = "%s · %d / %d\n%s" % [
		_label_fallback,
		selected_step,
		_total_steps,
		_hint_fallback,
	]


func _on_drag_started() -> void:
	_dragging = true


func _on_drag_ended(value_changed_by_drag: bool) -> void:
	_dragging = false
	if value_changed_by_drag:
		var _requested: bool = request_selected_step()
	else:
		set_progress(_authoritative_step)


func _on_value_changed(_new_value: float) -> void:
	_update_tooltip()
	queue_redraw()
