# TEA-AB 验证记录（2026-10-05）

版本 0.1.3-tea-ab；基线 HEAD cc2f438b8d924624aa3ef5f24767dffe02f4116e + 当前未提交切片。Godot 4.7.2.stable.official.ed1daf0bf / GDScript / Compatibility，匹配 Windows 和单线程 Web 模板。Windows 10.0.26300，PowerShell 7.6.5，实际执行账户 x1-lite\codexsandboxoffline；没有冒充 guoqi。

| 项目 | 结果 | 证据与边界 |
| --- | --- | --- |
| 场景加载 | PASS | 锁定引擎 headless 导入/主场景启动；没有脚本错误。 |
| 自动宿主状态 | PASS | 原养成 14 项、tea 73 项：杯子任意顺序、确认门槛、重复回执、旧会话、取消、跨日、重置、无时间/属性结算。 |
| 自动 UI 回归 | PASS | tea_ui_test：73 项无渲染 / 77 项实际 Compatibility 渲染；直接场景调用单独计为自动验证。 |
| 天气 | PASS | 既有 8 项 weather_test；UI 回归观察 elapsed 随阅读继续、养成时辰不变，静态开关不改资源；剑坪不套用听雨廊专属雨遮罩。 |
| 字体 | PASS | 472 码点，全量 scripts/assets/data 覆盖；锁定源 SHA256 校验、fontTools 4.60.1，本地 .local/fonttools，不改全局环境。 |
| 美术/alpha | PASS | 背景与双杯内置 imagegen，普通旧剑 Qwen 3.0；原始 PNG 保留，AtlasTexture 分杯，不编辑生成 PNG。完整杯体与四边透明余量检查；来源/精确提示/引用 SHA256 已保存。 |
| Web 构建/启动 | PASS | tools/build.ps1，实际本机 http://127.0.0.1:8766/ 加载。服务仅本机可用。 |
| Web 真实 UI 试玩 | PASS | 内置浏览器真实点击/按键，1152×720 与 960×600。详见序列。 |
| Windows 构建/启动 | PASS | ShuDemo.exe + ShuDemo.pck，实际启动；AMD Radeon 780M/OpenGL 3.3 Compatibility 初始化，无脚本错误。Dummy 音频。 |
| Windows 原生鼠标试玩 | WARN / 未验证 | Computer Use 的应用授权等待超时；未把启动或自动渲染写成原生鼠标试玩。 |
| 用户美术/切片验收 | 待反馈 | candidates 已选入运行目录；approved 表示制作选用，user_accepted=false。 |
| 存档/声音/手机/其他浏览器/Linux/Steam Deck | 未实现或未验证 | 当前只承诺运行内进度；重置/刷新/关闭后重开。 |

真实 Web 序列：

1. 打开归剑问天 → 取消委托 → 回到养成（尚未接受）；重新打开并接受 → 固定剑坪。
2. 点击第二杯名称牌 → Esc 取消未确认阅读 → 返回；修炼 100/0 → 78/12；休息 → 100/12、首日午时。
3. 重访无需重接委托，仍为 0/2；点击第一杯物件 → 记下所见 → 1/2；名称牌重复查看并确认仍为 1/2。
4. 点击第二杯名称牌 → 确认 → 2/2；只出现江砚秋初期推想，标题仍为归剑问天。
5. 缩到 960×600，两杯/文字/按钮无裁切；结束本段 → 听雨廊 → 修炼/休息 → 100/24、第二日卯时。
6. 跨日重访仍为 2/2、本段已结束；返回 → 请教口诀 → 92/24、领悟 1 → 继续 → 加成修炼 70/42；点拨只用一次。
7. 重新开始 → 首日卯时、100/0、委托入口恢复未接受。最终 Atlas 边距更新后另做实际图层/名称牌复核；玩法代码与流程未改。

渲染截图（自动渲染，不冒充浏览器/原生真人试玩截图）：

以下为本机证据，不随源码提交：

- `.local/qa/tea-ab/tea-1152x720.png`
- `.local/qa/tea-ab/tea-960x600.png`

本机完整日志位于 .local/qa/tea-ab；最终 snapshot.json 记录本次运行源码/数据/美术校验，包内 build-info.json 记录基线及文件 SHA256。该 snapshot/Windows 预览包记录的是首次制作阶段；后续公开发布与源码归档另见下面的记录。

归档说明：jggagi/sub 的 Git 读取需认证，已连接 GitHub 也返回 404；本轮无可用 sub 工作副本，不创建远端、不操作认证。仅复用历史 A/B/世人误解既有文字，UI 词条为实现文案，未写新支线剧情稿；历史原稿 SHA256 与原位不变。未来需要新剧情稿时先恢复指定 sub 归档入口。

## GitHub Pages 发布（客户端日期 2026-10-04，America/Los_Angeles）

- 在线地址：https://jggagi.github.io/shu/ ，版本 0.1.3-tea-ab；源为 gh-pages 分支根目录。
- 发布提交：f7d8a7eba184be35718e08a7399fcdbc3242f888；仅上传已验证 Web 导出、许可、.nojekyll 和版本信息。main 仍为 cc2f438b8d924624aa3ef5f24767dffe02f4116e，本机源码与 game-art 未提交内容保持原状。
- GitHub Pages build / report / deploy 均成功；运行记录：https://github.com/jggagi/shu/actions/runs/37249919619 。Pages API status=built，在线 build-info.json 与准备包版本及运行文件散列记录一致。
- 公网真实 UI 复核 PASS：在线加载、接受委托、第一杯确认 1/2、第二杯确认 2/2、结束返回养成；修炼 100/0 → 78/12，休息 → 100/12。960×600 桌面尺寸观察无裁切；随后重置到初始状态并清除临时浏览器窗口尺寸覆盖。
- 本次发布不等同于用户对切片或美术验收。接下来的验收仍是 A/B 杯子尺寸、点击区、阅读/返回节奏。

## 源码提交后的发布约定（客户端日期 2026-10-04）

用户授权聚焦源码提交/推送与重新发布。提交检查时运行文件与此前已通过检查的 snapshot 逐项 SHA256 一致，原稿 SHA256 不变；随后只清理新测试空行的尾随空白、补充本机候选范围及发布文档，玩法和图层字节未变；后续部署的 build-info.json 记录实际源码提交与导出文件散列。提交后的独立源码导出、上线结果写入本机 .local/qa/tea-ab/source-publication.json，在线部署状态由 GitHub Actions 与 Pages API 核验。初始本机工具/配置保持原字节且未暂存。
