# Cultivation Mode Runtime v0.3.1

## 山下集镇混合表现（内容版本仍0.3.1）

`scenes/demos/cultivation_engine_v05_town_hd2d.tscn` 使用同一 P1b catalog／包／Session／Store，仅由 `town_hd2d_mode_view` 和继承原 walker 的 `town_hd2d_walker` 替换城镇表现。SubViewport 内真实3D建筑、曲面屋顶、光影、透视摄像机与2D billboard人物由 `town_hd2d_stage.gd` 负责；UI点击先反投影回原逻辑平面，再调用原行走／到达／宿主合同，不改变养成或旅行费用。

全身四向SVG图帧、统一脚点和作者工具／哈希／许可见 `assets/art/shanxia_hd2d/source.json`。表现独立于包JSON内容指纹；旧P1b 15字段存档直接读取，应用custom userdir和save_base_dir继续保持。Web不同origin的数据仍隔离，同源升级入口使用旧18814下的 `/hd2d/` 路径，浏览器实操验收另记。实现、实际检查和入口见 [混合场景切片](../../docs/P1B_TOWN_HD2D_SLICE.md)。

## 可走城镇切片（0.3.1）

新入口 `scenes/demos/cultivation_engine_v04_town_walk.tscn` 运行 `games/town_walk_catalog.json` 的独立 `shu_town_walk` 和原 `stream_study`。P0/P1a 内容、目录、存档保持；没有旧档自动迁入。画面与完整验证见 [P1b 来源审查](../../docs/CHENGPING_P1B_SOURCE_AUDIT.md) 和 [P1b 切片](../../docs/P1B_TOWN_WALK_SLICE.md)。

可选 `files.walks` 引用包内 JSON，合同为 `{schema_version:1,scenes:{scene_id:{size:[w,h],floor:[x,y,w,h],spawn:[x,y],obstacles:[[x,y,w,h]],actor_radius:12,cell_size:20,interactions:{interaction_id:{label,position:[x,y],radius,action,repeat_action?,seen_flag?}}}}}`。坐标及尺寸为有限整数；格距须为2至100的偶数，保证格心可落在整数脚点。地图、旗标和行动引用需已登记。互动行动属于单一地图，必须 `menu:false`、无演出／事件，不允许由对话选项绕过距离。可选重访行动由已登记 `seen_flag` 选择，初次行动必须设置该旗标。

`walks_contract.gd` 负责加载和恢复合同，互动锚点须位于可走空地；`town_navigation.gd` 的膨胀障碍、精确线段检查和网格寻路按固定 Chengping 来源选择适配。Session 缓存只做几何检查的地图实例，不在每帧创建寻路网格。视图／walker 仅保存路径、朝向和待互动目标，所有持久坐标、资源与后果仍属于 Session。

- `walk_view()` 返回当前地图的 `{scene_id,definition,position,run_id,revision,enabled}`；无地图时返回空对象。
- `commit_walk_position(scene_id, position, expected_run_id, expected_revision)` 只在 `ready`、运行／修订一致、点和从上次位置到新位置的整段都可走时提交整数坐标。仅改变探索位置和 revision，不改变游戏时钟、资源、旗标、sequence、计数、札记或回执；重复当前位置不增加修订。
- `execute_walk_interaction(interaction_id, operation_id, expected_run_id, expected_revision)` 校验运行／修订、`ready`、地点、距离和遮挡后，以原行动事务一次提交。回执 `kind=walk` 带已登记的 `interaction_id`，相同操作重试只返回原回执；全局 `select_action` 无法直接执行这些非菜单行动。普通查看与问候免费，返山的 1 时辰由同一次宿主事务结算。

**状态／兼容策略：** manifest schema 仍为 1。仅声明非空 walks 的包使用 15 字段状态，新增严格的 `exploration:{schema_version:1,positions:{scene_id:[int_x,int_y]}}`；位置表必须精确对应声明地图，每点可走，路径／朝向／待互动对象不入档。原包保留精确 14 字段。SaveStore format 1 保持，包 ID、内容版本和 JSON 指纹继续隔离；加载器为旧包添加的内存空 `walks` 不参与指纹原文拼接。当前运行库已恢复旧 P0/P1a 封存测试快照，且旧三包指纹与 P1a 封存 stage 完全相同。

城内保存恢复当前位置、日期、属性和旗标；每次明确旅行重新进入城镇时，在旅行同一事务中将城镇位置重置到入口 spawn，重访旗标保留。视图保存前取消临时路径，已逐帧提交的当前位置即为安全点。对白／结果／动作占用阻止移动；`performing/event` 仍不能保存，`ready/result` 可保存。旧 14 字段档不会静默补成新包或自动成为新局，不提供跨版本迁移。

状态检查：`tests/cultivation_engine_town_walk_test.gd`。其五剑完成回调为可信控制器模拟，不代替真实动作播放、原生输入或浏览器操作。

## 有声师徒循环（0.2.2）

`scenes/demos/cultivation_engine_v02_mentor.tscn` 使用可选的 `catalog_path` 指向 `games/mentor_loop_catalog.json`，在同一内核中运行有声的 `shu_mentor_loop` 与原无声 `stream_study`。存档使用独立目录，不迁移旧档；实现与证据见[听教练剑切片](../../docs/CULTIVATION_ENGINE_MENTOR_LOOP.md)。

包内可选 `files.voices` 指向语音表JSON，内容为 `{voice_id:{speaker:character_id,text:"原文",file:"res://assets/audio/...wav"}}`。人物 `say`／`choice` 节点可用 `voice` 引用；加载器要求人物和台词逐字对应，路径使用规范小写 `.wav` 且无空／点／上级目录段。只绑定人物原文，`end`、选项标签、任务、行动回执和系统消息不朗读。资源缺失时播放器保留其余有效音频，界面给出可继续阅读的提示。

`voice_player.gd` 只加载本地音频，提供 `configure`、`play_clip`、`stop`、`set_enabled` 与审计状态。视图按内容指纹／运行／事件／节点去重播放；界面重绘与开启语音不重播当前句，后续句正常播放。取消、结算、切包、重置、读档及离场停止旧声音。

事件 `end` 节点可选 `set_flags:{flag:bool}`，在继续结束节点时由Session原子提交；此前取消不提交。仅允许结束节点使用，禁止写入支线／调查保留旗标。存档仍为原14字段，兼容性仍由内容指纹检查。本片直接消费内容事件图，不加载独立对照试样的剧情插件。

## 物件支线切片（0.2.1）

当前入口为`scenes/demos/cultivation_engine_v02_tea.tscn`；独立用户目录`shu-cultivation-engine-v02-tea`，存档子目录`user://cultivation_engine_v02_tea`。下方五剑说明保留为第一片基线，8807构建及其旧存档保持；本片不迁移旧存档。

可选`files.quests`登记支线场景、允许行动、返回地点和有序阶段。`quest_runtime.gd`验证数据并处理阶段／整条完成门禁，旗标仍只在Session待提交副本中修改。`enter_quest/return_quest`行动进入或返回；最后阶段须显式`terminal=true`才构成整条终点。本片A/B没有终点，双杯2/2后保留剑坪，提示后续内容未接入。当前只支持正向布尔阶段条件，不含文书／短回忆演出节点。

场景`objects`提供物件ID、所属支线／阶段、图像／裁切区域、0–1热点和锚点、查看行动、已阅旗标及专属行动。场景／物件ID允许点分段，其余稳定键沿用小写下划线。每物件使用独立行动，普通查看免费且只登记一次，重看只读描述。物件行动不在全局菜单重复出现。

`quest_view()`返回当前支线与阶段；`available_objects()`返回可用物件及带资格／消耗的专属行动。`inspect_object(object_id, operation_id, expected_run_id, expected_revision)`直接查看，`execute_object_action(object_id, action_id, operation_id, expected_run_id, expected_revision)`经上下文和资源检查后一次结算。相同操作只可重读相同物件／行动回执。`kind=object`回执和结果带`object_id`并严格验证；返回的description／repeat属于临时API装饰，不存入回执。原14字段状态结构保持，支线进度、已阅与一次行为由旗标／计数／回执保存。

选中物件和浮层为临时界面状态。关闭、Escape和阶段结束不释放已接受的支线；支线内普通行为直接回到安全ready，可保存后刷新。接受前委托对话可取消，仍不允许在普通对话中存档。旧正式版完整Tea、环境及编辑器未据此同时迁移。

当前检查入口为`tests/cultivation_engine_quest_test.gd`和`tests/cultivation_engine_quest_render.gd`，基础／五剑回归继续保留。构建工具默认生成本片；macOS同卷可选`--reuse-stage <既有stage>`逐哈希克隆相同源／可重建导入数据，不复制编辑器状态，Godot仍导入变更资源。完整Tea源JSON含后期剧情，不作为本片运行依赖复制。

Godot 4.7.2 / GDScript / Compatibility；当前独立入口为 `scenes/demos/cultivation_engine_v02.tscn`。这是运行库，未包含EditorPlugin。五套获批剑法通过内容包接入当前循环；旧正式蜀山仍使用其原宿主，完整Tea和环境迁移属于后续范围。

| 文件 | 职责 |
| --- | --- |
| `pack_loader.gd` | 读取 manifest 和五份数据，检查类型、范围、引用、图像资源及无环剧情图；成功后返回带内容指纹的 pack |
| `session.gd` | 唯一的每局权威状态、条件、原子行动、真实回执、对白选择与安全恢复 |
| `save_store.gd` | 每包两槽本机存档、完整性检查、版本匹配与显式恢复提醒 |
| `mode_view.gd` | 通用内容库、场景／人物、行动、对话、结果、目标和札记；读取数据，不结算资源 |
| `motion_assets.gd` | 检查数据化清单与接地锚点，扣费前载入待机／所选片段及完整图集区域 |
| `atlas_actor.gd` | 保持完整格与锚点，待机／回中性／动作／停留的表现时钟和完成通知 |

包目录和素材来源见[内容包说明](../../games/README.md)，当前范围与分层验证见[v0.2动作切片](../../docs/CULTIVATION_ENGINE_V02_SWORD_SLICE.md)，基础循环来源见[v0.1切片](../../docs/CULTIVATION_ENGINE_V0_SLICE.md)。

## 使用入口

```gdscript
const Loader = preload("res://addons/cultivation_mode/pack_loader.gd")
const Session = preload("res://addons/cultivation_mode/session.gd")
const Saves = preload("res://addons/cultivation_mode/save_store.gd")

var loaded: Dictionary = Loader.new().load_pack("res://games/<game_id>/game.json")
# 检查 loaded.ok；失败时呈现 loaded.errors，保留原有效 session。
var session = Session.new()
session.configure(loaded.pack)
var result: Dictionary = session.select_action("<activity_id>")
# 结果来自实际结算。完成结果阅读后：session.acknowledge_result()。
```

`load_pack()` 返回 `{ok, pack, errors}`；`validate(pack)` 为不激活内容的完整检查。运行库不引用某个包名、角色名、剧情名或专属属性键。

`EngineSession` 提供 `configure`、`start_new`、`snapshot`、`available_actions`、`select_action`、`event_view`、`continue_event`、`choose`、`cancel_event`、`acknowledge_result`、`can_save`、`restore`。消费者用快照显示状态，不直接修改 `state`。选择按钮绑定绘制时的运行／事件／节点／序列／选项操作标识，重复回调读取原回执，不继续推进另一个节点。

动画行动在`select_action`内完成资源预检与唯一结算后进入`performing`，`pending_presentation()`提供已预检资源及真实回执的临时副本。当前播放器完成中性回位且停止后，控制器调用`finish_presentation(run_id,operation_id)`匹配身份并进入结果，不再次改变数值、次数或回执。该本地协议由可信控制器调用，状态单测中的直接完成不代表真实动画已播放。重开局使旧身份失效；加载和UI上下文切换在播放期锁定。

## 当前数据合同

manifest 的 `schema_version=1`，包含 `id/version/title/subtitle/description/initial_scene/initial_flags/theme`；`files` 引用包内 `rules/characters/scenes/actions/events` 五份 JSON。内容包入口是 `res://games/<game_id>/game.json`，由 `games/catalog.json` 登记。示例以实际两包数据为准。

- `rules`：时段数组、起始日期与时段；任意稳定属性 ID、显示名、初始值／上下限；成长目标及完成旗标。
- `characters`：姓名、角色和真实立绘资源。空立绘有意使用文字人物卡。
- `scenes`：背景、人物槽位和在场名单；可选背景 `layers`、前景 `foreground` 与人物图集 `texture/region`。人物槽位与前景位置使用0–1逻辑比例；透明边界在运行时裁切，保留源文件。
- `actions`：可用场景、菜单可见性、时长、成本／收益、条件、设置旗标、一次性完成键、可消费加成、事件与目的地引用。成本先检查，所有修改和回执一次提交；收益受上限限制，结果显示实际变化。
- `events`：`say/choice/end` 无环图。条件支持属性最低值和布尔旗标；选择可执行已登记的非菜单行动。每个选择节点包含无条件无代价的离开选项。数据不执行脚本。事件取消保留已提交效果；本版普通事件均可结束后继续养成。
- 可选`files.motions`：注册`{character,idle,clips,settle_seconds,hold_seconds}`；每个`clips`项含`manifest/phases`，阶段为递增的`start_frame/label`。清单沿用版本1的图集帧、帧率、格尺寸和`anchor_resized_px`。待机／动作须有相同格尺寸及锚点，整个动作使用同一锚点，不逐帧裁切。`scenes.actors[].motion`绑定人物，`actions[].presentation`声明`motion/clip`；动画行动须为不切场景／不开事件的菜单行动，并在所有可用场景放有对应人物。`show_count`可显示稳定行动ID的累计次数。

新增普通内容仅变更包内数据／素材和 catalog。全新玩法须扩充能力及验收；P1b 的可选 walks 能力见上文；本版没有自动美术生成、战斗或完整多阶段支线运行器。原始主／支线归档规则不变。

## 状态与存档

一局状态含运行ID、操作序列与修订、日期／时段／地点、属性、旗标、行动计数、回执、阶段、当前事件、最后结果和札记。仅 `ready/result` 且无未完成事件时允许保存；对白期间 UI 禁用存档。可以在已结算结果页保存，读回后只继续展示，不重做结算。

当前v0.2界面使用`user://cultivation_engine_v02/<game_id>/checkpoint_0.json`或`checkpoint_1.json`；SaveStore的底层目录可由宿主配置。新文件先在pending路径写入、flush、读回校验，再替换较旧槽；另一个最近的有效槽保留。载荷包含游戏ID、内容版本／JSON指纹和完整状态，校验和用于检查意外损坏。文件上限4MiB，写入失败明确返回错误。内容或存档版本不匹配时拒绝；本版无自动版本迁移，旧8806构建及其存档独立保留。损坏最新槽时，恢复另一有效副本并在界面显示说明。

Godot JSON 将整数读成浮点数，恢复边界先对有限整数做副本规范化，再执行完整验证；不降低回执／计数一致性要求。验证失败保持原有效 session。

Web 的 `user://` 依赖当前浏览器／站点存储。保存后刷新恢复需实际检查；浏览器清理站点数据、换地址／浏览器不视为跨设备存档。官方边界见[Godot Web 数据持久化](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#using-cookies-for-data-persistence)。

## 验证与构建

基础状态回归使用`tests/cultivation_engine_test.gd`；当前动作状态与真实窗口分别使用`tests/cultivation_engine_motion_test.gd`、`tests/cultivation_engine_motion_render.gd`。测试使用专属临时目录；不操作玩家真实存档。界面audit API仅供本机观察，没有在玩家界面添加跳进度入口。旧v0.1的静态UI脚本按其历史内容／布局读取，不能直接当作当前五动作验收。

`tools/build_cultivation_engine.py --output <existing-absolute-dir>` 将本轮资源闭包复制到新目录并生成独立 `project.godot`；原正式入口不改。输出 `build-info.json` 绑定 dirty 源哈希、两个数据包和同一份运行代码摘要。随后使用锁定 Godot 导入和导出 Web。完整当前命令及证据见试玩切片。
