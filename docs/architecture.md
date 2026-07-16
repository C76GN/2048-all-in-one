# 架构说明

本项目是 Godot 4.7 与 GF Framework 8.x 的 2048 示例项目。目录严格采用 GF 内置 `Feature-Cohesive` 契约：业务能力优先内聚在 Feature 内，GF 的 Model、System、Utility、Controller 等是 Feature 内部的逻辑层，不再作为项目根目录的类型桶。

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
| `gameplay` | 棋盘、移动命令、规则、模式、对局状态、HUD 和玩法输入 |
| `navigation` | 场景路由、主菜单、模式选择、列表菜单导航壳和 UI Route 注册表 |
| `settings` | 应用设置模型、设置持久化和设置界面 |
| `bookmarks` | 书签数据、保存流程、列表和预览入口 |
| `replays` | 回放数据、回放输入、播放流程、列表和继续游戏入口 |
| `progress` | 最高分、统计和 progress SaveGraph section |
| `persistence` | 通用玩家数据 section 协议、GF SaveGraph 事务编排和存储诊断 |
| `themes` | 视觉主题、音效主题、主题化 UI 宿主与布局、UI 色板、棋盘反馈和主题内容包 |
| `asset_library` | 可复用素材内容包、候选评审、授权、引用审计和局部导入工具 |
| `diagnostics` | 项目诊断快照、支持报告和仅开发环境使用的测试面板 |

Feature 的 `scripts/` 内可以继续使用 `models/`、`systems/`、`utilities/` 等 GF 层目录，但这些目录只表达该 Feature 内部职责。例如 `features/replays/scripts/systems/` 只包含回放系统，不再和存档、路由、棋盘系统混放。

## 依赖方向

1. `app` 可以引用所有 Feature 与 `shared`，但只负责装配和启动，不实现业务规则。
2. Feature 可以依赖 GF、`shared` 和其他 Feature 的稳定公开契约，不得依赖 `app`。
3. `shared` 不得引用任何 Feature；否则相应代码应回到真正拥有它的 Feature。
4. 跨 Feature 协作优先使用 GF Model、System、Utility、Command、Query、事件或资源键，不使用跨场景 NodePath 形成隐式依赖。
5. Feature 私有资源路径不得成为其他 Feature 的持久化数据格式；跨 Feature 资源使用稳定资源键或公开 Resource 类型。
6. 新文件先确定所有权，再选择 GF 层。禁止为了方便重新创建全局类型桶。

## 启动与装配

1. `app/scenes/boot.tscn` 加载 `app/scripts/boot.gd`，显示启动画面并发布 `GFAsyncProgress`。
2. Boot 创建根 `GFArchitecture`，启用 `strict_dependency_lookup` 与 `fail_on_missing_declared_dependencies`，再调用 `await Gf.init()`。
3. GF 根据 `project.godot` 的 `gf/project/installers` 执行 `GameArchitectureInstaller`。
4. `app/scripts/game_architecture_installer.gd` 声明项目 Model、System、Utility；GF 扩展拥有的模块由扩展 Installer 自动装配。
5. Boot 通过 `GFSceneUtility` 预热主菜单，随后由 `SceneRouterSystem` 接管场景流转。

Boot 和路由依赖缺失时必须明确失败，不保留 `SceneTree.change_scene_to_file()` 等旁路。

## GF 模块约束

- `init()` 只初始化模块自己的内部状态；`async_init()` 只执行该模块自己的异步准备；跨模块 Model、System、Utility 和 Architecture 必须在 `ready()` 获取。
- 只有 `app/scripts/boot.gd` 作为 Composition Root 可以直接访问全局 `Gf`；其他业务脚本必须使用 GF Module 注入、`GFController` 或项目的 `GameUiController`。
- Model 只表达可观察状态，不操作场景节点。
- System 编排业务流程，通过明确的 GF 接口访问其他模块。
- Utility 封装稳定的项目 Adapter；仅转发调用且没有增加约束的浅层 Utility 应删除。
- Controller 连接场景树与 GF 架构，不实现棋盘算法或存档格式。
- Command 表达可撤销玩家操作；移动继续由 `GFCommandHistoryUtility` 管理。
- Rule 是资源化策略，通过 `RuleContext` 获取确定性依赖，不直接访问全局 `Gf`。
- UI 使用 Route、事件、Controller 或 Query 获取业务能力，不直接查找其他 Feature 的节点。

## 核心数据流

### 玩家移动

1. `PlayerInputSystem` 从 `GFInputMappingUtility` 消费 `GFInputContext`。
2. `MoveCommand` 调用棋盘 System 更新 `GridModel`。
3. `MovementRule` 只确定移动和碰撞候选，`TileCompositionUtility` 通过 `GFCapabilityUtility` 解析双方共同 Recipe 能力并仲裁交互提案。
4. `GameTurnSystem` 将有效 `MoveData` 封装为一次性的 `GameMoveTurnAction`，交给扩展拥有的 `GFTurnFlowSystem`。
5. GF 为回合 Action 注入 `RuleSystem` 与 `GameFlowSystem`，顺序完成移动统计、生成规则和目标/失败结算；不再派发项目私有 `TURN_FINISHED` 事件。
6. `GFCommandHistoryUtility` 保存包含定义、实际 Recipe 清单和能力状态的严格棋盘快照。
7. 业务事件携带动画指令到 `GameBoardController`；定义视觉家族与 Recipe 视觉层共同生成方块表现。
8. `BoardTweenBatchAction` 把同一批已有 Tween 适配成可等待的 `GFVisualAction`。
9. `GFActionQueueSystem` 等待整批移动、合并、生成或撤回 Tween，并拥有暂停、完成与取消生命周期；棋盘 Action 不使用 fire-and-forget。

方块组合详细契约见 `features/gameplay/docs/tile_composition.md`。

### 主题切换

1. 设置页写入视觉主题和音效主题 ID。
2. `GameThemeCatalogUtility` 通过 `GFContentPackageUtility` 注册 `features/themes/resources/gf_content_package.json`。
3. `GFResourceResolverUtility` 通过稳定资源键解析主题资源。
4. `GFValidationReport` 在主题进入运行时前验证 ID、资源引用、Shader 参数和音频事件。
5. `GameThemeUtility` 将 Profile 交给 `GFShaderParameterUtility`，将音频银行交给 `GFAudioUtility`。

### 素材评审

1. `features/asset_library/resources/gf_content_package.json` 只登记已批准运行时素材。
2. 候选素材和备注保存在 `features/asset_library/resources/review/`。
3. 原始来源保存在隔离的 `source_packs/`，不得被运行时直接依赖。
4. `GFProjectReferenceScanner`、`GFAssetAttributionTools` 和 `GFAssetCatalog` 生成引用、授权和用途报告。
5. Feature 局部浏览器和导入脚本位于 `features/asset_library/scenes/` 与 `features/asset_library/tools/`。

### 运行时通知

1. `PlayerInputSystem`、`GameFlowSystem` 等生产者只向 `GFNotificationUtility` 写入通知记录，不定义项目私有消息载荷。
2. GF 通知队列统一负责去重、优先级、展示时长和生命周期；场景内不再维护额外 `Timer`。
3. `Hud` 通过 `GFSignalUtility` 订阅通知开始与结束信号，只负责当前主题下的视觉呈现。
4. 通知属于瞬时表现状态，不进入 `GameStatusModel`、撤销快照、书签或回放 schema。

### UI 路由与所有权

1. 弹层只能通过 `GFUIRouterUtility` 的稳定 route ID 打开和关闭；业务代码不得直接调用 `GFUIUtility.pop_panel()` 或 `clear_all()`。
2. 菜单控制器拥有自身路由的关闭职责。触发继续、重开或返回等业务事件时，先捕获当前 `GFArchitecture`，校验并关闭自身路由，再由捕获的架构派发事件。
3. `GameFlowSystem` 只处理暂停状态、重新开始和场景路由等业务结果，不读取或清空 UI 栈。
4. 路由创建或关闭失败时保持原业务状态并显式报错，不切换暂停状态，也不回退到直接面板操作。

### 时钟、随机与运行诊断

1. `GFTimeUtility` 只拥有游戏 delta、缩放和暂停；`GameClockUtility` 是业务代码读取 wall-clock、单调 tick 和日期格式的唯一 Adapter。
2. `GFSeedUtility` 拥有运行时随机流、全局种子和稳定派生算法；业务代码不得自行创建 `RandomNumberGenerator`，也不得调用 Godot 全局随机函数。
3. 长流程耗时由 `GFOperationDiagnosticsUtility` 的操作记录拥有。调用方读取同一操作的 `started_ticks_usec` 记录阶段，不再平行缓存一份系统 tick。
4. 只有 Boot 组合根和 `features/asset_library/tools/` 下的离线素材工具可以直接访问 `Time`；该例外由 GF 合规测试的精确路径 allowlist 约束，不得扩散到运行时 Feature。
5. 开发构建由 `GameDiagnosticsUtility` 组合 GF Diagnostics、Asset Metadata、Debug Overlay、Runtime Inspector 与 Screenshot；发布构建不安装调试界面。支持报告在同一时点收集项目快照、当前场景资产元数据和 Viewport 截图。

### 持久化

- `persistence` 创建 `player_data` 根 Scope，并通过 `GFSaveGraphUtility` 统一校验、阶段排序、事务应用和诊断。
- `progress`、`bookmarks` 与 `replays` 各自拥有严格 section Provider；`app` 在 GF `init()` 前完成组合，不把业务字段写入 persistence。
- 三个 section 按 `EARLY`、`NORMAL`、`LATE` 写入同一个 Binary `player_data.save`；`GFStorageUtility` 负责存储元数据、checksum 和原子文件事务。
- 书签和回放使用 UUID v7 稳定身份，不依赖时间戳文件名或运行时 `file_path`。
- `bookmarks` section 当前 schema 为 v3；规则统计使用中性的 `ratio_resolutions`，并把目标值与达成状态作为严格语义契约，不提供旧阵营字段推断或兼容分支。
- 设置使用 `GFSettingsUtility` 的独立文件，不参与玩家数据图，也不随书签或回放恢复。
- 存档 Schema 发生破坏性变化时使用显式迁移工具；运行时代码不长期保留旧字段双读分支。

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
- GF 实现只能在独立的干净 worktree 和非 `main` 分支完成，通过对应 issue 的 PR、GF 自身测试与维护门禁合并；禁止直接向 GF `main` 提交或推送框架改动。
- 项目与 GF 的改动不得混在同一提交或 PR。项目可以先提交不依赖框架修改的调用侧改进；必须等待 GF PR 合并后，才能通过正式 vendor 更新流程同步新的上游提交。
- 同步 GF 时必须更新 `.gf/vendor.lock.json`，运行 vendor 完整性、GUT、LSP、Feature-Cohesive 和退出泄漏验证，并在项目提交中引用上游 issue、PR 与精确 source commit。
- GF 工作区存在未提交改动时只允许只读分析；不得代替所有者整理、覆盖、提交或推送这些改动。需要开发框架修复时另建干净 worktree。

## 验证门禁

- `GFProjectLayoutValidator` 的 error 与 warning 必须同时为零。
- `test_gf_project_conformance.gd` 必须保证 GF 弃用 API、全局架构旁路和早期生命周期依赖访问均为零。
- GDScript 规范扫描覆盖 `app/`、`features/`、`shared/`、`tests/gut/` 和 `tools/`。
- LSP 必须零 error、零 warning。
- 关键 Feature 变更先运行定向 GUT，再运行完整安全 GUT。
- 任何旧根目录引用、重复 Feature 前缀或不存在的 `res://` 路径都属于提交阻断问题。

具体命令见 `docs/validation.md`。
