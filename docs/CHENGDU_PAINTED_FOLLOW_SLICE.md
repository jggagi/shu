# 成都南门绘景样板：保留整座大城连续跟随镜头

客户端日期：2026-11-08，America/Los_Angeles。状态：初次真实UI绘景未显示的问题已修正，最终同源两尺寸完整原生490项／34张UI图／0失败、正常退出且日志无错误／警告，独立overlay像素A/B确认画稿实际出现。2538项状态、源保护与最终Web导出／HTTP字节核验通过，18866已启动；实际Web UI未验证。旧244项／17图候选、38项／2图烟测与旧独立专项各自留证，不累计成最终检查；局部地面／画幅边界限制和观感待验仍在。

## 已确认方向与本轮边界

用户要求按之前城镇切片的方法制作，并明确选择「保持现在整座大城的连续跟随镜头」。当前 `15360 × 11520`、592栋普通住宅的尺度继续作为已认可基线；镜头保持随人物在整座连续城市中行走，不转为固定相机或由固定画面组成的房间切换。

上一轮 `0.7.1-detail-city` 为南门、桥栏与8栋立面的程序构件候选，技术检查有记录，具体画面观感尚未获用户认可。它没有制作并接入此前茶街那种整幅绘景，不能把增加程序构件等同于用户此次指定的制作流程。旧构建、截图、状态、输入与浏览器证据仍按[原精修卡](CHENGDU_DETAIL_CITY_SLICE.md)保留。

本轮先制作一张由实际相机校准的南门环境画稿，验证画面语言与连续跟随镜头能否一起成立。南门以外的大城保持原有表现，不把这张画稿或局部投影样板说成全城绘景完成。画稿、材质过渡、移动时的观感与实际覆盖范围均是待试玩候选。

| 状态 | 当前内容 |
| --- | --- |
| 用户已确认 | 现有大城尺度；保留整座大城的连续跟随镜头；按之前城镇绘景切片方法推进。 |
| 已有实现 | 原Scale世界、导航、真3D人物、师徒养成、茶馆双门、伞与保存；0.7.1程序构件及其技术证据保留，未获得此次绘景观感认可。 |
| 本轮实施选择 | 首个样板为南门，以实际无UI／无人物底稿和旧茶街画稿分别约束几何与风格；先做单张画稿校准。 |
| 已实现／已技术验证 | 单张画稿、ID与相机、世界投影已制作；入树前签名已修正，最终两尺寸完整原生490项／34图及overlay独立像素贡献通过；2538项状态、源保护、导出与HTTP通过。 |
| 未验证范围 | 实际Web UI与浏览器保存刷新、Windows、实体输入／声音等未验证；旧独立七点／699步不当作新helper全部重验。 |
| 待用户认可 | 南门样板画面风格与观感、跟随移动中的效果；其他街区尚未绘制，不预设全城认可。 |

## 方法来源及适用范围

本轮方法参考来自town-polish工作树的 [`painted-town.md`](/home/x1-lite/games/shu/.local/worktrees/town-polish/.agents/skills/game-painted-scene-build/references/painted-town.md)：从实际相机导出无UI底稿与地标，制作整幅原创绘景，保留深度几何代理与独立真实3D人物，再校准人物接触、遮挡、输入和镜头。该记录对应旧茶街18850的制作经验；旧茶街画面与人物的正向反馈不等于当前成都样板已经获认可。

旧方法原场景采用固定画稿与有限查看，画稿不包含建筑侧背信息；当前用户选择的是大城连续跟随，必须作新的适配。仅复用制作关系和可追溯参考，不将town-polish整棵工作树、另一套状态或旧18850的通过结论搬入本轮。

本轮实现将画稿采样绑定在实际屋顶、墙面和地面的世界位置上：固定参考相机只负责给这些表面找画稿像素，玩家相机继续正常跟随。没有把整张画稿按 `SCREEN_UV` 固定贴在当前屏幕，也没有为了贴图临时锁住玩家镜头。源ID遮罩、参考法线方向与画幅边缘限制覆盖，原几何继续负责深度。源ID是几何对象级身份，不是完整的逐像素参考深度图；复杂表面是否露出旧材质或出现边界，需要图审，不能由身份匹配自动推定完美。

人物保持独立3D模型与原脚点，在几何表面前后行走；绘制的环境光影与人物实时受光分别核对，不因为用了绘景就声称整片环境可实时重打光。远近移动时画稿是否漂移、伸展、漏边或投到错误表面，需要在连续画面里观察，单个校准点截图不能证明跟随成立。

## 当前制作来源与文件

| 用途 | 当前已有文件／状态 |
| --- | --- |
| 几何与相机构图权威 | [`camera-environment.png`](concepts/chengdu-painted-gate-20261108/camera-environment.png)，实际Godot南门底稿，无UI与人物；脚点 `[7800,8400]`、1280×720，SHA256 `0dd0d53fb32fe2afc16d206f665d73248ceefadb68f25e2b5aa2c39a82f94819` |
| 风格参考 | [`town-style-reference.png`](concepts/chengdu-painted-gate-20261108/town-style-reference.png)，来自clean first-journey提交 `36760937d1c643a53652ccc5cffd8001ff785a1c` 的原茶街画稿；SHA `6656fe35aa44d9e6a7a0f05e3cc3705a1ccb214cf8d38537d164d8d31748500b`。只约束画面语言，不复制其茶街布局到南门 |
| 精确提示词 | [`camera-calibrated-gate.txt`](../art/prompts/chengdu-painted-gate-20261108/camera-calibrated-gate.txt)，SHA `fa77adc0be1962fb9bd3403c54b072235d4636e32196649907b19a5355344431`；记录底稿几何不变、镜头不动、通路保持及无人物／UI等约束 |
| 单张绘景 | [`painted-gate.png`](../assets/art/chengdu_painted_gate/painted-gate.png)，1672×941、不透明，SHA `611c601ad21440b17ccb8044a73b876bf9faa7ae79c4d174153bf3181f3b7fac`。内建 `codex-imagegen` 实际单次生成；回执模型未回显（null），不猜测具体模型；未调用付费API或Qwen批量生成 |
| 表面ID遮罩 | [`source-id-mask.png`](../assets/art/chengdu_painted_gate/source-id-mask.png)，1280×720数据图，SHA `52fca5a21a2c16ad150704645e9218a1786bc24140169491fcc4bf8dbaf3d975`；nearest、不转sRGB、无mipmap，不是绘画素材 |
| 参考相机 | [`reference-camera.json`](../assets/art/chengdu_painted_gate/reference-camera.json)，SHA `ef7b3b7d1d273abd1bfb8733613899a0ba3bb93910d681945f5965884c053e95`；记录原参考投影、稳定几何签名与表面身份，不是玩家固定相机模式 |
| 来源元数据 | [`source.json`](../assets/art/chengdu_painted_gate/source.json)保留准确参考、提示词、调用次数、模型未回显、原生成文件位置与SHA。其选作原型的初始审阅状态与本轮后续专项分别记录，技术检查不改写为用户认可 |
| 玩法包与空间 | 复用 [`shu_chengdu_scale / 0.7.0`](../games/shu_chengdu_scale/game.json)、[`walks.json`](../games/shu_chengdu_scale/walks.json)与 [`chengdu-scale-layout.json`](../assets/data/chengdu-scale-layout.json) |

提示词要求对屋顶、门洞、墙基与地面边界保持像素对齐，只在既有表面内绘制材质和光色，不新增堵路树木、台阶、车辆或建筑轮廓。是否实际做到必须看生成图与原底稿、表面遮罩的对照；提示词约束不算验证结果。

既有茶街画稿、人物模型、纹理的来源与许可继续按原记录保留，不重新标成新生成素材，也不因参考文件可读就推定所有制作源齐备。用户最初的成都地图仍仅作方位参考，不作为本轮底稿或运行贴图，原有[来源记录](references/chengdu-user-map-source.json)保持。

## 独立入口与原能力

| 项目 | 当前实施候选 |
| --- | --- |
| 内容包 | 继续 `shu_chengdu_scale / 0.7.0`，不新建包、状态或剧情 |
| 应用候选 | `0.7.2-painted-follow`，构建用户目录 `shu-chengdu-painted-20261108` |
| 场景入口 | [`cultivation_engine_chengdu_painted.tscn`](../scenes/demos/cultivation_engine_chengdu_painted.tscn)，最终两尺寸原生从该实际应用入口运行，结果与未验范围见下表 |
| 表现适配器 | [`chengdu_painted_mode_view.gd`](../addons/cultivation_mode/chengdu_painted_mode_view.gd)、[`chengdu_painted_walker.gd`](../addons/cultivation_mode/chengdu_painted_walker.gd)、[`chengdu_painted_gate_stage.gd`](../addons/cultivation_mode/chengdu_painted_gate_stage.gd)、[`chengdu_painted_gate_art.gd`](../addons/cultivation_mode/chengdu_painted_gate_art.gd)；世界投影与局部私有材质由新表现适配承担 |
| 表现配置 | [`chengdu-painted-gate-layout.json`](../assets/data/chengdu-painted-gate-layout.json)，画稿／遮罩／相机、24px画幅边缘过渡、参考法线与局部fallback配置；不含新导航或持久状态 |
| 内容目录 | 继续 [`chengdu_scale_catalog.json`](../games/chengdu_scale_catalog.json) |
| SaveStore基础目录 | `user://chengdu_painted_city`，与Scale／Detail目录隔离，最终应用使用独立用户目录 |
| 新本机服务 | [18866南门绘景试玩](http://127.0.0.1:18866/)已指向修正后stage；最终五文件HTTP200且完整字节SHA与磁盘一致。实际Web UI未验证 |
| 旧对照 | 18864已认可尺度版、18865程序构件候选保持可用，两页HTML与原冻结产物一致；旧存档及技术证据保持 |

所有位置、时钟、精力、旗标、伞、人物记忆与一次回执仍归唯一EngineSession。普通行走与查看费用、茶馆双门、返山、原师父同场景对话与选择、五剑、声音和安全存档保持。绘景适配只呈现，不增加通行任务、改动热点距离、改变行走速度或引入新人物动作状态。普通民居仍是外景，南门样板不代表新店铺或室内已实现。

新应用与旧存档目录隔离，不自动迁移浏览器其他端口的存档。主线与支线原稿归档规则保持，本轮不迁移或新增长篇剧情稿。

## 本轮可观察的验收点

1. 在与底稿相同的校准位置，新画稿的屋檐、门洞、墙面和地面位置准确对应，人物、UI与可走门洞保持独立而清楚。
2. 从桥南走向南门，再靠近、侧移和穿门时，画面内容留在正确的世界表面上；全城镜头仍正常跟随，角色的脚点、碰撞、热点与点击逆投影一致。
3. 参考画稿没有覆盖的边缘、侧背或远处退回原有表现；不出现固定在屏幕上的纹理漂移、画稿投穿到人物或错误墙面的情况。
4. 走出南门样板后仍能在原大城连续行走，地图、茶馆双门、伞、返山和原养成能力保持；不借局部绘景声称全城已画完。
5. 在两种既有窗口尺寸及实际Web中检查画稿清晰度、UI排版、保存／Load与真实刷新恢复；静态对比、数学投影、原生输入、浏览器和用户观感分别记录。

## 已知样板限制

一张参考画稿只覆盖参考相机看见的南门表面。靠近或进入门洞后，新露出而原参考视角看不见的地面仍是旧绿色铺地；城门侧背与两侧回墙使用各自复制的灰度／暖色fallback材质，未改变其余城内共享材质。最终图审已看到旧细绿缝被消除、东西回墙均实际生效，但新露出地面、局部画幅边缘与生成画稿的轮廓差异仍可见，不能称为无缝整城绘景。

109个匹配覆盖源代表安装与身份匹配数量，不等于109处均有同等画面贡献或全部像素准确；本轮另用原图回投、洋红覆盖与A/B图证明真实投影贡献。绘制光影已经烘在画里，人物实时受光不构成环境全面实时重打光。首个样板的艺术质量、移动中边界与风格衔接继续待用户试玩。

## 验证记录：最终原生与产物已验，Web UI及观感待验

保持Godot `4.7.2.stable.official.ed1daf0bf`、GDScript、Compatibility及匹配Web单线程模板。修正后的应用stage为 `.local/build/chengdu-painted-20261108/stage-5a08af989f04`，357项输入，运行库digest `9d296aeb7db301707238e0f8fbd76e2d245bd501c8674829f984d48c8d6b81ab`；helper SHA `1a187e1bddc2e4fd713b390c224048ade86670e95ec37bd0647d3431ba57e5eb`。工作树仍为 `codex/chengdu-connected-streets` / `7c992c578b1fe4a1624c769812425b38080771d3` 加已有dirty修改。旧 `stage-ebd689714c3d`及runtime `84d75f…`只作失败候选，实际应用显示结论不沿用。

| 层次 | 当前实际状态 |
| --- | --- |
| 用户方向确认 | 城市尺度和全城连续跟随镜头已确认，南门绘景成品与投影效果待认可。 |
| 生产素材与来源 | 单次内建imagegen画稿、准确prompt／参考、IDmask及相机文件均已产出，来源、尺寸与SHA见上表；不声称模型回显、付费API或全城生成。 |
| 世界投影与源审查 | helper使用世界顶点和冻结参考矩阵；原几何负责深度，源ID／参考法线排除无关表面，屋顶露人discard与旧shader一致，人物／UI不纳入投影。`source-review.json`的静态源审查和CPU矩阵／PNG验证仅对应其绑定版本，不替代真实生命周期；修正后的实际应用证明另见 `lifecycle-summary.json`。 |
| 修正后应用状态 | 新stage重新运行基础184、Scale2303、导航51，共 **2538项／0失败**，三组正常退出0。headless状态与绘景可见性分开验证。 |
| 最终源保护与静态审查 | `preservation-audit.json`59项通过，原346输入仅构建登记工具变化，新357输入与最终stage匹配；原玩法、导航、空间、人物、字体和媒体字节保持，旧冻结stage原字节保持。`source-review.json`绑定当前helper／stage／配置，仅为静态源、CPU矩阵及PNG核验，不代替GPU／UI或美术认可。 |
| 修正后应用构建／导出 | 新stage357输入，导入约10.29秒、Web单线程导出约2.77秒，均正常退出0且日志无错误／警告。旧候选的12.13秒／3.12秒及HTTP记录只属于旧stage，不覆盖新产物。 |
| 旧helper七点专项：历史 | `scene-summary.json`历史记录为 `PASS_FOR_LOCAL_WORLD_PROJECTIVE_TECHNICAL_PROBE`：桥南、门前、参考点、东西侧、门内、首街七点合法，几何错误表空；安装源58→109，门体38／两侧回墙各11处fallback生效。绘景／原图回投／tint脚本留22图，参考视角853096像素呈洋红；它证明旧独立脚手架的overlay贡献，不代表修正后完整应用同源重跑、画质或整城完成度。 |
| 旧helper原图回投：历史 | 距源ID边界至少3px且排除24px画幅过渡的682253内部像素中，原图回投MAE约0.00315（8位通道），最大通道差>3的像素为5。它检验旧版参考投影／身份对应，不是生成画稿本身的几何误差或新helper全图重验。mask无意外编码色，源ID仍是对象级而非逐像素深度图。 |
| 旧helper跟随专项：历史 | 旧GPU脚本从桥南沿合法轴行走2520逻辑像素，699步、约12.229秒，留15帧图，错误表空、退出0；世界／镜头未改，人物头脚在界内。脚本先入树后setup，不是实际UI同生命周期或Session／真实鼠标／存档证明；此次未把七点与699步整套重跑，不冒充新helper通过范围，也不当FPS基准。 |
| 旧专项日志限制 | 旧独立脚手架先尝试不可用的X11，再在Wayland／Compatibility运行；无SCRIPT／GLSL错误，但退出有2个ObjectDB清理实例。其exit0不代表最终应用清洁退出，最终新原生另验。 |
| 初次实际原生：未通过 | 两窗口测试各244项／17图／0失败，但图审绘景完全未显示、引擎ERROR大量出现，不能列为PASS。独立QA先入tree后setup，实际UI先setup后入tree；helper依赖global_transform产生无效签名／seen缓存。证据归档 `candidate-detached-setup`，修正后的强回归另列，不抹去旧失败。 |
| 生命周期修正与强回归 | 仅新helper的签名改为从world_root到几何节点按根到叶累乘局部 `Node3D.transform`，入树前后不依赖global查询；相机、几何、画稿、mask、碰撞、状态及父类均未改。`lifecycle-summary.json`绑定新helper与相同新runtime：detached GPU入树前匹配58源（含门体50）→入树后109源，签名变化0、局部与global对照差异0；实际应用走原师徒和真实全图鼠标路线，38项／2图／0失败、退出0。两次回归日志均无ERROR／WARNING。 |
| 生命周期烟测像素A/B | 在真实应用同一画面位置只开关overlay，fallback两图均保持，921600像素中666712像素最大通道差>10，证明绘景overlay确实贡献；已目视 `app-detached-smoke/1152x720_smoke_painted_gate.png`。烟测38项／2图不累计进下列完整原生计数，也不等于美术质量认可。 |
| 最终完整原生与实际输入 | 同源显式Wayland窗口1152×720、960×600各 **245项／17张UI图／0失败／退出0**，合计 **490项／34张UI图**，日志无引擎ERROR／WARNING。实际应用走原师徒选择→下山→全城步行→大慈寺→伞→保存→茶馆双门四向→还伞／重访→Load完整状态恢复→返山→重开。报告分别为 `native-wayland-1152/chengdu-scale-render-report.json`、`native-wayland-960/chengdu-scale-render-report.json`。 |
| 最终应用绘景强回归 | 两窗口同位置只开关overlay、fallback保持，各有 **666765／921600** 与 **652578／921600** 像素最大通道差>10，超过10%门槛，实际UI截图已目视出现画稿；另留 **4张viewport A/B诊断图**，不混为34张UI图。测试将3D SubViewport固定1280×720作可比图，实际窗口仍为上述两尺寸；1090×613响应式由生命周期专项另验。 |
| 初次Web导出／HTTP：历史 | 待修候选的五文件均HTTP200、字节与磁盘一致；PCK128492172B，SHA `e8ef9c3705f33256ae9ce7763d0d9cc9f98a853b810424ffc4d97d01484f3e02`。这些记录只说明旧候选字节可读，不代表绘景显示、浏览器输入或刷新通过，不用于当前服务验收。 |
| 最终Web导出／HTTP | 18866已重新指向 `stage-5a08af989f04`，五文件均HTTP200且完整字节／SHA与磁盘相同，见 `http-artifacts.json`。PCK **128492348B**，SHA `99758b8b40bf2c29e16cc552c5a127d8da281f62fd6feef747f1e84d3de221e4`；HTML SHA `5b9585c3b6b2bf4a212b6eaf4350a2327bad302c2a6e3747961a7a48cf09874a`。18864／18865页面仍HTTP200且与原冻结字节一致；HTTP不替代Web UI验证。 |
| 最终汇总收据 | `final-delivery.json`实际汇总为PASS，357项冻结输入与stage无不一致；2538项状态、490项完整原生／34张UI图及同源生命周期／59项源保护分别绑定最终SHA。主副本为与远端相同的clean main `7c992c`；本工作树保留未提交修改，不据此称已Git交付或Web UI通过。 |
| 实际Web UI／浏览器刷新 | **未验证**。本轮CUA库存为空、getBrowser返回 `No browser available`；尝试应用打开后仍无可控浏览器会话，见 `browser-availability.json`。没有运行本轮实际浏览器输入／保存刷新，不借旧0.7.1浏览器结果补签，也不把此工具限制说成游戏无法加载。 |
| 帧间隔采样／平台／用户观感 | 原生行走QA两窗口分别采样9601／9680帧，均值约17.396／17.241ms，P95约18.116／17.996ms，最大132.633／67.053ms；含QA采样与并行窗口负载，不是独占性能基准或投影开销测量，不承诺稳定60帧。实体输入、声音、Windows、Steam Deck、低配和长期未验证；样板风格与跟随效果待用户试玩。 |

本轮QA根目录为 `.local/qa/chengdu-painted-follow/`。初次七点／699步专项的 `scene-summary.json`已标记历史：它在旧helper、先入树的脚手架下通过，不能称为新helper下全部重验。修正后 `lifecycle-summary.json`来自独立 `stage-0c5430f63e7f`，与新应用 `stage-5a08af989f04`共享runtime `9d296aeb…`，357项源绑定无不一致。新生命周期与真实应用像素回归、最终两尺寸完整原生、源保护／HTTP、旧专项、`candidate-detached-setup`失败和浏览器可用性分别留证。最终完整原生只计两份245项报告，不重复累计38项烟测、旧244项候选或旧699步专项。

旧 `scene-first-erosion`含1px边界收缩、绿色fallback及两处在墙内的无效侧点，不作最终合法路径证明；`scene-tint-candidate`仅作中间诊断。最早QA脚本的解析错误与修正后成功日志分开保留，失败候选不转记为最终通过。旧0.7.1的2538项状态、476项原生等仍只属于旧stage；本轮2538项是最终应用实际重跑，不借旧结论。当前未提交、push、合并或公开发布。
