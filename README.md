# 2048 All In One

一个基于 Godot 4 和 gf 的可扩展 2048 规则实验项目。项目把棋盘数据、规则、输入、存档、设置、回放和 UI 流程拆成独立模块，目标是作为 gf 框架在中小型游戏中的最佳实践示例。

> **⚠️ 重要提示：作为 gf 框架实例项目的定位**
>
> 本项目主要作为 **gf 框架** 的最佳实践和实例展示。如果在开发或使用过程中发现问题，**允许修改和优化以反哺 gf 框架**。但在进行修改时，**务必严格遵循 gf 框架的规范**，保持代码的**通用性和抽象性**，绝对避免让 gf 框架去实现特定于任何项目的具体业务逻辑。

## 技术栈

- Godot 4.7+
- GF Framework 7.x（版本以 `addons/gf/plugin.cfg` 为准，当前源码为 `7.0.0`）
- GF Package Manager（GF 7 使用 Godot 原生 CLI；当前仓库为手动更新后的 vendored GF 源码状态，`.gf/packages.lock.json` 可能暂时不存在）
- GDScript，遵循 `docs/coding_style.md`

## 架构概览

- 项目严格采用 GF 内置的 Feature-Cohesive 目录契约，`gf_project_profile.json` 是可执行的结构真相来源。
- `app/` 只包含启动、Composition Root 和跨 Feature 装配；`app/scripts/game_architecture_installer.gd` 声明项目 Model、System、Utility。
- `features/` 按业务能力划分为 gameplay、navigation、settings、bookmarks、replays、progress、themes、asset_library 和 diagnostics。
- 每个 Feature 在自己的 `scripts/`、`scenes/`、`resources/`、`docs/` 或 `tools/` 内拥有完整实现；GF 的 Model/System/Utility/Controller 是 Feature 内部逻辑层。
- `shared/` 只保存跨 Feature 复用的契约、基础算法、UI 原语、素材和 Utility，不得引用具体 Feature。
- 旧的全局 `scripts/`、`scenes/`、`resources/`、`assets/` 和 `asset_library/` 类型桶不再使用，也不提供旧路径兼容。
- `features/gameplay/scripts/rules/` 是规则实现层。移动、交互、生成、结束判定互相解耦，模式配置通过 `features/gameplay/resources/modes/*.tres` 组合它们。
- `features/gameplay/resources/input/gameplay_input_context.tres` 使用 `GFInputContext` / `GFInputMapping` 描述玩法输入，运行时由 `GFInputMappingUtility` 消费。
- `features/gameplay/resources/registries/game_mode_registry.tres` 使用 `GFResourceRegistry` 维护可玩模式目录，菜单和初始化流程通过 `ProjectResourceCatalogUtility` / `GameModeConfigCacheUtility` 读取注册表。
- `features/navigation/resources/registries/ui_route_registry.tres` 使用 `GFResourceRegistry` 维护 UI 路由目录，`features/navigation/resources/ui_routes/*.tres` 用 `GFUIRoute` 描述弹层面板，并通过 `ProjectResourceCatalogUtility` 注册到资源解析器。
- `shared/assets/translations.csv` 提供中文和英文 UI 文案。

完整 Feature 所有权和依赖方向见 `docs/architecture.md`。

## gf 使用方式

项目启动入口是 `app/scenes/boot.tscn`。`boot.gd` 调用 `await Gf.init()`，gf 会执行项目级 installer 并完成三阶段生命周期。业务模块内部优先使用 `GFSystem` / `GFController` 的基类方法访问 Model、System、Utility 和事件总线。

当前启用的 GF 扩展：

- `gf.domain`
- `gf.action_queue`
- `gf.content_package`
- `gf.feedback`
- `gf.save`

当前项目直接依赖的 GF 能力：

- `gf.domain` 提供运行时 session、领域模型与通用进度语义。
- `gf.action_queue` 提供棋盘视觉动作队列。
- GF standard utilities 提供输入、状态机、资源注册、存储、设置、场景、UI、对象池、随机种子和诊断等能力。

GF 7 的包管理入口是 `res://addons/gf/kernel/package/gf_package_cli.gd`。如果后续重新使用包管理器安装/更新 GF 包，应让 `.gf/packages.lock.json` 与 `addons/gf/plugin.cfg`、`project.godot` 的扩展启用状态保持一致；`.gf/package_cache/` 是下载缓存，已在 `.gitignore` 中忽略。

当前重点实践：

- 用项目级 installer 管理注册顺序。
- 用 `GFCommandHistoryUtility.execute_command()`、`undo_last_async()` 和 `redo_async()` 管理移动命令、撤销与重做。
- 用 `GFInputMappingUtility` 管理资源化输入上下文。
- 用 `GFSceneUtility` 做异步场景切换，`SceneRouterSystem` 负责业务事件、路由意图和半调纸媒转场遮罩。
- 用项目级 `GameUiRouterUtility` 从 `ui_route_registry.tres` 加载 `GFUIRoute` 路由表，暂停、游戏结束和设置面板通过稳定 route_id 打开。
- 用项目级 `GameSettingsUtility` 承接 `GFSettingsUtility` / `GFDisplaySettingsUtility`，语言、显示、音量、视觉主题和音效主题通过 `GFFormBinder` 绑定到设置页控件，选项列表用 `GFItemListBinder` 写入。
- 用项目级 `GameSaveGraphUtility` 组合 `GFSaveGraphUtility` / `GFSaveScope` / `GFSaveDataSource`，把统计、书签和回放作为三个 Feature section 原子保存到类型保真的 Binary 玩家数据图；设置保持独立生命周期。
- 用 `GFLevelUtility` 把当前一局登记为运行时 session，集中清理命令历史与动作队列等对局残留；项目不把 2048 强行建模为关卡进度。
- 用 `ProjectResourceCatalogUtility` 把 `GFResourceRegistry`、`GFResourceResolverUtility` 和 `GFAssetUtility` 组合成统一资源目录 Adapter，模式目录和 UI 路由目录不重复实现注册、解析和缓存细节。
- 用 `GameThemeCatalogUtility` 承接 `gf.content_package` 的 `GFContentPackageUtility`，注册内置主题内容包，并通过 `GFResourceResolverUtility` 用稳定资源键加载主题注册表。
- 用 `GFObjectPoolUtility` 的池化 Hook 清理 Tile 复用状态，并用 `GFRepeaterBinder` 重建书签/回放列表项。
- 用项目级 `GameUiMotionUtility` 统一菜单、按钮、HUD 和列表刷新动效，避免各 UI 节点重复编写 Tween。
- 用项目级 `GameBoardFeedbackUtility` 统一棋盘合并、生成和转化反馈特效，表现触发点跟随 `GFActionQueueSystem` 中的视觉 Action，并通过 `GFShakeUtility` 播放语义化 board channel 反馈。
- 用 `GFController.get_host_as()` 访问 Controller 宿主节点，避免依赖 Godot `owner` 语义。
- 用 `GFValidationReport` 汇总模式配置校验结果，再由项目层决定如何输出错误。
- 用 `RuleContext` 给规则注入上下文并收集输出，避免规则资源直接触达全局 `Gf`。
- 开发构建中由 `GameDiagnosticsUtility` 向 `GFDiagnosticsUtility` 注册项目快照 provider，并注册 `support_report` 控制台命令生成统一支持报告。

## 维护路线

- 长期推进计划见 `docs/roadmap.md`。
- 验证策略见 `docs/validation.md`，GF 7 包状态验证使用 Godot headless 原生包管理 CLI。
- 项目结构由 `gf_project_profile.json` 声明，并通过 `GFProjectLayoutValidator` 与 GUT 持续校验。
- 视觉方向见 `docs/visual_style.md`；背景、方块、菜单、HUD、转场和动效应保持 CMYK 半调纸媒游戏质感。
- 历史上默认 Godot/GUT 运行曾写出巨大用户目录日志；需要运行 GUT 时，使用 `tools/run_gut_safe.ps1` 这样的隔离脚本，不要直接运行裸 Godot/GUT 命令。

## 新增模式的推荐流程

1. 在 `features/gameplay/scripts/rules/` 中实现所需的 `InteractionRule`、`MovementRule`、`SpawnRule` 或 `GameOverRule`。
2. 在 `features/gameplay/resources/rules/` 中创建对应资源。
3. 新增 `features/gameplay/resources/modes/*.tres`，组合棋盘主题、颜色主题和规则资源。
4. 在 `features/gameplay/resources/registries/game_mode_registry.tres` 中新增 `GFResourceRegistryEntry`，让模式选择菜单自动读取新的模式资源。
