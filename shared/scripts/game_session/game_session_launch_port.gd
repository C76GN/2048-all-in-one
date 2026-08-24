## GameSessionLaunchPort: 跨 Feature 的统一对局启动 Interface。
##
## 调用方只提交稳定路径、ID 与严格值快照；game_session Adapter 独占持有
## AppConfigModel 写入、持久化对象解析、启动校验与游戏场景路由。
## Composition Root 必须把同一个 GameSessionLaunchSystem 实例直接注册为本
## Port 的 System alias。
class_name GameSessionLaunchPort
extends GFSystem


# --- 公共方法 ---

## 启动一局新的游戏。
## @param _mode_config_path: 已登记模式配置的绝对资源路径。
## @param _board_topology_snapshot: BoardTopology.to_dict() 的严格值快照。
## @param _seed: 本局固定初始种子。
## @param _seed_source: random 或 manual 的稳定来源标识。
## @param _board_is_custom: 棋盘是否来自玩家编辑器。
func launch_new_game(
	_mode_config_path: String,
	_board_topology_snapshot: Dictionary,
	_seed: int,
	_seed_source: StringName,
	_board_is_custom: bool
) -> bool:
	push_error("[GameSessionLaunchPort] 未安装 game_session Adapter，无法启动新对局。")
	return false


## 按稳定 UUID v7 解析并启动书签对局。
## @param _bookmark_id: 当前玩家目录中的书签稳定身份。
func launch_bookmark(_bookmark_id: String) -> bool:
	push_error("[GameSessionLaunchPort] 未安装 game_session Adapter，无法启动书签。")
	return false


## 按稳定 UUID v7 解析并启动回放。
## @param _replay_id: 当前玩家目录中的回放稳定身份。
func launch_replay(_replay_id: String) -> bool:
	push_error("[GameSessionLaunchPort] 未安装 game_session Adapter，无法启动回放。")
	return false


## 返回当前目录中最新且满足当前模式契约的可恢复书签 ID。
func get_latest_resumable_bookmark_id() -> String:
	push_error("[GameSessionLaunchPort] 未安装 game_session Adapter，无法查询可恢复书签。")
	return ""
