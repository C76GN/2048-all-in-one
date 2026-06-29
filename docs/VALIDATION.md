# 验证指南

本文档记录不启动 Godot 的安全验证，以及未来运行 Godot/GUT 前必须满足的约束。

## 默认验证顺序

### 1. 空白与路径检查

```powershell
git diff --check -- .gitignore .gf/packages.lock.json project.godot addons/gf scripts resources scenes tests README.md AI_MAINTENANCE.md CODING_STYLE.md docs tools
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

注意：GF 7 使用 Godot 原生包管理 CLI，入口是 `res://addons/gf/kernel/package/gf_package_cli.gd`。不要继续使用旧的 Python `addons/gf/kernel/package_tools/gf_package_installer.py` 命令。

当前仓库是手动更新后的 vendored GF 源码状态，`.gf/packages.lock.json` 可能暂时不存在。缺失 lockfile 时，包状态命令会把 lockfile 视为空安装状态；这不等价于项目运行失败，但表示当前 GF 源码不是由包管理器重建出来的。若后续恢复包管理器安装流，应先重新生成 lockfile，再恢复对 installed 包数量的强校验。

## Godot / GUT 运行策略

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
- `-TimeoutSeconds`：超时时间，默认 `180`。
- `-MaxLogMB`：临时 Godot 日志大小上限，默认 `32`。
- `-MaxDefaultLogGrowthKB`：默认 Godot 用户日志允许增长上限，默认 `256`。
- `-PollIntervalMilliseconds`：日志和超时轮询间隔，默认 `100`。
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

### 最近一次安全 GUT 验证

验证时间：2026-06-19。

命令：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot -TimeoutSeconds 45 -MaxLogMB 4 -MaxDefaultLogGrowthKB 64
```

结果：

- Godot：当前环境中的 `godot` 命令。
- GUT：命令完成并由安全脚本推断为成功。
- 当前静态计数：`tests/gut/` 下 14 个脚本、93 个 `test_` 用例。
- 临时 `godot.log` 大小：约 `0.006 MB`。
- 未触发默认 Godot 用户日志增长保护。
- 当前输出无 GUT `Orphans` 提示。
- 临时运行目录已在成功后自动清理。

注意：脚本在当前环境中可能无法从 Godot 进程对象直接读取退出码，因此会在退出码为空时根据 GUT 输出中的成功标记推断成功。后续如果切换到明确的 Godot `4.7` 可执行文件，建议再运行一次同样的安全验证。

### 脚本静态检查

不启动 Godot，只检查 PowerShell 脚本文本可解析：

```powershell
$script = Get-Content -Raw -Encoding UTF8 tools/run_gut_safe.ps1
$null = [scriptblock]::Create($script)
```

## 当前验证缺口

- `tools/run_gut_safe.ps1` 已通过一次隔离 GUT 验证；后续仍建议用当前编辑器一致的 Godot `4.7` 可执行文件复测。
- Godot 编辑器中的 GDScript warning 数量需要在安全运行方案恢复后重新确认。
- 视觉和响应式布局仍需要 Playwright/截图或 Godot 运行级验证，目前只能依靠资源和脚本静态检查。
- GF 包管理器的独立 lockfile 校验入口已并入原生 CLI `status --json` 的 `lockfile_verify` 字段；若后续 CLI 再次变化，需要先更新本文档再更新自动化命令。
