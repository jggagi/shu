# P3a · 松风古道光影统一

后继[可破坏木栅战术切片](P3_SONGFENG_BARRICADE_SLICE.md)已实现并完成采用检查及最终包三套回归，当前入口18824、玩法待用户试玩。本页18823、939项／53图与光影性能观察保留为前轮证据，不覆盖后继规则修订。

客户端日期：2026-10-24，America/Los_Angeles。状态：**光影与对照切换已接入，最终本机与实际PCK检查通过，观感待用户试玩**。用户回复「统一」，授权在[18822细节基础](P3_SONGFENG_DETAIL_SLICE.md)上统一人物与环境的受光关系。前轮802项／41图及43.75fps短测不用于证明本轮通过或性能。

## 实际实现与取舍

默认「光影：增强」，可切换「光影：原版」，原版恢复18822的确切设置。增强采用暖斜阳、冷环境光与无阴影的冷补光，人物与环境共用同一套场景灯光；景物动静独立，切换不改变战局／Session，重开恢复增强。按钮悬停／按下使用墨色文字，修复浅底白字。

| 增强配置 | 实际值 |
| --- | --- |
| 主光 | energy 0.84，颜色 `#fff0d7`，旋转 `[-44,-42,-7]`。 |
| 环境光 | energy 0.24，颜色 `#b6c8d6`。 |
| 冷补光 | energy 0.10，颜色 `#a9c3e2`，不投影。 |
| 投影接地 | 主光bias 0.018、normal bias 0.32。 |

配置和来源见[光影配置](../assets/art/mountain_ambush/environment/lighting.json)与[本轮来源记录](../assets/art/mountain_ambush/environment/source-lighting.json)。正交相机near／far及相关投影设置保持，shadow distance仍为26；本轮调整的是光向与阴影偏移接地，不称已经收紧阴影视锥。

**两个交付模式均关闭SSAO。** 制作中两档轻量SSAO试样都在远山出现伪影，预览保留而未交付AO。暖冷关系与投影调整仍交付，不把SSAO参数存在写成已生效效果。不做LightmapGI或新shader插件，官方demo仅作思路参考，未复制第三方代码／示例地图。

原角色模型、地形／布局资产及16项规则／Session／内容JSON、7份角色代码／GLB保持；继续Godot4.7.2／GDScript／Compatibility与Web单线程。无素材替换、新采购／费用、依赖安装、Git提交推送或公开发布，主main保持干净。

## 最终候选与检查状态

当前最终stage为 `.local/build/songfeng-lighting-20261024/stage-49aa2100b472`，255项源逐SHA一致；版本 `0.4.7-songfeng-lighting-candidate`，custom userdir `shu-mountain-ambush-songfeng-lighting`。独立字库675码点，新增「光／强」的真实glyph覆盖。

规则52项／会话84项通过；最终五组实际渲染／Godot输入注入共 **939项、53图、0失败**，其中49张UI图、4张world图。所有最终命令退出0，无脚本／资源警告错误：

| 最终检查 | 结果 | `.local/qa/songfeng-lighting/` 证据目录 |
| --- | --- | --- |
| 原生光影1152×720 | 176项／9UI＋2world图 | `final-native-lighting1152/` |
| 实际PCK光影960×600 | 176项／9UI＋2world图 | `final-pck-lighting960/` |
| 实际PCK环境960×600 | 220项／10图 | `final-pck-environment960/` |
| 实际PCK反馈960×600 | 122项／11图 | `final-pck-feedback960/` |
| 实际PCK完整流程1152×720 | 245项／10图 | `final-pck-flow1152/` |

独立来源37项与最终两尺寸6图复核PASS，分别记录，不追加到939项或替代用户认可。总收据为 `.local/qa/songfeng-lighting/final-validation.json`，精确命令／日志见 `final-commands.json`，独立构建核对见 `creator-game-check.json`。悬停文字修复前的候选与结果归档到 `candidate-before-hover-fix/`，最终stage重新执行全流程，不复用旧结果。

验收覆盖两尺寸原版／增强对照、动态与静止独立、重复切换后真实参数恢复、状态不变、重开／返回资源释放，以及击退、截脉指、红格、药篓和返城安全存读／返山师父选择。实际PCK、原生注入、浏览器实操与用户审美分别记录。

Web共7文件、153,433,986字节；PCK为113,602,384字节，SHA256 `57d35c857241d6571ec1dd60264d33d401b764ff46d7d3143f8259579ec0aa13`。HTTP7／7完整字节与SHA读回一致，WASM MIME正确。255项stage与源码一致，角色、环境布局资产和江原Blend的SHA／444权限保持，主main干净且与origin/main `7c992c5` 一致。

## 原生短测与试玩边界

最终实际PCK在同一原生进程先原版、后增强，各60帧预热＋180帧采样，60fps上限下记录如下：

| 模式 | 实测fps | 平均帧间隔 | p95 |
| --- | --- | --- | --- |
| 原版 | 35.79 | 27.94ms | 33.37ms |
| 增强 | 35.47 | 28.19ms | 33.71ms |

后台旧预览未停，顺序未对消，均为约5秒的原生空闲战场观察；不能据此认定增强无开销、满60fps、Web或长期性能。性能不计入939项，精确数据与限制见 `.local/qa/songfeng-lighting/native-lighting-ab.json` 及对应收据。

在 **X1桌面内**打开[18823光影统一试玩](http://127.0.0.1:18823/)，或切到同PCK原生窗口。服务 `shu-ambush-songfeng-lighting-web-final-20261024.service` 与 `shu-ambush-songfeng-lighting-native-final-20261024.service` 均active；只替换本轮中间18823服务，旧18822及更早服务保持，最终及历史共12个服务active。

常驻原生只有既有X11 `wd.xic` 输入法警告，无脚本／资源错误；Dummy音频QA无警告，两者分别记录。CUA的apps／browsers仍为空，打开请求queued不能证明浏览器实操。用户审美、浏览器输入／刷新／性能、Windows／Steam Deck、实体输入、听感、长期性能和真实旧档迁移仍未验收。

下一验收点：在同一局切换增强／原版，观察人物脸发衣色与松石受光是否统一、冷暗面是否清楚、脚底投影是否自然，再实际移动、击退与截脉指，确认战术标记易读。
