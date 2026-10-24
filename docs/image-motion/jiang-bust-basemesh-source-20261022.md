# 江砚秋胸像建模基模来源与许可

记录日期：2026-10-22。本文记录 Codex 自行制作江砚秋胸像时拟用于重塑的通用角色基模来源，不表示江砚秋模型已完成或通过验收。

## 官方来源与本地文件

- Blender Studio 官方角色页：[Snow v3](https://studio.blender.org/characters/snow/v3/)。页面将其标为 Free、Blender 3.6 LTS、License: CC-BY，并说明这是 Blender Studio 制作的通用角色绑定，可用于动画学习与练习。
- 页面提供的官方压缩包：[snow_v3.zip](https://studio.blender.org/download-source/files/ca/cab3fc59bce48d1b8090109016ac16f0/cab3fc59bce48d1b8090109016ac16f0.zip)。页面标示大小 106.0 MB；本地压缩包为 111,158,458 字节（约 106.0 MiB）。
- 解出的源工程：`.local/qa/jiang-bust-20261022/snow-source/snow_v03.blend`。
- 压缩包：`.local/qa/jiang-bust-20261022/snow_v3.zip`，SHA-256：`c2d535baa485134bb5a3f6fe9e281645b60f7f5f7a41a1300de5296ae5cd1ca8`。
- `.blend` 文件：`.local/qa/jiang-bust-20261022/snow-source/snow_v03.blend`，SHA-256：`32644051c0ea512f61df0d98f0cfbb045716ee315c7c3609b77d0c7ba23d2719`。

## 许可与署名

Blender Studio 页面标注 CC-BY，并要求使用者遵守该许可及提供以下署名：**Snow Rig © Blender Foundation | studio.blender.org**。许可文本：[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)；官方 Snow v3 页面是该素材及页面署名要求的来源。

当基模实际被改动并形成衍生文件时，随交付保留上述署名，并标明修改事实、修改者和修改内容；不要将第三方基模的原始部分说成 Codex 原创。建议成品记录采用“Snow Rig © Blender Foundation | studio.blender.org — CC BY 4.0；由 Codex 为江砚秋胸像修改，修改内容：……（日期：……）”并在省略号处填写已实际完成的改动。此处只是署名格式建议，不宣称当前已产生衍生模型。

## 与江砚秋作品的边界

Snow 是通用第三方角色基模，作为 Codex 重塑江砚秋胸像的建模起点；它不是项目原画、胸像概念图，也不是最终的江砚秋角色。江砚秋身份、脸部与发型设计、服饰和最终风格需由 Codex 按[胸像目标](jiang-bust-art-brief-20261022.md)重新制作。既有程序化胸像仍是未完成候选，不能据此声称已将 Snow 基模整合进模型、已完成最终拓扑／UV／绑定，或已获得用户造型认可；Snow 自身拓扑、UV 与绑定对最终用途的适配性也尚未在本记录中评估。

已知处理边界：打开文件时不执行其中 Python 脚本，几何／材质复用不依赖安装附加组件。后续检查或变更应继续保持脚本执行禁用，并分别记录任何实际改动及其来源。

## 后续实际使用（同日）

上述记录写于检查前。实际整脸重塑试验未采用；最新 `refined-v7` 候选只从 Snow v3 裁切耳壳网格，缩放、调整位置并重着色。脸、眼眶开口、眼球、发型、马尾、布带和服装由 Codex 本地构建器制作，没有使用 Snow 原贴图、绑定或动画。修改日期为 2026-10-22，修改者为 Codex；准确署名为：**Snow Rig © Blender Foundation | studio.blender.org — CC BY 4.0；耳壳由 Codex 裁切、缩放并重着色。**

主交付 `.blend` 的场景属性和耳部对象保留来源及修改声明；审阅板、HTML、收据与 source/ 中保留同一署名。source/ 另存原始 `.blend` 供复现溯源；该原始文件包含官方脚本，复现时继续使用 `--disable-autoexec`。主候选保存前清除外部未使用数据与嵌入脚本，不将原始源工程当作安全清理后的主候选。静态候选及剩余美术差距见[本轮模型记录](jiang-bust-refined-20261022.md)。
