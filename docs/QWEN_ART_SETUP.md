# Qwen 美术制作配置

## 本机状态（2026-10-07）

听雨廊开发 checkout 已配置 `qwen-image-3.0`。`tools/qwen_art.py` 从 macOS 钥匙串读取已有 Qwen 凭据，传给当前生图子进程；本机工作空间与钥匙串条目位置放在忽略的 `.local/qwen-art.json`。没有复制密钥到文件，没有修改全局 shell 环境，没有改变既有文字模型服务。

离线 doctor 全项通过，首个姿态请求 dry-run 通过。READY 仅证明配置格式和本地读写就绪。首次在线调用曾被自动审批拒绝；用户随后明确回复「允许」，批准两张人物参考 PNG 与四份姿态提示词外发到已配置的北京工作空间。授权后的四张姿态均已成功生成并下载，没有自动重试，证明本次模型调用可用；不保证后续额度或持续可用性。原始输出均为 RGB，其中倾听图有烘焙棋盘格，没有真实透明通道。通过 `tools/compose_tingyu_actors.gd` 与 `art/prompts/tingyu-actors/composition.json` 将限定区域合成到原 RGBA；四张最终图的 alpha 与原图逐像素一致，身体与桌面锚点保持。真实 Godot 窗口与 Web 交互检查已完成，来源／配方见 `assets/art/tingyu_actors/source.json`。

## 使用

使用 Python 3.12 或更新版本，在已配置 checkout 执行：

```sh
python3 tools/qwen_art.py doctor --no-network
python3 tools/qwen_art.py generate --prompt-file art/prompts/tingyu-actors/player-closed.txt --out art/work/tingyu-actors/player-closed.png --reference assets/art/v2/jiang-yanqiu-v2.png --size 1086x1448 --dry-run
```

确认具体生图任务的发送范围后，移除 `--dry-run` 才会调用线上模型，可能产生费用。每次只生成一张，失败或结果不明时不自动重试。成功图仍需 alpha、身份、画幅及真实场景检查才可接入。

## 其他机器

同时设置进程环境 `DASHSCOPE_API_KEY` 和完整 `QWEN_IMAGE_ENDPOINT` 时，launcher 优先使用这对显式配置，不读取钥匙串。只设置其中一项会拒绝执行，避免混用不同工作空间的凭据和接口。Windows 使用显式环境配置；本机 `.local` 设置不随 Git 共享。

macOS 使用本机设置时，将下面非敏感结构保存到忽略的 `.local/qwen-art.json`，密钥留在钥匙串：

```json
{
  "endpoint": "https://YOUR_WORKSPACE.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/images/generations",
  "keychain_service": "YOUR_KEYCHAIN_SERVICE",
  "keychain_account": "YOUR_KEYCHAIN_ACCOUNT"
}
```

选择与 API Key 相同区域的工作空间。接口格式见 [百炼官方图像生成与编辑 API](https://help.aliyun.com/zh/model-studio/qwen-image-generation-and-editing-api-reference)。不要将密钥放入参数、提示词、配置、来源记录或 Git。
