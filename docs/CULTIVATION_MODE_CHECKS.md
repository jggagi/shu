# 养成模式 skill 0.1.0 收尾检查

日期：2026-10-04。范围：制作 skill、数据样例、可重复检查工具与新 chat 交接；没有修改 Godot 游戏代码、场景、素材或引擎配置。

| 项目 | 结果 | 证据与限制 |
| --- | --- | --- |
| Skill 格式与 UI 元数据 | PASS | skill-creator quick_validate 返回 Skill is valid；名称、版本与默认调用一致 |
| 包内示例/引用 | PASS | 9 个内部引用、6 个事件节点、3 个养成活动；有入口、失败去向及结束路径 |
| 检查工具拒绝错误内容 | PASS | 悬空边、循环、白名单外行动均被拒绝 |
| tea 来源与阶段 | PASS | 原稿固定版本和 SHA256 已核对；10 个阶段标题对应原稿，前后两杯 ID 相同 |
| 合同审查 | PASS | 明确 awaiting_cue_ack/确认实例失效；行动拒绝保留事件占用并走失败分支；事件退出才释放 |
| 小改/养成/战斗边界 | PASS | 沿用此前只读推演：小改不抽框架，养成活动可接入，战斗另走工作流 |
| 仓库文档、路径与交接 | PASS | 包按仓库相对路径组织；版本化入口和 tea 首切片交接可独立读取 |
| Godot runtime / EditorPlugin | 未实现 | 签名与目录为设计合同；没有声称可加载样例或已有插件 |
| tea 可玩内容、存档 | 未实现 | 下一 chat 制作；本轮不构建游戏，不把历史 D01 验证当作新支线验证 |
| 用户级 skill 安装 | 未执行 | 本轮保存仓库级版本，不改全局 skill 配置 |

仓库内重复检查（已有 Python 3 即可，无第三方包）：

```text
python .agents/skills/game-cultivation-build/scripts/validate_package.py --repo .
```

该命令验证包结构、示例及固定原稿来源，不验证 Godot 运行行为。后续可玩切片仍需真实 UI 验收。文档/skill 提交与远端保存以本文件 Git 历史及当轮交付的 commit 为准。

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
