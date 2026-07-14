## TestRecordingAudioBackend: 记录主题音效播放请求的无设备测试后端。
class_name TestRecordingAudioBackend
extends GFAudioBackend


# --- 公共变量 ---

var sfx_clip_count: int = 0
var paths: PackedStringArray = PackedStringArray()


# --- 公共方法 ---

## @param clip: 待播放的音频片段。
## @param channel: 目标音频通道。
## @param _context: 播放请求上下文。
func can_handle_clip(clip: GFAudioClip, channel: StringName, _context: Dictionary = {}) -> bool:
	return channel == &"sfx" and clip != null


## @param clip: 待播放的音频片段。
## @param _options: 播放请求选项。
func play_sfx_clip(clip: GFAudioClip, _options: Dictionary = {}) -> GFAudioEmitterHandle:
	sfx_clip_count += 1
	if clip != null:
		var _append_result: bool = paths.append(clip.path)
	return GFAudioEmitterHandle.new()
