# 真人动作 · 同源 B/C 灰模对照 v1

2026-10-11，用户反馈「这效果不错」，认可当前真人动作灰模效果；B/C 输出方式及最终主角造型待选，未替换正式修习、未发布。

## 探索范围与边界

用户原先选 A，随后持续反馈背转和全身不协调，授权探索“完整 3D 骨架＋真人动作来源，先灰模，再同源预渲染 2D／实时 3D 对照”。本轮零付费，购买另行确认。B/C 尚未成为产品决定，历史 A 素材、主工程入口、DemoState、Tea 与正式 M2 均保持；研究场景不包含玩法状态或结算。

复用独立 `animation-options-lab/shu` worktree，分支 `codex/animation-options-lab`，基线 `f12e3027d010e1c278ab2b0f5b4f6d783998f0b4`。开始时 README、SPEC、DECISIONS、DEVELOPMENT、ANIMATION_OPTIONS_LAB 已有未提交选择记录，全部保留。本轮仅在其中四份追加研究入口；SPEC 不改。原有 789 份文件修改前哈希均与保护快照一致。

## 动作和制作管线

采用 [CMU Graphics Lab 02_09 swordplay](https://mocap.cs.cmu.edu/search.php?subjectnumber=2) 全段真实全身动作。原始 120 Hz、1033 样本；每隔一个样本取一次，得到 60 Hz、517 样本、8.6 秒，无重定时、补造姿势或逐帧改骨长。ASF／AMC 原始文件、作者、下载地址、SHA256 与 [CMU 许可说明](https://mocap.cs.cmu.edu/faqs.php) 保存至 `assets/data/sword_mocap/source/` 和 `assets/art/sword_mocap/source.json`。许可原文附 `CMU-DATA-LICENSE.txt`，不把数据描述为 CC0。

- `cmu_motion.py`：ASF 关节轴、层级、XYZ 旋转顺序和 ASF 原单位到米的换算；解出 root＋30 骨的头尾位置／旋转。
- `make_study.py`：按源人体比例建立原创灰模（8126 顶点），完整 31 骨绑定；只加一次固定场地平移，所有骨的缩放为 1。Blender 4.5.9 LTS 输出 GLB 和 517 张透明 RGBA 帧。
- 左侧 B：21 张 1600×1600 图集，按共享时钟选 60 fps 帧；每源帧 320×320。
- 右侧 C：Godot 4.7.2 Compatibility 的真实 Skeleton3D，手动选择 SwordStudy，按同一时钟采样完整动作。使用同一导出正交镜头及 320×320 透明 SubViewport。
- 两侧采用完全相同、固定的 224×224 视图裁剪，放大人物；全序列最小透明边距 66 px，裁剪边距 48 px，不会按帧改变人物尺度。

Godot 动画导入固定 60 fps，关闭 AnimationPlayer 的有损 optimizer 与 compression，配置随 `study.glb.import` 管理。默认 30 fps／曲线简化曾导致几毫米至厘米级关节误差；失败日志保留，最终全帧校验通过。手动时钟使用 `assigned_animation` 和 `seek(update=true)`，不依赖播放器是否正在自主播放，因此播放终点保持正确姿势。

Blender 灯光与 Godot 灯光不同，B/C 不承诺像素或材质完全一致。UI 提供正常／半速／四分之一速度、暂停、重置、逐帧、时间轴、重复开关、素纸／后山、单看 B/C。默认单次，源动作不是闭环，打开重复会重新起播。

## 实际验证

根代理完成整合、导入排错、实机渲染和浏览器检查；真实 luna_worker 分别完成限定范围的 CMU 转换器与比较 UI／测试。

| 检查 | 实际结果 |
| --- | --- |
| `tests/test_cmu_motion.py` | 7 项通过，包括非零骨轴、根旋转和真实源文件片段 |
| Blender 全段骨架绑定 | 517 样本，最大端点误差 0.000001093 m |
| GLB 浮点值 | 135940 个有限值，0 个非有限值 |
| 全序列图集 | 517 帧／21 张图集，最小边距 66 px |
| `sword_mocap_import_test.gd` | 全部 517 帧／16027 个骨头位置，最大误差 0.000001142 m，0 失败；同时检查骨矩阵有限及无异常缩放 |
| `sword_mocap_comparison_test.gd` | 60 项，0 失败；实际资源、共享 seek、暂停、终点、逐帧、慢放、单看、背景尺寸 |
| `sword_mocap_render.gd` | Apple M4、真实 OpenGL Compatibility；1152×720 与 960×600，37 项／16 张截图／0 失败；暂停画面字节一致 |
| 独立 Web | 同一最终 stage 导入／导出成功；真实 IAB 输入与控制台检查见本地 QA 记录 |

证据位于 `.local/qa/sword-mocap-v1/`，不进 Git：转换器日志、GLB 检查、构建收据、最终三份检查日志、`render-verified/` 两尺寸图像、Web 截图与输入记录、`motion-normal.gif`。GIF 使用实际渲染帧合成素色背景、30 fps 预览；游戏比较序列为 60 fps。旧失败和中断渲染日志保留在独立构建目录；完整 517 帧已经补齐。

最终独立 stage / Web 为 `stage-20261011-023507` / `web-20261011-023507`，外部可重建目录 `/Volumes/AgentDev/Builds/shu-sword-mocap-v1/`。本机入口 http://127.0.0.1:8791/，构建哈希在 QA 收据，未 commit／push／PR／merge／部署。

## 已测成本与未决事项

21 张图集 PNG 共 9513066 bytes，GLB 705744 bytes；对照 PCK 约 10.2 MB，Godot WASM 39514754 bytes（共用引擎）。图集解码 RGBA 215040000 bytes，约 205.1 MiB；不是 GPU 实测占用。序列方案新增动作会增加帧素材，实时 3D 可共用模型增加骨架曲线；尚未做逐方案 FPS／GPU 内存、手机、Windows 实机或长时基准，不能据文件大小宣称哪路更快。

灰模采用源成人比例，尚未制作江砚秋 Q 版模型、衣服与水墨材质，也未做重定向、双手 IK、脚掌锁定或专业剑法审校。剑是绑定右手的道具，源数据没有武器标记；腕向与握剑需要后续专门修整。源身体朝向变化约 140°，固定斜镜头能看见背面，不能宣称已经完成任意 180°／360° 招式。真实人体动作有参考价值，不等于考证过的中国剑法。

当前灰模效果已获用户认可。下一建议切片：沿用这段动作制作江砚秋 Q 版造型，并校准握剑、脚步和衣服表现，再用同源 B/C 比较选择输出方式；此项仍是建议，不把本次灰模反馈升级为最终角色、全部剑法或 B/C 路线决定。不采购或增加新玩法。

## 可重建入口

复用锁定的 Godot 4.7.2 和已安装的 Blender 4.5.9 LTS，不需要安装运行时插件；下面 `$study_output` 为可重建输出目录。本机重型命令应通过 `agent-dev run --`，按 workstation 约定检查外部卷。

```sh
python3 -B -m unittest discover -s tests -p test_cmu_motion.py
blender -b --python tools/sword_mocap/make_study.py -- --repo "$PWD" --output "$study_output" --mode build
blender -b --python tools/sword_mocap/make_study.py -- --repo "$PWD" --output "$study_output" --mode render
godot --headless --path . --script tools/sword_mocap/pack_atlas.gd -- "$study_output/frames" "$PWD/assets/art/sword_mocap"
python3 tools/sword_mocap/build_study.py --output "$study_output" --godot godot
# 在输出收据中的 stage 中运行：
godot --headless --path "$study_stage" --script tests/sword_mocap_comparison_test.gd
godot --headless --path "$study_stage" --script tests/sword_mocap_import_test.gd
godot --path "$study_stage" --script tests/sword_mocap_render.gd -- --output "$study_output/qa"
python3 tools/sword_mocap/serve_preview.py --directory "$study_web" --port 8791
```

字体使用单独 OFL 子集，200 个字符、无缺字；现有字体不变。重新生成字体时按 `source-sword-mocap.json` 验证原字体 SHA，使用 `rebuild_font.py` 与已安装的 fontTools；运行小样无需下载字体。

后续造型研究追记（2026-10-11）：用户认可本灰模后授权同段江砚秋候选，见 [SWORD_JIANG_STUDY](SWORD_JIANG_STUDY.md)。本灰模模型／图集与8791导出保持，造型和最终B/C选择仍待用户判断。
