# 动作方案对照实验（探索中）

本实验比较三条零付费路径：Godot 原生 2D 骨骼动画、Blender 烘焙成 30 fps 图片序列、Blender 导出 glTF 后在 Godot 实时播放。它们共用一份原创动作研究数据，便于先看表现与制作路径差异；目前没有选出最终方案，也不是产品定稿。

## 对照边界

所有路径共用同一关节动作、固定正交镜头和三段动作：**弓步直刺、转身斜劈、双手棍法**。2D 是独立纸片造型，B/C 是同一圆润的 3D 研究模型；两种美术完成度不同，不能仅凭造型给工具下结论。源数据是 30 fps、每段 4 秒的程序化关节姿态研究；不读写 DemoState 或其他养成／战斗状态。角色是对照用的简化原创模型，不是江砚秋最终美术；动作只用于表现比较，不代表已经考证或认可的武术身法。

| 路径 | 当前方案 | 零成本判断与限制 |
|---|---|---|
| Godot 原生 2D | `Skeleton2D` / `Bone2D` 层级，由 `AnimationPlayer` 播放同一源动作。 | **可直接做对照**：Godot 内置能力，无额外动画运行时。已通过实际原生与 Web 渲染／输入检查，最终美术仍待决定。见 [Skeleton2D](https://docs.godotengine.org/en/4.7/classes/class_skeleton2d.html)、[Bone2D](https://docs.godotengine.org/en/4.7/classes/class_bone2d.html)。 |
| Blender 烘焙序列 | Blender 按 30 fps 将同一动作渲染为透明 PNG 序列，再由 Godot 播放。 | **工具免费，运行代价是帧素材**：可作为最简单的离线动画路径；序列占用资源且不能像骨骼那样直接改姿态。实际帧、图集、Web 播放已检查，规模代价见下方证据。见 [Blender 4.5 glTF/动画手册](https://docs.blender.org/manual/es/4.5/addons/import_export/scene_gltf2.html)。 |
| Blender → glTF 实时 3D | Blender 生成骨架角色和动画，导出 `.glb`，Godot 实时导入播放。 | **可直接做对照**：Blender 免费，Godot 推荐 glTF 2.0 场景格式；已核对实际骨骼姿态、武器切换与 Web 表现；材质和灯光仍为研究级。见 [Godot 3D 格式说明](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)、[Blender 许可](https://www.blender.org/about/license/)。 |

## 可复现入口

源姿态与片段定义在 `assets/data/animation_lab/motion.json`，由 `tools/animation_lab/make_motion.py` 生成。原生路径见 `scripts/animation_lab/native_actor.gd` 与 `scripts/animation_lab/comparison.gd`；演示场景为 `scenes/demos/animation_lab.tscn`。Blender 构建和渲染脚本是 `tools/animation_lab/make_blender_demo.py`，GLB 保留 Blender 第一帧的 `1/30` 秒时间原点，实时适配器补偿该偏移，并采用手动 AnimationPlayer 时钟；三个方案同一时刻对应同一源姿态。Godot 图片序列图集脚本是 `tools/animation_lab/pack_atlas.gd`。独立暂存／Web 导出入口为 `tools/build_animation_lab.py`。

```sh
python tools/animation_lab/make_motion.py
blender -b --python tools/animation_lab/make_blender_demo.py -- --repo "$PWD" --mode build
blender -b --python tools/animation_lab/make_blender_demo.py -- --repo "$PWD" --mode render
godot --headless --path . --script res://tools/animation_lab/pack_atlas.gd
python tools/animation_lab/verify_sources.py
# 主工程中的本地场景入口
# godot --path . res://scenes/demos/animation_lab.tscn
# 独立暂存并导出 Web（按需传入本机 Godot 可执行文件）
# python tools/build_animation_lab.py --godot godot
```

Blender 输出目标为 `assets/art/animation_lab/model.glb` 和 `assets/art/animation_lab/blender_frames/`；Godot 图集由 `tools/animation_lab/pack_atlas.gd` 生成。构建前需要已有的 Godot、Blender 命令；本实验没有安装工具或引入付费依赖。

## 其他工具：零成本可行性与门槛

- **Synfig**：软件免费开源，可制作骨骼动画并烘焙渲染，技术上能作为预渲染候选；本机未安装，也没有本实验演示。其文档所列 Lottie 导出尚不支持骨骼动画，因此不把它描述成已验证的 Godot 骨骼管线。[Synfig](https://www.synfig.org/)、[Lottie 导出限制](https://synfig.readthedocs.io/en/stable/export/export_for_web_lottie.html)
- **DragonBones**：官网仍写有 DragonBones Pro 免费下载；官方 GitHub 有 MIT 许可的 Godot 4 扩展。但编辑器下载信息较旧，扩展是否兼容本项目锁定的 Godot 4.7.2 尚未验证；免费工具、运行时代码和样例素材的许可也应分别核对。[下载页](https://dragonbones.github.io/en/download.html)、[Godot 扩展](https://github.com/DragonBones/Godot-DragonBones)
- **Spriter**：官方 Free 版页面列出的 Windows 版本为较早的 R11；本机没有已验证的 macOS 工具链。社区 SCML 导入器说明测试范围至 Godot 4.6，4.7.2 兼容性未验证，且有格式／插值限制。免费编辑器、MIT 导入器和示例素材是不同许可对象。[Free 下载页](https://brashmonkey.com/forum/index.php?/files/file/13-spriter-free-windows/)、[社区导入器](https://github.com/wojtossfm/godot_scml_importer)、[素材 EULA](https://brashmonkey.com/spriter-elua/)
- **Spine**：官方试用版不能保存工程或导出动画；官方网页演示与导出样例可用于观察和评估运行时。试用许可不允许把 Spine Runtime 集成进本实验；若未来要制作可导出的 Spine 资源或集成运行时，须另行决定是否采购有效编辑器许可，并按官方许可约束集成与分发。[试用版](https://us.esotericsoftware.com/spine-download)、[演示](https://us.esotericsoftware.com/spine-demos)、[许可](https://us.esotericsoftware.com/spine-editor-license)
- **Moho**：Pro 试用版不能导出动画到其他格式。免费源文件包面向 Moho Pro 14.4 持有人，因此不能作为当前零成本导入路径；公开电影样例只够观察外观。[试用版](https://moho.lostmarble.com/pages/try)、[源文件包条件](https://moho.lostmarble.com/products/moho-144-free-moho-source-files)、[影片样例](https://www.lostmarble.com/moviesamples.html)

当前不购买 Spine、Moho 或其他付费工具。若要评估其可编辑导出与项目内运行，应另开采购／许可决策；免费样例可看不等于可以把样例或运行时打包分发。

## 实际证据与交付

基线 `ed6ece9e371ae3e2b3ffbb447f659513e4a3094b`，独立 worktree `animation-options-lab/shu`，分支 `codex/animation-options-lab`。原 M2 的 `8777` 试玩保留；实验只在本机 [8778](http://127.0.0.1:8778/) 提供对照，未公开发布。

- Godot 4.7.2 Compatibility 真实原生渲染：1152×720 与 960×600，三段动作的 1.4 秒姿态，截图 `native-{thrust,cut,staff}.png` 与 `native-960-{thrust,cut,staff}.png`。
- `tests/animation_lab_test.gd`：最终导出同一暂存工程 **2,365 检查／0 失败**，检查真实 Skeleton2D 蒙皮路径／权重与渲染接触点、真实 Skeleton3D 姿态、三个 GLB action、120 帧图集索引、同步 seek／暂停／逐帧／循环／速度／单看／背景。
- `tools/animation_lab/verify_sources.py`：**13,704 检查／0 失败**，源骨长、闭环、握棍、图集、导出结构；两个原有 checkout 的 145 个保护文件哈希一致。
- Blender 完整渲染 **360 RGBA 帧，30 fps，每段 4 秒，171.021 秒**；全帧无镜头裁切，staff 最小边距 4 px。记录在 `assets/art/animation_lab/blender-source.json`。每段 121 个源样本含闭环端点，运行序列为 120 帧。
- 独立 Web 导入／导出退出 0，日志无引擎错误。完整工程初次并行字体导入曾崩溃，独立暂存工程固定串行导入后通过；正式 `project.godot` 未修改。
- 真实 IAB Web：鼠标播放／暂停、半速／四分之一速度、素纸／后山、时间轴、单看 C／并排；键盘换剑／棍、重看、逐帧。实际捕获视口为 685×428，不把申请的视口值当作真实尺寸。控制台 warning/error 空。
- 证据目录 `.local/qa/animation-options-lab/`：`runtime-checks.log`、`source-checks.log`、`build.log`、`final-native.log`、`small-native.log`、`web-{staff,paper,solo-c,playing}.jpg`、`web-input-notes.json`、`blender/` 渲染证据。`.local` 不进 Git。

12 张运行 PNG 图集共 **12,301,698 bytes**；GLB **807,340 bytes**。对照 Web PCK **13,366,232 bytes**，WASM **39,514,754 bytes**（引擎，共用开销，不能算在某一个方案头上）。图集未压缩 RGBA 约 **202.5 MiB**，显示了序列路线随招式数量增长的内存代价；GLB 文件小不等于其实际运行内存数字。没有完成逐方案独立 FPS、GPU 内存或移动设备基准。

`.blend` 为可重建的本地 QA 中间产物；360 原 PNG 被精确忽略，运行图集、GLB、原创源脚本和来源记录随项目管理。字体是已有 OFL Noto Serif SC 源的独立子集，来源及 SHA 见 `assets/fonts/source-animation-lab.json`；无需下载字体即可运行现有 demo。

## 已观察到的取舍与下一判断

- A 保持二维纸片观感，动作由原生骨架连续播放，衣袖真实蒙皮；脸朝向和前后遮挡仍是简化造型，需要逐视角美术与网格权重打磨。扩招式可复用骨架，但不能期待同一侧面图自动完成可信的背面。
- B/C 使用相同 3D 角色与动作，转身可显示背面且双手持棍有共同骨架约束；B 保留 Blender 光照，C 使用 Godot 灯光，画面并非像素完全相同。
- B 运行路径简单、固定美术效果稳定；每新增招式会增加帧素材。C 具有直接重定向与换镜头的基础，但还要解决与水墨背景的材质融合，并验证目标 Web/Windows/移动设备表现。

研究动作还没有真人参考、动作捕捉、专业身法审校或衣物模拟。真实角色的高质量分层美术／建模／绑定／动作设计仍然需要制作投入，工具免费不能代替这些工作。没有接入正式练剑或修改 M2 结算。用户试玩与最终路线选择 **尚未完成**；预算确认只授权零付费探索，购买另行确认。


## 发布授权（客户端日期 2026-10-08）

用户明确要求「推到 GitHub pages」。本轮将源码保存到 `codex/animation-options-lab`，将同一已验证 Web 导出部署到独立 `/animation-lab/`。远端 Pages 和 `gh-pages` 曾被移除；从历史最后发布快照恢复，旧根入口与 `/back-mountain/` 文件保持字节一致。该授权不表示最终动画路线已选定，不合并源码 main。公开构建绑定源码 SHA、运行文件哈希与 Godot 版本，带 Godot/OFL 许可和原创来源；实际部署结果记录在本地 release 收据与线上 `animation-lab/build-info.json`。
