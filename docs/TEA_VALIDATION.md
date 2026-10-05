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

## 2026-10-05 本地修订：物品中心交互

用户明确指定 Object → Action → Narrative，随后确认沿用叶知闲。当前本地内容版本 tea-ab-object-1，基线 acf2bf8；未提交／推送／更新线上。

- 完成：点击旧杯直接查看，单一锚定浮层；普通修补／询问直接执行；薄札记不含操作或确认，右侧菜单在剑坪隐藏，次要廊下歇息保留。
- 数值：浏览器精力 100 → 修补 78 → 询问 70；歇息实际 +30 到 100，推进一时辰。查看／双杯完成无结算；每杯每动作一次回执，重访不重复扣费；两杯直接查看自动达成本段条件并保留场景，原推想只在首次双杯时触发。
- 自动：state 14、legacy tea 73、object state 61、UI 67、weather 8，共 223 检查／0 失败；最后日志无 ERROR。直接查看同时失效旧待确认阅读，旧 UI／会话回调、重复、精力不足都不能变更资源。
- 真实 Compatibility：92 检查／0 失败；窗口 1152×720、960×600、1440×900、1280×720、800×600。非 16:10 沿用等比留边，活动画面截图分别为 1152×720／800×500，未误写为全窗口截图。
- 浏览器真实输入：悬停标签／淡暖边、直接查看 0→1→2、杯旁修补／询问、单浮层切换、Esc／空白关闭和歇息通过；实际 CSS 960×600、1281×720 及 762×476；两杯浮层不出场景、不遮杯体／HUD。控制台 error／warn 0。最终 Web 重载后启动、接受委托、首杯查看再次通过。
- 构建：Godot 4.7.2 + 匹配单线程 Web 模板导入／导出退出 0，日志无 ERROR／SCRIPT ERROR／WARNING。PCK SHA256 2c93748fd3daba494bb026e0effd2f8610dfa201a9fcf02ec00c31bc446c0736；字体子集 494 码点覆盖通过，git diff --check 通过。
- 来源：首杯描述及修补反馈明确为用户 UI 适配；第二杯／传闻／推想及历史原稿保留。复用既有 PNG，未付费生成新图；未改顶部 HUD、规则、角色表与天气系统。
- 未验证：Windows 原生／Safari／Firefox／手机竖屏／Steam Deck，以及用户主观手感。源码改动与本机预览不是用户认可或线上发布；阶段 C 尚未启动。

完整报告和截图保存在本 chat 的 outputs/object-ui，试玩 http://127.0.0.1:8770/ 。构建文件为开发卷上的可重建产物；本轮执行／发布与此前记录分开。

## 2026-10-05：skill 0.1.1 与支线完成门槛

用户 approve 明确将《两盏茶》定义为养成支线：接受后，整条支线完成前不回养成主界面。此规则取代前文历史版本允许 A/B 结束返回的约定；原委托未接受时可暂且返回，重新开始是清空状态的新一轮游戏。

- 当前本地内容 tea-ab-object-2、skill 0.1.1，基线 acf2bf8；未提交、推送或更新线上。
- 宿主分离 tea_stage_complete 与 tea_quest_complete；2/2 只收齐 A/B 线索，仍留剑坪，提示“本段线索已收齐；支线后续尚未开放”。C–I／结局未实现，正式路径不能产生全支线完成旗标。
- 隐藏未满足门槛的返回入口；Esc 优先关闭浮层，随后保持支线并以札记显示宿主原因。旧 cancel/finish 回调不能绕过宿主门槛。廊下歇息重复／跨天保留调查、回执和支线占用。
- Skill 增补 Object → Action → Narrative、可复用物品说明性数据与全支线 return_policy；普通查看不要求确认，成本由宿主定义，动作明确一次或可重复。proposed addon／EditorPlugin 仍是设计合同，不声称已安装。
- 包检查 PASS（14引用、6事件节点、10阶段、2物品及固定原稿）；quick_validate PASS；11语义负例全拒绝；repeatable 正例通过。独立剑／两页书／歇息前向推演完成，并澄清图动作失败路由、直接动作被动反馈及 Esc 文案。
- Headless：state14、tea106、object90、UI74、weather8，共292检查／0失败；真实 Compatibility99检查／0失败，5种窗口，非16:10沿用等比留边。
- 浏览器 CSS1281×720、960×600：调查0→1→2；修补／询问结果精力70；2/2、连续Esc和原返回位置均保持支线；歇息70→100、卯→辰、进度2/2。浮层不越界／遮HUD；console error/warn0。
- Godot4.7.2导入／Web导出退出0，无 ERROR／SCRIPT ERROR／WARNING；字体503码点覆盖PASS；git diff --check PASS。PCK SHA256 f48fad8d0a458eb3fb4a238f0c0cd44a5e954b0230ebed33de4161174bc91e35。
- 正式结局未可玩；完成后返回的正例仅以明确 synthetic fixture 验证，不算剧情完成。Safari／Firefox／Windows原生／手机竖屏／Steam Deck 未验证。

本 chat 当前报告／截图：outputs/skill-0.1.1；本机试玩 http://127.0.0.1:8770/ 。这是本地验证，与前文历史线上版本分开。

## 2026-10-05：0.1.4 交付授权

用户对当前物品交互和支线停留规则反馈“很好”，并要求“一键三连”。发布候选0.1.4-tea-objects（内容tea-ab-object-2、skill0.1.1），沿用 shu main → 既有 gh-pages → https://jggagi.github.io/shu/ 路径；先提交／PR合并，再从合并源码的固定快照导出，仅将 Web产物、许可与源码绑定build-info上传发布分支。当前C–I仍未实现，2/2不代表整条支线结束。game-art／Qwen本机工具、art配置、混合manifest及.gitignore原有未提交改动排除并保留；没有新增生图或改动凭据。

本次验证与部署提交、上线散列及真实公网输入记录另存本chat outputs/release-0.1.4，正式运行版本以线上 build-info.json 为准。不将以前的“本地未发布”记录当成本次交付结果。
