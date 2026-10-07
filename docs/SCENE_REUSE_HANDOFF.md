# Shu fixed-scene production method — v1（2026-10-06）

本轮用户授权 Consolidate Shu Scene-Making Skills v1：保存“中国画固定场景＋环境变化＋生活生趣＋物品互动＋养成叙事”的制作经验。两份新 skill 与两份现有 skill 的小幅补强属于制作方法整理，不新增玩法、素材或运行框架，不开始听雨廊迁移，不提交／推送／合并／发布。此前本文件的 skill 提案由本轮授权接替；下一场景仍仅为路线。

接手依次读 README、SPEC、DECISIONS、DEVELOPMENT，再按 AGENTS routing 读取相关 skill。Godot 4.7.2 stable、GDScript、Compatibility 保持。

## 方法整理阶段的 Repository/local 事实快照

以下为方法整理阶段的核对时点：2026-10-06 读取本地 Git 与实时 GitHub API/refs，当时没有 fetch/pull 或切换工作树。随后安全保存阶段已 fetch origin/main 并创建隔离 worktree，见文末；原 local main 和工作文件保持。

| 层次 | 已核对事实 |
| --- | --- |
| 本地 HEAD | `main` / `e7fa4207c721f78103abfb04a191a61a9bf05942`，即 Clouds v1 合并；存在大量 dirty/untracked Tea 与后山内容，保留原样 |
| 已在 main | 实时远端 `89e43692deaacf9ca66fb39c3a91a8ea0f437b30`；[PR #3 后山橘猫](https://github.com/jggagi/shu/pull/3) 和 [PR #4 Tea](https://github.com/jggagi/shu/pull/4) 均 MERGED，不再是 draft |
| 功能分支归档 | `codex/back-mountain-orange-cat-v2` 为 `ecf40067ee9a7b8a408befcb71e8bd1ea4c6cea7`；Tea 分支 `codex/tea-full-past-scenes` 为 `973c4b2eddfb246000ddfe47e3f0e1f3389337f2`；当前 checkout 不是这些功能分支 |
| 本地/远端差异 | 对实时 main 完整 Git tree 做 blob 哈希比较：45 个选定 Tea 源码/数据/测试/美术文件中 44 个一致；14 个选定后山模块与环境/生趣数据文件全部一致。唯一 Tea 差异是本地 provenance 的 memory 说明仍写 D032，远端已改 D033/D034/D037；完整运行正文一致。不是本地独有的新阶段 |
| 本轮仅本地 | 新 skills 与本轮文档修订尚未 commit/push；原有 dirty/untracked 不等于从未归档，不能重复全量提交 |
| 实现与玩家认可 | A/B、C、Clouds、晴天太阳、水彩橘猫分别有记录的试玩认可；完整 Tea 与最新过去画面仍待拍板，不能以方向认可、自动检查或 merge 代替 |
| 尚未实施的提案 | Tingyu Corridor 对两个 presenter 的接入、`shu_scene_runtime` addon、通用 narrative player、通用 quest/state runtime |

准确说法是 **local working state ahead of checked-out HEAD**；被检查的 Tea 功能已经进入 remote canonical main，不能再笼统声称本地实现领先远端。缓存 origin/main 在起点为 `07bd2ee`，不能替代实时查询。

本轮未核对线上部署页面或重建游戏。README/交接记录线上根入口为 A/B 0.1.4、后山为 Clouds v1；这是先前部署记录，源码合并不证明线上已更新。

## Tea 校准依据与验收层次

`demo_state.gd` 的 `view_tea_c`、`advance_tea_story`、`read_tea_story`、`turn_tea_story`、`fill_tea_cup` 与 `can_return_from_tea`，加上 `main.gd` 的调用路径和 `tea-full-source.json`，已连接 C–I 到真实双杯终点。没有在这些路径发现未接通的后续剧情段。原 binding 的“C–I/end 未实现”“终点仅 fixture”已过时。

`tea_stage_complete` 收齐 A/B 双杯，`tea_c_complete` 收齐生活物件/账册，`story_stage_complete()` 管后续段落；只有终点按序添两杯并经过宿主停顿才置 `tea_quest_complete`，之后允许返回养成。关浮层/回忆、歇息与中间阶段完成仍留在支线。`TeaMemoryScene` 实际存在、由 main 实例化，是 Tea 专用的过去场景表现。

已检查既有日志：完整宿主 153、回忆专项 619、完整 UI 2257、原生 UI 2359 项，均 0 失败；[过去片段验证](TEA_PAST_ALL_VALIDATION.md)记录 Web/Windows 导出与真实 Web 完整玩家流程。[归档复核](TEA_GITHUB_HANDOFF.md)记录隔离副本检查。**本轮没有重新运行这些游戏检查。** Windows 实机、移动端、声音与长时运行未验证；完整体验及新画面待用户验收。来源与历史原稿保持，当前工作入口见 [TEA_HANDOFF](TEA_HANDOFF.md)。

## Skill routing 与职责

| Skill | 制作职责 |
| --- | --- |
| [game-painted-scene-build](../.agents/skills/game-painted-scene-build/SKILL.md) | 从实际构图出发，制作分层、时辰/天气和克制环境动态，以 Static/Dynamic 与真实 Render QA 判断可见收益 |
| [game-ambient-life-build](../.agents/skills/game-ambient-life-build/SKILL.md) | 按场景能力安排低频生命、落点、天气门槛、注意力退让与确定性 QA，让世界安静地自己发生事情 |
| [game-art](../.agents/skills/game-art/SKILL.md) | Reference、raster/透明姿态、crop/contact anchor metadata 和 provenance；素材须在真实场景校准，运行 hitbox 由 adapter 负责 |
| [game-cultivation-build](../.agents/skills/game-cultivation-build/SKILL.md) | 养成状态、活动、人物、Object → Action → Narrative、一次结算、阶段/整条门槛与返回上下文；环境/生趣只观察 |

先做出玩家肉眼能感知的变化，再考虑技术复杂度。Lighting v1 的技术检查通过却被用户认为“变化不大”（D028），是判断反例；只有明确可见收益才采用复杂 realtime lighting，不是永远禁止它。先用第二个真实场景验证复用，再命名和抽取运行时 abstraction。

## Skill / runtime / scene adapter / gameplay state

Skill 保存 Agent 怎么做、怎么判断好坏及怎么验收；例如云影必须肉眼可感知。Runtime 是游戏执行的参数合成/过渡/调度；scene adapter 连接具体图层、路径、材质、落脚点与热点；gameplay state 是时间、精力、修为和任务进度的唯一事实来源。Skill 不复制 GDScript、不维护第二份实现、不随包提供当前 shu 类。

| 代码 | 当前分类与边界 | 未来提取门槛 |
| --- | --- | --- |
| [EnvironmentPresenter](../scripts/environment_presenter.gd) | Already reusable shu module：不持场景节点的时辰/天气参数与过渡；Tingyu adopter 已随 PR #6 完成，presenter 源码保持不变 | 保持 module；未来若第三场景实际暴露缺口再评估 data 边界，不先做 enum registry |
| [AmbientLifePresenter](../scripts/ambient_life_presenter.gd) | Already reusable shu module：固定 seed、机会/冷却、天气/capability/busy/动静调度；Back Mountain 已接入，Tingyu 第二 adapter 本地完成、待用户试玩验收，presenter 源码保持不变 | 玩家认可后才讨论纯 extraction；这轮没有 addon，也不先建 ECS |
| [InteractiveSceneObject](../scripts/interactive_scene_object.gd) | Reusable behavior contract with shu-specific presentation：发稳定 object intent，仍含“查看/已阅”、颜色与 inline shader | Scene object interaction 候选；第二真实 object-interaction 使用后再判断 theme/text 分离 |
| [SceneObjectPopover](../scripts/scene_object_popover.gd) | 可复用 shu 的局部 object/action/session 行为；paper-frame-v2.png、颜色、成本/已完成文案仍特定于 shu，非完全 theme-agnostic | 与物件行为一起评估，不能因 A/B 与 Tea 旧院共用就声称完成跨场景主题验收 |
| [TeaMemoryScene](../scripts/tea_memory_scene.gd) | Still story-specific：Tea IDs、人物称呼、固定布局/资源、翻页/hold/close 意图；宿主掌握进度 | 第四候选 NarrativeSequence；第二个不同叙事用例实际需要 picture/page sequence、dialogue、hold、close/return 后再抽 |
| [后山 Environment adapter](../scripts/back_mountain_environment.gd)、[Ambient adapter](../scripts/back_mountain_ambient_life.gd)、[controller](../scripts/back_mountain_training.gd)、[Tingyu ambient adapter](../scripts/tingyu_ambient_life.gd) | Still scene-specific：节点、遮罩、路径/落点、姿态、点击坐标与场景编排；仅不依赖坐标的猫 idle pose 由小型 helper 共用 | 保留场景边界；第二 adopter 不复制整个后山控制器，不创建通用 scene-query 系统 |
| `demo_state.gd` / `main.gd` 的 tea_* | Project/story-specific semantics；DemoState 为 gameplay authority，main 管表现/占用 | 最后才考虑 Generic quest/state runtime，需要另一条真实支线证明共同合同 |

Environment/Ambient presentation observers 可读取 time/weather/busy，不能自行修改 energy/time/quest。后山小雨无 sheltered 猫落点，所以猫隐藏；测试中的遮雨 marker 不是生产场景。猫属于 Place Life，窗台/院落/廊下等位置要由实际场景能力决定。

## Tingyu Corridor — Second Adopter 路线（历史）

**以下为实现前的 acceptance 路线记录。** 后续已先完成 EnvironmentPresenter 的 PR #6 adopter，再进行 AmbientLifePresenter 的本地第二切片；最新状态见本 handoff 后文。该路线原本提出用听雨廊验证真实 scene adapter boundary，并保留已有养成与 Tea 规则。

- 同一 EnvironmentPresenter 的时辰 profile 能否服务听雨廊构图；clear/cloudy/light_rain 接入后，无需看标签能区分，平滑过渡、Static/Dynamic 和 UI 不受染色成立。
- 实际画面能力允许时，大橘晴天在院落/窗台/廊下合理出现，小雨优先 sheltered spot；没有相应落点就不启用，不把后山岩石坐标硬搬过来。
- 师傅对白、物品阅读和修炼演出期间，Ambient Life 抑制新抢眼事件，已有生命安静退让；事件固定 seed 可复查，自然低密度仍须真实试玩。
- 对照前后完整 gameplay state，环境切换/猫互动不改变精力、养成时间、修为或任务进度；原行动、师傅选择与重置仍可用。

只有 **Back Mountain + Tingyu Corridor** 两个真实场景共同使用同一代码，并完成实际试玩，才考虑 `addons/shu_scene_runtime/`；届时只移动真正共用的代码。当前没有该 addon，本轮不创建。候选顺序：EnvironmentPresenter → AmbientLifePresenter → scene object interaction（第二真实物品用例后）→ NarrativeSequence（第二不同叙事用例后）→ generic quest/state runtime。顺序是候选，不是实施授权。

## 方法整理阶段的验证范围

实际执行：四份 skill 的 skill-creator `quick_validate.py` 全部通过；cultivation `validate_package.py --repo` 通过（14 个引用、6 个事件节点、10 个说明性 Tea 阶段、2 个物品及固定历史来源）。另检四份 YAML/name/description、新 skill 无主机绝对路径/复制 GDScript，以及本轮文档/skills 的 129 个本地 Markdown 引用，均通过；`git diff --check` 通过。

系统 `python3` 缺 PyYAML，quick validator 首次未启动；复用已有 `python` 环境后四份均通过，没有安装依赖或改环境。起点 SHA256 对照确认其他 251 个文件未变，本轮仅改 12 个 skill/文档文件；原始游戏源码/数据/美术/已有验证资料保留。未运行 Godot 全量回归、render suite、构建或新玩家试玩；历史游戏日志与本轮文档检查分开。


## 安全保存与 PR 边界（2026-10-06）

用户随后明确授权安全快照、最新 origin/main 上的隔离分支、commit/push 和针对 main 的 PR；不授权 merge 或同步原 local main。此授权接替上文方法制作轮的“本轮不提交／推送”，保留前述快照和检查为历史证据。

保存基线 `89e43692deaacf9ca66fb39c3a91a8ea0f437b30`，分支 `codex/shu-scene-skills-v1`。仅带入 12 个 skill/文档改动及后山归档追记，共 13 文件；排序与 Tea provenance 保持远端版本，runtime/素材/本机产物不进入新 diff。原 checkout 仍保留 `main/e7fa420` 及全部并行文件；等待 PR 合并后再单独处理同步。安全快照仅在原 checkout `.local/safety/scene-skills-20261006T143032Z/`，含 263 个 tracked/untracked 文件、校验 manifest、原索引和 diff；恢复到新空目录核对，不覆盖当前文件。忽略的 `.local/.godot/art/work` 内容仍在原处，未提交或删除。

本次隔离保存复核：四份 quick validation、cultivation package、136 个本地引用及 staged diff 检查通过；与安全快照比较，原 checkout 的 263 个文件、HEAD 和索引保持。未执行游戏回归或构建。


## Second Adopter 第一切片接手状态（2026-10-06）

后续用户已授权并开始 Tingyu Corridor 时辰／天气本地切片，接替上文“下一路线／本轮不实现”的历史阶段边界；范围仅 EnvironmentPresenter，不接 AmbientLifePresenter／猫。最新基线 `7f34a53`，独立 `codex/tingyu-environment-v1`，真实检查与下一试玩点见 [TINGYU_ENVIRONMENT_SLICE](TINGYU_ENVIRONMENT_SLICE.md)。共用 presenter 保持原模块，adapter 继续保留听雨廊实际坐标与遮罩；尚未达到用户试玩认可及 addon 提取门槛。本轮无 commit/push/PR/merge/部署。


Second Adopter交付授权更新（2026-10-06）：用户已要求创建PR并merge，授权当前时辰／天气切片的commit/push和main PR合并，接替上一节本轮不提交的历史边界；不部署、不更新原local main、不扩下一切片。当前实现与验证见TINGYU_ENVIRONMENT_SLICE，用户视觉反馈及addon提取门槛继续独立。


## AmbientLifePresenter 第二 adopter 本地切片（2026-10-06）

EnvironmentPresenter：Tingyu 第二 adopter 已通过 PR #6。AmbientLifePresenter：Tingyu adapter 已在最新 `origin/main` `0589f5e` 上本地实现，仍待用户试玩认可。工作位于隔离 `codex/tingyu-ambient-life-v1` worktree；原 `/Users/guoq/Developer/shu` checkout 的 HEAD、分支与工作状态保持，本轮未 commit/push/PR/merge/部署。

AmbientLifePresenter 源文件不变。Tingyu 仅接 Birds + Cat，通过场景 `BirdLane`、两个 `CatSpot_*` 与薄 adapter 决定路径、脚点和天气选点；squirrel/fish 未启用。`foreground_attention_busy` 汇总训练演出、师傅对白/选择等待和 Tea 活跃态。审核修订后，露天猫遇雨原地淡出；Static 隐去飞鸟并冻结猫姿态、当前淡出透明度，Dynamic 连续恢复。当前 seed 的无 Busy 默认多云模拟首次猫约 51 秒，后续保持低频。Environment 与 Ambient observer 均不改 DemoState。

共用姿态逻辑 `scripts/ambient_cat_motion.gd` 被 Back Mountain 与 Tingyu adapters 调用；几何、事件位置和层级仍由各场景 adapter 决定。切片详情、自动 suite、真实 Compatibility 截图与人工审阅见 [TINGYU_AMBIENT_LIFE_SLICE](TINGYU_AMBIENT_LIFE_SLICE.md)。用户试玩仍是唯一待完成 acceptance；认可后才另行讨论纯 extraction，本地 `addons/shu_scene_runtime/` 仍未创建。

### 听雨廊后续：一阵风经过

用户选择留在听雨廊继续提高生动感。当前切片已在 `weather.gd` 接入平静—阵风—回落、宿主 Busy 门与静态冻结；竹叶及一个原画帘穗响应同一次风，读现有天气强度，不改玩法。实际窗口预览已审阅，新表现待试玩。流程使用现有 painted-scene skill，无需更新 skill 或生成新美术。见 [阵风切片](TINGYU_WIND_SLICE.md)。

### 听雨廊后续：檐下落滴

阵风初版获用户“很好”反馈后保留，用户同意继续做雨中稀疏檐滴与雨后有限余水。当前 `weather.gd` 读取天气积水并使用现有 elapsed，三处锚点和时间参数由 Tingyu profile 管理；新落滴 shader 不自行计时。实际窗口预览已人工查看，新的落滴表现待玩家验收。见 [檐滴切片](TINGYU_EAVE_DRIPS_SLICE.md)。

### 听雨廊后续：黄昏灯火

檐滴获用户“很好”反馈后保留。用户同意黄昏灯火切片，当前 weather adapter 读实际六时辰、渐变灯火强度并对原画灯罩／木面及猫加局部暖色；共用 EnvironmentPresenter 不变。实际窗口已人工审阅白天／黄昏、雨天、Static／Dynamic、师傅对白与 Reset，灯火待玩家认可。此轮未运行自动测试，历史 suite 不覆盖此最新版本。见 [灯火切片](TINGYU_LANTERN_SLICE.md)。

### 听雨廊后续：雨声与檐滴

灯火获用户“好”反馈后保留，用户同意环境声音 v1。独立 Tingyu 音频 adapter 已接真实雨量、檐滴 release／既有 elapsed、Busy 与场景可见性，提供初始关闭的声音按钮和音量滑条。素材为可复现原创合成小样，尚待玩家听感认可；没有扩共用 presenter／addon。真实引擎混音与窗口、单线程 Web 操作范围见 [声音切片](TINGYU_AUDIO_SLICE.md)。

### 听雨廊整体规划（2026-10-07）

用户要求一次规划全场景 improvement。已核对当前听雨廊实际代码、素材与玩家反馈，新增 [完整改进规划 v1](TINGYU_IMPROVEMENT_PLAN.md)：画面与节奏统一 → 师徒与廊内生活 → 窗外天气与声场 → 轻交互与完整收尾。茶气方向已获「可以」，新增人物姿态、摸猫、物件查看和文案均列为规划提案，尚未实现或视为逐项批准。当前声音仍待主观试听认可。该轮只有规划文档与只读核对，没有构建／启动／测试或 runtime／skill 修改，亦无 Git 交付。


## 最新听雨廊实施入口（2026-10-07）

用户已授权 [完整计划](TINGYU_IMPROVEMENT_PLAN.md) A–D。当前 [完整候选记录](TINGYU_COMPLETE_SLICE.md) 管实际状态；环境、交互与声音已接入，AR1/AR2 新 PNG 因 Qwen 未配置而待生成。使用现有 skills，方法文件未修改。不要把 optional pose fallback 或按钮接入当成新姿态已完成。
