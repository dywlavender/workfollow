# WorkFollow 部署手册

版本：0.1.0

## 一、环境要求

### Linux

- 64 位 x86_64 Linux
- Python 3.12
- Python venv 和 pip
- 不需要安装 Node.js 或 npm；发布包内置 Node.js 运行时和协同服务依赖
- `curl`（启动脚本和验收检查使用）
- 8123、8124 端口未被其他程序占用

检查命令：

```bash
uname -m
python3 --version
python3 -m pip --version
python3 -m venv --help
curl --version
```

`uname -m` 应输出 `x86_64`，Python 应为 3.12。Debian/Ubuntu 如果缺少 venv，需安装对应的 `python3.12-venv` 系统包。

Linux 安装包适用于常见的 glibc 发行版，不适用于 ARM64、32 位系统和 Alpine/musl。

### Windows

- 64 位 Windows 10/11 或 Windows Server
- Python 3.12 x64
- 不需要安装 Node.js 或 npm；发布包内置 Node.js 运行时和协同服务依赖
- 安装 Python 时启用 `py launcher`，建议同时勾选“Add Python to PATH”
- `curl.exe`（启动脚本和验收检查使用）
- 8123、8124 端口未被其他程序占用

在命令提示符中检查：

```bat
py -3.12 --version
py -3.12 -c "import platform; print(platform.architecture())"
curl.exe --version
```

输出应显示 Python 3.12 和 64bit。

## 二、解压安装包

### Linux

```bash
sudo mkdir -p /opt/workfollow
sudo tar -xzf WorkFollow-0.1.0-linux-x86_64.tar.gz -C /opt/workfollow
sudo chown -R "$USER":"$(id -gn)" /opt/workfollow
cd /opt/workfollow
chmod +x deploy/linux/*.sh
```

不要使用 root 账户直接运行 WorkFollow；以上命令把目录交给当前登录用户管理。

### Windows

将 `WorkFollow-0.1.0-windows-x64.zip` 解压到固定目录，例如 `C:\WorkFollow`，建议使用不含中文和空格的目录。随后打开命令提示符：

```bat
cd /d C:\WorkFollow
```

## 三、安装项目依赖

前端已经构建完成，协同服务也使用发布包内置的 Node.js 运行时启动。目标机不需要安装 Node.js、npm，也不需要重新构建前端。

正式发布包应包含以下离线内容：

- `frontend/dist/`：已经构建的前端；
- `collaboration/node_modules/`：协同服务生产依赖；
- Linux 包的 `runtime/node/bin/node` 或 Windows 包的 `runtime/node/node.exe`：协同服务运行时；
- `wheelhouse/`：与目标操作系统及 Python 3.12 匹配的 Python wheel；
- `docs/mcp-integration.md`：Codex、Claude Code 和 WorkBuddy 接入说明。

如果发布包缺少 `wheelhouse`，安装脚本会尝试在线安装 Python 依赖，因此不能再视为完全离线包。内置 Node.js 运行时或协同依赖缺失时，安装脚本会直接停止；目标机不会调用 npm 补装。

### Linux

```bash
cd /opt/workfollow
./deploy/linux/install.sh
```

脚本会检查 Python 3.12 和包内 Node.js 运行时、创建 `.venv` 虚拟环境、从 `wheelhouse` 安装 Python 依赖、创建数据目录，并初始化或升级 SQLite 数据库。安装过程不会访问 npm。

### Windows

```bat
cd /d C:\WorkFollow
deploy\windows\install.bat
```

如果使用内部 PyPI 镜像，先设置镜像地址（仅 Python 依赖需要）：

```bat
set PIP_INDEX_URL=https://你的内网PyPI镜像/simple
deploy\windows\install.bat
```

Linux 使用内部镜像：

```bash
PIP_INDEX_URL=https://你的内网PyPI镜像/simple ./deploy/linux/install.sh
```

## 四、初始化系统管理员

首次部署必须显式创建一个系统管理员账号。该命令只允许成功执行一次，密码由部署人员自行设置，不存在默认管理员密码。

### Linux

```bash
cd /opt/workfollow
PYTHONPATH=backend .venv/bin/python -m app.cli init-root \
  --username admin \
  --password '请替换为强密码' \
  --nickname 系统管理员
```

### Windows

```bat
cd /d C:\WorkFollow
set PYTHONPATH=backend
.venv\Scripts\python.exe -m app.cli init-root ^
  --username admin ^
  --password 请替换为强密码 ^
  --nickname 系统管理员
```

## 五、启动项目

后端和协同服务共用根目录 `.env` 中的 `WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN`。只需配置一次，协同服务启动时会自动读取，不需要再单独传入同一个令牌；使用启动脚本时如果没有配置，脚本会自动生成并复用本次启动的令牌。

### Linux

```bash
cd /opt/workfollow
./deploy/linux/start.sh
```

默认监听 `0.0.0.0:8123`，浏览器访问：

```text
http://服务器IP:8123
```

如果只允许服务器本机访问：

```bash
WORKFOLLOW_HOST=127.0.0.1 ./deploy/linux/start.sh
```

如果需要修改端口：

```bash
WORKFOLLOW_PORT=9000 ./deploy/linux/start.sh
```

如果修改协同端口，启动脚本会同步设置后端内部使用的协同 HTTP 地址：

```bash
WORKFOLLOW_COLLABORATION_PORT=9124 ./deploy/linux/start.sh
```

### Windows

```bat
cd /d C:\WorkFollow
deploy\windows\start.bat
```

本机访问 `http://localhost:8123`。其他电脑访问时使用 `http://Windows部署机IP:8123`，并在 Windows Defender 防火墙中对可信内网放行 TCP 8123 和 8124（8124 是任务、个人笔记和团队知识草稿协同服务端口）。

生产脚本会把 FastAPI 使用的 `WORKFOLLOW_COLLABORATION_HTTP_URL` 固定到本机协同端口。8124 对浏览器提供 WebSocket，同时供本机后端执行 Agent 文档操作；不要把内部协同接口单独暴露到不可信网络。

## 六、验证项目

在浏览器中打开首页，使用第四节创建的系统管理员账号登录。

健康检查地址：

```text
http://服务器IP:8123/api/health
```

正常结果：

```json
{"status":"ok","database":"ok","version":"0.1.0"}
```

协同服务检查：

```text
http://服务器IP:8124/health
```

Linux 还可以执行以下依赖自检，确认 Agent/MCP 所需模块已经离线安装：

```bash
.venv/bin/python -c "import fastapi, httpx, mcp; print('Python dependencies OK')"
runtime/node/bin/node --version
```

Windows：

```bat
.venv\Scripts\python.exe -c "import fastapi, httpx, mcp; print('Python dependencies OK')"
runtime\node\node.exe --version
```

## 七、停止和查看日志

### Linux

```bash
./deploy/linux/status.sh
tail -f logs/workfollow.log
./deploy/linux/stop.sh
```

### Windows

日志文件为 `C:\WorkFollow\logs\workfollow.log`。停止项目：

```bat
deploy\windows\stop.bat
```

## 八、数据迁移和备份

业务数据保存在安装目录的 `data` 文件夹，包括 SQLite 数据库和附件。

迁移旧数据：

1. 停止旧环境和新环境的 WorkFollow。
2. 备份新环境的 `data` 文件夹。
3. 将旧环境的整个 `data` 文件夹复制到新安装目录。
4. 再次执行新环境的安装脚本，升级数据库。
5. 启动并执行健康检查。

升级当前版本时必须运行数据库迁移；Agent 写操作记录使用的新表会在迁移到 `0034` 时创建。不要只替换前端文件而跳过安装脚本。

Linux 备份：

```bash
./deploy/linux/backup.sh
```

Windows 备份：

```bat
deploy\windows\backup.bat
```

建议先停止项目再备份，确保数据库和附件保持一致。

## 九、可选：完全离线安装依赖

如果目标机完全不能联网，需要先在可联网且与目标机同操作系统、同 CPU 架构、同 Python 版本的机器上准备 wheelhouse。Linux 和 Windows 的 Python 包不能混用。

Linux 联网机：

```bash
mkdir -p wheelhouse/linux
python3.12 -m pip download --only-binary=:all: \
  -r deploy/requirements-offline.txt \
  -d wheelhouse/linux
```

Windows 联网机：

```bat
mkdir wheelhouse\windows
py -3.12 -m pip download --only-binary=:all: ^
  -r deploy\requirements-offline.txt ^
  -d wheelhouse\windows
```

把两个目录收集到打包机的 `wheelhouse/linux` 和 `wheelhouse/windows`，然后在仓库根目录运行：

```bash
./deploy/build-deployment-packages.sh --version 0.1.0 --require-offline
```

打包机需要 Node.js、npm、`curl`、`tar`、`zip` 和 `unzip`，并通常需要联网安装前端与协同服务依赖。目标机不需要 Node.js、npm 或网络。脚本会在隔离临时目录构建前端、打包协同服务生产依赖，下载并缓存 Linux/Windows 便携版 Node.js，然后分别把对应 wheelhouse 放进发布包。`--require-offline` 会在任一平台缺少 wheel 时直接停止，避免误把需要联网安装的普通包当成离线包交付。

Node.js 运行时默认缓存在仓库根目录的 `.runtime-cache/node`。如果打包机本身也不能联网，可先在联网环境准备以下官方归档，再复制到该目录：

```text
.runtime-cache/node/node-v22.23.2-linux-x64.tar.xz
.runtime-cache/node/node-v22.23.2-win-x64.zip
```

要切换内置运行时版本，可在打包时设置 `WORKFOLLOW_NODE_RUNTIME_VERSION`；对应文件名也必须使用同一版本。该变量只影响发布包内置运行时，不改变构建机自身执行 `npm` 所用的 Node.js。

交付前应解压到临时目录检查以下文件存在：

```text
frontend/dist/index.html
collaboration/node_modules/@hocuspocus/server/package.json
collaboration/node_modules/@hocuspocus/transformer/package.json
collaboration/node_modules/yjs/package.json
runtime/node/bin/node                  # Linux 包
runtime/node/node.exe                  # Windows 包
wheelhouse/*.whl
deploy/requirements-offline.txt
docs/mcp-integration.md
```

随后在一台断网验收机上实际运行安装脚本。仅看到压缩包生成成功，不能证明依赖完整。

## 十、常见问题

- Python 版本错误：安装 Python 3.12 x64，不要使用 3.11、3.13 或 32 位 Python。
- 离线安装仍尝试联网：发布包没有包含对应平台的 `wheelhouse`，重新制作完整发布包。
- `No matching distribution found`：wheelhouse 与目标操作系统、CPU 架构或 Python 3.12 不匹配。
- 提示内置 Node.js 缺失：发布包制作或解压不完整；重新生成并完整解压发布包，不需要在目标机安装 Node.js。
- MCP Server 提示缺少模块：确认 `deploy/requirements-offline.txt` 包含并已安装 `httpx` 和 `mcp`，再执行第六节依赖自检。
- 页面无法访问：检查服务状态、8123 端口、防火墙和日志。
- 多人正文或任务属性没有实时同步：检查协同服务日志、8124 端口和防火墙；浏览器必须能访问与业务页面同一主机的 8124 端口，并确认所有客户端使用同一版本。个人笔记使用 `note:<id>`，管理员团队知识草稿使用 `knowledge-draft:<id>`；团队知识点击“保存修改”后才更新已发布版本。
- Agent 能查询但不能修改笔记或任务：确认 8124 服务健康，并确认 `WORKFOLLOW_COLLABORATION_HTTP_URL` 指向部署机本地的协同端口。
- 页面显示 404：确认 `frontend/dist/index.html` 存在。
- 数据库启动失败：先备份 `data`，再重新执行安装脚本。

## 十一、安全提示

默认使用 HTTP 并监听 `0.0.0.0`，只适合可信内网。跨公网部署时，应为 8123 和 8124 同时增加 HTTPS/WSS 反向代理并限制防火墙来源。`data` 和 `backups` 可能包含敏感业务信息，应严格控制目录权限。

## 十二、可选：离线环境接入 Agent / MCP

部署完成后，在 WorkFollow 的“设置 → 账号 → Agent 接入”生成账号唯一 Token，再按发布包中的 `docs/mcp-integration.md` 配置客户端。

当前接入方式是本地 STDIO MCP：MCP 进程运行在哪台电脑，配置中的 Python 路径就必须存在于哪台电脑。因此，在 WorkFollow 部署机上运行 Codex 时可以直接使用 `/opt/workfollow/.venv/bin/python`；如果 Codex 在另一台电脑上，不能引用服务器文件路径，需要在客户端电脑部署同一 MCP 适配器及 Python 依赖，并把 `WORKFOLLOW_API_URL` 指向服务器地址。

Linux 同机部署示例：

```toml
[mcp_servers.workfollow]
command = "/opt/workfollow/.venv/bin/python"
args = ["-m", "app.mcp_server"]
cwd = "/opt/workfollow/backend"
env = { WORKFOLLOW_AGENT_TOKEN = "wf_请替换", WORKFOLLOW_API_URL = "http://127.0.0.1:8123/api" }
default_tools_approval_mode = "writes"
```

保存后重启客户端并查看 MCP 连接状态。重置 WorkFollow Token 后，所有客户端中的旧 Token 都会失效。

## 十三、外部 HTTP 通知配置

WorkFollow 可以将任务分配、取消分配、完成、每日待办汇总，以及团队知识投稿的待审核和审核结果发送到外部 HTTP 通知接口。接口由后端调用，默认使用 GET，并为每个用户单独发送：

```text
GET {配置的URL}?userIds={系统用户名}&msg={消息内容}&url={浏览器跳转地址}
```

其中 `userIds` 必须使用 WorkFollow 中的系统用户名，不是用户昵称或内部 ID；`msg` 和 `url` 都会进行 URL 编码。`url` 是可直接打开的业务深链接：未登录时先进入登录页，登录完成后回到对应任务、投稿审核页或团队知识页。

在项目根目录的 `.env` 中配置：

```text
WORKFOLLOW_NOTIFICATION_HTTP_URL=https://通知服务地址/notify
WORKFOLLOW_SERVER_URL=https://WorkFollow对外访问地址
WORKFOLLOW_NOTIFICATION_HTTP_TIMEOUT_SECONDS=5
WORKFOLLOW_NOTIFICATION_HTTP_RETRY_COUNT=3
WORKFOLLOW_NOTIFICATION_TASK_EDIT_QUIET_SECONDS=3
WORKFOLLOW_NOTIFICATION_TIMEZONE=Asia/Shanghai
WORKFOLLOW_NOTIFICATION_DAILY_DIGEST_TIME=08:30
```

`WORKFOLLOW_NOTIFICATION_TASK_EDIT_QUIET_SECONDS` 控制标题和正文协同投影通知的合并等待时间，默认 3 秒；截止时间、优先级、成员、完成等明确动作仍会立即通知。配置后重启 WorkFollow，后台发送器会自动处理待发送通知。任务或知识审核操作不会因为外部接口暂时不可用而失败，失败通知会自动重试。接口中台只需按现有 GET 规范读取 `userIds`、`msg`，并将 `url` 渲染为可点击链接即可。
