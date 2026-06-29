# 架构说明

本项目是 Godot 4.7 + GF Framework 7.x 的 2048 示例项目。目标不是把所有逻辑塞进场景脚本，而是展示中小型游戏如何用 GF 的 Model、System、Utility、Controller、事件、资源注册和包管理组织功能。

## 启动链路

1. `scenes/boot/boot.tscn` 加载 `scripts/boot/boot.gd`。
2. `boot.gd` 调用 `await Gf.init()`。
3. GF 根据 `project.godot` 的 `gf/project/installers` 运行 `GameArchitectureInstaller`。
4. 项目注册 Model、Utility、System。
5. `SceneRouterSystem` 接管初始场景流转。

GF AutoLoad 使用 `project.godot` 中的 `Gf="*uid://dftf1eh06apl0"`，对应 `addons/gf/kernel/core/gf.gd.uid`。

## GF 包和扩展

GF 框架版本以 `addons/gf/plugin.cfg` 为准，当前源码版本为 `7.0.0`。

启用扩展：

- `gf.domain`
- `gf.action_queue`

当前仓库是手动更新后的 vendored GF 源码状态，不应假设 `.gf/packages.lock.json` 一定存在。GF 7 的包管理入口是 `res://addons/gf/kernel/package/gf_package_cli.gd`；后续如果恢复包管理器安装流，需要重新生成 lockfile，并同步本文档、`README.md`、`docs/VALIDATION.md` 和包状态测试。

项目实际使用的 GF 能力包括：

- `gf.domain`
- `gf.action_queue`
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
- 注册项目 Model、Utility、System。
- 保持项目 Installer 只注册项目自身模块；GF 扩展模块由扩展 Installer 装配。
- `gf.domain` 拥有 `GFLevelUtility` / `GFQuestUtility`，`gf.action_queue` 拥有 `GFActionQueueSystem`；项目 Installer 不手动绑定这些 Module。

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

### Utility Module

主要目录：

- `scripts/utilities/`

职责：

- 承接项目级 Adapter 和可复用工具。
- 把 GF 通用能力接到 2048 的资源、场景、设置和视觉表现上。

当前重要 Utility：

- `GameModeConfigCacheUtility`：从 `GFResourceRegistry` 读取模式目录，并登记到 `GFAssetUtility`。
- `GameUiRouterUtility`：作为 `GFUIRouterUtility` 的项目 Adapter，从 UI 路由注册表加载 `GFUIRoute`。
- `GameSettingsUtility`：承接 `GFSettingsUtility` 和项目设置字段。
- `SavedResourceCollectionUtility`：复用 `GFStorageUtility` 保存时间戳 Resource 集合。
- `GameUiMotionUtility`：统一菜单、按钮、面板和列表动效。
- `GameBoardFeedbackUtility`：统一棋盘表现反馈，并和 `GFActionQueueSystem` 协作。

深化方向：

- 资源目录加载、排序、校验和 asset group 注册可以形成更深的内部 Module，减少模式目录和 UI 路由目录的重复知识。
- 存档集合 Utility 已经有复用价值，后续接入 `gf.extension.save` 前应先稳定它的接口。

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
2. `SceneRouterSystem` 切到游戏场景。
3. `GameInitSystem` 读取 `GameModeConfig`。
4. `RuleSystem` 配置规则。
5. `GFSeedUtility` 处理初始种子。
6. `GFLevelUtility` 登记当前 2048 session。
7. 棋盘生成初始方块并进入游戏状态。

### UI 弹层

1. 业务代码按 route id 请求打开暂停、设置或游戏结束界面。
2. `GameUiRouterUtility` 从 `ui_route_registry.tres` 找到 `GFUIRoute`。
3. `GFUIUtility` 将面板压入对应 UI layer。
4. `GameUiMotionUtility` 绑定按钮和播放入场动效。

## 配套文档

- `docs/SAVE_MODEL.md`：设置、最高分、书签、回放和未来 `gf.extension.save` 的接口。
- `docs/VISUAL_STYLE.md`：柔和肌理扁平风的视觉方向、色彩和噪点约束。
- `docs/VALIDATION.md`：安全验证命令、GUT 隔离运行策略和当前验证缺口。

## 待补事项

- 安全 GUT 链路：`tools/run_gut_safe.ps1` 已完成一次隔离烟雾验证；仍建议用用户编辑器一致的 Godot `4.7` 可执行文件复测。
