# 2048 All In One AI 维护指南

本文档只给 AI 维护者使用，不作为面向普通玩家的正式说明。它用于约束 AI 辅助维护 `2048-all-in-one` 时的工作方式：优先把本项目当作 gf 框架的实战示例来开发，同时把开发中暴露出的框架问题沉淀为可反哺 gf 的改进点。

## 项目定位

- 本项目是 Godot 4.6+ 与 gf 的 2048 实战示例，不是一个脱离框架的普通小游戏仓库。
- gf 当前版本以 `addons/gf/plugin.cfg` 中的 `version` 字段为唯一来源。维护文档、README 和测试说明不应硬编码具体 gf 版本号；只有框架升级提交本身需要修改 `plugin.cfg`。
- 业务代码应尽量展示 gf 的核心能力：`GFInstaller`、`GFModel`、`GFSystem`、`GFController`、`GFUtility`、事件系统、命令历史、资源化输入、资源化规则、存储、场景工具、对象池、动作队列和设置绑定。
- 当发现 gf 难以表达项目需求时，先判断问题属于示例项目建模不足、框架 API 可用性不足，还是框架缺陷。只有后两者才考虑修改 `addons/gf/**`。
- 如果需要改 `addons/gf/**`，改动必须保持通用性和抽象性，不能把 2048 的玩法、UI、存档字段或资源路径写进 gf 框架。
- 如果临时修改 `addons/gf/**` 且该改动尚未纳入当前 gf 版本，必须单独记录问题场景、必要性和修改方案思路；当 gf 新版本已包含对应改动后，应删除过时记录。
- `addons/gut/**` 是测试插件代码，除非任务明确要求处理 GUT，否则不要修改。

## 核心规则

- 使用 UTF-8 读取和写入文件。
- GDScript 必须遵循 `CODING_STYLE.md`，尤其是 section 顺序、公共 API 文档、类型提示、Tab 缩进、LF 换行和文件末尾空行。
- 项目文件命名遵循 gf 示例约定：脚本、场景、资源文件和项目目录使用 `snake_case`；`scripts/**` 中的脚本必须声明 `class_name`，类名应由文件名派生为 `PascalCase`，架构层脚本必须保留 `Model/System/Controller/Utility/Rule/State/Action/Command/Query` 等后缀。
- 优先阅读现有项目形态再改代码：`README.md`、`CODING_STYLE.md`、`scripts/boot/game_architecture_installer.gd`、相关 `scripts/**`、相关 `resources/**` 和 `tests/gut/**`。
- 不要提交临时分析、调试报告、AI 会话记录或一次性生成文件。
- 不要把框架限制绕到业务层长期堆积；如果确认为 gf 能力缺口，应在实现中保留清晰边界，并在回复中说明反哺建议。

## 架构速览

- 启动入口：`scenes/boot/boot.tscn` 挂载 `scripts/boot/boot.gd`，调用 `await Gf.init()` 后交给 `SceneRouterSystem` 切到主菜单。
- gf 装配入口：`scripts/boot/game_architecture_installer.gd` 注册项目 Model、System、Utility，并通过 Project Settings 的 `gf/project/installers` 接入。
- 场景控制器：`scripts/controllers/**` 放置直接继承 `GFController` 的游戏场景控制器，类名保留 `Controller` 后缀。
- 状态模型：`scripts/models/**` 保存棋盘、当前模式、分数、最高分、设置选择等可绑定状态，类名保留 `Model` 后缀。
- 业务系统：`scripts/systems/**` 负责初始化、输入、移动、生成、状态流转、存档、书签、回放和场景路由。
- 项目 Utility：`scripts/utilities/**` 承接项目级 gf Utility，例如设置过滤、模式配置缓存和基于 `GFStorageUtility` 的时间戳 Resource 集合持久化。
- 规则资源：`scripts/rules/**` 定义移动、交互、生成、结束判定；`resources/modes/*.tres` 组合这些规则形成不同玩法模式。
- 对局 session：`GameInitSystem` 使用 `GFLevelUtility` 记录当前一局的模式、尺寸、种子和来源；这只是运行时 session 语义，不代表项目引入关卡进度玩法。
- 模式目录：`resources/registries/game_mode_registry.tres` 使用 `GFResourceRegistry` 维护可玩模式列表，项目层通过 `GameModeConfigCacheUtility` 读取并复用 `GFAssetUtility` 缓存。
- UI 路由：`resources/registries/ui_route_registry.tres` 使用 `GFResourceRegistry` 维护 `GFUIRoute` 资源目录；`GameUiRouterUtility` 作为 `GFUIRouterUtility` 的项目级 Adapter 从注册表加载暂停、游戏结束和设置面板 route_id。业务 UI 优先按 route_id 打开面板，必要时才回退到 `GFUIUtility` 路径调用。
- 表现层：`scripts/ui/**`、`scripts/menus/**` 负责菜单、HUD、列表项和弹层界面。
- 数据与基础能力：`scripts/data/**` 放置 Resource、Payload 和纯数据对象；`scripts/foundation/**` 放置不接入 gf 生命周期的纯静态算法。
- 配置校验：模式配置应优先使用 `GFValidationReport` 汇总问题，再由调用方决定是否 `push_error` 或写日志。

## 开发流程

1. 先确认变更属于哪一类：玩法规则、UI/菜单、存档/回放、gf 示例用法、gf 框架反哺或维护测试。
2. 找到已有 gf 用法并复用。例如跨模块通信优先用事件或 Model，玩家操作优先走 `GFCommandHistoryUtility`，输入优先走 `GFInputMappingUtility`，场景跳转优先走 `SceneRouterSystem` / `GFSceneUtility`。
3. 保持边界清晰。规则资源不要直接触达全局 `Gf`；需要上下文时优先使用 `RuleContext` 或由 System 注入。
4. 涉及资源组合时，同步检查 `.gd`、`.tres`、`.tscn`、翻译和 README 是否仍一致。
5. 涉及公开方法、信号、导出变量、Resource 字段或存档格式时，同步补齐 `##` 文档和聚焦测试。
6. 修改后运行相关 GUT 测试；如果无法运行，明确说明原因和剩余风险。

## 按变更类型检查文件

### 玩法规则或模式变更

检查并按需更新：

- `scripts/rules/**`
- `scripts/data/game_mode_config.gd`
- `resources/rules/**`
- `resources/modes/*.tres`
- `resources/registries/game_mode_registry.tres`
- `resources/themes/**`
- `scripts/systems/rule_system.gd`
- `scripts/systems/game_init_system.gd`
- `scripts/queries/get_hud_stats_query.gd`
- `assets/translations.csv`
- `README.md` 的模式说明或新增模式流程

规则实现应保持资源化和可组合，不要让某个模式的特殊逻辑污染基础规则类。

### 输入、移动、撤销或回放变更

检查并按需更新：

- `resources/input/gameplay_input_context.tres`
- `resources/input/replay_input_context.tres`
- `scripts/systems/player_input_system.gd`
- `scripts/systems/replay_input_system.gd`
- `scripts/systems/grid_movement_system.gd`
- `scripts/commands/move_command.gd`
- `scripts/systems/replay_system.gd`
- `scripts/data/replay_data.gd`

玩家移动应继续通过 `MoveCommand` 和 `GFCommandHistoryUtility` 记录，确保撤销、书签和回放共享同一套状态语义。

### 存档、书签或设置变更

检查并按需更新：

- `scripts/systems/save_system.gd`
- `scripts/systems/bookmark_system.gd`
- `scripts/systems/game_state_system.gd`
- `scripts/data/bookmark_data.gd`
- `scripts/data/replay_data.gd`
- `scripts/utilities/saved_resource_collection_utility.gd`
- `scripts/utilities/game_settings_utility.gd`
- `scripts/boot/game_architecture_installer.gd`
- `scripts/menus/settings_menu.gd`

存档字段变化属于高风险改动。要考虑旧数据兼容、默认值、完整性校验、Resource 保存路径和回放/书签恢复流程。书签和回放的文件集合逻辑应优先复用 `SavedResourceCollectionUtility`，不要在各自 System 中重复实现目录枚举、路径写回和时间戳排序。

### UI、菜单或表现变更

检查并按需更新：

- `scenes/**/*.tscn`
- `resources/registries/ui_route_registry.tres`
- `resources/ui_routes/*.tres`
- `scripts/utilities/game_ui_router_utility.gd`
- `scripts/utilities/game_ui_motion_utility.gd`
- `scripts/utilities/game_board_feedback_utility.gd`
- `scripts/controllers/game_play_controller.gd`
- `scripts/controllers/game_board_controller.gd`
- `scripts/ui/**`
- `scripts/menus/**`
- `assets/translations.csv`
- `resources/themes/**`

表现层应继续通过事件接收业务结果，不要把棋盘算法或存档语义写进 UI 节点。

### gf 框架反哺变更

只有任务明确要求，或示例项目无法合理表达通用需求时，才修改：

- `addons/gf/**`
- `addons/gf/README.md`
- `addons/gf/plugin.cfg`，仅在明确升级框架版本时

修改 gf 时必须遵守：

- 先尝试项目层方案；只有项目层方案会绕开 gf 示例目标、造成重复补丁或无法表达通用能力时，才修改 gf。
- 不能引用本项目的 2048 类型、路径、文案、资源或玩法概念。
- 保持向后兼容，除非维护者明确批准破坏性升级。
- 优先为 gf 增加通用能力、诊断、校验或文档，而不是为示例项目写特例。
- 临时框架补丁必须有简短记录；当前 gf 版本已包含后删除该记录，避免维护噪音。
- 在最终回复中单独说明：为什么需要改框架、这个改动如何服务其他项目、还发现了哪些后续框架缺口。

当前临时框架补丁：

- gf Utility 退出清理：`GFUIUtility`、`GFObjectPoolUtility`、`GFConsoleUtility`、`GFDebugOverlayUtility`、`GFScreenTransitionUtility` 在 `dispose()` 或销毁辅助函数中避免同步 `remove_child()` 后再 `queue_free()`。问题场景是 Godot 退出时 autoload `_exit_tree()` 触发架构 dispose，此时父节点可能正忙于 children 变更；直接 `queue_free()` 让引擎在安全点释放节点，可避免 `Parent node is busy adding/removing children`。当 gf 上游包含等价修复后删除本记录。

### 文档变更

检查并按需更新：

- `README.md`：项目定位、技术栈、架构概览、gf 使用方式、新模式流程。
- `CODING_STYLE.md`：只有团队规范变化时更新。
- `AI_MAINTENANCE.md`：只有 AI 工作流程或维护边界变化时更新。
- `addons/gf/README.md`：仅当修改了可复用 gf 框架能力时更新。

## 公开 API 与注释

本项目中的公开 API 包括：

- `class_name`
- 信号
- 枚举
- 常量、导出变量和公共变量
- 不以下划线开头的公共函数
- Resource 字段
- Project Settings 项
- 输入 action、简单事件名、存档/回放/书签字段

要求：

- 带 `class_name` 的脚本顶部必须先有文件级 `##` 说明，再声明 `class_name` 和 `extends`。
- 公共函数如果有参数，`## @param` 必须与函数签名双向一致，顺序也要一致。
- 修改存档、回放、书签或事件 payload 时，应更新相关数据类文档和恢复逻辑。
- 下划线方法即使被框架约定调用，也仍然归类到生命周期、可重写钩子、私有/辅助或信号处理 section。

## 维护测试

本项目的静态维护测试位于：

- `tests/gut/test_api_docs_validation.gd`
- `tests/gut/test_gdscript_layout_validation.gd`

它们扫描示例项目源码和项目测试，不扫描 `addons/gf/**` 或 `addons/gut/**`。这些测试用于把 `CODING_STYLE.md` 中能稳定机器判断的规则固定下来。

运行命令：

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -ginclude_subdirs -gexit
```

如果只改了文档，可以不运行 GUT，但应检查链接、路径和项目定位是否准确。只要改了 `.gd`，优先运行上述命令。

## AI 临时工作区

如需本地临时记录，使用 `ai_analysis/`。该目录应保持被 Git 忽略，不作为正式项目文件。

建议用途：

- `ai_analysis/todo.md`：大型任务的临时拆解。
- `ai_analysis/reports/`：一次性检查结果。
- `ai_analysis/context.md`：跨轮维护时的事实摘要。

使用规则：

- 内容只记录恢复上下文所需事实，不写成正式文档。
- 不提交该目录。
- 不在 README 或项目说明中把它写成必需文件。
