# 方块试验台契约

本页定义 `tile_lab` Feature 的产品与架构边界；实现状态以代码和测试为准。

## 所有权

- `tile_lab` 拥有玩家方块蓝图、蓝图校验、配方冲突解释、试验台 UI 和隔离沙盒状态。
- `tile_catalog` 提供已登记的 `TileDefinition` 与 Recipe 发现 Interface。
- `gameplay` 的 `TileCompositionUtility` 继续拥有 `GFCapabilityRecipe` 能力匹配与交互仲裁。
- `persistence` 只编排当前账号 Profile 的 `tile_blueprints` section，不解释蓝图字段。
- GF 提供 Recipe/Capability、目录、SaveGraph、UI 路由和生命周期机制，不拥有本项目方块内容或试验规则。

## 蓝图

一个可保存蓝图至少包含：

- UUID v7 稳定身份和玩家显示名。
- 基础 `TileDefinition` 稳定 ID。
- 有序、去重的 `GFCapabilityRecipe` 稳定 ID。
- 有界预览值及创建、更新时间。

蓝图不得保存资源路径、运行时能力实例、场景节点或普通对局快照。加载时必须重新解析当前目录并验证缺失定义、重复 Recipe、能力覆盖冲突与参数范围；失败不能用 fallback 猜测。

## 沙盒 Seam

沙盒从已校验蓝图构造临时 `TileState`，允许玩家生成、配对并执行一次真实交互。临时状态不进入普通对局的 canonical state、命令历史、书签、回放、统计、成就或排行榜资格。

如果未来允许蓝图进入正式模式，必须先新增稳定内容身份、规则指纹、书签和回放契约，并在模式配置中显式选择；保存蓝图本身不等于自动修改普通模式。

## 验收

- 任意保存、替换或删除失败都保持原蓝图集合。
- 键盘、手柄和触摸可以完成选择、组合、试验和返回。
- 空目录、无可兼容 Recipe、冲突组合和容量上限都有明确焦点与用户反馈。
- 同一蓝图重复序列化往返保持稳定身份与 Recipe 顺序。
