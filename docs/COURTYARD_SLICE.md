# 山门庭院 v1 · 独立动态场景切片

日期：2026-10-07（客户端日期）。基线 `origin/main` / `9cab32a52a497e93ac52f3eaa4e71c814b8b30d4`；分支 `codex/mountain-gate-courtyard-v1`。主 checkout 干净但比远端落后6提交，本轮只刷新远端并建立新隔离工作树；已有工作树和 `.local` 保留。未提交／推送／合并／公开部署。

## 体验与范围

静态构图先行：近处老树和铺石，左侧山门与石阶，右侧檐廊石台，远处蓝绿山峰。只有三个动态系统：时辰与天气、同一次阵风带动相关叶簇、一只橘猫短路径休息与轻摸回应。没有新人物、剧情、音频、奖励、时间结算或 addon。

六时辰沿用 DemoState 的语义；宿主默认读真实 `time_index`，显式预览以宿主 `preview_time_index` 提供，不更改 DemoState。天气 clear／cloudy／light_rain 在庭院自己的 profile 中调色：1.6秒时辰过渡、4.5秒天气过渡、2.4秒雨退。UI 在世界调色外。雨 mask 仅支持实际露天铺地、山门开口与远处开口；檐下猫落点和建筑有遮蔽。

风首个机会5秒，持续6.5秒，再静16–25秒；固定seed，强度按当前天气组合。选定叶簇共享阵风包络与时钟，局部UV偏移最多4.5逻辑像素乘当前风强；树干、建筑、石阶和猫路径不动。

猫沿用已认可的原八姿态及桌面六姿态图集，重新绑定檐下上层石台。逻辑路径 `(958,495)→(1066,500)`，位于两根廊柱之间；真实遮蔽属性为true。姿态脚点使用已有cell-local pivot；显示尺度与热点按当前姿态、朝向和世界缩放计算。Static 在当前位置保留安静猫并禁用热点，冻结路径、步态、反馈和出现时钟；Resume 原位接续。轻摸只改变表现与短提示，光标沿用掌心向下v2和 `(8,24)` 指尖热点。

## 启动

```sh
godot --windowed --path . res://scenes/demos/mountain_gate_courtyard.tscn
python tools/build_courtyard.py --godot godot
python tools/serve_courtyard.py --port 8772
```

Web 地址：`http://127.0.0.1:8772/`，仅在此电脑。底部鼠标控制六时辰、晴／多云／小雨、静态／继续动态、重置。快捷键T下一个时辰、7／8／9天气、4动静、R重置。正式 `project.godot` 主入口保持，Web导出工具创建 `.local/build/courtyard-source` 可检查快照，再将主入口覆盖为庭院，输出 `.local/build/courtyard-web` 与逐源文件SHA256 `build-info.json`。

## 素材与方法复用

一张原创庭院构图参考由内置imagegen生成并选入本地切片，没有上传原项目图片，没有Qwen调用。精确提示 [scene-reference.txt](../art/prompts/courtyard/scene-reference.txt)，画景、原创mask、来源与SHA256见 [source.json](../assets/art/courtyard/source.json)。背景不要求透明；两个猫图集沿用实际RGBA、每姿态crop/pivot和原来源，不重生成。制作选用不等于玩家认可。

EnvironmentPresenter复用profile组合和独立平滑过渡，AmbientLifePresenter复用固定seed的机会／居留调度；两个presenter源码不改。庭院各有独立配置与adapter，没有复制整份听雨廊weather／ambient控制器。猫短路径helper经过实际第二用例最小提取，原听雨廊兼容入口保留。具体复用边界与问题见 [庭院案例](../.agents/skills/game-painted-scene-build/references/mountain-gate-courtyard.md)。

## 分层验收

| 层级 | 本轮实际证据 |
| --- | --- |
| 导入／导出 | Godot 4.7.2 stable最终原生导入与单线程Web导出成功；最终导出逐源SHA256与工作树一致。字体重新覆盖761字符，覆盖检查通过。日志 `import-final.log`、`web-build-final.log`，包内 `build-info.json`。 |
| 自动合同 | 根代理复跑 `courtyard_cat_test.gd`，41项通过：两方向接触脚点、稳定宽度、路径、暂停／Busy／轻摸接续、热点与宿主隔离。`cat-focused.log`。 |
| 原生真实画面 | macOS Apple M4 Compatibility/OpenGL实际窗口渲染20张完整捕获、0失败。根代理审核晴云雨、六时辰、阵风前／峰／平静、步态／脚点、Static／Resume／Reset及1200×750视口。完整宿主快照在表现推进前后相同；Static两次图像像素相同。`render-report.json` 与 `render-final.log`。此批捕获加速表现时间，不代替自然频率／长时验收。 |
| Web真实鼠标 | IAB实际画布684×427／视口685×428，鼠标切六时辰预览与晴云雨，实际点击走动中及休息时猫，观察轻摸姿态和提示；实际猫范围使用抚摸光标，离开范围恢复，Static禁用。Static两次完整截图像素相同，Resume原位接续且可再次轻摸，Reset清空并恢复卯时多云动态。控制台warn/error为空。最终包完成相应鼠标复核；`web-mouse-record.json` 与 `courtyard-web-*.jpg`。 |
| 实际运行入口 | 原生1152×720试玩窗口与loopback Web服务已启动，`playable.log`、`web-server.log`。原生OS鼠标交互没有单独自动化验收；鼠标证据来自实际Web。 |
| 用户认可 | 最新听雨廊Web收尾已按本chat用户明确反馈记入交接；用户随后在本chat明确回复「验收通过」，山门庭院首轮独立试玩认可完成。Windows实机等不能继承Web认可。 |

全部日志／截图在本工作树 `.local/qa/courtyard-v1/`，不进入Git。原生完整参考 `02-clear.png`、`04-light-rain.png`；Web完整截图 `courtyard-web-clear-day.jpg`、`courtyard-web-rain-dusk.jpg`、`courtyard-web-moving-pet.jpg`、`courtyard-web-resume-pet.jpg`。

回归边界：原听雨廊ambient套件154项有12项失败；对同一最新origin/main建立未修改基线并运行，逐项结果完全一致（142通过／12失败）。失效断言涉及既有落点／雨退休／鸟Static及headless tween；记录 `tingyu-baseline-comparison.json`。不能将该套件写成全通过，也没有把既有失败算作庭院新增回归。

Windows实机、手机、低配、长时运行未验证；本轮没有声音系统。用户于本chat确认「验收通过」，本轮构图、天气、阵风、橘猫与交互体验收尾。下一独立验收项为Windows实机及其他尚未执行的平台／稳定性检查；本次认可不扩展到这些项目。Git归档或公开发布按后续明确授权处理。
