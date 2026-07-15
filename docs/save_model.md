# 存档模型说明

本文档记录 `2048-all-in-one` 当前的设置、最高分、轻量统计、书签、回放和 GF save 接入边界。它面向维护者和后续 AI，目的是稳定项目存档语义，并明确哪些数据已经走 GF save slot，哪些数据仍保持 Resource 集合。

## 目标

存档系统应满足四个目标：

1. 玩家数据可以稳定恢复。
2. 示例项目清楚展示 GF 的存储、设置、资源集合和命令历史能力。
3. 存档格式变化必须显式提升 schema；不支持的 schema 直接拒绝，禁止长期保留双轨字段。
4. GF save 接入有明确边界，不重复实现框架能力。

## 当前持久化入口

当前项目有四类持久化入口，其中最高分和轻量统计写入稳定 GF save slot。

### 最高分

入口：

- `features/progress/scripts/systems/save_system.gd`
- `features/progress/scripts/utilities/game_save_slot_workflow_utility.gd`
- `GFSaveSlotWorkflow`
- `GFSaveSlotMetadata`
- `GFSaveSlotCard`
- `GFSaveSlotStorageAdapter`
- `GFStorageUtility`

槽位：

- `GameSaveSlotWorkflowUtility.MAIN_STATS_SLOT_INDEX`
- `schema_id = "game_stats"`
- `schema_version = 2`

结构：

```gdscript
{
	"stats": {
		"<mode_id>": {
			"<grid_size>x<grid_size>": {
				"plays": 0,
				"best_score": 0,
				"best_steps": 0,
				"max_tile": 0,
				"total_score": 0,
				"total_steps": 0,
				"step_samples": 0,
				"average_score": 0,
				"average_steps": 0,
				"target_value": 0,
				"target_reached_count": 0,
				"target_reached_rate": 0,
				"last_target_reached": false,
				"last_score": 0,
				"last_steps": 0,
				"last_max_tile": 0,
				"last_played_at": 0
			}
		}
	}
}
```

当前语义：

- `mode_id` 来自模式资源文件名派生的稳定标识。
- `grid_size` 以 `4x4`、`5x5` 这样的字符串作为二级 key。
- `stats.best_score` 是最高分的唯一真源；项目不维护第二套 `scores` 根字段。
- `stats` 同时记录完整对局次数、最佳步数、历史最大方块、平均表现、目标达成次数和最近一局摘要。
- `GameSaveSlotWorkflowUtility` 在 `ready()` 阶段把 `GFSaveSlotStorageAdapter` 绑定到 `GFStorageUtility`，`SaveSystem` 不直接依赖底层存储工具。
- 加载前必须校验 slot metadata 的 `schema_id` 与 `schema_version`；不匹配时返回空的当前模型，不执行旧字段回退。
- 加载后只投影出 `stats` 根字段，存储元信息和未知根字段不会进入业务模型。
- 保存时 `GameSaveSlotWorkflowUtility` 会生成 GF slot metadata，记录总局数、最高分、模式数量和 `game_stats` schema。
- UI 或调试工具需要展示概要时，应通过 `GFSaveSlotCard` 获取通用槽位摘要，不直接读取底层文件名。

### 设置

入口：

- `features/settings/scripts/utilities/game_settings_utility.gd`
- `GFSettingsUtility`
- `GFDisplaySettingsUtility`

当前语义：

- 显示和语言优先交给 GF display/settings 工具处理。
- `GameSettingsUtility` 负责过滤 `GFStorageCodec.META_KEY`。
- 设置不是书签或回放的一部分，恢复书签不应覆盖全局设置。
- 视觉主题保存为 `appearance/theme_id`，音效主题保存为 `audio/sound_theme_id`。
- 主题 ID 由 `GameThemeUtility` 解析到 `GameThemeRegistry` 中的资源包；书签和回放只记录玩法状态，不记录当前外观主题。

### 书签

入口：

- `features/bookmarks/scripts/systems/bookmark_system.gd`
- `features/bookmarks/scripts/data/bookmark_data.gd`
- `shared/scripts/utilities/saved_resource_collection_utility.gd`
- `GFStorageUtility`

目录：

- `bookmarks/`

文件：

- `bookmark_<timestamp>_<ticks>.tres`

稳定字段：

- `timestamp`
- `mode_config_path`
- `initial_seed`
- `score`
- `move_count`
- `monsters_killed`
- `highest_tile`
- `target_tile_value`
- `target_reached`
- `status_message`
- `extra_stats`
- `rng_full_state`
- `board_snapshot`
- `rules_states`
- `game_state_history`

当前语义：

- 书签是完整局面快照，用于恢复到某个可继续游玩的状态。
- 目标方块值和目标达成状态属于运行时局面的一部分，必须随书签和完整状态快照一起保存恢复，避免继续游戏后重复触发首次达成反馈。
- `file_path` 是运行时辅助字段，由加载流程写回，用于删除；它不是业务存档内容。
- 加载列表按 `timestamp` 降序排列。
- 书签保存和删除不应直接枚举目录，由 `SavedResourceCollectionUtility` 统一处理。
- GF 7 的 `GFStorageUtility.load_resource()` 默认关闭。项目 storage 配置必须显式开启 `allow_resource_loads`，并把允许的 Resource 扩展名和类型提示收窄到当前需要的 `.tres`、`BookmarkData`、`ReplayData`。

### 回放

入口：

- `features/replays/scripts/systems/replay_system.gd`
- `features/replays/scripts/data/replay_data.gd`
- `shared/scripts/utilities/saved_resource_collection_utility.gd`
- `GFCommandHistoryUtility`
- `GFStorageUtility`

目录：

- `replays/`

文件：

- `replay_<timestamp>_<ticks>.tres`

稳定字段：

- `timestamp`
- `mode_config_path`
- `initial_seed`
- `grid_size`
- `final_score`
- `actions`
- `final_board_snapshot`

当前语义：

- 回放是“初始条件 + 玩家有效操作序列 + 结束预览”，不是逐帧录像。
- `actions` 使用 `Array[Vector2i]` 表达方向，必须和 `MoveCommand` / `GFCommandHistoryUtility` 语义一致。
- `file_path` 是运行时辅助字段，由加载流程写回，用于删除。
- 继续游玩时，`ReplaySystem.continue_from_current_step()` 会清理 redo 历史，并通过 `ReplayContinueData` 回到普通对局。

## 共享集合 Utility

`SavedResourceCollectionUtility` 是项目层的轻量 Adapter，用于复用这些流程：

- 确保集合目录存在。
- 以 `prefix + timestamp + ticks` 保存 Resource。
- 加载某个目录下指定类型的 Resource。
- 写回 `file_path`。
- 按 `timestamp` 降序排序。
- 删除资源文件。

约束：

- 业务 System 不应重复实现目录枚举、路径拼接、时间戳排序和删除。
- 新的时间戳 Resource 集合应优先复用该 Utility。
- 该 Utility 只处理“多个 Resource 文件组成的集合”，不负责解释 2048 业务字段。

## 数据边界

不同数据类型不要互相覆盖：

- 设置是全局偏好，不随书签/回放恢复。
- 视觉主题和音效主题是全局偏好，不随书签/回放恢复。
- 最高分是成就统计，不应被加载旧书签回滚。
- 书签是可继续游玩的状态快照。
- 回放是可重演的操作记录。
- 当前对局运行时状态由 Model/System 管理，不应直接写成临时散落文件。

## 统计扩展

当前已由 `SaveSystem.record_game_result()` 在非回放、未污染的游戏结束时记录基础统计：

- 每个模式的游戏次数。
- 每个模式和棋盘大小的最大方块。
- 每个模式和棋盘大小的最佳步数。
- 每个模式和棋盘大小的平均分和平均步数。
- 每个定义了目标的模式和棋盘大小的目标值、目标达成次数与达成率。
- 最近一次对局摘要。

当前稳定字段：

- `plays`
- `best_score`
- `best_steps`
- `max_tile`
- `total_score`
- `total_steps`
- `step_samples`
- `average_score`
- `average_steps`
- `target_value`
- `target_reached_count`
- `target_reached_rate`
- `last_target_reached`
- `last_score`
- `last_steps`
- `last_max_tile`
- `last_played_at`

`SaveSystem.get_game_stats()` 会返回满足当前 schema 默认值和数值范围约束的统计字典。目标达成统计以 `GameStatusModel.target_reached` 代表的“本局曾经达成目标”为准，再用当前最高方块做兜底判断；`target_reached_count` 会被限制在 `0..plays`，确保 `target_reached_rate` 始终位于 `0..100`。当前测试已覆盖单一最高分真源、schema 拒绝、目标达成率归一化、零步对局不污染步数平均值、GF Adapter 持久化和 slot metadata/card。

模式选择页会读取这些统计，用一段短摘要展示当前尺寸下的游玩次数、最佳步数、最大方块、平均表现、目标达成情况和最近一局表现。游戏结束菜单也会展示当前局结果、历史摘要、平均表现和目标达成情况。统计展示不应覆盖模式玩法说明，也不应把书签或回放数据混入全局成绩。

后续游戏完成度仍可以继续增加：

- 更详细的最近一局摘要。
- 真正的胜利状态、胜利继续游玩和胜率。

建议继续扩展 GF 统计槽中的 `stats` 结构，而不是把统计塞进书签或回放：

```gdscript
{
	"stats": {
		"<mode_id>": {
			"<grid_size>x<grid_size>": {
				"plays": 0,
				"best_score": 0,
				"best_steps": 0,
				"max_tile": 0,
				"total_score": 0,
				"total_steps": 0,
				"step_samples": 0,
				"average_score": 0,
				"average_steps": 0,
				"target_value": 0,
				"target_reached_count": 0,
				"target_reached_rate": 0,
				"last_target_reached": false,
				"last_score": 0,
				"last_steps": 0,
				"last_max_tile": 0,
				"last_played_at": 0
			}
		}
	}
}
```

如果继续新增必需的 `stats` 字段，应提升 `STATS_SCHEMA_VERSION` 并更新测试和本文档。确需迁移历史数据时，应提供一次性离线迁移工具；运行时模型不得长期保留旧字段旁路。

## GF Save 接入边界

当前项目已启用 `gf.save` 并用 `GameSaveSlotWorkflowUtility` 展示了最高分/统计的 save slot 工作流。后续如果继续推进到 save graph，应先确认：

1. `SaveSystem` 的最高分/统计字典是否应从单槽位载荷迁移为 GF Save graph 或 save pipeline。
2. `BookmarkData` / `ReplayData` 这类 Resource 集合是否继续由 `SavedResourceCollectionUtility` 管理，还是迁移到 GF Save 的资源序列化能力。
3. 当前 `game_stats` slot、`bookmarks/*.tres`、`replays/*.tres` 是否需要迁移。
4. GF Save 接入后，`README.md`、`docs/roadmap.md`、`project.godot` 的扩展启用状态必须同步；如果恢复 GF Package Manager 安装流，也必须同步 `.gf/packages.lock.json`。

建议顺序：

1. 基于 `tests/gut/test_save_system.gd` 保持当前 schema、单一真源和 slot metadata 校验稳定。
2. 如果需要 save graph，再为当前对局、统计、书签和回放分别设计 `GFSaveScope` / `GFSaveSource` seam。
3. 最后迁移底层保存实现，保持 `SaveSystem`、`BookmarkSystem`、`ReplaySystem` 的公共 Interface 尽量不变。

## 验证要求

修改存档相关代码时至少检查：

- `tests/gut/test_saved_resource_collection_utility.gd`
- `tests/gut/test_save_system.gd`
- `tests/gut/test_replay_continue.gd`
- `docs/save_model.md`
- `docs/roadmap.md`
- `docs/ai_maintenance.md`

高风险改动还应新增聚焦测试：

- 不匹配的统计 schema 会被明确拒绝。
- 保存后的统计载荷只有 `stats` 一个业务根字段。
- 新统计字段默认值正确。
- 书签加载后 `file_path` 可用于删除。
- 回放继续游玩会清理 redo 历史。
- 设置恢复不会污染书签或回放。
