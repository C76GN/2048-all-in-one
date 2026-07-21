# mateuszsokola/2048-in-react 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/mateuszsokola/2048-in-react) |
| 固定版本 | [`4c27093929b4293c2c873b3ed75b18671b5be6cb`](https://github.com/mateuszsokola/2048-in-react/tree/4c27093929b4293c2c873b3ed75b18671b5be6cb) |
| 提交日期 | 2026-04-07 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\mateuszsokola-2048-react` |
| 许可证 | [LICENSE](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/LICENSE)，MIT |
| 研究方式 | 2026-07-22 静态阅读；未安装依赖、未运行或启动 Next.js |

该仓库的价值是现代组件测试、稳定 tile identity 与移动节流；它也清楚暴露了常见前端 2048 陷阱：四方向 reducer 重复、全局触摸监听、任意键都 `preventDefault`、定时器未清理和非确定性生成。当前项目应吸收测试思想，不照搬 UI 事件或 reducer 结构。

## 玩法与架构

React context 包装 reducer，负责新局、移动节流、胜负与延迟生成。[context 与生成](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/context/game-context.tsx#L27-L72)、[移动后状态](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/context/game-context.tsx#L74-L137)。reducer 用 tile id 维持表现身份，但上/下/左/右四组逻辑大段重复，并用 JSON 序列化克隆状态，[reducer 状态](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/reducers/game-reducer.ts#L8-L90)、[四方向实现](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/reducers/game-reducer.ts#L92-L294)。这会使一个规则修复需要同步四处，适合反向证明统一 lane compose 的价值。

## 特效、Shader、动效与音效

无 Shader 和音效。tile 根据状态改变位置与 scale，CSS 提供位移过渡、pop 与高值 glow，[tile 表现组件](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/components/tile.tsx#L13-L38)、[样式与 glow](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/styles/tile.module.css#L1-L137)。pop 由组件定时器恢复，但未见 effect cleanup，组件卸载时可能遗留回调。延迟生成同样依靠 `setTimeout`，没有显式取消。[延迟流程](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/context/game-context.tsx#L110-L123)。

## UI/UX 与输入

棋盘固定渲染 16 个 cell，并提供键盘、触屏和胜负 overlay。[棋盘组件](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/components/board.tsx#L13-L96)。键盘 handler 对所有按键无条件 `preventDefault()`，会影响页面快捷键和辅助技术。触摸层在 `window` 注册监听、阻止默认行为且没有最小滑动阈值；零距离手势也可能按分支被解释为移动。[触摸实现](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/components/mobile-swiper.tsx#L20-L60)。

测试覆盖 reducer 四方向、组件、滑动与 context 主流程，是其明显强项；但测试固化了重复实现，而未抽象方向不变量。没有持久化、撤销/回放、规则说明、键盘焦点策略或减少动态效果设置。

## 性能、可靠性与缺失

固定 4×4 下 React 重渲染成本有限，节流可防止动画期间重复输入；但 `trailing: false` 会直接丢弃窗口内输入，应明确这是产品选择还是缺陷。生成使用 `Math.random()` 且始终生成 2，[随机位置与值](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/context/game-context.tsx#L27-L53)，既不符合经典 90/10，也不可重放。JSON clone 和方向复制都不适合大棋盘。

## 可借鉴机制（只借思想）

1. 领域 tile 持稳定 id，表现层用 id 关联移动和 pop，而不是把值当身份。
2. 对四方向建立 property/golden tests：旋转/镜像等价、质量守恒、单次合并约束、无效移动不生成。
3. 输入节流应改为项目动作队列和明确 buffering 策略，并测试快速连滑序列。
4. 手势需死区、方向锁定、目标区域和取消；只有已消费的方向键才阻止默认行为。

## 当前项目对比与 GF 映射

当前项目在确定性、持久化、可变拓扑、输入抽象和动作生命周期上更完整。值得补强的是稳定表现 identity 的契约、快速输入回归测试与 reduced-motion 行为；不要引入四方向 reducer 或 timer 驱动状态。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 稳定 tile id 与动作元数据 | gameplay/board presentation | `GFCommandHistoryUtility`、`GFActionQueueSystem` | id 属于领域，节点引用不入存档 |
| 快速输入 buffering | gameplay/input | `GFInputMappingUtility`、`GFPointerGestureUtility`、action queue | 明确丢弃/排队/合并策略 |
| 定时动画生命周期 | board presentation | action queue + `GFClock` | 不用裸 timer 改领域状态 |
| 方向不变量测试 | gameplay tests | 无需新增 GF API | 用统一 lane compose 替代复制 |
| reduced-motion 与焦点 | settings/UI | `GFUIRouterUtility`、viewport/focus utility | 只消费命中的输入 |

## 证据边界

只分析固定提交，未安装 npm 包或执行测试。MIT 允许参考；没有复制实现或样式。
