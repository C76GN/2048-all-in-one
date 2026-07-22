# 有证据的行动建议

更新时间：2026-07-22（Asia/Shanghai）

本文件只列能够同时回答“外部证据是什么、当前项目缺什么、谁来拥有、怎样算完成”的建议。证据以[方法](./methodology.md)定义的一手来源为准，当前差距以[项目基线](./project_baseline.md)和[GF 审计](./gf_mapping_audit.md)为准。所有建议均为独立重实现的产品/工程思想；不复制第三方代码、文字、Shader、音频或素材，也不要求修改 `addons/gf`。

优先级含义：P0 是核心操作、可读性、首次体验、确定性和预算基线；P1 是内容深度、留存、复盘和完整跨端体验；P2 是基线稳定后的实验、工具或长尾优化。

## P0：先建立可信的核心体验与验收底座

### P0-01 扩展现有无 Node 的 `MoveData`

- **证据**：[原版 2048](./projects/repo_gabrielecirulli_2048.md)用前一位置、合并来源、新生和分数增量驱动表现；[Godot roguelike 样例](./projects/repo_statico_godot_roguelike.md)以 `ActionResult` 分离状态变化、效果、消息和时间成本。
- **当前差距**：[`MoveData`](../../../features/gameplay/scripts/data/move_data.gd) 已有方向、移动 lane 和反向目标，但 merge count/max/score/type 仍通过字符串字典传递，反馈层再从首项提取汇总；不能把这误报成“完全没有动作结果”。
- **归属 / GF**：扩展项目现有 `MoveData`，不另造平行 `MoveOutcome`；`GFTurnFlowSystem` 和 `GFActionQueueSystem` 只负责阶段与表现消费，不把业务语义上移 GF。
- **验收**：六模式、矩形和稀疏棋盘的有效命令稳定产出 typed transitions、merge count/max、score delta、生成和终态；无效命令保留现有“不入历史 + 明确 reason”；headless、快进和正常表现得到相同 canonical hash。

### P0-02 固定 tile 表现身份、方向与参照系不变量

- **证据**：[2048-in-react](./projects/repo_mateuszsokola_2048_react.md)显示稳定 tile ID 对合并动画重要，其四方向重复实现也提供了反面测试样本；[GUNCHO](./projects/game_r3_guncho.md)开发复盘明确记录相机旋转曾影响弹巢方向理解，最终改回显式左右控制。
- **当前差距**：模型坐标、视口和输入已经分层，但未见移动、撤销/重做、回放全过程的稳定表现 identity，以及相机/布局变化、旋转/镜像、HUD 指向与输入方向的联合黄金测试。
- **归属 / GF**：项目 `gameplay`、presentation 和 tests；复用现有 viewport/input 设施，不静默引入未声明的 `gf.standard.spatial`，也不新增平行坐标真源。
- **验收**：覆盖旋转/镜像等价、数值总量守恒、单回合不可二次合并、无效移动不生成；非合并 tile 的稳定 ID 能跨移动、撤销、重做和回放对应同一语义实体；相机缩放/平移与响应式布局变化不改变 canonical 方向、HUD 指示或同一抽象输入的结果。

### P0-03 固化快速输入与手势拥塞策略

- **证据**：[2048-in-react](./projects/repo_mateuszsokola_2048_react.md)暴露全局手势、裸 timer 和快速输入丢弃风险；[原版 2048](./projects/repo_gabrielecirulli_2048.md)提供键盘/触摸等价输入的最小基线。
- **当前差距**：已有 buffer、block、实时重定向策略，但缺在减少动态、不同帧率和连续滑动下的联合压力回归。
- **归属 / GF**：项目 input/gameplay；复用 `GFInputMappingUtility`、`GFPointerGestureUtility` 和命名 action queue。
- **验收**：自动注入 10–20 ms 间隔连滑，逐策略验证排队、丢弃、重定向符合规格；有效输入到首个主要反馈 P95 小于 50 ms，最终 hash 可重现，手势死区可配置。

### P0-04 统一棋盘 motion/feedback Profile 并提供减少动态

- **证据**：[GF 审计 A1](./gf_mapping_audit.md)确认时长、色彩和幅度散落；[2048-in-react](./projects/repo_mateuszsokola_2048_react.md)的 timer 生命周期反例说明表现策略需要单一所有权。
- **当前差距**：现有 `GameBoardFeedbackProfile` 只覆盖 Shake/Haptic，尚无完整 motion profile 或 reduced-motion 产品设置。
- **归属 / GF**：项目 themes/settings；继续复用 GF action queue、Shader 参数、Shake、Haptic，不建第二套表现管理器。
- **验收**：单一资源控制移动、生成、合并、扩建、冲击、颜色、时长、幅度和启用开关；减少动态设置持久化；切换档位不改变领域结果且队列最终空闲。

### P0-05 增加高对比、色觉安全和非色彩冗余

- **证据**：[2048.cpp](./projects/repo_plibither8_2048_cpp.md)证明纯文本仍可用数字、边框和位置表达状态；[项目基线](./project_baseline.md)确认当前没有完整高对比/色觉设置。
- **当前差距**：已有普通文本 4.5:1、大字 3:1 的静态对比测试，但只有一个产品主题；特殊状态仍可能依赖色彩，且没有用户可选高对比/色觉安全模式。
- **归属 / GF**：项目 themes/settings/UI；复用字体、焦点、输入映射和设置存储，不创建大而全 accessibility Utility。
- **验收**：数值、可合并、危险、目标和失效状态均由文字、轮廓、图标或纹理至少一种非颜色通道表达；关键文字/控件通过既定对比度检查；目标分辨率截图不存在只靠色相区分的状态。

### P0-06 建立领域事件到多通道 feedback recipe 的词表

- **证据**：[Pixel Dungeon](./projects/repo_watabou_pixel_dungeon.md)与[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)以粒子、漂字、闪光、震动、音效和文案的组合表达不同语义，而不是依赖重 Shader。
- **当前差距**：已有 `MOVE/MERGE/HIGH_MERGE/RECORD` 分级和无效移动通知；但事件覆盖、冲突预算与降级表不完整，Controller 当前未传 `is_record`，使 RECORD recipe 静态上不可达。
- **归属 / GF**：项目 themes/feedback；复用 `GFAudioUtility`、Shader/Shake/Haptic、action queue 和对象池。
- **验收**：每类领域事件映射唯一 recipe 与优先级；同帧事件按预算合并或降级；缺素材、减少动态或关闭震动时仍能靠声音、文字或静态视觉辨认。

### P0-07 彻底分离 gameplay RNG 与 cosmetic RNG

- **证据**：[BrogueCE](./projects/repo_brogue_ce.md)在固定提交中明确分流业务与表现 RNG，并只让业务流进入回放校验。
- **当前差距**：已有确定性 seed/回放，但尚无系统证据证明粒子、音高、闪烁和主题装饰永不推进业务随机流。
- **归属 / GF**：项目 gameplay/feedback；复用 `GFSeedUtility` 派生独立流，canonical state 只持业务随机状态。
- **验收**：同一 seed/命令序列在三套反馈 Profile、不同 cosmetic seed 和关闭全部表现时产生相同生成、分数、结束条件及 canonical hash。

### P0-08 升级回放封套并定位首个 OOS

- **证据**：[BrogueCE](./projects/repo_brogue_ce.md)保存 recording 版本、seed、命令并按回合校验 RNG，能拒绝不兼容版本。
- **当前差距**：当前回放/书签功能强，但尚未证实 schema/规则版本、周期摘要与第一次 divergence 的诊断格式。
- **归属 / GF**：项目 replays/diagnostics；复用 `GFCommandHistoryUtility`、SaveGraph、GF clock 和确定性序列化。
- **验收**：封套包含 schema、规则/拓扑版本、seed、命令和 checkpoint hash；篡改一条命令后精确报告首个回合、命令、expected/actual 摘要；不兼容版本明确拒绝而非静默播放。

### P0-09 建立固定 seed catalog 的确定性 CI

- **证据**：[BrogueCE](./projects/repo_brogue_ce.md)以固定 seed catalog 比较生成结果；[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)把 custom/daily seed 变成玩家可见产品。
- **当前差距**：没有覆盖模式、拓扑和支持平台的黄金 seed 目录。
- **归属 / GF**：项目 gameplay tests/diagnostics；复用 GF seed 与 canonical serializer。
- **验收**：六模式覆盖至少三类拓扑，记录开局与固定命令后的 hash；重复运行、正常/无表现运行和支持平台结果一致；有意规则变更必须显式提升规则版本和更新基线。

### P0-10 为现有真实响应式重排补齐端到端矩阵

- **证据**：[Pixel Dungeon](./projects/repo_watabou_pixel_dungeon.md)和[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)为不同最小尺寸与设备形态组织不同界面，而非只做整体缩放。
- **当前差距**：`gameplay_responsive_layout_controller` 与 board editor 已对 desktop/compact/portrait、safe area、HUD/D-pad/棋盘做真实重排，并有分类/inset 单测；缺的是跨分辨率、跨输入的完整任务与截图验收。
- **归属 / GF**：项目 UI/navigation；复用 UI router、焦点和 viewport 信号。`GFViewportUtility` 不替代项目 safe-area/布局策略。
- **验收**：1280×720、960×540、390×844 三类布局快照无遮挡/裁切，交互位于 safe area 且触控目标不小于 44 px；键盘、触摸和手柄能完成同一任务，棋盘不被 HUD/D-pad 遮挡。

### P0-11 实现可跳过、可恢复的分步首次上手

- **证据**：[danqing/2048](./projects/repo_danqing_2048.md)把规则差异放在选择流程中解释；[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)以渐进内容降低复杂系统的首次负担；[Freshly Frosted](./projects/game_r2_freshly_frosted.md)用 144 个手工谜题逐步引入设备，[Dungeons of Dreadrock](./projects/game_r3_dungeons_of_dreadrock.md)把 100 个手工单屏局面组织成真实规则课程，[Wilmot Works It Out](./projects/game_r2_wilmot_works_it_out.md)的开发反思则说明应先删除不服务核心的升级与角色机制。
- **当前差距**：[项目基线](./project_baseline.md)只找到固定 HUD 提示，没有教程状态、情境步骤或“已掌握”持久化。
- **归属 / GF**：项目 tutorial/progress/navigation；复用 UI router、SaveGraph 与输入映射。
- **验收**：首次流程至少覆盖移动、有效合并、无效动作和当前模式目标，步骤尽量嵌入真实局面；可跳过、重看、断点恢复；键盘、触摸、手柄分别通过；完成后不再遮挡熟练玩家主循环，且教程不额外引入与核心无关的升级层。

### P0-12 落地跨平台、规模与表现档位的性能矩阵

- **证据**：[nneonneo/2048-ai](./projects/repo_nneonneo_2048_ai.md)展示节点数、深度与缓存的可测预算；[BrogueCE](./projects/repo_brogue_ce.md)用局部刷新降低固定网格更新，但也说明优化须有负载前提；[R3-B 搜寻台账](./round_03_search.md)只把 Gun Rounds 开发者明确披露的性能与内存泄漏修复计为性能线索，同时拒绝用像素风代替数据。
- **当前差距**：已声明 16.667 ms 帧预算和 50 ms 首反馈目标，也有预热/对象池，但没有设备、棋盘规模和动画策略的正式实测表。
- **归属 / GF**：项目 QA/diagnostics；复用 `GFOperationDiagnosticsUtility`、构建信息和支持报告。
- **验收**：桌面/Web/目标移动平台 × 3×3/4×4/6×6/8×8 × 正常/减少动态/低端档记录 P50/P95 帧时、首反馈和帧尖峰，保存设备/构建信息并给出达标结论。

### P0-13 先用回归验证扩建 Tween 所有权

- **证据**：[GF 审计 A3](./gf_mapping_audit.md)发现 `_expansion_token` 递增但未消费、Tween 无持有句柄；[2048-in-react](./projects/repo_mateuszsokola_2048_react.md)的裸 timer 生命周期是同类反例。
- **当前差距**：连续扩建、恢复和实时重定向可能让多个布局 Tween 竞争，但现有静态证据不足以直接判定 bug。
- **归属 / GF**：项目 board presentation/controller；先测试，失败后才在 Controller 或 `GameBoardAnimationUtility` 修复，不改 GF。
- **验收**：连续两次扩建、一次实时重定向和场景切换后，所有格 scale 为 `Vector2.ONE`，无残留 Tween 或池节点，命名棋盘队列空闲。

### P0-14 让行动后果与失败原因在执行前后都可见

- **证据**：[Pawnbarian](./projects/game_pawnbarian.md)预铺全局危险格，[Into the Breach](./projects/game_into_the_breach.md)公开敌方行动/作用格，[Shotgun King](./projects/game_shotgun_king.md)在行动前显示射程与散布；[Dorfromantik](./projects/game_r2_dorfromantik.md)把合法边界、下一地块与局部任务留在同一视野；[GUNCHO](./projects/game_r3_guncho.md)公开敌人次序，[Card Crawl Adventure](./projects/game_r3_card_crawl_adventure.md)则把多格路径本身变成提交前草稿。它们都把“为什么可行或危险”变成棋盘数据。
- **当前差距**：当前已有无效移动通知和回放，但普通反馈偏执行后；若新增敌人、障碍、特殊格或连锁范围，尚无统一的无副作用 preview/reason 契约。
- **归属 / GF**：项目 gameplay 提供纯查询，board feedback/UI 画 overlay 与原因；复用 BoardTopology、turn flow、Shader 参数工具，不让预览修改 Board/RNG/history。
- **验收**：同一 snapshot 的预览稳定列出受影响格、原因和次序；多格草稿每次增删都更新投影；执行结果与预览一致；取消必须零副作用，状态变化立即清除；高对比、减少动态和手柄焦点下仍可读；经典模式可关闭额外提示。

### P0-15 建立屏幕阅读与字幕共享的 canonical 状态摘要

- **证据**：[Luck be a Landlord](./projects/game_luck_be_a_landlord.md)官方声明屏幕阅读器剪贴板输出和色盲支持；[Backpack Hero](./projects/game_backpack_hero.md)官方页列出互动教程、字幕与多输入；[Freshly Frosted](./projects/game_r2_freshly_frosted.md)把正向语音引导作为产品特征，说明旁白也必须有等价的静态通道。
- **当前差距**：已有焦点、统一文本、翻译和输入映射，但没有棋盘/移动结果的屏幕阅读语义、字幕事件或读取顺序产品契约。
- **归属 / GF**：项目 accessibility/UI/gameplay 定义语义摘要；复用现有文本、焦点、通知、设置和平台 Adapter。是否用 live region、剪贴板或原生辅助技术由平台 Adapter 决定。
- **验收**：摘要至少包含棋盘尺寸/占用、当前焦点、一次移动的合并/分数/生成、目标、危险和可用动作；字幕、教学旁白和屏幕阅读消费同一语义事件；语音可静音且有等价静态提示；开关持久化且不改变回放、资格或时序。

## P1：把确定性底座转化为内容深度与长期价值

### P1-01 明确模式 × 尺寸 × 主题兼容矩阵

- **证据**：[danqing/2048](./projects/repo_danqing_2048.md)让尺寸、合并规则和主题正交选择，并在规则变化时解释/确认。
- **当前差距**：当前组合数量更多，但冲突、目标、生成差异和重开影响不够集中，模式页仍被现有视觉文档列为需深化。
- **归属 / GF**：项目 gameplay/settings/themes；复用内容目录和 UI router，兼容规则来自资源而非 UI 硬编码。
- **验收**：每个组合展示规则摘要、目标、生成变化与兼容状态；破坏当前局面前确认；新增规则资源即可进入矩阵，不修改移动控制器或视图分支。

### P1-02 为多阶段合并定义可读时序

- **证据**：[danqing/2048](./projects/repo_danqing_2048.md)的三合一反馈和[原版 2048](./projects/repo_gabrielecirulli_2048.md)的经典节拍共同说明“先发生什么”必须可见；[Freshly Frosted](./projects/game_r2_freshly_frosted.md)的方向格、设备链和连续输送进一步要求预览与结算共享同一因果次序。
- **当前差距**：Fibonacci、Progressive 等复杂结果在快速输入和减少动态下的因果可读性没有正式验收。
- **归属 / GF**：项目 board presentation；`GFActionQueueSystem` 只执行已排序语义步骤。
- **验收**：统一靠拢→吸附/合并→成长→生成的事件顺序；链式设备或路径模式额外声明每步输入、处理与输出；快进和减少动态可以缩短/跳过表现，但预览顺序、声音提示和最终状态不变。

### P1-03 扩展语义音频和自适应音景

- **证据**：[Pixel Dungeon](./projects/repo_watabou_pixel_dungeon.md)与[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)按区域、动作和强度组织声音，形成视觉之外的状态通道。
- **当前差距**：当前只有 6 个正式 SFX，未发现 BGM、ambient、连锁/危险状态或并发混音层。
- **归属 / GF**：项目 themes/audio；直接复用 `GFAudioUtility` 的 bank、state/switch、crossfade、parameter 和 SFX 并发限制，GF 不缺运行时机制。
- **验收**：移动、合并、连锁、里程碑、危险和失败可听觉区分；多事件不削波/轰鸣；缺 bank 时安静降级；cosmetic pitch/variation 不影响业务 RNG 或回放。

### P1-04 在完整 custom seed 之上新增 daily challenge

- **证据**：[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)提供 custom/daily run；[BrogueCE](./projects/repo_brogue_ce.md)让 seed 可指定、显示和复现；[Card Crawl Adventure](./projects/game_r3_card_crawl_adventure.md)用 weekly crawl 证明轮换周期可以变化，但仍需同一版本与资格契约。
- **当前差距**：模式选择已经支持手动输入、刷新与稳定 hash，初始化/回放也保存完整 seed/RNG；真正缺失的是日期挑战、挑战版本和正式成绩资格，不能把 custom seed 写成待实现。
- **归属 / GF**：项目 challenge/progress/navigation；复用 GF seed/clock、SaveGraph 和平台 Adapter。
- **验收**：可注入时钟下，UTC date/明确周期 + schema/rule version + mode/topology 在支持平台派生同一挑战 seed，到期稳定变化；离线重进一致；daily/weekly 与手动 seed 明确区分，记录资格且不破坏现有 custom seed/回放。

### P1-05 增加正交 challenge modifiers

- **证据**：[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)以可组合 challenge 位形成内容压力，而不是复制整套回合系统。
- **当前差距**：六模式主要改变底层合并/生成规则，缺少可叠加的短局风险、限制和奖励选择。
- **归属 / GF**：项目 gameplay/content；复用 turn flow、Recipe/Capability 和 SaveGraph，modifier 语义不进入 GF。
- **验收**：首批至少三个数据驱动 modifier，定义冲突、顺序、分数倍率和资格；单项及两两组合有确定性测试；新增 modifier 不在移动控制器增加模式分支。

### P1-06 实现有预算、可解释的只读提示

- **证据**：[nneonneo/2048-ai](./projects/repo_nneonneo_2048_ai.md)提供高吞吐评估与 instrumentation；[ovolve/2048-AI](./projects/repo_ovolve_2048_ai.md)证明 hint 与玩家可共用命令入口，也暴露超时风险。
- **当前差距**：没有 project-owned analysis feature、硬 deadline、取消、snapshot 新鲜度或玩家可理解的解释。
- **归属 / GF**：项目 `analysis`；复用 `GFExecutionBudget`、GF clock/seed、async lifecycle 和 diagnostics。
- **验收**：输入是不可变 snapshot；结果含建议方向、主要因素、耗时、节点数和 snapshot ID；支持取消/硬 deadline；状态改变即丢弃旧结果；任意拓扑有通用降级且权威 RNG 不推进。

### P1-07 深化回放浏览器与事件标记

- **证据**：[BrogueCE](./projects/repo_brogue_ce.md)回放支持暂停、变速、逐回合和跳转；其校验机制让复盘同时可诊断。
- **当前差距**：项目已有逐步回放和从回放继续，但视觉规范明确历史页信息架构仍需深化。
- **归属 / GF**：项目 replays/UI；复用 command history、UI router 和虚拟列表（只在规模阈值达到后）。
- **验收**：支持暂停、倍速、逐步、跳转及合并/里程碑/失败事件标记；跳过表现与正常播放最终 hash 相同；三类输入完整操作，当前回合和继续后资格清晰。

### P1-08 建立高频动作带与多输入等价审计

- **证据**：[Pixel Dungeon](./projects/repo_watabou_pixel_dungeon.md)和[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)将高频动作放入快捷栏，并为手柄提供完整导航/虚拟指针；[R3-B 搜寻台账](./round_03_search.md)中的 Gun Rounds 与 FORWARD 又提供 one-button / 单输入压缩的作者证据。
- **当前差距**：撤销、提示、目标、书签、回放的触达和键鼠/触屏/手柄等价尚未形成正式矩阵。
- **归属 / GF**：项目 HUD/input/platform adapter；复用 Input Mapping、Pointer Gesture、焦点和 UI router。
- **验收**：每个高频动作都有等价命令；长按只提供解释或次级操作；焦点不会陷入死区；仅触控手势必须有可见的键盘/手柄替代入口。

### P1-09 实现按配置分组的本地榜与可解释结果页

- **证据**：[2048.cpp](./projects/repo_plibither8_2048_cpp.md)记录移动数、最佳局面与救援；[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)区分 run seed/challenge；[Card Crawl Adventure](./projects/game_r3_card_crawl_adventure.md)把 weekly crawl 与排行榜并列，进一步说明轮换题必须按版本和资格分组。
- **当前差距**：现有 replay/tainted 门控会阻止部分本地结果与回放写入，但只有单一 taint 布尔；undo/redo、bookmark、manual seed、custom board、replay continuation 等没有统一 reason codes，真实排行榜仍未实现，结果记录也缺 seed/资格/hash/challenge。
- **归属 / GF**：项目 progress/result；复用 SaveGraph。线上排行权威留给服务端/平台 Adapter，不由客户端或 GF 裁决。
- **验收**：不可变资格 snapshot + reason codes 覆盖 debug、replay continuation、bookmark、undo/redo、custom board、manual seed、daily；无障碍设置永不失格；按模式/拓扑/版本分榜，结果含 seed/hash/challenge，任何不合格结果都不调用平台提交。

### P1-10 给高频 VFX 定义池容量和安全退化

- **证据**：[Pixel Dungeon](./projects/repo_watabou_pixel_dungeon.md)与[Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md)复用 emitter/ripple/status 等表现对象。
- **当前差距**：已有对象池，但没有 8×8 高密度事件的容量、峰值或池耗尽产品策略。
- **归属 / GF**：项目 presentation/themes；复用 `GFObjectPoolUtility` 和资产 session，领域对象不池化。
- **验收**：8×8 连续高密度合并无孤儿节点和跨场景残留；池耗尽时先减少次要粒子，不丢文字/声音等语义反馈；P95 帧时满足性能矩阵预算。

### P1-11 增加低端 / Shaderless 兼容档

- **证据**：[BrogueCE](./projects/repo_brogue_ce.md)与多个 2048 样本在没有复杂 Shader 的条件下仍靠颜色、字符和节拍清晰表达状态；[Tinyfolks](./projects/game_r3_tinyfolks.md)用近单色稳定版式承载职业与战斗，但也提醒“极简画风”不能替代真实帧时、内存和小字号验收。
- **当前差距**：项目有预热和丰富 Shader，但没有玩家可选的正式低端/无 Shader 路径。
- **归属 / GF**：项目 settings/themes/diagnostics；复用 Shader Parameter Utility 与 Render Warmup，不另建渲染框架。
- **验收**：关闭高成本背景/后处理后，数值、危险、目标和焦点仍清楚，领域结果不变；性能矩阵证明目标设备上 P95 帧尖峰或内存有实质改善。

### P1-12 用有限步关卡包验证目标层与提示预算

- **证据**：[Six Match](./projects/game_six_match.md)让同一核心规则支持 survival/puzzle，明确“六步内完成”、提示资源、死局检测和 puzzle undo/redo；[Wilmot Works It Out](./projects/game_r2_wilmot_works_it_out.md)用 60+ 拼图形成内容进度，[Freshly Frosted](./projects/game_r2_freshly_frosted.md)用 144 个手工谜题逐步扩展设备语法，[Dungeons of Dreadrock](./projects/game_r3_dungeons_of_dreadrock.md)再以 100 个单屏关卡证明少量规则可以靠课程顺序持续深化。
- **当前差距**：当前有六模式、自定义棋盘、结束判定和完整 history，但没有策划关卡、步数预算、显式目标或有限提示经济。
- **归属 / GF**：项目 challenge/gameplay/content；复用 BoardTopology、turn flow、command history 和 SaveGraph。`GFLevelCatalog` 只在不制造平行内容真源时用于 pack、排序与 next/previous；关卡目标、解锁、完成、提示和奖励不进入 GF。
- **验收**：首包至少 10 个可版本化原创关卡，声明初始棋盘、规则、目标、步数和允许动作，并有稳定 pack/order/next/previous；可证明成功/失败/死局；提示不直接改状态且消耗可见；undo/redo/replay 保持确定性。

### P1-13 增加短局主目标、奖励目标与常驻进度节奏

- **证据**：[Into the Breach](./projects/game_into_the_breach.md)把主目标、bonus objective 和剩余回合常驻；[Luck be a Landlord](./projects/game_luck_be_a_landlord.md)用周期房租形成中期压力；[Twinfold](./projects/game_twinfold.md)常驻显示下一成长阈值；[Tinyfolks](./projects/game_r3_tinyfolks.md)用稳定的城镇—出征—回收资源循环连接短期战斗与长期建设。
- **当前差距**：当前核心目标主要是继续合并/达到数值，成就和图鉴属于局外记录，缺单局内每几步可判断的目标节奏。
- **归属 / GF**：项目 goals/challenge/progress；复用 turn flow、通知、HUD 和 SaveGraph，目标内容/奖励归项目。
- **验收**：至少三类原创目标（阈值、步数、布局/区域）能数据驱动组合；HUD 始终显示当前进度和失败原因；回放可重建目标状态；奖励不破坏正式榜资格定义。

### P1-14 做最小局内 build 选择层，而非先建通用卡牌框架

- **证据**：[Twinfold](./projects/game_twinfold.md)用 40+ 技能改变网格决策，[Luck be a Landlord](./projects/game_luck_be_a_landlord.md)用符号/物品形成组合，[Shotgun King](./projects/game_shotgun_king.md)让双方卡牌带来代价，[Cobalt Core](./projects/game_cobalt_core.md)用分叉升级塑造 run；[Stacklands](./projects/game_r2_stacklands.md)证明空间配方能形成 build，[Tinyfolks](./projects/game_r3_tinyfolks.md)则用职业、装备和建筑说明选择层必须先限制范围。
- **当前差距**：模式/主题/图鉴广度很高，但一次 run 中没有离散选择、代价交换或 build 身份。
- **归属 / GF**：项目 gameplay/content/progress；复用 Recipe/Capability、turn flow、seed 和 SaveGraph。不得因这批样本新增 GF 卡牌/遗物业务系统。
- **验收**：首个切片只含 3 个原创升级，每次二选一且效果完全数据化；选择进入命令历史/回放；组合顺序明确；同 seed/命令可重现；每项都可单独禁用并有平衡指标。

### P1-15 做单敌人、单障碍的可回放战术垂直切片

- **证据**：[Twinfold](./projects/game_twinfold.md)让敌人与合并物共享棋盘，[Pawnbarian](./projects/game_pawnbarian.md)以威胁格表达敌方范围，[Into the Breach](./projects/game_into_the_breach.md)要求敌方意图完全公开；[GUNCHO](./projects/game_r3_guncho.md)用小盘、单一弹巢资源和公开敌人次序给出更窄的验证切片。
- **当前差距**：可变/稀疏拓扑和确定性回合很适合承载障碍，但当前没有敌人、攻击、代价或意图数据。
- **归属 / GF**：项目新 gameplay mode/Feature；复用 turn flow、BoardTopology、seed、action queue 和 SaveGraph，敌人 AI/平衡不进入 GF。
- **验收**：仅一种敌人和一种静态障碍；行动次序、目标与受影响格在提交前可见；撤销、书签、回放、快进、无表现路径一致；AI 决策只消费业务 RNG；关闭该模式不影响现有六模式。

### P1-16 试验“两槽先计划、后结算”的动作队列模式

- **证据**：[Shogun Showdown](./projects/game_shogun_showdown.md)让玩家先排列攻击牌，再按可见次序执行；站位、朝向和时机共同形成深度。
- **当前差距**：现有命名 action queue 是生命周期/表现机制，不是玩家可编辑的计划；把两者混为一谈会污染 GF 所有权。
- **归属 / GF**：项目 gameplay 维护可序列化 plan slots/合法性；`GFActionQueueSystem` 只执行确认后的结果表现，turn flow 编排阶段。
- **验收**：两槽原创动作可交换、取消和确认；提交前显示次序/目标；计划写入命令历史并可确定回放；减少动态/快进只改变表现；无合法计划时原因明确。

### P1-17 将未来生成公开为可回放的有限资源队列

- **证据**：[Dorfromantik](./projects/game_r2_dorfromantik.md)把有限地块、下一块预告和空间任务并列；既有候选 [Threes!](./candidates.md)也公开下一张牌。两者说明“将来会来什么、还剩多少”本身可以成为玩家规则，而不只是调试信息。
- **当前差距**：项目已有稳定 seed、撤销和回放，但未见玩家可见的下一生成项、剩余数量或持久化队列；读取预告若临时推进 RNG 还会破坏确定性边界。
- **归属 / GF**：项目 gameplay/challenge；复用 GF seed、Turn Flow、Command History 和 SaveGraph。队列内容、公开规则和计分属于项目，读取预告不得推进权威 RNG。
- **验收**：只在独立模式或 modifier 启用；至少显示当前/下一资源与剩余量；queue/cursor 进入 snapshot、撤销和回放；提交后的生成与预告一致；同 seed/命令完全复现；经典模式零变化；预告同时具备高对比和非色彩编码。

## P2：在数据与基线允许后推进实验和维护深化

### P2-01 建设带来源与许可证的内部内容浏览器

- **证据**：[Godot roguelike 样例](./projects/repo_statico_godot_roguelike.md)提供可浏览游戏内容的开发工具，并反向暴露素材许可需要单独判断。
- **当前差距**：已有图鉴/资产底座，但没有按来源、许可证和发布资格筛选的内部视图。
- **归属 / GF**：项目 diagnostics/asset library；复用内容目录和资产 session，工具 UI 不进入生产路由。
- **验收**：按 ID、标签、主题、来源、许可证筛选；缺来源/许可记录的资产不能进入发布清单；代码、素材、字体和第三方依赖分别记录授权。

### P2-02 增加可暂停、可取消的 AI 自动演示

- **证据**：[ovolve/2048-AI](./projects/repo_ovolve_2048_ai.md)把自动游玩与玩家移动汇入同一入口；[nneonneo/2048-ai](./projects/repo_nneonneo_2048_ai.md)提供分析性能边界。
- **当前差距**：没有自动演示或吸引模式，但已有标准命令、回放和确定性底座。
- **归属 / GF**：项目 analysis/navigation/gameplay；复用 Input Mapping、Turn Flow 和取消生命周期。
- **验收**：演示只提交标准移动命令，可暂停、取消、切回玩家；不直接改 BoardState；固定 seed 可重放；过期分析不执行，正式排行榜资格明确取消。

### P2-03 将有限救援做成明确且不合榜的规则变体

- **证据**：[2048.cpp](./projects/repo_plibither8_2048_cpp.md)提供失败后救援，说明它有产品价值也会改变经典公平性。
- **当前差距**：当前没有失败后代价选择或对应资格语义。
- **归属 / GF**：项目 gameplay/progress；复用 command history、SaveGraph 和 deterministic seed。
- **验收**：救援次数、代价、随机选择和资格进入命令历史/存档；同 seed/命令可重放；结果页明确“不合正式榜”；经典模式默认不被悄悄改变。

### P2-04 仅在 profile 证明后采用 dirty-cell 刷新

- **证据**：[BrogueCE](./projects/repo_brogue_ce.md)只重绘 `needsRefresh` 格，但其固定网格/软件渲染负载与当前 Godot 项目不同。
- **当前差距**：大棋盘更新成本尚无实测证据，不能从竞品直接推导需要优化。
- **归属 / GF**：项目 board presentation/diagnostics；先测量，不修改领域或 GF。
- **验收**：整板更新占比达到预设阈值才实现；优化前后截图、事件序列和 canonical state 一致；目标设备 P95 有显著改善，否则撤回复杂度。

### P2-05 收敛虚拟动作 pulse 重复

- **证据**：[GF 审计 A2](./gf_mapping_audit.md)确认 HUD 与触摸控制器重复维护 press→timer→release；[原版 2048](./projects/repo_gabrielecirulli_2048.md)证明不同设备输入应汇入同一动作语义。
- **当前差距**：`GFVirtualInputSource` 精确 API 只有 press/release/clear，没有 pulse；直接新增 GF API 证据不足。
- **归属 / GF**：先建项目 gameplay input helper，调用端仍拥有动作含义和 hold 时长；多个项目出现稳定相同契约后再反馈 GF。
- **验收**：暂停、取消、场景切换和连续脉冲均保证每次恰好一次 press/release，无卡住动作；HUD/触摸不再各自持有 token/timer 模板。

### P2-06 定义隐私明确的本地产品诊断

- **证据**：[nneonneo/2048-ai](./projects/repo_nneonneo_2048_ai.md)用节点、深度、缓存命中证明可测量才可调优；[项目基线](./project_baseline.md)确认首次完成率、无效滑动、撤销使用和动画偏好尚未闭环；[Tinyfolks](./projects/game_r3_tinyfolks.md)的 Google Play 开发者声明不收集或共享数据，而 [Dungeons of Dreadrock](./projects/game_r3_dungeons_of_dreadrock.md)官方隐私页明确披露移动广告/分析边界，二者都要求产品公开自己的选择。
- **当前差距**：有通用 diagnostics，但没有产品事件 schema、留存期或隐私边界。
- **归属 / GF**：项目 diagnostics/progress；GF 只提供有界诊断机制，产品指标和隐私归项目。
- **验收**：先发布人可读隐私摘要、事件 schema 与留存期限；默认不联网，不含棋盘原始内容或身份信息；可关闭/清除；任何平台分析必须经 Adapter 并与本地核心分离；能回答教程完成、无效输入、撤销偏好和性能预算四类问题。

### P2-07 补齐 GF 能力目录发现性

- **证据**：[GF 审计](./gf_mapping_audit.md)确认 `shader`、`haptic`、`virtual list` 和 `grid path preview` 等 capability 搜索未命中已经安装的精确 API；仓库研究还发现 object pool、command history 和 execution budget 的关键词入口偏弱。
- **当前差距**：这是目录/`primary_classes` 缺口，不是游戏运行时缺口；重复实现会破坏框架边界。
- **归属 / GF**：形成独立 GF 文档/目录反馈，不在本研究批次改 `addons/gf`。accessibility 继续由项目先组合验证。
- **验收**：目录更新后 capability search 能定位 Shader/Render Warmup、Haptic、Virtual List、Object Pool、Command History 和 Execution Budget；每项说明项目仍应拥有的业务边界。

### P2-08 建立带许可元数据的翻译与主题内容包流程

- **证据**：[Shotgun King](./projects/game_shotgun_king.md)官方提供大量翻译及自定义翻译入口，说明小众游戏能用社区内容扩大触达；同时也暴露来源审核与不可信脚本边界。
- **当前差距**：项目已有中英文本、主题资源和内容包基础，但没有社区包 manifest、来源/许可、兼容版本和纯数据约束。
- **归属 / GF**：项目 localization/themes/author tools；复用 content package/asset metadata，不执行第三方脚本或宏。
- **验收**：manifest 记录作者、来源、许可证、schema/兼容版本和文件 hash；只允许白名单数据/资源类型；缺许可或越权引用拒绝导入；翻译完整性、溢出、字体 fallback 与主题对比自动检查。

### P2-09 用原创空间配方试验“位置即构筑”

- **证据**：[Backpack Hero](./projects/game_backpack_hero.md)让位置、邻接和朝向共同决定物品效果；[Stacklands](./projects/game_r2_stacklands.md)用堆叠直接触发配方；[Dorfromantik](./projects/game_r2_dorfromantik.md)用边缘相容与任务让落点产生长期价值。三者都让空间本身成为 build 资源。
- **当前差距**：当前自定义/稀疏棋盘和 Recipe 基础强，但格子邻接主要服务移动/合并，没有 project-owned 的空间配方层。
- **归属 / GF**：项目 gameplay/board editor/content；复用 topology 与 Recipe/Capability。拖放若进入原型，可复用 `GFDragDropUtility` 的会话/落点生命周期，但邻接、堆叠、得分、历史和 UI 仍归项目；不因单个灵感新增 GF inventory 模型。
- **验收**：只做 3–5 个原创配方，支持正交邻接/区域/朝向至少两类条件；编辑器能预览来源与作用格；规则可序列化、撤销和回放；关闭实验包后核心模式零分支变化。

## 许可证与采用边界

- 7 个 MIT 仓库也只用于独立重实现思想；根许可证不能自动证明字体、第三方库、商标或素材可用。
- BrogueCE 的 AGPL-3.0 代码与 CC-BY-SA-4.0 tiles、Pixel Dungeon 系列的 GPL 代码和未逐项审计素材，严格限定为产品机制、分类语言和测试方法参考。
- 未公开源码的商业/独立游戏只观察公开行为；其代码、Shader、音频、图像、文字和数据默认不可复用。
- 任一建议若需要游戏代码、GF 或平台服务改动，应另开 issue/分支/PR；本知识库本轮只保存研究证据与验收定义。
