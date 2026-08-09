extends SceneTree


func _init() -> void:
	call_deferred(&"_wait_then_exit")


func _wait_then_exit() -> void:
	await create_timer(20.0, true, false, true).timeout
	quit()
