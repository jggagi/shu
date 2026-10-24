# 江砚秋胸像：Codex 自行制作修订

日期：2026-10-22。用户指示「我要你来做」，由 Codex 负责实际模型制作，停止外包筛选。此轮是静态胸像候选，仍需用户审阅造型，不是最终角色或动画交付。

## 本轮实际改动

- 独立制作圆润少年脸，眼部在脸上有真实开口，配套完整立体眼球、曲面虹膜、瞳孔与眼皮／上眼线；统一模型而非分视角生成图。
- 新建宽窄分层的扫发、鬓角、长马尾根部与垂落发束、薄布带；补后颈头发。
- 重建白色内袍、蓝色无袖外衣、交领叠压、圆肩衣袖和固定空间的衣料色差。
- 整脸 Snow 基模重塑试验（`refined-v1` 至 `refined-v3`）因成熟脸型与穿插未采用。最终仅裁切、缩放和重着色复用 Snow 的耳壳网格；脸、眼、头发和服装由本地构建器制作。准确署名与哈希见[来源记录](jiang-bust-basemesh-source-20261022.md)。

## 当前产物

工作目录：`.local/qa/jiang-bust-20261022/`（忽略目录；保留所有旧版）。

- 最新构建：`refined-v7/jiang-bust.blend`。
- 正面、38 度侧面、90 度侧面和背面各一张上色及灰模 PNG，共八张，均为 1400 × 1400、同灯光、相同正交尺度 2.8。
- 审阅包：`refined-review-v7-clean/bust-review.png`、`index.html`、`source/`、`sha256-manifest.json`。
- 构建器：[build_bust_refined.py](../../tools/hero_lookdev/build_bust_refined.py)，基础几何工具：[build_bust.py](../../tools/hero_lookdev/build_bust.py)，包装：[package_bust_review.py](../../tools/hero_lookdev/package_bust_review.py)。
- 原画和二维目标仅作为身份与美术参考，未投射成替代脸部结构的图卡。

复现前从来源记录的官方链接取得 Snow v3，并核对源 `.blend` 哈希。使用既有 Blender 4.5.9 LTS；不更改 Godot 项目版本。本地命令（其他机器使用自己的 Blender 启动路径）：

```sh
Blender --background --factory-startup --disable-autoexec --threads 4 --python-exit-code 1 \
  --python tools/hero_lookdev/build_bust_refined.py -- \
  --base .local/qa/jiang-bust-20261022/snow-source/snow_v03.blend \
  --output .local/qa/jiang-bust-20261022/new-candidate \
  --reference assets/art/v2/jiang-yanqiu-v2.png \
  --concept art/work/jiang-bust-target-20261022/concept.png
python tools/hero_lookdev/package_bust_review.py \
  --render-dir .local/qa/jiang-bust-20261022/new-candidate \
  --output .local/qa/jiang-bust-20261022/new-review
```

构建和包装均拒绝覆盖已有输出。Mac 重型任务按工作站约定先检查卷身份，再用 `agent-dev run --` 启动。

## 验收边界

本轮针对真模型结构、灰模替换、文件重开和渲染一致性检查。肤色、虹膜及衣料均固定在几何／材质中，没有逐帧生成；这不等同于动画稳定性已经实测。

外观仍有差距：眼型与神态、发束的自然流动、衣褶和手绘笔触还未达到二维目标的细腻程度。此版是可编辑的继续修改基础，未认定为专业美术终稿。没有动画用拓扑验收、UV 贴图交付、骨骼绑定、全身衔接或两秒持剑转身；静态造型确认后才进入下一阶段。
