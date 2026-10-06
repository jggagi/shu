# Tingyu Corridor — Second Adopter：Environment v1

客户端日期 2026-10-06；本机候选 `0.1.10-tingyu-environment-local`。初始制作授权仅独立 worktree、实现、本地验证；后续 GitHub 交付授权见文末。表现认可与源码合并分别记录。

## 起点与保全

原 checkout `/Users/guoq/Developer/shu` 为 `main` / `7f34a5347e60c87fb982df1fb3d488a41d4d4f40`；tracked 干净、暂存区空、无非忽略 untracked。重新 fetch 后 origin/main 相同。从最新 origin/main 创建 `/Users/guoq/.codex/worktrees/tingyu-environment-v1/shu`，分支 `codex/tingyu-environment-v1`；保留原 `.local`／缓存／日志／截图／试玩包／安全快照，不做 clean/reset。原文件大小／mtime 与 safety SHA256 对照保存在本轮 `.local/qa/tingyu-environment-v1`。

## 本切片

玩家可观察目标：同一听雨廊中感到清晨到傍晚的色调变化，晴／多云／小雨无需看标签能辨认，同时师徒和文字清晰。对应 R09、D041。不接动物、猫、剧情扩展或 addon。

背景是完整廊景绘画，不具后山的远／中山透明边缘；使用现有窗洞遮罩，将远山罩染、雾和雨限制在廊外。独立竹叶与轻云影沿原廊景坐标；雨层 z=1、师徒与桌案 z=2、纸框和 UI z=3。师徒只接受较轻时辰调色，UI 不参与材质。复用所有原美术，未生成新 raster。

`EnvironmentPresenter` 原模块保持；`weather.gd` 为听雨廊 scene adapter，以自己的 `tingyu_environment.json` 组合已有六时辰和三天气。`main.gd` 在刷新时只读真实 `state.time_index`，环境不会写入 gameplay state。原 `weather_cycle.gd` 留作历史，不再驱动场景；没有第二游戏时钟或随机天气。

时辰 1.6 秒、天气 4.5 秒、退雨 2.4 秒是本轮制作参数，待试玩调整。Static 保留当前场景、竹叶、云雾和雨线，冻结环境运动时钟；主动天气选择或行动导致的时辰变化仍平滑过渡。Dynamic 从冻结位置恢复。重置回首日卯时／多云／Dynamic，清空原任务状态仍由原宿主执行。

字体检查发现“晴”缺字，复用原 checkout 已保留且 SHA256 校验匹配的 Noto Serif SC 源字体；现有 fontTools 4.51.0 重建运行子集至728码点，并记录实际工具版本、OFL与派生哈希。只改新 worktree 字体，不写原字体或安装依赖。

## 本机试玩

本轮启动的本机 Web：<http://127.0.0.1:8766/>。服务只绑定 loopback，根为该独立 worktree `.local/build/web`；本机 `build-info.json` 绑定 base commit、dirty候选文件哈希与包哈希。服务重启命令为在该 worktree 运行 `python3 tools/serve_preview.py --port 8766`。

```sh
/Users/guoq/.local/bin/godot --windowed --path /Users/guoq/.codex/worktrees/tingyu-environment-v1/shu
```

右上切换天气，5 循环，7 晴／8 多云／9 小雨；4 Static/Dynamic。1 修炼、2 师傅、3 休息；6 Tea 入口沿用。右上重新开始。

1. 先固定同一时辰看三天气：晴暖亮、多云偏冷且远山更柔、小雨有可见廊外雨线与雾。
2. 原修炼／请教／休息推进真实时辰，观察色调自然过渡。六次休息可走过一天，不增加额外预览时辰。
3. 小雨中切 Static，雨雾仍在、竹叶和雨线不动；切天气仍缓变，再切 Dynamic 从当前位置恢复。
4. 点师傅、选口诀、继续与加成修炼；试另一话题、Tea 物件与重置，观察人物／文字是否清楚、交互是否保持。

## 分层验证

最终原 checkout 保全复核：1521个 tracked/本机文件大小与mtime无变化，1258个ignored文件保持；10个安全快照文件SHA256一致，main/HEAD不变、tracked/untracked状态空、暂存区空。`original-baseline.json` 与 `original-preservation.json` 均在本轮忽略QA目录，保留原安全快照原位。

- 导入／启动：Godot 4.7.2 headless editor import 与主场景启动通过；最终 Web release 导出通过。无依赖安装，工作站卷身份／外置容量检查通过；内置容量警告遵守 warning-only。
- 自动检查：原养成状态通过；环境 **178 项、0 失败**，涵盖 18 组合、独立/中断过渡、Static 留雨留雾、恢复及 reset，并对全部 script gameplay 属性（含私有任务 token 与规则 dictionary）做深拷贝前后比较。完整 Tea 状态 **153**、完整 UI **2257**、回忆 UI **619** 项均 0 失败；后山环境回归通过，共用 presenter 未改。
- 真实 Compatibility 渲染：Apple M4 / macOS，**81 项、29 捕获、0 失败**。六时辰由真实休息行动抵达；同一真实酉时三天气、两种过渡 start/mid/end、动静、行动/师傅对白与选择、重置都有画面。1152×720 及请求920×575（实际窗口920×574、aspect-fit图像918×574）分别记录。Static 稳定雨景两帧差异 **0 像素**，Dynamic 的世界 crop 变化 **73233 像素**；同一时辰晴/多云/小雨的 HUD 与下方对白/行动区逐像素相同。
- Codex 画面观察：实际检查六时辰与三天气对照、过渡帧、雨景全图和小窗口师傅结果。首版雨雾罩染过平，降低远山罩染混合至0.50后再渲染，山体与建筑层次保留；雨线可见，师徒前层可读，UI无天气染色。制作参数继续待用户判断。
- 实际浏览器输入：CUA 在本机 Chrome 真实鼠标/键盘验证修炼→点击画面师傅→切雨/Static时选择保留→口诀→继续→加成修炼→休息，数值100/0→78/12→70/12→48/30→82/30。打开Tea、接受委托、查看首杯、修补82→60且按钮转已完成，最后实际点重新开始回100/0、首日卯时/多云/Dynamic。完整Tea结局本轮只做既有自动UI回归，没有重新声称浏览器全流程。最终包重载再检查入口/天气。
- 用户试玩认可：未完成；任何自动检查或 Codex 自评均不替代。
- Windows 实机、移动端、音频、低配性能与长时运行：本轮未验证。

证据目录：`.local/qa/tingyu-environment-v1/`，含各suite日志、`render-report.json`、29原始PNG、两张观察对照页、保全收据与本地候选metadata。首次类型推断失败和首次尺寸断言失败的证据保留在 `initial-render/`；最终结果为上列修正后的独立重跑。

下一验收点：用户判断时辰氛围、天气差异、平滑过渡与克制动态是否自然，并确认师徒和 UI 的可读性。先修此切片，再讨论下一 adopter 范围；不提前抽取共用 addon。


## GitHub 交付授权（2026-10-06）

用户随后明确要求「创建 PR and merge」，授权将本轮17文件切片 commit/push、创建针对main的PR并合并。此授权接替制作阶段的不提交／推送／PR／merge限制；本轮不部署。最新fetch后的origin/main仍为7f34a53，已验证候选源码哈希全部一致；本次仅追加授权记录，没有新的runtime变更。PR/merge结果以GitHub状态与合并提交为准，原checkout继续保留，不据此更新其local main或改写本机产物。未收到新的具体视觉反馈，不把归档合并自动写成参数已获永久批准。
