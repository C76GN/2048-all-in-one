## ImportAssetSources: 把外部素材包导入项目素材评审库。
class_name ImportAssetSources
extends SceneTree


# --- 常量 ---

const CONFIG_PATH: String = "res://features/asset_library/resources/import_sources.json"
const SOURCE_PACK_ROOT: String = "res://features/asset_library/resources/source_packs"
const REVIEW_ROOT: String = "res://features/asset_library/resources/review"
const REVIEW_RECORD_ROOT: String = "res://features/asset_library/resources/review/records"
const SOURCE_PACK_RESOURCE_ROOT: String = "res://features/asset_library/resources/review/source_packs"
const SLOT_MAP_PATH: String = "res://features/asset_library/resources/review/asset_slot_map.tres"
const REPORT_JSON_PATH: String = "res://features/asset_library/resources/reports/source_import_report.json"
const REPORT_MARKDOWN_PATH: String = "res://features/asset_library/resources/reports/source_import_report.md"
const COPY_BUFFER_SIZE: int = 1_048_576
const MAX_SOURCE_FILE_COUNT: int = 100000
const ASSET_REVIEW_RECORD_SCRIPT = preload("res://features/asset_library/scripts/data/asset_review_record.gd")
const ASSET_SOURCE_PACK_SCRIPT = preload("res://features/asset_library/scripts/data/asset_source_pack.gd")
const ASSET_SLOT_BINDING_SCRIPT = preload("res://features/asset_library/scripts/data/asset_slot_binding.gd")
const ASSET_SLOT_MAP_SCRIPT = preload("res://features/asset_library/scripts/data/asset_slot_map.gd")

const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3", "opus", "m4a"]
const SHADER_EXTENSIONS: Array[String] = ["gdshader", "shader"]
const TEXTURE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg"]
const VFX_EXTENSIONS: Array[String] = ["tres", "tscn"]
const REVIEW_EXTENSIONS: Array[String] = [
	"gdshader",
	"jpeg",
	"jpg",
	"m4a",
	"mp3",
	"ogg",
	"opus",
	"png",
	"shader",
	"svg",
	"tres",
	"tscn",
	"wav",
	"webp",
]
const REVIEW_RECORD_PERSISTED_PROPERTIES: Array[String] = [
	"asset_id",
	"source_pack_id",
	"display_name",
	"asset_kind",
	"review_status",
	"tags",
	"notes",
	"rating",
	"source_path",
	"library_path",
	"relative_path",
	"extension",
	"file_size_bytes",
	"sha256",
	"author",
	"license",
	"source_url",
	"license_status",
	"preview_supported",
	"suggested_slots",
	"imported_at",
	"reviewed_at",
]
const SOURCE_PACK_PERSISTED_PROPERTIES: Array[String] = [
	"source_pack_id",
	"display_name",
	"original_source_path",
	"library_root_path",
	"author",
	"license",
	"source_url",
	"license_status",
	"imported_at",
	"file_count",
	"review_record_count",
	"byte_count",
	"tags",
	"notes",
]
const STATUS_INBOX: StringName = &"inbox"
const STATUS_APPROVED: StringName = &"approved"
const KIND_AUDIO: StringName = &"audio"
const KIND_SHADER: StringName = &"shader"
const KIND_TEXTURE: StringName = &"texture"
const KIND_VFX: StringName = &"vfx"
const KIND_OTHER: StringName = &"other"


# --- Godot 生命周期方法 ---

func _init() -> void:
	print("Importing asset source packs...")
	var report: Dictionary = run_import()
	var ok: bool = GFVariantData.get_option_int(report, "error_count", 0) == 0
	var summary_prefix: String = "Asset source import:" if ok else "Asset source import failed:"
	print("%s %d packs, %d files, %d review records, %d copied, %d issues" % [
		summary_prefix,
		GFVariantData.get_option_int(report, "source_pack_count"),
		GFVariantData.get_option_int(report, "file_count"),
		GFVariantData.get_option_int(report, "review_record_count"),
		GFVariantData.get_option_int(report, "copied_count"),
		GFVariantData.get_option_int(report, "issue_count"),
	])
	quit(0 if ok else 1)


# --- 公共方法 ---

func run_import() -> Dictionary:
	var report: Dictionary = _make_report()
	var config: Dictionary = _read_json(CONFIG_PATH)
	if config.is_empty():
		_add_issue(report, "error", "missing_config", "Asset import config could not be loaded.", {
			"path": CONFIG_PATH,
		})
		_finalize_report(report)
		_write_reports(report)
		return report

	var ensure_roots_error: Error = _ensure_asset_library_roots()
	if ensure_roots_error != OK:
		_add_issue(report, "error", "root_directory_error", "Asset review directories could not be created.", {
			"error": ensure_roots_error,
		})
		_finalize_report(report)
		_write_reports(report)
		return report

	var source_packs: Array = GFVariantData.get_option_array(config, "source_packs")
	report["source_pack_count"] = source_packs.size()
	for source_pack_value: Variant in source_packs:
		var source_pack_config: Dictionary = GFVariantData.as_dictionary(source_pack_value)
		_import_source_pack(source_pack_config, report)

	_ensure_slot_map(report)
	_finalize_report(report)
	_write_reports(report)
	return report


# --- 私有/辅助方法 ---

func _ensure_asset_library_roots() -> Error:
	for path: String in [
		SOURCE_PACK_ROOT,
		REVIEW_ROOT,
		REVIEW_RECORD_ROOT,
		SOURCE_PACK_RESOURCE_ROOT,
		REPORT_JSON_PATH.get_base_dir(),
	]:
		var result: Error = _ensure_dir(path)
		if result != OK:
			return result
	return OK


func _import_source_pack(source_pack_config: Dictionary, report: Dictionary) -> void:
	var pack_id: String = GFVariantData.get_option_string(source_pack_config, "source_pack_id")
	var source_path: String = _normalize_path(GFVariantData.get_option_string(source_pack_config, "source_path"))
	if pack_id.is_empty() or source_path.is_empty():
		_add_issue(report, "error", "invalid_source_pack", "Source pack is missing source_pack_id or source_path.", source_pack_config)
		return
	if not DirAccess.dir_exists_absolute(source_path):
		_add_issue(report, "error", "missing_source_pack", "Source pack directory does not exist.", {
			"source_pack_id": pack_id,
			"source_path": source_path,
		})
		return

	var imported_at: String = _get_existing_source_pack_imported_at(pack_id)
	if imported_at.is_empty():
		imported_at = Time.get_datetime_string_from_system(false, true)
	var target_root: String = SOURCE_PACK_ROOT.path_join(pack_id).path_join("files")
	var records_root: String = REVIEW_RECORD_ROOT.path_join(pack_id)
	var ensure_target_error: Error = _ensure_dir(target_root)
	var ensure_records_error: Error = _ensure_dir(records_root)
	if ensure_target_error != OK or ensure_records_error != OK:
		_add_issue(report, "error", "source_pack_target_error", "Source pack target directories could not be created.", {
			"source_pack_id": pack_id,
			"target_error": ensure_target_error,
			"records_error": ensure_records_error,
		})
		return

	var source_scan_report: Dictionary = _scan_all_files(source_path)
	var source_files: PackedStringArray = GFVariantData.get_option_packed_string_array(
		source_scan_report,
		"paths"
	)
	var pack_report: Dictionary = _make_pack_report(pack_id, source_pack_config, source_files.size())
	pack_report["source_scan_report"] = _summarize_path_scan_report(source_scan_report)
	if (
		not GFVariantData.get_option_bool(source_scan_report, "ok")
		or GFVariantData.get_option_bool(source_scan_report, "truncated")
	):
		_add_issue(report, "error", "partial_source_scan", "GF source-pack enumeration did not complete.", {
			"source_pack_id": pack_id,
			"source_path": source_path,
			"scan_report": _summarize_path_scan_report(source_scan_report),
		})
		_accumulate_pack_report(report, pack_report)
		return
	var audio_entry_lookup: Dictionary = _collect_audio_entry_lookup(source_path)
	var total_bytes: int = 0
	for source_file: String in source_files:
		var relative_path: String = _make_relative_path(source_file, source_path)
		var target_path: String = target_root.path_join(relative_path)
		var file_size: int = _get_file_size(source_file)
		var sha256: String = FileAccess.get_sha256(source_file)
		total_bytes += file_size
		_import_file(
			source_pack_config,
			source_file,
			target_path,
			relative_path,
			file_size,
			sha256,
			imported_at,
			audio_entry_lookup,
			pack_report,
			report
		)

	pack_report["byte_count"] = total_bytes
	_save_source_pack_resource(source_pack_config, imported_at, pack_report, report)
	_write_source_pack_manifest(source_pack_config, imported_at, pack_report, report)
	_accumulate_pack_report(report, pack_report)


func _import_file(
	source_pack_config: Dictionary,
	source_file: String,
	target_path: String,
	relative_path: String,
	file_size: int,
	sha256: String,
	imported_at: String,
	audio_entry_lookup: Dictionary,
	pack_report: Dictionary,
	report: Dictionary
) -> void:
	var copy_result: String = _copy_file_if_changed(source_file, target_path, sha256)
	if copy_result == "copied":
		pack_report["copied_count"] = GFVariantData.get_option_int(pack_report, "copied_count") + 1
	elif copy_result == "unchanged":
		pack_report["unchanged_count"] = GFVariantData.get_option_int(pack_report, "unchanged_count") + 1
	else:
		pack_report["error_count"] = GFVariantData.get_option_int(pack_report, "error_count") + 1
		_add_issue(report, "error", "copy_failed", "Source asset copy failed.", {
			"source_path": source_file,
			"target_path": target_path,
			"reason": copy_result,
		})
		return

	var extension: String = source_file.get_extension().to_lower()
	if not REVIEW_EXTENSIONS.has(extension):
		pack_report["non_review_file_count"] = GFVariantData.get_option_int(pack_report, "non_review_file_count") + 1
		return

	var record_path: String = _make_record_resource_path(
		GFVariantData.get_option_string(source_pack_config, "source_pack_id"),
		relative_path,
		sha256
	)
	var existing_record: Resource = _load_review_record(record_path)
	var record: Resource = _make_review_record(
		source_pack_config,
		source_file,
		target_path,
		relative_path,
		file_size,
		sha256,
		imported_at,
		audio_entry_lookup,
		existing_record
	)
	if not _resources_match(existing_record, record, REVIEW_RECORD_PERSISTED_PROPERTIES):
		var save_result: Error = ResourceSaver.save(record, record_path)
		if save_result != OK:
			_add_issue(report, "error", "record_save_failed", "Review record could not be saved.", {
				"path": record_path,
				"error": save_result,
			})
			return
	pack_report["review_record_count"] = GFVariantData.get_option_int(pack_report, "review_record_count") + 1
	_increment_nested_count(pack_report, "kind_counts", _get_resource_string(record, "asset_kind"))
	_increment_nested_count(pack_report, "status_counts", _get_resource_string(record, "review_status"))
	_increment_nested_count(pack_report, "license_counts", _get_resource_string(record, "license_status"))


func _make_review_record(
	source_pack_config: Dictionary,
	source_file: String,
	target_path: String,
	relative_path: String,
	file_size: int,
	sha256: String,
	imported_at: String,
	audio_entry_lookup: Dictionary,
	existing_record: Resource
) -> Resource:
	var pack_id: String = GFVariantData.get_option_string(source_pack_config, "source_pack_id")
	var extension: String = source_file.get_extension().to_lower()
	var inferred_kind: StringName = _infer_asset_kind(extension)
	var record: Resource = ASSET_REVIEW_RECORD_SCRIPT.new()

	record.set("asset_id", StringName(_make_asset_id(pack_id, relative_path, sha256)))
	record.set("source_pack_id", StringName(pack_id))
	record.set("display_name", _make_display_name(source_file, relative_path, audio_entry_lookup))
	record.set("asset_kind", inferred_kind)
	record.set("review_status", STATUS_INBOX)
	record.set("tags", _make_record_tags(source_pack_config, relative_path, inferred_kind, existing_record))
	record.set("notes", "")
	record.set("rating", 0)
	record.set("source_path", source_file)
	record.set("library_path", target_path)
	record.set("relative_path", relative_path)
	record.set("extension", extension)
	record.set("file_size_bytes", file_size)
	record.set("sha256", sha256)
	record.set("author", GFVariantData.get_option_string(source_pack_config, "author"))
	record.set("license", GFVariantData.get_option_string(source_pack_config, "license"))
	record.set("source_url", GFVariantData.get_option_string(source_pack_config, "source_url"))
	record.set("license_status", StringName(GFVariantData.get_option_string(source_pack_config, "license_status", "unknown")))
	record.set("preview_supported", _is_preview_supported(extension))
	record.set("suggested_slots", _make_suggested_slots(relative_path, inferred_kind, existing_record))
	record.set("imported_at", imported_at)
	record.set("reviewed_at", "")

	if existing_record != null:
		record.set("review_status", _get_resource_string_name(existing_record, "review_status", STATUS_INBOX))
		record.set("notes", _get_resource_string(existing_record, "notes"))
		record.set("rating", _get_resource_int(existing_record, "rating"))
		record.set("reviewed_at", _get_resource_string(existing_record, "reviewed_at"))
		var previous_imported_at: String = _get_resource_string(existing_record, "imported_at")
		if not previous_imported_at.is_empty():
			record.set("imported_at", previous_imported_at)
	return record


func _load_review_record(record_path: String) -> Resource:
	if not FileAccess.file_exists(record_path):
		return null
	var loaded: Resource = ResourceLoader.load(record_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if _resource_uses_script(loaded, ASSET_REVIEW_RECORD_SCRIPT):
		return loaded
	return null


func _save_source_pack_resource(
	source_pack_config: Dictionary,
	imported_at: String,
	pack_report: Dictionary,
	report: Dictionary
) -> void:
	var pack_id: String = GFVariantData.get_option_string(source_pack_config, "source_pack_id")
	var resource: Resource = ASSET_SOURCE_PACK_SCRIPT.new()
	resource.set("source_pack_id", StringName(pack_id))
	resource.set("display_name", GFVariantData.get_option_string(source_pack_config, "display_name", pack_id))
	resource.set("original_source_path", _normalize_path(GFVariantData.get_option_string(source_pack_config, "source_path")))
	resource.set("library_root_path", SOURCE_PACK_ROOT.path_join(pack_id))
	resource.set("author", GFVariantData.get_option_string(source_pack_config, "author"))
	resource.set("license", GFVariantData.get_option_string(source_pack_config, "license"))
	resource.set("source_url", GFVariantData.get_option_string(source_pack_config, "source_url"))
	resource.set("license_status", StringName(GFVariantData.get_option_string(source_pack_config, "license_status", "unknown")))
	resource.set("imported_at", imported_at)
	resource.set("file_count", GFVariantData.get_option_int(pack_report, "file_count"))
	resource.set("review_record_count", GFVariantData.get_option_int(pack_report, "review_record_count"))
	resource.set("byte_count", GFVariantData.get_option_int(pack_report, "byte_count"))
	resource.set("tags", GFVariantData.get_option_packed_string_array(source_pack_config, "tags"))
	resource.set("notes", GFVariantData.get_option_string(source_pack_config, "notes"))

	var save_path: String = SOURCE_PACK_RESOURCE_ROOT.path_join("%s.tres" % pack_id)
	var existing_resource: Resource = _load_source_pack_resource(save_path)
	if _resources_match(existing_resource, resource, SOURCE_PACK_PERSISTED_PROPERTIES):
		return
	var save_result: Error = ResourceSaver.save(resource, save_path)
	if save_result != OK:
		_add_issue(report, "error", "source_pack_resource_save_failed", "Source pack resource could not be saved.", {
			"path": save_path,
			"error": save_result,
		})


func _write_source_pack_manifest(
	source_pack_config: Dictionary,
	imported_at: String,
	pack_report: Dictionary,
	report: Dictionary
) -> void:
	var pack_id: String = GFVariantData.get_option_string(source_pack_config, "source_pack_id")
	var manifest_path: String = SOURCE_PACK_ROOT.path_join(pack_id).path_join("source_pack_manifest.json")
	var manifest: Dictionary = {
		"schema_version": 1,
		"source_pack_id": pack_id,
		"display_name": GFVariantData.get_option_string(source_pack_config, "display_name", pack_id),
		"original_source_path": _normalize_path(GFVariantData.get_option_string(source_pack_config, "source_path")),
		"author": GFVariantData.get_option_string(source_pack_config, "author"),
		"license": GFVariantData.get_option_string(source_pack_config, "license"),
		"license_status": GFVariantData.get_option_string(source_pack_config, "license_status", "unknown"),
		"source_url": GFVariantData.get_option_string(source_pack_config, "source_url"),
		"imported_at": imported_at,
		"report": pack_report,
	}
	var write_error: Error = _write_text_if_changed(manifest_path, JSON.stringify(manifest, "\t"))
	if write_error != OK:
		_add_issue(report, "error", "source_pack_manifest_write_failed", "Source pack manifest could not be written.", {
			"path": manifest_path,
			"error": write_error,
		})


func _ensure_slot_map(report: Dictionary) -> void:
	var slot_map: Resource = _load_slot_map()
	var changed: bool = false
	for slot_definition: Dictionary in _get_default_slot_definitions():
		var slot_id: StringName = StringName(GFVariantData.get_option_string(slot_definition, "slot_id"))
		if _find_slot_binding(slot_map, slot_id) != null:
			continue
		_upsert_slot_binding(slot_map, _make_slot_binding(slot_definition))
		changed = true
	if changed:
		slot_map.set("updated_at", Time.get_datetime_string_from_system(false, true))
		var save_result: Error = ResourceSaver.save(slot_map, SLOT_MAP_PATH)
		if save_result != OK:
			_add_issue(report, "error", "slot_map_save_failed", "Asset slot map could not be saved.", {
				"path": SLOT_MAP_PATH,
				"error": save_result,
			})
	report["slot_count"] = _get_slot_bindings(slot_map).size()
	report["bound_slot_count"] = _get_bound_slot_count(slot_map)


func _load_slot_map() -> Resource:
	if not FileAccess.file_exists(SLOT_MAP_PATH):
		return ASSET_SLOT_MAP_SCRIPT.new()
	var loaded: Resource = ResourceLoader.load(SLOT_MAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if _resource_uses_script(loaded, ASSET_SLOT_MAP_SCRIPT):
		return loaded
	return ASSET_SLOT_MAP_SCRIPT.new()


func _make_slot_binding(slot_definition: Dictionary) -> Resource:
	var binding: Resource = ASSET_SLOT_BINDING_SCRIPT.new()
	var current_asset_key: StringName = StringName(GFVariantData.get_option_string(slot_definition, "current_asset_key"))
	binding.set("slot_id", StringName(GFVariantData.get_option_string(slot_definition, "slot_id")))
	binding.set("display_name", GFVariantData.get_option_string(slot_definition, "display_name"))
	binding.set("expected_kind", StringName(GFVariantData.get_option_string(slot_definition, "expected_kind", "other")))
	binding.set("current_asset_key", current_asset_key)
	binding.set("current_library_path", GFVariantData.get_option_string(slot_definition, "current_library_path"))
	binding.set("fallback_asset_key", current_asset_key)
	binding.set("tags", GFVariantData.get_option_packed_string_array(slot_definition, "tags"))
	binding.set("notes", GFVariantData.get_option_string(slot_definition, "notes"))
	return binding


func _get_default_slot_definitions() -> Array[Dictionary]:
	return [
		{
			"slot_id": "slot.audio.ui.select",
			"display_name": "UI Select",
			"expected_kind": "audio",
			"current_asset_key": "asset.audio.ui.printworks.select_soft_01",
			"current_library_path": "res://features/asset_library/resources/audio/ui/printworks_select_soft_01.ogg",
			"tags": PackedStringArray(["audio", "ui", "select"]),
			"notes": "Default menu focus or hover sound.",
		},
		{
			"slot_id": "slot.audio.ui.confirm",
			"display_name": "UI Confirm",
			"expected_kind": "audio",
			"current_asset_key": "asset.audio.ui.printworks.confirm_soft_01",
			"current_library_path": "res://features/asset_library/resources/audio/ui/printworks_confirm_soft_01.ogg",
			"tags": PackedStringArray(["audio", "ui", "confirm"]),
			"notes": "Default menu activation sound.",
		},
		{
			"slot_id": "slot.audio.tile.spawn",
			"display_name": "Tile Spawn",
			"expected_kind": "audio",
			"current_asset_key": "asset.audio.tile.printworks.spawn_soft_01",
			"current_library_path": "res://features/asset_library/resources/audio/tile/printworks_spawn_soft_01.ogg",
			"tags": PackedStringArray(["audio", "tile", "spawn"]),
			"notes": "Default tile creation sound.",
		},
		{
			"slot_id": "slot.audio.tile.move",
			"display_name": "Tile Move",
			"expected_kind": "audio",
			"current_asset_key": "asset.audio.tile.printworks.move_soft_01",
			"current_library_path": "res://features/asset_library/resources/audio/tile/printworks_move_soft_01.ogg",
			"tags": PackedStringArray(["audio", "tile", "move"]),
			"notes": "Default tile slide sound.",
		},
		{
			"slot_id": "slot.audio.tile.merge",
			"display_name": "Tile Merge",
			"expected_kind": "audio",
			"current_asset_key": "asset.audio.tile.printworks.merge_soft_01",
			"current_library_path": "res://features/asset_library/resources/audio/tile/printworks_merge_soft_01.ogg",
			"tags": PackedStringArray(["audio", "tile", "merge"]),
			"notes": "Default tile merge sound.",
		},
		{
			"slot_id": "slot.audio.game.over",
			"display_name": "Game Over",
			"expected_kind": "audio",
			"current_asset_key": "asset.audio.game.printworks.game_over_soft_01",
			"current_library_path": "res://features/asset_library/resources/audio/game/printworks_game_over_soft_01.ogg",
			"tags": PackedStringArray(["audio", "game", "over"]),
			"notes": "Default game over sound.",
		},
		{
			"slot_id": "slot.shader.background.main",
			"display_name": "Main Background Shader",
			"expected_kind": "shader",
			"current_asset_key": "asset.shader.background.halftone_paper",
			"current_library_path": "res://features/asset_library/resources/shaders/background/halftone_paper_background.gdshader",
			"tags": PackedStringArray(["shader", "background"]),
			"notes": "Default printworks background shader.",
		},
		{
			"slot_id": "slot.shader.transition.scene_wipe",
			"display_name": "Scene Wipe Transition",
			"expected_kind": "shader",
			"current_asset_key": "asset.shader.transition.halftone_wipe",
			"current_library_path": "res://features/asset_library/resources/shaders/transition/halftone_wipe_transition.gdshader",
			"tags": PackedStringArray(["shader", "transition"]),
			"notes": "Default routed scene transition shader.",
		},
		{
			"slot_id": "slot.shader.ui.button_focus",
			"display_name": "Button Focus Border",
			"expected_kind": "shader",
			"current_asset_key": "asset.shader.ui.button_focus_dash",
			"current_library_path": "res://features/asset_library/resources/shaders/ui/button_focus_dash.gdshader",
			"tags": PackedStringArray(["shader", "ui", "focus"]),
			"notes": "Default selected button border shader.",
		},
	]


func _collect_audio_entry_lookup(source_path: String) -> Dictionary:
	var lookup: Dictionary = {}
	var entries: Array[Dictionary] = GFAudioLibraryTools.scan_library(source_path, {
		"extensions": _to_packed_string_array(AUDIO_EXTENSIONS),
		"id_mode": GFAudioBankTools.ClipIdMode.RELATIVE_PATH,
		"base_path": source_path,
	})
	for entry: Dictionary in entries:
		var path: String = _normalize_path(GFVariantData.get_option_string(entry, "source_path"))
		if not path.is_empty():
			lookup[path] = entry
	return lookup


func _make_display_name(source_file: String, relative_path: String, audio_entry_lookup: Dictionary) -> String:
	var normalized_source: String = _normalize_path(source_file)
	var entry_value: Variant = audio_entry_lookup.get(normalized_source)
	if entry_value is Dictionary:
		var audio_entry: Dictionary = entry_value
		var clip_id: String = GFVariantData.get_option_string(audio_entry, "clip_id")
		if not clip_id.is_empty():
			return clip_id
	var base_name: String = source_file.get_file().get_basename().strip_edges()
	if not base_name.is_empty():
		return base_name
	return relative_path


func _make_record_tags(
	source_pack_config: Dictionary,
	relative_path: String,
	asset_kind: StringName,
	existing_record: Resource
) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	_append_unique_tag(tags, String(asset_kind))
	for source_tag: String in GFVariantData.get_option_packed_string_array(source_pack_config, "tags"):
		_append_unique_tag(tags, source_tag)
	for inferred_tag: String in _infer_tags(relative_path):
		_append_unique_tag(tags, inferred_tag)
	if existing_record != null:
		for existing_tag: String in _get_resource_packed_string_array(existing_record, "tags"):
			_append_unique_tag(tags, existing_tag)
	return tags


func _make_suggested_slots(
	relative_path: String,
	asset_kind: StringName,
	existing_record: Resource
) -> PackedStringArray:
	var slots: PackedStringArray = PackedStringArray()
	for slot: String in _infer_suggested_slots(relative_path, asset_kind):
		_append_unique_tag(slots, slot)
	if existing_record != null:
		for existing_slot: String in _get_resource_packed_string_array(existing_record, "suggested_slots"):
			_append_unique_tag(slots, existing_slot)
	return slots


func _infer_asset_kind(extension: String) -> StringName:
	if AUDIO_EXTENSIONS.has(extension):
		return KIND_AUDIO
	if SHADER_EXTENSIONS.has(extension):
		return KIND_SHADER
	if TEXTURE_EXTENSIONS.has(extension):
		return KIND_TEXTURE
	if VFX_EXTENSIONS.has(extension):
		return KIND_VFX
	return KIND_OTHER


func _is_preview_supported(extension: String) -> bool:
	if extension == "m4a":
		return false
	return (
		AUDIO_EXTENSIONS.has(extension)
		or SHADER_EXTENSIONS.has(extension)
		or TEXTURE_EXTENSIONS.has(extension)
	)


func _infer_tags(relative_path: String) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	var normalized: String = relative_path.replace("\\", "/").to_lower()
	for raw_token: String in normalized.split("/", false):
		for part: String in raw_token.get_basename().split(" ", false):
			var tag: String = _make_snake_token(part)
			if not tag.is_empty() and tag.length() <= 32:
				_append_unique_tag(tags, tag)
	for keyword: String in [
		"ui",
		"button",
		"click",
		"hover",
		"select",
		"confirm",
		"retro",
		"match",
		"tile",
		"transition",
		"toon",
		"shader",
	]:
		if normalized.contains(keyword):
			_append_unique_tag(tags, keyword)
	return tags


func _infer_suggested_slots(relative_path: String, asset_kind: StringName) -> PackedStringArray:
	var slots: PackedStringArray = PackedStringArray()
	var text: String = relative_path.to_lower()
	if asset_kind == KIND_AUDIO:
		if _contains_any(text, ["select", "hover", "cursor", "button", "click"]):
			_append_unique_tag(slots, "slot.audio.ui.select")
		if _contains_any(text, ["confirm", "accept", "ok", "start", "success"]):
			_append_unique_tag(slots, "slot.audio.ui.confirm")
		if _contains_any(text, ["spawn", "new", "appear", "pop"]):
			_append_unique_tag(slots, "slot.audio.tile.spawn")
		if _contains_any(text, ["move", "slide", "swipe", "shift"]):
			_append_unique_tag(slots, "slot.audio.tile.move")
		if _contains_any(text, ["merge", "match", "combine"]):
			_append_unique_tag(slots, "slot.audio.tile.merge")
		if _contains_any(text, ["fail", "error", "lose", "over"]):
			_append_unique_tag(slots, "slot.audio.game.over")
	elif asset_kind == KIND_SHADER:
		if text.contains("transition"):
			_append_unique_tag(slots, "slot.shader.transition.scene_wipe")
		if _contains_any(text, ["background", "stylized", "toon"]):
			_append_unique_tag(slots, "slot.shader.background.main")
		if _contains_any(text, ["button", "focus", "border"]):
			_append_unique_tag(slots, "slot.shader.ui.button_focus")
	return slots


func _scan_all_files(root_path: String) -> Dictionary:
	return GFPathEnumerationTools.scan_files(root_path, {
		"recursive": true,
		"include_hidden": false,
		"max_file_count": MAX_SOURCE_FILE_COUNT,
		"sort": true,
	})


func _summarize_path_scan_report(scan_report: Dictionary) -> Dictionary:
	var summary: Dictionary = scan_report.duplicate(true)
	var _erase_result: bool = summary.erase("paths")
	return summary


func _copy_file_if_changed(source_path: String, target_path: String, source_sha256: String) -> String:
	if FileAccess.file_exists(target_path):
		var target_sha256: String = FileAccess.get_sha256(target_path)
		if not target_sha256.is_empty() and target_sha256 == source_sha256:
			return "unchanged"
	var ensure_result: Error = _ensure_dir(target_path.get_base_dir())
	if ensure_result != OK:
		return "target_directory_error"
	var copy_result: Error = _copy_file(source_path, target_path)
	if copy_result != OK:
		return "copy_error_%d" % copy_result
	return "copied"


func _copy_file(source_path: String, target_path: String) -> Error:
	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return FileAccess.get_open_error()
	var target_file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		source_file.close()
		return FileAccess.get_open_error()
	while source_file.get_position() < source_file.get_length():
		var remaining_bytes: int = source_file.get_length() - source_file.get_position()
		var buffer_size: int = mini(COPY_BUFFER_SIZE, remaining_bytes)
		var buffer: PackedByteArray = source_file.get_buffer(buffer_size)
		if buffer.is_empty() and remaining_bytes > 0:
			source_file.close()
			target_file.close()
			return ERR_FILE_CANT_READ
		var store_result: Variant = target_file.store_buffer(buffer)
		if store_result is bool and not store_result:
			source_file.close()
			target_file.close()
			return ERR_FILE_CANT_WRITE
	source_file.close()
	target_file.close()
	return OK


func _make_pack_report(pack_id: String, source_pack_config: Dictionary, file_count: int) -> Dictionary:
	return {
		"source_pack_id": pack_id,
		"display_name": GFVariantData.get_option_string(source_pack_config, "display_name", pack_id),
		"file_count": file_count,
		"review_record_count": 0,
		"non_review_file_count": 0,
		"copied_count": 0,
		"unchanged_count": 0,
		"error_count": 0,
		"byte_count": 0,
		"kind_counts": {},
		"status_counts": {},
		"license_counts": {},
	}


func _accumulate_pack_report(report: Dictionary, pack_report: Dictionary) -> void:
	var pack_reports: Array = GFVariantData.get_option_array(report, "source_packs")
	pack_reports.append(pack_report)
	report["source_packs"] = pack_reports
	report["file_count"] = GFVariantData.get_option_int(report, "file_count") + GFVariantData.get_option_int(pack_report, "file_count")
	report["review_record_count"] = (
		GFVariantData.get_option_int(report, "review_record_count")
		+ GFVariantData.get_option_int(pack_report, "review_record_count")
	)
	report["copied_count"] = GFVariantData.get_option_int(report, "copied_count") + GFVariantData.get_option_int(pack_report, "copied_count")
	report["unchanged_count"] = GFVariantData.get_option_int(report, "unchanged_count") + GFVariantData.get_option_int(pack_report, "unchanged_count")
	report["byte_count"] = GFVariantData.get_option_int(report, "byte_count") + GFVariantData.get_option_int(pack_report, "byte_count")
	_merge_nested_counts(report, "kind_counts", GFVariantData.get_option_dictionary(pack_report, "kind_counts"))
	_merge_nested_counts(report, "status_counts", GFVariantData.get_option_dictionary(pack_report, "status_counts"))
	_merge_nested_counts(report, "license_counts", GFVariantData.get_option_dictionary(pack_report, "license_counts"))


func _merge_nested_counts(report: Dictionary, key: String, incoming: Dictionary) -> void:
	var counts: Dictionary = GFVariantData.get_option_dictionary(report, key)
	for incoming_key: Variant in incoming.keys():
		var text_key: String = GFVariantData.to_text(incoming_key)
		counts[text_key] = GFVariantData.get_option_int(counts, text_key) + GFVariantData.get_option_int(incoming, text_key)
	report[key] = counts


func _increment_nested_count(report: Dictionary, key: String, value: String) -> void:
	var counts: Dictionary = GFVariantData.get_option_dictionary(report, key)
	counts[value] = GFVariantData.get_option_int(counts, value) + 1
	report[key] = counts


func _make_report() -> Dictionary:
	return {
		"ok": true,
		"report_id": "asset_source_import",
		"config_path": CONFIG_PATH,
		"source_pack_count": 0,
		"file_count": 0,
		"review_record_count": 0,
		"copied_count": 0,
		"unchanged_count": 0,
		"byte_count": 0,
		"slot_count": 0,
		"bound_slot_count": 0,
		"kind_counts": {},
		"status_counts": {},
		"license_counts": {},
		"source_packs": [],
		"issues": [],
		"issue_count": 0,
		"error_count": 0,
		"warning_count": 0,
	}


func _add_issue(report: Dictionary, severity: String, kind: String, message: String, metadata: Dictionary) -> void:
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	var issue: Dictionary = metadata.duplicate(true)
	issue["severity"] = severity
	issue["kind"] = kind
	issue["message"] = message
	issues.append(issue)
	report["issues"] = issues
	if severity == "error":
		report["error_count"] = GFVariantData.get_option_int(report, "error_count") + 1
	elif severity == "warning":
		report["warning_count"] = GFVariantData.get_option_int(report, "warning_count") + 1


func _finalize_report(report: Dictionary) -> void:
	report["issue_count"] = GFVariantData.get_option_array(report, "issues").size()
	report["ok"] = GFVariantData.get_option_int(report, "error_count") == 0


func _write_reports(report: Dictionary) -> void:
	var markdown_error: Error = _write_text_if_changed(REPORT_MARKDOWN_PATH, _format_report_markdown(report))
	if markdown_error != OK:
		_add_issue(report, "error", "report_markdown_write_failed", "Source import Markdown report could not be written.", {
			"path": REPORT_MARKDOWN_PATH,
			"error": markdown_error,
		})
		_finalize_report(report)
	var json_error: Error = _write_text_if_changed(REPORT_JSON_PATH, JSON.stringify(report, "\t"))
	if json_error != OK:
		_add_issue(report, "error", "report_json_write_failed", "Source import JSON report could not be written.", {
			"path": REPORT_JSON_PATH,
			"error": json_error,
		})
		_finalize_report(report)


func _format_report_markdown(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	_append_markdown_line(lines, "# Source Asset Import Report")
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "- Source packs: `%d`" % GFVariantData.get_option_int(report, "source_pack_count"))
	_append_markdown_line(lines, "- Files: `%d`" % GFVariantData.get_option_int(report, "file_count"))
	_append_markdown_line(lines, "- Review records: `%d`" % GFVariantData.get_option_int(report, "review_record_count"))
	_append_markdown_line(lines, "- Copied: `%d`" % GFVariantData.get_option_int(report, "copied_count"))
	_append_markdown_line(lines, "- Unchanged: `%d`" % GFVariantData.get_option_int(report, "unchanged_count"))
	_append_markdown_line(lines, "- Slot bindings: `%d / %d`" % [
		GFVariantData.get_option_int(report, "bound_slot_count"),
		GFVariantData.get_option_int(report, "slot_count"),
	])
	_append_markdown_line(lines, "- Issues: `%d`" % GFVariantData.get_option_int(report, "issue_count"))
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "## Packs")
	for pack_value: Variant in GFVariantData.get_option_array(report, "source_packs"):
		var pack_report: Dictionary = GFVariantData.as_dictionary(pack_value)
		_append_markdown_line(lines, "")
		_append_markdown_line(lines, "### `%s`" % GFVariantData.get_option_string(pack_report, "source_pack_id"))
		_append_markdown_line(lines, "- Files: `%d`" % GFVariantData.get_option_int(pack_report, "file_count"))
		_append_markdown_line(lines, "- Review records: `%d`" % GFVariantData.get_option_int(pack_report, "review_record_count"))
		_append_markdown_line(lines, "- Copied: `%d`" % GFVariantData.get_option_int(pack_report, "copied_count"))
		_append_markdown_line(lines, "- Unchanged: `%d`" % GFVariantData.get_option_int(pack_report, "unchanged_count"))
		_append_markdown_line(lines, "- Bytes: `%d`" % GFVariantData.get_option_int(pack_report, "byte_count"))
	_append_markdown_line(lines, "")
	_append_markdown_line(lines, "## Issues")
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	if issues.is_empty():
		_append_markdown_line(lines, "- None")
	else:
		for issue_value: Variant in issues:
			var issue: Dictionary = GFVariantData.as_dictionary(issue_value)
			_append_markdown_line(lines, "- `%s` `%s`: %s" % [
				GFVariantData.get_option_string(issue, "severity"),
				GFVariantData.get_option_string(issue, "kind"),
				GFVariantData.get_option_string(issue, "message"),
			])
	return "\n".join(lines) + "\n"


func _append_markdown_line(lines: PackedStringArray, line: String) -> void:
	var _append_result: bool = lines.append(line)


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var dictionary: Dictionary = parsed
		return dictionary
	return {}


func _write_text(path: String, text: String) -> Error:
	var ensure_result: Error = _ensure_dir(path.get_base_dir())
	if ensure_result != OK:
		return ensure_result
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var _store_string_result: bool = file.store_string(text)
	file.close()
	return OK


func _write_text_if_changed(path: String, text: String) -> Error:
	if FileAccess.file_exists(path):
		var existing_file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if existing_file == null:
			return FileAccess.get_open_error()
		var existing_text: String = existing_file.get_as_text()
		existing_file.close()
		if existing_text == text:
			return OK
	return _write_text(path, text)


func _ensure_dir(path: String) -> Error:
	if path.is_empty() or path == ".":
		return OK
	return DirAccess.make_dir_recursive_absolute(_to_absolute_path(path))


func _get_file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = file.get_length()
	file.close()
	return length


func _make_record_resource_path(pack_id: String, relative_path: String, sha256: String) -> String:
	var slug: String = _make_snake_token(relative_path.get_file().get_basename())
	if slug.length() > 72:
		slug = slug.substr(0, 72).trim_suffix("_")
	if slug.is_empty():
		slug = "asset"
	var hash_text: String = sha256.substr(0, 8) if sha256.length() >= 8 else "no_hash"
	return REVIEW_RECORD_ROOT.path_join(pack_id).path_join("%s_%s.tres" % [slug, hash_text])


func _make_asset_id(pack_id: String, relative_path: String, sha256: String) -> String:
	var slug: String = _make_snake_token(relative_path.get_basename())
	if slug.length() > 48:
		slug = slug.substr(0, 48).trim_suffix("_")
	var hash_text: String = sha256.substr(0, 8) if sha256.length() >= 8 else "no_hash"
	return "asset.review.%s.%s.%s" % [pack_id.replace("_", "."), slug.replace("_", "."), hash_text]


func _make_relative_path(path: String, root_path: String) -> String:
	var normalized_path: String = _normalize_path(path)
	var normalized_root: String = _normalize_path(root_path)
	var root_prefix: String = normalized_root + "/"
	if normalized_path.begins_with(root_prefix):
		return normalized_path.substr(root_prefix.length())
	return normalized_path.get_file()


func _normalize_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/").strip_edges()
	while normalized.ends_with("/") and normalized.length() > 1:
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized


func _to_absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _resource_uses_script(resource: Resource, script: Script) -> bool:
	return resource != null and resource.get_script() == script


func _load_source_pack_resource(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if _resource_uses_script(loaded, ASSET_SOURCE_PACK_SCRIPT):
		return loaded
	return null


func _get_existing_source_pack_imported_at(pack_id: String) -> String:
	var resource_path: String = SOURCE_PACK_RESOURCE_ROOT.path_join("%s.tres" % pack_id)
	var existing_resource: Resource = _load_source_pack_resource(resource_path)
	var imported_at: String = _get_resource_string(existing_resource, "imported_at")
	if not imported_at.is_empty():
		return imported_at
	var manifest_path: String = SOURCE_PACK_ROOT.path_join(pack_id).path_join("source_pack_manifest.json")
	return GFVariantData.get_option_string(_read_json(manifest_path), "imported_at")


func _resources_match(left: Resource, right: Resource, property_names: Array[String]) -> bool:
	if left == null or right == null:
		return false
	for property_name: String in property_names:
		if left.get(property_name) != right.get(property_name):
			return false
	return true


func _get_resource_string(resource: Resource, property_name: String, fallback: String = "") -> String:
	if resource == null:
		return fallback
	var value: Variant = resource.get(property_name)
	return GFVariantData.to_text(value, fallback)


func _get_resource_string_name(
	resource: Resource,
	property_name: String,
	fallback: StringName = &""
) -> StringName:
	if resource == null:
		return fallback
	var value: Variant = resource.get(property_name)
	if value is StringName:
		var string_name_value: StringName = value
		return string_name_value
	return StringName(GFVariantData.to_text(value, String(fallback)))


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


func _find_slot_binding(slot_map: Resource, slot_id: StringName) -> Resource:
	for binding: Resource in _get_slot_bindings(slot_map):
		if binding != null and _get_resource_string_name(binding, "slot_id") == slot_id:
			return binding
	return null


func _upsert_slot_binding(slot_map: Resource, binding: Resource) -> void:
	if slot_map == null or binding == null:
		return
	var slot_id: StringName = _get_resource_string_name(binding, "slot_id")
	if slot_id == &"":
		return
	var bindings: Array[Resource] = _get_slot_bindings(slot_map)
	for index: int in range(bindings.size()):
		var existing: Resource = bindings[index]
		if existing != null and _get_resource_string_name(existing, "slot_id") == slot_id:
			bindings[index] = binding
			slot_map.set("bindings", bindings)
			return
	bindings.append(binding)
	slot_map.set("bindings", bindings)


func _get_slot_bindings(slot_map: Resource) -> Array[Resource]:
	var bindings: Array[Resource] = []
	if slot_map == null:
		return bindings
	var value: Variant = slot_map.get("bindings")
	if value is Array:
		var raw_bindings: Array = value
		for raw_binding: Variant in raw_bindings:
			if raw_binding is Resource:
				var binding: Resource = raw_binding
				bindings.append(binding)
	return bindings


func _get_bound_slot_count(slot_map: Resource) -> int:
	var count: int = 0
	for binding: Resource in _get_slot_bindings(slot_map):
		var asset_key: StringName = _get_resource_string_name(binding, "current_asset_key")
		var library_path: String = _get_resource_string(binding, "current_library_path")
		if asset_key != &"" or not library_path.is_empty():
			count += 1
	return count


func _make_snake_token(text: String) -> String:
	var result: String = ""
	var previous_was_separator: bool = false
	var normalized: String = text.to_lower()
	for index: int in range(normalized.length()):
		var code: int = normalized.unicode_at(index)
		var is_letter: bool = code >= 97 and code <= 122
		var is_digit: bool = code >= 48 and code <= 57
		if is_letter or is_digit:
			result += normalized.substr(index, 1)
			previous_was_separator = false
		elif not previous_was_separator:
			result += "_"
			previous_was_separator = true
	return result.trim_prefix("_").trim_suffix("_")


func _contains_any(text: String, needles: Array[String]) -> bool:
	for needle: String in needles:
		if text.contains(needle):
			return true
	return false


func _append_unique_tag(target: PackedStringArray, value: String) -> void:
	var normalized: String = value.strip_edges().to_lower()
	if normalized.is_empty() or target.has(normalized):
		return
	var _append_result: bool = target.append(normalized)


func _to_packed_string_array(values: Array[String]) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: String in values:
		var _append_result: bool = result.append(value)
	return result
