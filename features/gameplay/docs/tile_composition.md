# 方块组合架构

本文档定义 gameplay Feature 内方块身份、GF Capability、运行时状态和表现投影的当前契约。目标是支持规则混合、运行时获得或失去能力、严格存档以及可辨识的复合视觉，不为每一种组合继续创建条件分支。

## 四层模型

### TileDefinition

`TileDefinition` 是稳定身份资产，不是运行时方块实例。它拥有：

- `definition_id`：跨快照和诊断稳定的身份 ID。
- `capability_recipes`：此身份允许挂载的 GF Recipe 目录。
- `initial_recipe_ids`：创建时默认挂载的 Recipe 组合。
- `color_scheme_index`：主题色阶槽位，不携带玩法阵营语义。
- `visual_family_id` 与 `audio_family_id`：基础轮廓、材质和声音家族。

定义只声明允许范围和初始组合。运行时不能挂载目录外的 Recipe。

### GFCapabilityRecipe

一个 Recipe 表达一种可独立授予和拆卸的规则特征。当前示例包括经典相加、斐波那契相加、卢卡斯相加、卢卡斯桥接和跨定义求商。

每个方块 Recipe 必须：

- 使用稳定且唯一的 `recipe_id`。
- 通过 GF 自身的 Recipe 校验。
- 在 `metadata` 中声明 `visual_layer_id` 和 `audio_layer_id`。
- 独占其顶层 Capability 类型，避免拆卸一个 Recipe 时破坏另一个 Recipe。

Recipe group 用于 GF 查询和诊断。拆卸后由 `TileCompositionUtility` 按剩余 Recipe 重建 group，不直接删除共享 group。

### TileState

`TileState` 是纯数据和 GF Capability receiver，不依赖 Node。它持久化：

- UUID v7 `tile_id`。
- `definition_id`。
- 当前数值。
- 当前实际挂载的 `capability_recipe_ids`。
- 按 Recipe ID 隔离的 `capability_state`。

`capability_recipe_ids` 是事实来源。恢复时不能只按定义重新猜测初始能力，否则运行时获得的规则会丢失。

### TileInteractionCapability

Capability 读取两个方块并返回不可变更状态的 `TileInteractionProposal`。`TileCompositionUtility` 收集双方共同启用的 Capability 提案，按优先级和稳定规则 ID 仲裁，再统一应用结果。

同优先级、不同状态结果属于配置冲突，必须拒绝交互；不能依赖数组顺序决定结果。Capability 不直接修改棋盘、分数、节点或存档。

## 运行时流程

创建：

1. Spawn System 从当前 `InteractionRule` 解析 `TileDefinition`。
2. `TileCompositionUtility.create_tile()` 创建 `TileState`。
3. Utility 事务应用定义的初始 GF Recipe，并记录实际 Recipe ID。
4. 棋盘只接受由该工厂创建的状态。

交互：

1. Movement Rule 只决定候选碰撞顺序。
2. `InteractionRule` 将候选方块交给 `TileCompositionUtility`。
3. Utility 查询 GF Capability、生成并仲裁提案。
4. Utility 修改承载结果的实例、释放被消费实例的 Capability，再返回强约束结果字典。

动态组合：

- `grant_recipe()` 只允许授予定义目录内的 Recipe。
- `revoke_recipe()` 拆卸 Capability、清理对应状态命名空间并重建 GF group。
- `recompose_tile()` 用于身份整体变化，并在失败时恢复原定义、Recipe 和状态。

## 无阵营契约

方块定义描述身份和允许组合的能力，不表示玩家、敌人、怪物或任何阵营。一次碰撞的结果只由双方共同挂载的交互能力、定义和值决定：

- 同定义的两个 `2` 共享经典相加能力，得到 `2 + 2 = 4`。
- 不同定义的两个 `2` 共享跨定义求商能力，得到 `2 / 2 = 1`。
- 跨定义求商优先级高于经典相加，因此两个定义恰好同值时仍按求商结算。
- 结果由提案中的 `survivor_side` 指定承载实例，只表达状态延续位置，不表达胜负。

不得重新引入 `role`、`faction`、`player_type`、`monster_type` 或等价字段。若将来需要新的相互作用，应新增 GF Capability Recipe 或方块定义，而不是增加阵营条件分支。

## 当前示例

- 经典方块：初始组合为 `tile.recipe.classic_merge`。
- 斐波那契方块：初始组合为 `tile.recipe.fibonacci_merge`。
- 经典加斐波那契方块：目录包含两个独立 Recipe，初始时同时挂载二者。
- 卢卡斯加斐波那契方块：组合斐波那契、卢卡斯和桥接三个独立 Recipe。
- 比值模式：基础方块和因子方块是两个中性定义，都组合经典相加与跨定义求商 Recipe；视觉家族与色阶槽位用于辨识定义，不代表阵营。

因此“获得一条新规则”应表现为授予 Recipe，而不是生成新的硬编码组合类。

## 表现规则

复合表现使用固定语义通道，不把多张全幅纹理直接相乘：

- `visual_family_id` 决定基础材质纹理，确保同一身份的不同数值属于同一家族。
- 每个 Recipe 的 `visual_layer_id` 映射为边缘小标记，最多显示四个，中央数字保持清晰。
- `audio_family_id` 决定基础音色，Recipe 的 `audio_layer_id` 为获得、触发或拆卸能力提供语义声音层。
- 数值仍决定色阶和字号，不决定身份纹理。

立方体、骰子等空间形态应使用新的视觉家族和运动表现组件；规则能力标记仍沿用 Recipe 层，不通过叠加完整方块皮肤表达。

## 严格持久化

- `GridModel` 快照必须匹配 `SNAPSHOT_SCHEMA_VERSION`。
- 每个方块字典必须匹配 `TileState.SERIALIZATION_SCHEMA_VERSION`。
- UUID、定义、Recipe ID、状态命名空间或位置任一无效时，整张棋盘原子拒绝恢复。
- 破坏性 schema 调整使用显式迁移工具，不在运行时长期保留双读分支。

## 后续扩展边界

立方体翻滚、骰子定面和逐方块位移策略不属于 `TileInteractionCapability`。实现时应新增强类型移动提案协议，由方块移动 Capability 描述位移方式、朝向变换和动画语义，再由统一 Resolver 仲裁；不得在 `ClassicMovementRule` 中追加类型判断。

图鉴读取 `TileDefinition.to_descriptor()`、GF Recipe 描述和表现 descriptor。图鉴中的“?”只替代数值等运行时变量，不隐藏定义身份或 Recipe 组合。
