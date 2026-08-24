## AppConfigModel: 保存下一局对局的跨场景启动状态。
##
## 该 Model 属于 gameplay，用于跨场景传递选定模式、棋盘、种子以及待转换的
## 书签或回放输入；玩家长期设置仍由 settings Feature 独立拥有。
class_name AppConfigModel
extends GFModel


# --- 公共变量 (使用 GFBindableProperty 包装) ---

## 存储当前已选择的游戏模式配置文件的资源路径。
var selected_mode_config_path: GFBindableProperty = GFBindableProperty.new("")

## 存储即将启动的新局使用的完整棋盘拓扑。
var selected_board_topology: GFBindableProperty = GFBindableProperty.new(null)

## 存储当前正在播放或准备播放的回放数据资源。
var current_replay_data: GFBindableProperty = GFBindableProperty.new(null)

## 存储从书签列表选择的、即将用于加载游戏的书签数据。
var selected_bookmark_data: GFBindableProperty = GFBindableProperty.new(null)

## 存储开局时产生的或者用户输入的固定种子，用于重玩同一局。
var selected_seed: GFBindableProperty = GFBindableProperty.new(0)

## 存储待启动对局的 seed 来源；random 与 manual 语义不可互换。
var selected_seed_source: GFBindableProperty = GFBindableProperty.new(
	GameSessionMetadata.SEED_SOURCE_RANDOM
)

## 标记待启动棋盘是否来自玩家棋盘编辑器。
var selected_board_is_custom: GFBindableProperty = GFBindableProperty.new(false)


# --- Godot 生命周期方法 ---

func init() -> void:
	pass
