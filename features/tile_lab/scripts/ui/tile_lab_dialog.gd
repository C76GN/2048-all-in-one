## TileLabDialog: 可保存方块组合并运行真实双块交互的响应式 GF UI Route。
class_name TileLabDialog
extends GameUiController


# --- 常量 ---

const ROUTE_ID: StringName = &"tile_lab"
const _COMPACT_BREAKPOINT: float = 900.0
const _ONE_COLUMN_BREAKPOINT: float = 540.0
const _DESKTOP_MAXIMUM_WIDTH: float = 1120.0
const _DESKTOP_MAXIMUM_HEIGHT: float = 720.0
const _MINIMUM_TOUCH_TARGET_SIZE: float = 44.0
const _DESKTOP_RECIPE_LIST_MINIMUM_HEIGHT: float = 112.0
const _DESKTOP_RECIPE_LIST_MAXIMUM_HEIGHT: float = 180.0
const _DESKTOP_RECIPE_LIST_HEIGHT_BUDGET: float = 608.0


# --- 私有变量 ---

var _tile_lab: TileLabSystem = null
var _signal_utility: GFSignalUtility = null
var _save_graph: GameSaveGraphUtility = null
var _theme_utility: GameThemeUtility = null
var _viewport_utility: GFViewportUtility = null
var _blueprints: Array[CustomTileBlueprintData] = []
var _current_blueprint_id: String = ""
var _selected_recipe_ids: Array[StringName] = []
var _recipe_buttons_by_id: Dictionary = {}
var _loading_ui: bool = false
var _layout_update_queued: bool = false
var _has_revealed_recipes: bool = false
var _persistence_operation_busy: bool = false
var _persistence_outcome_unknown: bool = false
var _persistence_operation_token: int = 0
var _pending_persistence_transaction_id: int = 0
var _pending_persistence_action: StringName = &""
var _pending_persistence_resource_id: String = ""
var _pending_persistence_resource: Resource = null
var _persistence_reconciliation_prompted: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _outer_margin: MarginContainer = %OuterMargin
@onready var _surface: PanelContainer = $OuterMargin/Surface
@onready var _header: BoxContainer = %Header
@onready var _title_label: Label = %TitleLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _back_button: Button = %BackButton
@onready var _body_scroll: ScrollContainer = %BodyScroll
@onready var _workspace: BoxContainer = %Workspace
@onready var _blueprint_pane: PanelContainer = %BlueprintPane
@onready var _blueprint_title: Label = %BlueprintTitle
@onready var _blueprint_option: OptionButton = %BlueprintOption
@onready var _name_input: LineEdit = %NameInput
@onready var _blueprint_actions: BoxContainer = %BlueprintActions
@onready var _new_button: Button = %NewButton
@onready var _save_button: Button = %SaveButton
@onready var _delete_button: Button = %DeleteButton
@onready var _base_label: Label = %BaseLabel
@onready var _base_definition_option: OptionButton = %BaseDefinitionOption
@onready var _recipes_label: Label = %RecipesLabel
@onready var _recipes_scroll: ScrollContainer = %RecipesScroll
@onready var _recipe_list: VBoxContainer = %RecipeList
@onready var _selection_status_label: Label = %SelectionStatusLabel
@onready var _simulation_title: Label = %SimulationTitle
@onready var _simulation_description: Label = %SimulationDescription
@onready var _simulation_pane: PanelContainer = (
	$OuterMargin/Surface/InnerMargin/RootVBox/BodyScroll/Workspace/SimulationPane
)
@onready var _value_row: BoxContainer = %ValueRow
@onready var _left_value_label: Label = %LeftValueLabel
@onready var _right_value_label: Label = %RightValueLabel
@onready var _left_value_spin: SpinBox = %LeftValueSpin
@onready var _right_value_spin: SpinBox = %RightValueSpin
@onready var _run_simulation_button: Button = %RunSimulationButton
@onready var _result_label: Label = %ResultLabel
@onready var _result_panel: PanelContainer = (
	$OuterMargin/Surface/InnerMargin/RootVBox/BodyScroll/Workspace/SimulationPane/Margin/Content/ResultPanel
)
@onready var _status_label: Label = %StatusLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_dependencies()
	_bind_local_signals()
	_bind_runtime_signals()
	_apply_semantic_styles()
	_update_ui_text()
	_refresh_from_system()
	_queue_layout_update()
	call_deferred(&"_focus_initial_control")


func _exit_tree() -> void:
	_persistence_operation_token += 1
	_persistence_operation_busy = false
	_persistence_outcome_unknown = false
	_clear_persistence_tracking()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


# --- 虚方法 ---

func _update_ui_text() -> void:
	if not is_node_ready():
		return
	_title_label.text = _localized_text("TILE_LAB_TITLE", "方块试验台")
	_back_button.text = tr("BACK_BUTTON")
	_blueprint_title.text = _localized_text(
		"TILE_LAB_BLUEPRINT_SECTION",
		"蓝图组合"
	)
	_name_input.placeholder_text = _localized_text(
		"TILE_LAB_NAME_PLACEHOLDER",
		"蓝图名称"
	)
	_new_button.text = _localized_text("TILE_LAB_NEW", "新建")
	_save_button.text = _localized_text("TILE_LAB_SAVE", "保存")
	_delete_button.text = _localized_text("TILE_LAB_DELETE", "删除")
	_base_label.text = _localized_text(
		"TILE_LAB_BASE_DEFINITION",
		"外观基底"
	)
	_recipes_label.text = _localized_text("TILE_LAB_RECIPES", "能力配方")
	_simulation_title.text = _localized_text(
		"TILE_LAB_SIMULATION_SECTION",
		"双块交互沙盒"
	)
	_simulation_description.text = _localized_text(
		"TILE_LAB_SIMULATION_DESCRIPTION",
		"设置左右数值，使用当前组合执行一次真实能力交互。"
	)
	_left_value_label.text = _localized_text(
		"TILE_LAB_LEFT_VALUE",
		"左侧数值"
	)
	_right_value_label.text = _localized_text(
		"TILE_LAB_RIGHT_VALUE",
		"右侧数值"
	)
	_run_simulation_button.text = _localized_text(
		"TILE_LAB_RUN",
		"运行交互"
	)
	_rebuild_blueprint_option()
	_rebuild_base_definition_option()
	_rebuild_recipe_buttons()
	_update_summary()
	_update_selection_validation()


# --- 私有/辅助方法 ---

func _resolve_dependencies() -> void:
	var system_value: Object = get_system(TileLabSystem)
	if system_value is TileLabSystem:
		_tile_lab = system_value
	var signal_value: Object = get_utility(GFSignalUtility)
	if signal_value is GFSignalUtility:
		_signal_utility = signal_value
	var save_graph_value: Object = get_utility(GameSaveGraphUtility)
	if save_graph_value is GameSaveGraphUtility:
		_save_graph = save_graph_value
	var theme_value: Object = get_utility(GameThemeUtility)
	if theme_value is GameThemeUtility:
		_theme_utility = theme_value
	var viewport_value: Object = get_utility(GFViewportUtility)
	if viewport_value is GFViewportUtility:
		_viewport_utility = viewport_value


func _bind_local_signals() -> void:
	var _back_connection: int = _back_button.pressed.connect(_close_dialog)
	var _blueprint_connection: int = _blueprint_option.item_selected.connect(
		_on_blueprint_selected
	)
	var _name_connection: int = _name_input.text_changed.connect(
		_on_edit_value_changed
	)
	var _new_connection: int = _new_button.pressed.connect(
		_configure_new_blueprint
	)
	var _save_connection: int = _save_button.pressed.connect(
		_on_save_pressed
	)
	var _delete_connection: int = _delete_button.pressed.connect(
		_on_delete_pressed
	)
	var _base_connection: int = _base_definition_option.item_selected.connect(
		_on_base_definition_selected
	)
	var _left_connection: int = _left_value_spin.value_changed.connect(
		_on_preview_value_changed
	)
	var _right_connection: int = _right_value_spin.value_changed.connect(
		_on_preview_value_changed
	)
	var _run_connection: int = _run_simulation_button.pressed.connect(
		_on_run_simulation_pressed
	)
	var _resize_connection: int = resized.connect(_queue_layout_update)


func _bind_runtime_signals() -> void:
	if not is_instance_valid(_signal_utility):
		return
	if is_instance_valid(_tile_lab):
		var _blueprints_connection: GFSignalConnection = _signal_utility.connect_signal(
			_tile_lab.blueprints_changed,
			_on_blueprints_changed,
			self
		)
	if is_instance_valid(_theme_utility):
		var _theme_connection: GFSignalConnection = _signal_utility.connect_signal(
			_theme_utility.visual_theme_changed,
			_on_visual_theme_changed,
			self
		)
	if is_instance_valid(_save_graph):
		var _reconciliation_connection: GFSignalConnection = _signal_utility.connect_signal(
			_save_graph.section_reconciliation_settled,
			_on_section_reconciliation_settled,
			self
		)


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_panel_container(
		_surface,
		GameUiStyleUtility.SurfaceRole.SHELL,
		GameUiStyleUtility.BorderRole.DEFAULT,
		2
	)
	style.style_panel_container(_blueprint_pane)
	style.style_panel_container(_simulation_pane)
	style.style_panel_container(
		_result_panel,
		GameUiStyleUtility.SurfaceRole.FIELD
	)
	style.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_summary_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(
		_blueprint_title,
		GameUiStyleUtility.TextRole.PRIMARY,
		22
	)
	style.style_label(
		_simulation_title,
		GameUiStyleUtility.TextRole.PRIMARY,
		22
	)
	style.style_label(
		_simulation_description,
		GameUiStyleUtility.TextRole.SECONDARY
	)
	style.style_label(_selection_status_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_status_label, GameUiStyleUtility.TextRole.PRIMARY)
	style.style_label(_result_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_button(_back_button, GameUiStyleUtility.ButtonRole.ICON)
	style.style_button(_new_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_save_button, GameUiStyleUtility.ButtonRole.PRIMARY)
	style.style_button(_delete_button, GameUiStyleUtility.ButtonRole.QUIET)
	style.style_button(
		_run_simulation_button,
		GameUiStyleUtility.ButtonRole.PRIMARY
	)
	_refresh_recipe_button_styles()


func _refresh_from_system(preferred_blueprint_id: String = "") -> void:
	_blueprints.clear()
	if is_instance_valid(_tile_lab):
		_blueprints = _tile_lab.load_blueprints()
	_rebuild_blueprint_option()
	_rebuild_base_definition_option()
	if (
		not preferred_blueprint_id.is_empty()
		and _select_blueprint_option(preferred_blueprint_id)
	):
		var selected: CustomTileBlueprintData = _find_blueprint(
			preferred_blueprint_id
		)
		if selected != null:
			_apply_blueprint(selected)
			return
	_configure_new_blueprint()


func _rebuild_blueprint_option() -> void:
	if not is_instance_valid(_blueprint_option):
		return
	var preserved_id: String = _current_blueprint_id
	_loading_ui = true
	var blueprint_items: Array[Dictionary] = [{
		&"text": _localized_text(
			"TILE_LAB_NEW_BLUEPRINT_OPTION",
			"新蓝图"
		),
		&"metadata": "",
		&"selected": preserved_id.is_empty(),
	}]
	for blueprint: CustomTileBlueprintData in _blueprints:
		blueprint_items.append({
			&"text": blueprint.display_name,
			&"metadata": blueprint.blueprint_id,
			&"selected": blueprint.blueprint_id == preserved_id,
		})
	var _blueprint_count: int = GFItemListBinder.write_items(
		_blueprint_option,
		blueprint_items,
		{&"metadata_key": &"metadata"}
	)
	if _blueprint_option.selected < 0 and _blueprint_option.item_count > 0:
		_blueprint_option.select(0)
	_loading_ui = false


func _rebuild_base_definition_option() -> void:
	if not is_instance_valid(_base_definition_option):
		return
	var preserved_id: StringName = _get_selected_base_definition_id()
	_loading_ui = true
	var definition_items: Array[Dictionary] = []
	if is_instance_valid(_tile_lab):
		for entry: Dictionary in _tile_lab.get_base_definition_entries():
			var definition_id: StringName = (
				GFVariantData.get_option_string_name(entry, &"definition_id")
			)
			var display_name_key: StringName = (
				GFVariantData.get_option_string_name(
					entry,
					&"display_name_key"
				)
			)
			definition_items.append({
				&"text": tr(display_name_key),
				&"metadata": definition_id,
				&"selected": definition_id == preserved_id,
			})
	var _definition_count: int = GFItemListBinder.write_items(
		_base_definition_option,
		definition_items,
		{&"metadata_key": &"metadata"}
	)
	if _base_definition_option.selected < 0 and _base_definition_option.item_count > 0:
		_base_definition_option.select(0)
	_loading_ui = false


func _rebuild_recipe_buttons() -> void:
	if not is_instance_valid(_recipe_list):
		return
	if not is_instance_valid(_tile_lab):
		_clear_recipe_buttons()
		return
	var entries: Array[Dictionary] = _tile_lab.get_recipe_entries(
		_selected_recipe_ids
	)
	var focused_recipe_id: StringName = _get_focused_recipe_id()
	var display_names: Dictionary = _get_recipe_display_names(entries)
	var expected_ids: Dictionary = {}
	for entry: Dictionary in entries:
		var recipe_id: StringName = GFVariantData.get_option_string_name(
			entry,
			&"recipe_id"
		)
		if recipe_id != &"":
			expected_ids[recipe_id] = true
	_remove_obsolete_recipe_buttons(expected_ids)
	var child_index: int = 0
	for entry: Dictionary in entries:
		var recipe_id: StringName = GFVariantData.get_option_string_name(
			entry,
			&"recipe_id"
		)
		if recipe_id == &"":
			continue
		var button: CheckButton = _get_or_create_recipe_button(recipe_id)
		if not is_instance_valid(button):
			continue
		if button.get_index() != child_index:
			_recipe_list.move_child(button, child_index)
		child_index += 1
		_update_recipe_button(button, entry, display_names)
	_apply_recipe_focus_order()
	if focused_recipe_id != &"":
		call_deferred(&"_restore_recipe_focus", focused_recipe_id)
	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if is_instance_valid(motion) and not _has_revealed_recipes:
		_has_revealed_recipes = true
		var _reveal_count: int = motion.play_children_reveal(
			_recipe_list,
			Vector2.ZERO,
			0.018,
			0.0,
			0.12
		)


func _get_or_create_recipe_button(recipe_id: StringName) -> CheckButton:
	var cached_value: Variant = _recipe_buttons_by_id.get(recipe_id)
	if cached_value is CheckButton:
		var cached_button: CheckButton = cached_value
		if is_instance_valid(cached_button):
			return cached_button
	var button: CheckButton = CheckButton.new()
	button.name = "Recipe_%s" % String(recipe_id).validate_node_name()
	button.set_meta(&"recipe_id", recipe_id)
	button.custom_minimum_size = Vector2(
		0.0,
		_MINIMUM_TOUCH_TARGET_SIZE
	)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_child(button)
	_recipe_buttons_by_id[recipe_id] = button
	_apply_recipe_button_style(button)
	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if is_instance_valid(motion):
		var _bound: bool = motion.bind_button(button)
	var _toggle_connection: int = button.toggled.connect(
		_on_recipe_toggled.bind(recipe_id)
	)
	return button


func _update_recipe_button(
	button: CheckButton,
	entry: Dictionary,
	display_names: Dictionary
) -> void:
	var operation_blocked: bool = (
		_persistence_operation_busy
		or _persistence_outcome_unknown
	)
	var compatible: bool = GFVariantData.get_option_bool(
		entry,
		&"compatible"
	)
	var recipe_id: StringName = GFVariantData.get_option_string_name(
		entry,
		&"recipe_id"
	)
	button.text = GFVariantData.to_text(display_names.get(recipe_id, ""))
	button.tooltip_text = _get_recipe_tooltip(entry, display_names)
	button.set_pressed_no_signal(
		GFVariantData.get_option_bool(entry, &"selected")
	)
	button.disabled = operation_blocked or not compatible
	button.set_meta(&"recipe_conflict", not compatible)


func _remove_obsolete_recipe_buttons(expected_ids: Dictionary) -> void:
	for id_value: Variant in _recipe_buttons_by_id.keys():
		var recipe_id: StringName = GFVariantData.to_string_name(id_value)
		if expected_ids.has(recipe_id):
			continue
		var button_value: Variant = _recipe_buttons_by_id.get(recipe_id)
		if button_value is CheckButton:
			var button: CheckButton = button_value
			if is_instance_valid(button):
				if button.get_parent() == _recipe_list:
					_recipe_list.remove_child(button)
				button.queue_free()
		var _cached_button_erased: bool = _recipe_buttons_by_id.erase(
			recipe_id
		)


func _clear_recipe_buttons() -> void:
	_recipe_buttons_by_id.clear()
	for child: Node in _recipe_list.get_children():
		_recipe_list.remove_child(child)
		child.queue_free()


func _get_focused_recipe_id() -> StringName:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if not focus_owner is CheckButton:
		return &""
	var button: CheckButton = focus_owner
	if not _recipe_list.is_ancestor_of(button):
		return &""
	return GFVariantData.to_string_name(
		button.get_meta(&"recipe_id", &"")
	)


func _restore_recipe_focus(recipe_id: StringName) -> void:
	if not is_inside_tree():
		return
	var button_value: Variant = _recipe_buttons_by_id.get(recipe_id)
	if button_value is CheckButton:
		var button: CheckButton = button_value
		if is_instance_valid(button) and not button.disabled:
			button.grab_focus()
			return
	for child: Node in _recipe_list.get_children():
		if child is CheckButton:
			var fallback_button: CheckButton = child
			if fallback_button.visible and not fallback_button.disabled:
				fallback_button.grab_focus()
				return


func _apply_recipe_focus_order() -> void:
	var focus_order: Array[Control] = []
	for child: Node in _recipe_list.get_children():
		if child is CheckButton:
			var button: CheckButton = child
			if not button.disabled:
				focus_order.append(button)
	if focus_order.is_empty():
		return
	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(
		focus_order,
		{
			"axis": GFControlFocusUtility.AXIS_VERTICAL,
			"wrap": false,
			"wire_tab_order": true,
		}
	)
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error(
			"[TileLabDialog] GF Recipe 焦点顺序应用失败：%s"
			% str(focus_report.get("issues", []))
		)


func _get_recipe_display_names(entries: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in entries:
		var recipe_id: StringName = GFVariantData.get_option_string_name(
			entry,
			&"recipe_id"
		)
		var display_name_key: StringName = (
			GFVariantData.get_option_string_name(
				entry,
				&"display_name_key"
			)
		)
		var display_name: String = tr(display_name_key)
		if display_name_key == &"" or display_name == String(display_name_key):
			display_name = _localized_text(
				"TILE_LAB_RECIPES",
				"能力配方"
			)
		result[recipe_id] = display_name
	return result


func _get_recipe_tooltip(
	entry: Dictionary,
	display_names: Dictionary
) -> String:
	var recipe_id: StringName = GFVariantData.get_option_string_name(
		entry,
		&"recipe_id"
	)
	var display_name: String = GFVariantData.to_text(
		display_names.get(recipe_id, "")
	)
	if GFVariantData.get_option_bool(entry, &"selected"):
		return _localized_format(
			"TILE_LAB_RECIPE_ENABLED_HINT",
			"已启用“%s”。",
			display_name
		)
	if GFVariantData.get_option_bool(entry, &"compatible"):
		return _localized_format(
			"TILE_LAB_RECIPE_AVAILABLE_HINT",
			"选择“%s”加入当前组合。",
			display_name
		)
	var conflict: Dictionary = GFVariantData.get_option_dictionary(
		entry,
		&"conflict"
	)
	var owner_recipe_id: StringName = GFVariantData.get_option_string_name(
		conflict,
		&"owner_recipe_id"
	)
	var owner_display_name: String = GFVariantData.to_text(
		display_names.get(owner_recipe_id, "")
	)
	if not owner_display_name.is_empty():
		return _localized_format(
			"TILE_LAB_RECIPE_CONFLICT_HINT",
			"无法选择“%s”：与“%s”存在能力冲突。",
			[display_name, owner_display_name]
		)
	return _localized_format(
		"TILE_LAB_RECIPE_UNAVAILABLE_HINT",
		"当前组合无法使用“%s”。",
		display_name
	)


func _refresh_recipe_button_styles() -> void:
	if not is_instance_valid(_recipe_list):
		return
	for child: Node in _recipe_list.get_children():
		if child is CheckButton:
			var button: CheckButton = child
			_apply_recipe_button_style(button)


func _apply_recipe_button_style(button: CheckButton) -> void:
	if not is_instance_valid(button):
		return
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if is_instance_valid(style):
		style.style_button(
			button,
			GameUiStyleUtility.ButtonRole.SECONDARY
		)
	var pressed_color: Color = button.get_theme_color(
		"font_pressed_color"
	)
	button.add_theme_color_override(
		"font_hover_pressed_color",
		pressed_color
	)


func _focus_recipe_button(recipe_id: StringName) -> void:
	if not is_inside_tree() or not is_instance_valid(_recipe_list):
		return
	for child: Node in _recipe_list.get_children():
		if not child is CheckButton:
			continue
		var button: CheckButton = child
		var metadata_value: Variant = button.get_meta(&"recipe_id", &"")
		if not metadata_value is StringName:
			continue
		var button_recipe_id: StringName = metadata_value
		if button_recipe_id != recipe_id or button.disabled:
			continue
		button.grab_focus()
		return


func _configure_new_blueprint() -> void:
	if _persistence_operation_busy or _persistence_outcome_unknown:
		return
	_loading_ui = true
	_current_blueprint_id = ""
	if _blueprint_option.item_count > 0:
		_blueprint_option.select(0)
	_name_input.text = ""
	if _base_definition_option.item_count > 0:
		_base_definition_option.select(0)
	var base_definition_id: StringName = _get_selected_base_definition_id()
	_selected_recipe_ids.clear()
	if is_instance_valid(_tile_lab):
		_selected_recipe_ids = _tile_lab.get_initial_recipe_ids(
			base_definition_id
		)
	_left_value_spin.value = 2.0
	_right_value_spin.value = 2.0
	_loading_ui = false
	_result_label.text = _localized_text(
		"TILE_LAB_RESULT_WAITING",
		"等待运行"
	)
	_status_label.text = ""
	_delete_button.disabled = true
	_rebuild_recipe_buttons()
	_update_selection_validation()
	call_deferred(&"_focus_initial_control")


func _apply_blueprint(blueprint: CustomTileBlueprintData) -> void:
	if blueprint == null:
		return
	_loading_ui = true
	_current_blueprint_id = blueprint.blueprint_id
	_name_input.text = blueprint.display_name
	var _selected_base: bool = _select_base_definition_option(
		blueprint.base_definition_id
	)
	_selected_recipe_ids = blueprint.recipe_ids.duplicate()
	_left_value_spin.value = float(blueprint.preview_left_value)
	_right_value_spin.value = float(blueprint.preview_right_value)
	_loading_ui = false
	_delete_button.disabled = (
		_persistence_operation_busy
		or _persistence_outcome_unknown
	)
	_result_label.text = _localized_text(
		"TILE_LAB_RESULT_WAITING",
		"等待运行"
	)
	_status_label.text = ""
	_rebuild_recipe_buttons()
	_update_selection_validation()


func _make_edited_blueprint() -> CustomTileBlueprintData:
	var blueprint: CustomTileBlueprintData = CustomTileBlueprintData.new()
	blueprint.blueprint_id = _current_blueprint_id
	blueprint.display_name = _name_input.text
	blueprint.base_definition_id = _get_selected_base_definition_id()
	blueprint.recipe_ids = _selected_recipe_ids.duplicate()
	blueprint.preview_left_value = int(_left_value_spin.value)
	blueprint.preview_right_value = int(_right_value_spin.value)
	if not _current_blueprint_id.is_empty():
		var existing: CustomTileBlueprintData = _find_blueprint(
			_current_blueprint_id
		)
		if existing != null:
			blueprint.created_at = existing.created_at
			blueprint.updated_at = existing.updated_at
	return blueprint


func _update_selection_validation() -> void:
	var has_system: bool = is_instance_valid(_tile_lab)
	var report: GFValidationReport = (
		_tile_lab.validate_composition(
			_get_selected_base_definition_id(),
			_selected_recipe_ids
		)
		if has_system
		else null
	)
	var selection_valid: bool = report != null and report.is_ok()
	if selection_valid:
		_selection_status_label.text = _localized_format(
			"TILE_LAB_SELECTION_VALID",
			"组合有效：已选择 %d 个 Recipe。",
			_selected_recipe_ids.size()
		)
	else:
		var summary: String = (
			report.make_summary()
			if report != null
			else _localized_text("TILE_LAB_UNAVAILABLE", "试验台系统不可用。")
		)
		_selection_status_label.text = _localized_format(
			"TILE_LAB_SELECTION_INVALID",
			"组合无效：%s",
			summary
		)
	var at_capacity: bool = (
		_current_blueprint_id.is_empty()
		and _blueprints.size() >= TileLabSaveData.MAX_BLUEPRINT_COUNT
	)
	_save_button.disabled = (
		not selection_valid
		or _name_input.text.strip_edges().is_empty()
		or at_capacity
		or _persistence_operation_busy
		or _persistence_outcome_unknown
	)
	_run_simulation_button.disabled = not selection_valid
	_delete_button.disabled = (
		_current_blueprint_id.is_empty()
		or _persistence_operation_busy
		or _persistence_outcome_unknown
	)


func _update_summary() -> void:
	if is_instance_valid(_summary_label):
		_summary_label.text = _localized_format(
			"TILE_LAB_SUMMARY",
			"已保存 %d / %d",
			[
				_blueprints.size(),
				TileLabSaveData.MAX_BLUEPRINT_COUNT,
			]
		)


func _focus_initial_control() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_blueprint_option) and not _blueprint_option.disabled:
		_blueprint_option.grab_focus()
	elif is_instance_valid(_name_input):
		_name_input.grab_focus()


func _select_blueprint_option(blueprint_id: String) -> bool:
	for index: int in range(_blueprint_option.item_count):
		if GFVariantData.to_text(
			GFItemListBinder.get_item_metadata(
				_blueprint_option,
				index,
				""
			)
		) == blueprint_id:
			_blueprint_option.select(index)
			return true
	return false


func _select_base_definition_option(
	definition_id: StringName
) -> bool:
	for index: int in range(_base_definition_option.item_count):
		if GFVariantData.to_string_name(
			GFItemListBinder.get_item_metadata(
				_base_definition_option,
				index,
				&""
			)
		) == definition_id:
			_base_definition_option.select(index)
			return true
	return false


func _get_selected_base_definition_id() -> StringName:
	if (
		not is_instance_valid(_base_definition_option)
		or _base_definition_option.selected < 0
	):
		return &""
	return GFVariantData.to_string_name(
		GFItemListBinder.get_item_metadata(
			_base_definition_option,
			_base_definition_option.selected,
			&""
		)
	)


func _find_blueprint(blueprint_id: String) -> CustomTileBlueprintData:
	for blueprint: CustomTileBlueprintData in _blueprints:
		if blueprint.blueprint_id == blueprint_id:
			return blueprint
	return null


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
	_header.vertical = width < _ONE_COLUMN_BREAKPOINT
	_workspace.vertical = compact
	_blueprint_actions.vertical = width < 440.0
	_value_row.vertical = width < _ONE_COLUMN_BREAKPOINT
	_body_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO
		if compact
		else ScrollContainer.SCROLL_MODE_DISABLED
	)
	_body_scroll.follow_focus = compact
	_recipes_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
		if compact
		else ScrollContainer.SCROLL_MODE_AUTO
	)
	_recipes_scroll.follow_focus = not compact
	_recipes_scroll.custom_minimum_size.y = (
		0.0
		if compact
		else clampf(
			size.y - _DESKTOP_RECIPE_LIST_HEIGHT_BUDGET,
			_DESKTOP_RECIPE_LIST_MINIMUM_HEIGHT,
			_DESKTOP_RECIPE_LIST_MAXIMUM_HEIGHT
		)
	)
	_blueprint_pane.custom_minimum_size = (
		Vector2(0.0, 390.0) if compact else Vector2(420.0, 0.0)
	)
	var horizontal_margin: float = (
		8.0
		if compact
		else maxf((width - _DESKTOP_MAXIMUM_WIDTH) * 0.5, 24.0)
	)
	var vertical_margin: float = (
		8.0
		if compact
		else maxf((size.y - _DESKTOP_MAXIMUM_HEIGHT) * 0.5, 18.0)
	)
	var extra_margins: Dictionary = {
		"top": vertical_margin,
		"left": horizontal_margin,
		"bottom": vertical_margin,
		"right": horizontal_margin,
	}
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = (
			_viewport_utility.apply_display_safe_area_margins(
				_outer_margin,
				get_viewport(),
				extra_margins
			)
		)
	else:
		_outer_margin.add_theme_constant_override(
			"margin_left",
			roundi(horizontal_margin)
		)
		_outer_margin.add_theme_constant_override(
			"margin_right",
			roundi(horizontal_margin)
		)
		_outer_margin.add_theme_constant_override(
			"margin_top",
			roundi(vertical_margin)
		)
		_outer_margin.add_theme_constant_override(
			"margin_bottom",
			roundi(vertical_margin)
		)


func _close_dialog() -> void:
	var _closed: bool = _close_current_popup_route(ROUTE_ID)


func _show_operation_error(translation_key: StringName, error: Error) -> void:
	var fallback: String = (
		"保存失败，错误码：%d。"
		if translation_key == &"TILE_LAB_SAVE_FAILED"
		else "删除失败，错误码：%d。"
	)
	_status_label.text = _localized_format(
		String(translation_key),
		fallback,
		error
	)


func _begin_persistence_operation(
	action: StringName,
	resource_id: String,
	resource: Resource = null
) -> int:
	_persistence_operation_busy = true
	_persistence_operation_token += 1
	_pending_persistence_transaction_id = 0
	_pending_persistence_action = action
	_pending_persistence_resource_id = resource_id
	_pending_persistence_resource = resource
	_persistence_reconciliation_prompted = false
	_apply_persistence_control_state()
	return _persistence_operation_token


func _finish_persistence_operation(token: int) -> bool:
	if token != _persistence_operation_token or not is_inside_tree():
		return false
	_persistence_operation_busy = false
	_apply_persistence_control_state()
	return true


func _clear_persistence_tracking() -> void:
	_pending_persistence_transaction_id = 0
	_pending_persistence_action = &""
	_pending_persistence_resource_id = ""
	_pending_persistence_resource = null


func _apply_persistence_control_state() -> void:
	var blocked: bool = (
		_persistence_operation_busy
		or _persistence_outcome_unknown
	)
	_new_button.disabled = blocked
	_blueprint_option.disabled = blocked
	_base_definition_option.disabled = blocked
	_name_input.editable = not blocked
	_rebuild_recipe_buttons()
	_update_selection_validation()


func _await_persistence_operation(
	operation: GameSaveSectionOperation
) -> GameSaveSectionResult:
	if operation == null:
		return null
	var result: GameSaveSectionResult = operation.get_result()
	if result == null:
		result = await operation.completed
	return result


func _is_persistence_outcome_unknown(
	result: GameSaveSectionResult
) -> bool:
	if result == null:
		return false
	return result.get_status() in [
		GameSaveSectionResult.STATUS_OUTCOME_UNKNOWN,
		GameSaveSectionResult.STATUS_ROLLBACK_OUTCOME_UNKNOWN,
	]


func _show_persistence_outcome_unknown(
	result: GameSaveSectionResult
) -> void:
	if result == null:
		return
	_persistence_outcome_unknown = true
	_pending_persistence_transaction_id = result.get_transaction_id()
	_apply_persistence_control_state()
	var last_evidence: Dictionary = {}
	if is_instance_valid(_save_graph):
		last_evidence = _save_graph.get_last_section_reconciliation_evidence()
	if (
		GFVariantData.get_option_int(
			last_evidence,
			&"transaction_id",
			0
		)
		== _pending_persistence_transaction_id
	):
		await _on_section_reconciliation_settled(last_evidence)
	else:
		_status_label.text = tr("TILE_LAB_PERSISTENCE_OUTCOME_UNKNOWN")


func _localized_text(key: String, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == key else translated


func _localized_format(
	key: String,
	fallback: String,
	values: Variant
) -> String:
	return _localized_text(key, fallback) % values


func _reveal_simulation_result() -> void:
	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if is_instance_valid(motion):
		var _result_tween: Tween = motion.play_content_switch(_result_panel)


# --- 信号处理函数 ---

func _on_section_reconciliation_settled(evidence: Dictionary) -> void:
	if (
		not _persistence_outcome_unknown
		or _pending_persistence_transaction_id <= 0
		or GFVariantData.get_option_int(evidence, &"transaction_id", 0)
		!= _pending_persistence_transaction_id
	):
		return
	var operation_token: int = _persistence_operation_token
	var action: StringName = _pending_persistence_action
	var resource_id: String = _pending_persistence_resource_id
	var resource: Resource = _pending_persistence_resource
	var candidate_persisted: bool = GFVariantData.get_option_bool(
		evidence,
		&"candidate_persisted",
		false
	)
	var memory_rolled_back: bool = GFVariantData.get_option_bool(
		evidence,
		&"memory_rolled_back",
		false
	)
	_pending_persistence_transaction_id = 0
	_persistence_outcome_unknown = false
	_persistence_operation_busy = true
	var frame_wait: Dictionary = await GFAsyncWaitUtility.next_frame({
		"guard_node": self,
	})
	if not GFVariantData.get_option_bool(frame_wait, "completed", false):
		return
	if operation_token != _persistence_operation_token or not is_inside_tree():
		return
	var preferred_id: String = resource_id if memory_rolled_back else ""
	if (
		action == &"save"
		and candidate_persisted
		and resource is CustomTileBlueprintData
	):
		var saved_blueprint: CustomTileBlueprintData = resource
		preferred_id = saved_blueprint.blueprint_id
	_persistence_operation_busy = false
	_refresh_from_system(preferred_id)
	_clear_persistence_tracking()
	_apply_persistence_control_state()
	if not _persistence_reconciliation_prompted:
		_persistence_reconciliation_prompted = true
		_status_label.text = (
			tr("TILE_LAB_RECONCILIATION_SUCCEEDED")
			if candidate_persisted
			else tr("TILE_LAB_RECONCILIATION_ROLLED_BACK")
		)


func _on_blueprint_selected(index: int) -> void:
	if (
		_loading_ui
		or _persistence_operation_busy
		or _persistence_outcome_unknown
	):
		return
	var blueprint_id: String = GFVariantData.to_text(
		GFItemListBinder.get_item_metadata(
			_blueprint_option,
			index,
			""
		)
	)
	if blueprint_id.is_empty():
		_configure_new_blueprint()
		return
	var blueprint: CustomTileBlueprintData = _find_blueprint(blueprint_id)
	if blueprint != null:
		_apply_blueprint(blueprint)


func _on_base_definition_selected(_index: int) -> void:
	if (
		_loading_ui
		or _persistence_operation_busy
		or _persistence_outcome_unknown
	):
		return
	_selected_recipe_ids.clear()
	if is_instance_valid(_tile_lab):
		_selected_recipe_ids = _tile_lab.get_initial_recipe_ids(
			_get_selected_base_definition_id()
		)
	_rebuild_recipe_buttons()
	_update_selection_validation()


func _on_recipe_toggled(
	toggled_on: bool,
	recipe_id: StringName
) -> void:
	if (
		_loading_ui
		or _persistence_operation_busy
		or _persistence_outcome_unknown
	):
		return
	if toggled_on and not _selected_recipe_ids.has(recipe_id):
		_selected_recipe_ids.append(recipe_id)
	elif not toggled_on:
		_selected_recipe_ids.erase(recipe_id)
	_rebuild_recipe_buttons()
	_update_selection_validation()
	call_deferred(&"_focus_recipe_button", recipe_id)


func _on_edit_value_changed(_value: String) -> void:
	if (
		not _loading_ui
		and not _persistence_operation_busy
		and not _persistence_outcome_unknown
	):
		_update_selection_validation()


func _on_preview_value_changed(_value: float) -> void:
	if not _loading_ui:
		_status_label.text = ""


func _on_save_pressed() -> void:
	if _persistence_operation_busy or _persistence_outcome_unknown:
		return
	if not is_instance_valid(_tile_lab):
		_show_operation_error(&"TILE_LAB_SAVE_FAILED", ERR_UNCONFIGURED)
		return
	var blueprint: CustomTileBlueprintData = _make_edited_blueprint()
	var operation_token: int = _begin_persistence_operation(
		&"save",
		blueprint.blueprint_id,
		blueprint
	)
	var operation: GameSaveSectionOperation = (
		_tile_lab.request_save_blueprint(blueprint)
	)
	var result: GameSaveSectionResult = await _await_persistence_operation(
		operation
	)
	if not _finish_persistence_operation(operation_token):
		return
	if result == null:
		_clear_persistence_tracking()
		_show_operation_error(&"TILE_LAB_SAVE_FAILED", ERR_UNAVAILABLE)
		return
	if _is_persistence_outcome_unknown(result):
		await _show_persistence_outcome_unknown(result)
		return
	if not result.is_successful():
		_clear_persistence_tracking()
		_show_operation_error(
			&"TILE_LAB_SAVE_FAILED",
			result.get_error_code()
		)
		return
	_current_blueprint_id = blueprint.blueprint_id
	_refresh_from_system(blueprint.blueprint_id)
	_clear_persistence_tracking()
	_status_label.text = _localized_text(
		"TILE_LAB_SAVE_SUCCEEDED",
		"蓝图已保存。"
	)


func _on_delete_pressed() -> void:
	if _persistence_operation_busy or _persistence_outcome_unknown:
		return
	if _current_blueprint_id.is_empty():
		return
	var blueprint: CustomTileBlueprintData = _find_blueprint(
		_current_blueprint_id
	)
	var blueprint_id: String = _current_blueprint_id
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if not is_instance_valid(ui_router):
		return
	var config: GFModalConfig = GameUiRouterUtility.make_confirmation_modal_config(
		_localized_text("TILE_LAB_DELETE_CONFIRM_TITLE", "删除蓝图"),
		_localized_format(
			"TILE_LAB_DELETE_CONFIRM",
			"确定删除蓝图“%s”吗？",
			blueprint.display_name if blueprint != null else ""
		),
		_localized_text("TILE_LAB_DELETE", "删除"),
		tr("DELETE_CANCEL_ACTION")
	)
	var result: GFModalResult = await ui_router.show_modal_async(
		self,
		config,
		{
			&"source": &"tile_lab_delete",
			&"blueprint_id": blueprint_id,
		}
	)
	if (
		is_inside_tree()
		and result != null
		and result.status == GFModalResult.STATUS_CONFIRMED
	):
		await _on_delete_confirmed(blueprint_id)


func _on_delete_confirmed(blueprint_id: String = "") -> void:
	if _persistence_operation_busy or _persistence_outcome_unknown:
		return
	if not is_instance_valid(_tile_lab):
		_show_operation_error(&"TILE_LAB_DELETE_FAILED", ERR_UNCONFIGURED)
		return
	if blueprint_id.is_empty():
		blueprint_id = _current_blueprint_id
	var operation_token: int = _begin_persistence_operation(
		&"delete",
		blueprint_id
	)
	var operation: GameSaveSectionOperation = (
		_tile_lab.request_delete_blueprint(blueprint_id)
	)
	var result: GameSaveSectionResult = await _await_persistence_operation(
		operation
	)
	if not _finish_persistence_operation(operation_token):
		return
	if result == null:
		_clear_persistence_tracking()
		_show_operation_error(&"TILE_LAB_DELETE_FAILED", ERR_UNAVAILABLE)
		return
	if _is_persistence_outcome_unknown(result):
		await _show_persistence_outcome_unknown(result)
		return
	if not result.is_successful():
		_clear_persistence_tracking()
		_show_operation_error(
			&"TILE_LAB_DELETE_FAILED",
			result.get_error_code()
		)
		return
	_refresh_from_system()
	_clear_persistence_tracking()
	_status_label.text = _localized_text(
		"TILE_LAB_DELETE_SUCCEEDED",
		"蓝图已删除。"
	)


func _on_run_simulation_pressed() -> void:
	if not is_instance_valid(_tile_lab):
		_result_label.text = _localized_text(
			"TILE_LAB_UNAVAILABLE",
			"试验台系统不可用。"
		)
		_reveal_simulation_result()
		return
	var result: TileLabSimulationResult = _tile_lab.simulate_composition(
		_get_selected_base_definition_id(),
		_selected_recipe_ids,
		int(_left_value_spin.value),
		int(_right_value_spin.value)
	)
	if result == null or not result.is_valid_result():
		_result_label.text = _localized_format(
			"TILE_LAB_RESULT_INVALID",
			"无法运行：%s",
			result.validation_summary
			if result != null
			else _localized_text(
				"TILE_LAB_UNAVAILABLE",
				"试验台系统不可用。"
			)
		)
		_reveal_simulation_result()
		return
	if not result.did_interact():
		_result_label.text = _localized_format(
			"TILE_LAB_RESULT_NO_INTERACTION",
			"数值 %d 与 %d 没有产生交互。",
			[
				int(_left_value_spin.value),
				int(_right_value_spin.value),
			]
		)
		_reveal_simulation_result()
		return
	_result_label.text = _localized_format(
		"TILE_LAB_RESULT_INTERACTED",
		"%s方块保留，结果值 %d，得分 +%d。\n规则：%s",
		[
			_localized_text(
				"TILE_LAB_SURVIVOR_LEFT"
				if result.survivor_side == &"left"
				else "TILE_LAB_SURVIVOR_RIGHT",
				"左侧" if result.survivor_side == &"left" else "右侧"
			),
			result.result_value,
			result.score_delta,
			String(result.interaction_rule_id),
		]
	)
	_reveal_simulation_result()

func _on_blueprints_changed() -> void:
	if _persistence_operation_busy or _persistence_outcome_unknown:
		return
	var preferred_id: String = _current_blueprint_id
	_refresh_from_system(preferred_id)


func _on_visual_theme_changed(_theme: GameTheme) -> void:
	_apply_semantic_styles()
