# 听雨廊：环境声音 v1

客户端日期 2026-10-06。用户同意先做雨声与檐滴两层。本地延续 `codex/tingyu-ambient-life-v1`，源码基线 `0589f5e`；保留此前猫、阵风、檐滴与黄昏灯光，声音本轮待用户试听认可。

## 试玩

1. 顶部中间点击「开启声音」。右侧滑条调环境音量，默认 45%；左端为零音量。
2. 按 `9` 切到小雨，等天气渐入及檐水积累。按 `7` 晴，雨声退去后还会有少量实际余滴声。
3. 请教师傅，环境音降低；取消后恢复。`4` 切 Static 渐静，再次按恢复。
4. 「关闭声音」淡退雨底并清除短滴；重新开始清空播放历史，保留本次玩家开关和音量选择。刷新／新开应用则声音初始关闭。

## 已实现

- `scripts/tingyu_ambient_audio.gd` 为独立场景播放 adapter，只读 weather presenter 的连续 rain_amount、实际檐滴 release、既有 weather elapsed、Busy 和场景可见性；不改变 DemoState、天气权威或共享 Presenter。
- 每次画面 release 以明确锚点、起始 elapsed 和 fall_seconds 排一个 impact。到当前下落约 88% 时播放短滴；雨停后三个视觉余水事件也走同一入口。大帧跳过已错过超过 0.25 秒的事件，避免集中补播。
- 声音启动、音量变化和雨退去有平滑包络。Busy 相对音量约 35%。Static 渐退雨底和正在响的短滴，短滴自然完成；尚未到达的声音机会保留在冻结的 weather elapsed 上。恢复时不补播已响短滴。
- Mute／音量零／听雨廊不可见会清 pending 与瞬态；雨底渐退。进入《两盏茶》不沿用廊下雨声。Reset 清 pending、播放、fade 与 serial，保留用户的本次声音选择。
- 初次加载不自动播放；按钮直接触发播放。使用预生成 WAV，与现有单线程 Web 默认 Sample 路径配合，不在 Web 运行时合成或依赖 AudioEffects。浏览器开启音频要求用户交互，见 [Godot Web audio](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#audio)。播放与音量行为参照 [AudioStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html)，循环参数参照 [AudioStreamWAV](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html)。

参数在 Tingyu profile 的 `ambient_audio`，属于可调制作参数。首次声场只覆盖听雨廊，不增背景音乐、雷声、配音或新动物声。

## 素材与制作

使用既有 `game-painted-scene-build` 维持环境附着宿主和小切片方法，`tiered-coding` 的真实 Luna worker 只制作生成器／音频，随后只读审核。根代理负责播放接口、落滴同步、UI、集成与运行观察。审核指出 Static 直接暂停短滴会打断声音；已改为短尾淡退完成。没有 skill 或 addon 更新。

`tools/make_tingyu_audio.py` 仅 Python 标准库、固定 seed，生成项目原创合成小样；没有外部录音、下载或第三方采样。素材随项目保存：24 kHz／stereo PCM16，16 秒循环雨底、两种 0.45 秒短滴。雨底 RMS 约 0.13、peak 0.45282；短滴 peak 0.336。脚本、算法说明、工具作者、版本、来源及 SHA256 位于 `assets/audio/tingyu/source.json`，可在根目录运行 `python3 tools/make_tingyu_audio.py` 复现。主观“像不像自然轻雨”仍是玩家试听门槛，不以这些数值代替。

新增「声音／音量／檐滴」汉字不在旧 Serif 子集中，复用既有原字体和 fontTools 4.51.0 重建，无依赖安装；来源记录更新派生 hash，生成工具自动记录真实 fontTools 版本。

## 本轮证据与边界

Godot 4.7.2 / Apple M4 / Compatibility 真实窗口使用原按钮回调，按真实 delta 录制引擎内部 Master 输出；不是麦克风或系统录音。实际画面已人工查看声音控制、师傅对白、Static、雨后、Tea 隐藏和 Reset。证据在 `.local/qa/tingyu-audio-v1/`，含截图、`actual_mix.wav` 与从混音截出的 `rain_and_drops_preview.wav`。

实际轨迹记录：初始关闭无播放；开启小雨后 rain gain 约 0.2511，师傅 Busy 约 0.0908；雨停后 rain_amount 归零，仍有三个由余水 release 驱动的短滴，之后 loop 停止；Reset 清 serial 和 pending、保留 enabled 和 volume。混音有非零雨声／短滴，实际记录 peak 约 0.17569，初始关闭及晴天安静片段为零。该数据证明引擎生成了音频，不能证明用户的扬声器、耳机或听感验收。

锁定引擎的资源导入与单线程 Web 导出完成；初次类型推断与导出目录错误已修复。本机 in-app 浏览器实际加载并点击声音按钮、切小雨、调整滑条及静态；截图与控制台观察范围单独记录，不能声称跨浏览器声音已全部验收。

此轮没有新增或运行自动测试，之前 suite 不代表最新音频版本。Windows、其它浏览器、手机、设备声音输出与长时运行尚未验收。用户试听认可仍待完成。本轮未 commit、push、PR、merge 或发布。
