# 验证指南

本文档记录安全验证顺序，并区分纯文本检查、隔离的 headless Godot/GUT 运行和需要人工签字的视觉/平台验证。

## 默认验证顺序

### 1. 空白与路径检查

```powershell
git diff --check -- .gitignore .gf project.godot export_presets.cfg gf_project_profile.json addons/gf app features shared tests README.md docs tools
```

### 2. GF 项目契约

```powershell
$env:PYTHONDONTWRITEBYTECODE = "1"
python addons/gf/tools/ai_developer/gf_ai_project.py validate --project-root .
```

期望 `ok` 为 `true`，contract 本身没有 error、warning、`pending_review` 能力或缺失 Recipe 包。Snapshot 是按需重新生成的本地观察证据，不是日常校验的必需输入，也不得提交；其 drift advisory 必须逐项审阅，但不得为了追求 warning 数量为零而把生成输出、测试夹具、vendor 路径或目录扫描字符串伪报为项目所有资源。

### 3. GF vendor 来源

GF 11 使用完整 addon 快照，不再提供 Package Manager、包管理 CLI、registry、离线 bundle 或 `.gf/packages.lock.json` 安装流。项目的框架安装来源只由 `addons/gf/` 与 `.gf/vendor.lock.json` 共同定义；`.gf/project_contract.json` 中的 package declarations 继续表示能力与 API policy，不是本地安装记录。扩展选择只以 `project.godot` 的 `gf/extensions/enabled` 为准。

先执行离线来源校验：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_gf_vendor.ps1
```

默认命令离线校验 `addons/gf/` 的来源元数据、渠道、版本、文件数和内容哈希是否与 `.gf/vendor.lock.json` 一致。正式验收还必须运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_gf_vendor.ps1 -VerifyRemote
```

远程校验会通过 GitHub API 比对本地每个文件的 Git blob，并把它们与官方仓库的 commit 和 `addons/gf` Git tree 绑定为同一份 provenance。`development` 渠道继续要求规范 `.github/workflows/ci.yml` 的 `mode=full` main push run、`GF full validation` 和 `GF merge gate` 成功终态；`stable` 渠道要求版本 ref 是可有界 peel 到同一 `source_commit` 的 annotated tag，并验证精确 tag 上 `.github/workflows/release.yml` 的 build、static、GUT、integration、LSP 与发布 job 全部成功。稳定版还会下载有界的 `gf-release-artifacts-<version>.json` 和 `gf-framework-<version>.zip`，把严格 UTF-8 manifest 的 `version`、`source_revision`、单次构建计数、文件大小和 SHA-256 与 GitHub Release asset digest 及实际下载字节交叉绑定。CI 可通过 `GITHUB_TOKEN` 提高 API 配额。若本地有已锁定 commit 的干净 GF checkout，可再传入 `-UpstreamRepositoryPath <path>`，以独立 checkout 复核同一份内容。GF Python 工具运行时生成的 `__pycache__` / `*.pyc` 不属于 vendor 快照，校验和 Git 均明确排除；除此之外的额外文件仍会导致校验失败。

稳定示例线只采用 GF 正式发布；开发兼容线只采用 GF 官方 `main` 最新且全量上游门禁成功的精确 commit。开发版验证失败时不得移动稳定线、放宽基线或局部修补 vendor，应保留上一绿色身份并先完成项目误用排查和必要二分。

GF 官方仓库可用性与本地 vendored 源码完整性必须分别报告。精确版本、文件数、commit 和内容哈希直接读取当次校验输出与 `.gf/vendor.lock.json`，不在本指南中复制易过期的验证结果。

## Godot / GUT 运行策略

### GF 项目布局

项目目录契约位于 `gf_project_profile.json`。目录库存、Feature-Cohesive 拓扑和 profile 规则只有以下权威执行入口：

```powershell
powershell -ExecutionPolicy Bypass -File tools/validate_project_layout.ps1 -GodotExecutable godot
```

包装器通过 `tools/invoke_godot_project_tool.ps1` 等待 Steam 派生的 Godot 子进程、隔离用户目录并检查脚本诊断。派生进程只能通过启动器真实后代，或本次唯一 `--log-file` 与脚本路径的联合身份识别；不得仅因命令行包含同一项目根就等待或强杀其他 Godot/GUT/编辑器进程。进程身份回归可单独运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/test_invoke_godot_project_tool.ps1 -GodotExecutable godot
```

`tools/validate_project_layout.ps1` 负责隔离运行并判定进程终态，`tools/validate_project_layout.gd` 负责调用只读 `GFProjectLayoutAnalyzer`、合并 `ProjectResourceReferenceValidator` 报告、写入 `build/project_layout_report.json` 并判定完整结果。资源引用门禁有界扫描 `app/`、运行时 `features/` 与 `shared/` 的 `.tscn/.tres`：每条 `ext_resource` 的 `res://` 路径必须存在；引用与目标都提供规范 UID 时还必须一致；`sub_resource`、内建值和没有可比 UID 真值的合法路径不会误报。作者评审与原始 source pack 不进入发布运行时，继续由素材审计门禁负责。该执行路径要求输入与求值完整，同时把 warning 与 error 都视为失败；全量 GUT 不再重复扫描同一份目录库存。当前 profile 为 `c76.2048.feature_cohesive.v1`，基于 GF 内置 `gf.project_layout.feature_cohesive.v1` 收紧而来。文件、目录与引用计数仅作诊断信息，因为 `build/` 内的本地报告会随验证命令变化。

### GF API 与生命周期合规

`tests/gut/test_gf_project_conformance.gd` 使用 `GFScriptStructureTools` 扫描 `app/`、`features/`、`shared/` 和当前 `addons/gf/`：

- 动态读取 GF 源码中的 `@deprecated` 方法，并按项目接收者类型阻止调用。
- 限制全局 `Gf` / GF AutoLoad 基类只能由 `app/scripts/boot.gd` 与 `app/scripts/boot_runtime.gd` 组成的应用组合根访问。
- 沿项目本地 helper 调用链检查 GF Module 的 `init()` / `async_init()`，禁止提前获取跨模块依赖。

更新 vendored GF 或修改 Module 生命周期时，先运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_gf_project_conformance.gd,res://tests/gut/test_gdscript_layout_validation.gd" -TimeoutSeconds 180
```

### 项目 GDScript 风格政策

`tests/gut/test_gdscript_layout_validation.gd` 是项目源码文本政策的唯一执行者。它检查 GF Analyzer 与 Godot LSP 不表达的约束，包括中文 section 标签与源码排列、路径和架构层命名、显式类型声明，以及项目约定的强类型调用和禁用模式；每条规则只扫描脚本中声明的适用根。该测试不判断目录 profile，也不替代解析、名称解析或类型兼容性诊断。

### 分块 Profile 持久化

修改 `features/persistence/scripts/chunking/`、manifest-backed Provider 或 Feature chunk codec 时，先运行不依赖完整 Composition Root 的核心定向组：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_chunked_profile_persistence.gd,res://tests/gut/test_chunk_profile_runtime.gd,res://tests/gut/test_chunk_save_lease.gd,res://tests/gut/test_chunk_profile_utility.gd,res://tests/gut/test_bookmark_chunk_persistence.gd" -TimeoutSeconds 240 -MaxLogMB 16 -MaxDefaultLogGrowthKB 128
```

随后运行 SaveGraph、账号编排与 Composition Root 集成组：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_game_save_graph_utility.gd,res://tests/gut/test_local_player_profiles.gd,res://tests/gut/test_architecture_installer_validation.gd" -TimeoutSeconds 360 -MaxLogMB 16 -MaxDefaultLogGrowthKB 128
```

该组必须覆盖以下行为，但是否通过只以当次命令输出为准，本文档不记录“最近一次通过”：

- `ChunkManifest` 的 128 KiB 单块、64 块和 8 MiB 总预算，以及 descriptor 顺序、字节数与 SHA-256。
- inactive A/B bank 完整 stage 后仍不可见，只有主 Profile 保存成功才能提交候选 Manifest；known failure、cancelled 和 superseded 均不提交。
- stage `outcome_unknown` 必须等待精确 chunk Profile 进入 idle 且 unknown/detached 证据清空，并收敛为不提交 Manifest 的已知失败；main `outcome_unknown` 必须按公开 persisted generation 证据对账。
- main 精确提交必须在释放 owner 前把 WAITING/READY Lease 重基线到新的 bank/epoch；即使期间没有 live sibling，栅栏后才创建的 Lease 也必须继承该基线并写入对侧 bank。
- fence 期间的 dirty save intent 必须停放，并在精确结算后仅重臂一次；quiesce 先于 debounce 到达时也必须等待重新生成的最新 generation，而不是接受一次 busy flush。
- materialization 任一 chunk 缺失、损坏或摘要不符时不得返回部分数组；Feature codec 必须严格拒绝截断、尾随 frame、schema 不符和非规范 Variant。
- `ChunkMaterializationLease` 只能 claim 一次，主 Profile apply 失败必须回滚业务 Provider 与 active Manifest/revision；账号切换失败也必须恢复来源 Profile 的 Manifest 状态。
- `bookmarks` 与 `replays` 的业务 schema、流 schema 和主 Profile Manifest schema 分离，主文档不重新内嵌完整目录。
- 主 Profile 删除/重置的复合 cleanup saga 只在主 logical family 已确定删除后遍历全部 Manifest Provider；caller timeout、typed BUSY、partial failure 与迟到终态期间持续持有 canonical path，并可幂等重试。

分块持久化修改仍需运行本指南的 Godot LSP、GF 项目布局、GF 合规/风格和完整安全 GUT 门禁；定向组不能替代其中任何一个。

历史上，直接运行 Godot/GUT 曾在默认用户数据目录生成巨大日志文件。因此默认不要直接运行：

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -ginclude_subdirs -gexit
```

项目提供了安全运行入口：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot
```

脚本的接口：

- `-GodotExecutable`：Godot 可执行文件路径或命令名，默认 `godot`。
- `-ProjectRoot`：项目根目录，默认当前目录。
- `-TestDir`：GUT 测试目录，默认 `res://tests/gut`。
- `-TestScripts`：逗号分隔的 GUT 测试脚本完整路径；非空时只运行这些脚本，并忽略 `-TestDir`。
- `-UnitTestName`：可选的 GUT 测试方法名子串过滤，适合在同一脚本内最小化失败用例。
- `-TimeoutSeconds`：超时时间，默认 `180`。
- `-MaxLogMB`：临时 Godot 日志大小上限，默认 `32`。
- `-MaxDefaultLogGrowthKB`：默认 Godot 用户日志允许增长上限，默认 `256`。
- `-PollIntervalMilliseconds`：日志和超时轮询间隔，默认 `100`。
- `-VerboseGodot`：诊断退出泄漏时附加 Godot `--verbose`，默认关闭；详细对象现场仍受隔离目录和日志上限保护。
- `-KeepTemp`：保留临时运行目录，便于查看 `stdout.log`、`stderr.log` 和 `godot.log`。

脚本的保护措施：

1. 将 `APPDATA`、`LOCALAPPDATA`、`USERPROFILE`、`TEMP`、`TMP` 指到系统临时目录下的独立运行目录。
2. 使用 Godot `--log-file` 将日志写到临时运行目录。
3. 监控临时 `godot.log` 大小，超过 `-MaxLogMB` 会终止进程并返回 `125`。
4. 监控默认 Godot 用户日志增长，超过 `-MaxDefaultLogGrowthKB` 会终止进程并返回 `126`。
5. 超过 `-TimeoutSeconds` 会终止进程并返回 `124`。
6. 成功且未传 `-KeepTemp` 时删除临时运行目录；失败时保留现场。

重要：该脚本用于替代裸 Godot/GUT 命令。后续真正运行时，应先用较小 `-TimeoutSeconds`、较低 `-MaxLogMB` 和较低 `-MaxDefaultLogGrowthKB` 做一次烟雾验证，并确认默认用户目录没有新增大日志。

建议的首次烟雾验证命令：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TimeoutSeconds 30 -MaxLogMB 4 -MaxDefaultLogGrowthKB 64 -KeepTemp
```

只验证本次改动覆盖的脚本时，仍必须经过同一个安全包装器：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_deterministic_gameplay.gd,res://tests/gut/test_move_command_reverse_map.gd" -TimeoutSeconds 120
```

### 安全 GUT 结果记录

命令：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TimeoutSeconds 900 -MaxLogMB 32 -MaxDefaultLogGrowthKB 256
```

验收结果只以本次命令输出为准。测试脚本数、用例数、断言数、运行时 `class_name` 集合、ObjectDB/Resource/RID 计数和具体引擎版本都会随工作树变化，不在规范文档中复制。

退出门禁读取 `.gf/godot_exit_leak_baseline.json`，并绑定 `.gf/vendor.lock.json` 的精确 GF vendor tree 与当次项目运行时类集合。输入集合变化时必须先解释差异，再走显式校准流程；不得只修改数字使测试通过。

若 Godot 进程对象未提供退出码，包装器只能在 GUT 输出包含完整成功标记时接受结果；缺少退出码且没有完整终态证据时必须失败。

## GDScript LSP 诊断

普通 headless editor 和 GUT 日志不一定能稳定输出编辑器面板里的所有 GDScript warning。Godot LSP 是语法、名称解析、类型兼容性及引擎 error/warning 的唯一权威执行者；项目提供以下独立诊断入口：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_gdscript_lsp_diagnostics.ps1
```

默认扫描 `app`、`features`、`shared`、`tests/gut` 和 `tools`，默认排除 `addons/gut` 与上游原始素材区 `features/asset_library/resources/source_packs`。报告会写入 `build/gdscript_lsp_diagnostics.json`。该命令会启动临时 Godot LSP，读取 `textDocument/publishDiagnostics`，并在存在 error 或 warning 时返回非零退出码。

只想查看报告而不中断流程时使用：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_gdscript_lsp_diagnostics.ps1 -AllowDiagnostics
```

扫描文件数、诊断数和 timeout 数直接读取当次 `build/gdscript_lsp_diagnostics.json`。该报告位于忽略提交的 `build/`，长期文档不保存“最近一次”副本。

## 视觉与操作回放

真实场景流截图由项目内回放工具生成，不使用手工拼接的测试节点：

```powershell
powershell -ExecutionPolicy Bypass -File tools/invoke_godot_project_tool.ps1 -ScriptPath res://tools/capture_visual_review.gd -Rendering -ExpectedOutputPattern "[VisualReview] slowest_command_usec=" -TimeoutSeconds 300
```

输出位于忽略提交的 `build/visual_review/`，覆盖主菜单、场景遮罩、模式选择、主题化下拉菜单、稳定游戏帧和实际 `MoveCommand` 合并帧。工具每次先清理自己的输出目录，并写入 `capture_manifest.json`；manifest 记录 Git HEAD/工作树状态、GF vendor 版本与 commit、预期/实际截图和成功或失败终态。没有成功终态的目录不得作为签字证据。每次评审必须同时检查截图、manifest、命令耗时输出和运行日志；文档中的视觉目标不能替代当次证据。

玩家 UI 的跨视口结构验收使用独立矩阵工具：

```powershell
powershell -ExecutionPolicy Bypass -File tools/invoke_godot_project_tool.ps1 -ScriptPath res://tools/capture_ui_vfx_matrix.gd -Rendering -ExpectedOutputPattern "[UiVfxMatrix] completed captures=" -TimeoutSeconds 360
```

输出位于 `build/ui_vfx_matrix/`，同时生成：

- 各玩家页面在 `1280×720`、`1906×943`、`850×838`、`960×540` 和 `720×960` 的真实渲染截图。
- 需要滚动才能完成主要任务的页面末端截图。
- `geometry_report.json` 控件几何记录。
- `validation_report.json` 结构、首屏、焦点、触控目标和单滚动所有权错误清单。
- 所有通用页面在 `1280×720` 与 `720×960` 下的 Reduced Motion 静态终态截图。
- 与真实移动验收相同结构的 `capture_manifest.json`，用于排除旧截图混入。

验收时必须确认 `validation_report.json` 为 `[]`，并逐页查看截图。Windows 桌面会把高于工作区的实体窗口限制在任务栏上方；不得通过手动放大根节点伪造 `720×1558` 截图，因为那只会拉高渲染背景，Container 仍按受限窗口高度布局。桌面自动化矩阵使用可真实承载的 `720×960` 竖屏；更高设备比例仍需在目标设备或可控离屏渲染环境中复验。

人工签字至少核对裁切、层级、触控安全区、文字对比、首帧承接、键盘/手柄焦点、44px 命中根和 Reduced Motion 静态终态；纸片、旋转、描边、硬投影与焦点环的视觉包络不得越过控件根包络或最近裁剪祖先。新玩家页面或中/大型结构改版还必须读取对应 `UI Surface Intent Brief`，在三秒内指出玩家当前操作对象、当前选择和主动作，并确认隐喻确实改变了信息组织或因果反馈，而不是只增加装饰。截图 manifest 中的 `surface_contract_ids` 必须覆盖本次适用合同。

`capture_visual_review.gd` 负责实际移动命令、稳定帧和耗时证据；`capture_ui_vfx_matrix.gd` 负责页面与状态矩阵。两者用途不同，不以其中一个替代另一个。

## 性能诊断与目标设备证据

经典 4×4 的同步完整回合、各阶段、checkpoint 与生命周期数量级回归使用隔离的 headless 工具：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools/invoke_godot_project_tool.ps1 `
  -ScriptPath res://tools/run_game_performance_acceptance.gd `
  -ExpectedOutputPattern "Game performance acceptance:" `
  -TimeoutSeconds 300
```

该结果只证明共享开发机上没有数量级退化，不是玩家帧预算或微信真机签字。可签署的 `input_to_primary_feedback` 必须从项目收到真实有效抽象移动输入开始，到可见状态提交后匹配的 `RenderingServer.frame_post_draw` 结束；触控样本包含 virtual pulse 与 `PlayerInputSystem` 轮询，Action execute 或音频启动只形成阶段诊断。平台、输入、视口、布局、棋盘和渲染档必须精确匹配矩阵，帧时与首反馈各至少 120 个样本；桌面、Web、微信/普通移动和低端移动的 P95 帧时上限分别为 16.667、20、25 和 33.3 ms，首个已绘制反馈 P95 小于 50 ms。未经 Android/iOS 目标真机采样，不得把模拟器、headless 或共享开发机结果写成微信性能已通过。

## Web / 微信小游戏准备预检

平台准备必须先通过项目契约，再检查本机工具链：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_platform_readiness.ps1 -GodotExecutable godot
```

本地只审查项目配置、允许环境 blocker 时：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_platform_readiness.ps1 -GodotExecutable godot -AllowEnvironmentBlockers
```

第一份报告 `build/platform_readiness_report.json` 由 GFCompatibilityPreflight 和 GFBridgeContractReport 生成；第二份 `build/platform_environment_report.json` 检查 Godot 与导出模板版本一致性及微信开发者工具 CLI。正式导出和 CI 不得忽略环境 blocker。真机矩阵见 `features/platform_runtime/docs/wechat_minigame_readiness.md`。

预检数量、issue 数和本机 blocker 直接读取上述两份生成报告；长期文档不保存某次工作站签字或环境快照。尚未完成的微信能力边界与真机矩阵记录在 `features/platform_runtime/docs/wechat_minigame_readiness.md`。

动态加载的脚本资源必须在 GF 注册表或内容包中使用内置 `Resource` 作为 `ResourceLoader` type hint，再以 `is` 收窄到业务资源类型。Godot Web 导出不能依赖编辑器侧 `class_name` 名称作为动态加载 type hint；自动预检和 GUT 回归测试必须持续约束这条规则。

### 微信正式资源闭包

正式微信预设使用精确 `resources` 文件集。闭包工具从主场景、Installer、扩展选择、GF 注册表、内容包、动态结构路径和 raw include 构建根集合，继续展开资源依赖、GDScript class 与 static preload；运行时 `res://` literal 只有精确绑定 script path、literal、expected count、kind 与 reason 的规则才可豁免。缺失、partial/truncated、未登记或动态 literal、规则缺失/重复/次数漂移、字体 remap 漂移、禁入 editor/test/tool 资源和 preset 漂移均必须失败。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools/invoke_godot_project_tool.ps1 `
  -ScriptPath res://tools/wechat_minigame_release_resource_closure.gd `
  -ExpectedOutputPattern '"ok":true' `
  -TimeoutSeconds 300
```

闭包数量和 SHA-256 只能读取当次输出，不复制到长期文档。正式候选报告 schema 5 的 `resource_closure` 必须绑定 policy/tool/closure SHA-256、完整依赖扫描终态和当次计数；build identity 4 必须纳入这些闭包证据。独立闭包通过仍不能替代候选原子报告与隔离产物验证。

### 微信工具与正式候选

不启动 Godot 的确定性工具回归：

```powershell
node --test `
  tests/tooling/wechat_chunked_file_loader.test.cjs `
  tests/tooling/wechat_subpackage_startup_coordinator.test.cjs `
  tests/tooling/wechat_export_identity.test.cjs `
  tests/tooling/wechat_release_font_coverage.test.cjs `
  tests/tooling/gf_vendor_verifier.test.cjs
```

正式候选只能由零策略入口生成：

重导出同一个候选目录前，先关闭该目录对应的微信开发者工具项目窗口。Windows 文件占用可能使原子目录替换失败；此时旧候选必须保留，不得通过逐文件覆盖绕过事务。释放占用后重新导出，并按新报告确认身份。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools/export_wechat_minigame_release.ps1 `
  -GodotExecutable godot
```

期望同根 `export-report.json` 为 schema 5，build identity 为第 4 版，且绑定资源闭包、字体、GF/Godot、工具、输入快照、DPR、启动协调器、两个大资源、精确双分包 manifest 和包体预算。build ID、主包/engine/game_data/总包字节和工具 hash 都只从本轮新候选报告读取；源文件、闭包、模板、AppID 或工具变化后不得沿用旧值。导出器内置的临时最小宿主隔离验证是正式签字的一部分，项目宿主的结构复核不能替代它。

### 脚本静态检查

不启动 Godot，只检查 PowerShell 脚本文本可解析：

```powershell
$script = Get-Content -Raw -Encoding UTF8 tools/run_gut_safe.ps1
$null = [scriptblock]::Create($script)
```

## 持续验证边界

- 平台发布只能由当次环境报告、正式零错误导出和目标设备矩阵共同签字；静态配置通过不能替代工具链或真机证据。
- 项目目录库存与 profile 规则只由 `tools/validate_project_layout.ps1` / `tools/validate_project_layout.gd` 执行；不得在 GUT 中增加第二次完整库存扫描。
- 项目 style scanner 只执行源码文本与项目政策；显式类型声明是覆盖率政策，类型是否正确仍由 Godot LSP 裁决。
- GDScript LSP 始终以零 error、零 warning 为门禁，修改 `.gd` 后必须复跑并读取当次生成报告。
- 退出泄漏基线只用于阻止 ObjectDB、Resource 与 RID 债务增长，不代表债务已经修复；`GFTextFitter` 的 `ShapedText` / `Font` RID 仍由完整 GUT 维持零增长门禁。
- 当前截图工具提供真实跨视口证据，但没有自动像素差异门禁；视觉签字仍需人工逐页检查。
