# 架构说明

本项目是 Godot 4.7 + GF Framework 7.x 的 2048 示例项目。目标不是把所有逻辑塞进场景脚本，而是展示中小型游戏如何用 GF 的 Model、System、Utility、Controller、事件、资源注册和包管理组织功能。

## 启动链路

1. `scenes/boot/boot.tscn` 加载 `scripts/boot/boot.gd`，先绘制启动画面和印刷风格进度条。
2. `boot.gd` 通过 `GFAsyncProgress` 发布启动阶段进度，并调用 `await Gf.init()`。
3. GF 根据 `project.godot` 的 `gf/project/installers` 运行 `GameArchitectureInstaller`。
4. 项目注册 Model、Utility、System。
5. `Boot` 通过 `GFSceneUtility.preload_scene()` 预热主菜单。
6. `SceneRouterSystem` 接管初始场景流转。

GF AutoLoad 使用 `project.godot` 中的 `Gf="*uid://dftf1eh06apl0"`，对应 `addons/gf/kernel/core/gf.gd.uid`。

## GF 包和扩展

GF 框架版本以 `addons/gf/plugin.cfg` 为准，当前源码版本为 `7.0.0`。

启用扩展：

- `gf.domain`
- `gf.action_queue`
- `gf.content_package`
- `gf.feedback`
- `gf.save`

当前仓库是手动更新后的 vendored GF 源码状态，不应假设 `.gf/packages.lock.json` 一定存在。GF 7 的包管理入口是 `res://addons/gf/kernel/package/gf_package_cli.gd`；后续如果恢复包管理器安装流，需要重新生成 lockfile，并同步本文档、`README.md`、`docs/VALIDATION.md` 和包状态测试。

项目实际使用的 GF 能力包括：

- `gf.domain`
- `gf.action_queue`
- `gf.content_package`
- `gf.standard.deterministic`
- `gf.standard.input`
- `gf.standard.state_machine`
- `gf.standard.ui`
- `gf.standard.storage`
- `gf.standard.assets`
- `gf.standard.config`
- `gf.standard.diagnostics`
- `gf.standard.audio`

## Module 分层

### Boot Module

主要文件：

- `scripts/boot/boot.gd`
- `scripts/boot/game_architecture_installer.gd`

职责：

- 启动 GF。
- 显示启动画面和真实启动进度。
- 注册项目 Model、Utility、System。
- 通过 `GFSceneUtility` 预热主菜单，避免进入主菜单时突然空白等待。
- 保持项目 Installer 只注册项目自身模块；GF 扩展模块由扩展 Installer 装配。
- `gf.domain` 拥有 `GFLevelUtility` / `GFQuestUtility`，`gf.action_queue` 拥有 `GFActionQueueSystem`，`gf.content_package` 拥有 `GFContentPackageUtility`；项目 Installer 不手动绑定这些 Module。

当前风险：

- `GameArchitectureInstaller` 是高集中度装配点。它有价值，但需要持续避免把业务初始化、资源加载和调试工具逻辑都塞进同一个外部接口。
- `tests/gut/test_architecture_installer_validation.gd` 会静态检查项目 Installer 不重复绑定扩展 owned Module。
- `tests/gut/test_gf_package_validation.gd` 会静态检查 GF lockfile、`project.godot` 启用扩展和 `.gitignore` 的包缓存规则保持一致。

### Model Module

主要目录：

- `scripts/models/`

职责：

- 保存运行时状态：棋盘、当前模式、分数、最高方块、应用配置。
- 作为 System、Controller 和 Query 的共享状态接口。

原则：

- Model 应表达状态，不承担场景节点操作。
- 可序列化字段变化需要同步检查存档、回放、书签和测试。

### System Module

主要目录：

- `scripts/systems/`

职责：

- 处理业务流程：游戏初始化、输入、移动、生成、状态流转、存档、书签、回放、场景路由。
- 通过 GF 的 Model/System/Utility 查询接口协作。
- 通过事件或 Command 降低场景脚本之间的直接耦合。

重点接口：

- 玩家移动通过 `MoveCommand` 和 `GFCommandHistoryUtility` 进入历史。
- 回放和书签复用持久化资源集合。
- 对局初始化通过 `GFLevelUtility` 登记当前 session。
- 场景切换通过 `GFSceneUtility` 异步加载，`SceneRouterSystem` 负责业务路由和半调纸媒转场遮罩。

### Utility Module

主要目录：

- `scripts/utilities/`

职责：

- 承接项目级 Adapter 和可复用工具。
- 把 GF 通用能力接到 2048 的资源、场景、设置和视觉表现上。

当前重要 Utility：

- `ProjectResourceCatalogUtility`：把 `GFResourceRegistry`、`GFResourceResolverUtility` 和 `GFAssetUtility` 的组合用法集中成项目资源目录 Adapter。
- `GameModeConfigCacheUtility`：通过 `ProjectResourceCatalogUtility` 读取模式目录、注册稳定资源键并复用 `GFAssetUtility` 缓存。
- `GameUiRouterUtility`：作为 `GFUIRouterUtility` 的项目 Adapter，从 UI 路由注册表加载 `GFUIRoute`。
- `GameSettingsUtility`：承接 `GFSettingsUtility` 和项目设置字段，统一声明语言、显示、音量、视觉主题和音效主题默认值。
- `GameSaveSlotWorkflowUtility`：承接 `GFSaveSlotWorkflow`、`GFSaveSlotMetadata` 和 `GFSaveSlotCard`，把最高分/统计保存到稳定 GF save slot。
- `GameAssetLibraryUtility`：承接 `GFContentPackageUtility`、`GFResourceResolverUtility` 和 `GFContentPackageExportPlan`，注册项目内通用素材库、解析稳定 `asset.*` 资源键并生成素材审计报告。
- `GameThemeCatalogUtility`：承接 `GFContentPackageUtility` 和 `GFResourceResolverUtility`，注册内置主题内容包并加载主题注册表。
- `GameThemeUtility`：承接 `GFSettingsUtility`、`GameThemeCatalogUtility`、`GameUiMotionUtility` 和 `GFAudioUtility`，解析当前视觉主题和音效主题。
- `SavedResourceCollectionUtility`：复用 `GFStorageUtility` 保存时间戳 Resource 集合。
- `GameClockUtility`：集中 wall-clock 时间戳、短文件名 tick 和用户可读日期格式；`GFTimeUtility` 仍负责游戏 delta、缩放和暂停。
- `GameUiMotionUtility`：统一菜单、按钮、面板和列表动效；设置页、模式配置和调试面板选项通过 `GFItemListBinder` 写入 OptionButton。
- `GameBoardFeedbackUtility`：统一棋盘表现反馈，和 `GFActionQueueSystem` 协作，并通过 `GFShakeUtility` 播放 board channel 反馈。

深化方向：

- 回放/书签列表通过 `GFRepeaterBinder` 复制列表项模板并集中配置业务信号；`GFVirtualListModel` 暂不接入，留给未来大量历史记录场景。
- 视觉主题资源已经成为主要真相来源，但场景内仍有散落 `theme_override_*`，后续应继续收敛到主题资源与 `GameUiMotionUtility`。

### Controller Module

主要目录：

- `scripts/controllers/`

职责：

- 连接场景节点和 GF 架构。
- 读取 Model/System/Utility，驱动画面刷新和玩家交互。

当前实现说明：

- 项目脚本使用显式 `res://addons/gf/...` 继承路径，而不是裸 `extends GFController`。这是 GF 升级后为了规避 Godot class cache 未刷新时解析失败的兼容策略。
- 如果未来确认 Godot class cache 稳定，可以评估是否恢复裸类名继承；恢复前必须能安全运行解析和测试。

### Rule Module

主要目录：

- `scripts/rules/`
- `resources/rules/`
- `resources/modes/`

职责：

- 把移动、交互、生成、结束判定拆为可组合资源。
- `GameModeConfig` 组合规则、主题和棋盘参数。

原则：

- 规则资源不直接触达全局 `Gf`。
- 规则需要上下文时通过 `RuleContext` 注入。
- 新模式优先新增资源组合，而不是修改基础规则的模式特例。

### UI Module

主要目录：

- `scripts/ui/`
- `scripts/menus/`
- `scenes/ui/`
- `scenes/menus/`
- `resources/ui_routes/`

职责：

- 管理菜单、HUD、弹层、列表项和设置界面。
- UI 弹层通过 `GFUIRoute` 和 `GameUiRouterUtility` 按 route id 打开。
- 交互动效通过 `GameUiMotionUtility` 统一。

原则：

- UI 不写棋盘算法、存档格式或规则判断。
- UI 通过事件、Controller 或 Query 获取业务状态。
- 所有视觉风格变化应同步 `docs/VISUAL_STYLE.md`。

## 数据流示例

### 玩家移动

1. `PlayerInputSystem` 从 `GFInputMappingUtility` 消费输入。
2. 系统发送移动意图或执行 `MoveCommand`。
3. `MoveCommand` 调用移动相关 System 更新 `GridModel`。
4. `GFCommandHistoryUtility` 记录历史。
5. `GameBoardController` 根据模型变化和动画指令刷新 Tile。
6. `GFActionQueueSystem` 执行视觉 Action。

### 新游戏

1. 菜单选择模式和棋盘大小。
2. `SceneRouterSystem` 通过 `GFSceneUtility` 切到游戏场景，并播放半调纸媒场景转场遮罩。
3. `GameInitSystem` 读取 `GameModeConfig`。
4. `RuleSystem` 配置规则。
5. `GFSeedUtility` 处理初始种子。
6. `GFLevelUtility` 登记当前 2048 session。
7. 棋盘生成初始方块并进入游戏状态。

### UI 弹层

1. 业务代码按 route id 请求打开暂停、设置或游戏结束界面。
2. `ProjectResourceCatalogUtility` 将 `ui_route_registry.tres` 中的路由注册为稳定资源键，`GameUiRouterUtility` 找到并加载 `GFUIRoute`。
3. `GFUIUtility` 将面板压入对应 UI layer。
4. `GameUiMotionUtility` 绑定按钮和播放入场动效。

### 主题切换

1. 设置页通过 `GFFormBinder` 写入 `appearance/theme_id` 和 `audio/sound_theme_id`。
2. `GameThemeCatalogUtility` 通过 `GFContentPackageUtility` 把 `resources/gf_content_package.json` 注册到 `GFResourceResolverUtility`。
3. `GameThemeUtility` 通过 `GameThemeCatalogUtility` 使用 `game.theme_registry` 资源键解析 `GameTheme` / `GameAudioTheme`。
4. `GameUiMotionUtility` 接收 `GameUiPalette` 并刷新当前 UI 树。
5. `GamePlayController` 和 `BoardPreview` 通过当前 `GameTheme` 解析 `BoardTheme` 和 `TileColorScheme`，运行中切换时用 `GridModel` 快照重绘棋盘。
6. `GFAudioUtility` 接收主题音频银行；当前 `printworks` 主题使用 Universal UI Soundpack 中筛选出的 UI / tile / game over OGG 素材，后续继续打磨音色、响度和混音。

### 素材库

1. `asset_library/gf_content_package.json` 维护可复用素材包，资源键统一使用 `asset.*` 前缀。
2. `GameAssetLibraryUtility` 注册 `res://asset_library` source root，并把资源键同步到 `GFResourceResolverUtility`。
3. 首批音频和 shader 都从 `asset_library/` 路径引用；主题包声明依赖 `c76.asset_library.core`。
4. `tools/audit_asset_library.ps1` 生成 `asset_library/reports/asset_audit.json` 和 `.md`，报告素材存在性、元数据、未登记文件和项目引用者。

### 统计存档

1. `SaveSystem` 维护最高分和轻量统计的业务字典 Interface。
2. `GameSaveSlotWorkflowUtility` 把业务字典写入 `GameSaveSlotWorkflowUtility.MAIN_STATS_SLOT_INDEX`。
3. `GFSaveSlotWorkflow` 构建 `GFSaveSlotMetadata`，记录 `game_stats` schema、总局数和最高分摘要。
4. `GFStorageUtility.save_slot()` 原子写入数据和元数据；UI 或调试工具可通过 `GFSaveSlotCard` 获取通用槽位摘要。

## 配套文档

- `docs/SAVE_MODEL.md`：设置、最高分/统计 GF save slot、书签、回放和后续 save graph 扩展边界。
- `docs/VISUAL_STYLE.md`：CMYK 半调纸媒游戏的视觉方向、色彩、纹理和动效约束。
- `docs/VALIDATION.md`：安全验证命令、GUT 隔离运行策略和当前验证缺口。

## 待补事项

- 安全 GUT 链路：`tools/run_gut_safe.ps1` 已完成一次隔离烟雾验证；仍建议用用户编辑器一致的 Godot `4.7` 可执行文件复测。
