# 架构说明

本项目是 Godot 4.7 与 GF Framework 7.x 的 2048 示例项目。目录严格采用 GF 内置 `Feature-Cohesive` 契约：业务能力优先内聚在 Feature 内，GF 的 Model、System、Utility、Controller 等是 Feature 内部的逻辑层，不再作为项目根目录的类型桶。

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
| `navigation` | 场景路由、主菜单、模式选择、UI Route 注册表 |
| `settings` | 应用设置模型、设置持久化和设置界面 |
| `bookmarks` | 书签数据、保存流程、列表和预览入口 |
| `replays` | 回放数据、回放输入、播放流程、列表和继续游戏入口 |
| `progress` | 最高分、统计和 GF save slot 工作流 |
| `themes` | 视觉主题、音效主题、UI 色板、棋盘反馈和主题内容包 |
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
2. Boot 调用 `await Gf.init()`。
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
3. `GFCommandHistoryUtility` 保存可撤销状态。
4. 业务事件携带动画指令到 `GameBoardController`。
5. `BoardTweenBatchAction` 把同一批已有 Tween 适配成可等待的 `GFVisualAction`。
6. `GFActionQueueSystem` 等待整批移动、合并、生成或撤回 Tween，并拥有暂停、完成与取消生命周期；棋盘 Action 不使用 fire-and-forget。

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

### 持久化

- `progress` 管理最高分和统计 save slot。
- `bookmarks` 与 `replays` 拥有各自业务 Resource。
- `shared/SavedResourceCollectionUtility` 只封装两者共同需要的 GFStorage 集合操作。
- 存档 Schema 发生破坏性变化时使用显式迁移工具；运行时代码不长期保留旧字段双读分支。

## GF 扩展

当前启用：

- `gf.action_queue`
- `gf.asset_metadata`
- `gf.content_package`
- `gf.domain`
- `gf.feedback`
- `gf.save`

Installer 不得重复绑定这些扩展拥有的模块。启用扩展但不使用其核心能力时，应明确采用或关闭，不能用自动注册数量虚增 GF 利用率。

## 验证门禁

- `GFProjectLayoutValidator` 的 error 与 warning 必须同时为零。
- `test_gf_project_conformance.gd` 必须保证 GF 弃用 API、全局架构旁路和早期生命周期依赖访问均为零。
- GDScript 规范扫描覆盖 `app/`、`features/`、`shared/`、`tests/gut/` 和 `tools/`。
- LSP 必须零 error、零 warning。
- 关键 Feature 变更先运行定向 GUT，再运行完整安全 GUT。
- 任何旧根目录引用、重复 Feature 前缀或不存在的 `res://` 路径都属于提交阻断问题。

具体命令见 `docs/validation.md`。
