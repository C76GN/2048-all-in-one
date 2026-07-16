# 2048 All In One AI 维护指南

本文档只给 AI 维护者使用，不作为面向普通玩家的正式说明。它用于约束 AI 辅助维护 `2048-all-in-one` 时的工作方式：优先把本项目当作 gf 框架的实战示例来开发，同时把开发中暴露出的框架问题沉淀为可反哺 gf 的改进点。

## 项目定位

- 本项目是 Godot 4.7+ 与 gf 的 2048 实战示例，不是一个脱离框架的普通小游戏仓库。
- gf 当前版本以 `addons/gf/plugin.cfg` 中的 `version` 字段为唯一来源。维护文档、README 和测试说明不应硬编码具体 gf 版本号；只有框架升级提交本身需要修改 `plugin.cfg`。
- 当前 GF 源码是手动更新后的 vendored GF 7 状态。若 `.gf/packages.lock.json` 存在，GF Package Manager 的安装状态以它为准；若不存在，不要把旧 lockfile 假设当作当前事实。`.gf/package_cache/` 是下载缓存，不应提交。
- 业务代码应尽量展示 gf 的核心能力：`GFInstaller`、`GFModel`、`GFSystem`、`GFController`、`GFUtility`、事件系统、命令历史、资源化输入、资源化规则、存储、场景工具、对象池、动作队列和设置绑定。
- 当发现 gf 难以表达项目需求时，先判断问题属于示例项目建模不足、框架 API 可用性不足，还是框架缺陷。只有后两者才考虑修改 `addons/gf/**`。
- 如果需要改 `addons/gf/**`，改动必须保持通用性和抽象性，不能把 2048 的玩法、UI、存档字段或资源路径写进 gf 框架。
- 如果临时修改 `addons/gf/**` 且该改动尚未纳入当前 gf 版本，必须单独记录问题场景、必要性和修改方案思路；当 gf 新版本已包含对应改动后，应删除过时记录。
- `addons/gut/**` 是测试插件代码，除非任务明确要求处理 GUT，否则不要修改。

## 核心规则

- 使用 UTF-8 读取和写入文件。
- GDScript 必须遵循 `docs/coding_style.md`，尤其是 section 顺序、公共 API 文档、类型提示、Tab 缩进、LF 换行和文件末尾空行。
- 项目严格采用 GF Feature-Cohesive 契约。`app/**`、`features/**`、`shared/**`、`tests/**`、`tools/**` 和 `docs/**` 的手写路径使用 `snake_case`；项目脚本必须声明 `class_name`，类名严格由文件名执行 `to_pascal_case()` 得到，不保留缩写例外；GF 层脚本保留 `Model/System/Controller/Utility/Rule/State/Action/Command/Query` 等后缀。
- 优先阅读 `README.md`、`docs/architecture.md`、`docs/coding_style.md`、`app/scripts/game_architecture_installer.gd`、相关 Feature、`shared/**` 和 `tests/gut/**`。
- 新文件先确定 Feature 所有权，再确定 GF 层；禁止重新建立全局 `scripts/`、`scenes/`、`resources/`、`assets/` 或 `asset_library/` 类型桶。
- 默认不要启动 Godot 编辑器或裸 GUT 命令。历史上默认用户目录曾生成巨大日志；需要运行 GUT 时，优先使用 `tools/run_gut_safe.ps1`，并先以较短超时和较小日志上限做烟雾验证。
- Godot 编辑器中的 GDScript warning 不能只靠 GUT 判断。修改 `.gd` 后，尤其涉及 Variant、返回值、Signal 连接、`append()`、`erase()`、局部变量命名或 tool 脚本时，应运行 `tools/check_gdscript_lsp_diagnostics.ps1`。
- 不要提交临时分析、调试报告、AI 会话记录或一次性生成文件。
- 不要把框架限制绕到业务层长期堆积；如果确认为 gf 能力缺口，应在实现中保留清晰边界，并在回复中说明反哺建议。
- GF Module 的 `init()` / `async_init()` 不得直接或经 helper 获取跨模块依赖；统一在 `ready()` 解析。除 `app/scripts/boot.gd` 外，项目脚本不得直接访问全局 `Gf` 或 `GFAutoload`。

## 架构速览

- 启动入口：`app/scenes/boot.tscn` 挂载 `app/scripts/boot.gd`，启用 GF 根架构的严格依赖查询与声明校验，调用 `await Gf.init()` 后交给 `SceneRouterSystem` 切到主菜单。
- GF 上游治理：`addons/gf/**` 是只读 vendor 快照。框架缺陷必须在 `C76GN/gf-framework` 先建 issue，再从干净 worktree 的非 `main` 分支提交 PR；合并后才允许更新项目 vendor lock，禁止把 GF 本体修改直接提交到任一仓库主线。
- gf 装配入口：`app/scripts/game_architecture_installer.gd` 注册项目 Model、System、Utility，并通过 Project Settings 的 `gf/project/installers` 接入。
- Feature：`features/<feature_id>/` 内聚脚本、场景、资源、文档和局部工具；GF 层目录只在所属 Feature 内出现。
- Shared：`shared/**` 只保存跨 Feature 契约、基础算法、UI 原语、素材和 Utility，禁止引用具体 Feature。
- 场景控制器：`features/gameplay/scripts/controllers/**` 放置使用 `GFController` 基类能力的游戏场景控制器，类名保留 `Controller` 后缀。
- 规则资源：`features/gameplay/scripts/rules/**` 定义移动、交互、生成、结束判定；`features/gameplay/resources/modes/*.tres` 组合这些规则形成不同玩法模式。
- 对局 session：`GameInitSystem` 使用 `GFLevelUtility` 记录当前一局的模式、尺寸、种子和来源；这只是运行时 session 语义，不代表项目引入关卡进度玩法。
- 模式目录：`features/gameplay/resources/registries/game_mode_registry.tres` 使用 `GFResourceRegistry` 维护可玩模式列表，项目层通过 `GameModeCatalogUtility` 读取，缓存与分组生命周期由 `GFAssetUtility` 独占管理。
- UI 路由：`features/navigation/resources/registries/ui_route_registry.tres` 使用 `GFResourceRegistry` 维护 `GFUIRoute` 资源目录；业务 UI 按 route ID 打开，不保留路径调用后备。菜单负责关闭自身路由，System 不得直接调用 `GFUIUtility.pop_panel()` 或 `clear_all()`。
- 完整 Feature 所有权和依赖方向以 `docs/architecture.md` 为准。
- 配置校验：模式配置应优先使用 `GFValidationReport` 汇总问题，再由调用方决定是否 `push_error` 或写日志。

## 开发流程

1. 先确认变更属于哪一类：玩法规则、UI/菜单、存档/回放、gf 示例用法、gf 框架反哺或维护测试。
2. 找到已有 gf 用法并复用。例如跨模块通信优先用事件或 Model，玩家操作优先走 `GFCommandHistoryUtility`，输入优先走 `GFInputMappingUtility`，场景跳转优先走 `SceneRouterSystem` / `GFSceneUtility`。
3. 保持边界清晰。规则资源不要直接触达全局 `Gf`；需要上下文时优先使用 `RuleContext` 或由 System 注入。
4. 涉及资源组合时，同步检查 `.gd`、`.tres`、`.tscn`、翻译和 README 是否仍一致。
5. 涉及公开方法、信号、导出变量、Resource 字段或存档格式时，同步补齐 `##` 文档和聚焦测试。
6. 修改后优先运行安全静态验证；如需 GUT，必须使用隔离用户数据目录和日志策略。如果无法运行，明确说明原因和剩余风险。

## GF 包管理

当前项目使用手动 vendored GF 7 源码。GF 7 仍提供 Godot 原生 Package Manager；恢复包管理器安装流后，正式安装状态记录在 `.gf/packages.lock.json`。

当前实际使用的 GF 能力：

- `gf.action_queue`
- `gf.asset_metadata`
- `gf.content_package`
- `gf.domain`
- `gf.feedback`
- `gf.save`
- `gf.standard.assets`
- `gf.standard.audio`
- `gf.standard.diagnostics`
- `gf.standard.deterministic`
- `gf.standard.input`
- `gf.standard.state_machine`
- `gf.standard.storage`
- `gf.standard.ui`

当前启用扩展：

- `gf.action_queue`
- `gf.asset_metadata`
- `gf.content_package`
- `gf.domain`
- `gf.feedback`
- `gf.save`

常用安全验证命令：

```powershell
git diff --check -- .gitignore .gf gf_project_profile.json project.godot addons/gf app features shared tests README.md docs tools
```

```powershell
powershell -ExecutionPolicy Bypass -File tools/validate_project_layout.ps1 -GodotExecutable godot
```

`gf_project_profile.json` 是项目目录结构的真相来源；`GFProjectLayoutValidator` 的 warning 和 error 都必须清零。

```powershell
godot --headless --path . --script res://addons/gf/kernel/package/gf_package_cli.gd -- status --json
```

检查 `status --json` 输出中的 `ok`、`issue_count`、`orphan_packages` 和 `lockfile_verify.ok`。如果 `.gf/packages.lock.json` 不存在，`installed_count` 可能为 `0`，只表示当前是手动 vendored 源码状态。GF 7 包管理器没有 Python `package_tools` 入口，不要沿用旧命令。

新增或移除 GF 包时必须同步检查：

- `.gf/packages.lock.json`
- `project.godot` 的 `gf/extensions/enabled`
- `README.md`
- `docs/roadmap.md`
- `docs/save_model.md`，当变更涉及最高分、设置、书签、回放、统计或 `gf.extension.save` 时

## 按变更类型检查文件

### 玩法规则或模式变更

检查并按需更新：

- `features/gameplay/scripts/rules/**`
- `features/gameplay/scripts/data/game_mode_config.gd`
- `features/gameplay/resources/rules/**`
- `features/gameplay/resources/modes/*.tres`
- `features/gameplay/resources/registries/game_mode_registry.tres`
- `features/themes/resources/themes/**`
- `features/gameplay/scripts/systems/rule_system.gd`
- `features/gameplay/scripts/systems/game_init_system.gd`
- `features/gameplay/scripts/queries/get_hud_stats_query.gd`
- `shared/assets/translations.csv`
- `README.md` 的模式说明或新增模式流程

规则实现应保持资源化和可组合，不要让某个模式的特殊逻辑污染基础规则类。

### 输入、移动、撤销或回放变更

检查并按需更新：

- `features/gameplay/resources/input/gameplay_input_context.tres`
- `features/replays/resources/input/replay_input_context.tres`
- `features/gameplay/scripts/systems/player_input_system.gd`
- `features/replays/scripts/systems/replay_input_system.gd`
- `features/gameplay/scripts/systems/grid_movement_system.gd`
- `features/gameplay/scripts/commands/move_command.gd`
- `features/replays/scripts/systems/replay_system.gd`
- `features/replays/scripts/data/replay_data.gd`

玩家移动应继续通过 `MoveCommand` 和 `GFCommandHistoryUtility` 记录，确保撤销、书签和回放共享同一套状态语义。

### 存档、书签或设置变更

检查并按需更新：

- `features/progress/scripts/systems/save_system.gd`
- `features/bookmarks/scripts/systems/bookmark_system.gd`
- `features/gameplay/scripts/systems/game_state_system.gd`
- `features/bookmarks/scripts/data/bookmark_data.gd`
- `features/replays/scripts/data/replay_data.gd`
- `features/persistence/scripts/data/game_save_section_data.gd`
- `features/persistence/scripts/utilities/game_save_graph_utility.gd`
- `features/progress/scripts/data/game_stats_save_data.gd`
- `features/bookmarks/scripts/data/bookmark_catalog_save_data.gd`
- `features/replays/scripts/data/replay_catalog_save_data.gd`
- `features/settings/scripts/utilities/game_settings_utility.gd`
- `app/scripts/game_architecture_installer.gd`
- `features/settings/scripts/menus/settings_menu.gd`
- `docs/save_model.md`

存档字段变化属于高风险改动。统计、书签和回放必须通过各自的 `GameSaveSectionData` Provider 进入 `GameSaveGraphUtility`，不得重新创建 SaveSlot、时间戳 Resource 集合或业务 System 直写文件。破坏性 Schema 变化应提供一次性显式迁移工具，不在运行时代码中长期保留旧字段双读；同时检查 Binary Variant 类型、checksum、Profile/section 版本、全图回滚和设置独立性。

### UI、菜单或表现变更

检查并按需更新：

- `features/**/scenes/**/*.tscn`
- `shared/scenes/**/*.tscn`
- `features/navigation/resources/registries/ui_route_registry.tres`
- `features/navigation/resources/ui_routes/*.tres`
- `features/navigation/scripts/utilities/game_ui_router_utility.gd`
- `features/themes/scripts/utilities/game_ui_motion_utility.gd`
- `features/themes/scripts/utilities/game_board_feedback_utility.gd`
- `features/gameplay/scripts/controllers/game_play_controller.gd`
- `features/gameplay/scripts/controllers/game_board_controller.gd`
- `shared/assets/translations.csv`
- `features/themes/resources/themes/**`
- `docs/visual_style.md`

表现层应继续通过事件接收业务结果，不要把棋盘算法或存档语义写进 UI 节点。视觉改动必须保持 `docs/visual_style.md` 定义的柔和肌理扁平独立游戏方向，避免刺眼、粗糙或马赛克噪点。

### gf 框架反哺变更

只有任务明确要求，或示例项目无法合理表达通用需求时，才修改：

- `addons/gf/**`
- `addons/gf/README.md`
- `addons/gf/plugin.cfg`，仅在明确升级框架版本时

修改 gf 时必须遵守：

- 先尝试项目层方案；只有项目层方案会绕开 gf 示例目标、造成重复补丁或无法表达通用能力时，才修改 gf。
- 不能引用本项目的 2048 类型、路径、文案、资源或玩法概念。
- 本仓库已由维护者批准采用破坏性升级优先策略；删除旧 API、双读和隐式降级路径，并同步提升 schema/版本与测试。已发布数据如需保留，只提供显式一次性迁移，不把兼容分支留在运行时主路径。
- 优先为 gf 增加通用能力、诊断、校验或文档，而不是为示例项目写特例。
- 临时框架补丁必须有简短记录；当前 gf 版本已包含后删除该记录，避免维护噪音。
- 在最终回复中单独说明：为什么需要改框架、这个改动如何服务其他项目、还发现了哪些后续框架缺口。

当前临时框架补丁：

- gf 节点/Utility 退出清理：`GFUIUtility`、`GFObjectPoolUtility`、`GFConsoleUtility`、`GFDebugOverlayUtility`、`GFScreenTransitionUtility`、`GFNodeStateMachine`、`GFNodeStateGroup` 和 `GFPluginActions` 对话框清理在 `dispose()`、`_exit_tree()` 或销毁辅助函数中避免同步 `remove_child()` 后再 `queue_free()`。问题场景是 Godot 退出时 autoload `_exit_tree()` 触发架构 dispose，此时父节点可能正忙于 children 变更；直接 `queue_free()` 让引擎在安全点释放节点，可避免 `Parent node is busy adding/removing children`。当 gf 上游包含等价修复后删除本记录。

### 文档变更

检查并按需更新：

- `README.md`：项目定位、技术栈、架构概览、gf 使用方式、新模式流程。
- `docs/coding_style.md`：只有团队规范变化时更新。
- `docs/ai_maintenance.md`：只有 AI 工作流程或维护边界变化时更新。
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
- `tests/gut/test_gf_package_validation.gd`
- `tests/gut/test_gdscript_layout_validation.gd`

它们扫描示例项目源码和项目测试，不扫描 `addons/gf/**` 或 `addons/gut/**`。这些测试用于把 `docs/coding_style.md` 中能稳定机器判断的规则固定下来，也用于约束 GF 包状态和容易触发 Godot 4.7 静态警告的测试写法。

历史运行命令：

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -ginclude_subdirs -gexit
```

不要直接使用默认用户目录运行上面的命令。项目提供了安全入口：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot
```

该脚本会使用临时 `APPDATA`、`LOCALAPPDATA`、`USERPROFILE`、`TEMP`、`TMP`，并通过 `--log-file` 把 Godot 日志写入临时运行目录。它还会限制运行时间、临时日志大小和默认 Godot 用户日志增长，失败时保留现场，成功时默认清理临时目录。

注意：安全脚本已经完成过隔离 GUT 验证，但切换 Godot 可执行文件或升级版本后，仍应先使用较短 `-TimeoutSeconds`、较小 `-MaxLogMB` 和较小 `-MaxDefaultLogGrowthKB` 做烟雾运行，并确认默认 Godot 用户目录日志没有增长。

当前已验证的安全 GUT 命令：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TimeoutSeconds 330 -MaxLogMB 32 -MaxDefaultLogGrowthKB 256
```

2026-07-16 使用 Godot `4.7.stable.steam.5b4e0cb0f` 运行通过。当前完整套件为 22 个 GUT 测试脚本、183 个 `test_` 用例、1076 个断言；退出泄漏受 `.gf/godot_exit_leak_baseline.json` 严格约束，并同时绑定 `.gf/vendor.lock.json` 的精确 GF vendor tree 与 `app/`、`features/`、`shared/` 的运行时 `class_name` 数量。当前 GF 快照声明 703 个全局脚本类，项目运行时声明 116 个。回合流接入增加 `GameMoveTurnAction` 与 `GameTurnSystem`，通知迁移移除 `HudMessagePayload`，项目运行时类净增 1；完整套件退出计数仍为 `ObjectDB = 259`、`Resources = 116`、RID 类型数 `= 3`，因此没有放宽既有泄漏上限。GF vendor tree 与项目运行时类集合均未变化时，退出计数不得继续增长。

编辑器 GDScript warning 诊断入口：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_gdscript_lsp_diagnostics.ps1
```

该命令参考 GF 维护项目的 LSP 诊断方式，默认扫描 `app`、`features`、`shared`、`tests/gut` 和 `tools`，并把报告写入 `build/gdscript_lsp_diagnostics.json`。2026-07-16 零诊断基线为 145 个 `.gd` 文件，`diagnostic_count = 0`、`timeout_count = 0`。

如果只改了文档，可以不运行 GUT，但应检查链接、路径和项目定位是否准确。只要改了 `.gd`，应优先补充或运行相关测试；无法安全运行时，必须说明未验证风险。

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
