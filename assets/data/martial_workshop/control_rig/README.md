# 武学工坊：自定义控制层动作切片

本片覆盖落雁斩／劲风掌的增强变体。Blender 5.2.2 LTS 本地 CPU 制作，使用命名控制对象、CopyTransforms／CopyRotation 和四条两段 IK；**没有安装或使用 Rigify**。运行时仍用原22骨、原角色外形和原配方事件时刻。

```bash
python3 tools/build_martial_control_variants.py --check-only
python3 tools/build_martial_control_variants.py --report .local/qa/martial-control-rig/motion/batch.json
```

两张招式 JSON 是动作意图与控制器曲线的制作输入；`step_plant_return.template.json` 是两招共用的短进步模板，不是第三招。原六招 `catalog.json`、recipes 与原模型只读。编译结果在 `assets/art/martial_workshop/control_rig/<move_id>/<fingerprint>/`，包含 carrier-only `motion.glb`、100fps `.import`、数值来源报告与缓存清单。可编辑完整模型及12个控制对象保存在 `.local/sources/martial-control-rig/<move_id>/<fingerprint>/controls.blend`；源报告给出完整路径与SHA。运行时不用这个大制作文件。

`CTRL_COG` 管沉髋和重心转移，`Spine/Chest/Gaze` 管躯干相位与视线；`Hand.L/R` 同时管腕目标与手/剑轴；`Elbow.L/R` 是随躯干移动的肘pole；`Foot.L/R` 控制脚踝世界空间位置与方向；无footwork时两脚全程锁定，短进步时支持脚锁定、摆动脚按模板前送/踏稳/回收，方向保持源中性。`Knee.L/R` 管膝弯曲平面。稠密100fps普通对象曲线可在 Blender Graph Editor 修改，未使用Python handler或隐藏driver。IK仅在两个精确中性端点关闭，以保留源中性；内部帧全程开启，脚还受世界空间完整目标变换约束；进步是骨架内的脚/腿动作，不移动演员root或棋盘格。

手工修改请保留自动生成的制作源，另存本地副本；用显式回流命令生成独立候选：

```bash
python3 tools/build_martial_control_variants.py \
  --edited-blend palm_gale=/absolute/path/to/controls-edited.blend \
  --variants-output .local/qa/my-motion/control_variants.json \
  --report .local/qa/my-motion/batch.json
```

编辑输入的SHA进入新任务指纹，输出新文件夹；原Blend与默认变体JSON均不被覆盖。此模式要求显式 `--variants-output`。修改文件必须保留原22骨、rest、控制器名称、制作源身份、足步合同及首尾中性。控制曲线改变后仍须过对应的脚接触、腕目标、剑轴和骨架检查，再由真实场景审阅决定是否接纳。

指纹包括两张制作配方、实际引用的模板文件全部字节（含原始SHA）、实际profiles.json字节、固定模型/手型/原特效音频依赖、原招式播放意图、制作脚本和Blender/Godot二进制SHA。默认生产不把输出Blend、运行时脚本、文档或来源报告反喂为输入。清单按所有输出SHA验证缓存，文件存在不等于有效缓存。

原骨架无手指骨，手型由现有开放掌提供；无布料/头发模拟。数值合格不能代替动作自然度、半速/常速、场景衔接、Web及用户试玩验收。两招的特效、音频、释放/命中/总时长与原版完全相同，便于同刻比较。


2026-10-26全身发力修订加入可选`footwork`：

```json
{"template":"step_plant_return.template.json","active_side":"R","distance_m":0.24,"lift_m":0.075}
```

模板只定义归一化“沉身→抬脚前送→踏稳发力→抬脚回收→原位收势”，两招以源时长换算；落雁斩右脚0.24m/0.075m，劲风掌左脚0.18m/0.06m。踏稳平台为归一化`.34–.60`，覆盖两招既有释放/命中。前送/抬高采用原脚踝的偏移；位置不等于足底高度，不声称足跟独立滚动或通用步态引擎。无该块的旧配方保持原静态脚行为。

来源报告用明确的支持脚漂移、摆动脚目标残差、踏稳接触漂移与首尾目标位移检查进步；`max_foot_drift_m`保留为实际位移，进步时不再据其声称全程双脚锁定。静态配方仍保留旧`foot_lock_under_50um`检查。额外测量臂/腿链长（<50µm）及10ms局部骨旋转连续性（<30°），不能代替场景常速/半速审阅。

生产日志可指定`--log-root .local/qa/martial-fullbody/motion`。实际新配方、模板与编辑回流/缓存证据见两张`*-shot.md`及本地QA；原18830/18831资源目录保持，不覆盖旧输出。

模板由批预检单次`read_bytes`解析和计算SHA；制作器接收`--expected-template-sha256`并在任何Blender导入前比对。直接调用制作器也完整校验参数、归一化时间、平台与中性区间。源报告校验实际Foot控制曲线与声明模板目标一致，并要求有踏稳采样，不能只改Foot曲线却继续报告旧模板合同。

隔离编辑试验还可加`--output .local/qa/my-motion/assets --sources-root .local/qa/my-motion/blends`；后者将完整制作Blend隔离，防止自定义输出位置仍写入默认源路径。两参数的相对路径按当前工作目录规范化。保留默认目录时无需设置。来源报告、缓存清单仍逐项验证实际输出SHA；改变输出路径不改变动作输入指纹。
