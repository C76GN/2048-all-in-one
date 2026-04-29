# 2048 All In One

一个基于 Godot 4 和 gf 1.17.0 的可扩展 2048 规则实验项目。项目把棋盘数据、规则、输入、存档、回放和 UI 流程拆成独立模块，目标是作为 gf 框架在中小型游戏中的最佳实践示例。

## 技术栈

- Godot 4.6+
- gf 1.17.0
- GDScript，遵循 `CODING_STYLE.md`

## 架构概览

- `scripts/boot/game_architecture_installer.gd` 集中注册 Model、System、Utility，并由 Project Settings 中的 gf installer 驱动启动。
- `scripts/models/` 保存可绑定运行时状态，例如棋盘、当前模式、分数和最高方块。
- `scripts/systems/` 承担业务流程：初始化、输入、移动、生成、存档、回放、场景路由和游戏状态。
- `scripts/rules/` 是规则资源的实现层。移动、交互、生成、结束判定互相解耦，模式配置通过 `resources/modes/*.tres` 组合它们。
- `resources/input/gameplay_input_context.tres` 使用 `GFInputContext` / `GFInputMapping` 描述玩法输入，运行时由 `GFInputMappingUtility` 消费。
- `assets/translations.csv` 提供中文和英文 UI 文案。

## gf 使用方式

项目启动入口是 `scenes/boot/boot.tscn`。`boot.gd` 调用 `await Gf.init()`，gf 会执行项目级 installer 并完成三阶段生命周期。业务模块内部优先使用 `GFSystem` / `GFController` 的基类方法访问 Model、System、Utility 和事件总线。

当前重点实践：

- 用项目级 installer 管理注册顺序。
- 用 `GFCommandHistoryUtility.execute_command()` 和 `undo_last_async()` 管理移动命令与撤销。
- 用 `GFInputMappingUtility` 管理资源化输入上下文。
- 用 `GFSceneUtility` 做异步场景切换，`SceneRouterSystem` 负责业务事件和路由意图。
- 用 `RuleContext` 给规则注入上下文并收集输出，避免规则资源直接触达全局 `Gf`。

## 新增模式的推荐流程

1. 在 `scripts/rules/` 中实现所需的 `InteractionRule`、`MovementRule`、`SpawnRule` 或 `GameOverRule`。
2. 在 `resources/rules/` 中创建对应资源。
3. 新增 `resources/modes/*.tres`，组合棋盘主题、颜色主题和规则资源。
4. 在菜单配置中引用新的模式资源。
5. 运行冒烟测试确认初始化、移动、生成、撤销和回放都仍然可用。

## 本地校验

```powershell
godot --headless --path . --import
godot --headless --path . --quit
godot --headless --path . --scene res://scripts/tests/runtime_smoke_test.tscn
```

`runtime_smoke_test.tscn` 会覆盖框架注册、棋盘初始化、有效移动、命令历史、回放关键路径和基础状态同步。
