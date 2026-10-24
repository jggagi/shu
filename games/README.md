# 养成引擎 v0.2 内容包

当前有声循环目录为 `mentor_loop_catalog.json`：新增 `shu_mentor_loop`，并保留 `stream_study` 作为共用内核的无声验证包。默认 `catalog.json` 及原两包保持不变，新入口通过场景的 `catalog_path` 选择目录。

`shu_mentor_loop` 在听雨廊听完《慢半步》，到后山任选原五套剑法，再回廊复命；室内2D、练剑用固定模型帧。对白、条件、完成旗标、音频绑定、人物和场景均在JSON内；原九句配音复用，复命五句另行归档。调息8精力／一时辰／理解1，下一套剑法额外6修为一次；五套剑法仍为22精力／剑术10／一时辰。歇息沿用34精力／一时辰，复命没有额外数值奖励。新资料在 `shu_mentor_loop/source.json`，制作与验收见[听教练剑切片](../docs/CULTIVATION_ENGINE_MENTOR_LOOP.md)。

`catalog.json` 登记入口；两个包由同一套 `addons/cultivation_mode/` 代码解释，包内仅有 JSON，不带脚本。字段定义见[运行库](../addons/cultivation_mode/README.md)，当前动作接入见[v0.2切片](../docs/CULTIVATION_ENGINE_V02_SWORD_SLICE.md)，基础循环来源见[v0.1实施记录](../docs/CULTIVATION_ENGINE_V0_SLICE.md)。

- `shu_entry`：蜀山基础养成小样，江砚秋与叶知闲沿用已批准人物。E1 的基础修习、师傅互动、歇息、目标和短对白仍是引擎验证适配：后山修习消耗22／修为+12／两时辰，已领会提示时再加修为6；休息恢复34／一时辰；请教在选择口诀时消耗8／一时辰并增加理解1。属性上限、回报目标与对白不代表正式主线规则。
- `shu_entry` 的五个剑法菜单动作沿用 `assets/data/sword_manuals.json` 中已用的稳定 ID 与标题，并复用 `assets/art/jiang_sword_cycle/sets.json` 登记的五段已认可动作。它们采用正式剑术练习数值：每次精力−22、剑术+10、推进一时辰；菜单计数沿用对应稳定 ID。五套动作和这些结算规则不会改写 E1 的基础修习／师傅规则，也没有新增剧情。
- `shu_entry` v0.2.1：新增数据驱动的《归剑问天》A/B 支线；只包含山下老人委托、剑坪双杯查看／杯旁行动与 A/B 阶段边界。原稿选段、输入／美术 SHA256、来源许可记录和热点几何见 `games/shu_entry/quests.json`；运行只引用现有剑坪背景和透明双杯图集，不加载含 C–I 内容的 `assets/data/tea.json`。A/B 双杯完成只结束当前内容切片，不是整条支线终点；整条未完成前不返回养成。美术用户验收仍待确认。
- `stream_study`：独立验证样例，文字人物与短对白为本轮原创。余力80、读书耗15／心得8、歇息恢复25，采用四段时间；请教提示供下一次读书加4。该包证明不同 ID、属性与规则可配置，不作为第二款正式游戏或新支线验收；本轮保持其 JSON 原样。

运行数据和短对白不替代主／支线原稿归档；未搬动历史剧情。原始蜀山场景和正式8805流程保留。

美术均复用既有源文件，不重绘、不上传、不改名冒充人物：蜀山人物见 `assets/art/v2/source.json`，听雨廊见 `assets/art/weather3/source.json`，后山见 `assets/art/back_mountain_training/source.json`，溪亭见 `assets/art/stream_teahouse/source.json`。所有消费文件的 SHA256 记录在构建生成的 `build-info.json`；字库来源与 OFL 许可见 `assets/fonts/source-cultivation-engine.json` 和 `OFL-Serif.txt`。新文字人物有意仅显示姓名卡。
