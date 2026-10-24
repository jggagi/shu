# P1b：承平城镇来源审查与选择性适配

客户端日期：2026-10-24，America/Los_Angeles。本记录覆盖来源审查及已适配的导航模块；完整宿主、画面和试玩验收以本片最终切片记录为准。

## 来源与操作边界

- 主项目是 `/home/x1-lite/games/shu`，实际 `pwd`、`whoami` 为该路径和 `x1-lite`，Bash / X1 Lite Fedora 原生 Linux；开始基线 `codex/x1-shu-integration-plan` / `e1e682a72af842253e613b30efd2d1f27f662fd9`，origin `https://github.com/jggagi/shu.git`，开始工作区干净。
- 只读来源为 `/home/x1-lite/games/chengping`，`codex/vertical-slice` / **`a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`**，origin `https://github.com/jggagi/chengping.git`。审查前后均为该 HEAD、工作区干净。没有在来源运行导入、改文件、共享缓存、整仓合并或复制目录覆盖。
- 完整读取了承平 `AGENTS.md`、`CODEX_START_HERE.md`、`GAME_DESIGN_SPEC.md`、`IMPLEMENTATION_STATUS.md`、`PLAYTEST.md`、`ENVIRONMENT.md`；另读 Shu `AGENTS.md`、`README.md`、`SPEC.md`、`DECISIONS.md`、`DEVELOPMENT.md`、整合规划、X1 开发入口、P1a 记录和 P1b 交接。
- 来源文档中的 Windows / WSL 位置是承平自身职责记录；本片遵从用户明确要求，在 X1 原生 Linux 的 Shu 工作副本实施。Mac mini 资料保留，承平保持独立来源。

## 实际审查的来源文件

所有来源路径均相对于上述固定承平提交。SHA256 是该本地固定提交中的原文件字节，不是新 Shu 文件的哈希。

| 来源文件 | SHA256 | 审查用途 |
| --- | --- | --- |
| `src/world/navigation.gd` | `cf7a2e5599240c907a4c814e21d64e8dd6c46ae7040d23809e96aeaffa471f65` | 四邻接 AStar、小格网、共同碰撞几何、候选接近终点和评分 |
| `src/world/location_controller.gd` | `0108fc35ef2344431ba46482359902574005a1908361863579f7f6c99765ab88` | 点击选取、路线推进、取消、临时 pending、到达后单次交互 |
| `src/world/world_state.gd` | `9f8f44cc680b2df1ce138a81a0c8cd096e404c5c28d75a9a1fe2a4155e96de61` | 集中旗标／地区状态、改变后发事件；不含地图位置或旅行成本 |
| `data/locations/locations.json` | `03448b652fcb063667f34edc8f3bf8414d2250f37844ea79c051f62f3a14566f` | 地点、spawn、建筑矩形、人物位置、出口、条件分离的数据形状 |
| `tests/navigation_tests.gd` | `a565da3f0051d6f8b6bf4ad38ac6d8d9c5346eaea53edab602ca0c043b67a641` | 绕障、障碍内地面拒绝、物件接近、全目标可达、恰一次、取消与 overlay 门禁 |
| `src/ui/boot.gd` | `790dd922dc6b195aabeaa5e3cab94723f347151e029b94d5cd1df34ceabcb907` | 宿主 panel 门禁、打开面板取消走路、消耗过的 E/Enter 按键抑制到释放 |
| `src/core/runtime.gd` | `2419981da5e188d9cf660de305e7517a9bbdf2951f8812b8abdc2830e23539e9` | 源 travel 重设位置与绑定中央 world 的边界 |
| `src/core/game_state.gd` | `c46c03c2b0fd56b0ded80a9987fcf65987244c5a4a784bfd2ec45e3cf0f3b7df` | 源位置、地点、旗标、时间的单一存储及恢复检查边界 |
| `src/core/save_manager.gd` | `edf098735bd19f7c6a7928f8712d77dedc242d86befe986ff1e527eda2adc00d` | 原子落盘、checksum、失败不替换当前局；仅参考，不导入其格式 |

相关测试另审查 `tests/art_tests.gd`、`tests/ui_smoke.gd`、`tests/stability_tests.gd`，以及 `tests/ink_gate_ui.gd`、`tests/ink_street_ui.gd`、`tests/hd2d_ui.gd` 中的真实输入、暂停、坐标和存档等式检查。来源历史通过项只作已有设计与测试参考，本轮未在承平重跑，不能算作 Shu 已通过。

## 实际选择的算法与必要改写

已落地文件：[town_navigation.gd](../addons/cultivation_mode/town_navigation.gd)。它实质适配了源 `navigation.gd`，没有加载承平 runtime 或内容注册器。

| 来源规则 | Shu 本片处理 |
| --- | --- |
| `AStarGrid2D`、禁止对角、Manhattan 启发式 | 保留四邻接 AStar 与确定性候选遍历；每条网格边再以共同几何检查，防止薄障碍恰好落在两网格点之间 |
| 固定 `Rect2(70,115,1140,535)`、20px、建筑 `grow(12)` | 改由 `configure` 接收 `floor`、`obstacles`、`cell_size`、`actor_radius`；默认20px／12px，P1b逻辑画布1280×720、地面 `[60,160,1160,490]` |
| 障碍几何同时驱动阻挡和寻路 | 保留；`blocked`、`clear_segment`、网格边与路线终点均消费相同扩张矩形，碰到障碍边界也视为阻挡 |
| 每5px采样的 `clear_segment` | 改为精确 slab 线段／矩形相交，不允许薄墙因采样间隔漏检；有限坐标和无效定义失败关闭 |
| 起点附近5×5格寻找可见可走格 | 保留；索引以 `floori` 计算，消除负坐标截零歧义 |
| 互动半径内枚举可达终点、按路径长度与微小目标距离偏好评分 | 保留；地面路线追加精确点击终点，人物／出口路线止于半径内的可走点 |
| 已在互动半径内立即返回起点 | 增加目标通路检查，避免人物在墙另一侧却立即触发；目标本体若占障碍，导航仍可接近该本体的可达一侧 |
| 单个场景临时路线，不保存路线／动画时钟 | 保留职责；宿主存持久位置，walker持临时路径／pending；存读档不重放点击或旅行 |

`CollisionGrid._compute_cost` 以精确碰撞拒绝穿墙边，独立持有几何副本，不反向持有导航／Session 引用。它仍是小场景的格网导航；没有动态人群避让、任意 polygon、跨地图导航或大型导航框架。窄于网格表达能力的通道需调整内容或格距。

接口：

```gdscript
var nav = preload("res://addons/cultivation_mode/town_navigation.gd").new()
nav.configure(definition, true) # walker：构建寻路格网
nav.configure(definition, false) # 宿主校验：仅几何，避免每帧建格网
nav.blocked(point: Vector2) -> bool
nav.clear_segment(from: Vector2, to: Vector2) -> bool
nav.cell_near(point: Vector2) -> Vector2i
nav.route(from: Vector2, target: Vector2, interaction_radius: float = 0.0) -> Array[Vector2]
```

所有坐标是场景逻辑像素的脚点。`floor`／`obstacles` 为 `[x,y,width,height]`，障碍也可直接传 `Rect2`；角色半径只扩张障碍，不缩小脚点地面范围。`configure(false)` 的路线接口返回空，只用于 `blocked`／`clear_segment`。模块本身不扣时间、精力、设置旗标或调用旅行。

## 交互、状态与存档审查结论

源 `location_controller.gd` 到达后先复制 pending、清空路径和 pending，再验证目标仍存在且足够近，然后 emit。键盘接管会取消点击目标；打开面板也须取消并设 `active=false`。恰一次来自清除临时请求和宿主门禁的组合，单靠导航本身不能防止重复结算。

源有几个不能照抄的边界：

- 源每帧直接写 `runtime.state.data.position`，本片需经 Shu Session 的明确提交合同；walker不能自行写持久属性、日期或旗标。
- 源 `WorldState` 是传入中央字典的包装器，`set_flag`／`region_set` 直接改同一个字典并发布事件；不移植这个类来另建全局状态。这里只保留「持久后果交给唯一宿主」的规则，Shu沿用原Session和行动回执。
- 源 `runtime.travel` 直接改地点、重置目标 spawn；访问资格在 `boot.interact` 另查。Shu的旅行、资格和一次费用应都经现有原子宿主，不能把UI检查当成唯一授权。
- 源只有当前地点的当前位置；每次 travel 重设 spawn，没有按地点记住所有旧坐标的能力。Shu是否按地图保存位置应以本片显式 schema 为准，不能把源行为宣称为已有地图记忆。
- 源恢复只检查位置为两项数值，没有有限／地面／碰撞校验。本片位置恢复应同时检查地图存在、有限坐标、地面与障碍，并在失败时保留现有局。
- 源到达条件按缓存的目标位置测距，动态条件仅复查 kind/id。P1b所有人物／物件／出口均固定；宿主仍须用当前内容复查距离、当前scene、phase、run与revision，不信任旧view回调。
- 源 `advance_motion` 不自行检查 `active`，由 `_process` 外层负责。Shu的程序化入口和宿主提交也需要忙碌门禁，不能只依赖画面遮罩。
- 源按键轮询可在关闭对话帧再次看见已处理的 E/Enter，后续版本用 `interaction_key_blocked` 抑制到释放。P1b以鼠标为当前范围；未来加按键应保留这项输入所有权规则。

本片所有互动目标放在可走空地；宿主仍要求人物／物件／出口通路可达，不将「目标本体占障碍」升级为已支持的通用内容合同。位置保存必须属于同一Session，与日期、属性、旗标、回执一起恢复；临时路线、pending、步态、表现时钟不进存档。内容／状态 schema、旧P0／P1a拒绝或迁移策略及新包／用户目录由本片宿主合同记录，不导入承平schema1。

## 许可与依赖

审查固定提交的全部版本化路径，没有发现项目根 `LICENSE`／`COPYING` 或给承平原创 GDScript 统一声明的开源许可。本片依据用户对其两仓明确授权的选择性适配；记录固定提交和实际改写，**不把原创代码伪称MIT或CC0**，也不把授权扩展成任何第三方素材许可。

来源中存在 `assets/GODOT-LICENSE.txt`、`GODOT-COPYRIGHT.txt`、viewport样板的MIT、Kenney Nature和Ninja Adventure的CC0文件；字体为有重命名要求的OFL子集，`assets/SOURCES.json`另有 `project-original` 图像来源。这些分别只管对应引擎／第三方／素材，不是导航代码的项目许可证。本导航适配没有复制上述贴图、字体、音频、人物、场景绘景、Godot viewport样板、剧情或地图坐标；Shu现有许可声明继续保持。

## 导航模块实际验证

固定引擎 `/opt/agent-creator/godot/bin/godot`，`4.7.2.stable.official.ed1daf0bf`。隔离小项目只消费当前 `town_navigation.gd` 的逐字节相同副本，避免触碰承平或其他运行候选。

- 15项／0失败，退出0，最终日志无 `SCRIPT ERROR`、`ERROR`、`WARNING`。
- 覆盖默认参数、相同碰撞几何、障碍段拒绝、地面精确终点、整条绕障路线、障碍内地面拒绝、阻挡物本体接近、零半径薄墙、近距离隔墙目标绕行、仅几何配置、configure重置、非有限位置和畸形定义。
- 初次新增的薄墙夹具得到13项／1失败，暴露格网节点虽可走、两点之间仍穿墙的问题；增加共同几何的边成本检查后13项／0失败，再补畸形内容两项后15项／0失败。没有改弱原失败条件。
- 最终源码SHA256：`9b20ddcc5c73d92327535e706c34960d1a61b018ad2df597cd2aa4041f30a3ca`。
- 日志与源码／夹具字节绑定收据在 `.local/qa/x1-p1b-20261024/navigation-module/navigation-check-final.log`、`navigation-check-final.json`；临时独立夹具不作为已维护的完整产品回归套件。

这些是纯导航、headless算法验证，不构成原生窗口、浏览器、人工试玩、设备听感、Windows、Steam Deck、手柄或长期性能验收。完整P1b需另验证走近、重复与busy门禁、run／revision、存读档、返回师徒／五剑及溪亭隔离。

## walker／宿主交界的独立复核

只读审查 `town_walker.gd`、`town_mode_view.gd`、`walks_contract.gd` 及Session新增接口。发现每帧将位移四舍五入会在大于420fps时完全丢失不足半像素的预算，较低刷新率也会改变速度；由主实施者修为跨帧累计预算，并保留四舍五入超支到下一帧抵扣。

修订后用固定Godot和最小fake host实际运行17项／0失败、退出0、无脚本错误或警告：60fps、144fps和1000fps各1秒均精确前进210px；1ms步长到达只触发一次；结果页拒绝新点击并冻结；外部revision变化取消旧路；退役view不能继续提交位置或新路径。fake host逐次检查run、revision、phase和共同碰撞几何，不能代替完整EngineSession集成测试。

该次消费的 `town_walker.gd` SHA256为 `54a39b35a305cb88de481724df3ade0fb7f4be887c4aa6694810a446b4360f15`，导航SHA256同上；逐字节绑定与日志保存在 `.local/qa/x1-p1b-20261024/walker-review/walker-check-final.json`、`walker-check-final.log`。后续若改这两文件，应按最终源码重新确认消费绑定，不把这一较早候选收据当作新文件的测试结果。
