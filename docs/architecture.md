# 架构说明

本项目是 Godot 4.7 与 GF Framework 9.x 的 2048 示例项目。目录严格采用 GF 内置 `Feature-Cohesive` 契约：业务能力优先内聚在 Feature 内，GF 的 Model、System、Utility、Controller 等是 Feature 内部的逻辑层，不再作为项目根目录的类型桶。

## 目录契约

`gf_project_profile.json` 复制并收紧了 GF 内置 `feature_cohesive_v1.json`：

- `app/`：启动入口、Composition Root 和跨 Feature 装配。
- `features/<feature_id>/`：单个业务能力拥有的脚本、场景、资源、文档和局部工具。
- `shared/`：确实被多个 Feature 复用的契约、基础算法、UI 原语、素材和 Utility。
- `tests/`：跨 Feature 契约测试、集成测试和回归测试。
- `tools/`：项目级验证、构建和维护工具。
- `docs/`：项目级架构、规范和维护文档。
- `generated/`：可再生源码和中间产物；不得混入手写模块。
- `addons/`：vendored GF 与 GUT，不属于项目业务 Feature。

旧的 `scripts/`、`scenes/`、`resources/`、`assets/` 和 `asset_library/` 根目录不再承载项目文件，也不提供旧路径别名。

所有手写路径使用小写 `snake_case`。项目脚本的 `class_name` 必须由文件名直接执行 `to_pascal_case()` 得到，不为 UI、HUD 等缩写保留大小写例外，例如 `game_ui_controller.gd -> GameUiController`、`hud.gd -> Hud`。`features/asset_library/resources/source_packs/**` 是明确隔离的上游原始素材区，为保存来源真实性而不重命名文件；该例外不得扩散到正式运行时素材、评审记录或项目代码。

## Feature 所有权

| Feature | 所有权 |
| --- | --- |
| `accessibility` | 棋盘与回合的规范无障碍语义摘要、字幕同源文本、复制入口和未来平台辅助技术投影 |
| `gameplay` | 棋盘、移动命令、规则、模式、对局状态、HUD 和玩法输入 |
| `navigation` | 场景路由、主菜单、真正的“继续游戏”与“读取存档”入口、模式选择、列表菜单导航壳和 UI Route 注册表 |
| `board_editor` | 玩家棋盘草稿、局部撤销历史、自定义模板目录和 `custom_boards` SaveGraph section |
| `settings` | 应用设置模型、设置持久化和设置界面 |
| `bookmarks` | 书签数据、保存流程、最近可继续书签查询、读取存档列表和预览入口 |
| `replays` | 回放数据、回放输入、播放/定位流程和回放列表 |
| `player_profiles` | 设备内本地账号目录、账号切换事务、个人信息页和跨账号本地榜查询入口 |
| `progress` | 按账号隔离的最高分、模式摘要、规范结果、资格过滤排行榜和 progress SaveGraph section |
| `tile_lab` | 玩家方块蓝图、`TileDefinition` + `GFCapabilityRecipe` 组合、冲突解释和隔离沙盒试验 |
| `tile_catalog` | 方块定义目录、组合/拓扑发现、响应式图鉴和 discoveries SaveGraph section |
| `achievements` | 数据驱动成就目录、GF Quest 运行时投影、成就列表和 achievements SaveGraph section |
| `persistence` | 通用玩家数据 section 协议、GF SaveGraph 事务编排和存储诊断 |
| `platform_runtime` | 平台 Adapter 选择、Godot 生命周期桥接、Web/微信准备契约和平台冒烟入口 |
| `themes` | 视觉主题、音效主题、主题化 UI 宿主与布局、UI 色板、棋盘反馈和主题内容包 |
| `asset_library` | 可复用素材内容包、候选评审、授权、引用审计和局部导入工具 |
| `diagnostics` | 项目诊断快照、支持报告和仅开发环境使用的独立诊断工作区 |

Feature 的 `scripts/` 内可以继续使用 `models/`、`systems/`、`utilities/` 等 GF 层目录，但这些目录只表达该 Feature 内部职责。例如 `features/replays/scripts/systems/` 只包含回放系统，不再和存档、路由、棋盘系统混放。

## 依赖方向

1. `app` 可以引用所有 Feature 与 `shared`，但只负责装配和启动，不实现业务规则。
2. Feature 可以依赖 GF、`shared` 和其他 Feature 的稳定公开契约，不得依赖 `app`。
3. `shared` 不得引用任何 Feature；否则相应代码应回到真正拥有它的 Feature。
4. 跨 Feature 协作优先使用 GF Model、System、Utility、Command、Query、事件或资源键，不使用跨场景 NodePath 形成隐式依赖。
5. Feature 私有资源路径不得成为其他 Feature 的持久化数据格式；跨 Feature 资源使用稳定资源键或公开 Resource 类型。
6. 新文件先确定所有权，再选择 GF 层。禁止为了方便重新创建全局类型桶。

## Module 深度与公开 Seam

- **Module** 是拥有明确生命周期和删除边界的 Feature 内能力；目录本身不自动构成 Module，只有被 Composition Root 装配并提供稳定 **Interface** 的能力才算 Module。
- **Interface** 是其他 Feature 可以依赖的最小公开面，包括强类型数据、System/Utility 查询、领域事件、稳定资源键和 route ID。具体节点、文件路径、缓存结构与序列化细节属于 **Implementation**，不得穿透边界。
- **Depth** 来自“小 Interface 隐藏足够多的校验、事务、生命周期与恢复策略”，不是通过增加一层同名转发类制造抽象。只转发调用且不增加约束的浅层包装应删除。
- **Seam** 必须落在真实可替换或可独立验证的位置：例如本地账号目录与玩家 Profile 切换、设备内排行榜与未来线上榜、项目方块蓝图与 GF Recipe 仲裁、Godot 平台事实与 `GFPlatformRuntime`。
- **Adapter** 只在 Seam 上翻译两个已存在的契约；不得拥有被适配领域的规则，也不得把供应商 API、场景 NodePath 或存储路径泄漏给调用方。
- **Leverage** 优先来自复用 GF 已安装能力处理生命周期、预算、目录、事务、输入与导航；产品身份、资格、排行分组、方块内容与冲突文案仍由项目拥有。
- **Locality** 要求一次业务变更主要停留在所属 Feature。若修改一个产品概念必须同时了解多个 Feature 的私有 Implementation，应先收紧公开 Interface，而不是把代码搬进 `shared`。

## 启动与装配

1. `app/scenes/boot.tscn` 加载不引用 GF 或玩法资源的极轻 `app/scripts/boot.gd`，立即承接原生静态首帧并显示低成本扫条。
2. 轻量 Boot 通过 `ResourceLoader.load_threaded_request()` 加载 `app/scripts/boot_runtime.gd`；正式编排器就绪后仍复用同一静态启动壳，只向它发布 `GFAsyncProgress`，并在壳的遮挡下加载完整依赖链。
3. BootRuntime 创建根 `GFArchitecture`，启用 `strict_dependency_lookup` 与 `fail_on_missing_declared_dependencies`，再调用 `await Gf.init()`。
4. GF 根据 `project.godot` 的 `gf/project/installers` 执行 `GameArchitectureInstaller`。
5. `app/scripts/game_architecture_installer.gd` 声明项目 Model、System、Utility；GF 扩展拥有的模块由扩展 Installer 自动装配。
6. BootRuntime 通过 `GFSceneUtility` 预热主菜单，并配置 Feature-Cohesive 的 `features/navigation/resources/scene_preload_map.tres`；场景图只预热最高频相邻路径，随后由 `SceneRouterSystem` 接管场景流转。
7. BootRuntime 使用 `GFRenderWarmupUtility` 执行 `startup_render_warmup_manifest.tres`，统一加载并触碰首轮背景、转场、焦点和庆祝 Shader；随后在不透明启动页背后提交 `GameplayVisualWarmup` 首绘，补足 GF 通用资源预热无法表达的方块轮廓、母题和反馈画布自绘 pipeline。缓存和预绘节点在首帧提交后按组释放。

Boot 和路由依赖缺失时必须明确失败，不保留 `SceneTree.change_scene_to_file()` 等旁路。

## GF 模块约束

- `init()` 只初始化模块自己的内部状态；`async_init()` 只执行该模块自己的异步准备；跨模块 Model、System、Utility 和 Architecture 必须在 `ready()` 获取。
- 只有 `app/scripts/boot.gd` 与其线程加载的 `app/scripts/boot_runtime.gd` 组成应用 Composition Root，可以直接访问全局 `Gf`；其他业务脚本必须使用 GF Module 注入、`GFController` 或项目的 `GameUiController`。
- Model 只表达可观察状态，不操作场景节点。
- System 编排业务流程，通过明确的 GF 接口访问其他模块。
- Utility 封装稳定的项目 Adapter；仅转发调用且没有增加约束的浅层 Utility 应删除。
- 只有 `ProjectContentCatalogUtility` 可以修改项目级 `GFContentPackageUtility` source root 或触发目录重建；Feature 目录 Utility 只能查询目录快照和稳定资源键。
- Controller 连接场景树与 GF 架构，不实现棋盘算法或存档格式。
- Command 表达可撤销玩家操作；移动继续由 `GFCommandHistoryUtility` 管理。
- Rule 是资源化策略，通过 `RuleContext` 获取确定性依赖，不直接访问全局 `Gf`。
- UI 使用 Route、事件、Controller 或 Query 获取业务能力，不直接查找其他 Feature 的节点。

## 核心数据流

### 玩家移动

1. `PlayerInputSystem` 从 `GFInputMappingUtility` 消费 `GFInputContext`；`GameInputProfileUtility` 是玩家覆盖和冲突校验的唯一入口，默认绑定仍由资源声明。
2. `MoveCommand` 调用棋盘 System 更新 `GridModel`；`BoardTopology` 是活跃空间唯一真源，移动方向由连续 lane 表达，空洞会切断 lane。
3. `MovementRule` 只确定移动和碰撞候选，`TileCompositionUtility` 通过 `GFCapabilityUtility` 解析双方共同 Recipe 能力并仲裁交互提案。
4. `GridMovementSystem` 为有效移动生成无 Node 的强类型 `TurnResult`；它显式携带移动、合并、生成和转化 transition，以及分数、最大值和规则统计汇总。`GameTurnSystem` 将该结果封装为一次性的 `GameMoveTurnAction`，交给扩展拥有的 `GFTurnFlowSystem`。
5. GF 为回合 Action 注入 `RuleSystem` 与 `GameFlowSystem`，顺序完成移动统计、生成规则和目标/失败结算；不再派发项目私有 `TURN_FINISHED` 事件。
6. `GFCommandHistoryUtility` 保存包含定义、实际 Recipe 清单和能力状态的严格棋盘快照。
7. 业务事件携带同一个 `TurnResult` 到 `GameBoardController`；表现层只把 typed transition 投影成动画指令，不能从场景节点或字符串 Dictionary 反推领域结果。定义视觉家族与 Recipe 视觉层共同生成方块表现。
8. `BoardTweenBatchAction` 把同一批已有 Tween 适配成可等待的 `GFVisualAction`。
9. `GameBoardAnimationUtility` 从扩展拥有的 `GFActionQueueSystem` 取得 `gameplay.board_animation` 命名队列，并绑定当前棋盘生命周期。缓冲、动画期间阻断、实时取消并按模型快照重定向三种策略只在该 Adapter 仲裁；棋盘 Action 不使用默认队列或 fire-and-forget。

方块组合详细契约见 `features/gameplay/docs/tile_composition.md`。

### 棋盘拓扑

1. `BoardTopology` 只描述规范化活跃单元，不保存方块；`GridModel` 以坐标到 `TileState` 的稀疏映射保存占用状态，不再维护完整二维空数组。
2. `BoardTopologyTemplate` 属于模式配置，声明固定拓扑或可变矩形范围。模式选择页把原 3x3 至 8x8 选项转换成矩形拓扑，`board_editor` 则提交经过同一模板复核的自定义拓扑。
3. `GridMovementSystem`、`GridSpawnSystem` 与 `StandardGameOverRule` 只遍历活跃单元和真实相邻关系；任何系统不得按包围盒把空洞实体化，也不得让方块跨越空洞。
4. 撤销、书签、回放和 GF SaveGraph 共用严格拓扑快照；对局 ID、统计和本地排行榜分组使用语义 ID 加内容指纹的稳定键。
5. GF 继续拥有验证报告、确定性随机、命令历史、关卡 Session 和持久化事务；四向稀疏拓扑是 gameplay 领域对象，不误用 GF flow graph 或 hex grid 表达不同语义。
6. `BoardWorldViewportController` 把棋盘表现放入独立 `BoardWorld`，统一拥有缩放、平移、完整聚焦和边界约束；HUD 保持在视口外的屏幕空间，诊断 UI 不进入玩家场景树。
7. `GFPointerGestureUtility` 负责桌面指针、触摸与原生 pan/magnify 归一化，`GFViewportUtility` 负责屏幕/棋盘局部坐标换算和物理安全区，`GFSignalUtility` 负责宿主生命周期内的连接所有权。项目只保存“本轮触摸是否仍可成为玩法滑动”的领域仲裁状态，不重复维护指针几何或坐标变换工具。
8. 单指短滑由 `BoardWorldViewportController` 分类后，经 `GFVirtualInputSource` 写入 `GameplayInputActions`；`PlayerInputSystem` 仍是唯一消费 gameplay `GFInputContext` 并创建 `MoveCommand` 的入口。双指序列只控制视口，UI 控件拥有更高事件优先级。
9. `GameplayResponsiveLayoutController` 让棋盘占满玩法内容区，并把 HUD 保持为覆盖全屏的独立安全区层：分数位于顶部中间，操作提示位于左下，暂停/撤销/重做/书签/只读提示位于右下，详细状态按需展开。GF 通知与回合字幕共用 `FeedbackRail`；横屏位于棋盘右侧，并按棋盘实际世界包围盒宽高比动态求解 right fit inset，保证棋盘连同 `50px` 动效包络停在操作栏左侧；棋盘几何变化会触发布局重算。竖屏反馈轨位于棋盘与触控区之间，三种布局都不得与棋盘相交。继承布局的左右栏始终关闭，不恢复通用信息栏。
10. `BoardTopology.get_cells_in_rect()` 是超大稀疏棋盘的可见窗口查询入口；`GameBoardController` 通过 `GFObjectPoolUtility` 仅挂载当前可见格与方块节点，窗口外节点可以回收但模型与快照保持完整。
11. 棋盘动画由 `GameBoardAnimationUtility` 的 GF 命名队列拥有生命周期；视口变化不得释放正在执行 Tween 的方块，Action 完成或取消后按当前可见区域重建表现缓存。实时响应模式取消旧 Tween 后必须先从当前模型快照恢复表现，再执行新命令。
12. `board_editor` 拥有独立 GF 输入上下文和 `board_editor_undo`、`board_editor_redo` 抽象动作；编辑器快捷键不得依赖未注册的 Godot `InputMap` 动作。场景控件与草稿信号统一由 `GFSignalUtility` 持有连接生命周期。
13. `CanvasViewportMath` 是不引用 Feature 的共享纯算法；gameplay 和 `board_editor` 分别持有业务输入仲裁。编辑器用稳定世界尺寸绘制草稿，`BoardEditorViewportController` 通过 `GFPointerGestureUtility` 和 `GFViewportUtility` 实现左/右键绘制、中键/滚轮视口操作、单指绘制与双指平移缩放；第二根手指出现时必须取消尚未提交的笔画。
14. `BoardEditorResponsiveLayoutController` 负责桌面三栏、紧凑横屏和竖屏布局。紧凑布局以编辑/模板分区替代被压缩的三栏，竖屏工具栏位于画布上方，所有外边距通过 `GFViewportUtility.apply_display_safe_area_margins()` 叠加物理安全区。

详细契约见 `features/gameplay/docs/board_topology.md`。

### 确定性提示

1. `DeterministicHintQuery` 只接受调用方捕获的棋盘快照和 `snapshot_id`，不持有 Architecture，也不调用 `GridModel`、规则、命令历史或随机流。提示结果没有执行入口，不属于教程、回放命令或 canonical gameplay state。
2. 查询的结构校验、拓扑遍历和四向评分逐步消费 `GFExecutionBudget`；调用方可以同时设置 `max_steps`、`max_elapsed_msec` 和 `GFCancellationToken`。预算终止返回稳定 reason 和已有部分结果，不绕过 deadline 继续求精。
3. 评分只使用连续 lane 的压缩空间、可比较相邻结构和移动前沿稳定性，不承诺模式专用合并结果；任意 `BoardTopology` 和全部正式模式共享同一算法及固定四向 tie-break，缺少强信号时显式返回通用降级解释。
4. `Hud` 在捕获边界使用 `GameDeterminismUtility` 计算摘要，并在展示前重新读取当前快照复核；移动、刷新、尺寸或状态事件会立即清除旧结果。摘要不一致、取消或无效快照不得显示。
5. 键盘、手柄和触摸按钮统一写入 gameplay `GFInputContext` 的 `request_hint` 动作，再由 `PlayerInputSystem` 发布只读请求事件；任何输入表面都不得直接执行建议方向。

### 对局资格与本地排行榜

1. `GameSessionMetadata` 冻结本局 seed 来源和 `GameCompetitionEligibility`。资格快照不可变；调试改写、回放续玩、书签恢复、撤销/重做、自定义棋盘和手动 seed 都是显式失格原因，普通随机对局只有在没有这些原因时才合格。
2. `GameResultRecordedData` 冻结模式、拓扑、规则集 ID/版本/指纹、初始 seed、最终 canonical state hash、资格快照和结算指标，并以严格 hash 拒绝字段漂移。结果只在成功写入 `progress` section 后成为规范事实。
3. `ProgressStatsSystem` 把严格结果写入当前账号的有界最近结果；调试改写不推进统计或成就。只有 `is_competition_eligible()` 为真的结果进入本地排行榜，分组身份固定为 `mode_id`、`board_key`、`ruleset_id`、`ruleset_version` 和 `ruleset_fingerprint`。
4. `player_profiles` 可以只读聚合同一设备各账号的严格 `progress` section，并按账号展示个人模式摘要与本地榜名次；聚合不能改写其他账号 Profile，也不能放宽单条结果校验。
5. 本地排行榜只是离线设备内参考，不是平台或服务端权威证明。未来 Steam、微信或独立后端接入必须通过显式 bridge contract 重新定义上传、校验和裁决边界，不能把本地 SaveGraph 直接冒充线上真源。

### 本地账号与玩家 Profile

1. `LocalAccountCatalogUtility` 拥有设备级账号身份目录，只保存账号 ID、显示名、创建时间、最近使用时间和当前账号；它不保存统计、书签、回放、成就、图鉴或试验台蓝图。
2. 每个账号映射到独立的 `GameSaveGraphUtility` Profile。切换账号必须先冲刷当前 Profile，再加载并完整应用目标 Profile；任一步失败都保持原账号和原内存图，不发布半完成切换。
3. `LocalAccountSystem` 是账号创建、重命名、切换和删除的唯一业务 Interface。其他 Feature 订阅强类型账号变更事件或查询当前账号，不读取设备目录文件，也不拼接 Profile 路径。
4. 首次启用本地账号时可以把唯一的旧默认 Profile 一次性收养为首个账号；完成后不保留旧路径双读。删除非当前账号时同时删除其 Profile，失败必须向用户显式报告。
5. 个人信息页只投影当前账号的资料和各模式汇总；账号管理与排行榜 UI 通过 `GFUIRouterUtility` 进入，不让页面节点拥有存档事务。

### 方块试验台

1. `tile_lab` 保存的是项目拥有的方块蓝图：稳定蓝图 ID、显示名、基础 `TileDefinition` 身份、选中的 `GFCapabilityRecipe` 身份和预览参数；不序列化运行时对象或硬编码新方块子类。
2. `TileCompositionUtility` 仍是 Recipe 能力匹配与交互仲裁的唯一 Interface。试验台只组合目录中可用的定义与 Recipe，并把冲突、缺少共同能力或不合法参数解释给玩家。
3. 沙盒从蓝图构造临时 `TileState`，允许玩家实际尝试生成、配对和交互；临时状态与普通对局的 canonical state、命令历史、回放、统计和排行资格隔离。
4. 保存蓝图进入当前账号的独立 SaveGraph section。若未来让蓝图进入正式模式，必须先为内容身份、规则指纹、回放和书签定义新的稳定 Seam，不能让编辑器资源路径成为持久化真源。

### 开发诊断工作区

1. `RuntimeDiagnosticsUtility` 作为无 UI 的 `GFDiagnosticsUtility` 别名常驻，用于接收 `gf.action_queue` 等扩展的运行时贡献；普通运行不查询或创建 Console GUI。`GameArchitectureInstaller` 只在显式 `with_dev_tools` feature 下按路径加载 `features/diagnostics/scripts/installers/game_diagnostics_installer.gd`，再补齐 Console、Debug Overlay、Inspector、Screenshot 与 `TestToolUtility`，避免开发界面进入玩家首屏依赖链。
2. `GamePlayController` 只发布 `GameplayBoardReadyData`，不引用 `TestToolUtility`、`TestPanel` 或 diagnostics 资源。diagnostics feature 订阅该类型事件并持有开发上下文，依赖方向保持为 diagnostics -> gameplay。
3. `TestToolUtility` 默认不自动弹窗；仅在 `F4` 或控制台显式请求时按需创建非 transient、非 exclusive 的 `GameplayDiagnosticsWindow`，场景切换时释放窗口和棋盘引用。窗口关闭只隐藏工作区，当前对局内可再次打开。
4. 工作区使用独立 GF `diagnostics` 输入上下文，`F4` 通过 `GFInputMappingUtility` 切换窗口；`toggle_test_tools` 由 `GFConsoleUtility` 注册；窗口信号由 `GFSignalUtility` 持有生命周期。
5. 独立窗口不是 `GFUIRouterUtility` 的玩家 UI Route，也不参与回放、截图布局或移动端安全区。它自行通过 `GameThemeUtility`、`GameUiStyleUtility` 和 `GameUiMotionUtility` 应用当前主题与交互状态。
6. 需要工作区的专用开发导出必须声明 `with_dev_tools` custom feature；不得通过 `OS.is_debug_build()` 或 `editor` 自动开启，以免普通调试运行掩盖真实启动性能。

### 主题切换

1. Composition Root 把内置素材、内置主题和 `user://content_packages` 配置给 `ProjectContentCatalogUtility`。
2. `ProjectContentCatalogUtility` 是唯一可以注册 source root、重建 `GFContentPackageUtility` 目录并同步 `GFResourceResolverUtility` 的项目 Module。
3. `GameThemeCatalogUtility` 只读取 manifest metadata，建立 `GameThemeDescriptor` 索引；设置菜单枚举主题时不加载完整资源。
4. 用户选择主题后，`GameThemeUtility` 先让 `GameThemeCatalogUtility` 只解析根资源路径，再由 `GFResourceRegistryTools` 收集完整依赖图并创建手动提交的 `GFAssetLoadSession`；业务代码不得在激活路径同步 `load()` 主题资源。
5. 会话在 staging group 全量成功后校验资源类型、稳定主题 ID 和业务报告，随后提交唯一目标资源组并用 `GFActivationTransaction` 应用主题。只有事务成功才替换当前组并通过 `GFAssetUtility.unload_group(..., true)` 释放旧组；失败保留旧主题、旧银行和设置。
6. `BootRuntime` 在 `Gf.init()` 后显式等待视觉与声音主题均完成首次提交，再执行渲染预热和入口场景预加载。设置页等待真实激活结果并在会话期间禁用对应选择器，连续请求由主题 Utility 取消旧会话并以序列号拒绝迟到回调。
7. 视觉 Profile 交给 `GFShaderParameterUtility`；`GameBoardFeedbackProfile` 以 `GameFeedbackRecipe` 为领域事件定义颜色、时长、冲击、碎片、Shake 与 Haptic，`GameFeedbackPerformanceMatrix` 再按 `FULL`、`REDUCED`、`MINIMAL` 和无障碍状态施加硬预算。`GameBoardFeedbackUtility` 编排 GF Shake/Haptic/Shader 与项目表现节点：`BoardMotionBackdrop` 只在棋盘后层绘制局部棋格和有界纸片，`BoardFeedbackCanvas` 保留方块碰撞层；二者都只消费已经提交的 `TurnResult`，不得写回模型或推进 gameplay RNG。`GameplayAcceptanceMatrix` 用 `GFMetricSeries` 对输入、尺寸和 P95 性能门槛给出有证据的结论，并通过 GF Diagnostics/Support Report 暴露契约。声音银行通过 `GFAudioUtility.mount_audio_bank()` 获取令牌，`GameAudioTheme` 从 `TurnResult` 选择单一主事件，`GameThemeUtility` 以 `GFAudioEvent` 发布；细分事件由 `GFAudioBank` 层级回退，切换或释放时明确卸载旧银行。
8. `GFAudioUtility` 的内置 Godot 路径直接支持 bank、BGM/ambient、crossfade、总线混音、ducking、播放池与 SFX 并发/溢出控制。`set_parameter()`、`set_state()`、`set_switch()` 只委派给显式安装的 `GFAudioBackend`；当前生产 Composition Root 未安装该后端，基础 backend 返回 `false`，因此业务不得假定自适应 state/switch 已生效。
9. `GameAccessibilityUtility` 是减少动态、高对比反馈、震动、Shader 和 VFX 档位的唯一运行时投影；设置由 `GFSettingsUtility` 持久化，变更由 `GFSignalUtility` 管理。任何表现设置都不得进入 canonical gameplay state、回放 checkpoint 或排行资格。
10. `GameUiStyleUtility` 独占 `GameUiPalette`、静态 StyleBox、语义文本和焦点 Shader；`GameUiMotionUtility` 只拥有交互信号与 Tween。减少动态时 UI 直接落到终态且不创建 Tween；`SceneRouterSystem` 仍执行遮罩的 cover/swap/reveal 生命周期，但使用零时长、无 Shader 的静态路径。UI 节点声明语义角色，不保存从旧色板生成的样式对象。
11. 反馈分级、降级顺序和性能验收目标见 [`features/themes/docs/feedback_performance_matrix.md`](../features/themes/docs/feedback_performance_matrix.md)。

### 素材评审

1. 项目级治理、所有权、晋升与安全边界以 [`docs/asset_library.md`](./asset_library.md) 为权威；具体命令、快捷键和当前工具行为以 [`features/asset_library/docs/readme.md`](../features/asset_library/docs/readme.md) 为权威。生成报告只证明一次运行，不覆盖这两层规范。
2. `features/asset_library/resources/gf_content_package.json` 只登记已批准运行时素材，并由统一的 `ProjectContentCatalogUtility` 注册。
3. 候选素材和备注保存在 `features/asset_library/resources/review/`；原始来源保存在隔离的 `source_packs/`，不得被运行时直接依赖。
4. 同一声音的 WAV、OGG、MP3 等编码只有在源包声明了经过验证的同源分组后，才同步 `review_status` 与 `reviewed_at`。评分、标签、备注、路径、哈希和许可证仍属于具体编码；文件名相似、跨源包模糊匹配或冲突决定都不得自动同步。
5. `GFProjectReferenceScanner`、`GFAssetAttributionTools` 和 `GFAssetCatalog` 生成引用、授权和用途报告；Feature 局部浏览器和导入脚本位于 `features/asset_library/scenes/` 与 `features/asset_library/tools/`。

### 运行时通知

1. `PlayerInputSystem`、`GameFlowSystem` 等生产者只向 `GFNotificationUtility` 写入通知记录，不定义项目私有消息载荷。
2. GF 通知队列统一负责去重、优先级、展示时长和生命周期；场景内不再维护额外 `Timer`。
3. `Hud` 通过 `GFSignalUtility` 订阅通知开始与结束信号，只负责当前主题下的视觉呈现。
4. 通知属于瞬时表现状态，不进入 `GameStatusModel`、撤销快照、书签或回放 schema。

### UI 路由与所有权

1. 弹层只能通过 `GFUIRouterUtility` 的稳定 route ID 打开和关闭；业务代码不得直接调用 `GFUIUtility.pop_panel()` 或 `clear_all()`。
2. 菜单控制器拥有自身路由的关闭职责。触发继续、重开或返回等业务事件时，先捕获当前 `GFArchitecture`，校验并关闭自身路由，再由捕获的架构派发事件。
3. `GameFlowSystem` 只处理继续、重新开始和返回主界面等业务结果，并把暂停状态变更委托给 `GamePauseUtility`；它不读取或清空 UI 栈。
4. 路由创建或关闭失败时保持原业务状态并显式报错，不切换暂停状态，也不回退到直接面板操作。
5. 动态列表和模式卡片的纵向焦点顺序由 `GFControlFocusUtility` 写入；项目代码只保留跨列跳转等界面特有语义，不逐项重复计算首尾循环。

### 平台运行时

1. `GFPlatformRuntime` 是平台 Adapter 注册、初始化、能力契约路由、请求句柄、超时与生命周期序列的唯一所有者；业务 Feature 不得绕过 Runtime 直接调用 Adapter。
2. `GamePlatformUtility` 只负责选择项目 Adapter、把 Godot 窗口与应用通知转成 GF 生命周期事件，并投影只读 `GFPlatformRuntimeContext`；它不重复维护请求表、超时器或平台能力集合。
3. `GamePlatformAdapter` 继承 `GFPlatformAdapter`，负责冻结项目身份与能力契约；具体 Adapter 只实现支持的 SDK dispatch 和平台上下文刷新。
4. 当前唯一生产实现是 `LocalPlatformAdapter`：它投影 Godot 桌面、移动端和 Web 的本地存储、HTTP、音频、输入、显示与生命周期事实，不宣称微信登录、开放数据域、平台/线上排行榜、支付、分享或云存档。`progress` Feature 的本地排行榜不属于平台能力。Adapter 的项目所有权由 `.gf/project_contract.json` 的 `godot_local_platform_adapter` boundary 声明。
5. 只有具体平台 Adapter 可以使用 `OS.has_feature()`、`DisplayServer` 或供应商 SDK 探测玩家设备与平台能力；Gameplay、Board Editor 和其他 Feature 必须通过 `GamePlatformUtility` 查询 `GFPlatformRuntimeContext` 与能力 ID，平台上下文变化时重新投影布局。Composition Root 的构建 feature 开关、开发诊断的 headless 判定以及 `GFDisplaySettingsUtility` 所需的枚举类型不属于玩家平台能力探测。
6. 平台请求统一返回 `GFPlatformRequestHandle`。调用方通过句柄读取终态 `GFPlatformBridgeResult`，不得另建项目私有异步请求协议。
7. `GFHttpClientUtility` 目前只服务 `platform_smoke` 的网络兼容性验证，因此 Composition Root 仅在该导出 feature 下注册它。正式 Steam、Android、Web 与微信构建不得为未实现的在线业务常驻 HTTP 模块；未来排行榜联网应由平台 Adapter 或独立后端 Feature 明确拥有请求和重试边界。

### 时钟、随机与运行诊断

1. `GFTimeUtility` 拥有游戏 delta、缩放和逻辑暂停；`GamePauseUtility` 是唯一可写暂停 Adapter，负责把 GF 时间状态与 `SceneTree.paused` 原子同步。其他运行时 Module 不得直接写 `SceneTree.paused`。
2. `PlayerInputSystem` 显式忽略 GF 暂停和时间缩放，只为暂停期间继续消费“恢复”意图；检测到暂停后必须清空移动、撤销、重做、书签和提示输入，不能把缓冲延迟到恢复后执行。
3. Composition Root 创建单一 `GFClock` 并同时注入 `GFTimeUtility` 与 `GameClockUtility`；后者是业务代码读取 wall-clock、单调 tick 和日期格式的唯一 Adapter，测试使用 `GFManualClock` 控制同一时间源。
4. `GFSeedUtility` 拥有运行时随机流、全局种子和稳定派生算法；业务代码不得自行创建 `RandomNumberGenerator`，也不得调用 Godot 全局随机函数。生成规则只能消费以规则语义 ID 派生的 gameplay branch；粒子、音高、装饰闪烁等 cosmetic 随机不得消费 gameplay branch，也不得进入领域快照。
5. `GameDeterminismUtility` 是 canonical turn state 的唯一摘要入口：它按拓扑坐标排序方块、排除运行时 UUID，并分别计算 board、gameplay RNG、规则集和完整 state checksum。规则资源必须声明稳定 `ruleset_id` 与 `ruleset_version`，内容变化必须显式提升版本或指纹。
6. `ReplayData` 保存初始 seed/拓扑、规则集身份与指纹、会话资格元数据、有效命令，以及每个 settled turn 的 `ReplayCheckpoint`。回放在应用命令后立即比较 checkpoint；第一次不一致生成包含回合、命令及 expected/actual board/RNG/state 的 OOS 报告，并阻断继续步进和“从回放继续”。事件标记从 checkpoint 元数据确定性派生，前后标记定位仍通过有界命令历史重建并复核目标 checksum。
7. 固定 seed 测试语料必须覆盖全部正式模式和多种拓扑，验证重复执行、UUID/插入顺序变化与序列化往返不改变 canonical checksum。表现档位与无障碍设置的切换也不得改变同一 seed/命令序列的领域结果。
8. 开发构建的长流程耗时由 `GFOperationDiagnosticsUtility` 的操作记录拥有。调用方读取同一操作的 `started_ticks_usec` 记录阶段，不再平行缓存一份系统 tick；发布路径只能通过当前 Architecture 的 local lookup 可选读取该 Utility，且在未安装开发诊断模块时必须保持完整功能。
9. 只有 Boot 组合根和 `features/asset_library/tools/` 下的离线素材工具可以直接访问 `Time`；该例外由 GF 合规测试的精确路径 allowlist 约束，不得扩散到运行时 Feature。
10. 开发构建由 `GameDiagnosticsUtility` 组合 GF Diagnostics、Asset Metadata、Debug Overlay、Runtime Inspector 与 Screenshot；发布构建不安装调试界面，也不得声明对这些开发期 Utility 的严格依赖。支持报告在同一时点收集项目快照、当前场景资产元数据和 Viewport 截图。

### 持久化

- `persistence` 创建玩家根 Scope，并通过 `GFSaveGraphUtility` 统一生成、校验和应用规范 `GFSaveDocument`，不再把裸 Scope payload 当作磁盘根协议。
- `progress`、`bookmarks`、`board_editor`、`tile_catalog`、`achievements`、`replays` 与 `tile_lab` 各自拥有严格 section Provider；`app` 在 GF `init()` 前完成组合，不把业务字段写入 persistence。
- section 按声明的 apply phase 写入当前账号的单一 Binary Profile；`GFStorageUtility` 返回类型化 `GFStorageReadResult`，并负责存储元数据、checksum 和原子文件事务。账号目录是设备身份元数据，不是第二份玩家业务存档。
- 书签和回放使用 UUID v7 稳定身份，不依赖时间戳文件名或运行时 `file_path`。UUID 只用于持久身份，不参与 canonical board checksum。
- Profile、section 和 item 的当前 schema 版本以数据类型与 [`docs/save_model.md`](./save_model.md) 为准，本架构文档不复制易漂移数字。书签与回放冻结规则集身份和资格上下文；棋盘快照与玩家模板内嵌严格 `BoardTopology`，不提供旧尺寸键或旧业务字段推断。
- 设置使用 `GFSettingsUtility` 的独立文件，不参与玩家数据图，也不随书签或回放恢复。
- 旧 Profile 只允许由 persistence 通用编排执行显式一次性收养、备份或重建；未来/未知/畸形 Profile 继续拒绝，业务数据迁移只能使用显式离线工具，运行时代码不保留旧字段双读分支。

## GF 扩展

当前启用：

- `gf.action_queue`
- `gf.asset_metadata`
- `gf.capability`
- `gf.content_package`
- `gf.domain`
- `gf.feedback`
- `gf.save`
- `gf.turn_based`

Installer 不得重复绑定这些扩展拥有的模块。启用扩展但不使用其核心能力时，应明确采用或关闭，不能用自动注册数量虚增 GF 利用率。

项目 Module 对 Installer 和扩展声明的依赖采用严格契约：依赖缺失时停止初始化并报告配置错误，不允许退回直接实例化、直接执行 Action、手动跨生命周期连接信号或绕过 GFSceneUtility 切换场景。

## GF 框架变更治理

- `addons/gf/**` 是由 `.gf/vendor.lock.json` 锁定的上游快照，项目开发中视为只读；不得在项目功能提交中直接修补、格式化或重构 GF 源码。
- 发现 GF 缺陷或通用能力缺口时，必须先在 `C76GN/gf-framework` 创建可复现的 GitHub issue，明确影响版本、最小复现、期望契约和验证标准。
- GF 实现只能在独立 `gf-pr` 工作区的非 `main` 分支完成，并通过 GF 自身测试与维护门禁；`gf-pr` 只是隔离工作区名称，不代表授权创建 GitHub PR。对应 GitHub issue 是协作与验收的唯一记录，不得把 issue 转成 PR，也禁止直接向 GF `main` 提交或推送框架改动。
- 项目与 GF 的改动不得混在同一提交或实施批次。项目可以先提交不依赖框架修改的调用侧改进；只有 GF 变更完成测试并由维护者发布后，项目才能通过正式 vendor 更新流程同步精确的上游 source commit。
- 同步 GF 时必须更新 `.gf/vendor.lock.json`，运行 vendor 完整性、GUT、LSP、Feature-Cohesive 和退出泄漏验证，并在项目提交中引用上游 issue、发布版本与精确 source commit。
- 用户自有 `gf` 工作区只对本项目自动化与协作者开放只读分析；不得代替所有者整理、覆盖、提交或推送其中改动，但不限制用户本人继续维护。需要开发框架修复时只使用独立 `gf-pr` 工作区。

## 验证门禁

- `GFProjectLayoutValidator` 的 error 与 warning 必须同时为零。
- `test_gf_project_conformance.gd` 必须保证 GF 弃用 API、全局架构旁路和早期生命周期依赖访问均为零。
- GDScript 规范扫描覆盖 `app/`、`features/`、`shared/`、`tests/gut/` 和 `tools/`。
- LSP 必须零 error、零 warning。
- 关键 Feature 变更先运行定向 GUT，再运行完整安全 GUT。
- 任何旧根目录引用、重复 Feature 前缀或不存在的 `res://` 路径都属于提交阻断问题。

具体命令见 `docs/validation.md`。
