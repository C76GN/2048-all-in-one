# 2048 All In One

基于 Godot 4.7+ 与 GF Framework 的可扩展 2048 规则组合游戏。项目支持多种规则、确定性回放与书签、自定义棋盘、方块组合、主题、本地多账号和离线排行榜，并面向 Windows/Steam、Web、移动端与微信小游戏保持可移植边界。

## 运行

在 Godot 中打开 `project.godot`，或从项目根目录运行：

```powershell
godot --path .
```

启动入口是 `app/scenes/boot.tscn`。启动链会先安装项目架构、初始化 GF，再提交主题和进入玩家界面。

## 目录

- `app/`：启动、Composition Root 与跨 Feature 装配。
- `features/`：按业务能力内聚的玩法、导航、存档、主题和工具切片。
- `shared/`：真正跨 Feature 的契约、UI 原语、资源和 Utility。
- `tests/`、`tools/`：跨 Feature 验证与维护自动化。
- `addons/gf/`：由 `.gf/vendor.lock.json` 精确锁定的只读 GF vendor。

目录与依赖的可执行真相是 `gf_project_profile.json` 和 `.gf/project_contract.json`。项目功能不得直接修改 `addons/gf/`；通用框架问题按 `docs/ai_maintenance.md` 的 issue-first 流程处理。

## 验证

常用门禁：

```powershell
python addons/gf/tools/ai_developer/gf_ai_project.py validate --project-root .
powershell -ExecutionPolicy Bypass -File tools/validate_project_layout.ps1 -GodotExecutable godot
powershell -ExecutionPolicy Bypass -File tools/check_gdscript_lsp_diagnostics.ps1
powershell -ExecutionPolicy Bypass -File tools/run_gut_safe.ps1 -GodotExecutable godot
```

不要直接运行裸 GUT；安全包装器会隔离用户目录并限制日志增长。

## 文档

从 [`docs/readme.md`](docs/readme.md) 进入项目文档。架构、存档、视觉、素材治理、验证和活跃路线图分别由该索引指向，README 不重复维护易漂移的实现清单、GF 包列表或测试数量。
