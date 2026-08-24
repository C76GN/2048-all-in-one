# 2048 All-in-One 项目语境

这份语境固定项目在玩法组合、玩家数据与多平台交付中的领域词义，避免 Feature 之间用同一个词表达不同所有权。

## Language

**规则组合**:
决定棋盘拓扑、生成、合并与胜负语义的一组稳定规则身份。
_Avoid_: 模式配置、玩法参数

**对局会话**:
一次可玩的运行期编排边界；它冻结选定规则组合、拓扑、seed 与恢复来源，协调玩家或回放输入、场景控制器、HUD、动画和跨 Feature 结算，但不拥有 gameplay 的确定性规则算法或各 Feature 的持久化 schema。
_Avoid_: 玩法内核、关卡进度、游戏场景

**会话启动请求**:
调用方经 `GameSessionLaunchPort` 提交的最小稳定意图。新游戏携带已登记模式路径、严格拓扑值快照、seed 与来源；书签和回放只携带当前玩家目录中的稳定 UUID。只有 game_session 可以重新解析、校验、复制隔离、提交会话选择并请求场景路由。
_Avoid_: `AppConfigModel` 写入、`game_scene_path`、直接场景跳转

**数字样张**:
由一次规则组合运行产生、可供书签或回放引用的确定性棋盘状态。
_Avoid_: 截图、存档

**玩家 Profile（主 Profile）**:
一个本地账号独占、决定全部 Section 当前可见版本的完整玩家数据提交身份。
_Avoid_: 账号目录、单个存档文件

**Section**:
由一个 Feature 独占 schema 与业务状态的玩家 Profile 数据切片。
_Avoid_: 表、配置块

**Chunk Bank**:
属于同一玩家 Profile、用于完整暂存下一代大型 Section 内容的 A 或 B 块集合。
_Avoid_: 缓存目录、备份槽

**Chunk Manifest**:
玩家 Profile 内唯一声明当前可见 Chunk Bank、Section 版本、块顺序与摘要的提交记录。
_Avoid_: 文件列表、索引缓存

**可见提交点**:
主 Profile 成功持久化候选 Chunk Manifest 的 generation；在此之前，已经完整写入 inactive bank 的 chunks 仍不可见。
_Avoid_: chunk stage 完成、单块写入成功

**Outcome-unknown 栅栏**:
GF 已接纳写入但 caller 终态不能证明物理结果时，对精确主身份、Section、Profile 和 generation 保留的独占协调边界。
_Avoid_: 普通失败、自动重试标记

**Scope 提交基线**:
同一主身份与 Section 在当前进程内最近一次被精确证明已提交的 Chunk Bank 与单调 epoch；它只重定向尚未开始 stage 的 Lease，不缓存业务载荷。
_Avoid_: Provider 当前视图、磁盘缓存、猜测提交

**停放保存意图**:
Outcome-unknown 栅栏期间暂不创建新 Lease、但必须在精确结算后重新进入 debounce/flush 的 dirty generation。
_Avoid_: 失败重试循环、已持久化确认

**Materialization Lease**:
一次激活事务对已完整读取并校验的 Section 候选所持有的单次移交权；它绑定主 Profile authority 与完整 Chunk Manifest，并可在同一 load context 内暂存 provider-private 浅回滚根。
_Avoid_: 数据缓存、加载结果

**本地参考榜**:
同一设备多个本地账号的离线成绩投影，不构成线上权威证明。
_Avoid_: 排行榜、全球榜

## Relationships

- 一个**玩家 Profile**属于且只属于一个本地账号。
- 一个**玩家 Profile**包含多个 Feature-owned **Section**。
- 一个大型 **Section**在任一时刻只由一个**Chunk Manifest**指向 A/B 两套 **Chunk Bank**中的一套。
- 一个**Chunk Bank**只有在所有块写入并校验成功后，才能被新的**Chunk Manifest**设为可见。
- 完整 stage 只产生候选 **Chunk Manifest**；只有主玩家 Profile 的**可见提交点**才能切换玩家可见 bank。
- **Outcome-unknown 栅栏**解除前，同一主身份与 Section 不能开始下一次 stage，也不能把不确定的候选 Manifest 当成已提交。
- 精确提交必须先推进对应 **Scope 提交基线**，再释放 stage owner；WAITING/READY Lease 及栅栏后才创建的 Lease 都必须从该基线选择 inactive bank。
- 栅栏期间出现的 **停放保存意图**不能被 busy 终态吞掉；精确结算后若 Section 仍 dirty，必须自动重臂一次，quiesce/flush 在它收敛前不得越过。
- 一个**Materialization Lease**只能被 authority 与完整 Manifest 都匹配的 Section Provider 接管一次；错配不得消费 Lease，接管前不得改变玩家可见状态。
- 一个**规则组合**可以驱动多个**对局会话**；每个对局会话只冻结一个规则组合身份及其严格拓扑和 seed。
- 一个**对局会话**可以产生多个**数字样张**，书签和回放以稳定身份引用其确定性语义。
- 一个**会话启动请求**要么携带新游戏的严格值，要么携带一个书签/回放稳定身份，不携带 UI 当前持有的可变 Resource 或 Node。
- 只有被完整接受的**会话启动请求**才能更新下一局选择并请求进入对局场景；拒绝的请求不得改变当前会话状态或场景。
- **本地参考榜**只消费玩家 Profile 中已验证的结果，不改变任何玩家 Profile。

## Example dialogue

> **Dev:** “新的 Chunk Bank 已经全部写完，可以直接让书签页面读取吗？”
> **Domain expert:** “不可以；只有主玩家 Profile 成功提交新的 Chunk Manifest 后，该 Bank 才可见，激活时还必须通过 Materialization Lease 一次性移交完整 Section。”

> **Dev:** “书签页面已经拿到 `BookmarkData`，可以写进会话模型再跳到游戏场景吗？”
> **Domain expert:** “不可以；页面只提交书签 UUID 作为会话启动请求，由 game_session 在当前玩家目录重新解析、校验并复制后统一路由。”

## Flagged ambiguities

- “存档”曾同时指玩家 Profile、Section 和物理文件；现在分别使用**玩家 Profile**、**Section**和 GF 私有存储成员，业务代码不得依赖最后一种概念。
- “Profile”在 GF API 中也可指派生 chunk Profile；领域对话中的**玩家 Profile**只指主 Profile，chunk Profile 只表达不可独立发布的存储分片。
- “写完”必须说明是 chunk stage 完成还是到达主 Profile 的**可见提交点**；两者不能互换。
- “对局”曾同时指规则实现、运行期状态和游戏场景；现在分别使用**规则组合**、**对局会话**和对局场景，不能互换所有权。
- “启动”必须说明是提交**会话启动请求**、请求被接受，还是最终场景路由完成；页面发出请求不等于对局已经建立。
- “排行榜”曾同时表示设备内聚合与线上权威结果；设备内结果固定称为**本地参考榜**。
