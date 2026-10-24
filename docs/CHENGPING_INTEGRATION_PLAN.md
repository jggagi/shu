# Shu 与 Chengping 系统整合计划

客户端日期：2026-10-24，America/Los_Angeles。状态：已确认产品方向下的分期实施计划；下文新增接口、城镇案例与验收切片尚未实现。

本游戏沿用 Shu 原创人物、山中养成与现有宿主，参考 Chengping 已实现的城镇调查、证据、持久后果与空间战斗系统，形成「山中养成 → 入城办事 → 遭遇与抉择 → 返回师门」的连续体验。Chengping 是玩法系统来源，不自动引入其完整阴谋主线、司衡设定或旧人物；具体剧情另按 Shu 原创方向编写。

工作站与下一任务见 [X1 Lite 开发入口](X1_LITE_DEVELOPMENT.md)；原始交接见 [X1 Lite 交接](X1_LITE_HANDOFF.md)。产品要求以 [SPEC](SPEC.md) 为准，决定来源与执行记录分别见 [DECISIONS](DECISIONS.md)、[DEVELOPMENT](DEVELOPMENT.md)。

## 1. 事实基线

| 项目 | 已有实现／来源 | 本计划中的边界 |
| --- | --- | --- |
| Shu 源码 | 远端 `main` 基线 `391689938173e3dc9d8d59fd6d4531a13a5c7e16`，汇合 Mac 快照 `bf2afa5` 与此前远端 `7ef9ec1` | X1 后续从此基线接续；两侧历史保留。Mac 路径、预览、缓存与原始制作工程不移植为 X1 配置。 |
| 新养成宿主 | `addons/cultivation_mode/` 已有内容加载、唯一 `EngineSession`、原子结算、真实回执、动作与语音呈现、安全存读档 | 保留并扩展现有运行库；不重做 E1，不引入并行 Chengping `GameState`。 |
| 最新整合入口 | `scenes/demos/cultivation_engine_v02_mentor.tscn`，`0.2.2-mentor-loop`；听教、五剑任选、复命、歇息跨日与存档恢复已实现 | Mac 的分层验证见原切片；X1 导入、启动、输入、听感与性能需另作实机记录。 |
| 内容与存档隔离 | `games/mentor_loop_catalog.json` 运行 `shu_mentor_loop` 和 `stream_study`；同一内核、不同规则与独立存档 | 溪亭包是内核验证样例。不得为了城镇功能改写它的规则或把它称为第二款正式游戏。 |
| 旧正式流程 | F5 项目主场景仍使用旧 `DemoState`，已有听雨廊／后山往返、正式五剑、完整 Tea 与环境内容 | 与新内核入口分开。M1／M2 已有成果作为来源和回归基线，不从零重做；完整 Tea、天气／生趣尚未全部迁入新内核。 |
| 新内核物件支线 | v0.2.1 已有《归剑问天》A/B、双杯热点、免费查看、一次物件行动与阶段门禁 | A/B 不是整条结局；文书、回忆与 C–I 不因本计划而视为已迁移。 |
| Chengping 来源 | 独立仓库 `a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`，`0.3.5-alpha`；本轮盘点时工作区干净 | 已有短 Alpha 的系统与测试是移植依据；原游戏通过项不构成新 Shu 集成或 X1 验收。 |
| 工具与平台 | Godot 4.7.2 stable、GDScript、Compatibility；Web 使用同版单线程模板 | 保持版本。Mac 已有结果不代替 X1、Windows、Steam Deck、实体手柄或长期运行验收。 |

实际合同见 [运行库 API](../addons/cultivation_mode/README.md)、[内容包说明](../games/README.md)、[听教练剑整合](CULTIVATION_ENGINE_MENTOR_LOOP.md)。旧 A/B 剧情工具尚未选型且有退出问题；最新整合入口直接消费内容包事件图，不以引入这些插件作为城镇功能的前置条件。

## 2. 已确认方向与可调提案

已确认：

- Shu 为原创主项目，山中养成与师徒关系是主体；Chengping 提供城镇玩法系统。
- 有限游戏时间中的行动选择需要机会成本；培养应影响之后的调查、处理办法或战斗，而非只提高伤害数字。
- 战斗先采用轻量手动队伍回合制：玩家选择角色、移动位置、武学与目标，空间对结果有意义。自动辅助留待基本玩法成立后评估。
- 室内养成、日常互动与对白保留同系列 2D 原画；练武／战斗沿用人物模型动作的表现方向，身份、服饰与配色对应。现有练剑图集不等于可移动战斗动画已经齐备。
- 保留现有物件中心交互、证据改变理解和世界记住选择的价值；不显示善恶分数或隐藏玩家画像数值。

以下为本计划提案，需在各切片中试玩调整：首个城镇的名字与构图、往返时间、每日行动预算、人物与敌人数、格子／区域尺寸、武学范围与消耗、胜败目标及案例正文。不在规划阶段锁定完整日历、长篇主线、复杂关系树或大量战斗职业。

## 3. 按能力迁移的清单

Chengping 文件链接固定到来源提交。只选择当前切片确需的规则、数据结构或算法；每项移植记录来源路径、提交、必要改写、许可与验证。两个仓库独立保留，不复制整个目录、不合并整仓历史或共用工作树／缓存，也不复制未声明的素材依赖。

| 能力 | Shu 现有接点 | Chengping 参考来源 | 首轮处理 |
| --- | --- | --- | --- |
| 城镇地点、人物与往返 | [场景数据](../games/shu_mentor_loop/scenes.json)、[行动数据](../games/shu_mentor_loop/activities.json)、[Session](../addons/cultivation_mode/session.gd) | [world_state.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/world/world_state.gd) | 先用少量地点、可见出口与热点形成往返；自由行走不作为第一片前置。 |
| 城镇步行与点击互动 | 现有固定场景／热点视图，无自由探索角色控制 | [location_controller.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/world/location_controller.gd)、[navigation.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/world/navigation.gd) | P1 分成先往返、再适配一张可走城镇场景两片；点击人物／出口走近交互，障碍路径与逻辑位置一致。行走资源另核对，固定练剑图集不直接充当四向移动。 |
| 对话、物件与阶段 | [事件数据](../games/shu_mentor_loop/events.json)、[quest_runtime](../addons/cultivation_mode/quest_runtime.gd) | [dialogue_manager.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/dialogue/dialogue_manager.gd)、[quest_manager.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/quest/quest_manager.gd) | 复用 Shu 的已登记行动与原子结算；出现真实表达缺口才扩展内容合同，不并置第二套剧情状态机。 |
| 证据与江湖志 | 免费物件查看、旗标、札记；目前没有完整证据模型 | [evidence_manager.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/evidence/evidence_manager.gd)、[journal_model.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/evidence/journal_model.gd)、[journal_tests.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/tests/journal_tests.gd) | 设计证据来源、所见事实、人物说法、推断与尚未解决的问题；旧说法可以被新证据修正。现有札记不直接改名充当江湖志或普通任务列表。 |
| 持久后果与人物回应 | Session 旗标、行动计数、完成回执 | [world_state.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/world/world_state.gd)、[observer_profile.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/observer/observer_profile.gd) | 先完成一项可观察后果并存档。隐藏观察仅在具体剧情确需时设计，不塞进默认可见属性表，也不自动移入 Chengping 的完整观察／档案叙事。 |
| 空间队伍战斗 | 已有动作预检、表现繁忙门禁与唯一结算；尚无战斗 | [grid.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/combat/grid.gd)、[combat_controller.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/combat/combat_controller.gd)、[objectives.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/combat/objectives.gd)、[combat_tests.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/tests/combat_tests.gd) | 限定一张小场地与少量招式；移动、距离／阻挡、不同作用区域或位移至少形成可感知差别。暂不迁完整战斗 UI、资源包或全部武学。 |
| 存读档 | [save_store.gd](../addons/cultivation_mode/save_store.gd)、Session 恢复校验 | [save_manager.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/core/save_manager.gd)仅作边界参考 | 以 Shu 当前存档为基础；不导入 Chengping 存档格式或其全局 [game_state.gd](https://github.com/jggagi/chengping/blob/a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6/src/core/game_state.gd)。 |

原始主线稿仍归 `shu/trunk/`，新支线原稿归独立 `jggagi/sub`；运行包固定已选原稿版本、段落与来源哈希，不在运行时访问剧情仓库。遵循 [AGENTS](../AGENTS.md)，不迁移或改写历史原稿来配合新玩法。

## 4. 状态、内容与存档边界

- **一个权威宿主。** 新增城镇／证据／战斗能力由 EngineSession 统一接入。界面、动作播放器、地图与音频只显示或请求行动；不另扣精力、推进日期或提交剧情结果。战斗模块可以持有对局内的临时状态，持久结果仍经宿主按对局／操作身份一次提交。
- **先检查，再提交。** 保留资源预检、资格检查、运行与修订身份、真实回执及旧回调失效规则。城镇往返、调查选择、胜败结果与重试都不能重复扣费或重复发奖。
- **时间由明确行动推进。** 往返和有成本的行为在执行前显示代价；普通阅读、查看证据与阅读人物对白不因玩家停留而自动耗时。战斗如何映射游戏时间在战斗切片明确，只从一个边界结算，不让战斗动画与养成时钟同时收费。
- **不把新结构硬塞进旧字段。** 当前状态是严格校验的 14 字段结构，条件主要为属性下限与布尔旗标，事件为无环 `say/choice/end`；新证据图、隐性观察、战斗结果等需先写最小数据合同和恢复不变量。它们是待设计扩展，不是现有 API。
- **兼容性必须显式。** 当前包 manifest schema 为 1，SaveStore 按包 ID、内容版本／JSON 指纹与完整状态校验，安全 `ready/result` 才能保存；动作和交谈中禁存。增加内容或状态能力前明确包版本、schema 与指纹变化：保持兼容就证明旧档不变量；不兼容就明确拒绝或另做有测试的迁移，不静默当新局、不自动迁旧目录。
- **独立试验不覆盖旧档。** 新城镇纵切先用明确的新包／用户目录和存档子目录；只有决定接入正式包时才制定兼容方案。素材字节继续由构建清单绑定，不把纯美术变化和玩法 JSON 兼容性混为一谈。
- **扩充加载器与导出闭包。** 新能力须有引用检查、合法数据边界、缺失资源提示与恢复失败反馈；导出只带当前包所需资源。通用编辑器、大型插件框架、自动生成剧情和运行时云服务不属于本计划前置工作。

## 5. 分期与验收

每片交付可玩的完整结果，再根据反馈调整。以下列验收目标，不代表已运行或通过。

| 阶段 | 最小交付 | 完成条件 |
| --- | --- | --- |
| P0：X1 现有基线 | 在固定引擎中导入最新 main，运行已有 mentor 整合入口；保留原两个入口与存档隔离 | 记录实际身份、路径、提交与 dirty 状态；现有状态测试日志无脚本／资源错误；实际完成听教→五剑任一→复命→歇息跨日→保存重启恢复，再切溪亭验证包确认隔离。原生、Web、听感和用户反馈分别记录。 |
| P1：最小进城与返山 | P1a 先用同一 Shu Session 进入一个城镇地点并返回；P1b 再适配一张可行走的城镇场景，少量人物／物件可互动 | 地点、时间、资源、旗标连续，返回上下文正确；代价只结算一次，重复点击／取消／读档不重置进度；P1b 验证绕障、走近人物和出口、位置恢复与UI可读性。每片保持师徒、五剑与第二包可用，先不增加证据系统或战斗。 |
| P2：证据与后果小案 | 一个原创短事件、少量相互解释或冲突的线索、至少两种处理；培养影响其中一种可选办法，至少一个事件有明确的游戏时间窗口 | 江湖志区分所见与推断，查看／阅读免费；同案两条路线有可观察的城镇或师门回应；错过窗口后有可理解的变化并能继续游玩；保存恢复保留证据、选择和后果，重访不重复发奖。无需先导入整部 Chengping 故事。 |
| P3：轻量空间战斗 | 从小案触发一场手动队伍回合战斗，提供位置／目标反馈，完成后返回正确城镇上下文 | 玩家能选择队员、移动和武学／目标；至少一种站位与招式差别改变可用行动或局势；非法行动无副作用，胜败／退出边界明确，对局结果唯一提交；按明确的安全节点保存。自动辅助不在此片实现。 |
| P4：完整连续体验 | 培养选择→进城→调查／抉择→战斗→返山反馈→继续养成，形成一条短纵切 | 至少两条培养／处理路线产生不同经历或解决方法；日期与成本可解释，返回人物回应与实际经历对应；在多个安全节点保存重启，证据、后果、战斗结果和回执一致；完整 Tea 与旧包不因整合被误判为已迁移或被覆盖。 |

状态检查验证规则，真实画面与输入验证玩家流程；两者不能互相替代。每片按变更运行相关旧测试和新增能力检查，检查日志中的 `SCRIPT ERROR`／`ERROR`，同时记录实际引擎、消费源码与导出产物。平台构建、启动、实际输入、声音、用户认可及长时结果分开，不凭自动化宣称完整人工游玩。

## 6. 下一项实际任务

规划已先提交推送为 `403a254`，P0 验收记录与测试清理以 `58f56af` 归档。用户已认可 P0 试玩并授权 P1a 最小进城／返山，当前片见[P1a 任务与验证](P1A_TOWN_RETURN_SLICE.md)：同一 Session、独立内容包、听雨廊→集镇→听雨廊，原养成与存档连续。P1b 行走、P2 案件与 P3 战斗尚未开始；每程 1 时辰／不扣精力、地点名与示意美术仍待本片试玩调整。以下保留 P0 基线复现入口，当前 P1a 运行方法以其切片为准：

```sh
godot --windowed --path . res://scenes/demos/cultivation_engine_v02_mentor.tscn
godot --headless --path . --script res://tests/cultivation_engine_mentor_loop_test.gd
```

若 Godot 不在 PATH，使用核实过的工具绝对路径，不擅自升级引擎。实际试玩按 P0 行走；新机器 Web 构建使用独立 stage，不沿用 Mac 的 `--reuse-stage`。收据写入忽略的 `.local/qa/`，记录已完成与缺项，再决定 P1 的具体城镇构图、往返代价和唯一事件范围。

P1a 通过已有内容合同实现地点往返，不意味着 Chengping 行走／证据／战斗系统已经移植。用户随后授权本片提交推送，并新开任务开始实际接入，范围与起点见[P1b 交接](CHENGPING_P1B_HANDOFF.md)；没有合并 main 或公开部署。未来阶段的授权和通过结果以各次真实记录为准。
