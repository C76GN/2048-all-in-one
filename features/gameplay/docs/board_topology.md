# 棋盘拓扑契约

本文档定义 gameplay Feature 的棋盘空间模型。它是玩家自定义棋盘、超大棋盘、可缩放视口和跨平台布局的共同基础。

## 领域边界

- `BoardTopology` 只回答“哪些坐标存在”，不保存方块、阵营、规则或表现。
- `GridModel` 只在活跃坐标上保存 `TileState`，空洞不是空方块，也不占容量。
- `BoardTopologyTemplate` 由 `GameModeConfig` 持有，声明模式接受固定拓扑、可变矩形或自定义拓扑。
- 当前模式选择页的尺寸下拉框和 `board_editor` Feature 都只是拓扑输入界面，不是运行时棋盘契约。

GF 没有与“四向、带空洞、连续 lane”完全同义的通用类型。`GFFlowGraph` 表达流程连接，`GFHexGridMath` 表达六边形网格；复用它们会混淆领域语义。因此拓扑由 gameplay Feature 拥有，同时复用 GF 的 `GFValidationReport`、确定性随机、Command History、Level Session 与 SaveGraph。

## 坐标与规范化

1. 活跃坐标使用 `Vector2i`，不得为负数。
2. 包围盒左上角必须是 `(0, 0)`。
3. `active_cells` 必须去重，并按 `y`、`x` 行优先升序保存。
4. 玩家绘制输入由 `BoardTopology.create_custom()` 平移、去重和排序。
5. 持久化输入不做修复；非规范顺序、重复坐标、未知 schema 或空拓扑直接拒绝。
6. 当前安全上限为 262144 个活跃单元，后续超大棋盘需先完成分块渲染与性能预算再调整。
7. 运行时把拓扑视为不可变值；`active_cells` 读取只返回副本，改变形状必须整体替换属性或创建新资源，以便查询、包围盒与指纹缓存同步失效。

## 移动语义

`get_move_lanes(direction)` 只接受四个单位方向。每条 lane 从移动前沿向后排列，并满足：

- 每个活跃单元在同一方向恰好属于一条 lane。
- 相邻坐标缺失时立即结束当前 lane；同一行或列中的后续单元形成新 lane。
- `MovementRule` 只处理单条连续 lane，不能感知或跨越拓扑空洞。
- 合并、反向动画映射和对边生成都使用同一 lane 顺序。

## 身份与持久化

- `topology_id` 表达语义来源，例如矩形模板或玩家棋盘 ID。
- `get_content_fingerprint()` 只对规范化活跃坐标计算 SHA-256 截断指纹。
- `get_stable_key()` 组合语义 ID 与内容指纹，供统计、排行榜和 GF Level Session 使用。
- `GridModel` 快照严格保存 `schema_version`、`topology` 和 `tiles`；方块位置必须属于快照拓扑。
- 书签与回放不保留旧 `grid_size` 双读分支。发布后若需要迁移，使用独立的一次性迁移工具。

## 当前能力

- 任意矩形、十字形和自定义稀疏拓扑。
- 空洞安全的移动、生成、判负、棋盘预览、撤销、书签与回放。
- 原 3x3 至 8x8 模式选择通过 `scalable_square_board_template.tres` 生成矩形拓扑。
- 调试扩建仅支持矩形正方形；它不是玩家棋盘编辑器。
- `board_editor` 已提供画笔、橡皮、矩形与十字预设、位置规范化、连通分量提示、局部 GF 撤销历史和玩家模板目录。
- 玩家模板使用 `custom_boards` SaveGraph section 和 `board.player.<uuid>` 稳定拓扑 ID。

## 后续顺序

1. 将棋盘表现拆为世界画布与 HUD，加入相机缩放、平移、聚焦和可见区域裁剪。
2. 增加响应式手机布局与 GF 输入上下文，区分滑动棋盘、拖动画布和 UI 手势。
3. 在稳定棋盘键上接入图鉴、成就与平台排行榜 Adapter。

任何后续形状都应先扩展拓扑或规则资源，不得重新引入固定二维数组或以 UI 尺寸推断逻辑空间。
