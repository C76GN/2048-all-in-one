# scripts/ui/mode_selection.gd

## ModeSelection: 模式选择界面的UI控制器。
##
## 该脚本负责动态加载所有可用的游戏模式，为每个模式创建一个
## ModeCard 实例，并处理卡片的选择事件。
extends Control

# --- 导出变量 ---
@export var game_play_scene: PackedScene
## 在编辑器中配置所有可玩模式的资源文件路径。
@export var mode_configs: Array[Resource] = []

# --- 预加载资源 ---
const ModeCardScene = preload("res://scenes/ui/mode_card.tscn")

# --- 节点引用 ---
@onready var mode_list_container: VBoxContainer = %ModeListContainer
@onready var back_button: Button = %BackButton


## Godot生命周期函数：当节点及其子节点进入场景树时调用。
func _ready() -> void:
	_populate_mode_list()
	back_button.pressed.connect(_on_back_button_pressed)

# --- 内部辅助函数 ---

## 动态生成模式卡片列表。
func _populate_mode_list() -> void:
	# 清空容器，以防万一
	for child in mode_list_container.get_children():
		child.queue_free()

	# 遍历配置好的模式列表
	for mode_config_resource in mode_configs:
		if not is_instance_valid(mode_config_resource):
			continue
			
		var card: ModeCard = ModeCardScene.instantiate()
		mode_list_container.add_child(card)
		card.setup(mode_config_resource.resource_path)
		card.mode_selected.connect(_on_mode_selected)

# --- 信号处理函数 ---

## 响应任一模式卡片的点击事件。
func _on_mode_selected(config_path: String) -> void:
	GlobalGameManager.select_mode_and_start(config_path, game_play_scene)

## 响应“返回”按钮的点击事件。
func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()
