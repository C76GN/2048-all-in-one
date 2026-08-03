## 验证项目通用素材库的 GF 内容包注册、资源解析和审计报告。
extends GutTest


# --- 常量 ---

const _ASSET_LIBRARY_MANIFEST_PATH: String = "res://features/asset_library/resources/gf_content_package.json"
const _REVIEW_CATALOG_PROVIDER_SCRIPT = preload(
	"res://features/asset_library/scripts/catalog/game_asset_review_catalog_source_provider.gd"
)
const _ASSET_REVIEW_RECORD_SCRIPT = preload("res://features/asset_library/scripts/data/asset_review_record.gd")


# --- 测试用例 ---

func test_asset_library_manifest_is_valid_and_self_contained() -> void:
	var manifest: GFContentPackageManifest = GFContentPackageManifest.load_from_path(_ASSET_LIBRARY_MANIFEST_PATH)

	assert_true(manifest != null, "素材库 manifest 应能加载。")
	assert_true(manifest.package_id == GameAssetLibraryUtility.ASSET_LIBRARY_PACKAGE_ID, "素材库 package id 应稳定。")
	assert_true(manifest.safety_kind == &"trusted_developer", "素材库包含 shader，应使用 trusted_developer safety kind。")
	assert_true(manifest.is_valid({"check_resource_exists": true}), "素材库 manifest 应只登记存在且位于库内的资源。")
	assert_true(manifest.get_resource_keys().has("asset.audio.ui.printworks.select_soft_01"), "素材库应登记 UI 选择音效。")
	assert_true(manifest.get_resource_keys().has("asset.shader.ui.button_focus_dash"), "素材库应登记按钮焦点 shader。")
	assert_true(manifest.get_resource_keys().has("asset.shader.ui.startup_progress_bar"), "素材库应登记启动进度条 shader。")
	assert_true(manifest.get_resource_keys().has("asset.vfx.celebration.confetti_canvas"), "素材库应登记庆祝反馈 VFX shader。")


func test_asset_library_registers_assets_into_gf_resolver() -> void:
	var setup: Dictionary = await _create_asset_library_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var resolver: GFResourceResolverUtility = _get_resolver(setup)
	var asset_library: GameAssetLibraryUtility = _get_asset_library(setup)

	var audio: Resource = asset_library.load_asset(&"asset.audio.ui.printworks.select_soft_01", "AudioStreamOggVorbis")
	var shader: Resource = asset_library.load_asset(&"asset.shader.ui.button_focus_dash", "Shader")
	var startup_progress_shader: Resource = asset_library.load_asset(&"asset.shader.ui.startup_progress_bar", "Shader")
	var celebration_shader: Resource = asset_library.load_asset(&"asset.vfx.celebration.confetti_canvas", "Shader")
	var resolve_report: Dictionary = resolver.resolve(&"asset.shader.transition.halftone_wipe", "Shader")
	var runtime_catalog: GFAssetCatalog = asset_library.get_runtime_catalog()
	var transition_catalog_id: StringName = (
		GameAssetLibraryUtility.make_runtime_catalog_asset_id(
			&"asset.shader.transition.halftone_wipe"
		)
	)
	var transition_entry: GFAssetCatalogEntry = asset_library.get_runtime_catalog_entry(
		&"asset.shader.transition.halftone_wipe"
	)

	assert_true(audio is AudioStream, "素材库音频应能通过稳定 asset key 加载。")
	assert_true(shader is Shader, "素材库 shader 应能通过稳定 asset key 加载。")
	assert_true(startup_progress_shader is Shader, "启动进度条 shader 应能通过稳定 asset key 加载。")
	assert_true(celebration_shader is Shader, "素材库庆祝 VFX shader 应能通过稳定 asset key 加载。")
	assert_true(GFVariantData.get_option_bool(resolve_report, "ok", false), "素材库资源键应注册进 GFResourceResolverUtility。")
	assert_true(
		runtime_catalog.has_entry(transition_catalog_id),
		"内容包资源应以 package_id/resource_key 规范 ID 进入 GFAssetCatalog。"
	)
	assert_true(transition_entry != null, "内容包目录应保留已注册资源条目。")
	if transition_entry != null:
		assert_true(
			transition_entry.asset_id == transition_catalog_id,
			"项目 helper 应把稳定 resource key 映射到 GF 规范目录 ID。"
		)
		assert_true(
			GFVariantData.get_option_string_name(
				transition_entry.metadata,
				"content_package_resource_key"
			) == &"asset.shader.transition.halftone_wipe",
			"GF 目录 metadata 应保留原稳定 resource key，避免 catalog ID 迁移丢失身份。"
		)
		assert_true(transition_entry.tags.has("shader"), "GF 标准 metadata.tags 应进入目录标签索引。")
		assert_true(transition_entry.tags.has("transition"), "转场素材应保留用途标签。")
	assert_true(
		asset_library.resolve_asset_path(&"asset.audio.ui.printworks.select_soft_01", "AudioStreamOggVorbis")
			== "res://features/asset_library/resources/audio/ui/printworks_select_soft_01.ogg",
		"素材库应提供稳定 ID 到资源路径的解析。"
	)

	await _dispose_architecture(architecture)


func test_runtime_asset_catalog_atomically_tracks_content_refresh() -> void:
	var setup: Dictionary = await _create_asset_library_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var project_catalog: ProjectContentCatalogUtility = _get_project_catalog(setup)
	var asset_library: GameAssetLibraryUtility = _get_asset_library(setup)
	var before_snapshot: Dictionary = asset_library.get_debug_snapshot()
	var before_runtime: Dictionary = GFVariantData.get_option_dictionary(
		before_snapshot,
		"catalog_runtime"
	)
	var before_revision: int = GFVariantData.get_option_int(
		before_runtime,
		"revision"
	)

	project_catalog.catalog_refreshed.emit({
		"ok": true,
		"refresh_marker": "gut-runtime-refresh",
	})

	var after_snapshot: Dictionary = asset_library.get_debug_snapshot()
	var after_runtime: Dictionary = GFVariantData.get_option_dictionary(
		after_snapshot,
		"catalog_runtime"
	)
	assert_true(
		GFVariantData.get_option_int(after_runtime, "revision")
			== before_revision + 1,
		"内容目录刷新应通过 replace_mount_catalog 原子提交一个新 revision。"
	)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.get_option_dictionary(after_snapshot, "catalog_report"),
			"refresh_marker"
		) == "gut-runtime-refresh",
		"素材库应保留触发本次原子目录替换的刷新报告。"
	)

	await _dispose_architecture(architecture)


func test_project_content_catalog_uses_owner_scoped_roots_and_gf_query() -> void:
	var setup: Dictionary = await _create_asset_library_architecture()
	var architecture: GFArchitecture = _get_architecture(setup)
	var content_packages: GFContentPackageUtility = _get_content_packages(setup)
	var project_catalog: ProjectContentCatalogUtility = _get_project_catalog(setup)

	assert_true(
		content_packages.get_owner_source_roots(
			ProjectContentCatalogUtility.SOURCE_ROOT_OWNER_ID
		).has(GameAssetLibraryUtility.ASSET_LIBRARY_SOURCE_ROOT),
		"项目内容包根目录应由稳定 owner scope 持有。"
	)
	assert_true(
		content_packages.get_owner_source_roots(
			GFContentPackageUtility.DEFAULT_SOURCE_ROOT_OWNER_ID
		).is_empty(),
		"项目目录不应再占用 GF 默认 manual owner scope。"
	)

	var matching_entries: Array[Dictionary] = project_catalog.query_resources({
		"package_ids": PackedStringArray([
			String(GameAssetLibraryUtility.ASSET_LIBRARY_PACKAGE_ID),
		]),
		"required_content_type": "asset_library",
		"type_hint": "Shader",
		"key_prefix": "asset.shader.transition.",
		"metadata": {"category": "transition"},
	})
	var non_matching_entries: Array[Dictionary] = project_catalog.query_resources({
		"package_ids": PackedStringArray(["missing.package"]),
		"required_content_type": "asset_library",
	})

	assert_false(matching_entries.is_empty(), "GFContentPackageQuery 命中包后应继续应用资源级薄筛选。")
	for entry: Dictionary in matching_entries:
		assert_true(
			GFVariantData.get_option_string(entry, "type_hint") == "Shader",
			"资源级 type_hint 筛选应保持原契约。"
		)
		assert_true(
			String(GFVariantData.get_option_string_name(entry, "key")).begins_with(
				"asset.shader.transition."
			),
			"资源级 key_prefix 筛选应保持原契约。"
		)
	assert_true(non_matching_entries.is_empty(), "不存在的 package ID 应稳定返回零匹配。")

	await _dispose_architecture(architecture)


func test_asset_library_audit_reports_usage_and_metadata_health() -> void:
	var audit: AssetLibraryAudit = AssetLibraryAudit.new()
	var report: Dictionary = audit.build_audit_report()
	var usage: Dictionary = GFVariantData.get_option_dictionary(report, "usage")
	var select_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.audio.ui.printworks.select_soft_01"
	)
	var button_shader_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.shader.ui.button_focus_dash"
	)
	var celebration_vfx_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.vfx.celebration.confetti_canvas"
	)
	var startup_progress_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.shader.ui.startup_progress_bar"
	)
	var boot_splash_usage: Dictionary = GFVariantData.get_option_dictionary(
		usage,
		"asset.texture.branding.printworks_boot_splash"
	)
	var reference_scan_report: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"reference_scan_report"
	)
	var attribution_report: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"attribution_report"
	)
	var library_scan_report: Dictionary = GFVariantData.get_option_dictionary(
		report,
		"library_scan_report"
	)

	assert_true(GFVariantData.get_option_bool(report, "ok", false), "素材库审计不应有 error。")
	assert_true(GFVariantData.get_option_int(report, "resource_count") >= 11, "素材库审计应覆盖首批音频、shader 和 VFX。")
	assert_true(
		GFVariantData.get_option_packed_string_array(report, "unregistered_library_files").is_empty(),
		"素材库内不应存在未登记的运行时素材文件。"
	)
	assert_true(
		GFVariantData.get_option_array(report, "metadata_issues").is_empty(),
		"素材库登记项必须包含审计所需元数据。"
	)
	assert_true(
		GFVariantData.get_option_bool(library_scan_report, "ok"),
		"运行时素材文件应由 GFPathEnumerationTools 成功枚举。"
	)
	assert_false(
		GFVariantData.get_option_bool(library_scan_report, "truncated"),
		"运行时素材文件枚举不应达到安全上限。"
	)
	assert_false(
		GFVariantData.get_option_bool(reference_scan_report, "partial_scan"),
		"GFProjectReferenceScanner 必须完整扫描，否则 unused 结论不可信。"
	)
	assert_true(
		GFVariantData.get_option_int(reference_scan_report, "scanned_file_count") > 0,
		"素材引用审计应由 GFProjectReferenceScanner 提供扫描证据。"
	)
	assert_true(
		GFVariantData.get_option_bool(attribution_report, "ok"),
		"运行时素材必须通过 GFAssetAttributionTools 授权覆盖校验。"
	)
	assert_true(
		GFVariantData.get_option_int(attribution_report, "covered_path_count")
			== GFVariantData.get_option_int(report, "resource_count"),
		"每个运行时素材都应有明确归因条目。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(select_usage, "path_users").has("res://features/themes/resources/audio/printworks_audio_bank.tres"),
		"审计报告应能说明 UI 选择音效被音频银行使用。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(button_shader_usage, "key_users").has("res://features/themes/scripts/utilities/game_ui_style_utility.gd"),
		"审计报告应能说明 UI 样式 Utility 通过稳定素材键使用按钮焦点 shader。"
	)
	assert_false(
		GFVariantData.get_option_packed_string_array(button_shader_usage, "path_users").has("res://features/themes/scripts/utilities/game_ui_style_utility.gd"),
		"UI 样式 Utility 不应绕过 GF 素材解析器直接引用按钮焦点 shader 路径。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(celebration_vfx_usage, "key_users").has("res://features/themes/resources/themes/game/vfx/halftone_atlas_celebration_theme.tres"),
		"审计报告应能说明庆祝 VFX shader 资源键由当前庆祝主题声明。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(boot_splash_usage, "path_users").has(
			"res://project.godot"
		),
		"Godot 原生启动图设置应被审计为正式启动素材的引擎级消费者。"
	)
	assert_false(
		GFVariantData.get_option_bool(startup_progress_usage, "used"),
		"静态首帧不应为可选进度 shader 支付编译成本。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(
			report,
			"optional_unused_keys"
		).has("asset.shader.ui.startup_progress_bar"),
		"已批准的可替换启动 shader 应保留在素材库，但不得被误报为死资源。"
	)
	assert_true(
		GFVariantData.get_option_packed_string_array(
			report,
			"required_unused_keys"
		).is_empty(),
		"当前主题要求的正式素材必须都有实际消费者。"
	)

	var allowed_direct_script_users: PackedStringArray = [
		"res://features/asset_library/tools/import_asset_sources.gd",
	]
	for asset_key_value: Variant in usage:
		var asset_key: String = GFVariantData.to_text(asset_key_value)
		var asset_usage: Dictionary = GFVariantData.get_option_dictionary(usage, asset_key_value)
		for path_user: String in GFVariantData.get_option_packed_string_array(asset_usage, "path_users"):
			if not path_user.ends_with(".gd"):
				continue
			assert_true(
				allowed_direct_script_users.has(path_user),
				"架构启动后的业务 GDScript 必须通过稳定素材键加载：%s -> %s。"
				% [asset_key, path_user]
			)
	audit.dispose()


func test_runtime_asset_policy_rejects_candidate_paths_and_placeholder_licenses() -> void:
	var audit: AssetLibraryAudit = AssetLibraryAudit.new()
	var blocked_entry: Dictionary = {
		"key": &"asset.audio.fixture.blocked",
		"path": (
			"res://features/asset_library/resources/source_packs/"
			+ "fixture/files/blocked.ogg"
		),
		"metadata": {
			"asset_kind": "audio",
			"category": "ui",
			"origin": "third_party",
			"author": "Fixture Author",
			"source": "Fixture source",
			"source_url": "https://example.com/fixture",
			"license": "unknown",
		},
	}
	var blocked_entries: Array[Dictionary] = [blocked_entry]
	var metadata_issues: Array[Dictionary] = audit._collect_metadata_issues(
		blocked_entries,
		{}
	)
	var attribution_report: Dictionary = audit._build_manifest_attribution_report(
		blocked_entries
	)

	assert_true(
		_metadata_issues_have_kind(metadata_issues, "forbidden_runtime_asset_path"),
		"运行时 manifest 不得引用 source_packs 或 review 候选路径。"
	)
	assert_true(
		_metadata_issues_have_kind(metadata_issues, "placeholder_license_metadata"),
		"运行时 manifest 不得用 unknown 等占位文本冒充许可证。"
	)
	assert_false(
		GFVariantData.get_option_bool(attribution_report, "ok"),
		"占位许可证必须继续触发 GF attribution 覆盖错误。"
	)
	audit.dispose()


func test_runtime_asset_policy_accepts_runtime_path_and_real_license() -> void:
	var audit: AssetLibraryAudit = AssetLibraryAudit.new()
	var eligible_entry: Dictionary = {
		"key": &"asset.audio.fixture.eligible",
		"path": "res://features/asset_library/resources/audio/ui/fixture.ogg",
		"metadata": {
			"asset_kind": "audio",
			"category": "ui",
			"origin": "third_party",
			"author": "Fixture Author",
			"source": "Fixture source",
			"source_url": "https://example.com/fixture",
			"license": "MIT",
		},
	}
	var eligible_entries: Array[Dictionary] = [eligible_entry]
	var metadata_issues: Array[Dictionary] = audit._collect_metadata_issues(
		eligible_entries,
		{}
	)

	assert_true(metadata_issues.is_empty(), "合法运行时路径和真实许可证不应被门禁误报。")
	audit.dispose()


func test_asset_review_provider_uses_gf_catalog_search() -> void:
	var fixture_root: String = "user://gut_asset_review_catalog"
	var fixture_path: String = fixture_root.path_join("positive_chime.tres")
	var absolute_fixture_root: String = ProjectSettings.globalize_path(fixture_root)
	var _mkdir_result: Error = DirAccess.make_dir_recursive_absolute(absolute_fixture_root)
	var record: Resource = _ASSET_REVIEW_RECORD_SCRIPT.new()
	record.set(
		"asset_id",
		&"asset.review.fixture.audio.positive_chime"
	)
	record.set("display_name", "Positive Chime")
	record.set("asset_kind", &"audio")
	record.set("review_group_id", &"review.group.fixture.positive_chime")
	record.set("review_status", &"candidate")
	record.set("tags", PackedStringArray(["audio", "positive", "ui"]))
	record.set("library_path", "res://features/asset_library/resources/audio/ui/printworks_confirm_soft_01.ogg")
	var save_result: Error = ResourceSaver.save(record, fixture_path)
	assert_true(save_result == OK, "候选素材 fixture 应保存成功。")

	var provider: GameAssetReviewCatalogSourceProvider = _REVIEW_CATALOG_PROVIDER_SCRIPT.new()
	assert_true(provider is GFAssetCatalogSourceProvider, "评审目录 adapter 应实现 GF provider 契约。")
	var _configured: GFAssetCatalogSourceProvider = provider.configure_review_records(
		fixture_root,
		&"fixture_review"
	)
	var catalog: GFAssetCatalog = provider.build_catalog()
	var search_reports: Array[Dictionary] = catalog.search("positive chime", {"limit": 5})
	var review_group_ids: PackedStringArray = catalog.query(
		GFAssetCatalog.GROUP_SOURCE_TAGS,
		"review_group:review.group.fixture.positive_chime"
	)
	var scan_report: Dictionary = provider.get_scan_report()
	var entry: GFAssetCatalogEntry = catalog.get_entry(
		&"asset.review.fixture.audio.positive_chime"
	)

	assert_true(catalog.get_all_ids().size() == 1, "GF 候选素材目录应覆盖 fixture 记录。")
	assert_true(GFVariantData.get_option_bool(scan_report, "ok"), "候选目录应使用 GF 路径枚举并成功完成。")
	assert_false(GFVariantData.get_option_bool(scan_report, "truncated"), "候选目录路径枚举不应达到安全上限。")
	assert_true(
		review_group_ids.has("asset.review.fixture.audio.positive_chime"),
		"GF 标签索引应支持按稳定 review_group_id 查找同音频变体。"
	)
	assert_not_null(entry, "GF 候选素材目录应保留 fixture 条目。")
	if entry != null:
		assert_true(
			GFVariantData.get_option_string(entry.metadata, "review_group_id")
				== "review.group.fixture.positive_chime",
			"候选条目 metadata 应保留稳定 review_group_id。"
		)
	assert_false(search_reports.is_empty(), "GFAssetCatalog 搜索应命中已导入的候选音频。")
	if not search_reports.is_empty():
		var candidate: Dictionary = GFVariantData.get_option_dictionary(search_reports[0], "candidate")
		assert_true(
			GFVariantData.get_option_string(candidate, "asset_id")
				== "asset.review.fixture.audio.positive_chime",
			"候选素材搜索应返回稳定 asset_id。"
		)
	_cleanup_review_fixture(fixture_path, absolute_fixture_root)


# --- 私有/辅助方法 ---

func _create_asset_library_architecture() -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var content_packages: GFContentPackageUtility = GFContentPackageUtility.new()
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var project_content_catalog: ProjectContentCatalogUtility = (
		ProjectContentCatalogUtility.new().configure_source_roots(PackedStringArray([
			GameAssetLibraryUtility.ASSET_LIBRARY_SOURCE_ROOT,
		]))
	)
	var asset_library: GameAssetLibraryUtility = GameAssetLibraryUtility.new()

	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(GFContentPackageUtility, content_packages)
	await architecture.register_utility(GFSignalUtility, signal_utility)
	await architecture.register_utility(
		ProjectContentCatalogUtility,
		project_content_catalog
	)
	await architecture.register_utility(GameAssetLibraryUtility, asset_library)
	await architecture.init()
	await get_tree().process_frame

	return {
		"architecture": architecture,
		"resolver": resolver,
		"content_packages": content_packages,
		"project_content_catalog": project_content_catalog,
		"asset_library": asset_library,
	}


func _dispose_architecture(architecture: GFArchitecture) -> void:
	if architecture != null:
		architecture.dispose()
	await get_tree().process_frame


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_resolver(setup: Dictionary) -> GFResourceResolverUtility:
	var value: Variant = setup.get("resolver")
	if value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = value
		return resolver
	assert_true(false, "测试 setup 缺少 GFResourceResolverUtility。")
	return GFResourceResolverUtility.new()


func _get_asset_library(setup: Dictionary) -> GameAssetLibraryUtility:
	var value: Variant = setup.get("asset_library")
	if value is GameAssetLibraryUtility:
		var asset_library: GameAssetLibraryUtility = value
		return asset_library
	assert_true(false, "测试 setup 缺少 GameAssetLibraryUtility。")
	return GameAssetLibraryUtility.new()


func _get_content_packages(setup: Dictionary) -> GFContentPackageUtility:
	var value: Variant = setup.get("content_packages")
	if value is GFContentPackageUtility:
		var content_packages: GFContentPackageUtility = value
		return content_packages
	assert_true(false, "测试 setup 缺少 GFContentPackageUtility。")
	return GFContentPackageUtility.new()


func _get_project_catalog(setup: Dictionary) -> ProjectContentCatalogUtility:
	var value: Variant = setup.get("project_content_catalog")
	if value is ProjectContentCatalogUtility:
		var project_catalog: ProjectContentCatalogUtility = value
		return project_catalog
	assert_true(false, "测试 setup 缺少 ProjectContentCatalogUtility。")
	return ProjectContentCatalogUtility.new()


func _metadata_issues_have_kind(issues: Array[Dictionary], kind: String) -> bool:
	for issue: Dictionary in issues:
		if GFVariantData.get_option_string(issue, "kind") == kind:
			return true
	return false


func _cleanup_review_fixture(fixture_path: String, absolute_fixture_root: String) -> void:
	var absolute_fixture_path: String = ProjectSettings.globalize_path(fixture_path)
	if FileAccess.file_exists(fixture_path):
		var _remove_file_result: Error = DirAccess.remove_absolute(absolute_fixture_path)
	if DirAccess.dir_exists_absolute(absolute_fixture_root):
		var _remove_dir_result: Error = DirAccess.remove_absolute(absolute_fixture_root)
