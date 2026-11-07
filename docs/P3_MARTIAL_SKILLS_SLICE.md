# P3a · 穿云刺与回风扫

客户端日期：2026-10-25，America/Los_Angeles。状态：**用户批准的两招完整切片已实现并完成本机／实际PCK检查，视听和平衡等待试玩**。承接[整体打磨](P3_AMBUSH_POLISH_SLICE.md)后的「不错」反馈与工具调研；批准范围是两招动作、范围预览、命中FX与声音，其余五剑整体转实战、独立试演场仍为提案。

后继：用户另行同意的[掌风与落尘工具小样](P3_PALM_VFX_TOOL_SAMPLE.md)已完成本机／实际PCK检查并交付18827，仅为原战场纯试演，不新增掌法规则；本卡的两招验证与18826保留。

## 试玩与可玩范围

在 **X1桌面内**打开[18826两招试玩](http://127.0.0.1:18826/)，或切到同PCK原生窗口。先用下拉框选两招近看试演，再用键6／7选择实战招式、点正交方向格；保留原三招和每轮一次移动／一次出招。「招式声」可开关，试演不伤敌、不扣行动或时辰。

| 招式 | 当前规则候选 | 可见区别 |
| --- | --- | --- |
| 穿云刺 `pierce`／6 | 直线两格，山石／活木栅截断；每名敌人4伤害。 | 独立刺击，剑气在0.24–0.34秒出手段飞到合法终点，命中后退尾淡出。 |
| 回风扫 `sweep`／7 | 正前与左右共三格；中心受阻拒绝，侧格按supercover视线过滤；每名敌人3伤害。 | 独立横扫、连续金白横弧与贴地短尘，正常深度测试。 |

两招均取四正交方向，同伴／药篓免伤且不挡传播；预览与实际命中共用格子和目标预测，范围无敌人不扣行动。4／3伤害待试玩调整。原开局两招各有一名即时目标，多目标UI回归另用明确标注的合法QA布阵。

同局两人三敌、位置、血量、敌招与四轮护药保持；Rules／encounter及绑定有意修订，13项宿主内容保护、Session唯一持久结算、战中禁存和战前／后安全存读保持。包0.5.0、app `0.5.0-martial-skills-candidate`，独立userdir `shu-mountain-ambush-martial-skills`；旧18825／18824／18823六个服务与旧档保留，不自动迁档。

本地Blender制作48,048字节双clip动画库，复用原22骨架与皮肤网格，原GLB／Blend保持；源动作0.13秒对应约0.34秒命中、0.85秒演员动作。剑刃拖尾取真实锚点，横弧共享25点端面，复用单个招式灯。4个原创短WAV由本地Python标准库确定性合成，静音／换招／退出清理已检查。来源、SHA与复现见[总表](../assets/art/mountain_ambush/source.json)、[动作](../assets/art/mountain_ambush/source-martial-clips.json)、[FX](../assets/art/mountain_ambush/skills/source-skill-fx.json)和[声音](../assets/art/mountain_ambush/skills/source-sfx.json)。保持Godot 4.7.2／Compatibility与Web优先，无新模型生成、云调用、采购或安装。

## 主要验证与交付

最终stage `.local/build/ambush-skills-20261025/stage-5f1fce9843a9`，277项源与stage逐SHA一致，699字形覆盖；18项旧输入修改、15项新增、无移除。状态52＋127＋86＋322＝**587项**，16条主命令成功，十套两尺寸原生／实际PCK检查 **2814项／120张UI图／0失败**，另有2张独立战场图，共122个图像文件。覆盖新招／原招、范围与多人命中、免伤、菜单指针、声音调度／静音、清理、胜败重试、返城安全存读与返山师父选择；输入为Godot注入。

最终实际PCK原开局另做轻量时点18项检查，两招各两次输入到命中为336／333／336／335ms，见`minimal-timing/report.json`，不并入主总数。重型UI审计的反馈墙钟另出现189–229ms，两种样本不混用、不推断原因，也不作为Web、帧率或持续性能结论。独立来源38项、QA与最终审图收据另列。

Web7文件153,608,714字节，HTTP完整SHA与WASM MIME通过；PCK113,777,124字节，完整SHA见总收据。`shu-ambush-martial-skills-{web,native}-final-20261025.service`均active。本轮常驻原生出现X11 `wd.xic`警告，主QA日志无警告错误；creator-game-check仅核对产物尺寸与SHA。主main干净且与origin/main `7c992c5`一致，候选dirty，无提交推送或公开发布。

权威证据在`.local/qa/ambush-skills/final-validation.json`；同目录`run_final.py`、`final-commands.json`、`independent-source-audit.json`、`independent-qa-review.json`、`independent-visual-review.json`及各`final-*`保留命令、日志、SHA和图。最终导入使用：

```bash
/opt/agent-creator/godot/bin/godot --headless --path .local/build/ambush-skills-20261025/stage-5f1fce9843a9 --import
```

前两次`--editor --quit`导入崩溃已归档，根因未确认；第三份相同源freshstage采用标准`--import`通过，未改引擎／项目设置。失败导入、菜单测试夹具和剑气／横弧修订过程均保留在上述收据与历史报告，不算最终通过结果。

## 下一验收与限制

请用户比较两招是否容易区分、命中与节奏是否清楚，以及伤害和站位选择是否有意义。用户approve批准实施，不代替新招视听和平衡终验，也不自动批准更多招式。

程序敌人细节仍低于两名原GLB，战术投影下近身人物可能重叠；与商业HD-2D参考品质仍有距离。浏览器打开请求仅queued，未实际加载或操作；浏览器性能、Windows／Steam Deck、实体输入、设备听感、长时和真实旧档迁移未验证，WAV解码／Dummy调度不代替听感。
