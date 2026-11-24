# WordPress + Nginx + MariaDB（Docker Compose，HTTPS 自签名证书）

基于 Docker Compose 一键部署的 WordPress 站点，前置 Nginx 反向代理，**默认启用 HTTPS（自签名证书）**，并将 HTTP 80 端口自动 301 跳转到 HTTPS。

## 目录结构

```
.
├── docker-compose.yml      # 服务编排：db / wordpress / nginx
├── .env.example            # 环境变量模板（提交到仓库）
├── .env                    # 本地环境变量（由 .env.example 复制而来，不提交）
├── .gitignore
├── generate-certs.sh       # 生成自签名 TLS 证书
├── nginx/
│   └── default.conf        # Nginx 配置（80->443 跳转 + 443 SSL 反代）
└── certs/                  # 证书目录（已生成，密钥已被 .gitignore 忽略）
    ├── nginx.crt
    └── nginx.key
```

## 环境变量（.env）

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DB_NAME` | `wordpress` | 数据库名 |
| `DB_USER` | `wordpress` | 数据库用户 |
| `DB_PASSWORD` | `wordpress_pass` | 数据库密码（请修改） |
| `DB_ROOT_PASSWORD` | `root_pass` | 数据库 root 密码（请修改） |
| `HTTP_PORT` | `80` | 宿主机 HTTP 端口（仅用于跳转到 HTTPS） |
| `HTTPS_PORT` | `443` | 宿主机 HTTPS 端口 |
| `SERVER_NAME` | `localhost` | 自签名证书的域名，运行 `generate-certs.sh` 时读取 |

> `.env` 不提交到仓库，仅跟踪模板 `.env.example`。首次使用请先 `cp .env.example .env`，再修改其中的值。生产使用请务必修改数据库密码；如绑定域名，把 `SERVER_NAME` 改成你的域名。

## 快速开始

### 1. 配置环境变量

首次使用需从模板复制一份 `.env`，并按需修改（特别是数据库密码、域名）：

```bash
cp .env.example .env
```

> `.env` 已被 `.gitignore` 忽略，不会提交到仓库；仓库中只跟踪 `.env.example` 模板。各变量含义见上方「环境变量」表。

### 2. 生成自签名证书（已生成，可跳过）

```bash
./generate-certs.sh            # 使用 .env 中的 SERVER_NAME（默认 localhost）
# 或指定域名：
./generate-certs.sh your.domain.com
```

证书默认有效期 3650 天，包含 SAN（`DNS:<域名>, DNS:localhost, IP:127.0.0.1`），生成在 `certs/nginx.crt` 与 `certs/nginx.key`。

如需自定义有效期：

```bash
CERT_DAYS=825 ./generate-certs.sh
```

### 3. 启动服务

```bash
docker compose up -d
```

首次启动时会自动执行一次性服务 `wpcli`：按当前 WordPress 版本下载并安装简体中文语言包，并把站点语言设为 `zh_CN`。执行完该容器会以退出码 0 结束（`Exited (0)` 属正常，不影响站点）。

```bash
docker compose logs wpcli     # 查看语言包安装结果
```

> 如需其他语言，修改 [docker-compose.yml](docker-compose.yml) 中 `wpcli` 服务的 `zh_CN`（如 `zh_TW`、`ja`）后重新执行 `docker compose up -d wpcli`。
> 若后续在后台切换了语言，WordPress 会在「更新 → 更新翻译」时自行维护 `wp-content/languages`。

查看状态与日志：

```bash
docker compose ps
docker compose logs -f nginx
```

### 4. 访问

浏览器打开 **https://localhost**（或你的域名/IP）。

由于是**自签名证书**，浏览器会提示“不安全/证书不受信任”，这是正常现象——点击“高级”→“继续访问”即可。消除警告的方法见下文。

> HTTP `http://localhost` 会自动 301 跳转到 HTTPS。

## 关于自签名证书

- **为什么浏览器告警？** 自签名证书没有受信任的 CA 签发，浏览器默认不信任。仅适合**本地开发、内网测试**。
- **信任本机证书（消除告警）：**
  - macOS：`sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/nginx.crt`
  - Linux（Debian/Ubuntu）：`sudo cp certs/nginx.crt /usr/local/share/ca-certificates/nginx.crt && sudo update-ca-certificates`
  - Windows：双击 `nginx.crt` → 安装证书 → 存入“受信任的根证书颁发机构”
- 生产环境请替换为正式证书（如 Let's Encrypt），见下文。

## 更换域名 / 重新生成证书

1. 修改 `.env` 中的 `SERVER_NAME`。
2. 重新生成证书：
   ```bash
   ./generate-certs.sh
   ```
3. 重载 Nginx：
   ```bash
   docker compose exec nginx nginx -s reload
   ```

## 反向代理 HTTPS 与 WordPress

Nginx 通过 `X-Forwarded-Proto: https` 头告知 WordPress 请求来自 HTTPS。`docker-compose.yml` 中的 `WORDPRESS_CONFIG_EXTRA` 会自动向 `wp-config.php` 注入：

```php
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('FORCE_SSL_ADMIN', true);
```

这样可避免后台重定向循环、混合内容（HTTP/HTTPS 混用）等问题。

> 注意：compose 中写为 `$$_SERVER` 是为了**转义 `$`**，防止 Docker Compose 把 `$_SERVER` 当成变量插值掉；运行到容器内会还原为 `$_SERVER`。

如果站点此前是以 HTTP 安装的，切换 HTTPS 后还需在 WordPress 设置里把“WordPress 地址 / 站点地址”改为 `https://`，或在 `wp-config.php` 中固定：

```php
define('WP_HOME', 'https://your.domain.com');
define('WP_SITEURL', 'https://your.domain.com');
```

## 将来替换为正式证书（可选）

Nginx 配置中已预留 `/.well-known/acme-challenge/` 位置。申请 Let's Encrypt 证书后，把 `fullchain.pem` / `privkey.pem` 放到 `certs/` 并修改 `nginx/default.conf` 中两个 `ssl_certificate*` 路径指向它们即可。同时可取消注释 HSTS 响应头。

## 常用命令

```bash
docker compose up -d          # 启动
docker compose down           # 停止并移除容器（数据卷保留）
docker compose down -v        # 停止并移除容器与数据卷（⚠️ 清空数据）
docker compose exec nginx nginx -t       # 校验 Nginx 配置
docker compose exec nginx nginx -s reload # 重载 Nginx 配置
docker compose logs -f                 # 查看全部日志
```

## 数据持久化

- 数据库数据：`./db-data`（挂载到 MariaDB 容器）
- WordPress 站点文件：`./wp-data`（挂载到 WordPress 容器，含上传的媒体、插件、主题）
- 两个目录均已加入 `.gitignore`，不会被提交。
