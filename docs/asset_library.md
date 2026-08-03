# 素材库规范

本文只定义项目级素材治理、信任边界和发布规则。命令、评审快捷键及工具行为由 [`features/asset_library/docs/readme.md`](../features/asset_library/docs/readme.md) 负责；二者不得重复维护同一操作说明。`features/asset_library/` 是项目 Feature，不属于只读的 `addons/gf/`。

## 权威来源

| 内容 | 权威来源 |
| --- | --- |
| 所有权、信任边界、晋升与发布规则 | 本文 |
| 操作命令、快捷键和工具行为 | `features/asset_library/docs/readme.md` |
| 已批准运行时素材与稳定资源键 | `features/asset_library/resources/gf_content_package.json` |
| 候选状态、评分、标签、备注和可移植身份 | `features/asset_library/resources/review/records/` |
| 同源音频编码分组和源包元数据 | `features/asset_library/resources/import_sources.json` |
| 本机作者素材根 | 忽略提交的 `features/asset_library/resources/import_sources.local.json` |
| 某次导入或审计结果 | 忽略提交的 `build/asset_library/` |

生成报告只表示一次运行结果，不能覆盖 manifest、评审记录或本规范，也不得提交本机绝对路径。

## 目录与单向晋升

```text
features/asset_library/resources/
  gf_content_package.json
  import_sources.json
  source_exclusions.json
  audio/
  shaders/
  textures/
  vfx/
  licenses/
  source_packs/
  review/
```

- `audio/`、`shaders/`、`textures/`、`vfx/` 是运行时区；正式素材必须登记到 manifest。
- `source_packs/` 和 `review/` 是作者评审区，不进入玩家导出。
- 候选素材只有在复制或转码到运行时区、登记稳定 key、补齐许可证并通过审计后才完成晋升。
- 导入、试听或 `review_status=approved` 都不会自动改变玩家内容。
- 空目录只表达分类方向，不应产生 manifest 占位条目。

## 信任与授权

下载的音频、Shader、纹理和第三方包均视为不可信输入：

1. 先进入 source pack，保留 `source_pack_id + relative_path + SHA-256` 身份。
2. 评审记录保存质量、标签、用途、来源 URL 和许可证状态。
3. `approved` 只表示质量通过；许可证未知、占位或缺失时，派生晋升门禁仍为 `blocked_license`。
4. 正式第三方素材必须同时具备作者、来源 URL、许可证和项目归因记录。
5. 任何不完整的路径、引用或授权扫描都视为失败，不能以部分结果继续晋升或删除。

质量结论与许可证门禁必须分离。不能通过改写质量状态来掩盖授权缺口，也不能因同名或相似文件自动合并不同来源。

## 可移植身份与本机路径

共享配置只保存源包身份、元数据和显式的同源编码分组。绝对作者路径只存在于被 Git 忽略的 `import_sources.local.json`，由 `source_pack_id` 覆盖对应本机根。

评审记录和 source-pack manifest 不保存工作站绝对路径；它们只依赖：

- `source_pack_id`
- `relative_path`
- `SHA-256`
- 项目内 `library_path`

因此换工作站只需重建本地 override，不会制造共享配置或数百条评审记录的无意义差异。生成报告可以在本机显示执行路径，但必须留在 `build/`，不得提交或外发未脱敏版本。

## 同源多格式音频

WAV、OGG、MP3 等编码只有在同一源包显式声明、并经试听或来源元数据确认属于同一声音时，才共享语义质量结论：

- 默认只同步 `review_status` 与 `reviewed_at`。
- 评分、标签、备注、文件哈希、可播放性和许可证证据保持编码级独立。
- 决定冲突或只来自不可播放编码时，批处理必须停止写入并报告。
- 不跨源包按文件名、时长或模糊指纹自动归并。

## 稳定资源键与 GF 边界

资源键格式：

```text
asset.<kind>.<domain>.<theme_or_pack>.<name>
```

- `kind` 表示 `audio`、`shader`、`texture` 或 `vfx`。
- `domain` 表示 `ui`、`tile`、`game`、`background`、`transition` 等业务语义。
- 文件可移动，稳定 key 不应随意改名。
- 运行时业务通过 `GameAssetLibraryUtility` 和稳定 key 解析素材，不使用作者路径后备。
- `ProjectContentCatalogUtility` 以 `project.content_catalog` owner scope 独占 GF 内容目录重建；包级条件使用 `GFContentPackageQuery`，资源级 `type_hint`、key 前缀和 metadata 保持项目薄筛选。
- 运行时目录由 `GFContentPackageAssetCatalogProvider` 构建并交给 `GFAssetCatalogRuntime` 原子挂载；规范目录 ID 为 `package_id/resource_key`，Resolver 与业务加载 API 继续使用原稳定资源键。首次 `ready()` 建立 mount，后续 `ProjectContentCatalogUtility.catalog_refreshed` 由 `GameAssetLibraryUtility` 通过 owner-bound `GFSignalUtility` 消费，并以 `replace_mount_catalog()` 原子提交新 revision；候选构建或替换失败时保留旧目录，`dispose()` 断开 owner 信号并释放 mount。
- `GFAssetCatalog` 统一暴露运行时和评审查询接口。
- `GFProjectReferenceScanner` 与 `GFAssetAttributionTools` 分别负责强引用和第三方归因证据。
- 主题内容包依赖素材库 manifest，但候选目录不得进入主题或运行时 manifest。

启动阶段的 `app/scripts/boot.gd` 位于 GF 架构之前，只能使用序列化到启动场景的最小资源；可选 Shader 或候选素材不得进入静态首帧。

## 清理与晋升

- 拒绝素材只能通过 Feature 操作文档规定的 purge 工具删除。工具必须先完成正式项目强引用扫描，再写入最小排除身份，最后删除候选副本与记录。
- 排除身份只防止同一 `source_pack_id + relative_path + SHA-256` 被重新导入，不保留已淘汰评分和备注。
- 未评审、授权未知或仍有用途价值的源包不能当作普通缓存整包删除。
- 运行时素材若无引用，仍需检查 manifest、槽位、许可证、可编辑源和测试契约后才能删除。
- 每批导入、晋升、替换或清理完成后，按 Feature 操作文档运行导入/审计，再执行安全 GUT。

## 发布约束

玩家导出必须排除：

- `source_packs/`
- `review/`
- `import_sources.json` 与本机 override
- `features/asset_library/tools/`
- `build/asset_library/`

发布只包含 manifest 登记并通过授权、引用和存在性审计的运行时素材。第三方清单与许可证摘要见 [`docs/third_party_assets.md`](./third_party_assets.md)。
