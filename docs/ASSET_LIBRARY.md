# 素材库规范

`asset_library/` 是当前项目内的通用素材库。它暂时随项目提交，后续成熟后可以整体迁移到 `addons/c76_asset_library/` 或独立仓库。

## 目标

- 音频、shader、贴图、特效等素材先进入统一库，不再散落在业务目录。
- 每个正式素材都有稳定 `asset.*` 资源键。
- 第三方素材必须记录作者、来源和授权。
- 工具可以自动报告素材是否存在、是否登记、被谁引用。

## 目录

```text
asset_library/
  gf_content_package.json
  import_sources.json
  audio/
  shaders/
  textures/
  vfx/
  licenses/
  source_packs/
  review/
  reports/
```

`audio/`、`shaders/`、`textures/`、`vfx/` 是已批准运行时素材区，只有这里的正式素材才进入 `gf_content_package.json`。

`source_packs/` 和 `review/` 是候选评审区：

- `source_packs/<pack_id>/files/` 保存原始下载包的完整复制。
- `review/records/<pack_id>/*.tres` 保存每个候选素材的状态、评分、标签、备注、哈希和授权信息。
- `review/source_packs/*.tres` 保存源包级授权和来源信息。
- `review/asset_slot_map.tres` 保存“用途槽位”到当前运行时素材的映射，方便后续替换。

空目录只表示未来分类方向。没有可用素材时，不要在运行时 manifest 中创建占位条目。

## 稳定 ID

资源键使用：

```text
asset.<kind>.<domain>.<theme_or_pack>.<name>
```

示例：

```text
asset.audio.ui.printworks.select_soft_01
asset.audio.tile.printworks.merge_soft_01
asset.shader.transition.halftone_wipe
asset.shader.ui.button_focus_dash
asset.shader.ui.startup_progress_bar
asset.vfx.celebration.confetti_canvas
```

规则：

- `kind` 对应素材大类：`audio`、`shader`、`texture`、`vfx`。
- `domain` 对应使用语义：`ui`、`tile`、`game`、`background`、`transition`。
- 文件可以移动，但资源键不应随意改名。
- 主题、音效银行或场景必须优先通过 manifest 中的素材路径或稳定 key 建立引用。

## GF 接入

- `asset_library/gf_content_package.json` 是 GF 内容包 manifest。
- `GameAssetLibraryUtility` 注册 `res://asset_library` 到 `GFContentPackageUtility`。
- 素材资源键同步到 `GFResourceResolverUtility`，供项目通过稳定 ID 解析和加载。
- `GameContentPackageCatalogSourceProvider` 和 `GameAssetReviewCatalogSourceProvider` 通过 `GFAssetCatalogSourceRegistry` 把运行时素材与候选素材映射为统一的 `GFAssetCatalog` 接口。
- 项目引用由 `GFProjectReferenceScanner` 扫描；第三方归因、授权覆盖率和 notices 由 `GFAssetAttributionTools` 生成。
- 主题包 `resources/gf_content_package.json` 依赖 `c76.asset_library.core`。

## 审计

运行：

```powershell
tools\audit_asset_library.ps1
```

输出：

```text
asset_library/reports/asset_audit.json
asset_library/reports/asset_audit.md
asset_library/reports/review_catalog_audit.json
asset_library/reports/review_catalog_audit.md
```

运行时素材审计会检查：

- manifest 是否有效。
- 登记素材文件是否存在。
- 库内是否有未登记运行时素材。
- 第三方素材是否有作者、来源 URL 和授权。
- 每个素材被哪些项目文件按路径或 key 引用，以及引用扫描是否完整。
- 运行时目录的 GF attribution coverage 是否完整。

评审目录审计会检查：

- 候选记录数量、类型、状态和授权分布。
- 候选 `GFAssetCatalog` 是否可以按状态、类型、标签和稳定 ID 查询。
- 源包授权是否已确认。
- 已批准候选是否仍缺少明确授权。
- 用途槽位绑定的运行时文件是否存在。

## 批量导入候选素材

候选源包登记在：

```text
asset_library/import_sources.json
```

运行：

```powershell
tools\import_asset_sources.ps1
```

当前导入会复制这些源包：

- `E:/_inbox/Downloads/UI Soundpack`
- `E:/_inbox/Downloads/JDSherbert - Ultimate UI SFX Pack (FREE)/Mono`
- `E:/_inbox/Downloads/shader`
- `E:/_inbox/Downloads/400 Sounds Pack`
- `E:/_inbox/Downloads/UltimateToonSource`

此外，`asset_library/source_packs/manual_shader_notes/` 用于保存从对话、实验或临时笔记中手动收集的候选 shader，例如 2.5D foliage/billboard、world-space coordinate grid、luminance texture-mask transition、shine sweep overlay、surface-masked shine sweep、space cloud starfield background、flicker noise background、gyroid FBM background、rain/snow weather overlay、Brian Smith MIT rain/snow overlay、chromatic aberration glitch、screen lens aberration shockwave、hand-drawn hatch tile pattern、animated checker tile pattern、angled stripe tile pattern、sine wave stripe pattern、square wave tile pattern、noise node-link tile pattern、new item radial shine 等。它不由 `import_sources.json` 刷新，默认只进入评审目录，授权和用途明确后再晋升到正式运行时分类目录。

`asset_library/source_packs/manual_effect_notes/` 用于保存从对话中捕获的交互 VFX 配方，例如点击位置转 UV、驱动 shader `position` / `radius` 参数的 burn/dissolve 卡片反馈，按钮 hover/drag follow/wobble 动效配方，以及 pooled shader drop/decal 控制器。它保存的是设计配方和参考代码，不是可直接运行的正式素材；需要配套 shader、授权、UI 适配、可访问性和可读性验证后才能晋升。

导入规则：

- 全量复制源文件，保留原始目录结构。
- 为音频、shader、贴图、场景/资源候选生成 `AssetReviewRecord`。
- 重复导入不会覆盖人工评审状态、评分、标签和备注。
- 授权未知的源包只进入评审区，不会自动进入 `gf_content_package.json`。
- 导入报告输出到 `asset_library/reports/source_import_report.json` 和 `.md`。

## 评审浏览器

打开或运行：

```text
scenes/tools/asset_review_browser.tscn
```

这个内部工具可以：

- 搜索候选素材。
- 按评审状态过滤。
- 播放支持的音频。
- 预览 shader 和图片。
- 修改状态、评分、标签和备注。
- 保存回对应的 `review/records/*.tres`。

浏览器的搜索和状态过滤以 `GFAssetCatalog` 为真相来源；保存评审记录后会重建目录，不维护第二套手写索引。

## 批准素材流程

1. 先通过 `asset_review_browser.tscn` 试听/预览并写备注。
2. 确认授权，必要时更新 `import_sources.json` 或对应源包 `.tres`。
3. 将可用素材从 `source_packs/` 复制或转码到正式分类目录。
4. 在 `gf_content_package.json` 中登记稳定 `asset.*` key。
5. 补齐 `asset_kind`、`category`、`origin`、`author`、`source`、`license`。
6. 第三方素材还要补 `source_url`，并在 `licenses/` 或 `docs/THIRD_PARTY_ASSETS.md` 记录来源。
7. 更新 `review/asset_slot_map.tres` 或具体主题、音效银行、场景引用。
8. 运行 `tools\audit_asset_library.ps1` 和 `tools\run_gut_safe.ps1`。
