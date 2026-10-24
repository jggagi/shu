# 江砚秋：Meshy 胸像小样

日期：2026-10-22。用户最初同意先用 Meshy 生成一个胸像候选，再由 Codex 在 Blender 修整；登录后确认免费账号下载限制，用户进一步选择「用免费点数试新版，先在线检查质量」。当前交付改为单次新版在线质量预览；不扩大至全身或持剑动作，不购买订阅、充值、安装软件或发布作品。

## 输入已准备

- 输入：`art/work/jiang-meshy-bust-20261022/input-three-quarter.png`，1254 × 1254，PNG，2,224,877 字节。
- SHA256：`bdc3fb43e6b2ca1aad1847a45804acc4a09da08db4c0b5db76acb6f930240b3e`。
- 输入由内置 imagegen 将已有三视图中的中央角色整理为单独完整胸像；保留少年脸、棕色马尾、蓝色布带、蓝白交领，去除其他视角和文字，补齐肩胸边界。它是二维建模参考，**不是 Meshy 已生成的三维模型**。
- 精确提示：[输入整理提示](../../art/prompts/jiang-meshy-bust-input-20261022.txt)。父图：`art/work/jiang-bust-target-20261022/concept.png`；来源记录在 `art/manifest.jsonl`。输入作为候选，不替换游戏正式美术。

## 实际接入状态

插件目录未找到 Meshy 接入口。当前进程的 `MESHY_API_KEY`、`MESHY_API_TOKEN` 均未配置；只检查是否存在，未显示或查找私有凭据。用户亲自完成网页登录后，实际账号菜单显示 Free，提交前余额为 100 点。

已上传上述单人胸像输入，并提交一次任务，先后观察到几何与贴图生成阶段，最终出现可旋转的带贴图胸像。实际设置：High Detail、Meshy 7.1 - Flagship、Standard、Texture 开启、Image Enhancement 关闭，Multi-view／Pose／Split 关闭，CC BY 4.0。按钮显示约 2 分钟、30 点；按用户选择使用现有免费点数。只有一次 Generate 提交，未发起第二次生成、重试或购买行为。界面产出几何阶段和带贴图结果两项，不把两张资产卡误记为两次手工提交。

已将带贴图结果从默认名 Blue Ribbon Daydream 改为 **江砚秋_胸像_Meshy7.1_20261022**。打开 [Meshy 工作区](https://www.meshy.ai/workspace)后可在当前账号中按此名称查找；右侧浏览器保留该模型的 Lit Mode 预览。公开工作区 URL 没有暴露本次任务 ID，未从隐藏状态或接口提取 ID。

完成后界面余额显示 110 点，期间也弹出签到赠送 30 点的提示。本轮没有检查点数流水，因此只能确认提交时按钮报价为 30 点、提交一次，不用余额变化推断净扣费。没有现金购买或订阅。

官方 [Free 计划说明](https://help.meshy.ai/en/articles/15696428-what-is-included-on-the-free-plan)指出：免费计划有月度点数，但新版 Meshy 6／7 模型的下载受订阅限制；免费可下载的是 Meshy 6 Lite，API 也不在 Free 计划内。因此必须在生成前核对实际账号的导出权限，不能先消耗点数再发现无法交付 Blender 文件。本文不推断用户已有计划或剩余额度。

官方多个页面对带贴图生成点数存在差异：以任务实际配置后、提交前显示的价格为准，不把公开说明当作这个账号的实付报价。页面来源：[图生 3D](https://docs.meshy.ai/en/webapp/image-to-3d)、[API 价格](https://docs.meshy.ai/en/api/pricing)、[导出格式](https://docs.meshy.ai/en/webapp/guides/platform/export-formats)。

## 登录后的单次执行

1. 已核对账号为 Free、100 点；免费新版模型不能下载。用户在获知该限制后选择先在线测试新版，暂不进入 Blender 修整。
2. 已上传并按上述实际参数提交一次 30 点任务；保留输入哈希、截图和原始结果定位。
3. 等待任务完成，检查正、侧、背、头部和马尾真实体积、几何与贴图区分；失败或状态不明不自动重试。
4. 若未来取得可导出权限，再保存原始 GLB／贴图与 SHA256并进入 Blender。当前不声称已有本地模型、完成修模或绑定。

提交时状态：`MESHY_SINGLE_TASK_SUBMITTED_QUEUED`，后续完成情况见下节。在线结果不等同于已下载到本地的可编辑模型。

## 完成检查与当前结果

最新状态：`ONLINE_PREVIEW_COMPLETED_AND_REVIEWED`，取代上面的提交中状态。Root 实际旋转检查正、约四分之三侧面、近侧面和后侧，并在同一带贴图结果上切换 Solid Mode，检查灰模；最终保留 Lit Mode。临时将 Vertical FOV 从 35 改为 20 检查脸部近景，结束前已用 Reset FOV 恢复默认。角度为手动旋转近似值，不宣称正交测量或几何哈希一致性。

本地截图与记录目录：`.local/qa/jiang-meshy-bust-20261022/`。

- `final-three-quarter-painted.png` 与 `final-three-quarter-gray.png`：同一最终资产、近似同一视角的上色／灰模 UI 截图；未读取或精确比较相机矩阵。
- `painted-face-detail.png` 与 `gray-face-detail.png`：同一最终资产脸部近景；界面覆盖了部分头顶和胸部，不作为完整轮廓截图。
- `painted-front.png`、`painted-side.png`、`painted-back.png` 及对应侧／背灰模截图：实际手动旋转观察；没有逐视角重生成。
- `gray-three-quarter-geometry-stage.png`：较早的未贴图中间资产截图，仅作历史，不冒充最终上色图的同视角配对。
- `asset-library.png`、`meshy-ready.png`、`source.json`：账号内结果定位、提交前设置及实际参数／截图哈希。

Root 的视觉判断：此候选的脸部神态、分层发束、布带和交领比此前脚本模型更贴近二维目标；灰模也有相应体积，值得作为继续修改的候选。细发束仍有薄片和毛糙结构，眼部几何需要后续清理，衣褶较杂。此为模型观察，**不是用户已认可或专业终稿**。

本轮按用户选择完成在线质量预览。没有下载 GLB／贴图、未在 Blender 修模，未检查可动画拓扑、UV、绑定、持剑或帧间稳定性；免费账户的导出门槛仍然存在。
