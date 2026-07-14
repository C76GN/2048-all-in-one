@tool
extends Control


const REVIEW_CATALOG_PROVIDER_SCRIPT = preload(
	"res://scripts/assets/catalog/game_asset_review_catalog_source_provider.gd"
)
const REVIEW_RECORD_ROOT: String = "res://asset_library/review/records"
const STATUS_OPTIONS: Array[String] = [
	"inbox",
	"candidate",
	"approved",
	"rejected",
	"blocked_license",
	"archived",
]


var _records_by_asset_id: Dictionary = {}
var _filtered_records: Array[Resource] = []
var _selected_record: Resource = null
var _review_catalog: GFAssetCatalog = GFAssetCatalog.new()
var _ui_built: bool = false

var _search_input: LineEdit
var _status_filter: OptionButton
var _record_list: ItemList
var _title_label: Label
var _meta_label: RichTextLabel
var _preview_host: PanelContainer
var _status_editor: OptionButton
var _rating_editor: SpinBox
var _tags_editor: LineEdit
var _notes_editor: TextEdit
var _save_status_label: Label
var _audio_player: AudioStreamPlayer


func _ready() -> void:
	if _ui_built:
		return
	_build_ui()
	_load_records()
	_refresh_list()


func _build_ui() -> void:
	_ui_built = true
	anchors_preset = Control.PRESET_FULL_RECT

	var audio_player: AudioStreamPlayer = AudioStreamPlayer.new()
	audio_player.name = "PreviewAudioPlayer"
	add_child(audio_player)
	_audio_player = audio_player

	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(root_margin)

	var root_split: HSplitContainer = HSplitContainer.new()
	root_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_split.split_offset = 430
	root_margin.add_child(root_split)

	var left_panel: VBoxContainer = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(380, 0)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_split.add_child(left_panel)

	var heading: Label = Label.new()
	heading.text = "素材评审"
	heading.add_theme_font_size_override("font_size", 22)
	left_panel.add_child(heading)

	var search_input: LineEdit = LineEdit.new()
	search_input.placeholder_text = "搜索名称、路径、标签"
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.add_child(search_input)
	_search_input = search_input
	var _search_connect_result: Error = search_input.text_changed.connect(_on_filter_changed) as Error

	var status_filter: OptionButton = OptionButton.new()
	status_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_status_item(status_filter, "全部状态", "all")
	for status: String in STATUS_OPTIONS:
		_add_status_item(status_filter, status, status)
	left_panel.add_child(status_filter)
	_status_filter = status_filter
	var _filter_connect_result: Error = status_filter.item_selected.connect(_on_status_filter_selected) as Error

	var record_list: ItemList = ItemList.new()
	record_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	record_list.fixed_icon_size = Vector2i(0, 0)
	record_list.same_column_width = true
	left_panel.add_child(record_list)
	_record_list = record_list
	var _list_connect_result: Error = record_list.item_selected.connect(_on_record_selected) as Error

	var right_panel: VBoxContainer = VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(560, 0)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_split.add_child(right_panel)

	var title_label: Label = Label.new()
	title_label.text = "选择一个素材"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_panel.add_child(title_label)
	_title_label = title_label

	var meta_label: RichTextLabel = RichTextLabel.new()
	meta_label.fit_content = true
	meta_label.scroll_active = false
	meta_label.bbcode_enabled = true
	meta_label.custom_minimum_size = Vector2(0, 110)
	right_panel.add_child(meta_label)
	_meta_label = meta_label

	var preview_host: PanelContainer = PanelContainer.new()
	preview_host.custom_minimum_size = Vector2(0, 220)
	preview_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_child(preview_host)
	_preview_host = preview_host

	var preview_placeholder: Label = Label.new()
	preview_placeholder.text = "预览区域"
	preview_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_placeholder.custom_minimum_size = Vector2(0, 220)
	preview_host.add_child(preview_placeholder)

	var action_row: HBoxContainer = HBoxContainer.new()
	right_panel.add_child(action_row)
	_add_button(action_row, "播放", _on_play_pressed)
	_add_button(action_row, "停止", _on_stop_pressed)
	_add_button(action_row, "候选", _on_candidate_pressed)
	_add_button(action_row, "批准", _on_approved_pressed)
	_add_button(action_row, "拒绝", _on_rejected_pressed)

	var form_grid: GridContainer = GridContainer.new()
	form_grid.columns = 2
	form_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_child(form_grid)

	_add_form_label(form_grid, "状态")
	var status_editor: OptionButton = OptionButton.new()
	status_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for status: String in STATUS_OPTIONS:
		_add_status_item(status_editor, status, status)
	form_grid.add_child(status_editor)
	_status_editor = status_editor

	_add_form_label(form_grid, "评分")
	var rating_editor: SpinBox = SpinBox.new()
	rating_editor.min_value = 0
	rating_editor.max_value = 5
	rating_editor.step = 1
	rating_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_grid.add_child(rating_editor)
	_rating_editor = rating_editor

	_add_form_label(form_grid, "标签")
	var tags_editor: LineEdit = LineEdit.new()
	tags_editor.placeholder_text = "用逗号分隔"
	tags_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_grid.add_child(tags_editor)
	_tags_editor = tags_editor

	var notes_label: Label = Label.new()
	notes_label.text = "备注"
	notes_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	form_grid.add_child(notes_label)
	var notes_editor: TextEdit = TextEdit.new()
	notes_editor.custom_minimum_size = Vector2(0, 130)
	notes_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_grid.add_child(notes_editor)
	_notes_editor = notes_editor

	var bottom_row: HBoxContainer = HBoxContainer.new()
	right_panel.add_child(bottom_row)
	_add_button(bottom_row, "保存评审", _on_save_pressed)
	var save_status_label: Label = Label.new()
	save_status_label.text = ""
	save_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(save_status_label)
	_save_status_label = save_status_label


func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(92, 36)
	parent.add_child(button)
	var _connect_result: Error = button.pressed.connect(callback) as Error


func _add_form_label(parent: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(72, 0)
	parent.add_child(label)


func _add_status_item(option: OptionButton, label: String, status: String) -> void:
	var index: int = option.item_count
	option.add_item(label)
	option.set_item_metadata(index, status)


func _load_records() -> void:
	_records_by_asset_id.clear()
	_review_catalog = GFAssetCatalog.new()
	var provider: GameAssetReviewCatalogSourceProvider = REVIEW_CATALOG_PROVIDER_SCRIPT.new()
	var _configured: GFAssetCatalogSourceProvider = provider.configure_review_records(
		REVIEW_RECORD_ROOT,
		&"asset_review"
	)
	_review_catalog = provider.build_catalog()
	for asset_id: String in _review_catalog.get_all_ids():
		var entry: GFAssetCatalogEntry = _review_catalog.get_entry(StringName(asset_id))
		if entry == null:
			continue
		var record_path: String = GFVariantData.get_option_string(entry.metadata, "record_path")
		var loaded: Resource = ResourceLoader.load(record_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if loaded == null:
			continue
		_records_by_asset_id[asset_id] = loaded


func _refresh_list() -> void:
	_filtered_records.clear()
	_record_list.clear()
	var query: String = _search_input.text.strip_edges()
	var status_filter: String = _get_selected_option_metadata(_status_filter, "all")
	var candidate_ids: PackedStringArray = _get_search_candidate_ids(query)
	var status_ids: PackedStringArray = PackedStringArray()
	if status_filter != "all":
		status_ids = _review_catalog.query(
			GFAssetCatalog.GROUP_SOURCE_TAGS,
			"status:%s" % status_filter
		)
	for asset_id: String in candidate_ids:
		if status_filter != "all" and not status_ids.has(asset_id):
			continue
		var record_value: Variant = GFVariantData.get_option_value(_records_by_asset_id, asset_id)
		if not (record_value is Resource):
			continue
		var record: Resource = record_value
		_append_resource(_filtered_records, record)
		var item_index: int = _record_list.item_count
		var _add_item_result: int = _record_list.add_item(_make_record_list_text(record))
		_record_list.set_item_metadata(item_index, _filtered_records.size() - 1)
	_update_empty_state()


func _get_search_candidate_ids(query: String) -> PackedStringArray:
	if query.is_empty():
		return _review_catalog.get_all_ids()
	var result: PackedStringArray = PackedStringArray()
	for search_value: Variant in _review_catalog.search(query):
		if not (search_value is Dictionary):
			continue
		var search_report: Dictionary = search_value
		var candidate: Dictionary = GFVariantData.get_option_dictionary(search_report, "candidate")
		var asset_id: String = GFVariantData.get_option_string(candidate, "asset_id")
		if not asset_id.is_empty() and not result.has(asset_id):
			var _appended: bool = result.append(asset_id)
	return result


func _make_record_list_text(record: Resource) -> String:
	return "%s  |  %s  |  %s" % [
		_get_resource_string(record, "review_status"),
		_get_resource_string(record, "display_name"),
		_get_resource_string(record, "asset_kind"),
	]


func _update_empty_state() -> void:
	if _filtered_records.is_empty():
		_title_label.text = "没有匹配的素材"
		_meta_label.text = ""


func _show_record(record: Resource) -> void:
	_selected_record = record
	_title_label.text = _get_resource_string(record, "display_name", "未命名素材")
	_meta_label.text = _format_record_meta(record)
	_set_status_editor_value(_get_resource_string(record, "review_status", "inbox"))
	_rating_editor.value = _get_resource_int(record, "rating")
	_tags_editor.text = ", ".join(_get_resource_packed_string_array(record, "tags"))
	_notes_editor.text = _get_resource_string(record, "notes")
	_save_status_label.text = ""
	_refresh_preview(record)


func _format_record_meta(record: Resource) -> String:
	return (
		"[b]路径[/b] %s\n[b]来源[/b] %s\n[b]授权[/b] %s / %s\n[b]用途建议[/b] %s"
		% [
			_get_resource_string(record, "library_path"),
			_get_resource_string(record, "source_pack_id"),
			_get_resource_string(record, "license_status"),
			_get_resource_string(record, "license"),
			", ".join(_get_resource_packed_string_array(record, "suggested_slots")),
		]
	)


func _refresh_preview(record: Resource) -> void:
	_clear_preview()
	var kind: String = _get_resource_string(record, "asset_kind")
	var path: String = _get_resource_string(record, "library_path")
	if kind == "audio":
		_set_preview_label("音频素材：点击“播放”试听。")
	elif kind == "shader":
		_show_shader_preview(path)
	elif kind == "texture":
		_show_texture_preview(path)
	else:
		_set_preview_label("这个格式暂不支持直接预览。")


func _show_shader_preview(path: String) -> void:
	var loaded: Resource = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_REUSE)
	if not (loaded is Shader):
		_set_preview_label("Shader 无法加载。")
		return
	var shader: Shader = loaded
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = shader
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(0.8, 0.8, 0.8, 1.0)
	rect.material = shader_material
	rect.custom_minimum_size = Vector2(0, 220)
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_host.add_child(rect)


func _show_texture_preview(path: String) -> void:
	var loaded: Resource = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
	if not (loaded is Texture2D):
		_set_preview_label("图片无法加载。")
		return
	var texture: Texture2D = loaded
	var texture_rect: TextureRect = TextureRect.new()
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = Vector2(0, 220)
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_host.add_child(texture_rect)


func _set_preview_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 220)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_host.add_child(label)


func _clear_preview() -> void:
	for child: Node in _preview_host.get_children():
		_preview_host.remove_child(child)
		child.queue_free()


func _play_selected_audio() -> void:
	if _selected_record == null:
		return
	if _get_resource_string(_selected_record, "asset_kind") != "audio":
		_save_status_label.text = "当前素材不是音频。"
		return
	var path: String = _get_resource_string(_selected_record, "library_path")
	var loaded: Resource = ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_REUSE)
	if not (loaded is AudioStream):
		_save_status_label.text = "这个音频格式暂不能播放。"
		return
	var stream: AudioStream = loaded
	_audio_player.stop()
	_audio_player.stream = stream
	_audio_player.play()
	_save_status_label.text = "正在播放。"


func _save_selected_record() -> void:
	if _selected_record == null:
		return
	_selected_record.set("review_status", StringName(_get_selected_option_metadata(_status_editor, "inbox")))
	_selected_record.set("rating", int(_rating_editor.value))
	_selected_record.set("tags", _parse_tags(_tags_editor.text))
	_selected_record.set("notes", _notes_editor.text)
	_selected_record.set("reviewed_at", Time.get_datetime_string_from_system(false, true))
	var path: String = _selected_record.resource_path
	if path.is_empty():
		_save_status_label.text = "保存失败：记录没有 resource_path。"
		return
	var save_result: Error = ResourceSaver.save(_selected_record, path)
	if save_result != OK:
		_save_status_label.text = "保存失败：%d" % save_result
		return
	var selected_asset_id: String = _get_resource_string(_selected_record, "asset_id")
	_load_records()
	var reloaded_value: Variant = GFVariantData.get_option_value(_records_by_asset_id, selected_asset_id)
	if reloaded_value is Resource:
		_selected_record = reloaded_value
	_save_status_label.text = "已保存。"
	_refresh_list()


func _set_selected_status(status: String) -> void:
	if _selected_record == null:
		return
	_set_status_editor_value(status)
	_save_selected_record()


func _set_status_editor_value(status: String) -> void:
	for index: int in range(_status_editor.item_count):
		if GFVariantData.to_text(_status_editor.get_item_metadata(index)) == status:
			_status_editor.select(index)
			return
	_status_editor.select(0)


func _parse_tags(text: String) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	for raw_part: String in text.replace("，", ",").split(",", false):
		var tag: String = raw_part.strip_edges().to_lower()
		if not tag.is_empty() and not tags.has(tag):
			var _append_result: bool = tags.append(tag)
	return tags


func _get_selected_option_metadata(option: OptionButton, fallback: String) -> String:
	var selected_index: int = option.selected
	if selected_index < 0 or selected_index >= option.item_count:
		return fallback
	return GFVariantData.to_text(option.get_item_metadata(selected_index), fallback)


func _append_resource(target: Array[Resource], value: Resource) -> void:
	target.append(value)


func _get_resource_string(resource: Resource, property_name: String, fallback: String = "") -> String:
	if resource == null:
		return fallback
	var value: Variant = resource.get(property_name)
	return GFVariantData.to_text(value, fallback)


func _get_resource_int(resource: Resource, property_name: String, fallback: int = 0) -> int:
	if resource == null:
		return fallback
	var value: Variant = resource.get(property_name)
	return GFVariantData.to_int(value, fallback)


func _get_resource_packed_string_array(resource: Resource, property_name: String) -> PackedStringArray:
	if resource == null:
		return PackedStringArray()
	var value: Variant = resource.get(property_name)
	return GFVariantData.get_option_packed_string_array({ "value": value }, "value")


func _on_filter_changed(_text: String) -> void:
	_refresh_list()


func _on_status_filter_selected(_index: int) -> void:
	_refresh_list()


func _on_record_selected(index: int) -> void:
	var metadata: Variant = _record_list.get_item_metadata(index)
	var record_index: int = GFVariantData.to_int(metadata, -1)
	if record_index < 0 or record_index >= _filtered_records.size():
		return
	_show_record(_filtered_records[record_index])


func _on_play_pressed() -> void:
	_play_selected_audio()


func _on_stop_pressed() -> void:
	_audio_player.stop()
	_save_status_label.text = "已停止。"


func _on_candidate_pressed() -> void:
	_set_selected_status("candidate")


func _on_approved_pressed() -> void:
	_set_selected_status("approved")


func _on_rejected_pressed() -> void:
	_set_selected_status("rejected")


func _on_save_pressed() -> void:
	_save_selected_record()
