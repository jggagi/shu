# 听雨廊：猫常来与桌面走动

2026-10-07，D051，用户授权本地修订；本地实现与原生画面检查完成，步态、密度与外形待用户试玩。

## 制作参数与素材

- 初次安全出现机会由18–26秒提前到4–8秒；后续事件间隔14–24秒，停留100–140秒。实际出现会受到 Busy／显眼事件与黄昏机会乘数影响，不是始终常驻。
- 原八姿态沿用；新增四个迈步姿态、坐姿与站姿，单张 RGBA 图 `assets/art/ambient_life/tingyu-cat-desk-v1.png`，1536×1024，3×2单元，每单元512×512。
- 内置 imagegen 制作单张 companion 姿态参考图，沿用已认可橘猫的水彩身份；该参考图经选用直接进入本地运行，不外发新图至 Qwen、不改 Qwen 配置。
- 图片按字节原样复制，alpha extrema0..254，透明像素815034；没有抠图或像素编辑。低 alpha 边缘保留，需在实际场景审阅边缘和姿态接触。
- 精确提示 `art/prompts/tingyu-cat-desk-v1.txt`，来源 `tingyu-cat-desk-source-v1.json`，AtlasTexture region／pivot `tingyu-cat-desk-layout-v1.json`，manifest记录provider与SHA256；原图集/source/后山运行保持。
- 路径由 `CatWalk_Desk` 声明在真实右側空桌面 `(1228,472)`→`(1290,472)`。桌面在屋顶内、廊外雨遮罩之外，两处猫点和路线 sheltered=true；晴点仍sunny=true。

## 行为边界

只读宿主 time/weather/Busy/Dynamic；不改 DemoState、规则、剧情、Tea 或鸟的参数。独立听雨廊桌面动作 helper，由 AmbientLife 已有推进量更新动作相位；Static、Busy、鸟／阵风和摸猫暂停位移。走动时暂停保留实际位置并站定，恢复接续路线，不瞬间跳回落点。走动中的点击热点跟随实际猫的轮廓，继续原摸摸回应，没有新资源或关系系统。

节奏：趴卧→站起→短距离交替迈腿→停下嗅闻→坐下→走回→休息；显眼事件继续错开。

## 验证记录

- Godot 4.7.2 stable / macOS Apple M4 / Compatibility 导入成功；新图和动作 helper 实际加载。首轮发现 Control 没有 `to_local`，已改用全局变换逆矩阵，后续原生预览与最新试玩启动无引擎错误。
- 默认多云、未操作的实际等待中，猫约6.2秒自然淡入；四个迈步帧、站立、坐下、往返位置均已在真实窗口捕获并人工查看。脚点保持桌面 y=472，左右面对和每姿态比例正常；透明边缘未见背景矩形。1152×720与960×600小雨画面均可辨认，遮蔽桌面上的猫不因下雨瞬间退场。
- 真实场景回调预览检查请教／选择／修炼的 Busy，走动猫在实际位置站定；解除 Busy 后接续。选择与修炼仍结算至修为18、精力70、时辰3，摸猫保持数值和位置；左向摸猫不突然翻向。
- 走动中 Static 站定、恢复后继续；坐下时 Static 保留坐姿。两张坐姿静态截图 SHA256 相同：`36c5a91ed65670920001b620c3aa4e8cdb19f912fe1af9349970f83f9caae768`。Tea 接受后实际画面不显示猫；Reset 清除旧遇见与动作状态，回到修为0／精力100，下一只自然再来。
- 证据位于忽略目录 `.local/qa/cat-desk-v1/`；自然预览日志 `/private/tmp/tingyu-cat-desk-preview.log`，交互回调预览 `/private/tmp/tingyu-cat-desk-settle.log`，最新试玩 `/private/tmp/tingyu-cat-desk-playable.log`。这些属于真实渲染与回调检查，尚未完成本轮原生鼠标点击验收、长期密度试玩或用户认可。

没有新增或运行自动测试套件。既有 Web／Windows 导出未包含此次猫和香炉修订；本轮未重新导出、未验证 Windows 实机。

下一验收：几秒内可遇到猫、坐卧和走动有变化，步态不似平移贴图，脚贴桌、姿态大小稳定，原有行动／器物和猫点击不冲突。

## D052：抚摸手形光标（2026-10-07）

新增原创 `assets/art/ui/cat-pet-cursor.svg`，40×40透明手形，接触热点 `(12,12)`；来源、作者与SHA256在同目录source及manifest中。仅猫的可互动热点选择自定义形状，鼠标离开自动交还普通控件光标；Busy／Static和摸猫回应期间热点禁用并恢复箭头，节点释放时清除自定义映射。未更改原点击行为或状态结算。

Godot4.7.2导入退出0，原生场景加载／释放退出0，日志显示素材40×40、专用光标形状6及映射注册成功，无运行错误；手形素材已人工查看。导入时补回此前桌面动作helper缺失的UID，预览运行未出现该警告。证据在`.local/qa/cat-pet-cursor-v1/`和`/private/tmp/tingyu-pet-cursor-preview.log`；实际鼠标悬停／移出、Busy和Static切换仍待用户试玩。本轮不运行自动测试套件，旧Web／Windows包未更新。使用接口依据[Godot自定义光标文档](https://docs.godotengine.org/en/stable/classes/class_input.html#class-input-method-set-custom-mouse-cursor)。

### 手形反馈修订 v2

用户不认可首版手形。当前改用原创`assets/art/ui/cat-pet-cursor-v2.svg`，掌心朝下、手腕从右侧伸来、手指并拢轻弯；40×40，接触热点`(8,24)`落在指尖，避免以手掌中心点击。首版SVG与来源保留，新版单独记录SHA256。悬停范围和所有互动门保持。Godot4.7.2导入和实际原生加载／释放均退出0，40×40素材与光标注册正常，无运行错误；指尖向下的新外形已查看。证据在`.local/qa/cat-pet-cursor-v2/`与`/private/tmp/tingyu-pet-cursor-v2-preview.log`。用户实际悬停与手形验收仍待完成。
