# 存档模型说明

本文档定义 `2048-all-in-one` 当前的设备账号、玩家 Profile 与设置持久化契约。每个本地账号映射到一个独立 GF SaveGraph Profile，统一最高分、统计、玩家棋盘、书签、发现、成就、回放和方块试验台蓝图；设备账号目录和全局设置保持独立文件与独立生命周期。

## 设计目标

1. 每个账号的玩家数据以一个原子文件保存，不出现统计成功但书签、回放或蓝图失败的部分状态。
2. 每个 Feature 拥有自己的业务 Schema，持久化 Feature 不解释业务字段。
3. 加载前严格校验 GFStorage 物理文档、Profile、Scope、Source 和 Feature Schema；不可解析的物理载荷只允许丢弃并重建，同源旧 Profile 只允许先备份再重建，未来版本或业务 Schema 错误直接拒绝并保留原档。
4. 复用 `GFSaveGraphUtility`、`GFSaveDocument`、`GFSaveScope`、`GFSaveDataSource` 和 `GFStorageUtility`，不在项目层重复实现对象图遍历、阶段排序、文档封装、快照回滚和原子文件提交。
5. 不保留旧 SaveSlot 或时间戳 Resource 集合的运行时双读分支。

## 文件边界

### 设备账号目录

- 文件：`local_accounts.save`
- 内容：有界本地账号 ID、显示名、创建时间、最近使用时间和当前账号 ID。
- 所有权：`features/player_profiles/scripts/utilities/local_account_catalog_utility.gd`

账号目录是设备身份元数据，不是玩家业务 Profile。它不得保存统计、书签、回放、成就、发现、自定义棋盘或试验台蓝图。账号切换由 `LocalAccountSystem` 编排：先冲刷当前 Profile，再事务加载目标 Profile，失败时保持原账号和原内存图。

### 玩家数据

- 文件：`profiles/<account_id>.save`；`account_id` 必须来自已校验的设备账号目录，业务 Feature 不自行拼接路径。
- 格式：`GFStorageCodec.Format.BINARY`
- 完整性：启用 GF 存储元数据和 SHA-256 checksum，校验失败时拒绝读取。
- 磁盘根：规范 `GFSaveDocument`；项目 Profile metadata 与 SaveGraph payload 分别位于文档契约定义的位置。
- Profile Schema：`GameSaveGraphUtility.PROFILE_SCHEMA_ID` 与 `PROFILE_SCHEMA_VERSION` 是可执行真源。
- 所有权：`features/persistence/scripts/utilities/game_save_graph_utility.gd`

Binary 是契约的一部分。玩家数据包含严格 `int`、`float`、`Vector2i` 和嵌套 Variant；JSON 不能稳定保留普通数字的原始类型。不得仅为可读性切回 JSON，除非同步设计显式类型编码并重写回归测试。

首次启用本地账号时，唯一的旧默认 `player_data.save` 可以被一次性收养为首个账号 Profile；目标 Profile 写入成功后才删除旧文件，不保留运行时双读。此后每个账号只使用自己的路径。

当文档 metadata 精确标识为同一 Profile schema、版本为历史正整数且低于当前版本时，启动流程先把完整规范文档保存到带账号身份和旧版本的 `recovery/` 路径，确认备份成功后再通过当前 section 默认值原子重建活动文件。不读取、转换或合并历史业务字段；备份失败时不得覆盖原活动文件。

`ProjectStorageRecoveryPolicy` 只把 `ERR_PARSE_ERROR`、`ERR_FILE_UNRECOGNIZED` 和 `ERR_FILE_CORRUPT` 视为可重置的物理载荷失败。项目绝不消费其中的字段；先由 GF 拒绝读取，再通过 `GFStorageUtility.delete_file()` 清理主文件及事务伴生文件，最后以当前默认 section 写回新 Profile。未来 GFStorage 版本、未来 Profile 版本、未知 schema ID、畸形业务文档和当前 section 校验失败必须保留原档并显式失败。

### 设置

- 文件：`settings.sav`
- 所有权：`features/settings/scripts/utilities/game_settings_utility.gd`
- 能力：`GFSettingsUtility`、`GFDisplaySettingsUtility` 和 `GFStorageUtility`

设置是全局偏好，不参与玩家数据图事务。语言、显示、主音量、视觉主题、音效主题、GF 输入覆盖和棋盘动画响应策略不随书签或回放恢复。

设置只接受当前 GF Storage codec 和当前设置定义。项目不再在运行时识别旧版 `XOR + Base64 JSON` 载荷；物理解析、envelope 或 checksum 失败时由 GF 明确拒绝，再按同一 `ProjectStorageRecoveryPolicy` 删除并写回当前默认设置，未知载荷中的字段不得猜测。未来存储版本和设置业务错误不自动删除，并阻断本次运行中的后续设置写入，防止旧程序覆盖新版本文件。发布后若存在必须保留的数据，只提供显式一次性迁移工具，不把旧格式双读留在主路径。

## SaveGraph 结构

`GameSaveGraphUtility` 创建一个根 Scope，并由 `app/scripts/game_architecture_installer.gd` 在 GF `init()` 前登记 Feature section。下表记录所有权和 apply phase；精确 schema 数字只从各数据类常量读取，不在架构文档复制：

| Scope | Phase | Provider |
| --- | --- | --- |
| `player_data` | `NORMAL` | 根作用域，无业务 Source |
| `progress` | `EARLY` | `GameStatsSaveData` |
| `bookmarks` | `NORMAL` | `BookmarkCatalogSaveData` |
| `custom_boards` | `NORMAL` | `CustomBoardCatalogSaveData` |
| `discoveries` | `NORMAL` | `TileDiscoverySaveData` |
| `tile_blueprints` | `NORMAL` | `TileLabSaveData` |
| `achievements` | `LATE` | `AchievementSaveData` |
| `replays` | `LATE` | `ReplayCatalogSaveData` |

每个子 Scope 只有一个稳定 Source：`state`。Source 的数据 Provider 必须实现统一 envelope：

```gdscript
{
	"section_id": "progress",
	"schema_version": 5,
	"data": {
		# Feature 自己拥有的严格业务数据
	}
}
```

`features/persistence/scripts/data/game_save_section_data.gd` 只定义该协议。具体字段校验分别位于 `progress`、`bookmarks`、`board_editor`、`tile_catalog`、`tile_lab`、`achievements` 和 `replays` Feature，禁止把业务 Schema 下沉到 persistence 或 shared。

## 事务语义

### 保存

1. System 取得当前 section 副本并构造完整替换值。
2. `GameSaveGraphUtility.replace_section_data()` 严格校验 Feature 数据。
3. `GFSaveGraphUtility.gather_document()` 按 Scope phase 收集整张图并生成规范 `GFSaveDocument`。
4. `GFStorageUtility` 把文档字典通过临时文件、事务标记和原子提交写入当前账号 Profile。
5. 校验或写入失败时，项目层恢复本次涉及的所有 section 内存快照。

业务 System 不得直接调用 `FileAccess`、枚举存档目录或生成旁路文件。

### 加载

1. `GFStorageUtility.load_data()` 返回 `GFStorageReadResult`，并在成功前校验存储 envelope 与 checksum。
2. `GFSaveDocument.inspect_dict()` / `from_dict()` 严格解析规范文档，项目层再按当前常量校验 Profile metadata；精确识别到同源旧 Profile 时执行“备份后重建”，不进入业务加载管线。
3. `GFSaveGraphUtility.create_document_schema().validate_document()` 严格校验 Scope 和 Source 图。
4. `GFSaveGraphUtility.apply_document(..., transactional_apply = true)` 按 `EARLY -> NORMAL -> LATE` 应用。
5. 任一后期 section 失败时，先前已应用 section 必须回滚，运行时不得暴露部分加载状态。

首次运行没有文件是正常状态。物理格式损坏不是首次运行，必须记录拒绝原因并按 `reset_allowed` 重建；未来版本或业务 Schema 错误必须明确失败且保留原档。

## Feature 数据

### Progress

`GameStatsSaveData` 的业务根严格为 `stats`、`results` 和 `leaderboards`。其中 `stats.best_score` 是最高分唯一真源，同时记录：

- 游玩次数、最佳步数和历史最大方块。
- 总分、总步数、有效步数样本和平均值。
- 累计对局时长、有效时长样本、最近时长、最短单局时长和平均单局时长。
- 目标值、达成次数、达成率与最近一局是否达成。
- 最近一局分数、步数、最大方块和时间戳。

统计按稳定 `mode_id` 和 `BoardTopology.get_stable_key()` 二级 key 组织。棋盘键由语义 ID 与规范化活跃单元内容指纹共同组成，因此相同包围盒但形状不同的棋盘不会共享成绩。`ProgressStatsSystem` 负责数值归一化和统计计算，Provider 负责 section 结构边界。

`results` 保存有界的严格 `GameResultRecordedData`，按结束时间降序稳定排列。每条结果冻结模式、棋盘键、规则集 ID/版本/指纹、初始 seed、最终 canonical state hash、`GameCompetitionEligibility` 快照和结算指标，并用 `result_hash` 拒绝字段篡改。精确容量与 schema 版本由数据类常量拥有。调试结果仍可作为可解释的最近记录保留，但不推进统计或成就。

对局时长由 `GameFlowSystem` 只在可操作阶段累计，并在同一次 `ProgressStatsSystem.record_game_result()` 调用中投影到当前账号的统计摘要；它不是 `GameResultRecordedData` 字段，也不参与 `result_hash`。这样可保持现行严格结果 schema 不变，同时让个人信息页展示累计、最近、最短与平均单局时长。暂停期间不累计；书签恢复和回放续玩遵循各自既有资格规则，回放播放本身不写入进度。

`leaderboards` 保存有界分组与结果；分组身份严格为 `mode_id`、`board_key`、`ruleset_id`、`ruleset_version` 和 `ruleset_fingerprint`。只有 `is_competition_eligible()` 为真的结果可以进入本地榜。调试改写、回放续玩、书签恢复、撤销/重做、自定义棋盘和手动 seed 都会在不可变资格快照中留下失格 reason code。`player_profiles` 可以只读聚合各账号的严格 progress section，但不得改写其他账号 Profile。本地榜只是在同一设备上的离线参考，不是 Steam、微信或服务端的线上权威证明。

### Bookmarks

`BookmarkCatalogSaveData` 的业务根只有 `items`。每个 `BookmarkData` 使用 `bookmark_id` UUID v7 作为稳定身份，删除和替换不得依赖时间戳或文件路径。

书签是可继续游玩的完整局面快照，包括模式、种子、棋盘、规则状态、命令历史、分数、步数、跨定义求商次数和目标状态。它还严格保存从初始种子到书签位置的 typed replay actions/checkpoints 前缀，保证续玩后的完整对局仍能产出逐回合可验证回放，不允许从命令历史再次推断回放语义。视觉主题、音效主题和全局设置不属于书签。

目录 section、单条 `BookmarkData`、命令历史、状态 envelope 和 `GameSessionMetadata` 各自拥有独立 schema 常量，不得混淆。书签冻结 `ruleset_id`、`ruleset_version`、64 字符十六进制 `ruleset_fingerprint` 和资格上下文，恢复前必须与当前模式严格匹配；书签恢复会保留并增加 `bookmark` 失格原因。`rules_states` 是按稳定规则状态键保存的 `Dictionary`；`ratio_resolutions` 只表示规则执行次数，不携带阵营或击杀语义。

棋盘快照的根字段严格为 `schema_version`、`topology` 和 `tiles`，精确版本分别由 `GridModel.SNAPSHOT_SCHEMA_VERSION`、`BoardTopology.SERIALIZATION_SCHEMA_VERSION` 和 `TileState.SERIALIZATION_SCHEMA_VERSION` 拥有。拓扑保存规范化活跃坐标；方块只能位于活跃单元，空洞不得以空方块伪装。每个方块显式保存 UUID v7、`definition_id`、当前实际 `capability_recipe_ids` 以及按 Recipe ID 隔离的 `capability_state`。恢复时由 `TileCompositionUtility` 通过 GF Recipe 重建能力实例；不得仅按定义的初始 Recipe 猜测运行时组合。

`target_tile_value` 与 `target_reached` 是当前 schema 的显式契约。恢复时不允许从最高方块猜测缺失状态；目标值必须与当前模式一致。若当前最高方块已达到目标却声明 `target_reached=false`，载荷无效；`target_reached=true` 且当前最高方块较低仍可表示本局曾经达成过目标。

### Custom Boards

`CustomBoardCatalogSaveData` 的业务根只有 `items`。每个 `CustomBoardData` 使用 UUID v7 稳定身份，保存规范化显示名、创建时间、更新时间和严格 `BoardTopology`。

拓扑语义 ID 必须为 `board.player.<uuid>`，不得使用显示名、数组索引或时间戳作为身份。断开的活跃区域是允许的空间语义；是否接受具体尺寸和形状由使用时的 `BoardTopologyTemplate` 复核。编辑器草稿的撤销历史是局部瞬时状态，不进入 SaveGraph。

### Discoveries

`TileDiscoverySaveData` 的业务根固定为 `tile_compositions` 和 `board_topologies`。方块组合以 `TileCatalogUtility.make_composition_key()` 生成的稳定键去重，保存定义 ID、规范化 Recipe ID、首次发现时间和最高观察值；棋盘以 `BoardTopology.get_stable_key()` 去重，保存语义 ID、内容指纹、首次发现时间和单元数。

静态名称、标签、颜色、纹理、Shader 和音频路径不进入玩家数据，运行时始终从资源目录与当前主题投影。`TileDiscoverySystem` 只在首次发现、最高值提升或新拓扑出现时写入，UI 不得直接修改 section。

### Tile Lab

`TileLabSaveData` 的业务根保存有界方块蓝图。每个蓝图使用 UUID v7 稳定身份，保存显示名、基础 `TileDefinition` 稳定 ID、选中的 `GFCapabilityRecipe` 稳定 ID、预览参数和时间字段。

蓝图不保存运行时能力实例、场景节点、资源路径或普通对局状态。加载后由 `TileCatalogUtility` 和 `TileCompositionUtility` 解析当前目录并重新验证 Recipe 冲突；缺失定义、重复 Recipe、能力覆盖冲突或非法参数必须拒绝，不能通过 fallback 猜测。试验沙盒状态不进入该 section，也不推进 progress、成就或排行。

### Achievements

`AchievementSaveData` 的业务根只有 `records`。每条 `AchievementProgressRecord` 保存稳定成就 ID、达成条件指纹、当前值、最后进度时间和完成时间；静态标题、说明、目标、图标与平台 ID 始终来自 `AchievementDefinition` 资源。

成就进度是 `progress` 与 `discoveries` 的派生高水位。`AchievementSystem` 先原子保存提议记录，再推进扩展拥有的 `GFQuestUtility`；GF Quest 是运行时状态机，不是第二份持久化真源。重复领域事件必须幂等，新成就必须能从规范 section 回填历史进度。详细契约见 `features/achievements/docs/achievements.md`。

### Replays

`ReplayCatalogSaveData` 的业务根只有 `items`。每个 `ReplayData` 使用 `replay_id` UUID v7 作为稳定身份。

回放保存“初始条件 + 有效玩家操作序列 + 逐回合确定性 checkpoint + 结束预览”，不是逐帧录像。section、单条 `ReplayData` 和嵌套资格上下文各自拥有独立 schema 常量。从回放继续普通对局会增加 `replay_continuation` 失格原因。`initial_board_topology` 是初始空间契约，`final_board_snapshot` 是结束预览，两者都必须通过当前严格校验。`actions` 使用 `Array[Vector2i]`，必须与 `MoveCommand` 和 `GFCommandHistoryUtility` 的方向语义一致，并受目录、命令数和 checkpoint 的有界容量约束。

每个 `ReplayData` 必须保存 `ruleset_id`、`ruleset_version`、`ruleset_fingerprint` 和与有效命令一一对应的 `ReplayCheckpoint`。Checkpoint 分别保存 board、gameplay RNG、规则集和完整 state checksum；运行时 UUID 与表现状态不得进入摘要。回放发现首个 OOS 后必须停止步进，并禁止从该回合继续普通对局，不得用结束预览掩盖中途偏离。

## Schema 规则

- Profile 或 section 出现破坏性变化时必须提升对应版本。
- 当前运行时只把当前版本应用到业务状态，不做旧字段猜测、默认降级、字段迁移或双轨写入。
- 同源旧 Profile 只执行通用的完整备份与当前默认 Profile 重建；它不是业务迁移，也不得引入历史 section 类型或字段知识。
- 确需把已发布版本数据转换到新业务 Schema 时，提供一次性离线迁移工具并单独验证；迁移逻辑不得进入运行时主路径。
- 新字段必须同步更新 Provider 校验、数据类、本文档和聚焦测试。
- 持久化路径中不得使用 `ResourceLoader.load()` 恢复不可信 Resource 文件。

## 诊断与验证

`GameDiagnosticsUtility` 的支持报告必须包含 `save_graph` 快照，其中包括图健康度、注册 section、最近加载事务和最近保存事务。

修改持久化代码至少运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_game_save_graph_utility.gd,res://tests/gut/test_progress_stats_system.gd" -TimeoutSeconds 300 -MaxLogMB 16 -MaxDefaultLogGrowthKB 128
```

回归测试必须覆盖：

- 所有已登记 Feature section 的图健康检查与 phase。
- 统计、书签、玩家棋盘、发现进度、成就和回放只生成一个玩家数据文件。
- Binary 往返后严格类型与稳定 UUID 保留。
- 后期 section 应用失败时早期 section 回滚。
- 同源旧 Profile 先完整备份再以当前默认 section 重建，且运行时不双读旧业务字段。
- 不可解析的 GFStorage 物理文档只重建当前默认值；未来存储版本不得自动删除。
- 未来 Profile、未知 schema、畸形 metadata 和当前 section Schema 不匹配时拒绝载荷。
- 保存失败时内存 section 回滚。
- 回放继续游玩清理 redo 历史，设置恢复不污染玩家数据。
