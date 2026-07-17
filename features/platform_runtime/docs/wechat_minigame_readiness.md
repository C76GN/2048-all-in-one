# 微信小游戏准备基线

## 当前边界

项目已建立 `GamePlatformUtility -> GamePlatformAdapter -> 平台 SDK` 单向边界。业务 Feature 只能读取 `GFPlatformRuntimeContext`、查询 `GFPlatformCapabilitySet`、订阅 `GFPlatformLifecycleEvent` 或发送 `GFPlatformBridgeRequest`，不得直接读取微信全局对象或散落判断 `OS.has_feature()`。

当前 `LocalPlatformAdapter` 覆盖 Godot 桌面、移动端和 Web 的共同能力：

- 本地存储、HTTP、音频；
- 指针、触摸和安全区；
- 前后台、焦点和窗口尺寸生命周期；
- Web Compatibility 渲染器事实。

它不宣称已经实现微信登录、开放数据域、排行榜、支付、分享或云存档。上述能力必须由后续 `WeChatMinigamePlatformAdapter` 显式提供，并通过 `GFBridgeContractReport` 后才能被业务层启用。

## 自动门禁

项目侧预检：

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_platform_readiness.ps1 -GodotExecutable godot -AllowEnvironmentBlockers
```

报告：

- `build/platform_readiness_report.json`：GFCompatibilityPreflight 项目契约；
- `build/platform_environment_report.json`：编辑器、匹配导出模板和微信开发者工具环境。

CI 或正式导出不得传 `-AllowEnvironmentBlockers`。本地仅审查项目配置时才允许该开关。

Web 冒烟预设名为 `Web Compatibility Smoke`，并固定：

- custom feature：`platform_smoke,wechat_minigame_smoke`；
- `gl_compatibility` Web override；
- 单线程；
- 关闭 Web extension support；
- 启用移动纹理压缩；
- 启用虚拟键盘输入。

该预设会由 Boot 路由到 `platform_smoke_test.tscn`，验证安全区、生命周期、手势、本地存储、HTTPS、音频用户手势和代表性 Shader。

## 当前环境阻塞

截至 2026-07-18，本机环境审计结果：

- 项目开发编辑器：`4.7.stable.steam.5b4e0cb0f`；
- Web 验证工具链：`4.7.1.stable.official.a13da4feb` 与匹配的 `4.7.1.stable` 导出模板；
- 微信开发者工具 CLI：未检测到。

项目侧兼容契约与标准 Web 浏览器冒烟已经通过，但尚不能签字“微信开发者工具 / 微信真机通过”。下一步必须安装微信开发者工具并配置 CLI 路径，再接入微信导出适配器执行真机矩阵。

Godot 4.7.1 导出期间，当前 vendored GF 8.1.0 仍会报告 `GFExtensionExportPlugin` 未覆盖 `_get_name()`。导出产物可以生成，但正式发布要求零导出错误。框架修复已按项目规范提交 [gf-framework#9](https://github.com/C76GN/gf-framework/issues/9) 与 [gf-framework#10](https://github.com/C76GN/gf-framework/pull/10)；PR 合并发布后再更新 vendored GF，不在项目主线复制临时补丁。

## 已完成的 Web 签字

2026-07-18 使用官方 Godot 4.7.1 重新导出 `Web Compatibility Smoke`，并在 Chromium WebGL 2 环境验证：

- 构建为 Compatibility、single-threaded、no GDExtension；
- `390x844` 竖屏与 `1280x720` 横屏均使用 `720x720 + canvas_items + expand` 契约，无固定比例黑边；
- 页面控制台 `0 error / 0 warning`；
- GFStorageUtility 写入、回读与跨刷新计数通过；
- 指针手势状态可更新，半色调背景 Shader 正常渲染；
- 项目预检 `8 checks / 0 issues`，环境报告仅保留“缺少微信开发者工具 CLI”一个 blocker。

动态加载的脚本资源必须在 GF 注册表或内容包中使用内置 `Resource` 作为 `ResourceLoader` type hint，再以 `is` 收窄到业务资源类型。Godot Web 导出不能依赖编辑器侧 `class_name` 名称作为动态加载 type hint；该规则已进入自动预检和 GUT 回归测试。

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

1. 完成匹配工具链、Web 导出和微信真机冒烟签字。
2. 将棋盘数据模型升级为稀疏拓扑，支持矩形、十字形和玩家绘制。
3. 建立可缩放、平移、裁剪和安全区感知的棋盘视口。
4. 建立响应式 HUD 与输入上下文，按桌面、触摸和小游戏能力切换布局。
5. 将开发测试工具迁移到 GF 调试工作区或独立窗口。
6. 在平台 bridge 之上实现成就、排行榜与方块图鉴。
