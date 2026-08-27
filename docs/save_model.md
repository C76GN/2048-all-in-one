# 存档模型说明

本文档定义 `2048-all-in-one` 当前的设备账号、玩家 Profile 与设置持久化契约。每个本地账号映射到一个独立主 `GFSaveProfile`，统一最高分、统计、玩家棋盘、书签、发现、成就、回放和方块试验台蓝图；大型 Section 可以由主 Profile 中的 `ChunkManifest` 引用严格派生的 A/B chunk Profiles。设备账号目录和全局设置保持独立文件与独立生命周期。

## 设计目标

1. 每个账号只有一个主玩家 Profile 作为业务可见提交点；普通 Section 直接进入主 `GFSaveDocument`，大型 Section 只在主文档保存 `ChunkManifest`，载荷写入由可信主身份派生的 A/B chunk Profiles。chunk Profiles 不是 Feature 自行维护的旁路文件，也不能独立发布业务可见性。GFStorage 私有拥有每个 logical family 的 metadata、payload 与事务成员，项目不得拼接、枚举或修改这些物理成员。彼此独立的业务操作仍各自拥有明确的类型化终态。
2. 每个 Feature 拥有自己的业务 Schema，持久化 Feature 不解释业务字段。
3. 加载前严格校验 GFStorage logical family、`GFSaveProfile`、typed section 和 Feature Schema；immutable claim 有效时的不可解析载荷只允许丢弃并重建，同源旧 Profile 只允许先备份再重建；私有 family 结构损坏在项目接入 GF 的 source-bound 一次性授权重置前仍直接拒绝并保留证据，未来版本或业务 Schema 错误始终拒绝并保留原档。
4. 复用 `GFSaveProfileUtility`、`GFSaveProfile`、`GFSaveSectionProvider`、`GFSaveProfileOperation`/`GFSaveProfileResult`、`GFSaveRecoveryPolicy`、`GFSaveDocument` 和 `GFStorageUtility`，不在项目层重复实现 generation 合并、重试、flush barrier、事务 apply/rollback、文档封装或原子文件提交。
5. 不保留旧 SaveSlot 或时间戳 Resource 集合的运行时双读分支。

## 文件边界

### 设备账号目录

- 文件：`local_accounts.save`
- 内容：有界本地账号 ID、显示名、创建时间、最近使用时间和当前账号 ID。
- 所有权：`features/player_profiles/scripts/utilities/local_account_catalog_utility.gd`

账号目录是设备身份元数据，不是玩家业务 Profile。它不得保存统计、书签、回放、成就、发现、自定义棋盘或试验台蓝图。账号切换由 `LocalAccountSystem` 编排：先冲刷当前 Profile，再事务加载目标 Profile，失败时保持原账号和原内存图。

创建、切换、重命名和删除只返回一次性 `LocalAccountOperation` / `LocalAccountOperationResult`，不保留同步 CRUD 包装或重复事务实现。目录变更先构造候选 payload，只有 GFStorage typed async 写成功后才交换权威内存状态并由 System 发布业务信号。目录写通过 `GFStorageAsyncRequestOptions` 的 5 秒 caller deadline 进入 `catalog_outcome_unknown`：保留在途 operation、候选 payload 和路径所有权，阻止后续目录变更；同一 operation 的 physical completed 迟到后再按实际存储结果对齐内存，不得把 caller 离开当成已回滚成功。Profile 切换或清理进入 outcome-unknown 时也必须持有同一账号协调锁，直到迟到终态、轮询证据或显式 `request_account_reconciliation()` 完成对账。删除目录的迟到成功不能直接释放账号 ID 与路径：目标 Profile logical family 的物理删除成功后才能解锁；清理超时或失败继续保留所有权和可诊断证据。GF `ready()` 只连接运行期依赖；当前账号 Profile 由 `begin_activation()` 接入 `GameSaveGraphUtility.begin_bootstrap_profile()` 的一次性异步终态，成功后架构才进入 READY。`GameSaveGraphUtility.ready()` 不隐式加载旧 layout 文件；不安装 `LocalAccountSystem` 的工具与测试架构必须自行等待 `begin_bootstrap_profile()` 的 typed completion。关闭时账号 System 先停止 saga 准入，Catalog 随后通过自己的 `begin_quiesce()` 拒绝新目录写并排空已接纳及 caller 离开后的物理写入，SaveGraph 冲刷并注销全部 Profile，最后才允许 GF Storage 依赖关闭；`dispose()` 不再轮询或睡眠等待 I/O。

### 玩家数据

- 文件：`profiles/<account_id>.save`；`account_id` 必须来自已校验的设备账号目录，业务 Feature 不自行拼接路径。
- 格式：`GFStorageCodec.Format.BINARY`
- 完整性：启用 GF 存储元数据和 SHA-256 checksum，校验失败时拒绝读取。
- 磁盘根：规范 `GFSaveDocument`，直接保存 typed sections 与项目 Profile metadata，不含 SaveGraph Scope/Source payload。
- Profile Schema：`GameSaveGraphUtility.PROFILE_SCHEMA_ID` 与 `PROFILE_SCHEMA_VERSION` 是可执行真源。
- 所有权：`features/persistence/scripts/utilities/game_save_graph_utility.gd`

大型 Section 的 chunk logical family 由 `ChunkProfileIdentity` 从已校验的主 Profile ID、主 logical file、Section ID、A/B bank 和规范序号派生；当前逻辑布局为 `chunk_profiles/<main_identity_digest>/<section_id>/<bank>/<index>.save`。持久化 Manifest 不保存主身份、路径、Profile 前缀，也不保存独立的 `chunk_count` 或 `total_bytes` 字段；数量与总量只能从有界 descriptors 重新求得。业务 Feature 不得自行拼接或枚举该布局。

`ChunkManifest` 固定使用 A/B 两个 bank，并施加以下硬预算：单 chunk 不超过 128 KiB，单 Section 最多 64 个 chunk，总载荷不超过 8 MiB。Manifest 只保存自身 schema、Section ID、物理 Section schema 版本、当前可见 bank，以及按序号排列的 `byte_count + SHA-256` descriptors。所有 chunks 必须非空、序号连续，读取时逐块复核大小和摘要。

主 Profile 删除与开发期重置使用同一个复合 cleanup saga。只有主 logical family 的物理删除已确定成功，或 GFStorage 返回规范 `NOT_FOUND`，才按稳定 Provider 顺序清理全部已登记 Manifest Section 派生出的 A/B chunk families；主删除已知失败不得触碰派生数据。caller 超时只结束调用方等待，后台 saga、canonical path 和账号协调所有权必须保持到主删除与全部派生清理收敛；派生清理返回 typed `BUSY` 时等待既有同 scope cleanup 终态后再重试，不以每帧轮询制造重复删除。cleanup settlement 先释放 scope fence 再唤醒 waiter，避免同步信号造成 lost wakeup。若 exact commit 时仍有同 scope sibling Lease，旧 bank 回收意图保留到最后一个 sibling 结算；更新 commit 必须替换其 basis，pre-stage 失败/取消消费安全意图，`SUPERSEDED` 则作废可能删除当前 active bank 的旧意图。

Binary 是契约的一部分。玩家数据包含严格 `int`、`float`、`Vector2i` 和嵌套 Variant；JSON 不能稳定保留普通数字的原始类型。不得仅为可读性切回 JSON，除非同步设计显式类型编码并重写回归测试。

首次启用本地账号时，当前 Storage layout 中唯一的默认 `player_data.save` logical family 可以被一次性收养为首个账号 Profile；目标 Profile 写入成功后才删除旧 family，不保留运行时双读。当前仓库尚无 tag 或正式 release，因此不实现旧 visible-root 到私有 family layout 的运行时兼容双读；未来若已有发布数据，只能提供一次性、显式、离线迁移工具。

当前项目仍处于未发布开发阶段，主 Profile schema 为 13。文档 metadata 精确标识为同一 Profile schema、版本为历史正整数且低于 13，或当前主版本中任一已知 Section schema 低于运行时 Provider 时，启动流程先把完整规范文档保存到带账号身份和旧版本的 `recovery/` 路径，确认备份成功后再通过当前 section 默认值重建活动文件。不读取、转换或合并历史业务字段，不为 v12 及更早版本保留运行时兼容；备份失败时不得覆盖原活动文件。未来版本和未知 schema 仍拒绝且不得破坏性重置。

`ProjectStorageRecoveryPolicy` 只把 GF 已归类为 `GFStorageReadResult.FailureKind.CORRUPT` 的读取视为可尝试重置。当前项目不消费读取结果中的私有字段；immutable claim 有效时先由 GF 拒绝读取，再由 GFStorage 的 logical-family 删除入口清理可变成员，最后以当前默认 section 写回新 Profile。`f6d7b87a` 已新增 `create_family_reset_authorization()` 与同步/异步 `reset_file_family` 入口，可用同一 `GFStorageUtility` 返回的原始 CORRUPT 结果签发绑定 Utility、Storage root 和 canonical logical identity 的一次性授权；自 `7d63ff5a` 起还会冻结签发时的 family observation，任何较新的同 family 写入或修复都会令旧授权失效，消费方必须基于新的原始读取重新取得授权。项目尚未把该能力接入 Settings、账号目录和主 Profile 恢复，因此 catalog、owner 或事务身份等私有 family 结构损坏仍保留证据并失败关闭。后续独立切片只能在类型化 reset 确定成功后写回默认值，不得拼接 `.tmp`、`.bak`、事务证据或其他私有 sidecar。未来 GFStorage 版本、未来 Profile 版本、未知 schema ID、畸形业务文档和当前 section 校验失败必须保留原档并显式失败。

### 设置

- 文件：`settings.sav`
- 所有权：`features/settings/scripts/utilities/game_settings_utility.gd`
- 能力：`GFSettingsUtility`、`GFDisplaySettingsUtility`、`GFSettingsStoreUtility` 和 `GFStorageSettingsStoreUtility`

设置是全局偏好，不参与玩家数据图事务。语言、显示、主音量、视觉主题、音效主题、GF 输入覆盖、棋盘动画响应策略和默认关闭的本地性能诊断同意项不随书签或回放恢复；撤回诊断同意必须立即清空内存轨迹。Composition Root 把 `GFStorageSettingsStoreUtility` 注册为精确 `GFSettingsStoreUtility` alias；该 Store 声明并缓存 Storage 生命周期依赖，`GFSettingsUtility` 在 Store ready 后的 activation 边界加载设置。架构关闭时由 GF Settings 先冻结 mutation admission，再按冻结时的原目标文件顺序冲刷全部 debounce/batch 记录；项目不得读取框架私有队列，也不得把最后一次保存拖到 Storage 已释放后的 `dispose()`。

设置只接受当前 GF Storage codec 和当前设置定义。项目不再在运行时识别旧版 `XOR + Base64 JSON` 载荷；payload、envelope 或 checksum 损坏由 GF 明确拒绝，再按同一 `ProjectStorageRecoveryPolicy` 通过 Settings Store 覆写当前默认设置，未知载荷中的字段不得猜测。GF 已提供与原始 CORRUPT 读取绑定的一次性 family-reset 授权，但设置恢复尚未接入：私有 catalog、owner 或事务身份损坏在架构激活前仍由 Storage 阻止启动进入 READY；Storage 已激活后的显式设置重载可以应用内存默认值，但该加载诊断与持久化健康必须失败，原证据和 logical identity 保持不动并阻断后续写入。后续接入只能由同一 Storage 消费 source-bound 授权和类型化 reset 结果，项目不得解析或修改私有成员。未来存储版本和设置业务错误同样不自动删除。发布后若存在必须保留的数据，只提供显式一次性迁移工具，不把旧格式双读留在主路径。

## GFSaveProfile 结构

`app/scripts/game_architecture_installer.gd` 在 GF `init()` 前把 Feature-owned 业务 Provider 与主 Profile Provider 登记到项目 `GameSaveGraphUtility`。两者通常是同一实例；大型 Section 使用 manifest-backed 适配 Provider，业务 Provider 继续独占字段与校验。项目 `SectionOrder` 只定义主 Profile provider 数组的稳定顺序；`GFSaveProfileUtility` 负责在后续 Profile tick 中按该顺序推进 snapshot preparation、校验和事务 apply。

| 顺序 | `section_id` | 业务 Provider | 主 Profile Provider |
| --- | --- | --- | --- |
| `EARLY` | `progress` | `GameStatsSaveData` | 同业务 Provider |
| `NORMAL` | `bookmarks` | `BookmarkCatalogSaveData`（schema 9） | `BookmarkManifestSaveSectionProvider`（schema 10） |
| `NORMAL` | `custom_boards` | `CustomBoardCatalogSaveData` | 同业务 Provider |
| `NORMAL` | `discoveries` | `TileDiscoverySaveData` | 同业务 Provider |
| `NORMAL` | `tile_blueprints` | `TileLabSaveData` | 同业务 Provider |
| `LATE` | `achievements` | `AchievementSaveData` | 同业务 Provider |
| `LATE` | `replays` | `ReplayCatalogSaveData`（schema 6） | `ReplayManifestSaveSectionProvider`（schema 8） |

每个 Provider 实现统一的项目 envelope，供业务入口、诊断和工具使用：

```gdscript
{
	"section_id": "progress",
	"schema_version": 5,
	"data": {
		# Feature 自己拥有的严格业务数据
	}
}
```

`features/persistence/scripts/data/game_save_section_data.gd` 同时继承 `GFSaveSectionProvider`，把 envelope 中的 `data` 映射为磁盘 `GFSaveSection` 的 `payload` 字段。manifest-backed Section 是明确例外：业务 envelope 仍由 Feature Provider 拥有，主 Profile payload 只保存 `ChunkManifest`。磁盘文档不再嵌套 SaveGraph Source。具体字段校验分别位于 `progress`、`bookmarks`、`board_editor`、`tile_catalog`、`tile_lab`、`achievements` 和 `replays` Feature，禁止把业务 Schema 下沉到 persistence 或 shared。

## GF Profile Coordinator 迁移边界

当前 vendored 开发版本已经提供 `GFSaveProfileTransactionCoordinator`，但项目暂不迁移。`f6d7b87a` 已解除先前的切换恢复 blocker：`switch_profile()` 对 missing/corrupt 目标返回与原事务、domain generation 和来源身份绑定的 `GFSaveProfileRecoveryLease`；`bootstrap_and_switch_profile()` / `adopt_and_switch_profile()` 会重新冲刷来源，必要时消费同一次结构损坏读取签发的 family-reset 授权，并只在目标确定持久化后原子切换身份。source flush、target save、reset 的 outcome-unknown 以及 quiesce/dispose 都保留类型化终态和对账栅栏，恢复完成前来源身份与 section 状态保持不变，不能把来源账号当前 Provider 状态写入目标而造成跨账号数据泄漏。

先前的恢复 blocker 已解除，但项目仍不能直接迁移：bookmarks/replays 的 manifest-backed Provider 必须先读取目标主 Profile，校验 Manifest，再异步物化派生 chunk 并把一次性 lease 放入 load context，随后才能 apply Provider。Coordinator 的 `switch_profile(target_profile_id, context, metadata)` 要求在接纳事务时就交付 context；接纳后先冲刷来源，再直接用该 context 启动严格目标加载，当前没有在其目标主文档读取完成后、Provider apply 前执行项目异步 preflight 的 seam。外部预读与物化可以依靠 `ChunkMaterializationLease.claim_for_manifest()` 对第二次读取的完整 Manifest 做一致性校验并在漂移时失败关闭，但这段异步工作发生在 Coordinator domain admission/reservation 之前，不受其取消、quiesce 和类型化终态管辖；若继续保留项目外层 gate 持有它，又会形成双重事务权威。

因此 `GameSaveGraphUtility` 目前仍拥有活动 Profile 身份、切换 gate、项目恢复决策、chunk preflight、section 事务与对账证据，底层 generation、Storage I/O 和 Provider apply/rollback 继续由 `GFSaveProfileUtility` 拥有。本轮只更新 vendor，不建立 Coordinator 双轨。

当前版本已经允许在共享 Provider domain 仍有另一个活动身份时安全注销目标非活动 Profile，前提是目标不是活动身份且 domain 没有在途事务或 recovery/reconcile lease；原注销 blocker 已解除。该修复只缩小了未来迁移范围，不授权把账号状态机拆成 Coordinator 与项目 transition gate 各管一半。

只有异步 chunk preflight 能在单一事务 authority 下完成准入、取消、迟到完成抑制与类型化结算，并在其后原子进入 target load/apply，才允许安排独立的一次性迁移纵向切片。迁移验收仍必须覆盖 missing/corrupt 目标恢复、preflight 取消/失败/迟到完成、outcome-unknown、rollback failure、quiesce/dispose，以及同 domain 活动身份存在时注销无事务、无 recovery/reconcile lease、无 detached 写的非活动 Profile。Coordinator 应统一接管 Profile 注册、活动身份、source flush、target load、recovery/reconcile lease 和 `mutate_and_persist()`；项目继续拥有本地账号目录、账号 ID 到 logical identity 的映射、chunk Manifest 校验与物化、当前 layout 内的默认 Profile 收养，以及旧业务档备份/重建策略；物理 family 与成员清理由 GFStorage 独占。迁移完成前不得让项目 transition gate 与 Coordinator 双重协调，也不得保留新旧两套运行时入口；注册、切换、section mutation、对账和关闭顺序必须在同一批改动与回归测试中整体切换。

## 事务语义

### 保存

1. System 取得当前 section 副本、构造并严格校验完整替换值，再调用 `GameSaveGraphUtility.request_replace_section_data()`；多 section 事务使用 `request_replace_sections_data()`。
2. section 替换只通过立即返回的一次性 `GameSaveSectionOperation`；Profile 保存、加载和冲刷只通过 `request_save_profile()`、`request_load_profile()`、`request_flush_profile()` 返回的 `GFSaveProfileOperation`；启动与账号切换分别等待 `begin_bootstrap_profile()` completion 和 `activate_profile_async()`。`GameSaveGraphUtility` 不保留同步保存、加载、冲刷、引导或切换包装。玩家 UI 在操作期间禁用重复提交，并以 owner/token 防止页面释放后回写。
3. 项目先保存本次涉及 section 的内存快照并应用候选；同一时刻只允许一个立即事务。项目构造一次性 `GFSaveProfileRequest`，`GFSaveProfileUtility.save_profile()` 立即返回 `GFSaveProfileOperation`，不在请求调用栈里收集或写盘；后续 Profile tick 按 provider 顺序推进 `GFSaveSectionSnapshotOperation`，再按 generation 串行化、合并和有界重试。小型、有严格容量上限的 provider 可以返回已完成 snapshot operation；`ReplayCatalogSaveData` 必须按回放、action 和 checkpoint 预算分片，避免长回放目录在单帧同步序列化。任何目录增长到会占用整帧时都应在 provider 内采用分步 snapshot operation，不得恢复 UI 调用栈同步深拷贝。
4. 对每个 dirty 的 manifest-backed Section，SaveGraph 在主保存请求边界创建 `ChunkSaveLease`。Provider 分步编码冻结业务快照，把 chunks 一次性移交给 Lease；`ChunkProfileUtility` 通过 `GFSaveProfileUtility` 的公开 API 注册严格派生的 chunk Profiles，并按顺序把完整候选写入当前 active bank 之外的 bank。stage 成功只得到尚不可见的候选 Manifest，不能直接更新业务可见状态。
5. Provider 只有在完整 stage 成功后才把候选 Manifest 写入本次主 Profile snapshot。主 `GFSaveProfile` 是唯一可见提交点：只有与 Lease 绑定的主保存 generation 被证明已经持久化，Provider 才把候选 Manifest 设为 active；已知失败、取消或被后续 generation 合并取代的 Lease 不得提交自己的候选 Manifest。未被 active Manifest 引用的 bank 内容不属于玩家可见状态。
6. chunk stage 与主 Profile 保存各自保留 `outcome_unknown` 栅栏。GF 公共 Profile 快照只由 `GameSaveProfileSettlementEvidence` 严格解析：Profile 身份、state、三类 queue、persisted generation、unknown generations、detached count 与 request IDs 任一缺失或错类型都 fail-closed，SaveGraph、ChunkProfileUtility、ChunkSaveLease 和 LocalAccountSystem 不得各自用默认零值解释快照。stage 的任一 chunk 写结果未知时，同一主身份与 Section 不得开始新 stage；只有该精确 chunk Profile 的 evidence 证明完整 idle 后，栅栏才收敛为已知失败，本路径永不提交候选 Manifest，后续必须完整重试。主 Profile 保存结果未知时也保留 Lease、Profile 和 logical identity；精确 persisted generation evidence 证明请求已持久化时才提交 Manifest，否则按已知失败收敛。只有 `COMMITTED` 终态可以推进同 scope 的进程内 bank/epoch 基线；推进发生在释放 stage owner 之前，并以不复制 payload 的标量重基线覆盖 WAITING/READY Lease。基线保留到 Utility dispose，确保栅栏后才创建的 Lease 仍从真实已提交 bank 选择对侧 bank；known failure、superseded 和 cancelled 均不得推进。
7. `GFStorageUtility` 通过临时文件、事务标记和原子提交写入每个 GF logical family。确认成功后 `GameSaveSectionResult` 为 `persisted`；确认失败时项目反向恢复本次 section，并等待回滚状态的补偿保存后再终结。
8. 普通 section 事务的 `outcome_unknown` 同样不表示成功或失败。项目保留候选快照、Profile 与路径所有权，并阻止新的立即写入和账号切换；GF caller-first 后的迟到物理写入收敛后，按 requested/persisted generation 判断晚到成功，或回滚并补偿保存，再以原 transaction ID 发布唯一对账证据。`GameSaveSectionSettlementWaiter` 独占即时 operation、latest-evidence 快路径、signal race 重检和 transaction matching，并只向业务层交付不可变的 `GameSaveSectionSettlementResult`；GameFlow 不得再次解析裸 evidence Dictionary。内存回滚本身失败是 `restart-required` fatal fence，不是可轮询收敛的 reconciliation：继续锁住 Section/Profile，拒绝后续 mutation，并让 quiesce 以明确失败终结，禁止永久 pending 或伪造 flush 成功。
9. 高频统计、发现和成就更新使用 `queue_section_data()` 合并到下一 generation；`flush_profile()` 是覆盖调用时最新 generation 的屏障。“已排队”不等于“已持久化”。若 debounce/flush 在 chunk scope 栅栏期间不能创建 Lease，SaveGraph 必须显式停放该 dirty 意图；精确结算后仅在 manifest-backed Provider 仍 dirty 时自动重臂一次，不按帧忙重试。quiesce 即使先于 debounce 到达，也必须先识别并等待该意图，不能清掉 pending 后把 `ERR_BUSY` 拒绝当成最终 flush。

Profile 删除使用 `GFStorageUtility.delete_file_request_async()` 和 `GFStorageAsyncRequestOptions`。caller 轴可以因 owner、token 或 deadline 先终结；已接纳 delete 此时是 `OUTCOME_UNKNOWN`，项目继续保留账号协调锁与 logical identity。只有同一 `GFStorageAsyncOperation.completed` 的物理终态到达后才释放路径所有权并推进 reconciliation。主删除成功后若 `ChunkProfileUtility` 配置缺失，`GameSaveProfileCleanupSaga.fail_derived_setup()` 进入 typed `derived_setup_failed` 终态并释放路径 ownership；不得在未冻结 derived plan 时误调用完成入口而永久占有路径。未找到 logical family 保持幂等成功语义；项目不得再用 `GFBackgroundWorkUtility` 自建文件删除任务。

业务 System 不得直接调用 `FileAccess`、枚举存档目录或生成旁路文件。

### 加载

1. 启动与账号激活先由 SaveGraph preflight 读取主 Profile，严格解析 `GFSaveDocument`、Profile schema、typed sections 和每个 `ChunkManifest`。Manifest-backed Section 缺失、版本不符或 descriptor 非规范时，在修改业务内存前失败。
2. `ChunkProfileUtility` 按 Manifest 顺序通过 `GFSaveProfileUtility.load_profile()` 读取对应 bank 的 chunk Profiles；每块都必须通过 GF Profile 校验以及 Manifest 的字节数和 SHA-256 复核。任一块失败时丢弃全部已读取 chunks，不把部分载荷交给业务 Provider。
3. Feature codec 在 GF Provider callback 之外严格解码完整记录流，并把已验证业务根装入绑定主 Profile authority 与完整 Manifest 的一次性 `ChunkMaterializationLease`。随后主 `GFSaveProfileUtility.load_profile()` 才按 provider 数组顺序 apply；manifest-backed Provider 只有在第二次读取的 Manifest 与 Lease 完全一致时才能原子 claim，错配不得消费 Lease 或修改业务根。事务 capture 把 provider-private immutable 浅根留在同一 Lease，GF section 只接收小型 rollback sentinel；任一后续 provider 失败时反向根交换并恢复 active Manifest/revision，不把合法大型业务树重新塞进 GF 的持久化值校验器。
4. 直接调用同步返回句柄的 `request_load_profile()` 无法先完成 chunk I/O；存在 manifest-backed Section 时，该公共入口无条件拒绝外部 context，不能把可猜测的 Dictionary key 当成内部授权。生产加载必须走 `begin_bootstrap_profile()` 或 `activate_profile_async()` 的异步 preflight。
5. 缺失文件可以按当前内存默认值恢复并随后保存；未来 schema、未知 section、畸形 metadata 或当前 Feature schema 错误必须明确失败并保留原档。

首次运行没有文件是正常状态。payload/envelope 格式损坏不是首次运行，必须记录拒绝原因并在 immutable claim 有效时按 `reset_allowed` 重建；私有 family 结构损坏在项目接入 GF 的 source-bound 授权重置前必须明确失败并保留证据，未来版本或业务 Schema 错误始终失败且保留原档。

## Feature 数据

### Progress

`GameStatsSaveData` 的业务根严格为 `stats`、`results` 和 `leaderboards`。其中 `stats.best_score` 是最高分唯一真源，同时记录：

- 游玩次数、最佳步数和历史最大方块。
- 总分、总步数、有效步数样本和平均值。
- 累计对局时长、有效时长样本、最近时长、最短单局时长和平均单局时长。
- 目标值、达成次数、达成率与最近一局是否达成。
- 最近一局分数、步数、最大方块和时间戳。

统计按稳定 `mode_id` 和 `BoardTopology.get_stable_key()` 二级 key 组织。棋盘键由语义 ID 与规范化活跃单元内容指纹共同组成，因此相同包围盒但形状不同的棋盘不会共享成绩。`ProgressStatsSystem` 负责数值归一化和统计计算，Provider 负责 section 结构边界。

`results` 保存有界的严格 `GameResultRecordedData`，按结束时间降序稳定排列。每条结果冻结模式、棋盘键、规则集 ID/版本/指纹、初始 seed、最终 canonical state hash、`GameCompetitionEligibility` 快照和结算指标，并用 `result_hash` 拒绝字段篡改。`stats` 根最多包含 64 个模式；字典型模式最多包含 256 个棋盘统计条目，历史自由字典中的标量叶保持原类型。整个 progress section 的边界扫描预算为约 8 MiB/131072 个 Variant 节点；递归深度最多 8、单容器最多 1024 项、文本最多 16384 字符、单个 `PackedByteArray` 最多 64 KiB。协作快照按模式、结果或榜单桶分片，单个 work unit 再收紧到约 256 KiB/4096 个节点，避免一份合法但巨大的自由 Variant 在一帧内完成深复制。精确容量与 schema 版本由数据类常量拥有。调试结果仍可作为可解释的最近记录保留，但不推进统计或成就。

对局时长由 `GameFlowSystem` 只在可操作阶段累计，并在同一次 `ProgressStatsSystem.request_record_game_result()` 类型化异步事务中投影到当前账号的统计摘要；它不是 `GameResultRecordedData` 字段，也不参与 `result_hash`。这样可保持现行严格结果 schema 不变，同时让个人信息页展示累计、最近、最短与平均单局时长。暂停期间不累计；书签恢复和回放续玩遵循各自既有资格规则，回放播放本身不写入进度。

`leaderboards` 保存有界分组与结果；分组身份严格为 `mode_id`、`board_key`、`ruleset_id`、`ruleset_version` 和 `ruleset_fingerprint`。只有 `is_competition_eligible()` 为真的结果可以进入本地榜。调试改写、回放续玩、书签恢复、撤销/重做、自定义棋盘和手动 seed 都会在不可变资格快照中留下失格 reason code。`player_profiles` 先由 `LocalAccountSystem` 把账号顺序与显示元数据冻结为 progress-owned `DeviceProgressAccountCatalogSnapshot`，再把该严格值对象传给 `ProgressStatsSystem.request_device_progress_snapshot()`；它只暴露活动账号 ID 与规范 `account_id/display_name/last_active_at/profile_file_name` 描述符，构造和读取均复制隔离，因此 `progress` 不反向依赖账号目录实现。请求边界先验证输入快照当前账号的规范 Profile 路径与 `GameSaveGraphUtility` 当前路径完全一致，不一致时返回带双方路径和 reconciliation 证据的 `ERR_BUSY`，不得把活动内存错归到另一个账号；一致时当前账号读取尚未落盘也已生效的内存 section，其余账号各提交一次 `GFStorageUtility.load_data_request_async()`，再由 `GFAsyncBatch` 汇总。页面上的模式摘要、分组切换和排行榜排序只复用该快照，不再触发同步磁盘读取；单账号失败形成带错误分类的 partial 快照，不阻断其余账号。批处理即使没有调用方 token 也有 5 秒产品超时；超时返回 `timed_out=true`、`ERR_TIMEOUT` 的 typed partial 快照，释放 owner-bound 连接并隔离迟到读取。该只读聚合不得改写其他账号 Profile。本地榜只是在同一设备上的离线参考，不是 Steam、微信或服务端的线上权威证明。

### Bookmarks

`BookmarkCatalogSaveData` 的业务根只有 `items`。每个 `BookmarkData` 使用 `bookmark_id` UUID v7 作为稳定身份，删除和替换不得依赖时间戳或文件路径。产品目录最多保留最新 16 条；Provider 在复制或解析条目前以 20,000 条作为 GFStorage 一百万 Variant 总预算下的绝对兼容性防线，任何超过产品上限但未越过该防线的当前 schema 历史目录都会先完整校验，再按 UUID v7 降序稳定收敛为最新 16 条，满额新增自动淘汰最旧条目。保存与删除只复制目录数组根并复用已经验证、后续不再原地修改的 envelope；候选通过项目显式 ownership 入口交给 SaveGraph 后，调用方立即放弃全部别名。事务回滚和 `GFSaveSectionSnapshotOperation` 同样冻结旧数组根，正常点击保存不再同步深复制整个历史目录；普通 `replace_section_data()` 仍保留完整调用方隔离。

Bookmarks 是首个分块持久化生产 tracer。业务 `BookmarkCatalogSaveData` schema 仍为 9；主 Profile 中 `bookmarks` typed section 由 `BookmarkManifestSaveSectionProvider` 以物理 schema 10 保存 Manifest，结构化记录流 schema 为 2。`BookmarkChunkCodec` 不再把整条书签编码为单 frame：scalar metadata、四个状态根、固定小批拓扑坐标、单方块、固定 64 KiB 历史字节批和逐步 replay action/checkpoint 分别形成带 4 字节长度前缀、且不超过 128 KiB 的 outer frame；所有 outer key/type/order 固定为规范 `StringName`，任何深复制或 `var_to_bytes()` 之前先拒绝超深、超节点、超文本/PackedArray、对象、环和非有限数。`BookmarkChunkDecoder` 跨 chunk 按 frame budget 增量验证 phase、连续序号、业务形状、规范重编码与尾随字节，并直接构造一次性 `BookmarkCatalogPreparedState`；异步 Profile preflight 按批跨进程帧推进，Provider apply 只交换有限 envelope/cache 根，不再同步执行完整 `BookmarkData.from_dict()`。

书签是可继续游玩的完整局面快照，包括模式、种子、棋盘、规则状态、命令历史、分数、步数、跨定义求商次数和目标状态。它还严格保存从初始种子到书签位置的 typed replay actions/checkpoints 前缀，保证续玩后的完整对局仍能产出逐回合可验证回放，不允许从命令历史再次推断回放语义。视觉主题、音效主题和全局设置不属于书签。

目录 section、单条 `BookmarkData`、命令历史、状态 envelope 和 `GameSessionMetadata` 各自拥有独立 schema 常量，不得混淆。书签冻结 `ruleset_id`、`ruleset_version`、64 字符十六进制 `ruleset_fingerprint` 和资格上下文，恢复前必须与当前模式严格匹配；书签恢复会保留并增加 `bookmark` 失格原因。`rules_states` 是按稳定规则状态键保存的 `Dictionary`；`ratio_resolutions` 只表示规则执行次数，不携带阵营或击杀语义。

棋盘快照的根字段严格为 `schema_version`、`topology` 和 `tiles`，精确版本分别由 `GridModel.SNAPSHOT_SCHEMA_VERSION`、`BoardTopology.SERIALIZATION_SCHEMA_VERSION` 和 `TileState.SERIALIZATION_SCHEMA_VERSION` 拥有。单书签棋盘及其每条命令快照必须通过 `BoardTopology.get_playable_validation_report()`：最多 256 个活跃格和 256 个方块，包围盒宽高分别最多 256、面积最多 256；两格超宽之类的稀疏领域拓扑不得进入可恢复快照。typed replay actions/checkpoints 最多 8192 对且必须一一对应；v6 命令历史的 undo/redo 合计最多 64 条，二进制 envelope 不得超过 2 MiB，v5 迁移输入在完整验证后裁为最近 64 条再生成 v6。拓扑保存规范化活跃坐标；方块只能位于活跃单元，空洞不得以空方块伪装。每个方块显式保存 UUID v7、`definition_id`、当前实际 `capability_recipe_ids` 以及按 Recipe ID 隔离的 `capability_state`；该状态必须可由 GF deterministic Variant serializer 规范编码，Object、循环引用、unsupported Variant 与 NaN/Inf 在 gameplay 领域层直接拒绝。恢复时由 `TileCompositionUtility` 通过 GF Recipe 重建能力实例；不得仅按定义的初始 Recipe 猜测运行时组合。

`target_tile_value` 与 `target_reached` 是当前 schema 的显式契约。恢复时不允许从最高方块猜测缺失状态；目标值必须与当前模式一致。若当前最高方块已达到目标却声明 `target_reached=false`，载荷无效；`target_reached=true` 且当前最高方块较低仍可表示本局曾经达成过目标。

### Custom Boards

`CustomBoardCatalogSaveData` 的业务根只有 `items`。每个 `CustomBoardData` 使用 UUID v7 稳定身份，保存规范化显示名、创建时间、更新时间和严格 `BoardTopology`。产品目录最多保留最新 32 个棋盘；Provider 在复制或解析条目前以 50,000 条作为 GFStorage 一百万 Variant 总预算下的绝对兼容性防线，任何超过产品上限但未越过该防线的当前 schema 历史目录都会先完整校验，再按 `updated_at + UUID` 稳定降序收敛为最新 32 条，满额新增自动淘汰最旧棋盘；单个持久化拓扑必须通过共享可玩报告，不能只检查活跃格数量。

拓扑语义 ID 必须为 `board.player.<uuid>`，不得使用显示名、数组索引或时间戳作为身份。断开的活跃区域是允许的空间语义；是否接受具体尺寸和形状由使用时的 `BoardTopologyTemplate` 复核。编辑器草稿的撤销历史是局部瞬时状态，不进入玩家 Profile section。

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

Replays 是第二个分块持久化生产 tracer。业务 `ReplayCatalogSaveData` schema 为 6；主 Profile 中 `replays` typed section 由 `ReplayManifestSaveSectionProvider` 以物理 schema 8 保存 Manifest，结构化记录流 schema 为 2。`ReplayChunkCodec` 不复制或序列化完整回放根：标量 metadata、初始拓扑坐标批次、单方块终局 frame 和逐步 action/checkpoint 分别形成不超过 128 KiB 的 length-prefixed frame，每次 `advance()` 只产生一个有界 work unit；任意深复制和 `var_to_bytes()` 之前先执行深度、节点、集合、文本、PackedArray、对象/环和非有限数预算，单条仍超限时显式失败。加载由 `ReplayChunkDecoder` 跨 chunk 增量读取并严格验证 phase、计数、批次连续性、业务 schema、frame 规范性和尾随字节，直接构造一次性 `ReplayCatalogPreparedState`；生产 Profile preflight 按帧预算跨进程帧推进，业务 Provider 的 apply 只执行有界根交换，不再同步二次 `ReplayData.from_dict()`。

回放保存“初始条件 + 有效玩家操作序列 + 逐回合确定性 checkpoint + 结束预览”，不是逐帧录像。section、单条 `ReplayData` 和嵌套资格上下文各自拥有独立 schema 常量。从回放继续普通对局会增加 `replay_continuation` 失格原因。`initial_board_topology` 是初始空间契约，`final_board_snapshot` 是结束预览，两者都必须通过当前严格校验和共享可玩拓扑报告；流式 decoder 在构造 PreparedState 前执行同一门禁，不能因 frame 分批而绕过。`actions` 使用 `Array[Vector2i]`，必须与 `MoveCommand` 和 `GFCommandHistoryUtility` 的方向语义一致，并受目录、命令数和 checkpoint 的有界容量约束。

每个 `ReplayData` 必须保存 `ruleset_id`、`ruleset_version`、`ruleset_fingerprint` 和与有效命令一一对应的 `ReplayCheckpoint`。Checkpoint 分别保存 board、gameplay RNG、规则集和完整 state checksum；运行时 UUID 与表现状态不得进入摘要。回放发现首个 OOS 后必须停止步进，并禁止从该回合继续普通对局，不得用结束预览掩盖中途偏离。

## Schema 规则

- Profile 或 section 出现破坏性变化时必须提升对应版本。
- 当前运行时只把当前版本应用到业务状态，不做旧字段猜测、默认降级、字段迁移或双轨写入。
- 同源旧 Profile 只执行通用的完整备份与当前默认 Profile 重建；它不是业务迁移，也不得引入历史 section 类型或字段知识。
- 确需把已发布版本数据转换到新业务 Schema 时，提供一次性离线迁移工具并单独验证；迁移逻辑不得进入运行时主路径。
- 新字段必须同步更新 Provider 校验、数据类、本文档和聚焦测试。
- 持久化路径中不得使用 `ResourceLoader.load()` 恢复不可信 Resource 文件。

## 当前已知限制

- 分块链路当前接入 `bookmarks` 与 `replays`；其他 Section 仍按原有主 Profile typed section 保存。后续迁移必须由对应 Feature 提供自己的流式 codec、增量物化钩子和独立 schema 升级，不能复用书签或回放的业务格式。
- `request_load_profile()` 的立即句柄入口不会自行执行异步 chunk preflight；带分块 Section 的正常加载只支持启动和账号激活流程。若未来需要运行期“重载当前 Profile”，应先增加返回 typed completion 的异步入口，而不是把旧业务内存或未校验 chunks 塞进 context。
- 当前是未发布开发基线，schema 13 采用备份后重置而非兼容迁移。此策略不适用于已有用户数据的发布版本；首次发布后任何破坏性 schema 变化都必须重新决策并提供可验证的一次性迁移方案。

## 诊断与验证

`GameDiagnosticsUtility` 的支持报告继续使用稳定键 `save_graph`，但内容表示当前 GFSaveProfile 的 provider 注册、运行状态、最近加载事务和最近保存事务；该键名不代表项目仍采用 GFSaveGraph API。

修改持久化代码至少运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_chunked_profile_persistence.gd,res://tests/gut/test_chunk_profile_runtime.gd,res://tests/gut/test_chunk_save_lease.gd,res://tests/gut/test_chunk_profile_utility.gd,res://tests/gut/test_chunk_profile_cleanup.gd,res://tests/gut/test_bookmark_chunk_persistence.gd,res://tests/gut/test_replay_chunk_persistence.gd,res://tests/gut/test_game_save_graph_utility.gd,res://tests/gut/test_local_player_profiles.gd" -TimeoutSeconds 300 -MaxLogMB 16 -MaxDefaultLogGrowthKB 128
```

回归测试必须覆盖：

- 所有已登记 Feature provider 的 ID、顺序和 Profile 注册检查。
- typed save/load/flush 终态、generation 合并、有界 retry 与覆盖最新 generation 的 flush barrier。
- section 立即事务的 typed success、全局 busy、已知失败反向回滚与补偿保存。
- IO 超时后的 `STATUS_OUTCOME_UNKNOWN`、迟到成功/失败、按 generation 对账和 profile/path 所有权保留；补偿迟到失败后必须保留待保存 generation，立即 flush 不得复活候选。
- GF Profile 公共快照缺字段、错类型、未知 generation 或 detached request 时统一 fail-closed；内存 `rollback_failed` 必须报告 restart-required 并让 quiesce 明确失败，不能永久等待。
- 普通 Section 只进入主 Profile；书签和回放主 section 只保存 Manifest，载荷只进入由可信主身份派生的 A/B chunk Profiles，不生成 Feature 自定义旁路文件。
- 128 KiB/64 chunks/8 MiB 三层预算、descriptor 顺序/大小/SHA-256 校验，以及错误时不返回部分物化结果。
- inactive-bank 完整 stage、主 Profile 可见提交点、known failure/superseded 不提交，以及 stage/main 两类 outcome-unknown 栅栏与迟到对账。
- exact commit 在 owner 释放前重基线已有 WAITING/READY Lease；无 live sibling 的空窗之后新建 Lease 仍继承 scope bank/epoch，只能写入真实可见 bank 的对侧。
- 栅栏期间 queue 的 dirty generation 被停放，精确结算后无需无关业务更新即可自动保存；flush/quiesce 在 pending 尚未经过 debounce 时也必须等待它收敛。
- `ChunkMaterializationLease` 绑定主 Profile authority 与完整 Manifest，只能由匹配 provider claim 一次；错配不消费，加载失败通过 context 内浅根反向交换业务载荷并恢复 active Manifest/revision，跨账号失败保持原状态。
- 书签 schema 9/Manifest schema 10/流 schema 2 与回放 schema 6/Manifest schema 8/流 schema 2 分离；两种 length-prefixed record stream 都严格拒绝截断、尾随数据和非规范 frame，并按固定 work budget 增量物化为一次性 PreparedState。
- 主 Profile 删除或开发期重置仅在主 logical family 已确定成功或不存在后清理全部 Manifest Provider 的派生 family；known failure 不清理，caller timeout、typed BUSY 和任一派生失败都必须保留 path 到后台 saga 收敛，并允许幂等重试。
- 主删除成功但 derived cleanup 配置缺失时必须产生 typed setup-failed 终态并释放 path ownership，不得留下未冻结 plan。
- Binary 往返后严格类型与稳定 UUID 保留。
- 后期 section 应用失败时早期 section 回滚。
- 同源旧 Profile 先完整备份再以当前默认 section 重建，且运行时不双读旧业务字段。
- immutable claim 有效时，不可解析的 GFStorage logical family 载荷只重建当前默认值；私有 family 结构损坏在独立恢复切片接入同源一次性授权和类型化 reset 终态前不得自动重建，未来存储版本不得自动删除。
- 未来 Profile、未知 schema、畸形 metadata 和当前 section Schema 不匹配时拒绝载荷。
- 保存失败时内存 section 回滚。
- 回放继续游玩清理 redo 历史，设置恢复不污染玩家数据。
