# 项目文档索引

本页定义文档权威层级与维护入口。它不复制易变的版本号、测试数量、运行时类数量或环境状态；需要判断“现在是什么”时，按下列顺序读取。

## 权威层级

1. **可执行真相**：实际代码与资源、`project.godot`、[`gf_project_profile.json`](../gf_project_profile.json)、[`.gf/project_contract.json`](../.gf/project_contract.json)、[`addons/gf/plugin.cfg`](../addons/gf/plugin.cfg) 和 [`.gf/vendor.lock.json`](../.gf/vendor.lock.json)。
2. **规范文档**：本目录中的架构、数据、编码、视觉、素材和验证契约。规范必须与可执行真相同一变更更新；发生冲突时先按代码和可执行配置确认事实，再修正文档。
3. **Feature 操作文档**：`features/*/docs/` 中由具体 Feature 拥有的工作流、工具和领域说明。项目级文档定义边界，Feature 文档定义具体操作。
4. **计划与证据**：Roadmap 表达尚未完成的意图；生成报告表达某次运行结果；`docs/research/` 是带日期的历史研究快照。三者都不能覆盖当前代码或规范契约。

精确 GF 版本只从 `addons/gf/plugin.cfg` 读取，vendor 身份只从 `.gf/vendor.lock.json` 读取。`addons/gf/` 是只读上游快照；项目不得直接修补 vendor。

## 核心规范

- [架构与 Feature 所有权](./architecture.md)
- [存档与 schema 真值](./save_model.md)
- [视觉、UI 与特效规范](./visual_style.md)
- [编码规范](./coding_style.md)
- [AI / 维护工作流](./ai_maintenance.md)
- [验证策略](./validation.md)
- [素材库项目级治理](./asset_library.md)
- [第三方素材与许可证](./third_party_assets.md)

## Feature 文档

- [成就](../features/achievements/docs/achievements.md)
- [素材库操作说明](../features/asset_library/docs/readme.md)
- [棋盘编辑器](../features/board_editor/docs/board_editor.md)
- [棋盘拓扑](../features/gameplay/docs/board_topology.md)
- [方块组合规则](../features/gameplay/docs/tile_composition.md)
- [微信小游戏准备基线](../features/platform_runtime/docs/wechat_minigame_readiness.md)
- [反馈性能矩阵](../features/themes/docs/feedback_performance_matrix.md)
- [方块图鉴](../features/tile_catalog/docs/tile_catalog.md)

## 计划、研究与当前验证状态

- [Roadmap](./roadmap.md) 只描述方向与待办；完成状态必须回到代码、测试和对应规范核对。
- [竞品与灵感研究](./research/indie_game_benchmark/readme.md) 是有日期的历史证据库，其中“当前”只代表快照日。
- GF 合同现状通过 `python addons/gf/tools/ai_developer/gf_ai_project.py context --project-root .` 与 `validate --project-root .` 读取。
- GUT 现状以 `tools/run_gut_safe.ps1` 的当次输出为准；退出门禁读取 `.gf/godot_exit_leak_baseline.json`。
- GDScript LSP 现状以忽略提交的 `build/gdscript_lsp_diagnostics.json` 为准。
- 素材审计以 `features/asset_library/resources/reports/` 中本次生成的报告为准。
- 平台与工具链环境以 `build/platform_readiness_report.json` 和 `build/platform_environment_report.json` 为准。

生成报告必须带生成时间、输入范围或对应 vendor / 工作树身份；旧报告只能作为历史证据，不能复制成长期规范中的“当前数量”。

## 维护规则

- 修改代码导致所有权、schema、启动链、平台能力或资源流程变化时，在同一批次更新对应规范。
- 不在多份规范文档重复维护 Feature 所有权表、GF 包清单、精确版本、测试数量或环境检测结果；README 可提供概览，但必须链接权威来源。
- 文档中的本地文件引用使用仓库相对路径或 `res://`；除明确的作者工具执行输入和带日期研究证据外，不记录工作站绝对路径。
- 新文档先确定归属：跨 Feature 契约放在 `docs/`，具体 Feature 操作放在 `features/<feature>/docs/`，一次性调查放在带日期的 `docs/research/`。
