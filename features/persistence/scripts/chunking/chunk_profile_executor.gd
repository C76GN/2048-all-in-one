## 隔离项目分块状态机与 GFSaveProfileUtility 的 public operation Seam。
##
## Production Adapter 只需把一次性 GFSaveProfileRequest 转交已注册 Profile 的
## `save_profile()`；它不得暴露或解析 GFStorage private family。测试 fake 可直接
## 返回确定性的 GFSaveProfileOperation。
class_name ChunkProfileExecutor
extends RefCounted


# --- 公共方法 ---

## 请求一个逻辑 GF Profile 保存操作。
##
## @param profile_id: 已由 Composition Root 注册的逻辑 Profile ID。
## @param request: 交给 GFSaveProfileUtility 的一次性 public 请求。
## @return GF public Profile operation；无法接纳时返回 null。
func save_profile(
	profile_id: StringName,
	request: GFSaveProfileRequest
) -> GFSaveProfileOperation:
	if profile_id == &"" or request == null:
		return null
	push_error("ChunkProfileExecutor requires a production or test implementation.")
	return null
