## CanvasViewportMath: 跨 Feature 复用的二维画布视口变换算法。
##
## 该类型只计算适配比例、缩放锚点与平移边界，不持有节点、输入或业务状态。
class_name CanvasViewportMath
extends RefCounted


# --- 公共方法 ---

## 计算完整内容适配视口时的缩放比例。
## @param viewport_size: 视口逻辑尺寸。
## @param content_rect: 画布局部世界包围盒。
## @param margin: 四周屏幕空间留白。
## @param max_zoom: 允许的最大适配比例。
static func calculate_fit_zoom(
	viewport_size: Vector2,
	content_rect: Rect2,
	margin: float,
	max_zoom: float
) -> float:
	if (
		viewport_size.x <= 0.0
		or viewport_size.y <= 0.0
		or content_rect.size.x <= 0.0
		or content_rect.size.y <= 0.0
	):
		return 1.0
	var safe_margin: float = maxf(margin, 0.0)
	var available_size: Vector2 = Vector2(
		maxf(viewport_size.x - safe_margin * 2.0, 1.0),
		maxf(viewport_size.y - safe_margin * 2.0, 1.0)
	)
	return minf(
		minf(
			available_size.x / content_rect.size.x,
			available_size.y / content_rect.size.y
		),
		maxf(max_zoom, 0.0001)
	)


## 计算让内容中心与视口中心重合时的世界根节点位置。
## @param viewport_size: 视口逻辑尺寸。
## @param content_rect: 画布局部世界包围盒。
## @param zoom: 目标缩放比例。
static func calculate_centered_world_position(
	viewport_size: Vector2,
	content_rect: Rect2,
	zoom: float
) -> Vector2:
	return viewport_size * 0.5 - content_rect.get_center() * zoom


## 计算围绕屏幕锚点缩放后保持锚点下世界位置不变的根节点位置。
## @param current_position: 当前世界根节点位置。
## @param anchor: 视口局部缩放锚点。
## @param current_zoom: 当前缩放比例。
## @param next_zoom: 目标缩放比例。
static func calculate_zoomed_world_position(
	current_position: Vector2,
	anchor: Vector2,
	current_zoom: float,
	next_zoom: float
) -> Vector2:
	var safe_current_zoom: float = maxf(current_zoom, 0.0001)
	var world_anchor: Vector2 = (anchor - current_position) / safe_current_zoom
	return anchor - world_anchor * next_zoom


## 把世界根节点位置限制到内容不会完全离开视口的范围。
## @param viewport_size: 视口逻辑尺寸。
## @param content_rect: 画布局部世界包围盒。
## @param zoom: 当前缩放比例。
## @param desired_position: 未约束的目标世界位置。
## @param edge_margin: 大内容在视口边缘至少保留的屏幕像素。
static func calculate_clamped_world_position(
	viewport_size: Vector2,
	content_rect: Rect2,
	zoom: float,
	desired_position: Vector2,
	edge_margin: float
) -> Vector2:
	var result: Vector2 = desired_position
	result.x = _clamp_world_axis(
		viewport_size.x,
		content_rect.position.x,
		content_rect.size.x,
		zoom,
		desired_position.x,
		edge_margin
	)
	result.y = _clamp_world_axis(
		viewport_size.y,
		content_rect.position.y,
		content_rect.size.y,
		zoom,
		desired_position.y,
		edge_margin
	)
	return result


# --- 私有/辅助方法 ---

static func _clamp_world_axis(
	viewport_extent: float,
	content_start: float,
	content_extent: float,
	zoom: float,
	desired_position: float,
	edge_margin: float
) -> float:
	if viewport_extent <= 0.0 or content_extent <= 0.0:
		return desired_position
	var scaled_extent: float = content_extent * zoom
	var scaled_start: float = content_start * zoom
	var safe_margin: float = minf(maxf(edge_margin, 0.0), viewport_extent * 0.5)
	if scaled_extent <= maxf(viewport_extent - safe_margin * 2.0, 0.0):
		return (viewport_extent - scaled_extent) * 0.5 - scaled_start
	var minimum_position: float = (
		viewport_extent
		- safe_margin
		- (content_start + content_extent) * zoom
	)
	var maximum_position: float = safe_margin - scaled_start
	return clampf(desired_position, minimum_position, maximum_position)
