# 落雁斩增强版：全身发力候选1任务卡

- **shot_id／版本**：`sword_cleave@enhanced`，全身发力候选1，2026-10-26；当前两招中一招，使用同一个归一化短进步模板。
- **授权与状态**：用户在18831后同意继续“全身发力＋实战衔接”并要求“做完”。本卡记录CPU制作候选；Root场景常速/半速、实战与最终包检查另记，不能由本卡补签用户视觉认可。
- **身份与素材保护**：沿用`res://assets/art/mountain_ambush/jiang-approved.glb`，SHA256 `e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27`。原人物网格/蒙皮/22骨/rest/父子/UV/纹理/服饰与原握持保持；新增编排由Codex for Shu原创。沿用原素材许可条款，不声明底模为MIT或CC0。无上传、云端、付费调用、安装、手指骨或布料模拟。
- **制作路线**：既有固定3D模型→12命名Blender控制对象和12约束（4条两段IK）→100fps烘焙原22骨→carrier-only GLB。未使用Rigify，不生成RGBA、不抠像。控制曲线是普通可编辑F-curves，没有隐藏运行时生成器。
- **动作意图**：举剑过顶→右脚踏稳→转腰斜劈→余势停稳→收脚归中。上半身沿用18831已接受的大轮廓，加入真实脚/腿关节运动；演员root、棋盘格和规则位移不由动画改写。
- **共用模板**：`step_plant_return.template.json`，实际字节SHA `472295d78569c89ac5b8a9bbac6f8c3e230496ea82c8260348e297fc7a2316cc`；时间归一化0–1，关键点`0,.10,.22,.34,.60,.74,.90,1`，`[.34,.60]`为严格踏稳平台。右脚前送0.24m、抬高目标0.075m，左脚全程锁定；回收后双脚回原位。没有toe/heel独立滚动，不能称为完整人体步态系统。
- **实际时序**：0–0.32s 沉髋提剑，右脚抬起；0.32–0.44s 举剑过顶，右脚前送；0.44–0.66s 踏稳转腰，肩腕带剑斜劈；0.66–0.84s 剑锋斜落，越过身侧；0.84–1.55s 松肩收锋，抬脚回中性。摆动脚踏稳区间`0.527–0.930s`，覆盖原释放和命中。
- **时钟合同**：源时长1.55s、100fps/156帧/66轨道；源事件释放.58s／命中.66s不变。实战时钟映射与命中短停由Root集成，制作源不硬加时间。完整首尾接原中性Idle，是单次动作，不声称循环。
- **坐标与脚指标**：报告采样为源Y-up／+Z前方；模板输入为Blender−Y前方/+Z向上。测得前送0.239999995m、最高抬脚0.074993521m，支持脚漂移0m、摆动脚目标残差0m、踏稳接地漂移0m、脚旋转残差0rad、首末目标相邻帧位移0m。旧`max_foot_drift_m`现为有意位移，不再误称全程双脚锁定。
- **链条与连续性**：手臂链长残差3.97723021e-07m、腿链残差4.49344167e-05m，均<50µm；腕目标残差5.66965196e-06m。局部骨四元数相邻10ms最大18.3968°，`upper_arm.R`@0.56s，<30°。数值只说明约束，不能证明动作自然。
- **可编辑制作源**：`/home/x1-lite/games/shu/.local/worktrees/mountain-ambush/.local/sources/martial-control-rig/sword_cleave/158b20053fb99a52/controls.blend`，SHA256 `cda891a48b10e3d961b98a2a77e111fc68df6bf23551d15dd18cf9b296f1096b`。显式另存副本后可经`--edited-blend`回流；制作文件记录足步合同，须匹配原配方/模板。
- **运行输出**：`res://assets/art/martial_workshop/control_rig/sword_cleave/158b20053fb99a52/motion.glb`，clip `SwordCleaveControl`，SHA256 `35ff0301c1b01b4ca6eef0e4124551cfb66333d6bc3f1bc1f8bffe962524bcdc`，65248bytes；仅原22骨Skin和3顶点carrier，不复制人物纹理或网格。
- **来源证据**：`assets/art/martial_workshop/control_rig/sword_cleave/158b20053fb99a52/source-motion.json`、同目录`manifest.json`与`.local/qa/martial-fullbody/motion/batch-final.json`。来源报告all_pass=True；编译器SHA `e8f86d69058128b2a1ce30fdc9e45ede3176a572ca68646a4a829227e8922a81`，Blender `5.2.2 LTS`。模板实际字节、配方、profiles、源模型和工具全部进入缓存指纹，文档与消费者回执不反喂。
- **旧版保护**：原六招catalog/recipes/profiles、18830/18831所有动作资源及原Blend保留。制作前配方/脚本/卡片/sidecar副本和12项SHA在`.local/qa/martial-fullbody/motion/before/`；无footwork的历史配方仍走原双脚锁定路径。
- **待验收**：Root需看前/侧关键相位、正常与半速连续动作、完整剑/手/袖/头发/脚的留边、踏稳到命中和归中切换。实际浏览器操作/性能、设备听感、其他平台、用户认可均分别记录，不以机械检查替代。

来源合同修复后的最终生产：与候选1整GLB SHA完全相同，未修改动作。单次捕获模板字节用于解析和SHA，批预检SHA传入制作器；直接调用同样校验完整步法合同。新增控制器/模板目标残差0m、踏稳有效采样41帧，均通过；未修改模板而改变Foot曲线的编辑输入须拒绝。原候选1资源和源工程仍保留，Root可引用相同动作的已审实景。
