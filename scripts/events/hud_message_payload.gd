## HudMessagePayload: 传递要在 HUD 上显示的提示消息及停留时间的数据载荷。
class_name HudMessagePayload
extends GFPayload


# --- 公共变量 ---

## 消息内容
var message: String

## 停留时间（秒）
var duration: float


# --- Godot 生命周期方法 ---

func _init(p_message: String = "", p_duration: float = 3.0) -> void:
	message = p_message
	duration = p_duration
