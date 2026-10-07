# 听雨廊：黄昏灯暖起来

客户端日期 2026-10-06。用户同意黄昏灯火提案，延续本地 `codex/tingyu-ambient-life-v1` 切片。此前檐滴获用户“很好”反馈；灯火本轮仍待玩家视觉认可。

## 玩家可观察的变化

- 白天保持原画；申时微亮，酉时右侧灯罩在约 1.6 秒内渐暖。
- 灯旁案几和猫带轻微暖色，窗外远山稍偏冷，形成廊内外层次。人物脸和对白保持可读。
- Dynamic 使用既有环境 elapsed 产生约 ±3.5% 的缓慢灯火起伏；师傅对白、修炼与 Tea Busy 时起伏收敛。Static 保留灯光并冻结起伏，恢复后连续。主动时辰切换仍按已有 Static 合同过渡。
- Reset 清除灯火呈现历史并回到卯时；玩法、精力和时间推进仍归 DemoState。

试玩：从重新开始点“廊下休息”五次（键盘 `3`）到酉时，等待约两秒。按 `9` 看雨夜，按 `7` 看晴天；`4` 对照动态与静态。猫维持已有自然低频安排，此操作不保证立刻出现。

## 实现边界

现有 `game-painted-scene-build` + `tiered-coding`：Luna 只修改 ambient 着色器灯光区域，根代理接时辰、猫 tint、冻结、重置和画面调参。没有新增美术、声音、skill 或 addon。

`tingyu_environment.json` 的 `lantern_light` 管场景参数：六时辰强度、1.6 秒过渡、灯罩中心 `(1368,403)`／半尺寸 `(24,58)`，木面暖色中心 `(1368,428)`／半径 `(235,108)`。这来自当前 Tingyu 原画的真实位置，属于可调制作参数。酉时 sky tint 调为冷灰蓝，与原来的 world tint 配合；未将其升级为永久 SPEC。

`weather.gd` 观察 EnvironmentPresenter 的实际 profile id，在场景 adapter 内过渡 lamp scalar，避免扩共用 presenter 的固定 compose 接口。重复 `_refresh` 不重启同一时辰的渐变；没有第二 gameplay 时钟。灯火起伏只读已有 elapsed，并缓存 Static 时刻的值。

`ambient.gdshader` 在既有 grading 后以柔边纸罩遮罩和原图亮度 gate 保留深色灯框／笔触，再做有界椭圆暖色衰减；保留 texture alpha，不画图像外的光晕。灯罩 core 只启用在 backdrop。猫 sprite 单独读同一区域的暖色，父节点淡入淡出透明度保持原逻辑。

## 本轮实际证据与剩余项

Godot 4.7.2 / Apple M4 / Compatibility 实际窗口预览已捕获并人工查看午时、申时、酉时 0.4／0.8／1.6 秒渐变、灯光 shader 关闭／开启的诊断对照、酉时小雨、Static／Dynamic、真实师傅按钮对白与 Reset。

日志记录：酉时 lamp scalar 依次 0.308125、0.59、1；Static 前后 elapsed 都为 9.6、flicker 都为 1.00058567，Dynamic 同帧保持该值后继续；Reset 回卯时，lamp=0、flicker=1。最终实际窗口日志无错误。暖色初版在整幅画面中过弱，根代理据渲染增大木面暖色，并重新捕获最终参数。

证据存 `.local/qa/tingyu-lantern-v1/`；实际预览脚本使用真实 `_rest()` 推进时辰，手动 delta 定位渐变，猫只在预览中 force 便于对照。灯光禁用对照属于诊断，不是玩家新增开关。这些是渲染预览与人工审阅，不等同于用户完整试玩。

此轮没有新增或运行自动测试；此前 suite 是旧版本历史结果。Windows／Web 导出、声音、长时运行与玩家认可未验证。未 commit、push、PR、merge 或发布。

下一验收点：灯罩暖起来是否容易察觉，木面／猫是否自然，以及黄昏是否仍保留宋画质感。
