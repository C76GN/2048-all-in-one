## HudMessagePayload: 传递要在 HUD 上显示的提示消息及停留时间的数据载荷。
class_name HudMessagePayload
extends GFPayload

## 消息内容
var message: String

## 停留时间（秒）
var duration: float


func _init(p_message: String = "", p_duration: float = 3.0) -> void:
	message = p_message
	duration = p_duration
