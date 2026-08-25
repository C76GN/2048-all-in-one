## GameSpatialCanvasInputPolicy: 项目棋盘画布共享的 GF 输入策略构造入口。
##
## GFSpatialCanvas2D 继续拥有通用手势状态机；本项目 Module 只冻结玩法棋盘与
## 棋盘编辑器共同采用的中键、滚轮和多指导航产品策略。
class_name GameSpatialCanvasInputPolicy
extends RefCounted


## 创建棋盘类画布共用的导航策略。
## @param wheel_zoom_factor: 每个滚轮刻度采用的缩放倍率。
static func create_navigation_policy(
	wheel_zoom_factor: float
) -> GFSpatialCanvasInputPolicy:
	var policy: GFSpatialCanvasInputPolicy = GFSpatialCanvasInputPolicy.new()
	policy.pan_mouse_button = MOUSE_BUTTON_MIDDLE
	policy.pan_action = &""
	policy.pan_modifier_mask = GFSpatialCanvasInputPolicy.ModifierMask.NONE
	policy.selection_mouse_button = MOUSE_BUTTON_NONE
	policy.selection_action = &""
	policy.selection_modifier_bindings.clear()
	policy.wheel_axis = GFSpatialCanvasInputPolicy.WheelAxis.VERTICAL
	policy.wheel_routing = GFSpatialCanvasInputPolicy.WheelRouting.CANVAS
	policy.wheel_modifier_mask = GFSpatialCanvasInputPolicy.ModifierMask.NONE
	policy.wheel_zoom_factor = maxf(wheel_zoom_factor, 0.0001)
	policy.touch_enabled = true
	policy.touch_primary_behavior = GFSpatialCanvasInputPolicy.TouchPrimaryBehavior.NONE
	policy.touch_multi_pan_enabled = true
	policy.touch_multi_zoom_enabled = true
	policy.system_pan_gesture_enabled = true
	policy.system_magnify_gesture_enabled = true
	policy.placement_cancel_action = &""
	policy.consume_handled_events = true
	policy.consume_wheel_events = true
	return policy
