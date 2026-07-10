## GameAudioTheme: 定义可切换的主题音效银行和事件 ID。
class_name GameAudioTheme
extends Resource


# --- 导出变量 ---

@export var theme_id: StringName = &""
@export var display_name_key: String = ""
@export var description_key: String = ""
@export var audio_bank_id: StringName = &""
@export var audio_bank: GFAudioBank

@export var ui_select_event: StringName = &"ui/select"
@export var ui_confirm_event: StringName = &"ui/confirm"
@export var tile_spawn_event: StringName = &"tile/spawn"
@export var tile_move_event: StringName = &"tile/move"
@export var tile_merge_event: StringName = &"tile/merge"
@export var game_over_event: StringName = &"game/over"


# --- 公共方法 ---

func get_display_text() -> String:
	if not display_name_key.is_empty():
		return tr(display_name_key)
	if theme_id != &"":
		return String(theme_id)
	return tr("UI_UNKNOWN")


func get_resolved_bank_id() -> StringName:
	if audio_bank_id != &"":
		return audio_bank_id
	return theme_id
