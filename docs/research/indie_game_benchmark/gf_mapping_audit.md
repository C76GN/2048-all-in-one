# GF 能力映射与项目使用审计

审计日期：2026-07-22  
依据：GF 9.0.1 固定 vendor、`.gf/project_contract.json`、运行时代码静态检索与 `gf_ai_project.py` API/能力目录查询。此审计只记录研究发现，不修改 `addons/gf` 或游戏代码。

## 已正确复用的机制

| 边界 | 静态证据 | 结论 |
| --- | --- | --- |
| 输入 | 运行时代码未发现直接 `Input.is_action_*`；HUD 与触摸手势通过 `GFVirtualInputSource` 写入抽象动作，主输入由 `GFInputMappingUtility` 消费 | 合规；新增教程、AI 提示或自动回放继续走抽象动作，不注入 Godot `InputMap` 旁路 |
| 场景 | 运行时代码未发现 `change_scene_to_*` 或 `reload_current_scene`；路由由 `SceneRouterSystem`/`GFSceneUtility` 承担 | 合规；新挑战页和结果页应注册 UI route 或场景意图 |
| Shader | 运行时代码未发现直接调用 `set_shader_parameter()`；[棋盘反馈](../../../features/themes/scripts/utilities/game_board_feedback_utility.gd) 先经 `GFShaderParameterUtility` 校验契约，再让 Tween 改变已经确认的材质属性 | 合规；竞品中的冲击、危险或连锁 Shader 可作为主题 Profile，不需要新全局 Shader 管理器 |
| 音频 | 正式运行时未直接创建 `AudioStreamPlayer`；[主题 Utility](../../../features/themes/scripts/utilities/game_theme_utility.gd) 通过 `GFAudioBank` 与语义事件播放 | 合规；GF 已支持 BGM、ambient、SFX 上限、crossfade、parameter/state/switch，自适应音频应先用现有 API |
| 玩家存档 | 玩家统计、书签、回放、图鉴、成就和自定义棋盘进入统一 SaveGraph | 合规；每日挑战和局内构筑应新增严格 section/provider，而非直接 `FileAccess` |
| 时间与随机 | 玩法层使用 `GameClockUtility`/GF clock 和确定性 seed；直接 `Time.get_ticks_*` 只在 Boot/显式 QA 工具中出现 | 合规；每日挑战可由日期解析出公开 seed，但回合结果仍只消费冻结后的 seed |
| 表现生命周期 | 单方块 Tween 由 [Tile](../../../features/gameplay/scripts/components/tile.gd) 返回，移动批次由 [GameBoardAnimationUtility](../../../features/gameplay/scripts/utilities/game_board_animation_utility.gd) 接入 GF 命名 Action Queue | 不是重复造队列；保留现有取消、阻断与实时重定向语义 |
| 作者工具文件 | `AssetSourceExclusionIndex` 直接读写 JSON，但它属于素材评审/作者工具索引，不是玩家数据 | 边界合理；不应强行塞进玩家 SaveGraph |

## 项目级深化点

### A1：棋盘表现参数仍分散在脚本常量中

[Tile](../../../features/gameplay/scripts/components/tile.gd) 固定保存移动、生成、合并、成长和退场时长，以及合并/转化闪色；[GameBoardController](../../../features/gameplay/scripts/controllers/game_board_controller.gd) 固定保存棋盘 intro 时长；[GameBoardFeedbackUtility](../../../features/themes/scripts/utilities/game_board_feedback_utility.gd) 固定保存生成、合并、转化色和多组冲击时长/强度，而现有 [GameBoardFeedbackProfile](../../../features/themes/scripts/data/game_board_feedback_profile.gd) 只资源化 Shake 与 Haptic。

这不构成 GF 误用，但造成三项真实成本：主题无法完整改变反馈语言；减少动态只能在多个脚本分支处理；竞品研究得到的节奏参数难以 A/B 或做低端设备降级。建议由项目新增单一棋盘 motion/feedback Profile，主题持有颜色、时长、幅度和启用开关；现有 `GFActionQueueSystem`、`GFShaderParameterUtility`、`GFShakeUtility` 与 `GFHapticUtility` 继续拥有机制。

### A2：虚拟动作“按下—延迟—释放”重复两次

[HUD `_inject_hud_action`](../../../features/gameplay/scripts/ui/hud.gd#L644) 与 [触摸 `_inject_touch_action`](../../../features/gameplay/scripts/controllers/board_world_viewport_controller.gd#L719) 都维护 token、调用 `GFVirtualInputSource.press()`、创建暂停期间可运行的 `SceneTreeTimer`、通过 `GFSignalUtility.connect_once()` 释放。

精确 API 检查确认当前 `GFVirtualInputSource` 只提供 `press/release/clear`，没有 one-shot pulse。重复逻辑应收敛为项目 gameplay 内的小型输入脉冲 Adapter 或纯 helper；动作含义和 hold 时长仍由调用端传入。只有出现多个项目都需要且生命周期语义稳定时，才把 `pulse()` 作为 GF 反馈候选。

### A3：扩建 Tween 的所有权需要回归验证

[GameBoardController `_animate_expansion`](../../../features/gameplay/scripts/controllers/game_board_controller.gd#L868) 创建局部 Tween，不保存句柄；`_expansion_token` 只递增，当前源码未发现消费点。节点销毁会终止绑定 Tween，因此尚不能据此判定泄漏，但连续扩建/恢复/切换场景时可能出现多个布局 Tween 竞争。

建议先加研究驱动的回归用例：连续触发两次扩建和一次实时重定向后，所有格子 scale 回到 `Vector2.ONE`，池中节点无动画残留，命名棋盘队列空闲。若失败，修复应在项目 `GameBoardAnimationUtility` 或 Controller 的显式句柄所有权内完成，不修改 GF。

## 研究建议去重核对

在把竞品发现转为行动项前，又针对高频方向做了一轮静态反查。以下能力不能写成“从零实现”；正确建议是扩展、补齐或增加回归。

| 方向 | 已存在的项目证据 | 真正缺口与正确动作 |
| --- | --- | --- |
| 动作语义 | [`MoveData`](../../../features/gameplay/scripts/data/move_data.gd) 已含 direction、moved lanes、reverse target map；[`GridMovementSystem`](../../../features/gameplay/scripts/systems/grid_movement_system.gd) 还以字符串 Dictionary 传 merge count/max/score/type | 扩展现有 `MoveData` 为 typed transitions/汇总，不另建平行 `MoveOutcome`；无效移动已通知且不入历史，应保留 |
| 反馈层级 | [`GameBoardFeedbackUtility`](../../../features/themes/scripts/utilities/game_board_feedback_utility.gd) 已分 `MOVE/MERGE/HIGH_MERGE/RECORD`，无效移动也已有通知 | 补全 recipe 表与冲突预算；Controller 当前没有传 `is_record`，先用回归证明并接通不可达的 RECORD 路径 |
| custom / daily seed | [`mode_selection.gd`](../../../features/navigation/scripts/menus/mode_selection.gd) 已支持手动输入、刷新和稳定 hash；[`ReplayData`](../../../features/replays/scripts/data/replay_data.gd) 保存初始 seed | custom seed 已完成；新增的是可注入 UTC 日期 + schema/rule/mode/topology 的 daily challenge、离线一致性和资格模型 |
| 响应式布局 | [`GameplayResponsiveLayoutController`](../../../features/gameplay/scripts/controllers/gameplay_responsive_layout_controller.gd) 已对 desktop/compact/portrait、safe area、HUD/D-pad/board 做真实重排，编辑器也有独立 Controller 和测试 | 补 1280×720、960×540、390×844 截图/实例化回归、44 px 触控目标、safe area 和完整控制器焦点路径；不重建布局系统 |
| 快速输入 | [`GameInputProfileUtility`](../../../features/settings/scripts/utilities/game_input_profile_utility.gd) 已定义 buffered/block/realtime-retarget，[`GameBoardAnimationUtility`](../../../features/gameplay/scripts/utilities/game_board_animation_utility.gd) 经 GF action queue 清队列/重同步 | 补 10–20 ms burst 的端到端回归，分别验证接收/丢弃/重定向数量、旧 completion、池化 tile 和最终 GridModel；GF 无缺口 |
| 音频 | [`GameAudioTheme`](../../../features/themes/scripts/data/game_audio_theme.gd) 与正式 audio bank 已有六类语义 SFX、音量/音高变化，播放统一走 `GFAudioUtility` | 新增 BGM/ambient/自适应 state、独立音量、并发/ducking/overflow 与 Web 解锁验收；不建平行音频管理器 |
| 排行资格 | `GameFlowSystem` 已阻止 tainted/replay 的部分结果和回放写入，但只保存单一 taint 布尔；结果记录不含 seed/资格/reason/hash/challenge | 建不可变 eligibility snapshot + reason codes；无障碍永不失格；平台/服务端是线上权威，SaveGraph 只保存本地状态 |

这轮核对同时确认：正式性能 budget、预热和对象池已存在，但没有 P50/P95/P99 benchmark harness；完整 snapshot/equality 已存在，但没有只读 AI hint；回放有 seed/actions/final snapshot 和逐步播放，但没有 step hash、首个 OOS、simulation/content fingerprint 或固定 seed corpus。

## 追加轮次 API 边界复核

摆放、路径与手工关卡样本容易诱发“看到相似名词就接入框架”的误判。本轮按精确 API、项目 contract 和当前静态使用三层复核：

| 研究方向 | 已安装事实 | contract / 当前使用 | 正确判断 |
| --- | --- | --- | --- |
| 拖放 / 堆叠 | `GFDragDropUtility` 位于 `gf.standard.input`，管理拖拽会话、落点注册、命中排序、drop/reject/cancel 和调试快照 | `gf.standard.input` 已声明 required；当前游戏代码未使用该 Utility | 未来若验证拖放玩法，可复用会话生命周期；它不读取输入、不移动 Node、不保存历史，也不拥有放置、堆叠、配方或计分语义 |
| 关卡包 | `GFLevelCatalog` 位于 `gf.extension.domain`，提供 entry、pack、排序及 next/previous 查询 | `gf.extension.domain` 已声明 required；当前内容/进度没有使用该 Catalog | 只有在不制造平行内容真源时才评估采用；目标、步数、解锁、完成、提示、资格与 SaveGraph section 仍归项目 |
| 路径 / 坐标变换 | `GFGridPathMath2D` 提供 BFS、A*、分步 A*、视线简化和 flow field；`GFGridTransform2D` 提供旋转、镜像和方向纯映射 | `gf.standard.spatial` 已安装但未在 required/optional packages 声明，当前项目代码也未使用 | 不能写成“当前可直接复用”；先由项目 `BoardTopology` 邻接纯查询承载。出现跨模式稳定需求后，才显式评估 package、contract 与 composition root |
| 目录发现性 | capability search `grid path preview` 无结果，但精确 API 存在 | 不影响当前运行时 | 这是关键词和 package 发现性问题；既不要求当前项目采用 spatial，也不构成重造路径 API 的理由 |

当前 [`BoardTopology`](../../../features/gameplay/scripts/data/board_topology.gd) 仍是四向、可含空洞且按连续 lane 结算的项目领域真源；视口缩放/平移、HUD、输入动作和模型方向已经分层。[GUNCHO](./projects/game_r3_guncho.md) 的开发者复盘提供了直接反例：让 3D 相机旋转影响方向资源理解后，团队改回显式左右控制。后续应补“相机或布局变化不改变 canonical 方向”的回归，而不是新增平行坐标系统。`GFGridTransform2D` 即使未来被声明，也只负责纯变换，不拥有相机、HUD、输入或玩法参照系。

## GF 发现性反馈候选

能力目录查询结果与精确 API 查询存在落差：

| 查询 | capability-search | 已安装精确 API | 判断 |
| --- | --- | --- | --- |
| `shader` | 无结果 | `GFShaderParameterUtility`、`GFRenderWarmupUtility` 位于 `gf.standard.display` | 目录关键词/主类缺口，不是运行时缺口 |
| `haptic` | 无结果 | `GFHapticUtility`、`GFHapticPreset`、`GFHapticBackend` 位于 `gf.extension.feedback` | 目录关键词/跨包发现性缺口 |
| `virtual list` | 无结果 | `GFVirtualListModel` 位于 `gf.standard.ui` | UI capability 的关键词/主类覆盖不足 |
| `grid path preview` | 无结果 | `GFGridPathMath2D` / `GFGridTransform2D` 位于未声明的 `gf.standard.spatial` | 目录关键词/包选择信息不足；不代表当前项目应立即接入 |
| `accessibility` / `reduced motion` / `colorblind` | 无结果 | 输入、焦点、文本适配、主题和设置机制分别存在，但没有一个声明式产品策略 API | 先由项目组合；待至少两个项目出现相同稳定契约再判断框架能力 |
| `leaderboard` | 命中 `platform-adapters` | `GFInstaller`、存储/网络 backend、异步终态 | 正确：GF 只提供边界，线上权威与排行规则属于项目/服务端 |

建议先为 GF 能力目录补充 display/feedback/UI 的关键词和 `primary_classes`，让未来代理能先发现现有机制。accessibility 不宜直接新增“大而全 Utility”；本项目应先实现减少动态、高对比、震动开关和输入提示策略，沉淀后再反馈可复用契约。

## 不建议的重复实现

后续竞品灵感落地时，以下做法会与现有机制重复或破坏边界：

- 为每日挑战另写随机数、回合日志或存档文件；应复用 seed、回放和 SaveGraph。
- 为新 VFX 建第二套全局 Tween/队列管理器；应复用命名 Action Queue 与现有棋盘表现 Adapter。
- 为新音色直接放置全局 `AudioStreamPlayer`；应扩展语义事件、bank、state/switch 或主题包。
- 为关卡/模式写硬编码场景分支；应继续用模式注册表、规则资源和内容目录。
- 在 gameplay/UI 直接调用平台排行榜、成就或云存档 SDK；应经过 `platform_runtime` 的项目 Adapter。
- 因一个游戏的遗物、敌人、教程或评分规则而新增 GF Model/System；这些首先是项目业务 Feature。
