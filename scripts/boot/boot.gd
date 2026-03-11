# scripts/boot/boot.gd

## Boot: 游戏的启动入口与总线注册。
class_name Boot
extends Node
# --- 信号 ---

# --- 枚举 ---

# --- 常量 ---

# --- 导出变量 ---

# --- 公共变量 ---

# --- 私有变量 ---

# --- @onready 变量 (节点引用) ---

# --- Godot 生命周期方法 ---

func _ready() -> void:
	var arch := GFArchitecture.new()
	
	# --- 注册 Utility ---
	arch.register_utility(GFStorageUtility, GFStorageUtility.new())
	arch.register_utility(GFSeedUtility, GFSeedUtility.new())
	
	var history_util := GFCommandHistoryUtility.new()
	history_util.max_history_size = 0
	arch.register_utility(GFCommandHistoryUtility, history_util)
	
	arch.register_utility(GameStateUtility, GameStateUtility.new())
	arch.register_utility(TestToolUtility, TestToolUtility.new())

	arch.register_utility(GFLogUtility, GFLogUtility.new())
	arch.register_utility(GFConsoleUtility, GFConsoleUtility.new())
	arch.register_utility(GFUIUtility, GFUIUtility.new())
	arch.register_utility(GFObjectPoolUtility, GFObjectPoolUtility.new())
	
	# --- 注册 Model ---
	arch.register_model(AppConfigModel, AppConfigModel.new())
	arch.register_model(GridModel, GridModel.new())
	arch.register_model(GameStatusModel, GameStatusModel.new())
	arch.register_model(CurrentGameModel, CurrentGameModel.new())
	
	# --- 注册 System ---
	arch.register_system(SceneRouterSystem, SceneRouterSystem.new())
	arch.register_system(SaveSystem, SaveSystem.new())
	arch.register_system(BookmarkSystem, BookmarkSystem.new())
	arch.register_system(ReplaySystem, ReplaySystem.new())
	arch.register_system(GameFlowSystem, GameFlowSystem.new())
	arch.register_system(GridMovementSystem, GridMovementSystem.new())
	arch.register_system(GFActionQueueSystem, GFActionQueueSystem.new())
	arch.register_system(RuleManager, RuleManager.new())
	arch.register_system(GameInitSystem, GameInitSystem.new())
	arch.register_system(PlayerInputSystem, PlayerInputSystem.new())
	arch.register_system(ReplayInputSystem, ReplayInputSystem.new())
	
	# 设置架构并等待其内部初始化完成
	await Gf.set_architecture(arch)
	
	var router := arch.get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.goto_scene("res://scenes/menus/main_menu.tscn")

# --- 公共方法 ---

# --- 私有/辅助方法 ---

# --- 信号处理函数 ---
