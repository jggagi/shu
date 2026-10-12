# 江砚秋 · 双手扎棍 · input-v1

本卡记录此招式的输入、生成尝试和当前验收边界。`shot_id` 保持稳定；没有成功生成的主角动作片段。

## 当前状态（2026-10-12）

本地角色参考与 4 秒灰模指南已准备。官方 ModelScope 上两次获授权、零付费的生成提交都返回 `FAILED`，没有可下载的视频，也没有主角透明帧或场景接入。两份回执没有暴露失败原因；不从诊断编号推测原因，也没有第三次提交记录。

| 尝试 | Task ID | 状态 | 诊断编号 | 输出 |
| --- | --- | --- | --- | --- |
| 首次提交 | `ed96c8b6-272c-43b5-a0c4-d8f4f4ef7680` | `FAILED` | `e596a8a6cbf94832b9b63d92a6881f05` | 无；`download_status=no_output` |
| 用户授权的一次额外提交 | `40802fc0-575c-4e70-8aca-77b0dafd6055` | `FAILED` | `849ffe003586496d885a82c0800477fe` | 无；`download_status=no_output` |

回执记载的平台任务均为 Wan-Animate-2、`wan2.2-animate-move`、`wan-pro`；精确上游修订与 seed 未记录。成本字段是 `max_paid_cost: 0`；没有单独账单凭证可据此推断平台侧费用情况。

## 输入与动作意图

目标为溪边茶亭独立研究。沿用江砚秋棕发高马尾、浅蓝发带、白袖蓝袍和布靴；一根1.80m直棍，两手沿棍轴相距0.34m，左右肘由IK求解，无换手。原30fps动作每2帧取样：起势0–0.85s，进步发力约1.0–1.75s，回棍退步2.25–3.2s，3.2–4s收势。固定正交镜头，保持真实进退与抬脚，不逐帧把最低像素锁地。以上是输入合同，尚无生成结果可验证。

- **角色参考：** `.local/qa/hero-martial-three-v1/inputs/staff/reference.png`，来源名 `staff-reference-v1.png`，1254×1254，SHA-256 `6cf1dd766fa623b5e87a71df7797c50f638449dfc86aef18a911d5542759fca9`。
- **动作指南：** `.local/qa/hero-martial-three-v1/inputs/staff/motion-guide.mp4`，512×512、15 fps、60 帧、4.0 秒、H.264/yuv420p，SHA-256 `2c846636c36416ee81eeb4fd5ead7027635bbc94aa73ef604bd1d4909918e687`；完整解码已验证。
- **指南来源：** 原创程序化动画 `assets/data/animation_lab/motion.json` 的 staff 段；它是灰模动作参考，不是人体捕捉或主角成片。制作记录描述了起势、前进扎棍、回棍和末尾停势；生成失败后无法核验主角动作是否遵循该节奏。
- **工作招式标签：** 双手扎棍／向前扎棍。双手共握一根棍是输入规格中的动作意图，不是生成结果观察；实际手与棍的接触、连续性及动作自然度均未验证。
- **角色参考状态：** 本地 imagegen 角色图仍是制作候选，未记录最终美术认可。

本地 imagegen 角色参考的精确提示词在 `art/prompts/hero-martial-staff-reference-v1.txt`。用户授权记录及输入包在 `.local/qa/hero-martial-three-v1/retry-authorization.json`、`.local/qa/hero-martial-three-v1/inputs/staff/metadata.json` 和 `.local/qa/hero-martial-three-v1/jobs/staff.json`；额外一次授权原话为「允许额外重试一次」，第二次结果见 `.local/qa/hero-martial-three-v1/jobs/staff-attempt2.json`。两次输入的参考图及指南哈希相同。

## 处理与验收边界

- **透明帧／atlas：** 未执行；没有生成源片可供抠像。`assets/art/hero_martial_v1/jiang-staff-forward-thrust-v1/` 当前不存在。
- **场景、锚点、接地与播放：** 未集成或验证；没有 Godot、Web、Windows 或用户试玩验收。
- **仍未知：** 两次失败的服务端原因、精确模型修订、seed，以及生成后握持与棍身轨迹。诊断编号仅用于对应回执，不能单独说明原因。

本地输入与任务证据目录：`.local/qa/hero-martial-three-v1/`。两份结果回执分别为 `.local/qa/hero-martial-three-v1/jobs/staff.json` 与 `.local/qa/hero-martial-three-v1/jobs/staff-attempt2.json`。
