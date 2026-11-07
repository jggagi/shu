# P3a · 沈听岚战斗形象与截脉指

后续同一关的[松风古道环境切片](P3_SONGFENG_ENVIRONMENT_SLICE.md)已完成本机与实际PCK检查，当前试玩入口18821，环境审美待用户试玩。本页18820、639项／65图与指尖检查保留为前轮历史证据，不覆盖后续环境候选。

客户端日期：2026-10-24，America/Los_Angeles。状态：**独立角色、动作与指尖轨迹起点已实现，最终本机与实际PCK检查通过，外观待试玩**。本片继续同一场两人对三人的山道遇袭，承接[战斗反馈加强](P3_AMBUSH_FEEDBACK_SLICE.md)，不将上一候选593项／52图作为新角色通过的证据。

## 授权与角色边界

用户批准升级沈听岚的战斗形象、标志性截脉指，以及移动、受击和收势表现，在同一关验收。上轮「不错」记录为战斗反馈方向认可，不补签浏览器专项或其余人物造型；本次批准的是制作范围，沈听岚新造型仍需实际试玩拍板。

沈听岚沿用既有名字与「入门弟子／剑术同门」身份。原始形象参考为[人物概念图](concepts/03-character-roster.png)上排第二位，文件来源与认可范围见[概念索引](concepts/README.md)。本片不补写性别、身世、关系或新剧情。

本轮造型候选依据概念图处理深色长高束发、青色系带、深青剑衫、面部比例和服装细节。左手制作独立双指手型及截脉指出手，右手持一把剑；角色在正常战斗距离与近看中应有清楚的同门身份和独立轮廓。具体脸型、衣摆、发束、动作幅度仍属待试玩的实现参数。

## 来源与制作方法

本轮采用本地Blender模型衍生制作。既有 `assets/art/mountain_ambush/jiang-approved.glb` 作为已验证体型、拓扑与骨架的技术底稿，另建独立沈听岚候选；这不是找到沈听岚现成模型，也不把江砚秋原审批扩大成沈听岚造型认可。

| 来源 | 固定身份与本轮用途 |
| --- | --- |
| 江砚秋既有GLB | SHA256 `e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27`，17,700,976字节。仅作本轮衍生技术底稿，原文件作为只读输入保留，不覆盖。 |
| 江砚秋获批原 `.blend` | `.local/sources/jiang-approved-warm-9aa7c926/jiang-sword-phrase.blend`，175,525,576字节，SHA256 `9aa7c926103f58b664427b2400601001562ff9a436b153c9b46d0c9241de6e65`，权限444。原源保持，来源与原审批见[模型复用记录](P3_JIANG_MODEL_REUSE.md)。 |
| 沈听岚概念参考 | `docs/concepts/03-character-roster.png`，SHA256 `267fa67dc43133794c4df914501515056e323b41a3379c56e8b4b14590e17da0`；引用作身份与服饰参考，不直接充当新模型贴图。 |
| 沈听岚既有战斗候选 | `ambush_actor.gd`／`ambush_character_mesh.gd`的本地程序几何及旧近看截图保留为前轮对照；不冒充本轮Blender衍生源。 |
| 新角色制作源 | `.local/sources/tinglan-candidate-v2/tinglan-candidate.blend`，16,366,547字节，SHA256 `0d354a948c747c8e82d35c8feb59b340bc8cfe4a9ec59079c61d4e761b4ffec1`。独立可编辑工程，由本轮脚本从江GLB衍生，不改写江原源。 |
| 新角色派生GLB | `assets/art/mountain_ambush/tinglan-candidate.glb`，16,974,732字节，SHA256 `cdbec85183a9e2d452546c6a5a1a164c854042c9a2f4f783b5d184c750d5856b`；69,249三角面、27个运行mesh、22骨，已用于最终包检查；指尖轨迹起点修正不改变该GLB。 |

本轮制作前，本地项目与现有记录的盘点未发现独立沈听岚 `.blend`／GLB或专用原画；Mac本轮未新作实时查询，不能由本地未发现推导Mac不存在。本片明确采用新的衍生制作来源，不把来源缺项写成已找回资产。

模型与短动作在本地制作，借用既有骨架适配、来源追踪与复位检查方法；没有新图片生成，也不承诺离线原画动作片交付。江砚秋原源与GLB、三名敌人不因本片而修改造型。

## 接入与玩法边界

- 同一场山道遇袭、同一角色ID与武学ID、同一规则数值和胜败条件。规则、Session、内容JSON与存档合同不改，演出不额外扣血或推进时间。
- 已建立沈听岚独立运行适配器，舞台传入技能ID，近看提供独立指法按钮；资产与动作已接入当前候选，最终检查与外观认可分别记录。
- 战场与近看当前消费同一独立沈听岚资产。普通剑招、左手截脉指、移动、受击与收势分开处理；动作完成或取消后的复位已纳入最终流程检查；具体观感仍待试玩。
- 继续在 `/home/x1-lite/games/shu/.local/worktrees/mountain-ambush` 制作，主副本main保持干净；旧18816／18817／18818／18819候选及其检查证据保留。新入口为18820，产物与实际检查见下方。
- 无新云调用、素材上传、费用、依赖安装、Git提交／推送或公开发布。

## 当前已实现的模型与动作

新资产继承江GLB的基础比例、UV和22骨架作为技术底稿；本轮是角色衍生与局部几何制作，不称为重新独立雕刻全部人物。面部与衣服采用COLOR_0局部乘色增益，原纹理像素与江GLB保持；新长发、青系带、衣摆、玉扣和双指手型是本地新增几何。

左手采用两种真实mesh互斥显示，分别服务稳定待机／普通动作与截脉指，不靠在原手前叠放第二只可见手冒充换型。右侧原握持与一把剑保留。运行适配器独立处理动画和手型，避免本片改动江砚秋表现。

当前GLB包含三个片段：Idle约0.433秒；保留原Sword四秒片段供战斗短剑式采样；新 `TinglanInterrupt` 为0.4秒，约0.133秒到命中姿态、0.333秒已回中性，0.4秒为静止尾。指法、剑式、移动、受击、自然收势与提前取消的最终可观察结果仍按下表分别验收。

Tinglan与Actor提供 `get_action_origin("interrupt")`，stage据此把绿色指法轨迹接到实际骨骼指尖。独立13项probe按真实mesh顶点、蒙皮权重与求值骨架检查：0.13秒时局部起点约 `(0.12005, 1.31979, 0.57669)`，距最近真实蒙皮指尖2.72毫米、距双指末端中心15.41毫米；旋转和平移后关系保持。该检查证明轨迹不再从腰间发出，不等于起点与每个顶点零误差重合。

## 本地复现与候选身份

使用已有Blender5.2.2与新脚本 `tools/hero_lookdev/build_ambush_tinglan.py`。在当前worktree下，候选的复现命令为：

```bash
/usr/bin/blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python /home/x1-lite/games/shu/.local/worktrees/mountain-ambush/tools/hero_lookdev/build_ambush_tinglan.py -- \
  --base /home/x1-lite/games/shu/.local/worktrees/mountain-ambush/assets/art/mountain_ambush/jiang-approved.glb \
  --out /home/x1-lite/games/shu/.local/worktrees/mountain-ambush/assets/art/mountain_ambush/tinglan-candidate.glb \
  --blend /home/x1-lite/games/shu/.local/worktrees/mountain-ambush/.local/sources/tinglan-candidate-v2/tinglan-candidate.blend
```

已有Blender的OCIO配置声明2.5，而已装库为2.4。脚本自动生成仅用于该进程的兼容配置副本，带该配置重启本次流程；没有修改系统配置、安装或升级依赖。原江GLB是只读输入，导出与可编辑工程写入独立沈听岚路径。

最终stage为 `.local/build/tinglan-character-20261024/stage-43aea7c643cf`，231项输入与worktree逐项SHA一致，665码点字库；应用版本 `0.4.4-tinglan-candidate`，原生custom userdir为 `shu-mountain-ambush-tinglan`。下方639项／65图及实际PCK、HTTP结果均绑定此stage，汇总收据为 `.local/qa/tinglan-character/final-validation.json`。

## 过程与中间候选

制作中修正了原shader graph读取、导入帧率与旧片段时长，以及初轮偏棕头发、旧马尾残片、颈部误染和发尾折线。现于导入前设30fps，保留Sword四秒与新指法0.4秒；报告统计实际GLB网格，校准读取实际bounds，probe读取当前metadata。失败候选与日志保留，当前外观仍不宣称无缺陷。

根代理查看过candidate13三视与指法侧视。中间stage `ed9811a2fec6` 的637项／65图确已通过，随后发现手抬到胸前而绿色轨迹仍从腰间发出；修正为骨骼指尖起点后重新执行完整pipeline，并追加真实蒙皮指尖probe。旧stage保留，其QA归档到 `.local/qa/tinglan-character/pre-tip-origin/`，不与下方最终639项混用。其余制作与检查材料位于当前worktree `.local/qa/tinglan-character/`。

## 逐步验收卡

| 验收项 | 当前状态与观察点 |
| --- | --- |
| 独立制作源与来源链 | 新工程／GLB独立；16项规则／Session／JSON保持，江原源／adapter／GLB、ambush_view、原mesh helper未变；六份嵌入纹理payload SHA与江底稿完全相同。 |
| 造型正侧背面 | 本轮实际渲染已检查，用户观感待试玩。检查深色长束发、青系带、深青服饰、面部与衣摆；同场与近看一致，不从模型补定人设。 |
| 指法与兵器 | 最终原生、runtime与真实蒙皮指尖probe已检查，观感待试玩。左手双指、右手一剑，轨迹从指尖发出；普通攻击与截脉指可辨，命中／打断仍对应真实规则事件。 |
| 移动、受击与收势 | 已纳入实际输入／回归与probe，观感待试玩。脚底、腰身、手剑、衣摆与发束连续，移动到位、受击结束和出招收势回到同一稳定状态。 |
| 近看与模态 | 本轮实际近看与probe已检查。转身、行走、剑招与独立指法按钮，提前取消／关闭后无残留姿态，宿主与战局快照不变。 |
| 原关玩法连续性 | 实际PCK完整流程已检查。真实完成移动、剑招、截脉指、胜败、重试、返回与安全存读，检查无重复结算或过期回调。 |
| 两尺寸与导出包 | 指尖起点修正后的最终两尺寸回归、实际PCK、Web导出及7文件HTTP完整读回通过，分项与边界见下方。 |
| 用户造型与动作认可 | 待试玩。本轮制作授权不等于新形象获认可。 |

## 最终检查、产物与平台边界

Godot4.7.2／Compatibility、X1原生实际渲染，输入由Godot `root.push_input` 注入，不是浏览器或物理键鼠验收。最终QA命令全部退出0，Dummy音频下日志无游戏脚本／资源警告错误。规则52项与会话84项，共136项通过；独立runtime probe19项、真实蒙皮指尖起点probe13项通过。四次图像／输入检查共639项、65图、0失败，均对应最终stage `43aea7c643cf`：

| 最终检查 | 实际结果 | 当前worktree `.local/qa/tinglan-character/` 证据目录 |
| --- | --- | --- |
| 原生人物近看1152×720 | 139项／22图，含沈听岚正侧背面、独立指法与兵器、指尖起点、动作和模态检查。 | `final-native-characters1152/` |
| 实际PCK反馈960×600 | 118项／11图，含真实截脉指与原关击退、碰撞、打断和威胁反馈。 | `final-pck-feedback960/` |
| 实际PCK完整流程1152×720 | 243项／10图，含胜败、重试、返回城镇、安全存读、返山与同场师父选择。 | `final-pck-flow1152/` |
| 实际PCK人物近看960×600 | 139项／22图，确认新角色、指法按钮、指尖起点、手型与动作在实际包内可用。 | `final-pck-characters960/` |

完整串行执行器为 `.local/qa/tinglan-character/run_final.py`；每条实际命令、参数、退出码、错误检索和日志路径见同目录 `final-commands.json`，包括 `final-runtime-probe`。独立指尖检查见 `finger-origin-probe.json`／`.log`，汇总绑定见 `final-validation.json`。原生和实际PCK检查分别记录，不由源码检查代替打包后验收。

Web共7文件、149,166,887字节，PCK为109,335,284字节、SHA256 `6327e03b64c0725fc8f028bb971515cb68b9d69422716c1bd7f6a2d7a027b59a`。导入／导出及7文件HTTP完整字节／SHA256读回通过，WASM MIME正确；产物与HTTP证据为 `final-stage.json`、`final-build.json`、`final-http.json`。

总收据实核16项保护文件、江原源／GLB／adapter、ambush_view、mesh helper与11项旧素材保持，原江 `.blend` 权限444；六份嵌入纹理payload字节SHA与江底稿相同。江砚秋与三敌的mesh计数、三角面数和bounds尺寸保持；待机呼吸可使捕获的bounds起点有毫米差异，不称逐姿势不变。主副本main干净并与origin/main `7c992c5` 一致；本轮源码仍为独立worktree未提交状态。

浏览器打开请求已排队，代理未完成浏览器实操／刷新／IndexedDB专项。用户观感、Windows／Steam Deck、实体输入、设备听感与长期性能仍未验证；上一轮593项／52图和更早人物候选计数继续只属于各自候选。

## 当前试玩与复现

在 **X1桌面内**打开[18820沈听岚试玩](http://127.0.0.1:18820/)，若此前已打开18820请刷新以加载最终包。Web服务 `shu-ambush-tinglan-web-final-20261024.service` 与同一PCK的原生服务 `shu-ambush-tinglan-native-final-20261024.service` 均active。仅停止被替换的两个中间18820服务，原产物保留；旧18819／18818／18817／18816服务均active，未停止。

常驻原生启动日志 `native-startup.log` 只有既有X11 `wd.xic` 输入法警告，无游戏脚本／资源错误；上述Dummy音频QA日志干净，两者分别记录。浏览器CUA的apps／browsers inventory为空，打开请求虽已排队，不能称浏览器实际玩过。

先点右上「人物近看」→选择「沈听岚」→点「截脉指」，观察左手双指、右手一剑与自然收势；再看正／侧／背、移动、受击或提前取消，返回同一场战斗实际使出截脉指，核对敌方打断和红格变化。新custom userdir为 `shu-mountain-ambush-tinglan`，18820网页存储与旧端口隔离，未自动迁移真实用户旧档。

在当前worktree复现完整QA的命令为：

```bash
cd /home/x1-lite/games/shu/.local/worktrees/mountain-ambush
python3 .local/qa/tinglan-character/run_final.py
```

没有新云调用、费用、依赖安装、Git提交／推送或公开发布。新外观与动作仍是待用户试玩的独立衍生候选，不夸大为专业拓扑、全新独立雕刻或江砚秋原审批下的自动认可。

下一验收点：在正常战场和近看中辨认沈听岚的新外观，实际使出左手截脉指，再检查移动／受击／收势与同一场战斗的连续性。
