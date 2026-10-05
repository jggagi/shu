# TEA-AB 任务卡（2026-10-05）

状态：已实现并验证 Web，待用户试玩拍板。入口《归剑问天》。

- 基线：main / cc2f438b8d924624aa3ef5f24767dffe02f4116e；已有 .gitignore、AGENTS、.codex、art 和 setup_game_art 修改完整保留。制作时暂不提交、不推送；用户随后授权源码提交、推送与在线更新。初始 game-art 工具/配置修改继续保留在本机，未纳入本次切片提交。
- 来源：历史 story/sub/tea/README.md（原稿 commit 086e13e），只取阶段 A/B；原稿不迁移。本轮只复用既有原稿，不写新剧情稿；运行快照留 assets/data，来源附 SHA256。jggagi/sub 暂不可访问，后续新稿须先恢复该指定归档入口。
- 流程：养成面板 → 山下老人的旧剑委托（接受或取消）→ 固定剑坪 → 两杯分别查看并明确确认 → 本段结束或随时取消 → 听雨廊继续修炼/休息。
- 稳定 ID：quest tea；阶段 return_sword、cups_first；场景 tea.sword_terrace；物件 tea.cup_first、tea.cup_second。后续结尾复用。
- 规则：无日期门槛；本段调查不消耗精力/养成时间、不发属性或装备奖励；既有修炼/请教/休息继续引用 rules.json。已确认线索保留到明确重置/重开；未确认阅读取消不提交。当前运行内保持，无存档承诺。
- 顺序：接受委托再进入剑坪；只展示杯沿磨痕、茶渍与初期传说；江砚秋为见证者。不展示失忆、医案、信件、后事公文、最终标题；不改顾青萝和谢长安选择/结局。
- 实施：demo_state.gd 最小宿主状态/会话令牌；main.gd 最小支线面板/热点；独立 tea.json、tea-layout.json；现有 Weather 继续独立计时，剑坪不复用听雨廊专属雨遮罩。UI 不受光照。
- 美术：核对概念/现有来源；内置 imagegen 制作核心剑坪和透明两杯；常规旧剑用配置 Qwen（须本地 READY）。候选 art/work，精确提示 art/prompts，选用 assets/art/tea；approved 表示制作选用，user_accepted=false。
- 验收：两杯可点/确认、任意顺序、重复查看不推进两次、旧回调拒绝、取消/重置释放占用、修炼/休息跨日保持进度；师傅流程与精力不足保留；窗口缩放。
- 分别记录自动检查、Web/Windows 构建、启动、真实 UI 试玩、用户验收。下一点：用户拍板 A/B 的节奏、热点和构图后才接阶段 C。
实际结果与未验证项见 [TEA_VALIDATION](TEA_VALIDATION.md)。本轮三张素材已选入 assets/art/tea；候选保留 art/work，用户尚未验收。
