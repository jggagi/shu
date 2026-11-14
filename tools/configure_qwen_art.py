"""One-use loopback setup for Shu's existing Qwen art launcher.

API keys enter through a password form and are stored in Linux Secret Service.
Only a non-secret endpoint and credential identifier enter ignored local config.
No provider requests, package installation or global environment changes.
"""
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import tempfile
import threading
from urllib.parse import parse_qs, urlsplit

from qwen_art import ROOT, SECRET_TOOL, SETTINGS, private_settings, single_line_key, validate_endpoint


def loopback_origin(value):
    match = re.fullmatch(r"http://(?:127\.0\.0\.1|localhost):([1-9][0-9]{0,4})", value)
    if not match or int(match[1]) > 65535:
        raise ValueError("Use an exact http://localhost:PORT or http://127.0.0.1:PORT browser origin")
    return value


def beijing_endpoint(value):
    value = value.strip()
    if not value.startswith("https://"):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", value):
            raise ValueError("请输入北京工作空间ID，或控制台提供的完整生图接口地址。")
        value = "https://" + value + ".cn-beijing.maas.aliyuncs.com/compatible-mode/v1/images/generations"
    validate_endpoint(value)
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}\.cn-beijing\.maas\.aliyuncs\.com", urlsplit(value).hostname):
        raise ValueError("此配置页使用北京工作空间，请使用相同区域的API Key。")
    return value


def save_configuration(endpoint, key):
    endpoint = beijing_endpoint(endpoint)
    key = single_line_key(key.strip())
    directory = SETTINGS.parent
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    meta = directory.lstat()
    if not stat.S_ISDIR(meta.st_mode) or meta.st_uid != os.getuid() or meta.st_mode & 0o022:
        raise ValueError("项目本机配置目录权限不正确。")
    secret_id = secrets.token_hex(16)
    if SETTINGS.exists() or SETTINGS.is_symlink():
        previous = private_settings()
        if re.fullmatch(r"[a-f0-9]{32}", str(previous.get("secret_id", ""))):
            secret_id = previous["secret_id"]
    config = {"schema_version": 1, "endpoint": endpoint, "secret_id": secret_id}
    fd, temporary = tempfile.mkstemp(prefix=".qwen-settings-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            os.fchmod(handle.fileno(), 0o600)
            json.dump(config, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        stored = subprocess.run([SECRET_TOOL, "store", "--label=蜀 · 百炼生图", "application", "shu-art", "profile", secret_id],
                                input=key.encode("ascii"), capture_output=True, timeout=45)
        if stored.returncode != 0:
            raise ValueError("系统密钥环未能保存。请解锁KDE钱包后重试；未调用百炼接口。")
        check = subprocess.run([SECRET_TOOL, "lookup", "application", "shu-art", "profile", secret_id],
                               stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
        if check.returncode != 0 or not hmac.compare_digest(check.stdout.strip(), key.encode("ascii")):
            raise ValueError("密钥环读取校验未通过；未调用百炼接口。")
        os.replace(temporary, SETTINGS)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def form(token):
    return """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>蜀 · 百炼生图配置</title><style>
body{background:#f3efe4;color:#302e28;font:17px/1.65 system-ui;margin:0;padding:38px 22px}main{max-width:640px;margin:auto;background:#fffdf7;padding:30px;border:1px solid #d8ceb8;border-radius:12px}h1{font-size:25px}label{display:block;font-weight:650;margin-top:22px}input{box-sizing:border-box;width:100%;padding:12px;border:1px solid #bdb49e;border-radius:6px;font:15px system-ui;margin-top:7px}button{margin-top:25px;background:#3b6355;color:white;border:0;border-radius:6px;padding:12px 22px;font:17px system-ui}small{color:#676359}a{color:#365f50}
</style><main><h1>百炼生图 · 本机配置</h1><p>模型：<strong>qwen-image-3.0 标准版</strong>。使用北京工作空间，API Key须来自相同区域。</p>
<form method="post" action="/configure" autocomplete="off"><input type="hidden" name="token" value="TOKEN">
<label for="workspace">北京工作空间ID，或完整生图接口地址</label><input id="workspace" name="workspace" required maxlength="500" placeholder="工作空间ID / https://…cn-beijing.maas.aliyuncs.com/compatible-mode/v1/images/generations" autocomplete="off" spellcheck="false">
<small>从百炼控制台工作空间的API调用示例复制；不要填写模型名称或聊天接口地址。</small>
<label for="key">API Key</label><input id="key" type="password" name="api_key" required minlength="8" maxlength="4096" autocomplete="new-password" spellcheck="false">
<small>密钥只写入当前用户的系统密钥环。若系统弹出钱包解锁提示，请完成解锁。</small><br><button type="submit">保存到本机密钥环</button></form>
<p><small>保存配置不发起付费生图。页面仅由本机临时服务提供，成功后关闭服务。<a href="https://help.aliyun.com/zh/model-studio/qwen-image-generation-and-editing-api-reference" target="_blank" rel="noopener noreferrer">官方接口说明</a></small></p></main></html>""".replace("TOKEN", token)


class SetupHandler(BaseHTTPRequestHandler):
    def setup(self):
        self.request.settimeout(10)
        super().setup()

    def handle(self):
        try:
            super().handle()
        except (OSError, ValueError):
            # Malformed/unfinished local requests must never log request data.
            pass

    def log_message(self, *_args):
        pass

    def reply(self, status, html):
        data = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(data)

    def local_host(self):
        return "http://" + self.headers.get("Host", "") in self.server.allowed_origins

    def valid_token(self, token):
        return bool(re.fullmatch(r"[a-f0-9]{48}", token)) and hmac.compare_digest(token, self.server.setup_token)

    def do_GET(self):
        try:
            url = urlsplit(self.path)
            token = parse_qs(url.query, max_num_fields=1).get("token", [""])
            valid = self.local_host() and url.path == "/setup" and len(token) == 1 and self.valid_token(token[0])
        except ValueError:
            valid = False
        if not valid:
            self.reply(403, "配置入口无效或已关闭。")
            return
        self.reply(200, form(self.server.setup_token))

    def do_POST(self):
        host = self.headers.get("Host", "")
        if (self.path != "/configure" or not self.local_host()
                or self.headers.get("Origin") != "http://"+host
                or self.headers.get("Origin") not in self.server.allowed_origins
                or self.headers.get("Content-Type", "").split(";", 1)[0] != "application/x-www-form-urlencoded"
                or self.server.saved):
            self.reply(403, "配置请求无效。请使用原本机配置页。")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 20000:
                raise ValueError()
            fields = parse_qs(self.rfile.read(length).decode("utf-8"), keep_blank_values=True, max_num_fields=3)
            if set(fields) != {"token", "workspace", "api_key"} or any(len(value) != 1 for value in fields.values()):
                raise ValueError()
            if not self.valid_token(fields["token"][0]):
                raise ValueError()
            save_configuration(fields["workspace"][0], fields["api_key"][0])
        except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
            self.reply(400, "<!doctype html><meta charset=utf-8><p>未能完成配置。请确认北京工作空间ID或完整接口地址、API Key格式，并解锁系统钱包。没有调用百炼接口。返回上一页重试。</p>")
            return
        self.server.saved = True
        self.reply(200, "<!doctype html><meta charset=utf-8><p>配置已保存到本机系统密钥环，读取校验通过。没有发起付费生图。可以关闭此页。</p>")
        print("[OK] Qwen image credential stored in the system wallet; no provider request made.", flush=True)
        threading.Thread(target=self.server.shutdown, daemon=True).start()


class SetupServer(HTTPServer):
    def __init__(self, address, handler):
        super().__init__(address, handler)
        self.allowed_origins = {"http://127.0.0.1:"+str(self.server_port), "http://localhost:"+str(self.server_port)}

    def handle_error(self, _request, _client_address):
        # Never include exception text, paths or form values in server logs.
        print("[ERROR] Local setup request failed; no request details logged.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--browser-origin", action="append", type=loopback_origin, default=[],
                        help="Exact loopback browser origin used by an existing SSH/app port forward")
    args = parser.parse_args()
    if not Path(SECRET_TOOL).is_file():
        raise SystemExit("System secret-tool is unavailable; no configuration changed.")
    server = SetupServer(("127.0.0.1", args.port), SetupHandler)
    server.allowed_origins.update(args.browser_origin)
    server.setup_token = secrets.token_hex(24)
    server.saved = False
    timer = threading.Timer(args.timeout, server.shutdown)
    timer.daemon = True
    timer.start()
    print("Setup URL: http://127.0.0.1:"+str(server.server_port)+"/setup?token="+server.setup_token, flush=True)
    print("Listening on loopback only. No request/body logging. Store only; no paid generation.", flush=True)
    try:
        server.serve_forever()
    finally:
        timer.cancel()
        server.server_close()
    return 0 if server.saved else 2


if __name__ == "__main__":
    raise SystemExit(main())
