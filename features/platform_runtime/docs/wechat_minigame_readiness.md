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

脚本把已校验的社区 `godothub/godot-minigame` 4.7 模板与 Godot
`--export-pack` 产物组装为 `build/wechat_minigame_smoke/wxgame`。模板必须精确为
11,763,895 bytes、SHA-256
`AE5BDEB5BA1CE9712D4EFC35D337CB5ECBEF3AD5BFB0F7D06AE9CB662C1F2D71`；导出器会删除
示例 PCK、示例分包、示例 AppID 和 private config，将项目 PCK 改为微信允许的 `.bin`，
并把 loader 绑定到同一路径。模板默认缓存在 `build/wechat_toolchain/4.7/`，也可通过
`-TemplateArchivePath` 传入同一份已校验归档。模板是社区工具链，不是 Godot 或微信官方支持的导出器。
发布 stage 在替换旧输出前会在不含项目资源的临时最小 Godot 宿主中调用同一份可测试的产物验证器，
检查 JSON、loader、精确文件白名单、AppID、包体预算、包内字体重映射和编辑器插件泄漏；失败时不会
覆盖旧输出。完整包内检查必须由该隔离宿主执行，避免工作区中的同路径资源掩盖 PCK 缺失；在项目宿主中
只能独立复核不挂载 PCK 的结构部分：

```powershell
godot --headless --path . `
  --script res://tools/wechat_minigame_artifact_check.gd -- `
  --artifact-root build/wechat_minigame_smoke/wxgame
```

社区模板原始 `fsUtils.localFetch()` 会用一次异步 `readFile` 读取整个 ArrayBuffer。当前项目的
WASM 与 PCK 分别约 8.4 MB 和 15.4 MB；微信开发者工具 2.02.2607271 的模拟器桥在大 PCK
响应上会进入内部 `coverRes -> atob` 错误。导出器因此复制项目自有的
`tools/wechat_minigame/chunked_file_loader.js`，只对这两个构建时精确计量的资源按 4 MiB 串行分块，
使用 `position + length` 读取并逐块验证返回类型与长度；目标资源失败、短读或超时都直接失败，不回退到
原来的整文件读取。算法回归可独立执行：

```powershell
node --test tests/tooling/wechat_chunked_file_loader.test.cjs
```

开发者工具必须启用上游模板要求的 Experimental WebAssembly。重新编译后，Console 应看到两个资源
合计 7 个 `[wechat-chunked-fetch] chunk`、随后 `engine init`、`Engine has started!`，并进入
Godot 平台冒烟场景；缺少任一终态都不能签字。若当前输出被已打开的 DevTools 占用，可用
`-OutputPath build/wechat_minigame_smoke_candidate/wxgame` 生成独立候选工程，不能强删或覆盖被占用目录。
候选产物固定 `projectname = "2048 Chunked Toolchain Smoke"`；DevTools 项目标题必须显示该名称且模式
必须为“小游戏”。标题仍为 `wxgame` 或顶部显示“小程序模式”时，说明导入的是旧目录，不能用于验证分块修复。

报告：

- `build/platform_readiness_report.json`：GFCompatibilityPreflight 项目契约；
- `build/platform_environment_report.json`：编辑器、匹配导出模板和微信开发者工具环境。
- `build/wechat_minigame_smoke/export-report.json`：模板身份、精确发布白名单、主包/引擎分包字节数和预算结论。

CI 或正式导出不得传 `-AllowEnvironmentBlockers`。本地仅审查项目配置时才允许该开关。

Web 冒烟预设名为 `Web Compatibility Smoke`，并固定：

- custom feature：`platform_smoke,wechat_minigame_smoke`；
- `gl_compatibility` Web override；
- 单线程；
- 关闭 Web extension support；
- 启用移动纹理压缩；
- 启用虚拟键盘输入。
- `addons/wechat_minigame_smoke_export` 仅在 `wechat_minigame_smoke` feature 下通过 Godot 资源定制接口把完整 Noto Sans SC 重映射为诊断字形子集；子集禁用系统字体 fallback，并由 GUT 从 Boot、BootRuntime、Boot 场景和平台冒烟控制器的字符串字面量逐码点验证。正式桌面、Web 和游戏构建不启用该定制，继续使用完整字体。

该预设会由 Boot 路由到 `platform_smoke_test.tscn`，验证安全区、生命周期、手势、本地存储、HTTPS、音频用户手势和代表性 Shader。

微信冒烟工程固定横屏，把 `engine/` 声明为普通分包，并使用保守的十进制预算：主包硬上限
4,000,000 bytes、总包硬上限 30,000,000 bytes；软预算分别为 3,600,000 与
27,000,000 bytes。任何 `.pck`、`.html`、未压缩 `.wasm`、未知模板文件或上游示例 AppID
都会使导出失败。该结果只表示 `toolchain_smoke`，不得冒充全游戏可发布。

## 环境状态与签字边界

编辑器版本、导出模板和微信开发者工具 CLI 都是工作站易变状态，只以当次 `build/platform_environment_report.json` 为准，不在长期文档中复制为“当前环境”。报告出现 blocker 时，可以继续做项目侧静态审查，但不能签字微信开发者工具或真机通过。

匹配的 Godot 导出工具链与微信开发者工具 CLI 就绪后，还必须在开发者工具和真机执行下方矩阵。`project.config.json` 默认不写入 AppID；首次导入时由开发者工具填写项目自己的小游戏 AppID，或者在本地调用导出器时传 `-AppId`。脚本会保留已生成输出中的有效本机 AppID 与 `project.private.config.json` 的本地 IDE 偏好，但会把私有配置里的 `appid` / `compileType` 提升到已验证的公共配置或移除，禁止其覆盖产物身份和编译目标；`build/` 始终被 Git 忽略。GF vendor 版本与上游修复状态以 `addons/gf/plugin.cfg`、`.gf/vendor.lock.json` 和当前 vendor 源码为准；本项目不得保留临时 GF 补丁。

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

1. 用固定 4.7 模板完成 `toolchain_smoke` 的开发者工具编译、模拟器启动和 Android/iOS 真机签字；当前本机 CLI 仍需用户开启服务端口或授权 clientName。
2. 为完整游戏设计字体、资源分包或远程资产策略，使正式 PCK 与引擎壳持续低于总包预算，再新增无 `platform_smoke` 的发布产物。
3. 根据产品范围先定义登录、存储、分享、支付和开放数据域中真正需要的 capability / bridge contract，再实现并注册 `WeChatMinigamePlatformAdapter`；未选择的能力不得被 UI 假定存在。
4. 将现有本地成就、图鉴与本地排行榜分别接到平台 bridge；线上排行榜和平台成就同步由平台或服务端裁决，本地 Profile 只保留离线状态与待同步事实。
5. 在每次 Godot、GF、微信模板、平台 Adapter 或关键 Shader 更新后重跑项目预检、环境检查、包体门禁和真机矩阵，不沿用历史 Web 报告代替新签字。
