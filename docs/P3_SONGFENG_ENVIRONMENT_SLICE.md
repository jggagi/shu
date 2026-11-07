# P3a · 松风古道环境

用户反馈首轮环境不够精细，后继[松风古道细节修订](P3_SONGFENG_DETAIL_SLICE.md)已完成本机与实际PCK检查，当前试玩入口18822、视觉待用户认可。本页18821与941项／63图保留为首轮环境证据，不作为后继修订通过结果。

客户端日期：2026-10-24，America/Los_Angeles。状态：**环境已接入，最终本机与实际PCK检查通过，构图与动态观感待用户试玩**。本片承接[沈听岚战斗形象与截脉指](P3_TINGLAN_CHARACTER_SLICE.md)，继续同一场「山道遇袭」。前轮18820及639项／65图只属于前轮角色候选；本轮新入口为18821。

## 授权与实际实现

用户在询问可用于重点打造环境的开源项目后，授权实施「松风古道」小型环境切片。已把同一战场接入谷地、古道、松石与远山构图。用户批准的是本轮制作范围，场景审美、色调与动态幅度仍需试玩拍板。

| 已授权范围 | 当前实际实现 | 验收状态 |
| --- | --- | --- |
| 场外崖壁与远山 | 不规则山崖台地围合谷地，自制远峰形成层次；中央仍为原平地战斗区域。 | 本机及实际PCK画面检查通过，构图观感待试玩。 |
| 少量Quaternius松／石／草候选 | 实际消费免费Standard包派生的两种岩石、短草与石板；原三格规则障碍换为自然岩石外观。松树最终采用自制盘松，准备的pine-source未进runtime。 | 资源来源与实际消费路径已核对。 |
| 自制盘松 | 原创枝干与松冠作为场景标志，配合场外山崖和道路边缘。 | 两尺寸可见性与动态检查通过，造型待试玩。 |
| 地表过渡 | 土路、路肩与苔草过渡，11块嵌地石板；棋盘、人物脚点和预览保持原逻辑位置。 | 格子投影与真实输入回归通过。 |
| 克制远雾与风动 | 52个两侧草石小物、2片远雾与松草微动；「景物：动态／静止」只切换景物运动。 | 状态隔离、静止／恢复、复位与释放检查通过。 |

独立 [ambush_environment.gd](../addons/cultivation_mode/ambush_environment.gd) 消费[场景布局](../assets/art/mountain_ambush/environment/layout.json)，由 [ambush_stage.gd](../addons/cultivation_mode/ambush_stage.gd) 统一调用 `step(delta)`。环境没有独立process或shader TIME时钟，不推进战斗或养成时间。景物静止不暂停人物出招和战斗；新局／重建恢复景物原位，关闭战场释放环境。

## 玩法与平台边界

- 同一9×7平地战斗、同一两人对三人、药篓与三格障碍。规则、胜败、HP、伤害、移动及养成成本保持，Session继续唯一结算；装饰不增加隐藏碰撞。
- 江砚秋、沈听岚及三敌沿用原模型、材质和动作。16项规则／Session／内容JSON、7份角色代码与GLB逐SHA保持；江原Blend的SHA与444只读权限保持。
- 63格点击仍按原地平面投影。场外崖壁只作景物，真实红格、移动／技能／击退预览、人物名血条与药篓危机提示分别依据原规则显示。
- 使用Godot4.7.2／GDScript／Compatibility与Web单线程。没有更换引擎、渲染器或新增原生扩展依赖。
- 本轮源码在 `/home/x1-lite/games/shu/.local/worktrees/mountain-ambush`，分支 `codex/mountain-ambush-slice`、HEAD `7c992c5` 加未提交修改；主副本main干净并与origin/main一致。
- 新版本 `0.4.5-songfeng-candidate`、custom userdir `shu-mountain-ambush-songfeng` 与18821独立。旧18820原生／Web及18819／18818／18817／18816均active，产物与历史证据保留，未自动迁移真实玩家档。
- 没有新图片生成、云端生成调用、采购费用、依赖安装、Git提交／推送或公开发布。

## 素材与开源制作来源

Quaternius实际来源为 **Stylized Nature MegaKit免费Standard包**，不是付费Source版。原ZIP为104,088,529字节、SHA256 `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`，作者包内许可为CC0；固定地址、源文件／依赖／导出SHA及处理细节见[环境来源清单](../assets/art/mountain_ambush/environment/source-environment.json)，[许可原文](../assets/art/mountain_ambush/environment/License_Quaternius_CC0.txt)随仓保留。旧官方Drive取源遇到配额限制后改取作者免费Standard，未购买Source。

共准备6份GLB、3,025,912字节，连同PNG副本为4,834,939字节；**当前runtime只消费4份GLB**：rock-a、rock-b、grass-a、stone-step，合计2,287,524字节。pine-source和grass-b保留作制作候选，未进runtime。原PNG只做缩图并嵌入GLB，辅以alpha处理、哑光与材质乘色；没有新绘制、AI生成图片或改写原下载源。

ProtonScatter真实用于制作期散布：固定commit `7198cc00078ebde61307578137c3f35223c6e438`，通过原PathShape／负BoxShape、Create Inside Random／Edit Scale／Randomize Transforms和原ModifierStack生成36草＋16碎石。固定种子两次独立Godot烘焙字节相同，52项变换均避开中央禁区，并符合两侧范围与尺度。原插件335份文件原样，仅置于独立 `.local/tools/songfeng-scatter-authoring` 制作项目；runtime只读取[散布布局JSON](../assets/art/mountain_ambush/environment/scatter-layout.json)，不带addon或Textures.com demo素材。固定ZIP、输出SHA、实际API与复现命令见[散布来源清单](../assets/art/mountain_ambush/environment/source-scatter.json)，[MIT原文](../assets/art/mountain_ambush/environment/PROTON-LICENSE.txt)随仓保留。

本地可复现入口为 [build_ambush_environment_assets.py](../tools/hero_lookdev/build_ambush_environment_assets.py) 与 [bake_ambush_scatter.py](../tools/hero_lookdev/bake_ambush_scatter.py)／[制作脚本](../tools/hero_lookdev/bake_ambush_scatter.gd)。散布工具先核独立制作项目metadata，误在生产项目运行会退出且不写入数据；动态load与拼接路径避免把制作插件跟入游戏资源闭包。

## 最终验收与证据

最终stage为 `.local/build/songfeng-environment-20261024/stage-68333106fea2`，246项输入与worktree逐SHA一致，673码点字库。汇总收据为 `.local/qa/songfeng-environment/final-validation.json`。下列实际输入由Godot `root.push_input` 注入，在X1原生Compatibility渲染；实际PCK通过独立harness加载，宿主没有运行资源副本。它们不等同于浏览器或实体键鼠验收。

规则52项＋会话84项，共136项通过。五组实际渲染／输入检查合计 **941项、63图、0失败**，所有命令退出0，Dummy音频QA日志无脚本／资源警告错误：

| 最终检查 | 结果 | `.local/qa/songfeng-environment/` 下证据目录 |
| --- | --- | --- |
| 原生环境1152×720 | 219项／10图：构图、格子、静态／动态、状态隔离、复位与释放。 | `final-native-environment1152/` |
| 实际PCK环境960×600 | 219项／10图：同一环境专项在实际包与小尺寸复核。 | `final-pck-environment960/` |
| 实际PCK反馈960×600 | 120项／11图：命中、红格、药篓、击退／碰撞／打断与指法。 | `final-pck-feedback960/` |
| 实际PCK完整流程1152×720 | 244项／10图：胜败、重开／重试、返城、安全存读、步行返山与同场师父选择。 | `final-pck-flow1152/` |
| 实际PCK近看960×600 | 139项／22图：原角色、手剑／指法、近看模态与返回原战斗。 | `final-pck-characters960/` |

独立来源审查27项通过，见 `independent-source-audit.json`；另对最终两尺寸到场、击退与截脉指预览共4张图做独立视觉复核，见 `independent-visual-review.json`。两项分别记录，不追加到941项／63图，也不当作用户审美认可。draft1–4为lookdev过程，其中draft4另有219项／10图环境专项通过；这些中间记录不计入最终数。

新环境未增加遮挡的几何与图像检查通过；开场药篓本体仍与原人物布局挤在一起，上方目标面板清楚。这是保留的布局可读性反馈点，本轮没有另作UI变更。

完整执行器为 `.local/qa/songfeng-environment/run_final.py`，逐条实际命令、参数、日志与退出码见同目录 `final-commands.json`。最终流程已使用新的 [cultivation_ambush_environment_ui_test.gd](../tests/cultivation_ambush_environment_ui_test.gd)，以及原反馈／全流程／近看和规则／会话入口；没有直接重跑或覆写前轮Tinglan执行器。按当前X1显示认证环境复现：

```bash
cd /home/x1-lite/games/shu/.local/worktrees/mountain-ambush
python3 .local/qa/songfeng-environment/run_final.py
```

Web共7文件、152,024,958字节，PCK为112,193,356字节、SHA256 `51c79b7614a95008bb68abd621b48f5e431efb6e7edfeee51270dc9f7300aa5e`。Compatibility导入、Web导出及7文件HTTP完整字节／SHA读回通过，WASM MIME正确；证据为 `final-stage.json`、`final-build.json`、`final-http.json`，与总收据绑定。

## 当前试玩与未验证项

在 **X1桌面内**打开[18821松风古道试玩](http://127.0.0.1:18821/)，或切到同PCK原生窗口。服务 `shu-ambush-songfeng-web-20261024.service` 与 `shu-ambush-songfeng-native-20261024.service` 均active。先看谷地／盘松／远山与嵌地石板，再切「景物：动态／静止」观察风雾；正常移动、击退并使出截脉指，核对红格与药篓危机，最后返回原城镇继续养成。

常驻原生启动只记录既有X11 `wd.xic` 输入法警告，无游戏脚本／资源错误；Dummy音频QA日志干净，两者分别记录。CUA仍返回apps／browsers空列表，打开请求queued不能作为浏览器实操证据。用户环境审美、浏览器输入／刷新存档／帧率、实体键鼠与输入法、设备听感、Windows／Steam Deck、长期性能和真实旧档迁移仍未验收。

下一验收点：用户在正常战场试玩，判断古道构图、松石轮廓、人物接地与远雾风动是否合适，同时确认战术格子和敌方威胁易读。
