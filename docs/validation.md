# 验证指南

本文档记录不启动 Godot 的安全验证，以及未来运行 Godot/GUT 前必须满足的约束。

## 默认验证顺序

### 1. 空白与路径检查

```powershell
git diff --check -- .gitignore .gf project.godot gf_project_profile.json addons/gf app features shared tests README.md docs tools
```

### 2. GF 包状态

```powershell
godot --headless --path . --script res://addons/gf/kernel/package/gf_package_cli.gd -- status --json
```

期望：

- `ok` 为 `true`
- `issue_count` 为 `0`
- `orphan_packages` 为空
- `lockfile_verify.ok` 为 `true`
- 如果 `.gf/packages.lock.json` 存在，`installed_count` 与 lockfile 中的 installed 包数量一致

注意：GF 9 使用 Godot 原生包管理 CLI，入口是 `res://addons/gf/kernel/package/gf_package_cli.gd`。不要继续使用旧的 Python `addons/gf/kernel/package_tools/gf_package_installer.py` 命令。

当前仓库是手动更新后的 vendored GF 源码状态，`.gf/packages.lock.json` 可能暂时不存在。缺失 lockfile 时，包状态命令会把 lockfile 视为空安装状态；这不等价于项目运行失败，但表示当前 GF 源码不是由包管理器重建出来的。若后续恢复包管理器安装流，应先重新生成 lockfile，再恢复对 installed 包数量的强校验。

手动 vendored 源码由独立锁文件校验：

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_gf_vendor.ps1
```

该命令校验 `addons/gf/` 的版本、文件数和内容哈希是否与 `.gf/vendor.lock.json` 一致。GF Python 工具运行时生成的 `__pycache__` / `*.pyc` 不属于 vendor 快照，校验和 Git 均明确排除；除此之外的额外文件仍会导致校验失败。更新 GF 后必须同步锁文件；不要把 package lockfile 和 vendor lockfile 混为一谈。

2026-07-20 的本机复核中，Steam Godot 4.7 因 SSL 模块初始化失败而无法连接远程 registry，`status --json` 因此报告 1 个环境 issue；同一工作树的离线 vendor 校验通过，版本为 `9.0.1`、文件数为 `1684`，SHA-256 为 `c2d921861f7d0afe8d8de343be4f07001e62016f88c4d5de576c36d6e71a994e`，commit 为 `5ab736d3e4037525b38c6cbee85cbe4c2b1b9b28`。远程 registry 可用性与本地 vendored 源码完整性必须分别报告。

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

### 最近一次安全 GUT 验证

验证时间：2026-07-23。

命令：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TimeoutSeconds 900 -MaxLogMB 32 -MaxDefaultLogGrowthKB 256
```

结果：

- Godot：`4.7.stable.steam.5b4e0cb0f`。
- GF Framework：官方稳定 tag `9.0.1`，commit `5ab736d3e4037525b38c6cbee85cbe4c2b1b9b28`。
- GUT：305 个测试全部通过，共 1943 个断言。
- 当前完整套件：`tests/gut/` 下 36 个顶层测试脚本、305 个 `test_` 用例。
- Boot 首帧壳与 Godot 原生启动图共用同一构图；正式 `BootRuntime` 由线程加载，在严格 `Gf.init()` 后等待视觉与声音主题通过 `GFAssetLoadSession` 完整预载、提交资源组并事务激活，随后再由 `GFScenePreloadMap`、`GFSceneUtility` 和 `GFRenderWarmupUtility` 预热稳定场景流与首轮游戏视觉资源。Boot 继续启用 `strict_dependency_lookup` 与 `fail_on_missing_declared_dependencies`；项目 Module 的静态跨模块查找均受声明覆盖门禁约束。高频进度写入由 `GameSaveGraphUtility` 合并后调用 GFStorage 异步接口，关键完成事务仍同步落盘。
- 未触发默认 Godot 用户日志增长保护。
- 退出泄漏与 `.gf/godot_exit_leak_baseline.json` 一致：`ObjectDB = 309`、`Resources = 131`、RID 类型数 `= 3`，上限为 TextureStorage 11、ShapedText 9、Font 5。GF 9.0.1 声明 732 个全局脚本类，当前项目运行时声明 185 个 `class_name`。本轮导航、回放、列表与庆祝效果测试扩展到 36/305，未增加 retained Node、Resource 或 RID 类别。基线绑定 `.gf/vendor.lock.json` 的精确 GF commit、vendor tree 和项目运行时类集合；输入集合不变时任何增长都会失败。
- 临时运行目录已在成功后自动清理。

注意：脚本在当前环境中可能无法从 Godot 进程对象直接读取退出码，因此会在退出码为空时根据 GUT 输出中的成功标记推断成功。后续如果切换到明确的 Godot `4.7` 可执行文件，建议再运行一次同样的安全验证。

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

最近一次 LSP 诊断时间：2026-07-22。结果：扫描 230 个 `.gd` 文件，`diagnostic_count = 0`、`timeout_count = 0`。

## 视觉与操作回放

真实场景流截图由项目内回放工具生成，不使用手工拼接的测试节点：

```powershell
powershell -ExecutionPolicy Bypass -File tools/invoke_godot_project_tool.ps1 -ScriptPath res://tools/capture_visual_review.gd -Rendering -ExpectedOutputPattern "[VisualReview] slowest_command_usec=" -TimeoutSeconds 240
```

输出位于忽略提交的 `build/visual_review/`，覆盖主菜单、场景遮罩、模式选择、主题化下拉菜单、稳定游戏帧和实际 `MoveCommand` 合并帧。最近一次 1280x720 回放中，最慢命令样本为 `6165 us`；截图确认方块身份图案被裁切在安全区，合并反馈包含冲击环、碎片和多方向分数飘字。

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

最近一次项目预检为 `8 checks / 0 issues`。官方 Godot 4.7.1 Web 导出已在 Chromium 的 `390x844` 与 `1280x720` 视口完成 Compatibility 冒烟，控制台 `0 error / 0 warning`，本地存储写入回读通过。当前默认 Steam Godot 4.7 环境报告保留 2 个 blocker：缺少精确匹配的 `4.7.stable` 导出模板，以及未检测到微信开发者工具 CLI。

### 脚本静态检查

不启动 Godot，只检查 PowerShell 脚本文本可解析：

```powershell
$script = Get-Content -Raw -Encoding UTF8 tools/run_gut_safe.ps1
$null = [scriptblock]::Create($script)
```

## 当前验证缺口

- 当前默认 Steam Godot 4.7 缺少精确匹配的 `4.7.stable` 导出模板；微信开发者工具 CLI、微信导出适配器和微信真机矩阵也尚未完成，因此当前只保留已完成的官方 Godot 4.7.1 标准 Web 兼容性签字，不签字微信小游戏发布就绪。
- GF 9.0.1 已包含 `gf-framework#9` / `gf-framework#10` 的导出插件 `_get_name()` 修复；安装与当前 Godot 4.7 精确匹配的导出模板后，仍需重新执行正式零错误导出签字。
- Godot 编辑器中的 GDScript warning 已通过 `tools/check_gdscript_lsp_diagnostics.ps1` 建立零诊断基线；后续修改 `.gd` 后应复跑。
- Godot 退出仍存在已量化的框架/测试对象泄漏债务；当前通过严格基线阻止继续增长，不能把基线当成已经修复。
- GF 9.0.1 已包含 `gf-framework#6` / `gf-framework#7` 的文本测量修复；项目方块文本已迁移到 `GFTextFitter.MeasurementMode.SINGLE_LINE`，完整 GUT 仍必须维持 `ShapedText` / `Font` RID 零增长门禁。
- 开发构建已通过 `GFScreenshotUtility` 提供单张与支持报告现场截图，但尚未建立跨分辨率的视觉基线比较和像素差异门禁。
- GF 包管理器的独立 lockfile 校验入口已并入原生 CLI `status --json` 的 `lockfile_verify` 字段；若后续 CLI 再次变化，需要先更新本文档再更新自动化命令。
