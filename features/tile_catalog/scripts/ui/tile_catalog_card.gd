## TileCatalogCard: 图鉴中的单个方块组合条目。
class_name TileCatalogCard
extends Button


# --- 信号 ---

signal entry_selected(entry: Dictionary)


# --- 私有变量 ---

var _entry: Dictionary = {}
var _background_color: Color = Color("#f0d696")
var _font_color: Color = Color("#594a45")


# --- @onready 变量 (节点引用) ---

@onready var _preview_holder: Control = %PreviewHolder
@onready var _preview_tile: Tile = %PreviewTile
@onready var _title_label: Label = %TitleLabel
@onready var _summary_label: Label = %SummaryLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _pressed_connection: int = pressed.connect(_on_pressed)
	var _resized_connection: int = _preview_holder.resized.connect(_center_preview)
	_center_preview()
	_apply_entry()


# --- 公共方法 ---

## 配置只读图鉴投影与当前主题下的方块颜色。
## @param entry: TileDiscoverySystem 生成的图鉴条目。
## @param background_color: 方块预览背景色。
## @param font_color: 方块预览文字色。
func configure(entry: Dictionary, background_color: Color, font_color: Color) -> void:
	_entry = entry.duplicate(true)
	_background_color = background_color
	_font_color = font_color
	if is_node_ready():
		_apply_entry()


## 返回当前条目的只读副本。
func get_entry() -> Dictionary:
	return _entry.duplicate(true)


## 同步单选视觉状态，不派发 pressed 信号。
## @param selected: 当前卡片是否为详情选中项。
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)


# --- 私有/辅助方法 ---

func _apply_entry() -> void:
	if _entry.is_empty() or not is_instance_valid(_preview_tile):
		return
	var discovered: bool = GFVariantData.get_option_bool(_entry, &"discovered")
	var presentation: Dictionary = GFVariantData.get_option_dictionary(
		_entry,
		&"presentation"
	)
	var visual_layers: Array[StringName] = _to_string_name_array(
		GFVariantData.get_option_array(presentation, &"visual_layer_ids")
	)
	var preview_background: Color = _background_color
	var preview_font: Color = _font_color
	if not discovered:
		preview_background = preview_background.lerp(Color("#a9a994"), 0.58)
		preview_font = Color("#594a45")

	_preview_tile.setup(
		2,
		GFVariantData.get_option_string_name(_entry, &"definition_id"),
		preview_background,
		preview_font,
		GFVariantData.get_option_string_name(_entry, &"visual_family_id"),
		visual_layers
	)
	_preview_tile.value_label.text = "?"
	_preview_tile.modulate.a = 1.0 if discovered else 0.62

	if discovered:
		_title_label.text = tr(
			GFVariantData.get_option_string_name(_entry, &"display_name_key")
		)
		_summary_label.text = tr("TILE_CATALOG_RULE_COUNT") % (
			GFVariantData.get_option_array(_entry, &"active_recipe_ids").size()
		)
	else:
		_title_label.text = tr("TILE_CATALOG_UNDISCOVERED")
		_summary_label.text = tr("TILE_CATALOG_LOCKED_SUMMARY")


func _center_preview() -> void:
	if not is_instance_valid(_preview_tile) or not is_instance_valid(_preview_holder):
		return
	_preview_tile.position = Vector2(_preview_holder.size.x * 0.5, 44.0)


func _to_string_name_array(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		var item: StringName = GFVariantData.to_string_name(value)
		if item != &"":
			result.append(item)
	return result


# --- 信号处理函数 ---

func _on_pressed() -> void:
	entry_selected.emit(get_entry())
