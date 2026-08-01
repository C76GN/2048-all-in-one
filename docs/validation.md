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

### 3. GF 包状态

```powershell
godot --headless --path . --script res://addons/gf/kernel/package/gf_package_cli.gd -- status --json
```

期望：

- `ok` 为 `true`
- `issue_count` 为 `0`
- `orphan_packages` 为空
- `lockfile_verify.ok` 为 `true`
- 如果 `.gf/packages.lock.json` 存在，`installed_count` 与 lockfile 中的 installed 包数量一致

注意：当前 GF 使用 Godot 原生包管理 CLI，入口是 `res://addons/gf/kernel/package/gf_package_cli.gd`。不要继续使用旧的 Python `addons/gf/kernel/package_tools/gf_package_installer.py` 命令。

当前仓库是手动更新后的 vendored GF 源码状态，`.gf/packages.lock.json` 可能暂时不存在。缺失 lockfile 时，包状态命令会把 lockfile 视为空安装状态；这不等价于项目运行失败，但表示当前 GF 源码不是由包管理器重建出来的。若后续恢复包管理器安装流，应先重新生成 lockfile，再恢复对 installed 包数量的强校验。

手动 vendored 源码由独立锁文件校验：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_gf_vendor.ps1
```

默认命令离线校验 `addons/gf/` 的来源元数据、渠道、版本、文件数和内容哈希是否与 `.gf/vendor.lock.json` 一致。正式验收还必须运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_gf_vendor.ps1 -VerifyRemote
```

远程校验会通过 GitHub API 比对本地每个文件的 Git blob，并把它们与官方仓库的 commit、`addons/gf` Git tree、规范 `.github/workflows/ci.yml` 的 `mode=full` push run、`GF full validation` 和 `GF merge gate` 成功终态绑定为同一份 provenance；CI 可通过 `GITHUB_TOKEN` 提高 API 配额。若本地有已锁定 commit 的干净 GF checkout，可再传入 `-UpstreamRepositoryPath <path>`，以独立 checkout 复核同一份内容。GF Python 工具运行时生成的 `__pycache__` / `*.pyc` 不属于 vendor 快照，校验和 Git 均明确排除；除此之外的额外文件仍会导致校验失败。

稳定示例线只采用 GF 正式发布；开发兼容线只采用 GF 官方 `main` 最新且全量上游门禁成功的精确 commit。开发版验证失败时不得移动稳定线、放宽基线或局部修补 vendor，应保留上一绿色身份并先完成项目误用排查和必要二分。

远程 registry 可用性与本地 vendored 源码完整性必须分别报告。精确版本、文件数、commit 和内容哈希直接读取当次 CLI 输出与 `.gf/vendor.lock.json`，不在本指南中复制易过期的验证结果。

## Godot / GUT 运行策略

### GF 项目布局

项目目录契约位于 `gf_project_profile.json`，独立验证命令为：

```powershell
powershell -ExecutionPolicy Bypass -File tools/validate_project_layout.ps1 -GodotExecutable godot
```

包装器通过 `tools/invoke_godot_project_tool.ps1` 等待 Steam 派生的 Godot 子进程、隔离用户目录并检查脚本诊断。GDScript 使用 `GFProjectLayoutValidator` 扫描项目，将报告写入 `build/project_layout_report.json`，并把 warning 与 error 都视为失败。当前 profile 为 `c76.2048.feature_cohesive.v1`，基于 GF 内置 `gf.project_layout.feature_cohesive.v1` 收紧而来。文件与目录计数仅作诊断信息，因为 `build/` 内的本地报告会随验证命令变化。

### GF API 与生命周期合规

`tests/gut/test_gf_project_conformance.gd` 使用 `GFScriptStructureTools` 扫描 `app/`、`features/`、`shared/` 和当前 `addons/gf/`：

- 动态读取 GF 源码中的 `@deprecated` 方法，并按项目接收者类型阻止调用。
- 限制全局 `Gf` / `GFAutoload` 只能由 `app/scripts/boot.gd` 与 `app/scripts/boot_runtime.gd` 组成的应用组合根访问。
- 沿项目本地 helper 调用链检查 GF Module 的 `init()` / `async_init()`，禁止提前获取跨模块依赖。

更新 vendored GF 或修改 Module 生命周期时，先运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TestScripts "res://tests/gut/test_gf_project_conformance.gd,res://tests/gut/test_gdscript_layout_validation.gd" -TimeoutSeconds 180
```

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

普通 headless editor 和 GUT 日志不一定能稳定输出编辑器面板里的所有 GDScript warning。项目提供了独立的 LSP 诊断入口，参考自 GF 维护工具：

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
powershell -ExecutionPolicy Bypass -File tools/invoke_godot_project_tool.ps1 -ScriptPath res://tools/capture_visual_review.gd -Rendering -ExpectedOutputPattern "[VisualReview] slowest_command_usec=" -TimeoutSeconds 240
```

输出位于忽略提交的 `build/visual_review/`，覆盖主菜单、场景遮罩、模式选择、主题化下拉菜单、稳定游戏帧和实际 `MoveCommand` 合并帧。每次评审必须同时检查截图、命令耗时输出和运行日志；文档中的视觉目标不能替代当次证据。

玩家 UI 的跨视口结构验收使用独立矩阵工具：

```powershell
powershell -ExecutionPolicy Bypass -File tools/invoke_godot_project_tool.ps1 -ScriptPath res://tools/capture_ui_vfx_matrix.gd -Rendering -ExpectedOutputPattern "[UiVfxMatrix] completed captures=" -TimeoutSeconds 300
```

输出位于 `build/ui_vfx_matrix/`，同时生成：

- 各玩家页面在 `1280×720`、`1906×943`、`850×838`、`960×540` 和 `720×960` 的真实渲染截图。
- 需要滚动才能完成主要任务的页面末端截图。
- `geometry_report.json` 控件几何记录。
- `validation_report.json` 结构、首屏、焦点、触控目标和单滚动所有权错误清单。

验收时必须确认 `validation_report.json` 为 `[]`，并逐页查看截图。Windows 桌面会把高于工作区的实体窗口限制在任务栏上方；不得通过手动放大根节点伪造 `720×1558` 截图，因为那只会拉高渲染背景，Container 仍按受限窗口高度布局。桌面自动化矩阵使用可真实承载的 `720×960` 竖屏；更高设备比例仍需在目标设备或可控离屏渲染环境中复验。

人工签字至少核对裁切、层级、触控安全区、文字对比、首帧承接、键盘/手柄焦点、44px 命中根和 Reduced Motion 静态终态；纸片、旋转、描边、硬投影与焦点环的视觉包络不得越过控件根包络或最近裁剪祖先。

`capture_visual_review.gd` 负责实际移动命令、稳定帧和耗时证据；`capture_ui_vfx_matrix.gd` 负责页面与状态矩阵。两者用途不同，不以其中一个替代另一个。

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

### 脚本静态检查

不启动 Godot，只检查 PowerShell 脚本文本可解析：

```powershell
$script = Get-Content -Raw -Encoding UTF8 tools/run_gut_safe.ps1
$null = [scriptblock]::Create($script)
```

## 持续验证边界

- 平台发布只能由当次环境报告、正式零错误导出和目标设备矩阵共同签字；静态配置通过不能替代工具链或真机证据。
- GDScript LSP 始终以零 error、零 warning 为门禁，修改 `.gd` 后必须复跑并读取当次生成报告。
- 退出泄漏基线只用于阻止 ObjectDB、Resource 与 RID 债务增长，不代表债务已经修复；`GFTextFitter` 的 `ShapedText` / `Font` RID 仍由完整 GUT 维持零增长门禁。
- 当前截图工具提供真实跨视口证据，但没有自动像素差异门禁；视觉签字仍需人工逐页检查。
