# scripts/global/game_save_resource.gd

## GameSaveResource: 用于存储游戏存档数据（分数和设置）的资源类。
class_name GameSaveResource
extends Resource


# --- 导出变量 ---

## 存储所有模式最高分数据的字典。
## 结构: { "mode_id": { "4x4": score, "5x5": score } }
@export var scores: Dictionary = {}

## 存储游戏设置数据的字典。
@export var settings: Dictionary = {
	&"locale": "zh"
}


# --- 公共方法 ---

## 确保设置项包含所有默认键。
func ensure_defaults() -> void:
	if not settings.has(&"locale"):
		settings[&"locale"] = "zh"
