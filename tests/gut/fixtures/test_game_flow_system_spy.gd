## TestGameFlowSystemSpy: 记录流程系统重启调用的测试替身。
class_name TestGameFlowSystemSpy
extends GameFlowSystem


var restart_count: int = 0


func restart_game() -> void:
	restart_count += 1
