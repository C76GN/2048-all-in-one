@tool
extends EditorPlugin


# --- 常量 ---

const _EXPORT_PLUGIN_SCRIPT: Script = preload(
	"res://addons/wechat_minigame_smoke_export/wechat_minigame_smoke_export_plugin.gd"
)


# --- 私有变量 ---

var _export_plugin: EditorExportPlugin = null


# --- Godot 生命周期方法 ---

func _enter_tree() -> void:
	_export_plugin = _EXPORT_PLUGIN_SCRIPT.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if is_instance_valid(_export_plugin):
		remove_export_plugin(_export_plugin)
	_export_plugin = null
