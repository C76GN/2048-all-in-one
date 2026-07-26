# 微信小游戏准备基线

## 当前边界

项目已建立 `GamePlatformUtility -> GFPlatformRuntime -> GamePlatformAdapter -> 平台 SDK` 单向边界。`GFPlatformRuntime` 拥有 Adapter 注册、契约路由、请求句柄、超时和生命周期序列；项目 Utility 只做 Adapter 选择与 Godot 通知桥接。业务 Feature 只能读取 `GFPlatformRuntimeContext`、查询 `GFPlatformCapabilitySet`、订阅 `GFPlatformLifecycleEvent` 或发送 `GFPlatformBridgeRequest`，不得直接读取微信全局对象或散落判断 `OS.has_feature()`。

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

## 环境状态与签字边界

编辑器版本、导出模板和微信开发者工具 CLI 都是工作站易变状态，只以当次 `build/platform_environment_report.json` 为准，不在长期文档中复制为“当前环境”。报告出现 blocker 时，可以继续做项目侧静态审查，但不能签字微信开发者工具或真机通过。

匹配的 Godot 导出工具链与微信开发者工具 CLI 就绪后，还必须接入实际微信导出适配器并执行下方真机矩阵。GF vendor 版本与上游修复状态以 `addons/gf/plugin.cfg`、`.gf/vendor.lock.json` 和当前 vendor 源码为准；本项目不得保留临时 GF 补丁。

## 历史 Web 签字证据

以下是 2026-07-18 使用官方 Godot 4.7.1 对 `Web Compatibility Smoke` 的一次历史验证，不自动代表当前工作树或微信运行时已经签字：

- 构建为 Compatibility、single-threaded、no GDExtension；
- `390x844` 竖屏与 `1280x720` 横屏均使用 `720x720 + canvas_items + expand` 契约，无固定比例黑边；
- 页面控制台 `0 error / 0 warning`；
- GFStorageUtility 写入、回读与跨刷新计数通过；
- 指针手势状态可更新，半色调背景 Shader 正常渲染；
- 项目预检 `8 checks / 0 issues`，环境报告仅保留“缺少微信开发者工具 CLI”一个 blocker。

动态加载的脚本资源必须在 GF 注册表或内容包中使用内置 `Resource` 作为 `ResourceLoader` type hint，再以 `is` 收窄到业务资源类型。Godot Web 导出不能依赖编辑器侧 `class_name` 名称作为动态加载 type hint；该规则已进入自动预检和 GUT 回归测试。

## 已完成的项目侧准备

- 稀疏、矩形与玩家绘制拓扑已经进入统一棋盘模型，不再是微信后续任务。
- gameplay 与棋盘编辑器已具备可缩放/平移视口、安全区投影和 desktop/compact/portrait 响应式布局。
- HUD、触摸 D-pad、指针手势和抽象输入上下文已按设备能力分层。
- diagnostics 工作区由 `with_dev_tools` Feature 与独立 Window 隔离，普通玩家构建不创建该工作区。
- 本地成就、方块图鉴及其 SaveGraph section 已实现；它们尚未等同于微信开放数据域或平台同步。
- `GamePlatformAdapter` / `LocalPlatformAdapter` 已实现 Godot 本地、移动端和 Web 的共同能力投影；尚无 `WeChatMinigamePlatformAdapter`。

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

1. 准备与当前项目匹配的导出工具链、微信开发者工具 CLI 和实际微信导出适配器，完成开发者工具与真机冒烟签字。
2. 根据产品范围先定义登录、存储、分享、支付和开放数据域中真正需要的 capability / bridge contract，再实现并注册 `WeChatMinigamePlatformAdapter`；未选择的能力不得被 UI 假定存在。
3. 将现有本地成就、图鉴与未来排行榜分别接到平台 bridge；线上排行榜和平台成就同步由平台或服务端裁决，本地 SaveGraph 只保留离线状态与待同步事实。
4. 在每次 Godot、GF、微信导出适配器或关键 Shader 更新后重跑项目预检、环境检查和真机矩阵，不沿用历史 Web 报告代替新签字。
