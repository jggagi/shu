# 山下集镇：2D／3D 混合场景

客户端日期：2026-10-24，America/Los_Angeles。用户明确要求把承平的混合场景适配到Shu山下集镇，替换简绘占位，保留养成、互动和存档，完成后试玩。此片是P1b的表现升级，不是P2案件或P3战斗。

## 玩家可见的变化

山下集镇现在以真实3D石路、铺面、曲面瓦顶、摊棚、树木、台阶、光照和阴影构成；蓝衣江砚秋与棕衣掌柜使用原创全身四向2D图帧，作为Sprite3D billboard置于同一场景。人物经过建筑时使用真实深度关系，近身遮挡处局部渐隐。固定透视摄像机保持原行走范围和三个互动点可见。

点击画面后先反投影回原逻辑地面，再使用已有P1b寻路与宿主提交；点击人物、木牌和返山出口仍须走近。原日期、精力、成长、掌柜记忆、免费走动／阅读、旅行每程一时辰及返山后听教／五剑／复命均保持。实际3D实体的地面范围只落在原障碍或可走区域外；悬牌和横梁位于空中，没有额外隐藏碰撞。

首轮画面发现照明偏黄、高光裁白与街外纹理波纹，已减弱日光、改中性环境光、去掉街外拉伸纹理，并校准脚点接地。建筑、人物和构图是本轮可玩候选，用户视觉与节奏认可尚待试玩。

## 来源、资源与状态边界

实际工作仍为X1 Lite / Fedora、Bash、用户`x1-lite`，主副本`/home/x1-lite/games/shu`、`codex/x1-shu-integration-plan`，HEAD `e1e682a72af842253e613b30efd2d1f27f662fd9`加上一轮保留的P1b未提交修改。首次试玩交付阶段保留完整工作区，不从旧main覆盖、不在Mac开发；当时未执行提交／push／合并或公开部署。

承平只读固定`codex/vertical-slice` / `a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`，没有在来源导入或修改。选择性适配`hd2d_street.gd`／`street_details.gd`的SubViewport组合、投影与反投影、建筑／曲面屋顶、billboard人物、受光和遮挡思路；没有复制其地图坐标、人物、剧情或像素资源。来源文件哈希、Godot官方demo固定引用、许可和改写见[来源审查](P1B_HD2D_SOURCE_AUDIT.md)。Godot viewport部分的完整MIT原文位于`assets/art/shanxia_hd2d/GODOT-VIEWPORT-LICENSE.txt`，哈希随资源记录，发行第三方声明也包含全文；其许可不扩展成承平原创代码的统一MIT许可。

入口[新场景](../scenes/demos/cultivation_engine_v05_town_hd2d.tscn)采用`town_hd2d_mode_view`／`town_hd2d_walker`／`town_hd2d_stage`。新walker继承原P1b walker，只增加投影、命中和画面；没有新GameState或第二套结算。原5个核心状态文件、所有`shu_town_walk` JSON、包ID `shu_town_walk`、内容版本`0.3.1`、JSON指纹、15字段及SaveStore format1逐字节保持。独立构建表现版本`0.3.1-town-hd2d`不改变内容存档版本。

人物素材为本片代码创作的SVG图集：每人4方向×4帧、每格80×112，脚点`[40,104]`，统一锚点以Sprite3D.offset落在实际地面。作者工具、身份配色、SHA256和许可在`assets/art/shanxia_hd2d/source.json`，可用`tools/build_town_hd2d_characters.py`重建。没有将半身原画或固定练剑图集冒充行走素材。没有新增云端生成、采购、配音或第三方人物素材。

原生应用继续使用`shu-cultivation-engine-town-walk` custom userdir和`user://cultivation_engine_town_walk`，可直接继续原P1b存档，不做迁移、重置或改写。开工时该原生人工检查点目录没有保存文件；兼容验证使用旧stage真实writer产生的隔离QA档，而非伪称恢复过不存在的玩家档。测试在UI `_ready`前设置随机QA Store，不扫描或写入人工存档。

Web主升级入口使用旧18814 origin下的`/hd2d/`。仅在旧Web产物根下新增指向新Web产物的符号链接，旧index及原13个文件保持原字节、旧服务PID不变。固定引擎源码和导出JS证明IDBFS `/userfs`数据库与custom userdir不以页面子路径分隔，因而同源路径应保留旧档；这属于源码推断，实际浏览器继续／刷新尚未验证。独立18815属于不同origin，不自动获得18814网页档。详见[Web存档说明](P1B_HD2D_WEB_STORAGE.md)。

## 最终验证与交付

固定Godot `/opt/agent-creator/godot/bin/godot`，`4.7.2.stable.official.ed1daf0bf`，GDScript／Compatibility。新构建根`.local/build/x1-hd2d-20261024/`；证据根`.local/qa/x1-hd2d-20261024/`，首轮候选与最终检查分开保留。

最终stage `/home/x1-lite/games/shu/.local/build/x1-hd2d-20261024/stage-a1adc95d2b7a`，195个输入逐项与当前源码／stage／清单SHA256一致；runtime digest `0f71cc6876cc251a11d26098dd33dc554df770052d8c91df82aa10bdab37df79`。仍为e1e682a＋dirty候选，不冒称已提交。构建器继续收集全部games JSON及具体资源闭包，不声称仅含当前两包。

| 检查层 | 最终结果与证据（相对于证据根的final/） |
| --- | --- |
| 导入 | `--editor --quit`退出0，7.83秒，无SCRIPT ERROR／ERROR／WARNING；`import-result.json`。 |
| 8组状态 | **1065项／0失败**（原7组941＋P1b124），逐进程退出0、日志无错误／警告；`state/`。 |
| 真实旧stage→新stage兼容 | **85项／0失败**，旧P1b writer与新reader不同PID；全量typed快照、5核心与所有town JSON哈希、custom userdir均匹配；`compatibility/compatibility-results.json`。仅操作归属明确的QA Store，保留fixture供原生继续测试。 |
| 编辑器脚本驱动原生窗口 | 960×600与1152×720各**192项／12图／0失败**，合计384项／24图，均退出0且无错误／警告；`native-<size>/`。覆盖实际旧档UI继续、掌柜记忆、投影反解、绕障、三处近距互动、重复／busy、准确位置存读、原松风真实演出／复命及溪亭隔离。 |
| 导出PCK外部驱动 | 固定Godot `--main-pack` 加载最终Linux PCK，1152×720 **192项／12图／0失败**、退出0，无错误／警告；`packed-pck/`。父／子QA helpers按原语义flatten为外部脚本，源与派生哈希在`driver-binding.json`，没有修改运行资源或把QA带入发行。 |
| 原生独立程序默认启动／UI | 最终release可执行与PCK启动退出0，无错误／警告；`standalone-boot/`保存5帧默认入口，实际看过两个内容包、按钮和原P1b标题。发行模板内的物理／注入输入全流程未另验证；输入证据来自上两层。 |
| Web／Linux导出 | 两者退出0，无错误／警告；`export-web.json`、`export-linux.json`。生成的Linux/x86_64预设、项目配置哈希在`generated-settings.json`；没有更改项目F5。 |
| Web HTTP字节读回 | 18814/hd2d/及18815各**13文件、119,069,435字节**，全部HTTP200、长度／SHA256一致；`http-binding.json`。浏览器操作未验证。 |
| 资源／产物 | 820码点OFL字体覆盖无缺字；人物4向×4帧与脚点一致；完整MIT viewport原文随第三方声明提供。两zip逐文件读回、SHA256SUMS与`creator-game-check`元数据通过；`archives.json`、`artifact-inspection.json`。 |
| 模块专项 | 最终舞台构造、实际实体footprint与8点投影复核退出0，最大逻辑反解误差0.000137px；`.local/qa/x1-p1b-hd2d-20261024/stage-module/stage-check-final.json`。它是模块检查，不代替上面的窗口输入。 |

首个QA候选曾把既有void `check()`当bool使用，解析失败；只修新增测试为布尔wrapper后，在runtime逐字节相同的独立候选跑通192项。首次候选、失败日志及修订后的来源绑定留在`candidate-001/`，最终表只列最终stage。正式数据／状态代码未因测试修改。

Web离线包 `/home/x1-lite/games/shu/.local/build/x1-hd2d-20261024/shu-x1-town-hd2d-web-20261024.zip`，88,439,457字节，SHA256 `b7d30ace830e805cdde0c81939a76bbf502824dd4c5decdf841f3abd4d6a9c71`。
Linux离线包 `/home/x1-lite/games/shu/.local/build/x1-hd2d-20261024/shu-x1-town-hd2d-linux-20261024.zip`，107,255,861字节，SHA256 `5a2e93f612e23102d4c82c9c7c5d344a5e1528b743a783fbd0903795e13e5a90`。包内包含PLAY、第三方及字体许可、manifest和SHA256SUMS；无测试、开发证据或源目录。

交付时`shu-hd2d-web-preview.service`及`shu-hd2d-native-preview.service`均active。原生服务直接运行最终Linux独立程序，日志／journal无错误。旧18812／18813／18814和P1a／P1b原生PID均保持，`preview-services.txt`记录实际命令与状态；`same-origin-alias.json`证明只加新路径、旧13个Web文件未改。机器重启后临时服务不保证保留。

关闭新窗口后，可在X1桌面终端直接重开：

```bash
/home/x1-lite/games/shu/.local/build/x1-hd2d-20261024/stage-a1adc95d2b7a/linux/shu-town-hd2d.x86_64
```

重建及兼容复核使用当前仓库工具：

```bash
python3 tools/build_cultivation_engine.py --output /absolute/existing/build-dir --entry scenes/demos/cultivation_engine_v05_town_hd2d.tscn --title '蜀·山下集镇' --app-version 0.3.1-town-hd2d --user-dir shu-cultivation-engine-town-walk
python3 tools/validate_town_hd2d_compatibility.py --previous-stage /absolute/previous-p1b-stage --stage /absolute/new-stage --output /absolute/new-qa-dir
```

导入、原生窗口、导出与PCK实际命令分别写在对应JSON收据；保留源码dirty记录和资源闭包哈希。

实际验证分为状态检查、原生窗口自动注入、导出PCK外部驱动、原生独立程序默认启动，以及Web导出／HTTP字节读回；这些不互相替代。浏览器工具inventory仍为空，浏览器点击／旧网页档继续／刷新恢复未验证。设备听感、物理鼠标／实体手柄、Windows、Steam Deck、长期性能与用户认可也未补签。原生输入测试采用Dummy音频；新预览使用系统音频，但不据此宣称听感验收。

## 试玩

在X1桌面切到新窗口《蜀·山下集镇》；已有P1b原生档可直接点「继续」。网页优先用[同源升级入口18814/hd2d/](http://127.0.0.1:18814/hd2d/)，独立新入口为[18815](http://127.0.0.1:18815/)。这些localhost地址须在X1桌面内使用；Codex新浏览器面板可经应用转发显示。原18812／18813／18814页面与原生进程保持。

1. 开始或继续《山下集镇·走一趟》，下山并收起回报。
2. 点摊棚另一侧石路绕行；点掌柜或木牌，观察走近互动、人物四向和建筑遮挡。
3. 城内保存，再走去别处、读档，确认回到原位置且掌柜记得问候。
4. 走到返山石阶，核对旅行只扣一次时辰；回听雨廊继续原听教、练剑和复命。

本轮交付后按试玩反馈调整混合场景的构图与人物表现，不自动开展调查、战斗或发布。

2026-10-24后续：用户明确授权保存到GitHub，当前源码与文档在原功能分支归档；没有将“保存”扩展为自行合并main或公开部署。主开发副本和源码入口见[GitHub归档与本地入口](X1_TOWN_INTEGRATION_GITHUB.md)。以上stage仍按实际构建时的dirty输入和SHA256识别。
