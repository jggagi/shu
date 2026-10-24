# P1b：街口走走

客户端日期：2026-10-24，America/Los_Angeles。状态：最小可走城镇已实现；最终同源检查与试玩入口记录见下文，用户体验待试玩决定。

## 可观察结果与范围

从听雨廊「下山进城」，收起回报后，在山下集镇点击石路走动。路径绕过中央摊棚和北侧铺面；点击茶摊掌柜、街口木牌或返山石阶时，先走到附近，再由同一个 EngineSession 执行互动。掌柜第一次问候和再次见面有不同旁白，存档与重访保留该旗标。返山后继续原听教、五套剑法、复命与歇息跨日。

| 玩家操作 | 规则 |
| --- | --- |
| 点击空地／重新选择去处 | 四邻接寻路；新点击取消旧临时路线。人物全身、正背左右及迈步均为原创程序绘制。 |
| 掌柜／木牌 | 走近再免费阅读，不改变日期、时辰、精力或成长。重复点击不能重放同一次到达。 |
| 明确进城／返山 | 每程暂定1时辰，不扣精力，由宿主一次结算；零精力仍能返山。 |
| 回报／对白／动作／确认面板 | 冻结走动并取消临时路线；收起后可重新点地面。 |
| 城内存档／继续 | 保存当前整数脚点及完整宿主状态；恢复不重走、不重做互动、不重复旅行收费。 |
| 再次主动下山 | 回到入口出生点；掌柜记忆等旗标仍保留。 |

本片只有一张场景、一个人物、一件木牌和一个返山出口。当前原创简绘地图、全身Q版人物、通用地点名、构图与每程一时辰是试玩候选；没有据自动检查将它们升级为用户认可。未开展 P2 证据案、P3 战斗或整部承平剧情。

## 来源与唯一状态

工作位于 X1 Lite / Fedora 原生 Linux，Bash，真实用户 `x1-lite`；Shu `/home/x1-lite/games/shu`，分支 `codex/x1-shu-integration-plan`，开始 HEAD `e1e682a72af842253e613b30efd2d1f27f662fd9`，远端同名引用一致，开始工作区干净。首次试玩交付时尚未获新 Git 提交／推送授权，候选源码当时保留为未提交修改；没有覆盖旧 main、改 Git 身份或触碰 Mac 副本。

承平 `/home/x1-lite/games/chengping` 只读固定 `codex/vertical-slice` / `a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`。真实适配的是 `navigation.gd` 的四邻接 AStar、扩张障碍、候选接近终点评分，以及 `location_controller.gd` 的临时 pending／取消／到达后单次交互规则。按 `world_state.gd` 的中央持久后果原则沿用 Shu 的 Session；没有导入 Chengping GameState。文件SHA256、许可现状、代码改写、审查范围和算法检查见[来源审查](CHENGPING_P1B_SOURCE_AUDIT.md)。来源仓库没有导入、修改或同步覆盖。

入口为 [cultivation_engine_v04_town_walk.tscn](../scenes/demos/cultivation_engine_v04_town_walk.tscn)，使用 [town_mode_view.gd](../addons/cultivation_mode/town_mode_view.gd) 扩展原视图；原山中与溪亭仍走原视图。新包 [shu_town_walk](../games/shu_town_walk/game.json) / `0.3.1`，新目录 `games/town_walk_catalog.json`，同一内核运行原 `stream_study`。继承 JSON 的固定哈希在 `source.json`，没有复制原剧情仓库或素材目录。

可选 `files.walks` / `walks.json` schema1 登记地图、障碍、spawn与互动。仅声明该能力的新包使用15字段状态，新增 `exploration:{schema_version:1,positions:{shanxia_town:[int_x,int_y]}}`。位置表须精确对应地图，脚点及每段移动都必须可走；格距要求偶数，避免整数脚点无法到达半像素格心。路线、pending、朝向和步态不入档。

`commit_walk_position` 只改变位置与revision；`execute_walk_interaction` 校验run／revision、phase、地点、距离和遮挡，调用已注册非菜单行动并发出 `kind=walk` 真实回执。重试同操作只返回原回执；原普通菜单不能绕过走近门禁。旅行在原 `_prepare_action` 一次原子提交。契约与恢复细节见[API](../addons/cultivation_mode/README.md)。

旧包继续严格14字段。SaveStore format1、旧P0／P1a／溪亭的内容指纹与 JSON 保持，当前运行库已实际恢复三份此前封存的完整测试快照。新包应用目录 `shu-cultivation-engine-town-walk`、存档目录 `user://cultivation_engine_town_walk` 独立，不自动迁移旧档。两个轮换检查点沿用原保存语义，不是承平的五个人工槽。

旧室内原画的来源 prompt 明写 `waist-up`；固定练剑图集只有固定脚点和单镜头动作，没有方向注册。本片未冒用它们。新全身角色与地图直接在 `town_walker.gd` 绘制，正／背／左／右脸与发型可区分、双腿随实际距离迈步，独立绘制脚底接触影。没有复制承平人物、城镇绘景或商业游戏素材，也没有新云端生成、采购或配音。字体继续使用原固定来源Noto Serif SC／OFL与项目重命名子集，来源和派生哈希在 `assets/fonts/source-cultivation-engine.json`。

## 验证与交付

固定引擎 `/opt/agent-creator/godot/bin/godot`，`4.7.2.stable.official.ed1daf0bf`，GDScript / Compatibility。独立构建根 `.local/build/x1-p1b-20261024/`，最终证据根 `.local/qa/x1-p1b-20261024/`。候选历史在 `.local/qa/x1-p1b-qa-20261024/`、宿主专项在 `.local/qa/p1b-host-contract/`；历史候选通过项不冒充最终字节验证。

最终候选 `/home/x1-lite/games/shu/.local/build/x1-p1b-20261024/stage-998cc78b3722`，184个消费文件逐项与源码／stage／清单SHA256一致；共享runtime digest `6b46db876c8cf13ba5097517a8a20c45cdc56d52c92b23b3cd129b5e9be936e4`。源码仍为 e1e682a＋明确dirty候选，不冒称已提交版本。构建器仍收集全部games JSON及依赖，不声称只导出当前两个包。

| 检查 | 最终结果／证据 |
| --- | --- |
| 导入 | 最终退出0，无错误／警告；`import-final.json`。首次全量资源导入完成后进程SIGABRT退出-6，日志没有错误原因；保留`import-attempt-1-abort.*`。同一stage明确`--editor --quit`复核退出0，后续所有状态／窗口／导出均通过，不隐去首次异常。 |
| 8组状态 | **1065项／0失败**（原7组941＋P1b124），全部退出0、无脚本错误／错误／警告；`state-final/state-results.json`。汇总器起初只识别一种旧测试输出格式，已从原日志补识别31/31与207/207格式，没有重复执行或放宽测试。 |
| 编辑器脚本驱动原生窗口 | 960×600、1152×720各112项／10图／0失败，共**224项／20图**；`native-final-<size>/`。实际注入鼠标、绕障脚点、四向、走近互动、重复与busy、完整位置恢复、返山后真实练剑／复命及溪亭隔离均通过。 |
| 导出PCK外部驱动 | 固定Godot以`--main-pack`加载最终Linux PCK，外部QA脚本1152×720 **112项／10图／0失败**，退出0、无错误／警告；`packed-pck-final/`。外部脚本由当前绑定的父测试helpers与子测试flatten生成，`packed-native-final/driver-binding.json`记录原始输入及派生哈希，不改PCK或运行资源。 |
| 原生独立程序默认启动／UI | Linux release可执行与旁置PCK，退出0、无错误／警告；`standalone-boot-final/`记录5帧默认入口，实际看过两包选择卡／按钮。原生模板不执行外部`--script`QA，因此没有冒称模板内输入全流程；先前外部脚本尝试无检查产物，已终止归属明确的QA进程并保留`packed-native-final/process-result.json`。实际输入证据来自上两行。 |
| 跨进程存档 | writer42＋reader43，**85项／0失败**，不同PID、完整typed快照、stage哈希与归属清理通过；`process-restart-final/process-restart-results.json`。 |
| Web／Linux导出 | 两者退出0，无脚本错误／错误／警告；`export-web.json`、`export-linux.json`。Linux包含可执行／PCK／PLAY／第三方与字体许可／manifest／SHA256SUMS。 |
| Web HTTP字节 | **13文件、118,967,525字节**，全部HTTP200、长度与SHA256一致；`http-binding.json`。实际浏览器操作未验证。 |
| 字体 | 固定OFL源与fontTools4.51.0重建，820码点无缺字，派生字体276,448字节；元数据与哈希随源码及stage绑定。 |
| 来源／工作区 | `source-stage-binding.json`、`source-import-cleanup.json`。首次源树导入产生的61个新UID／GLB派生PNG已按初始clean证据清理，两个跟踪的GLB import设置恢复原字节。承平仍为固定提交、clean；没有触碰原试玩存档。 |

Web离线包：`/home/x1-lite/games/shu/.local/build/x1-p1b-20261024/shu-x1-p1b-web-20261024.zip`，88,344,972字节，SHA256 `93882d5c98737b1d8404759ae907ea1b1c4ff13449ce0471d0c659b4feb9810c`。
Linux离线包：`/home/x1-lite/games/shu/.local/build/x1-p1b-20261024/shu-x1-p1b-linux-20261024.zip`，107,161,713字节，SHA256 `43caa2152af31ff5835f229a119ada636b5d08dedf2d25255aea2058f60891be`。两zip逐文件读回与SHA256SUMS通过；`artifact-inspection.json`只证明元数据／哈希，不替代上面的运行证据。

交付时`shu-p1b-web-preview.service`及`shu-p1b-native-preview.service`均active；新原生窗口直接运行最终Linux独立程序，日志／journal无错误。`preview-services.txt`记录旧18812／18813与P1a原生PID未变，新服务只监听127.0.0.1。临时服务不保证重启后仍在；若关闭新窗口，可直接重开：

```bash
/home/x1-lite/games/shu/.local/build/x1-p1b-20261024/stage-998cc78b3722/linux/shu-town-walk.x86_64
```

从当前源码重建独立stage：

```bash
python3 tools/build_cultivation_engine.py --output /absolute/existing/build-dir --entry scenes/demos/cultivation_engine_v04_town_walk.tscn --title '蜀·街口走走' --app-version 0.3.1-town-walk --user-dir shu-cultivation-engine-town-walk
/opt/agent-creator/godot/bin/godot --headless --path /absolute/returned-stage --editor --import
/opt/agent-creator/godot/bin/godot --headless --path /absolute/returned-stage --script res://tests/cultivation_engine_town_walk_test.gd
python3 tools/validate_town_walk_restart.py --stage /absolute/returned-stage --output /absolute/new-qa-dir
```

最终候选另在生成的stage预设中增加Linux/x86_64 release（`embed_pck=false`），Web沿用单线程预设；生成配置哈希在`generated-settings.json`，不改原项目F5入口。全部可复查实际命令存于对应JSON收据。

状态验证覆盖绕障的合法逐段提交、点／段／整数校验、远距拒绝、run／revision、重复／忙碌、掌柜重访、位置／日期／属性／旗标／完整回执恢复、畸形恢复原子拒绝、零精力跨日、五剑与溪亭隔离。原生窗口测试以 `root.push_input` 注入真实鼠标事件，采样每帧脚点、检查四向与接近过程、存读准确位置、返山后真实松风动作及复命；它不是物理鼠标或浏览器操作。

跨进程 writer／reader 使用不同PID，typed Variant完整快照比对保留整数类型，同时保留JSON报告；只清理带匹配归属token的唯一QA存档目录，不操作玩家数据。其行走提交与动作完成回调为程序化模拟，真实表现证据来自原生窗口检查。

导航独立15项通过；帧率专项17项通过，60／144／1000fps一秒均移动210px、到达只发送一次、旧revision及退役view被拒绝。审查发现逐帧取整会丢失小于一像素的距离，已改为跨帧预算累计并保留舍入负债；另将奇数格距从内容合同拒绝。导航测试曾暴露薄墙夹在格心间的穿越，已在AStar边成本加入相同精确几何检查。失败日志保留，未改弱失败条件。

浏览器工具inventory本轮仍为空，实际浏览器点击、刷新和持久存储未验证。Web导出和HTTP字节检查不替代浏览器验收。设备听感、物理鼠标、Windows、Steam Deck、手柄、长期性能与用户P1b认可均未验证；P0的用户认可仅属于P0。原声音资源未新增，人物与场景简绘外观仍待试玩。

## 试玩步骤

在远程桌面进入 X1 后，切到新的《蜀·街口走走》原生窗口；或在 **X1桌面内浏览器**打开 [18814本机试玩](http://127.0.0.1:18814/)。Mac的同一localhost指向Mac自身。18812／18813旧试玩与存档保留，新服务只监听本机，没有公开部署。

1. 选择《山下集镇·走一趟》开始，可先听教，也可直接「下山进城」。收起回报后开始走动。
2. 点击中间摊棚另一侧的石路，观察角色绕行；点右侧掌柜、下方木牌，观察走近才互动、时辰不变。
3. 在街上存档，走去别处，再读档确认回到原位置；再问掌柜，检查他记得先前问候。
4. 点左上返山石阶，走近后才扣一次时辰；回听雨廊继续练剑、复命与休息。

本片交付后先根据你的试玩调整人物、构图和走路节奏，再决定后续片；没有开始调查案、战斗、合并main或公开部署。

2026-10-24后续：用户已明确授权“保存到GitHub”，本片与后续混合场景一起在现有分支归档。主开发路径仍为`/home/x1-lite/games/shu`，见[GitHub归档与本地入口](X1_TOWN_INTEGRATION_GITHUB.md)。以上dirty stage及其验证记录保留原事实，不改写为提交后重新构建。
