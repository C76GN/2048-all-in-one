## TileCatalogDialog: 响应式方块图鉴 GF UI Route。
class_name TileCatalogDialog
extends GameUiController


# --- 常量 ---

const TILE_CATALOG_CARD_SCENE: PackedScene = preload(
	"res://features/tile_catalog/scenes/ui/tile_catalog_card.tscn"
)
const _COMPACT_BREAKPOINT: float = 900.0
const _ONE_COLUMN_BREAKPOINT: float = 560.0
const _DESKTOP_CATALOG_MINIMUM_WIDTH: float = 520.0
const _FALLBACK_BACKGROUND: Color = Color("#f0d696")
const _FALLBACK_FONT: Color = Color("#594a45")


# --- 私有变量 ---

var _discovery_system: TileDiscoverySystem = null
var _clock_utility: GameClockUtility = null
var _signal_utility: GFSignalUtility = null
var _theme_utility: GameThemeUtility = null
var _viewport_utility: GFViewportUtility = null
var _cards_by_key: Dictionary = {}
var _selected_composition_key: String = ""
var _layout_update_queued: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _outer_margin: MarginContainer = %OuterMargin
@onready var _title_label: Label = %TitleLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _back_button: Button = %BackButton
@onready var _header: BoxContainer = %Header
@onready var _filters: BoxContainer = %Filters
@onready var _search_input: LineEdit = %SearchInput
@onready var _state_filter: OptionButton = %StateFilter
@onready var _content: BoxContainer = %Content
@onready var _catalog_area: VBoxContainer = %CatalogArea
@onready var _catalog_grid: GridContainer = %CatalogGrid
@onready var _empty_label: Label = %EmptyLabel
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_state: Label = %DetailState
@onready var _detail_form: Label = %DetailForm
@onready var _detail_recipes: Label = %DetailRecipes
@onready var _detail_max_value: Label = %DetailMaxValue
@onready var _detail_discovered_at: Label = %DetailDiscoveredAt


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_dependencies()
	_setup_state_filter()
	_bind_runtime_signals()
	_update_ui_text()
	_queue_layout_update()
	_search_input.grab_focus()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_dialog()
		get_viewport().set_input_as_handled()


# --- 虚方法 ---

func _update_ui_text() -> void:
	if not is_node_ready():
		return
	_title_label.text = tr("TILE_CATALOG_TITLE")
	_back_button.text = tr("BACK_BUTTON")
	_search_input.placeholder_text = tr("TILE_CATALOG_SEARCH_PLACEHOLDER")
	_empty_label.text = tr("TILE_CATALOG_EMPTY")
	_setup_state_filter()
	_rebuild_catalog()


# --- 私有/辅助方法 ---

func _resolve_dependencies() -> void:
	var discovery_value: Object = get_system(TileDiscoverySystem)
	if discovery_value is TileDiscoverySystem:
		_discovery_system = discovery_value
	var clock_value: Object = get_utility(GameClockUtility)
	if clock_value is GameClockUtility:
		_clock_utility = clock_value
	var signal_value: Object = get_utility(GFSignalUtility)
	if signal_value is GFSignalUtility:
		_signal_utility = signal_value
	var theme_value: Object = get_utility(GameThemeUtility)
	if theme_value is GameThemeUtility:
		_theme_utility = theme_value
	var viewport_value: Object = get_utility(GFViewportUtility)
	if viewport_value is GFViewportUtility:
		_viewport_utility = viewport_value


func _bind_runtime_signals() -> void:
	if not is_instance_valid(_signal_utility):
		push_error("[TileCatalogDialog] 缺少 GFSignalUtility。")
		return
	var _back_connection: GFSignalConnection = _signal_utility.connect_signal(
		_back_button.pressed,
		_close_dialog,
		self
	)
	var _search_connection: GFSignalConnection = _signal_utility.connect_signal(
		_search_input.text_changed,
		_on_search_changed,
		self
	)
	var _filter_connection: GFSignalConnection = _signal_utility.connect_signal(
		_state_filter.item_selected,
		_on_state_filter_selected,
		self
	)
	var _resize_connection: GFSignalConnection = _signal_utility.connect_signal(
		resized,
		_queue_layout_update,
		self
	)
	if is_instance_valid(_discovery_system):
		var _tile_connection: GFSignalConnection = _signal_utility.connect_signal(
			_discovery_system.tile_discovery_changed,
			_on_tile_discovery_changed,
			self
		)
	if is_instance_valid(_theme_utility):
		var _theme_connection: GFSignalConnection = _signal_utility.connect_signal(
			_theme_utility.visual_theme_changed,
			_on_visual_theme_changed,
			self
		)


func _setup_state_filter() -> void:
	if not is_instance_valid(_state_filter):
		return
	var selected_index: int = maxi(_state_filter.selected, 0)
	_state_filter.clear()
	_state_filter.add_item(tr("TILE_CATALOG_FILTER_ALL"), 0)
	_state_filter.add_item(tr("TILE_CATALOG_FILTER_DISCOVERED"), 1)
	_state_filter.add_item(tr("TILE_CATALOG_FILTER_UNDISCOVERED"), 2)
	_state_filter.select(clampi(selected_index, 0, _state_filter.item_count - 1))


func _rebuild_catalog() -> void:
	if not is_node_ready():
		return
	_clear_catalog_cards()
	if not is_instance_valid(_discovery_system):
		_empty_label.visible = true
		_clear_detail()
		return

	var entries: Array[Dictionary] = _discovery_system.get_catalog_entries()
	var visible_count: int = 0
	var first_visible_entry: Dictionary = {}
	for entry: Dictionary in entries:
		if not _entry_matches_filters(entry):
			continue
		var card_node: Node = TILE_CATALOG_CARD_SCENE.instantiate()
		if not card_node is TileCatalogCard:
			card_node.queue_free()
			continue
		var card: TileCatalogCard = card_node
		_catalog_grid.add_child(card)
		var colors: Array[Color] = _resolve_tile_colors(entry)
		card.configure(entry, colors[0], colors[1])
		var _card_connection: GFSignalConnection = _signal_utility.connect_signal(
			card.entry_selected,
			_on_entry_selected,
			self
		)
		var composition_key: String = GFVariantData.get_option_string(
			entry,
			&"composition_key"
		)
		_cards_by_key[composition_key] = card
		visible_count += 1
		if first_visible_entry.is_empty():
			first_visible_entry = entry

	_empty_label.visible = visible_count == 0
	_update_progress(entries)
	if visible_count == 0:
		_clear_detail()
		return
	var selected_entry: Dictionary = _find_entry(entries, _selected_composition_key)
	if selected_entry.is_empty() or not _entry_matches_filters(selected_entry):
		selected_entry = first_visible_entry
	_select_entry(selected_entry)


func _clear_catalog_cards() -> void:
	_cards_by_key.clear()
	for child: Node in _catalog_grid.get_children():
		child.queue_free()


func _entry_matches_filters(entry: Dictionary) -> bool:
	var discovered: bool = GFVariantData.get_option_bool(entry, &"discovered")
	match _state_filter.selected:
		1:
			if not discovered:
				return false
		2:
			if discovered:
				return false

	var query: String = _search_input.text.strip_edges().to_lower()
	if query.is_empty():
		return true
	var searchable: PackedStringArray = PackedStringArray([
		tr(GFVariantData.get_option_string_name(entry, &"display_name_key")),
		GFVariantData.get_option_string(entry, &"definition_id"),
	])
	for recipe_value: Variant in GFVariantData.get_option_array(entry, &"recipes"):
		if recipe_value is Dictionary:
			var recipe: Dictionary = recipe_value
			var _searchable_appended: bool = searchable.append(
				tr(GFVariantData.get_option_string_name(recipe, &"display_name_key"))
			)
	return " ".join(searchable).to_lower().contains(query)


func _select_entry(entry: Dictionary) -> void:
	_selected_composition_key = GFVariantData.get_option_string(
		entry,
		&"composition_key"
	)
	for key_value: Variant in _cards_by_key.keys():
		var card_value: Variant = _cards_by_key[key_value]
		if card_value is TileCatalogCard:
			var card: TileCatalogCard = card_value
			card.set_selected(GFVariantData.to_text(key_value) == _selected_composition_key)
	_update_detail(entry)


func _update_detail(entry: Dictionary) -> void:
	var discovered: bool = GFVariantData.get_option_bool(entry, &"discovered")
	if not discovered:
		_detail_title.text = tr("TILE_CATALOG_UNDISCOVERED")
		_detail_state.text = tr("TILE_CATALOG_STATE_UNDISCOVERED")
		_detail_form.text = tr("TILE_CATALOG_LOCKED_DETAIL")
		_detail_recipes.text = ""
		_detail_max_value.text = ""
		_detail_discovered_at.text = ""
		return

	_detail_title.text = tr(
		GFVariantData.get_option_string_name(entry, &"display_name_key")
	)
	_detail_state.text = tr("TILE_CATALOG_STATE_DISCOVERED")
	_detail_form.text = tr("TILE_CATALOG_FORM") % tr(
		"TILE_CATALOG_FORM_INITIAL"
		if GFVariantData.get_option_bool(entry, &"is_initial_composition")
		else "TILE_CATALOG_FORM_COMPOSED"
	)
	var recipe_names: PackedStringArray = PackedStringArray()
	for recipe_value: Variant in GFVariantData.get_option_array(entry, &"recipes"):
		if recipe_value is Dictionary:
			var recipe: Dictionary = recipe_value
			var _recipe_name_appended: bool = recipe_names.append(
				tr(GFVariantData.get_option_string_name(recipe, &"display_name_key"))
			)
	_detail_recipes.text = tr("TILE_CATALOG_RECIPES") % " / ".join(recipe_names)
	var discovery: Dictionary = GFVariantData.get_option_dictionary(entry, &"discovery")
	_detail_max_value.text = tr("TILE_CATALOG_MAX_VALUE") % GFVariantData.get_option_int(
		discovery,
		&"max_observed_value"
	)
	var discovered_at: int = GFVariantData.get_option_int(discovery, &"discovered_at")
	var discovered_at_text: String = (
		_clock_utility.format_datetime(discovered_at)
		if is_instance_valid(_clock_utility)
		else ""
	)
	_detail_discovered_at.text = tr("TILE_CATALOG_DISCOVERED_AT") % discovered_at_text


func _clear_detail() -> void:
	_selected_composition_key = ""
	_detail_title.text = tr("TILE_CATALOG_DETAIL_EMPTY")
	_detail_state.text = ""
	_detail_form.text = ""
	_detail_recipes.text = ""
	_detail_max_value.text = ""
	_detail_discovered_at.text = ""


func _update_progress(entries: Array[Dictionary]) -> void:
	var discovered_count: int = 0
	for entry: Dictionary in entries:
		if GFVariantData.get_option_bool(entry, &"discovered"):
			discovered_count += 1
	_progress_label.text = tr("TILE_CATALOG_PROGRESS") % [
		discovered_count,
		entries.size(),
	]


func _resolve_tile_colors(entry: Dictionary) -> Array[Color]:
	if not is_instance_valid(_theme_utility):
		return [_FALLBACK_BACKGROUND, _FALLBACK_FONT]
	var visual_theme: GameTheme = _theme_utility.get_current_visual_theme()
	var definition_value: Variant = entry.get(&"definition")
	if visual_theme == null or not definition_value is TileDefinition:
		return [_FALLBACK_BACKGROUND, _FALLBACK_FONT]
	var definition: TileDefinition = definition_value
	var scheme_value: Variant = visual_theme.color_schemes.get(definition.color_scheme_index)
	if not scheme_value is TileColorScheme:
		return [_FALLBACK_BACKGROUND, _FALLBACK_FONT]
	var scheme: TileColorScheme = scheme_value
	if scheme.styles.is_empty() or scheme.styles[0] == null:
		return [_FALLBACK_BACKGROUND, _FALLBACK_FONT]
	var style: TileLevelStyle = scheme.styles[0]
	return [style.background_color, style.font_color]


func _find_entry(entries: Array[Dictionary], composition_key: String) -> Dictionary:
	if composition_key.is_empty():
		return {}
	for entry: Dictionary in entries:
		if GFVariantData.get_option_string(entry, &"composition_key") == composition_key:
			return entry
	return {}


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var width: float = size.x
	var compact: bool = width < _COMPACT_BREAKPOINT
	_header.vertical = compact
	_filters.vertical = compact
	_content.vertical = compact
	_catalog_area.custom_minimum_size = (
		Vector2.ZERO
		if compact
		else Vector2(_DESKTOP_CATALOG_MINIMUM_WIDTH, 0.0)
	)
	_catalog_grid.columns = (
		1 if width < _ONE_COLUMN_BREAKPOINT
		else 2 if width < 1360.0
		else 3
	)
	var extra_margins: Dictionary = (
		{"top": 10.0, "left": 10.0, "bottom": 10.0, "right": 10.0}
		if width < _COMPACT_BREAKPOINT
		else {"top": 24.0, "left": 28.0, "bottom": 24.0, "right": 28.0}
	)
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
			_outer_margin,
			get_viewport(),
			extra_margins
		)


func _close_dialog() -> void:
	var _closed: bool = _close_current_popup_route(GameUiRouterUtility.ROUTE_TILE_CATALOG)


# --- 信号处理函数 ---

func _on_search_changed(_text: String) -> void:
	_rebuild_catalog()


func _on_state_filter_selected(_index: int) -> void:
	_rebuild_catalog()


func _on_entry_selected(entry: Dictionary) -> void:
	_select_entry(entry)


func _on_tile_discovery_changed(_composition_key: String) -> void:
	_rebuild_catalog()


func _on_visual_theme_changed(_theme: GameTheme) -> void:
	_rebuild_catalog()
