## 运行微信小游戏冒烟产物验证器的命令行入口。
extends SceneTree


# --- 常量 ---

const _VERIFIER_SCRIPT = preload(
	"res://tools/wechat_minigame_artifact_verifier.gd"
)


# --- Godot 生命周期方法 ---

func _init() -> void:
	var artifact_root: String = ""
	var inspect_pack: bool = false
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < arguments.size():
		match arguments[index]:
			"--artifact-root":
				index += 1
				if index < arguments.size():
					artifact_root = arguments[index]
			"--inspect-pack":
				inspect_pack = true
		index += 1

	var verifier: _VERIFIER_SCRIPT = _VERIFIER_SCRIPT.new()
	var report: Dictionary = verifier.verify_artifact(artifact_root, inspect_pack)
	print(JSON.stringify(report))
	var ok_value: Variant = report.get("ok", false)
	var ok: bool = ok_value if ok_value is bool else false
	quit(0 if ok else 1)
