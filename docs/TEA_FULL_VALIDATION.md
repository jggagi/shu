当前演出修订（2026-10-05）：用户否定本候选的日记表现，完整功能验证保留为历史证据；当前 0.1.7 的过去场景与实际试玩见 [新验证记录](TEA_MEMORY_VALIDATION.md)，完整体验仍待认可。

# 《两盏茶》完整支线验证（2026-10-05）

用户状态：C 已验收，完整实现已授权；本候选 0.1.6-tea-full-local 的完整体验尚待用户试玩拍板。正式线上 A/B 0.1.4 不变；本轮无提交、推送、发布。

## 来源与范围

历史原稿 SHA256 20fc0889378091e70999bb0cee1ae99df28dad7da0469b9fa8ff76de20f2377c 保持。jggagi/sub HEAD 50acc08b5cdd7d8a83525f1c0c1102ca9b7d6ca5 已实时核实；完整快照及 SHA256 见 tea-full-provenance.json。没有新剧情稿、原稿迁移或人物决定改写。game-cultivation-build 0.1.1；game-art 复用已有来源素材，程序茶面无新增 raster 来源。

## 分层证据

| 层次 | 结果 |
| --- | --- |
| 宿主 | 根代理独立运行 tea_full_state_test：153 项 PASS，完整 D–I、阅读前置／实例、重复／旧回调、歇息、添茶顺序与 1.2 秒停顿、终点返回及重置。 |
| 界面 | tea_full_ui_test：1291 项 PASS；逐页原文、未来物件隐藏、全文完成门槛、所有页排版边界、关闭与旧回调、同双杯节点、静默添茶、返回后原修炼／师傅。 |
| 原有回归 | state_test、tea_test 106、tea_object_state_test 90、tea_c_state_test 58、tea_ui_test 74、tea_c_ui_test 121、weather_test 均 PASS。核心 rules.json 未改。 |
| 原生画面 | 最终 1330 项 PASS；1152×720、920×575 各采集长信、短回忆、公文、第一杯与双杯终点，共 10 张非空全窗口截图，根代理已打开复核。首轮黑帧及后续失败日志保留；修正 macOS 异步窗口／backbuffer 缩放重设，并在保存前检查亮度取样。 |
| Web 构建／真实输入 | 最终 Web 导出成功；真实浏览器两次走过委托、C–I 全部证据、双杯调查与添茶、标题变更，原构建返回后修炼／师傅结算已观察。关闭账册后的入口刷新修正已在最终构建复核；第二杯停顿中禁用、到时开启、无重复结尾正文及更清楚茶面已观察。浏览器 error/warn 日志为空；页面已重置到起点。实际浏览器画布约 547×342；两个标准尺寸由原生画面验证，不混称。 |
| Windows | Godot 4.7.2 的 Windows Desktop 最终导出成功，ShuDemo.exe 与 pck 已生成；本 Mac 未运行 Windows。 |
| 来源／字体／skill | 原稿与快照哈希复核，字体完整覆盖 702 codepoints；skill 包检查 PASS。 |

日志和完整窗口截图放 .local/qa/tea-full，不入版本控制。早期失败及调整记录保留；headless 在受限沙箱中有 macOS CA 证书诊断，但游戏检查成功且退出 0，实际原生运行使用 Apple M4 Compatibility。

本机入口：http://127.0.0.1:8767/ 。复制到 /Users/guoq/Developer/shu 时检查当前文件哈希，保留并行后山 Clouds v1 源码与反馈记录。场景、字体、数据和产物范围核对后再交付。

未验证：用户完整情感验收、Windows 实机、手机、声音、持久存档、Steam Deck。重新开始／刷新是新运行；本候选不承诺这些能力。

同步复核：22 个明确范围文件 SHA256 一致，Web／Windows 产物一致；主副本字体导入成功，完整 UI 1291 项 PASS，共享 DemoState 的后山消费方回归 PASS。主副本并行后山交付将 main 推进至 e7fa4207c721f78103abfb04a191a61a9bf05942；该提交由另一授权工作产生，本轮 tea 未提交。tea 运行源码与候选绑定见本机 .local/build/web/build-info.json。
