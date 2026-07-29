## GameAudioUtility: 项目音频生命周期适配。
##
## GF 10.0.0 的本地 BGM 播放器挂在 SceneTree root 下；当 root 先于架构释放节点时，
## GFAudioUtility.dispose() 会把已经释放的播放器引用放入 TypedArray，触发引擎错误。
## 本适配只在进入框架 dispose 前清除失效引用，其他音频行为仍完全委托 GFAudioUtility。
class_name GameAudioUtility
extends GFAudioUtility


## 清除已由 SceneTree 释放的播放器引用，再执行 GF 的完整释放流程。
func dispose() -> void:
	_clear_released_bgm_player_references()
	super.dispose()


# --- 私有/辅助方法 ---

func _clear_released_bgm_player_references() -> void:
	if not is_instance_valid(_bgm_player):
		_bgm_player = null
	if not is_instance_valid(_bgm_fade_player):
		_bgm_fade_player = null
