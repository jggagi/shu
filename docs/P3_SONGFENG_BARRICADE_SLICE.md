# P3a · 松风古道可破坏木栅

后继实验：[回澜剑战斗灯光三档对照](P3_COMBAT_LIGHT_EXPERIMENT.md)已按「动作有点快」反馈更新0.65速节奏候选，18825当前页请刷新，节奏待认可；本页结果仍只覆盖此前木栅候选。

客户端日期：2026-10-25，America/Los_Angeles。状态：**木栅战术已实现，采用的状态／渲染与最终PCK检查通过，玩法与观感待用户试玩**。本片承接[18823光影统一](P3_SONGFENG_LIGHTING_SLICE.md)，仍是同一路口两人对三敌、护药四轮或全歼。位置、HP6耐久和具体反馈是待试玩参数，不升级为整款游戏的最终平衡设定。

## 实际战术与反馈

| 战术 | 已实现并纳入检查的结果 |
| --- | --- |
| 北段撞栅 | 江砚秋开场用回澜剑击退持棍客，撞毁 `[6,3]` 路口木栅；敌停在栅前 `[5,3]`，承受出招3＋碰撞2＝5伤害，不穿过原木栅格。 |
| 南段拆路 | 初始在 `[5,5]` 的沈听岚以普通剑招选择 `[6,5]` 侧路木栅，一击拆开侧路，再使用尚未消耗的移动。 |

两种出招只消耗一次攻击，不返还已用移动；两条战术均有真实四回合胜利路线。完整木栅、受击／破坏和低矮碎木展示真实回执，预览不提前扣HP或消耗行动。活障碍变化同步刷新路径、视线、技能／击退预览与敌方覆盖，保留本轮原定目标、朝向及路径偏移，不隐藏重选敌人意图。新遭遇从定义重建木栅，不引入持久世界破坏。

本轮实际修改局内Rules、遭遇及gamepack绑定，不能沿用「16项全保持」。13项宿主／内容保护文件、7份角色代码／GLB、17项环境与光影输入保持；原EngineSession／SaveStore、唯一持久结算和安全存档边界保持，江原Blend SHA与444权限保持。木栅为本地原创几何，没有新增模型采购、图片生成、依赖安装、Git提交／推送或公开发布。源码与机制来源见[木栅来源记录](../assets/art/mountain_ambush/environment/source-barricade.json)。

## 最终候选与采用证据

最终stage `.local/build/songfeng-barricade-20261025/stage-58998e8275cb`，258项输入逐SHA与worktree一致；app `0.4.8-songfeng-barricade-candidate`、gamepack `0.4.1`、custom userdir `shu-mountain-ambush-songfeng-barricade`。686字形覆盖。Godot4.7.2／Compatibility、Web单线程保持；主main干净并与origin/main `7c992c5` 一致。

采用状态检查为旧规则52＋木栅规则127＋会话86＝**265项**。六套渲染／Godot实际输入检查共 **1339项、62图、0失败**（60UI＋2world），不计重复运行；证据覆盖格子与动静、两种拆栅战术、四轮胜利、重开／重试／失败、返回城镇、安全存读与返山师父选择：

| 采用检查 | 结果 | 实际候选与证据目录 |
| --- | --- | --- |
| 原生木栅1152×720 | 283项／10图 | stage971；`final-native-barricade1152/` |
| 实际PCK木栅960×600 | 283项／10图 | 最终stage589；`final-v2-pck-barricade960/` |
| 实际PCK光影960×600 | 178项／9UI＋2world图 | stage971；`final-pck-lighting960/` |
| 实际PCK环境960×600 | 221项／10图 | stage971；`final-pck-environment960/` |
| 实际PCK反馈960×600 | 126项／11图 | 最终stage589；`final-v2-pck-feedback960/` |
| 实际PCK完整流程1152×720 | 248项／10图 | 最终stage589；`final-v2-pck-flow1152/` |

证据根为 `.local/qa/songfeng-barricade/`，stage971指 `971175e2c894`，stage589指最终 `58998e8275cb`。状态、原生木栅与光影／环境检查采用stage971结果。最终只修改一份feedback测试：旧断言错误地同时要求互斥的撞击与自由击退提示，现分别检查受阻碰撞和下一次自由击退，保留状态、伤害与破栅断言。其余257项输入及全部runtime／资产相同；这是测试修正，未修游戏runtime，历史失败报告保留。

两候选PCK字节不同，因此最终包重新执行木栅960、反馈960与完整流程1152三套；不声称六套全部在最终stage重跑。对应绑定见 `test-revision-binding.json`／`test-revision-pck.json`；实际命令分别见 `final-commands.json`、`revision-commands.json` 与执行器 `run_final.py`／`run_revision.py`，权威汇总为 `final-validation.json`。采用的成功命令均退出0，Dummy音频QA无脚本／资源警告错误。

独立来源31项与4张审图、另一份最终来源28项分别留证，不追加到1339项；见 `independent-source-audit.json`、`independent-visual-review.json`、`independent-final-source.json`。实际输入为Godot注入，不是物理键鼠或浏览器验证。

## 包、试玩与未验收项

Web共7文件、153,445,658字节；最终PCK为113,614,052字节，SHA256 `86cc0da1eaca3e7d39a6a919ec73e8179b1e54cb12a3f1246fcd8e084bb03831`。7文件HTTP全文／SHA读回及WASM MIME通过，见 `http-final-receipt.json` 与 `creator-game-check-final.json`。

在 **X1桌面内**打开[18824木栅试玩](http://127.0.0.1:18824/)，或切到同PCK原生窗口。服务 `shu-ambush-songfeng-barricade-web-final-20261025.service` 与 `shu-ambush-songfeng-barricade-native-final-20261025.service` 均active，旧18823原生／Web保持；新userdir不迁移旧档。先以江砚秋撞毁北栅，再重开用沈听岚直接拆南栅并移动，比较控敌与开路选择，继续原护药战斗。

常驻原生有既有X11 `wd.xic` 输入法警告，无游戏脚本／资源错误；Dummy QA无警告，两者分开。非阻断表现限制：短时命中浮字可能叠到中央头牌；敌方计划列需滚动才能看全弓手详情，上方药篓威胁汇总保持完整。

用户玩法／平衡／视觉认可、浏览器输入／刷新／性能、Windows／Steam Deck、声音听感、实体输入、长期运行与真实旧档迁移仍未验收。CUA无可控浏览器surface，open queued不作浏览器试玩证据；前轮性能数据不迁用于本轮。下一验收点是实际比较两条拆栅路线，判断路径与敌方预告变化是否清楚、有用。
