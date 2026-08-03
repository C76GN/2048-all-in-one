# C76 Common Asset Library

本页是项目素材库 Feature 的操作入口。跨 Feature 的信任边界、晋升规则和权威来源表见 [`docs/asset_library.md`](../../../docs/asset_library.md)。

## 目录职责

- `resources/gf_content_package.json`：玩家运行时素材清单，只登记稳定的 `asset.*` 键。
- `resources/source_packs/`：待评审素材副本，不进入玩家导出。
- `resources/review/`：评审记录、源包元数据与槽位映射，不进入玩家导出。
- `resources/import_sources.json`：可提交的源包身份、授权元数据与格式分组；`source_path` 必须为空。
- `resources/import_sources.local.json`：按 `source_pack_id` 提供本机作者素材路径，已被 Git 和导出排除。
- `resources/source_exclusions.json`：已清除候选的可移植身份，防止再次导入。
- `build/asset_library/`：当次导入和审计报告，仅作运行证据并忽略提交。

素材身份统一使用 `source_pack_id + relative_path + SHA-256`。评审记录、源包资源和源包 manifest 不保存工作站绝对路径。

玩家运行时仍通过稳定 `asset.*` resource key 解析和加载素材。GF 目录由
`GFContentPackageAssetCatalogProvider` 构建，并由 `GFAssetCatalogRuntime` 原子挂载；
目录条目 ID 采用当前 vendored GF 内容目录契约 `package_id/resource_key`，项目代码需要目录条目时调用
`GameAssetLibraryUtility.get_runtime_catalog_entry()`，不得自行拼接或回退资源路径。
`GameAssetLibraryUtility` 通过 owner-bound `GFSignalUtility` 跟随
`ProjectContentCatalogUtility.catalog_refreshed`；刷新先构造完整候选目录，再以
`replace_mount_catalog()` 原子替换当前 mount。失败时继续提供上一 revision，禁止先清空旧目录或让业务观察半更新状态。

`resources/review/asset_slot_map.tres` 及其 `AssetSlotMap`/`AssetSlotBinding`
只保存作者审核所需的候选、采用项、回退项和标签，不持有玩家运行时资源。当前主题等
可替换资源的强引用、类型契约、generation 与终态释放统一由 `GFAssetSlot` 负责；
审核元数据不会伪装成运行时句柄。

## 标准流程

1. 在本机 `resources/import_sources.local.json` 配置源包路径。
2. 运行 `tools/import_asset_sources.ps1` 刷新候选副本和评审记录。
3. 打开 `features/asset_library/scenes/asset_review_browser.tscn` 完成试听、标签、评分和状态评审。
4. 必要时运行 `features/asset_library/tools/sync_audio_review_variants.gd`，只在显式同源编码组内同步无歧义的评审状态。
5. 运行 `tools/purge_rejected_assets.ps1` 清除已拒绝且无引用的候选。
6. 运行 `tools/audit_asset_library.ps1`，确认运行时清单、授权、引用与候选边界均通过。

本机覆盖文件的最小结构如下，键必须与共享配置中的 `source_pack_id` 一致：

```json
{
  "schema_version": 1,
  "source_paths": {
    "source_pack_id": "<absolute-path-to-source>"
  }
}
```

`GFProjectReferenceScanner` 的 partial 结果视为失败；不得据此删除素材。`review_status=approved` 只表示质量通过，进入运行时还必须具有明确授权，并复制或转码到运行时目录、登记稳定素材键且通过审计。

同一声音的 WAV、OGG、MP3 仅在 `import_sources.json` 中显式验证并声明后才可同步评审状态；评分、备注、标签、哈希、可播放性和授权仍按具体文件保存。禁止跨源包通过模糊文件名自动合并。

评审快捷键：`Space` 播放/暂停，`1`/`2`/`3` 设置状态，`J`/`K` 切换记录，`Ctrl+S` 保存；文本输入聚焦时会屏蔽裸键操作。
