## 把项目 chunk staging 请求委托给已注入的 GFSaveProfileUtility。
##
## Adapter 不构造 GF operation/result，也不访问 Storage private family。
class_name GfChunkProfileExecutor
extends ChunkProfileExecutor


# --- 私有变量 ---

var _profile_utility: GFSaveProfileUtility = null


# --- 生命周期方法 ---

func _init(profile_utility: GFSaveProfileUtility = null) -> void:
	_profile_utility = profile_utility


# --- 公共方法 ---

## 委托已注册 chunk Profile 的 public GF save 请求。
## @param profile_id: 已注册 chunk GF Profile 的 ID。
## @param request: 由 staging 编排器构造的类型化保存请求。
func save_profile(
	profile_id: StringName,
	request: GFSaveProfileRequest
) -> GFSaveProfileOperation:
	if _profile_utility == null or profile_id == &"" or request == null:
		return null
	return _profile_utility.save_profile(profile_id, request)
