# P3 · 全身发力与落雁斩实战样板

客户端日期：2026-10-26 America/Los_Angeles。状态：本机及实际PCK检查完成，18832新预览已启动；本轮新观感等待用户试玩。

用户对18831近看与两招轮廓回复「可以」，随后批准完成全身发力、实战衔接与模板复用。认可指向18831本轮试玩，不补签旧浏览器、声音或其他平台验证。

## 需求与玩家验收

- 落雁斩：过顶举剑时短垫步，支撑脚稳定，出剑前落脚承重，腰肩带剑斩落，再完整收势回位。动作临时去除特效仍应看出发力。
- 实战：江砚秋现有「松风剑」采用落雁斩式表现，按钮标为「松风剑·落雁斩」。保持近身1格、6点基础伤害、一次出招及原移动规则；只升级这一行为的动作、同刻命中和受击表现。沈听岚原剑击、穿云刺、回风扫、击退、打断与保护目标保持。
- 复用：同一可追溯步法模板分别驱动右脚剑步与左脚掌步，掌法以更小幅度完成第二例。劲风掌仍在工坊试演，不自行添加掌法结算。
- 交互：沿用近看、同刻原版对照、慢放／暂停／时间线与本机审阅。战斗忙碌期间禁止重复指令，结束和重试恢复原格位、姿态与输入。

## 制作与运行边界

仍使用原角色、22骨、原rest、skin、握剑、开放掌与现有Blender自定义控制层，Godot4.7.2／GDScript／Compatibility／Web单线程。源模型、原六招catalog与recipes、Rules／Session／SaveStore／遭遇和内容包0.5.0保持。旧18830／18831及资产不覆盖。

支撑脚全程锁定，活动脚按明确的离地／前移／落脚／驻留／返步相位移动，首尾归零。旧无步法合同仍执行原两脚锁定；不能把有意踏步的位移误报为脚滑，也不能删去落脚与支撑检查。模板字节、配方、实际工具和源资源均进入制作指纹；可编辑Blend与运行GLB分别记录。

实战只对player/strike建立显式表现映射，增强目录仍是preview_only资源描述，不成为规则权威。源释放.58s、命中.66s保持；战斗表现名义总长1.82s，接触处名义停顿70ms，并保证至少两个Stage呈现接触采样。大时间增量首次跨接触时夹在.66；下一帧若将直接跨.73则先夹在.695，audit记录丢弃的表现增量。低帧率下实际停留时间允许延长，不能追赶跳过接触。工坊原版／增强版仍用原来相同事件时长；表现层不再次扣血、加奖或消耗时辰。

## 实际模板与离线复现

本轮使用[同一短进步模板](../assets/data/martial_workshop/control_rig/step_plant_return.template.json)，由[落雁斩配方](../assets/data/martial_workshop/control_rig/sword_cleave.json)和[劲风掌配方](../assets/data/martial_workshop/control_rig/palm_gale.json)选择活动脚、前送与抬高幅度。归一化时间点为`0/.10/.22/.34/.60/.74/.90/1`，`.34–.60`是严格接地平台，`.90–1`双脚已回原位；这些是当前两例的制作参数，不是所有武学默认值。旧配方没有`footwork`块时仍执行原两脚锁定。

| 候选 | 活动脚／前送／抬高目标 | 实际接地平台 | 接地采样 |
|---|---|---|---|
| 落雁斩 | 右／0.24m／0.075m | 0.527–0.930s | 41帧 |
| 劲风掌 | 左／0.18m／0.060m | 0.493–0.870s | 38帧 |

两招Blender来源采样的支撑漂移、活动脚目标残差、平台接触漂移及首末目标位移均为0；腕残差<6µm、腿链残差<45µm、10ms局部骨旋转峰值18.397°／15.980°。独立重组实际GLB后，支撑漂移分别46.73／42.00µm、活动脚与平台误差48.48／48.02µm，均保持原50µm门槛。导出器将变化<0.0001的近恒定通道压为两端键，与这项来源／导出差异一致；不把源报告的0冒充运行资源完全无误差。数字不代替动作自然度验收。

[批处理器](../tools/build_martial_control_variants.py)调用[Blender制作器](../tools/hero_lookdev/build_martial_control_motions.py)，用已有Blender5.2.2 LTS、固定Godot4.7.2和本地输入复现：

```bash
python3 tools/build_martial_control_variants.py --check-only
python3 tools/build_martial_control_variants.py \
  --log-root .local/qa/martial-fullbody/motion \
  --report .local/qa/martial-fullbody/motion/reproduce.json
```

模板SHA为`472295d78569c89ac5b8a9bbac6f8c3e230496ea82c8260348e297fc7a2316cc`。批预检与制作器各自单次捕获模板字节用于解析／SHA，并通过`--expected-template-sha256`拒绝中途变动；直接调用也校验数值、次序、中性区间与平台。编辑回流保留同一合同，不能只改Foot曲线后继续报告旧模板。另存Blend后使用`--edited-blend`；隔离候选同时设置`--output`、`--sources-root`及显式`--variants-output`，详见[制作说明](../assets/data/martial_workshop/control_rig/README.md)。

## 冻结动作与制作源

最终[增强目录](../assets/data/martial_workshop/control_variants.json)SHA为`8c055080c5abcccb5cb1b8920abe9380c1f9ef8694098e12c08b9a88d78bb8c9`。运行时只使用原22骨、66轨和3顶点carrier，不复制人物网格或纹理；完整Blend只用于本地编辑。

- [落雁斩GLB](../assets/art/martial_workshop/control_rig/sword_cleave/158b20053fb99a52/motion.glb)：`35ff0301c1b01b4ca6eef0e4124551cfb66333d6bc3f1bc1f8bffe962524bcdc`；[来源报告](../assets/art/martial_workshop/control_rig/sword_cleave/158b20053fb99a52/source-motion.json)。可编辑源`/home/x1-lite/games/shu/.local/worktrees/mountain-ambush/.local/sources/martial-control-rig/sword_cleave/158b20053fb99a52/controls.blend`，SHA `cda891a48b10e3d961b98a2a77e111fc68df6bf23551d15dd18cf9b296f1096b`。
- [劲风掌GLB](../assets/art/martial_workshop/control_rig/palm_gale/af1ee0f5c26908c5/motion.glb)：`1f6cbfb51fad300489788c4f914c8501c3a14c2231564ebaa9f692bd3e3eb4f6`；[来源报告](../assets/art/martial_workshop/control_rig/palm_gale/af1ee0f5c26908c5/source-motion.json)。可编辑源`/home/x1-lite/games/shu/.local/worktrees/mountain-ambush/.local/sources/martial-control-rig/palm_gale/af1ee0f5c26908c5/controls.blend`，SHA `5d6cf958ec780c66cb91f3de46727fa380fefd3fd9b5d161e48c028b0c2fb88d`。

Root已审C1实际近看关键姿态与踏步构图；最终资源因来源合同修复更换制作指纹，两个GLB整文件仍与C1相同，可复用这组动作画面。实战及实际包检查已在下节完成，用户新观感仍须试玩认可。

制作收据在`.local/qa/martial-fullbody/motion/final-proof.json`，独立GLB审查在`.local/qa/martial-fullbody/independent/raw-motion-review.json`。35项旧模型、原六招catalog／recipes／profiles、旧制作工具及18830／18831动作文件SHA保持；原无步法两配方在最终代码重编后66轨与采样时间全部误差0。默认两任务与隔离编辑两任务分别2缓存命中／0生成。有效COG曲线额外4mm沉身回流通过；未改模板的4mm摆动脚横移被新合同检查拒绝，15类无效合同／预检字节变动也被拒绝。

制作过程的失败保留：初次QA自定义输出被相对路径处理拒绝，随后发现自定义输出仍复用默认Blend源路径，重存了本轮C1剑源；已从保留备份按原SHA逐字节恢复，夹具副本另存。新增`--sources-root`与路径规范化后，隔离回流及默认源hash／缓存复验均通过。独立代码审查先发现模板预检绑定、直调校验、控制曲线与声明目标、有效平台采样四项缺口，均已修复；原C1和初次失败收据不删除，没有放宽脚接触门槛。

## 当前候选与验证

最终stage为`.local/build/martial-fullbody-20261026/stage-c7a05089a9ae`，绑定406项源文件，与当前源一致；相较18831为26项有意修订、18项新增、0项移除。共享运行源码digest为`ba59c72a73092006d5b17b65dd60919c335e573498b93009f428027a9ce53b5c`，字库797码点。最终收据为`.local/qa/martial-fullbody/final-validation.json`。

14条最终命令均退出0，无游戏脚本／资源错误；旧工坊QA服务中的1条已知X11/XIM初始化提示已单列，未称全部日志干净。状态检查为Rules52、木栅127、Session86、skills322、catalog86、control-rig544，共1217项。实际渲染／Godot根输入的六套检查如下，合计2040项／56张UI截图；本轮总计3257项，不累加前轮2601项。

| 最终实际运行 | 尺寸 | 检查／UI截图 |
|---|---|---|
| 原生全身实战 | 1152×720 | 299／10 |
| 原生增强工坊 | 1152×720 | 409／8 |
| 原生原六招工坊回归 | 1152×720 | 361／10 |
| 实际PCK全身实战 | 960×600 | 295／10 |
| 实际PCK增强工坊 | 960×600 | 409／8 |
| 实际PCK完整护药、胜败／重置、返城与师傅选择 | 1152×720 | 267／10 |

以上通过真实Godot `root.push_input`和原遭遇运行，未用直接按钮signal代替输入；这不等于物理输入或浏览器操作。Root另复看26张关键相位、8张临时无特效身体诊断图、81帧常速／半速实播；实际PCK960的开局与命中截图确认按钮排版、目标受6点伤害及剑锋／特效落点可见。最终两GLB逐字节等同这组已审C1动作，用户艺术判断仍待试玩。

失败和重跑保留：三轮接触采样诊断暴露截图／GPU读回干扰及低帧率仅呈现一次接触，修复首两次观察不得读回，并在运行时保证至少两次接触呈现；多帧输入夹具边界另改为同步真实press/release，原0.14秒门槛保持。旧工坊短音效在process观察之间播完，改为Stage建声后、GPU绘制前的`frame_pre_draw`观察并同步真实暂停，原7秒／live／paused阈值未放宽，运行时音频未改变。

宿主exec曾在子进程打印旧工坊PASS后以143中断，未保存exit；该命令在短暂用户QA服务实际重跑exit0、361项／10图通过，并单列XIM提示。其余导出和三个PCK命令在同一冻结stage独立进程完成，源码／406源绑定／digest均未改变。日志、失败收据、XIM分类和全过程在最终收据及`xim-warning-classification.json`中保留。

最终stage使用`--serial-import`，并独立复制同引擎派生导入缓存；所有原始资源／import字节SHA匹配后仍运行正常Godot import，见`derived-import-cache.json`，未更换引擎或Compatibility。消费来源整合后离线两任务仍2缓存命中／0生成，见`motion/cache-after-consumers.json`。

Web导出的`index.pck`为118888828bytes，SHA256 `e1c1d58b1e864dff228cd4d29274374a9084bf4e5ed52588b74faa8a64b1bd44`；7个HTTP文件共158720431bytes，完整读回、MIME与SHA均匹配。Web导出／HTTP和实际PCK回归分别验证，不将它们冒充浏览器玩法或性能。

## 交付与下一验收

在X1桌面内打开[18832全身发力试玩](http://127.0.0.1:18832/)，或切到同PCK原生窗口。app `0.6.3-martial-fullbody-candidate`、独立userdir `shu-martial-fullbody`、gamepack0.5.0；新Web／原生两服务active，旧18个预览服务全部保持，共20个。主main干净且与origin/main同为`7c992c578b1fe4a1624c769812425b38080771d3`，本轮未提交／push或公开发布。

浏览器打开请求返回queued；本轮Browser插件bootstrap缺少`browser-service.mjs`，未能实际操作浏览器，未修改系统或浏览器配置。原生启动另见同类XIM提示；实际浏览器玩法／性能、实体输入与原生中文IME、设备听感、Windows／Steam Deck、长时性能、旧档迁移和用户新观感仍未验证。

试玩先对初始相邻持棍客使用「松风剑·落雁斩」，看落脚→斩落→受击→回位；确认仍只受6点伤害、原格位及未用移动保留。再进工坊对照两招和原版，检查步法确有差异、落脚稳定、近看不裁切。


## 后续反馈与接续（2026-10-26）

用户对本轮18832回复「可以，下面做什么」，认可该轮方向；随后以「好」批准[剑掌配合切片](P3_SWORD_PALM_SLICE.md)。新一轮将劲风掌明确注册为沈听岚真实战斗技能，并验证先掌开路、后剑追击的空间关系。因此本文件「劲风掌仍只工坊试演／内容包0.5.0保持」是本轮交付时边界，不能用于否定后续批准的0.5.1变化。这里的406项源／3257项检查及18832产物继续独立保留，不转记为新切片证据。 后续剑掌切片已完成本机与实际PCK检查，18833及同PCK原生已交付；本轮既有18832和源资产保持。新片的408源／2228项／44图单列，用户对新剑掌平衡／观感仍待试玩。
