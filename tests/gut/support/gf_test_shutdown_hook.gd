## GUT 退出前释放 GF 静态缓存，并稳定 Godot 4.7 的全局脚本类清理顺序。
extends GutHookScript


# --- 公共方法 ---

func run() -> void:
	GFExtensionSettings.clear_manifest_cache()
