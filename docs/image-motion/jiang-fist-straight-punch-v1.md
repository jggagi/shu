# 江砚秋 · 站桩冲拳 · input-v2 / source-v2

本卡沿用稳定 `shot_id` `jiang-fist-straight-punch-v1`，并保留 input-v1 的拒收记录。input-v2已完成透明图集、后山研究入口、原生检查与Web导出；Web实际UI、Windows和用户最终质量验收待完成。

## 当前状态（2026-10-12）

input-v2源片及53帧透明图集已生成。自动校验通过；Root对5帧做480方格浅／深底检查，用240方格序列表查看全部53帧，未见明显残留底色、裁切或光晕。独立后山入口已做两窗口原生渲染和行为检查；Web导出成功，但实际UI检查因工具超时后浏览器安全策略阻止恢复而未完成。

| 阶段 | 结果与证据 |
| --- | --- |
| input-v1 生成 | 成功，Task ID `ce9c7f32-2cb2-4cb8-98cd-8ec2b787d482`；源片因开场高马尾与画面上边相交并被裁切，拒绝用于抠像。 |
| input-v2 生成 | 成功，Task ID `cc4926bd-7caa-4474-84a8-65e9029e7800`；输入为修正留白的参考图和同一动作指南。 |
| source-v2 自动抠像与图集 | 已生成；自动逐帧、图集、哈希及透明角校验通过，详见 `.local/qa/hero-martial-three-v1/jobs/fist-v2-alpha-validation.json`。 |
| 人工透明帧检查 | 帧0／13／26／39／52做480方格浅深底检查；另以240方格四张序列表查看全部53帧。 |
| scene/runtime | 原生295项行为检查0失败；36项真实渲染检查、14张图，Web导出成功。 |
| Web实际UI／Windows／用户认可 | Web最后检查未完成，Windows／用户认可未验收。 |

## 输入与版本沿革

本招式目标为后山独立研究，沿用棕发高马尾、浅蓝发带、白袖蓝袍、布靴的江砚秋身份，空手，无新增道具。灰模由CMU02_05的源帧65–313逐8帧采样为32格／15fps，固定正交镜头。动作意图为站定前送、躯干转动与回拳；单次播放，末帧保持，不声明为首尾连续循环。画景用固定首帧源锚点和统一尺度，保留源片位移，不按逐帧诊断脚点抹平身体动作。

### input-v1（保留为拒收样本）

- Codex 内置 imagegen 角色参考 `.local/qa/hero-martial-three-v1/inputs/fist/reference.png`，来源名 `fist-reference-v1.png`，1254×1254，SHA-256 `84f56b2908eb295add9051cca6fc492a33ccdad2fc7319c0902649e5bf06a829`；提示词在 `art/prompts/hero-martial-fist-reference-v1.txt`。
- 动作指南 `.local/qa/hero-martial-three-v1/inputs/fist/motion-guide.mp4`，512×512、15 fps、32 帧、2.133333 秒，SHA-256 `7187388732b2129c2c9e28df44a61dd296654cde30a83d126c545146d689ca72`。
- 生成源片 SHA-256 `555371a9364a84e222f09858353a9af58741c0f630dec80ff4b0c072d7d3af74`；H.264/yuv420p、960×960、25 fps、53 帧、2.12 秒，完整解码通过。
- `.local/qa/hero-martial-three-v1/jobs/fist-source-review.json` 记录查看了第 0、5、10、15、20、25、30、35、40、45、48、52 帧，并以开场高马尾与上边相交、被裁切为由标记 `source_rejected_for_matting`。未尝试用 alpha 或修图掩盖裁切。对应首次生成回执为 `.local/qa/hero-martial-three-v1/jobs/fist.json`。

### input-v2 / source-v2

- 用户看到修正后的 v2 PNG 后，明确允许「上传 v2 并生成一次」：只替换角色参考，沿用同一指南；任务和素材版本记为 `input-v2`，稳定 `shot_id` 未改变。
- 角色参考 `.local/qa/hero-martial-three-v1/inputs/fist-v2/reference.png`，来源名 `fist-reference-v2.png`，1254×1254，SHA-256 `003c64a478558da8f4a0bf38e22d90eb816b2dc5e83dc84d50ec046cb06ea9e9`。精确提示词在 `art/prompts/hero-martial-fist-reference-v2.txt`，文件 SHA-256 `3f745333bb94314243a32c3cf19bd31acf66c3fc395b6fe4803bb7c7c775895a`。
- 复用 input-v1 同一指南，SHA-256 `7187388732b2129c2c9e28df44a61dd296654cde30a83d126c545146d689ca72`。指南记录来自 CMU 全身动作捕捉 `02_05.amc`（源 SHA-256 `b370aae1972be9bf73d49a6c94ca74dda01a5cb5ab2f4cce7f61d4d08ca9a611`）；成人体型，不含武器标记，也未验证中国拳法。它是动作参考，不是江砚秋的最终动作。
- 12 个源片样本的联系表复核记录为 v2 顶部留白已修正；这是源片取景复核，不等同于主角动作或最终美术验收。
- 官方 ModelScope 回执 `.local/qa/hero-martial-three-v1/jobs/fist-attempt2.json` 记录 Wan-Animate-2、`wan2.2-animate-move`、`wan-pro`；Task ID `cc4926bd-7caa-4474-84a8-65e9029e7800`，状态 `SUCCEEDED`。源片 `source.mp4` SHA-256 `28ca3d8d407f7a90453378b68c69fc4b7e5631e54a302c957d032aff203c1c7f`；H.264/yuv420p、960×960、25 fps、53 帧、2.12 秒，时间戳 CFR 与完整解码均已验证。
- 精确上游模型修订与 seed 在回执中为空，保持未知。回执记 `max_paid_cost: 0`；没有单独账单凭证，本卡不推断平台侧费用。

## 透明帧与图集

成品目录：`assets/art/hero_martial_v1/jiang-fist-straight-punch-v1/`。其中 `source.mp4` 保留源片，`source.json` 记录来源、模型与处理信息，`atlas.json` 指向五张 atlas 图。

- 逐帧源尺寸为 960×960；每个图集格为 480×480，`cell_scale=0.5`。53 个帧格按 4 列×3 行、4 px padding 封装为 5 张 atlas；没有插帧或裁切。
- 使用本地 CPU `isnet-anime.onnx`，模型 SHA-256 `f15622d853e8260172812b657053460e20806f04b9e05147d49af7bed31a6e99`；`source.json` 记录未使用网络访问。透明帧仍属于自动抠像结果，人工接受范围见上表。
- `.local/qa/hero-martial-three-v1/jobs/fist-v2-alpha-validation.json` 记录 53 帧已校验：RGBA RGB 与源帧统一缩放相等；图集格与 RGBA 相等；manifest 文件哈希一致；所有帧角点 alpha 为 0；所有帧的四边接触标记为 false；成功任务回执与封装来源相符。整个成品目录共 7,793,279 bytes，含源片、五张图集与两份 JSON。
- Root 复核 alpha 帧0／13／26／39／52的480方格浅深底合成，另查看覆盖全部53帧的`jobs/fist-v2-alpha-sequence-1.jpg`至`-4.jpg`（每底240方格）；未见明显残留背景、裁切或光晕。浏览器Canvas页已核验正常速、半速、暂停／恢复、逐帧到末格与末帧保持。它们不是实际画景或用户最终验收。

## 独立后山呈现

`scenes/demos/hero_martial_fist.tscn`使用新包、空clean_manifest、独立标题与OFL字体子集。舞台1440×900，位置(1010,565)，演员统一尺度0.90，固定源锚点(522,810)×cell_scale=0.5，全53帧同值，不新增锚点平滑。复用后山山色、轻纸感0.85、软接触阴影和环境调制；融合／纸感A/B不改帧时间、几何、锚点或DemoState。

Godot4.7.2 GL Compatibility、Web单线程导入与导出成功；295项行为检查0失败，覆盖帧表、正常／半速、暂停／重播／末帧、Static／Resume、深层状态保持。原生1152×720和960×600共14张图，36项检查0失败，含起／中／末帧、Static像素保持、晴天／酉时小雨及材质A/B；Root查看代表画面。最终证据在`/Volumes/AgentDev/Builds/shu-hero-martial-three-v1/review-fist-final-v1/`的收据、logs与render目录。

Web实际查看只到加载进度，后续工具截图超时、会话重置，恢复浏览器连接被URL安全策略拒绝，未换浏览器或间接控制。不能据原生与Web导出把Web实际UI验收记为通过。[本轮记录](../HERO_MARTIAL_THREE_SLICE.md#两招独立后山预览2026-10-12)保留试玩入口与完整平台边界。

## 尚待验收

- 目标显示尺寸下的细发丝／袖口／拳部边缘质量与动作连续性。
- 用户在真实场景中的接地、遮挡、调色与动作观感；原生行为／渲染通过，Web实际UI、Windows及低端性能未验证。
- 用户对主角动作质量的最终意见。源片成功、自动 alpha 检查及有限样本视觉检查均不代表这一验收已经通过。

相关记录：`.local/qa/hero-martial-three-v1/jobs/fist.json`、`.local/qa/hero-martial-three-v1/jobs/fist-source-review.json`、`.local/qa/hero-martial-three-v1/jobs/fist-attempt2.json`、`.local/qa/hero-martial-three-v1/jobs/fist-v2-alpha-validation.json`、`.local/qa/hero-martial-three-v1/inputs/fist-v2/metadata.json`；封装摘要及图集清单位于成品目录的 `source.json` 和 `atlas.json`。
