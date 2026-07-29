## 验证启动编排使用 GFAsyncProgressAggregator 表达具名加权任务。
extends GutTest


# --- 常量 ---

const _BOOT_RUNTIME_SCRIPT: GDScript = preload("res://app/scripts/boot_runtime.gd")
const _TASK_PREPARE: StringName = &"prepare"
const _TASK_ARCHITECTURE: StringName = &"architecture"
const _TASK_THEMES: StringName = &"themes"
const _TASK_VISUALS: StringName = &"visuals"
const _TASK_ENTRY_SCENE: StringName = &"entry_scene"
const _TASK_FINISH: StringName = &"finish"


# --- 测试方法 ---

func test_startup_progress_uses_weighted_named_tasks() -> void:
	var runtime_value: Object = _BOOT_RUNTIME_SCRIPT.new()
	assert_true(runtime_value is BootRuntime, "启动进度测试应能创建 BootRuntime。")
	if not runtime_value is BootRuntime:
		return
	var runtime: BootRuntime = runtime_value
	runtime._setup_progress()
	var progress: GFAsyncProgressAggregator = runtime._startup_progress

	assert_not_null(progress, "启动编排应创建 GFAsyncProgressAggregator。")
	assert_true(progress.get_task_count() == 6, "启动链应由六个具名任务组成。")
	_assert_task_weight(progress, _TASK_PREPARE, 0.10)
	_assert_task_weight(progress, _TASK_ARCHITECTURE, 0.32)
	_assert_task_weight(progress, _TASK_THEMES, 0.16)
	_assert_task_weight(progress, _TASK_VISUALS, 0.10)
	_assert_task_weight(progress, _TASK_ENTRY_SCENE, 0.24)
	_assert_task_weight(progress, _TASK_FINISH, 0.08)

	runtime._complete_startup_task(_TASK_PREPARE, "准备启动")
	assert_almost_eq(progress.get_total_progress(), 0.10, 0.0001)
	runtime._set_startup_task_progress(_TASK_ARCHITECTURE, 0.25, "初始化 GF 架构")
	assert_almost_eq(progress.get_total_progress(), 0.18, 0.0001)
	runtime._complete_startup_task(_TASK_ARCHITECTURE, "加载主题资源")
	assert_almost_eq(progress.get_total_progress(), 0.42, 0.0001)
	runtime._complete_startup_task(_TASK_THEMES, "准备视觉资源")
	assert_almost_eq(progress.get_total_progress(), 0.58, 0.0001)
	runtime._complete_startup_task(_TASK_VISUALS, "预热入口场景")
	assert_almost_eq(progress.get_total_progress(), 0.68, 0.0001)
	runtime._set_startup_task_progress(_TASK_ENTRY_SCENE, 0.5, "预热入口场景")
	assert_almost_eq(progress.get_total_progress(), 0.80, 0.0001)
	runtime._complete_startup_task(_TASK_ENTRY_SCENE, "入口场景已预热")
	assert_almost_eq(progress.get_total_progress(), 0.92, 0.0001)
	runtime._set_startup_task_progress(_TASK_FINISH, 0.5, "整理入口场景")
	assert_almost_eq(progress.get_total_progress(), 0.96, 0.0001)
	var completed: bool = progress.complete_all("启动完成")

	assert_true(completed, "启动任务全部完成时应强制发布 100% 终态。")
	assert_true(progress.is_complete(), "全部启动任务应收敛到完成状态。")
	var debug_snapshot: Dictionary = progress.get_debug_snapshot()
	var progress_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		debug_snapshot,
		"progress"
	)
	assert_true(
		GFVariantData.get_option_string(progress_snapshot, "message") == "启动完成",
		"成功终态应保留现有启动完成文案。"
	)
	runtime.free()


func test_startup_failure_completes_progress_with_failure_evidence() -> void:
	var runtime_value: Object = _BOOT_RUNTIME_SCRIPT.new()
	assert_true(runtime_value is BootRuntime, "失败终态测试应能创建 BootRuntime。")
	if not runtime_value is BootRuntime:
		return
	var runtime: BootRuntime = runtime_value
	runtime._setup_progress()
	runtime._complete_startup_failure("架构初始化失败")
	var progress: GFAsyncProgressAggregator = runtime._startup_progress
	var debug_snapshot: Dictionary = progress.get_debug_snapshot()
	var progress_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		debug_snapshot,
		"progress"
	)
	var metadata: Dictionary = GFVariantData.get_option_dictionary(
		progress_snapshot,
		"metadata"
	)

	assert_true(progress.is_complete(), "启动失败也应终结进度，避免加载页永久等待。")
	assert_true(
		GFVariantData.get_option_string(progress_snapshot, "message") == "架构初始化失败",
		"失败终态应保留现有失败文案。"
	)
	assert_true(
		GFVariantData.get_option_bool(metadata, "failed"),
		"失败终态应携带可供诊断消费的明确证据。"
	)
	runtime.free()


# --- 私有/辅助方法 ---

func _assert_task_weight(
	progress: GFAsyncProgressAggregator,
	task_key: StringName,
	expected_weight: float
) -> void:
	var task_index: int = progress.get_task_index(task_key)
	assert_gte(task_index, 0, "启动任务应注册稳定 key：%s。" % task_key)
	var task_snapshot: Dictionary = progress.get_task_snapshot(task_index)
	assert_almost_eq(
		GFVariantData.get_option_float(task_snapshot, "weight"),
		expected_weight,
		0.0001,
		"启动任务权重应与阶段预算一致：%s。" % task_key
	)
