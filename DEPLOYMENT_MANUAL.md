# WorkFollow 部署手册

版本：0.1.0

## 一、环境要求

### Linux

- 64 位 x86_64 Linux
- Python 3.12
- Python venv 和 pip
- Node.js 22+（用于运行任务正文及元数据协同服务；npm 仅在依赖缺失时需要）
- 发布包已内置协同服务的 Node 依赖；只有从源码部署且依赖缺失时才需要 npm 网络或内部镜像
- 8123、8124 端口未被其他程序占用

检查命令：

```bash
uname -m
python3 --version
python3 -m pip --version
python3 -m venv --help
node --version
npm --version
```

`uname -m` 应输出 `x86_64`，Python 应为 3.12。Debian/Ubuntu 如果缺少 venv，需安装对应的 `python3.12-venv` 系统包。

Linux 安装包适用于常见的 glibc 发行版，不适用于 ARM64、32 位系统和 Alpine/musl。

### Windows

- 64 位 Windows 10/11 或 Windows Server
- Python 3.12 x64
- Node.js 22+（用于运行任务正文及元数据协同服务；npm 仅在依赖缺失时需要）
- 安装 Python 时启用 `py launcher`，建议同时勾选“Add Python to PATH”
- 发布包已内置协同服务的 Node 依赖；只有从源码部署且依赖缺失时才需要 npm 网络或内部镜像
- 8123、8124 端口未被其他程序占用

在命令提示符中检查：

```bat
py -3.12 --version
py -3.12 -c "import platform; print(platform.architecture())"
node --version
npm --version
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

前端已经构建完成，不需要在目标机重新构建前端；但目标机仍需安装 Node.js 22+，用于启动任务、个人笔记和管理员团队知识草稿的 Yjs/Hocuspocus 协同服务。

### Linux

```bash
cd /opt/workfollow
./deploy/linux/install.sh
```

脚本会检查 Python 3.12、创建 `.venv` 虚拟环境、安装 Python 依赖、创建数据目录，并初始化或升级 SQLite 数据库。发布包已包含协同服务的生产依赖，检测到依赖完整时不会访问 npm。

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

### Windows

```bat
cd /d C:\WorkFollow
deploy\windows\start.bat
```

本机访问 `http://localhost:8123`。其他电脑访问时使用 `http://Windows部署机IP:8123`，并在 Windows Defender 防火墙中对可信内网放行 TCP 8123 和 8124（8124 是任务、个人笔记和团队知识草稿协同服务端口）。

## 六、验证项目

在浏览器中打开首页，首次使用时注册账号。

健康检查地址：

```text
http://服务器IP:8123/api/health
```

正常结果：

```json
{"status":"ok","database":"ok","version":"0.1.0"}
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

如果目标机完全不能联网，发布包中的协同服务依赖无需另行下载；只需为 Python 依赖准备 wheelhouse。

Linux 联网机：

```bash
mkdir -p wheelhouse
python3.12 -m pip download -r deploy/requirements-offline.txt -d wheelhouse
```

Windows 联网机：

```bat
mkdir wheelhouse
py -3.12 -m pip download -r deploy\requirements-offline.txt -d wheelhouse
```

将 `wheelhouse` 连同整个项目复制到目标机，再运行对应安装脚本。脚本检测到 wheel 文件后会自动使用本地依赖，不访问网络；发布包检测到 `collaboration/node_modules` 后也不会运行 npm。Linux 和 Windows 的 Python 依赖包不能混用。

## 十、常见问题

- Python 版本错误：安装 Python 3.12 x64，不要使用 3.11、3.13 或 32 位 Python。
- 依赖下载失败：检查网络、代理或 `PIP_INDEX_URL`。
- 页面无法访问：检查服务状态、8123 端口、防火墙和日志。
- 多人正文或任务属性没有实时同步：检查协同服务日志、8124 端口和防火墙；浏览器必须能访问与业务页面同一主机的 8124 端口，并确认所有客户端使用同一版本。个人笔记使用 `note:<id>`，管理员团队知识草稿使用 `knowledge-draft:<id>`；团队知识点击“保存修改”后才更新已发布版本。
- 页面显示 404：确认 `frontend/dist/index.html` 存在。
- 数据库启动失败：先备份 `data`，再重新执行安装脚本。

## 十一、安全提示

默认使用 HTTP 并监听 `0.0.0.0`，只适合可信内网。跨公网部署时，应为 8123 和 8124 同时增加 HTTPS/WSS 反向代理并限制防火墙来源。`data` 和 `backups` 可能包含敏感业务信息，应严格控制目录权限。

## 十二、外部 HTTP 通知配置

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
