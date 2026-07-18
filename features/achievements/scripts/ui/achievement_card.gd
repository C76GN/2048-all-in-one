## AchievementCard: 单个成就的只读进度卡片。
class_name AchievementCard
extends PanelContainer


const _LOCKED_TITLE: String = "???"


# --- 私有变量 ---

var _pending_entry: Dictionary = {}


# --- @onready 变量 (节点引用) ---

@onready var _marker: Label = %Marker
@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _progress_label: Label = %ProgressLabel
@onready var _status: Label = %Status


# --- Godot 生命周期方法 ---


func _ready() -> void:
	if not _pending_entry.is_empty():
		_apply_entry(_pending_entry)


# --- 公共方法 ---

## 使用 AchievementSystem 展示快照配置卡片。
## @param entry: 单个成就的只读展示字典。
func configure(entry: Dictionary) -> void:
	_pending_entry = entry.duplicate(true)
	if not is_node_ready():
		return
	_apply_entry(_pending_entry)


# --- 私有/辅助方法 ---

func _apply_entry(entry: Dictionary) -> void:
	var completed: bool = GFVariantData.get_option_bool(entry, &"completed")
	var is_hidden: bool = (
		GFVariantData.get_option_bool(entry, &"hidden_until_unlocked")
		and not completed
	)
	var current_value: int = GFVariantData.get_option_int(entry, &"current_value", 0)
	var target_value: int = maxi(
		GFVariantData.get_option_int(entry, &"target_value", 1),
		1
	)
	_marker.text = "✓" if completed else "?" if is_hidden else "·"
	_title.text = (
		_LOCKED_TITLE
		if is_hidden
		else tr(GFVariantData.get_option_string_name(entry, &"title_key"))
	)
	_description.text = (
		tr("ACHIEVEMENT_HIDDEN_DESC")
		if is_hidden
		else tr(GFVariantData.get_option_string_name(entry, &"description_key"))
	)
	_progress_bar.max_value = target_value
	_progress_bar.value = current_value
	_progress_label.text = "%d / %d" % [current_value, target_value]
	_status.text = tr(
		"ACHIEVEMENT_STATUS_UNLOCKED"
		if completed
		else "ACHIEVEMENT_STATUS_IN_PROGRESS"
	)
	_status.modulate = Color("#445162") if completed else Color("#887c56")
