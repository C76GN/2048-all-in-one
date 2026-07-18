# 方块目录与发现契约

`tile_catalog` Feature 负责方块定义目录、稳定组合身份、玩家发现进度和图鉴 UI。它不实现移动、合并算法，也不复制主题资源。

## 所有权

- `TileDefinition` 与 `GFCapabilityRecipe` 是静态内容真源，仍位于 `gameplay` Feature。
- `TileCatalogUtility` 通过 `GFResourceRegistry`、`ProjectResourceCatalogUtility`、`GFResourceResolverUtility` 和 `GFAssetUtility` 注册、校验并查询全部定义。
- `TileDiscoverySystem` 观察 `TileCompositionUtility.tile_composition_observed` 与 `GameplayBoardReadyData`，不介入玩法决策。
- `TileDiscoverySaveData` 独占 SaveGraph 的 `discoveries` section，只保存玩家进度身份，不复制名称、颜色、纹理或音效路径。
- `TileCatalogDialog` 是 `GFUIRouterUtility` 的 `tile_catalog` 弹层 Route，只消费目录与发现系统的只读投影。

## 组合身份

方块组合身份由 `definition_id + 规范化 Recipe ID 集合` 决定。Recipe 顺序不影响身份，空 ID 和重复 ID 直接使组合无效。外部代码必须调用 `TileCatalogUtility.make_composition_key()`，不得自行拼接分隔字符串。

基础组合来自每个 `TileDefinition.initial_recipe_ids`。运行时授予或移除 Recipe 后形成的新组合只有在实际出现时才加入玩家图鉴；条目按定义和视觉家族连续排列。

## 发现数据

`discoveries@1` 根字段固定为：

```gdscript
{
	"tile_compositions": Array[Dictionary],
	"board_topologies": Array[Dictionary],
}
```

方块记录保存稳定组合键、定义 ID、Recipe ID、首次发现时间和最高观察值。棋盘记录保存稳定拓扑键、语义 ID、内容指纹、首次发现时间和单元数。

同一方块组合只在首次发现或最高观察值提升时提交 SaveGraph；同一棋盘稳定键只写入一次。所有替换都通过 `GameSaveGraphUtility.replace_section_data()` 原子保存，不允许旁路文件、逐帧写入或 UI 直接写存档。

## 表现投影

图鉴卡片复用正式 `Tile` 场景。颜色来自当前 `GameTheme` 的 `TileColorScheme`，身份纹理由 `visual_family_id` 决定，Recipe 标记来自 `visual_layer_ids`。图鉴不得维护第二套硬编码方块画法。

“?”只代表该类型可出现多个运行时数值。未发现条目可以隐藏名称和规则；发现后必须显示静态定义名称、Recipe 组合、最高值与发现时间。

桌面端使用网格与详情左右布局；窄屏切换为上下布局和单列卡片。安全区边距由 `GFViewportUtility` 应用，运行时信号由 `GFSignalUtility` 统一管理。

## 扩展规则

1. 新方块类型先新增合法 `TileDefinition`，再登记到 `tile_definition_registry.tres`。
2. 新 Recipe 必须提供稳定 `recipe_id`、`display_name_key`、`visual_layer_id` 与 `audio_layer_id`。
3. 新的主题、纹理和音效只通过表现 descriptor 与主题内容包接入，不进入发现存档。
4. 组合键算法、section schema 或稳定 ID 发生破坏性变化时必须提升 schema，并提供一次性显式迁移工具；运行时不保留长期双读。
5. 立方体、骰子等位移/朝向行为应扩展强类型移动 Capability，不得塞进图鉴或按 `definition_id` 写条件分支。

## 验证

聚焦测试位于 `tests/gut/test_tile_catalog.gd`，覆盖资源目录、组合键、Recipe 元数据、严格 section、观察事件、跨架构重载和响应式布局。UI 路由目录由 `tests/gut/test_game_ui_router_utility.gd` 验证。
