# 微信小游戏准备基线

## 当前边界

项目已建立 `GamePlatformUtility -> GFPlatformRuntime -> GamePlatformAdapter -> 平台 SDK` 单向边界。`GFPlatformRuntime` 拥有 Adapter 注册、契约路由、请求句柄、超时和生命周期序列；项目 Utility 只做 Adapter 选择与 Godot 通知桥接。`GamePlatformUtility.ready()` 只准备、注册 Adapter 并建立 owner-bound Runtime 信号，`begin_activation(scope)` 必须等待 Adapter 初始化 typed completion 成功后才开放请求，`begin_quiesce(scope)` / `dispose()` 必须先终结 pending 初始化与外层 activation，再断连和注销。业务 Feature 只能读取 `GFPlatformRuntimeContext`、查询 `GFPlatformCapabilitySet`、订阅 `GFPlatformLifecycleEvent` 或发送 `GFPlatformBridgeRequest`，不得直接读取微信全局对象或散落判断 `OS.has_feature()`。

当前 `LocalPlatformAdapter` 覆盖 Godot 桌面、移动端和 Web 的共同能力：

- 本地存储、HTTP、音频；
- 指针、触摸和安全区；
- 前后台、焦点和窗口尺寸生命周期；
- Web Compatibility 渲染器事实。

`LocalPlatformAdapter` 还把 `display_server_name` 与 `headless` 作为上下文 metadata 发布；它们是宿主事实而非 capability。Navigation 等消费者通过 `GamePlatformUtility` 读取该事实，`DisplayServer` 调用不得越出具体 Adapter。

它不宣称已经实现微信登录、开放数据域、平台/线上排行榜、支付、分享或云存档。上述能力必须由后续 `WeChatMinigamePlatformAdapter` 显式提供，并通过 `GFBridgeContractReport` 后才能被业务层启用。项目 `progress` Feature 的本地排行榜只是离线设备内能力，不属于微信平台实现。

## 自动门禁

项目侧预检：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_platform_readiness.ps1 -GodotExecutable godot -AllowEnvironmentBlockers
```

微信小游戏工具链冒烟导出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export_wechat_minigame_smoke.ps1 `
  -GodotExecutable godot
```

完整游戏正式候选导出（不包含 `platform_smoke`）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export_wechat_minigame_release.ps1 `
  -GodotExecutable godot
```

正式入口是零策略薄包装；模板、身份冻结、AppID 清洗、4 MiB 分块读取、精确白名单、包体预算、隔离验证和原子发布仍由同一导出核心拥有。二者不得复制或分叉组装事务。

脚本只接受版本字符串为 `4.7.2.stable` 或以 `4.7.2.stable.` 开头的 Godot，可执行文件版本、项目当前合约与 4.7 模板必须一致。它把已校验的社区 `godothub/godot-minigame` 4.7 模板与 Godot
`--export-pack` 产物组装为 `build/wechat_minigame_smoke/wxgame`。模板必须精确为
11,763,895 bytes、SHA-256
`AE5BDEB5BA1CE9712D4EFC35D337CB5ECBEF3AD5BFB0F7D06AE9CB662C1F2D71`；导出器会删除
示例 PCK、示例分包、示例 AppID 和 private config，将项目 PCK 改为微信允许的 `.bin`，
放入 `game_data/`，并让根加载器严格按 main→game_data→engine 串行启动。模板默认缓存在 `build/wechat_toolchain/4.7/`，也可通过
`-TemplateArchivePath` 传入同一份已校验归档。模板是社区工具链，不是 Godot 或微信官方支持的导出器。
导出开始前会冻结当前内容而不是 Git HEAD：精确纳入 `project.godot`、`export_presets.cfg`、默认音频总线、图标及其 import 描述，并递归纳入 `addons/`、`app/`、`features/`、`shared/`；`.git/`、`.godot/`、`build/`、`tests/`、非导出文档及普通 `tools/` 不进入内容快照。七个真正参与组装、验证或隔离验证依赖的文件单独记录 SHA-256。GF 的 `.gf/vendor.lock.json`、`source_commit`、`source_git_tree`、锁文件 hash 与 `addons/gf` 实际全树 hash/文件数会在导出前后重算；其中任一项、导出内容快照或工具内容在组装期间漂移都会终止。正式候选还会在冻结前验证字体 coverage manifest、子集、OFL 和对应 hash；任一证据漂移都失败关闭。

发布 stage 固定为同一候选根下的 `{wxgame/, export-report.json}`。schema 3 报告位于 `wxgame` 外，因此产物清单不会自引用；它包含除 `project.private.config.json` 本机 sidecar 外，按 ordinal path 排序的每个可发布文件 `path/bytes/sha256`、canonical manifest hash、输入快照 hash、build ID，main、engine、game_data 与 total 四组包体证据，以及 Godot、GF、模板和工具身份。替换时整候选根先备份再一次发布，任一注入或 I/O 失败都恢复旧报告和旧 `wxgame` 的同一 build ID，不会留下新报告配旧产物。

发布 stage 在替换旧候选前会在不含项目资源的临时最小 Godot 宿主中调用同一份可测试的产物验证器，重算报告绑定的完整可发布清单、包体和 build ID，并检查 JSON、loader、精确文件白名单、AppID、包内字体重映射和编辑器插件泄漏；失败时不会覆盖旧候选。DevTools 可自行生成或改写的 `project.private.config.json` 不进入包体、manifest 或 build ID，但仍须位于精确白名单中，并单独通过 JSON 与身份覆盖检查；任何其他额外文件仍会失败。完整包内检查必须由该隔离宿主执行，避免工作区中的同路径资源掩盖 PCK 缺失；在项目宿主中可复核报告绑定的结构部分：

```powershell
godot --headless --path . `
  --script res://tools/wechat_minigame_artifact_check.gd -- `
  --artifact-root build/wechat_minigame_smoke/wxgame `
  --report-path build/wechat_minigame_smoke/export-report.json
```

省略 `--report-path` 只运行便于夹具复用的旧结构模式，不构成候选身份复核。

社区模板原始 `fsUtils.localFetch()` 会用一次异步 `readFile` 读取整个 ArrayBuffer。当前候选的
WASM 与 PCK 分别位于 engine 与 game_data 分包；微信开发者工具的模拟器桥在大 PCK
响应上会进入内部 `coverRes -> atob` 错误。导出器因此复制项目自有的
`tools/wechat_minigame/chunked_file_loader.js`，只对这两个构建时精确计量的资源按 4 MiB 串行分块，
使用 `position + length` 读取并逐块验证返回类型与长度；目标资源失败、短读或超时都直接失败，不回退到
原来的整文件读取。算法回归可独立执行：

```powershell
node --test tests/tooling/wechat_chunked_file_loader.test.cjs
```

开发者工具必须启用上游模板要求的 Experimental WebAssembly。重新编译后，Console 必须依次确认 game_data 与 engine 分包入口、PCK probe、两个资源的 `[wechat-chunked-fetch] chunk`、WASM、GF 和 `Engine has started!`，并进入预期场景；缺少任一终态都不能签字。若当前输出被已打开的 DevTools 占用，可用
`-OutputPath build/wechat_minigame_smoke_candidate/wxgame` 生成独立候选工程，不能强删或覆盖被占用目录。
候选产物固定 `projectname = "2048 Chunked Toolchain Smoke"`；DevTools 项目标题必须显示该名称且模式
必须为“小游戏”。标题仍为 `wxgame` 或顶部显示“小程序模式”时，说明导入的是旧目录，不能用于验证分块修复。

报告：

- `build/platform_readiness_report.json`：GFCompatibilityPreflight 项目契约；
- `build/platform_environment_report.json`：编辑器、匹配导出模板和微信开发者工具环境。
- `build/wechat_minigame_smoke/export-report.json`：与同根 `wxgame/` 原子发布的完整可发布产物 manifest（不含本机 private sidecar）、输入/GF/Godot/工具身份、build ID、主包、engine、game_data 与总包字节数和预算结论。
- `build/wechat_minigame_release_candidate/export-report.json`：完整游戏候选的同等证据，并额外记录正式字体 coverage、子集与 OFL 身份。

CI 或正式导出不得传 `-AllowEnvironmentBlockers`。本地仅审查项目配置时才允许该开关。

Web 冒烟预设名为 `Web Compatibility Smoke`，并固定：

- custom feature：`platform_smoke,wechat_minigame_smoke`；
- `gl_compatibility` Web override；
- 单线程；
- 关闭 Web extension support；
- 启用移动纹理压缩；
- 启用虚拟键盘输入。
- `addons/wechat_minigame_smoke_export` 是为兼容既有 Godot 插件路径而保留的历史目录名；其中实现是共享的 profile-specific font export customizer，并非只服务冒烟。它在 `wechat_minigame_smoke` 下映射诊断子集，在 `wechat_minigame_release` 下映射正式字形闭包子集；两个 feature 同时出现会失败关闭，未出现二者时不定制字体。正式桌面及普通 Web 构建不启用该插件行为，继续使用完整字体，也不复制第二套导出插件。

该预设会由 Boot 路由到 `platform_smoke_test.tscn`，验证安全区、生命周期、手势、本地存储、HTTPS、音频用户手势和代表性 Shader。

完整游戏预设名为 `Web Compatibility WeChat Release`，固定 custom feature `wechat_minigame_release`，明确不包含 `platform_smoke`，因此 Boot 走正式入口场景。它复用相同 Web Compatibility、单线程、关闭 extension support、移动纹理压缩和虚拟键盘选项，并禁用 ICU；Boot/Composition Root 在 GF 架构创建与正式场景路由前调用唯一的平台启动 Utility，注册随包 en/zh Translation，Boot 不得自行读取翻译文件，业务与 UI 不得复制 locale 状态。资源定制插件会把常规/展示字体变体映射到 445,076-byte 的 `wechat_release_sans_subset.ttf`；其 SHA-256 为 `B9BD519D1A5CEE5647C976B21153726035ADC848A563F0E8AF2D612E56FD265F`，policy 为 `wechat-release-shipped-literals-v1`。该确定性子集覆盖随包运行时字符串字面量及基础 ASCII，禁用系统 fallback；`release_font_coverage.py --check`、GUT 和 Node 测试使用 FontTools 4.59.1 并共同验证源 Noto Sans SC、OFL-1.1、coverage、子集 hash 与所有声明码点。任意新增运行时文案都必须先重新生成并审查字体证据：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools/generate_wechat_release_font_subset.ps1 `
  -PythonExecutable <安装了精确 FontTools 4.59.1 的 python>
node --test tests/tooling/wechat_release_font_coverage.test.cjs
```

该子集只保证项目随包文案和可打印 ASCII；任意用户自定义 Unicode 文本不在保证范围内。生成器会在子集前后逐码点验证 Noto Sans SC 的 cmap，源字体或生成子集缺少任一声明字形都会失败关闭。当前源字体不包含曲线撤销箭头、Unicode 下标数字或 U+FFFD，因此随包文案已确定性使用 `←` / `→` 与 ASCII `F2` / `F3` / `F4` / `F5` / `L3`，且不虚假声明 U+FFFD coverage；若要恢复原符号，必须先引入可审计、随包且有许可证证据的字体资源。coverage 清单和 manifest 是导出前的构建证据，其 hash 会进入候选报告，但文件本身不随运行时打包，避免把源字体路径元数据误带入产品包。

微信工程固定横屏，把 `game_data/` 与 `engine/` 声明为普通分包，并使用保守预算：主包硬/软上限 4,000,000/3,600,000 bytes，engine 与 game_data 各自硬/软上限 20,000,000/18,000,000 bytes，总包硬/软上限 20,000,000/18,000,000 bytes。任何 `.pck`、`.html`、未压缩 `.wasm`、未知模板文件或上游示例 AppID
都会使导出失败。冒烟结果只表示 `toolchain_smoke`；完整游戏结果表示 `full_game_release_candidate`，仍不等于已签名、已上传或真机验收的生产发布，也不宣称微信登录、分享、支付、云存档或开放数据域能力已经实现。

## 环境状态与签字边界

编辑器版本、导出模板和微信开发者工具 CLI 都是工作站易变状态，只以当次 `build/platform_environment_report.json` 为准，不在长期文档中复制为“当前环境”。报告出现 blocker 时，可以继续做项目侧静态审查，但不能签字微信开发者工具或真机通过。

匹配的 Godot 导出工具链与微信开发者工具 CLI 就绪后，还必须在开发者工具和真机执行下方矩阵。`project.config.json` 默认不写入 AppID；首次导入时由开发者工具填写项目自己的小游戏 AppID，或者在本地调用导出器时传 `-AppId`。脚本会在导出开始时一次性冻结已生成输出中的有效本机 AppID 与 `project.private.config.json` 本地 IDE 偏好，后续 stage 不再读取 DevTools 正在使用的活文件；私有配置里的 `appid` / `compileType` 会被提升到已验证的公共配置或移除，禁止其覆盖产物身份和编译目标。本机 sidecar 可随候选原子发布并接受独立安全校验，但不属于可发布产物身份；`build/` 始终被 Git 忽略。GF vendor 版本与上游修复状态以 `addons/gf/plugin.cfg`、`.gf/vendor.lock.json` 和当前 vendor 源码为准；本项目不得保留临时 GF 补丁。

按微信[小游戏项目配置文件](https://developers.weixin.qq.com/minigame/dev/devtools/projectconfig.html)的当前契约，普通小游戏的 `compileType` 必须精确为 `minigame`；`miniprogram` 会把工程导入为普通小程序。固定社区模板内的历史默认值也不能覆盖导出器与产物验证器的小游戏身份。

首次验收一个新候选目录时，必须先把该绝对路径正式导入开发者工具，再打开项目窗口；不能把临时 `open` 当作导入完成。微信开发者工具 RC 2.02.2607271 在未导入候选上曾错误进入小程序配置分支并报 `pages is not iterable`，此时游戏入口尚未执行，console 也不会包含分包日志。`project_list` 必须显示该候选的 `compileType = minigame`，随后才允许将横屏主菜单与运行日志记为验收证据。

## 真机签字矩阵

每次 Godot、GF、微信导出适配器或关键 Shader 更新后，至少验证：

| 项目 | Web 浏览器 | 微信开发者工具 | Android 真机 | iOS 真机 |
| --- | --- | --- | --- | --- |
| Boot 与首屏 | 必测 | 必测 | 必测 | 必测 |
| Compatibility Shader | 必测 | 必测 | 必测 | 必测 |
| 单指拖动 / 双指缩放 | 必测 | 必测 | 必测 | 必测 |
| 音频首次用户操作解锁 | 必测 | 必测 | 必测 | 必测 |
| 本地存储重启回读 | 必测 | 必测 | 必测 | 必测 |
| 前后台恢复 | 必测 | 必测 | 必测 | 必测 |
| 安全区 / 横竖屏 / 尺寸变化 | 必测 | 必测 | 必测 | 必测 |
| HTTPS 合法域名 | 必测 | 必测 | 必测 | 必测 |
| 内存、首包与分包预算 | 记录 | 必测 | 必测 | 必测 |

微信适配器接入时必须先新增能力与 bridge contract，再实现 adapter，最后由业务消费；不得先在排行榜、成就或 UI 中调用 SDK。

## 后续实施顺序

1. 当前工作站的最终 `full_game_release_candidate` build ID 为 `749f6ff3c9ea0c396dc8a9b3e82546312b4e924533063b7cce664189ce3ef0ce`：主包 88,331 bytes、engine 8,901,332 bytes、game_data 8,916,808 bytes、总包 17,906,471 bytes，schema 3、字体闭包和全部隔离产物门禁通过；正式预览计量为 17,693,596 bytes。数字属于本次本机证据，源码、模板、AppID 或工具变化后必须重测。
2. 微信模拟器已经启动横屏中文主菜单，main→game_data→engine、PCK 探针、4 MiB chunk、WASM 与 GF 均成功；唯一告警为内容目录同步刷新 115 ms，不阻断本次启动签字。下一步完成 Android/iOS 真机矩阵、玩家手势与长时游玩、音频首次解锁、前后台恢复和重启存档；模拟器成功不得替代这些真机终态。
3. 根据产品范围先定义登录、存储、分享、支付和开放数据域中真正需要的 capability / bridge contract，再实现并注册 `WeChatMinigamePlatformAdapter`；未选择的能力不得被 UI 假定存在。
4. 将现有本地成就、图鉴与本地排行榜分别接到平台 bridge；线上排行榜和平台成就同步由平台或服务端裁决，本地 Profile 只保留离线状态与待同步事实。
5. 在每次 Godot、GF、微信模板、平台 Adapter 或关键 Shader 更新后重跑项目预检、环境检查、包体门禁和真机矩阵，不沿用历史 Web 报告代替新签字。
