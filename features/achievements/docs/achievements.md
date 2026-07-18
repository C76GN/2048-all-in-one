# 成就系统契约

`achievements` Feature 提供平台无关的成就定义、进度协调、展示与解锁事件。Steam 和微信 SDK 只能作为后续同步 Adapter，不能成为本地进度真源。

## 所有权

- `AchievementDefinition`：资源化身份、文案、单调指标和目标值。
- `AchievementCatalogUtility`：通过 `GFResourceRegistry`、`ProjectResourceCatalogUtility`、`GFResourceResolverUtility` 和 `GFAssetUtility` 注册并校验定义。
- `AchievementSystem`：把规范玩家数据投影为成就进度。
- `AchievementSaveData`：拥有 SaveGraph 的 `achievements` section。
- `GFQuestUtility`：拥有运行时任务状态机、进度封顶和完成状态，不拥有持久化 schema。
- `AchievementListDialog`：只读 GF UI Route，不直接写进度。

## 数据流

1. `SaveSystem` 先原子提交 `progress` section，成功后发送 `GameResultRecordedData`。
2. `TileDiscoverySystem` 先提交 `discoveries` section，成功后发送 `DiscoveryProgressChangedData`。
3. `AchievementSystem` 从两个规范 section 重新计算单调高水位，而不是盲目累计事件次数。
4. 提议进度先写入 `achievements` section；保存成功后才用每个成就独立的 simple event 推进 `GFQuestUtility`。
5. 本地真源确认完成后发送 `AchievementProgressChangedData` 和 `AchievementUnlockedData`。

这种顺序具有三个约束：重复事件不会重复累计；新增成就可以从历史统计回填；持久化失败时 GF Quest 不会领先于本地真源。

## 当前指标

| Metric | 规范来源 | 语义 |
| --- | --- | --- |
| `game.completed_count` | `progress.stats.*.*.plays` | 全部有效完整对局数 |
| `game.target_reached_count` | `progress.stats.*.*.target_reached_count` | 全部目标达成次数 |
| `game.best_score` | `progress.stats.*.*.best_score` | 跨模式与棋盘最高单局分数 |
| `game.max_tile` | 统计与方块发现记录 | 历史最高方块值 |
| `catalog.tile_composition_count` | `discoveries.tile_compositions` | 已发现组合数 |
| `catalog.board_topology_count` | `discoveries.board_topologies` | 已发现拓扑数 |

指标必须是可从规范数据重建的非递减整数。一次性、可撤销或依赖 UI 展示次数的条件不能直接加入本表；这类成就需要先设计自己的 Feature 真源。

## 定义与版本

`achievement_definition_registry.tres` 是定义目录。新增成就必须提供唯一 `achievement_id`、本地化键、有效 `metric_id`、正整数目标和稳定排序值。

`criteria_fingerprint` 只覆盖成就 ID、指标 ID 和目标值。已有记录的指纹与当前定义不一致时，当前实现丢弃该记录并从规范高水位重新计算，不保留旧条件双读。展示文案、排序、图标和平台 ID 变化不会清空玩家进度。

## 平台边界

后续平台同步只消费 `AchievementUnlockedData` 或启动时的已完成快照，并通过 `GamePlatformUtility` 的显式 bridge contract 调用 Adapter。Adapter 必须使用幂等外部成就 ID；网络失败只形成待重试状态，不能撤销本地完成记录。业务 Feature 不得直接调用 Steamworks、微信 JS API 或开放数据域。

## 验证

聚焦测试：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -TestScripts "res://tests/gut/test_achievement_system.gd" -TimeoutSeconds 180
```

测试覆盖资源目录、严格 section、GF Quest 投影、幂等协调、历史回填以及宽屏/窄屏 UI。
