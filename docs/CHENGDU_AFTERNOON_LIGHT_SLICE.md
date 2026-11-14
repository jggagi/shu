# 成都茶铺与庭树：统一午后光样板

客户端日期2026-11-10，America/Los_Angeles。用户对「茶铺＋庭树＋门前路面」统一午后光的局部制作提案回复「好」。玩家可观察的目标为树影和檐影真实落在石路上、暖亮处与较冷暗部协调，并在原连续跟随镜头下稳定。具体观感仍待用户试玩。

## 实现范围

现有太阳会为Blender茶铺／庭树投影，但原绘景路面的unshaded材质不接收这些实时阴影。新[午后光helper](../addons/cultivation_mode/chengdu_afternoon_light.gd)在原helper完成后，为7个首街ground与8个保留南门ground的当前材质派生私有shader；保留原fragment的画稿选择、来源ID／深度归属、透明ALPHA、材质链、优先级以及完整vertex。原0.01米世界法线深度修复保持，未新增地面或调整几何。

世界遮罩限定于逻辑范围`[7100,7080,1480,700]`、羽化128；亮处略暖，接影处乘`[0.72,0.78,0.87]`。茶铺和庭树共6个模型材质的直射光略暖、环境填光适度收敛，保持原顶点AO、图集和fade规则。原10个不透明铺地本就接收实时光，不另叠一层。原太阳位置、能量、色值、全局环境和渲染设置保持；没有新灯、纹理sampler、生图或全局后期。

Godot4.7.2 Compatibility将带阴影的方向光放在独立加法pass，各pass单独转换sRGB。接收端以EMISSION保存sRGB阴影色，ALBEDO设白，light()输出亮色减阴影色的线性化差值乘ATTENUATION，避免直接拆分线性能量引起的亮度溢出。遮罩外差值为0，保留原画稿颜色。合同为唯一带阴影方向光、linear tonemap、非强制vertex shading；切换渲染器或增设方向光须重新检查。依据[官方4.7.2 GLES shader](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl)。

旧画稿的烘焙光仍在，未声称完成物理去光照；局部可能有双重暗部。本轮实景图审认为树影落地、檐下层次有可见改善，保留手绘风格。范围配置见[布局](../assets/data/chengdu-afternoon-light-layout.json)。大城15360×11520、592住宅／622障碍、原相机、导航、人物、商贩、唯一EngineSession与保存路径保持。

## 分层验证

最终候选`stage-ae5fd766e55b`，437输入，runtime digest `c5ab18b17d8aa89e6f16b98e1eeed5dd25a72e9287b283b17dce0e3fb95602b7`。HEAD `7c992c578b1fe4a1624c769812425b38080771d3`，`codex/chengdu-connected-streets` dirty。相对上版434项，433项字节保持，只有ArtStreet Stage接线变化，新增helper、配置和继承原流程的render测试。Godot4.7.2 stable／Compatibility／匹配单线程Web模板保持。

- 导入、2538项状态／导航与Web导出通过，退出0，游戏日志无错误／警告。
- 独立headless真实Stage408项通过，3978个uniform值比较无差异；15地面＋6模型的完整vertex、材质链与优先级保持。开关两轮、关闭期间fade／player_uv更新及helper释放恢复均通过，实际1盏带阴影方向光、linear tonemap、force_vertex_shading=false。35项资产／来源／制作源／11项保护hash通过。
- 原跟随镜头8个合法铺前点位GPU检查通过；相同相机／状态仅旁路路面ATTENUATION，太阳仍保持原阴影加法pass。横巷／主街／茶铺分别有41204／68897／47598个像素至少变暗8级，反向亮差为0，证明真实接影。前后图为完整viewport等比缩放，画外标记，无修图；[横巷](../.local/qa/chengdu-afternoon-light-20261110/comparison-lane.png)、[主街](../.local/qa/chengdu-afternoon-light-20261110/comparison-middle.png)、[茶铺](../.local/qa/chengdu-afternoon-light-20261110/comparison-tea.png)。
- 原761帧路线，两绘景条件各65张PNG；camera trace与0.7.10逐项相同。冻结420点／5294对，正式条件亮度相邻跳变p95为1.096615级、最大7.834255级、≥12级短亮峰0；前版p95为1.083778级、最大7.738149级。旁路新绘景条件p95为2.274548级、最大6.744115级、亮峰0。没有重新筛选或排除新树影样本；这不保证全城每帧或代表独占性能。

- Wayland实际窗口1152×720与960×600各286项／20张UI图／0失败，共572项／40图，另20张viewport诊断图。完整行动结果、同场师傅选择、全城地图与行走、竹伞重访、茶馆双门、保存后恢复全字段、返山和确认重置通过；两个窗口正常退出，日志无错误／警告。旧helper的诊断先关闭本轮光照，再最后恢复，避免互相覆盖材质。
- [18871试玩](http://127.0.0.1:18871/)已更新为0.7.11-afternoon-light，5个HTTP文件与磁盘完整字节／SHA一致；PCK 147452264字节，SHA256 `5c0526d81f3de2c510b5ff212d17a8d36b12b7b24f100ab7da03fd37b8e0cd40`。原用户目录`shu-chengdu-art-street-20261108`与保存目录`user://chengdu_art_street`保持，主副本仍为干净main。HTTP检查不等同于浏览器操作。

## 诊断修正与边界

首候选用`sun.shadow_enabled=false`制作无阴影图，会使太阳切换GLES pass，颜色变化不能证明真实接影。该诊断废弃，相关图与被中止的原生运行归档于QA的`candidate-be270ddf800d-diagnostic-renderpass/`，不计入最终通过。最终只用接收端uniform旁路ATTENUATION，太阳属性和其他模型材质保持。另修复helper关闭期间新房流入时需保持关闭状态的开关边界。

QA目录`.local/qa/chengdu-afternoon-light-20261110/`保存原始PNG、路线、比较源SHA、构建／CPU／原生／HTTP收据和复现脚本。CUA当前返回apps=[]／browsers=[]，实际Web UI／刷新恢复未验证；Windows、声音、实体输入、独占性能及用户美术认可未验证。没有Git提交、push、合并或公开发布。

下一验收点：沿主街到茶铺，再拐入庭树横巷，观察碎树影、檐影的落点和冷热关系，判断是否更有体积、暗部是否过重，以及走动时是否稳定。样板获认可后再讨论扩大范围。
