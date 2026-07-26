## Headless entry:
## godot --headless --path . --script res://tools/run_game_performance_acceptance.gd
extends SceneTree


const HarnessType = preload(
	"res://tools/game_performance_acceptance_harness.gd"
)


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var harness: GamePerformanceAcceptanceHarness = HarnessType.new()
	var host: Node = Node.new()
	root.add_child(host)
	var checkpoint_report: Dictionary = harness.benchmark_checkpoint_generation()
	var compatibility_report: Dictionary = (
		harness.verify_checkpoint_hash_compatibility()
	)
	var lifecycle_report: Dictionary = await harness.run_lifecycle_plateau(host)
	host.queue_free()
	await process_frame
	var report: Dictionary = {
		&"passed": (
			GFVariantData.get_option_bool(checkpoint_report, &"passed")
			and GFVariantData.get_option_bool(compatibility_report, &"passed")
			and GFVariantData.get_option_bool(lifecycle_report, &"passed")
		),
		&"checkpoint": checkpoint_report,
		&"hash_compatibility": compatibility_report,
		&"lifecycle_plateau": lifecycle_report,
	}
	print("Game performance acceptance: %s" % JSON.stringify(report))
	quit(0 if GFVariantData.get_option_bool(report, &"passed") else 1)
