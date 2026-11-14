# Qwen 美术制作配置

## 当前 Linux／X1 配置流程（2026-11-08）

本节说明新工具的操作与存储方式，不是本次配置完成或在线调用成功的记录。Linux／X1 使用 [`tools/configure_qwen_art.py`](../tools/configure_qwen_art.py) 的一次性本机密码页，将API Key存入当前用户的Linux Secret Service密钥环；[`tools/qwen_art.py`](../tools/qwen_art.py) 在需要时读取，并只传给当前制作子进程。不修改全局shell环境或既有文字模型服务，不自动安装依赖。

在X1桌面会话中运行：

```sh
python3 tools/configure_qwen_art.py
```

用 **X1本机浏览器** 打开终端打印的 `http://127.0.0.1:随机端口/setup?token=…`。服务仅监听127.0.0.1，默认30分钟到期；成功保存后自动关闭，之后需重新运行工具才能再次配置。工具要求系统已有 `/usr/bin/secret-tool`；若系统提示解锁KDE钱包，完成解锁后再保存。

Mac通过已有SSH或应用端口转发访问X1时，浏览器地址中的端口可能不同。此时启动服务时用 `--browser-origin http://localhost:MAC_PORT` 明确加入该次转发的实际浏览器地址；`MAC_PORT` 替换为实际端口。仅接受带明确端口的 `http://localhost` 或 `http://127.0.0.1`，不自动信任转发头或其他端口，提交的Origin仍须与Host一致。此参数只在临时服务中生效，不写入凭据配置，也不会创建转发。重启服务后使用新token的链接。

页面接受北京工作空间ID，或完整的 `https://…cn-beijing.maas.aliyuncs.com/compatible-mode/v1/images/generations` 地址，并使用密码框输入同区域API Key。不要在聊天、命令参数、提示词、日志或来源记录中粘贴密钥。页面提交体与密钥不写入工具日志；密钥通过标准输入交给系统密钥环，不作为子进程命令参数。

保存时，工具写入并读取校验Secret Service条目。忽略的 `.local/qwen-art.json` 以0600权限原子保存：除 `schema_version` 外，仅有非敏感的 `endpoint` 和 `secret_id`，没有API Key。`secret_id` 是工具生成的密钥环条目标识，不是密钥；已有合法本地标识会复用。Linux launcher读取本地设置时要求文件属于当前用户、为非符号链接的普通文件，且不允许组或其他用户访问。

保存与本机读取校验 **不调用百炼接口**，不能证明API Key的线上权限、额度或模型可用性。本次是否成功保存、是否实际在线调用，需要按各自执行结果另记。

### 本轮实际状态追记（2026-11-08）

用户提供官方 `api-key.sh` 一键配置方式。本轮仅下载审查公开脚本，并使用绑定其SHA256 `ff22f530e3c338e554f84e40c08c69075313a5a638c912fb0c6e4653a441bcd5` 的纯本地decoder在内存中解码；未运行安装、main、skills配置或遥测。密钥仅通过标准输入写入Secret Service，读取校验通过；launcher的 `doctor --no-network` 已返回READY，三材质dry-run通过，临时页面服务已关闭。

在线结果：`qwen-image-3.0` 三次串行图生图均成功并下载，每次发送两张已批准参考、生成一张1024×1024 RGB图，0重试。铺地、灰墙、屋瓦三张位于 `assets/art/chengdu_crafted_street/`，准确参考、提示词、参数、SHA与原PNG不变记录在 [`source.json`](../assets/art/chengdu_crafted_street/source.json)。当前仅选入真实场景检查，用户试玩待验；在线调用成功不等于素材可直接平铺或游戏效果已获认可，见[四屋精作切片](CHENGDU_CRAFTED_STREET_SLICE.md)。文档不记录实际token、密钥、endpoint或工作空间地址。

## 离线检查与制作使用

使用Python 3.12或更新版本，在已配置checkout执行：

```sh
python3 tools/qwen_art.py doctor --no-network
python3 tools/qwen_art.py generate --prompt-file art/prompts/tingyu-actors/player-closed.txt --out art/work/tingyu-actors/player-closed.png --reference assets/art/v2/jiang-yanqiu-v2.png --size 1086x1448 --dry-run
```

`doctor --no-network` 只做离线检查，不调用线上接口。READY或dry-run通过只表示本地配置／请求准备情况，不能记为在线生图成功。按具体任务已确定的素材与提示词发送范围操作；移除 `--dry-run` 才会调用线上模型，可能产生费用。每次只生成一张，失败或结果不明时不自动重试。成功图仍需alpha、身份、画幅及真实场景检查才可接入。

## 显式环境与其他机器

同时设置当前进程的 `DASHSCOPE_API_KEY` 和完整 `QWEN_IMAGE_ENDPOINT` 时，launcher优先使用这对显式环境，不读取Linux密钥环或macOS钥匙串。只设置其中一项会拒绝执行，避免混用不同工作空间的凭据和接口。不要通过包含真实密钥的命令文本设置环境，以免进入命令记录或日志。Windows使用完整的显式环境配置；本机 `.local` 设置和密钥环内容不随Git共享。

选择与API Key相同区域的工作空间。接口说明见[百炼官方图像生成与编辑API](https://help.aliyun.com/zh/model-studio/qwen-image-generation-and-editing-api-reference)。本机配置页限定北京工作空间；显式环境是另一条配置路径，不把本机配置保存当作在线验证。

## 历史：macOS听雨廊配置与生成（2026-10-07）

以下为当时Mac checkout的完成记录，保留历史，不代表当前X1已配置或已在线验证：

听雨廊开发 checkout 已配置 `qwen-image-3.0`。`tools/qwen_art.py` 从 macOS 钥匙串读取已有 Qwen 凭据，传给当前生图子进程；本机工作空间与钥匙串条目位置放在忽略的 `.local/qwen-art.json`。没有复制密钥到文件，没有修改全局 shell 环境，没有改变既有文字模型服务。

离线 doctor 全项通过，首个姿态请求 dry-run 通过。READY 仅证明配置格式和本地读写就绪。首次在线调用曾被自动审批拒绝；用户随后明确回复「允许」，批准两张人物参考 PNG 与四份姿态提示词外发到已配置的北京工作空间。授权后的四张姿态均已成功生成并下载，没有自动重试，证明本次模型调用可用；不保证后续额度或持续可用性。原始输出均为 RGB，其中倾听图有烘焙棋盘格，没有真实透明通道。通过 `tools/compose_tingyu_actors.gd` 与 `art/prompts/tingyu-actors/composition.json` 将限定区域合成到原 RGBA；四张最终图的 alpha 与原图逐像素一致，身体与桌面锚点保持。真实 Godot 窗口与 Web 交互检查已完成，来源／配方见 `assets/art/tingyu_actors/source.json`。

### 历史macOS本机设置结构

macOS使用本机设置时，将下面非敏感结构保存到忽略的 `.local/qwen-art.json`，密钥留在钥匙串：

```json
{
  "endpoint": "https://YOUR_WORKSPACE.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/images/generations",
  "keychain_service": "YOUR_KEYCHAIN_SERVICE",
  "keychain_account": "YOUR_KEYCHAIN_ACCOUNT"
}
```

该结构属于macOS钥匙串分支，不复制为Linux／X1配置。密钥继续留在系统密钥存储中，不写入配置、参数、提示词、来源记录或Git。
