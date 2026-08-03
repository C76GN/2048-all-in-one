## GameSaveProfileOperationTestSupport: 在测试架构中推进 Profile typed 终态。
class_name GameSaveProfileOperationTestSupport
extends RefCounted


## 显式引导一个有效账号 Profile；SaveGraph ready 不再隐式加载 legacy 档案。
## @param save_graph: 被测项目存档图 Utility。
## @param architecture: 需要逐帧推进的独立 GF 架构。
## @param scene_tree: 提供测试帧等待的场景树。
## @param storage: 可选的独立 GF 存储 Utility。
## @param profile_file_name: 可选目标 Profile 文件名。
## @param adopt_legacy_if_missing: 缺失目标时是否采用当前 legacy 数据。
## @param max_frames: 等待 typed 终态的最大帧数。
## @return profile_file_name 与 GFAsyncCompletion，供测试断言唯一终态。
static func bootstrap_account(
	save_graph: GameSaveGraphUtility,
	architecture: GFArchitecture,
	scene_tree: SceneTree,
	storage: GFStorageUtility = null,
	profile_file_name: String = "",
	adopt_legacy_if_missing: bool = true,
	max_frames: int = 600
) -> Dictionary:
	var target_file_name: String = profile_file_name
	if target_file_name.is_empty():
		target_file_name = LocalAccountCatalogUtility.make_profile_file_name(
			GFUuid.generate_v7()
		)
	var scope: GFAsyncScope = GFAsyncScope.new()
	var completion: GFAsyncCompletion = save_graph.begin_bootstrap_profile(
		target_file_name,
		scope,
		adopt_legacy_if_missing
	)
	await await_completion(
		completion,
		architecture,
		scene_tree,
		storage,
		max_frames
	)
	return {
		&"profile_file_name": target_file_name,
		&"completion": completion,
	}


## 有界推进测试架构，直到一次性 completion 完成或达到帧上限。
## @param completion: 要等待的一次性终态。
## @param architecture: 需要逐帧推进的独立 GF 架构。
## @param scene_tree: 提供测试帧等待的场景树。
## @param storage: 可选的独立 GF 存储 Utility。
## @param max_frames: 最大等待帧数。
static func await_completion(
	completion: GFAsyncCompletion,
	architecture: GFArchitecture,
	scene_tree: SceneTree,
	storage: GFStorageUtility = null,
	max_frames: int = 600
) -> GFAsyncCompletion:
	if completion == null:
		return null
	for _frame: int in range(maxi(max_frames, 1)):
		if completion.is_completed():
			break
		if architecture != null:
			architecture.tick(0.0)
		if storage != null:
			storage.wait_for_async_tasks()
		if architecture != null:
			architecture.tick(0.0)
		await scene_tree.process_frame
	return completion


## 有界推进测试架构，直到 GF Profile operation 到达唯一终态。
## @param operation: 要等待的 GF Profile 操作句柄。
## @param architecture: 需要逐帧推进的独立 GF 架构。
## @param scene_tree: 提供测试帧等待的场景树。
## @param storage: 可选的独立 GF 存储 Utility。
## @param max_frames: 最大等待帧数。
static func await_result(
	operation: GFSaveProfileOperation,
	architecture: GFArchitecture,
	scene_tree: SceneTree,
	storage: GFStorageUtility = null,
	max_frames: int = 600
) -> GFSaveProfileResult:
	if operation == null:
		return null
	for _frame: int in range(maxi(max_frames, 1)):
		if operation.is_completed():
			break
		if architecture != null:
			architecture.tick(0.0)
		if storage != null:
			storage.wait_for_async_tasks()
		if architecture != null:
			architecture.tick(0.0)
		await scene_tree.process_frame
	return operation.get_result()


## 从测试协程启动异步 Profile 切换，同时持续推进独立 GFArchitecture。
## @param save_graph: 被测项目存档图 Utility。
## @param profile_file_name: 目标 Profile 文件名。
## @param adopt_current_if_missing: 缺失目标时是否采用当前数据。
## @param architecture: 需要逐帧推进的独立 GF 架构。
## @param scene_tree: 提供测试帧等待的场景树。
## @param storage: 可选的独立 GF 存储 Utility。
## @param max_frames: 最大等待帧数。
static func activate_profile(
	save_graph: GameSaveGraphUtility,
	profile_file_name: String,
	adopt_current_if_missing: bool,
	architecture: GFArchitecture,
	scene_tree: SceneTree,
	storage: GFStorageUtility = null,
	max_frames: int = 600
) -> Error:
	var state: Dictionary = {
		&"done": false,
		&"error_code": int(ERR_BUSY),
	}
	var runner: Callable = func() -> void:
		var error_code: Error = await save_graph.activate_profile_async(
			profile_file_name,
			adopt_current_if_missing
		)
		state[&"error_code"] = int(error_code)
		state[&"done"] = true
	runner.call_deferred()
	for _frame: int in range(maxi(max_frames, 1)):
		if GFVariantData.get_option_bool(state, &"done"):
			break
		if architecture != null:
			architecture.tick(0.0)
		if storage != null:
			storage.wait_for_async_tasks()
		if architecture != null:
			architecture.tick(0.0)
		await scene_tree.process_frame
	@warning_ignore("int_as_enum_without_cast")
	return GFVariantData.get_option_int(state, &"error_code", ERR_BUSY)
