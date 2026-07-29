## GameSaveSectionOperationTestSupport: 在测试架构中推进并读取 section typed 终态。
class_name GameSaveSectionOperationTestSupport
extends RefCounted


## 有界推进测试架构，直到 section operation 完成或达到帧上限。
## @param operation: request_* 返回的一次性 section operation。
## @param architecture: 拥有 GFStorage/GFSaveProfile 生命周期的测试架构。
## @param scene_tree: 用于让异步 worker 回调返回主线程的测试 SceneTree。
## @param max_frames: 最多推进的测试帧数。
static func await_result(
	operation: GameSaveSectionOperation,
	architecture: GFArchitecture,
	scene_tree: SceneTree,
	max_frames: int = 600
) -> GameSaveSectionResult:
	if operation == null:
		return null
	for _frame: int in range(maxi(max_frames, 1)):
		if operation.is_completed():
			break
		if architecture != null:
			architecture.tick(1.0 / 60.0)
		await scene_tree.process_frame
	return operation.get_result()
