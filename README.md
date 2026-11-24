# WordPress + Nginx + MariaDB（Docker Compose，HTTPS 自签名证书）

基于 Docker Compose 一键部署的 WordPress 站点，前置 Nginx 反向代理，**默认启用 HTTPS（自签名证书）**，并将 HTTP 80 端口自动 301 跳转到 HTTPS。

## 目录结构

```
.
├── docker-compose.yml      # 服务编排：db / wordpress / nginx
├── Dockerfile              # 构建 WordPress 镜像并内置中文语言包
├── .dockerignore           # 构建上下文排除项
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
| `WORDPRESS_VERSION` | `7.1.5` | WordPress 基础镜像版本（构建镜像时使用） |
| `WP_LANG` | `zh_CN` | 站点语言，语言包在构建镜像时内置（`zh_TW`、`ja` 等） |

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

### 3. 构建并启动服务

```bash
docker compose up -d --build
```

首次会基于根目录的 [Dockerfile](Dockerfile) 构建镜像：按 `WORDPRESS_VERSION` 拉取官方镜像，并在构建阶段把 `WP_LANG` 对应的语言包下载进 `/usr/src/wordpress/wp-content/languages`。构建上下文为项目根目录，已通过 `.dockerignore` 排除 `wp-data/`、`db-data/`、`certs/` 等。不修改官方 ENTRYPOINT——首次启动（`./wp-data` 为空）时官方 entrypoint 会把 `/usr/src/wordpress` 完整复制进数据卷，语言包随之生效并自动归属 `www-data`。

> 修改 Dockerfile 或更换 `WP_LANG` / `WORDPRESS_VERSION` 后，需要重新构建：`docker compose up -d --build`。
> 升级 WordPress 版本：把 `.env` 里的 `WORDPRESS_VERSION` 改成新版本后重新构建，语言包会自动匹配新版本。

查看状态与日志：

```bash
docker compose ps
docker compose logs -f nginx
```

### 4. 访问

浏览器打开 **https://localhost**（或你的域名/IP）。

由于是**自签名证书**，浏览器会提示“不安全/证书不受信任”，这是正常现象——点击“高级”→“继续访问”即可。消除警告的方法见下文。

> HTTP `http://localhost` 会自动 301 跳转到 HTTPS。

## 中文语言包（镜像内置）

语言包不依赖运行时联网，而是固化在镜像里，且**不修改官方 ENTRYPOINT**：

1. **构建阶段**：根目录的 [Dockerfile](Dockerfile) 读取镜像内 WordPress 版本，下载 `https://downloads.wordpress.org/translation/core/<版本>/<WP_LANG>.zip` 并解压到 `/usr/src/wordpress/wp-content/languages`（官方 entrypoint 的源目录）。
2. **首次启动**：`./wp-data` 为空时，官方 entrypoint 自动把 `/usr/src/wordpress` 复制进数据卷（`--owner www-data`），语言包随之进入 `wp-content/languages`。
3. **激活**：`WORDPRESS_CONFIG_EXTRA` 写入 `define('WPLANG', 'zh_CN')`（取自 `WP_LANG`）。

> 官方镜像声明了 `VOLUME /var/www/html`，在其下直接 `COPY` 文件会被丢弃，且 bind mount 会遮蔽镜像内容——所以语言包必须放在 `/usr/src/wordpress`（官方 entrypoint 唯一会搬运的目录）。
>
> **已有数据卷不会自动补语言包**（官方只在首次初始化时复制）。若 `./wp-data` 初始化时镜像还没内置语言包，在宿主机手动补一次即可：
>
> ```bash
> curl -fsSL -o /tmp/lang.zip "https://downloads.wordpress.org/translation/core/7.1.5/zh_CN.zip"
> unzip -o /tmp/lang.zip -d wp-data/wp-content/languages
> docker compose exec wordpress chown -R www-data:www-data /var/www/html/wp-content/languages
> ```

> 语言由 `WPLANG` 常量固定，后台「设置 → 常规 → 站点语言」切换不会生效。要换语言：改 `.env` 的 `WP_LANG`（如 `zh_TW`、`ja`）后执行 `docker compose up -d --build`（已有数据卷还需按上方方法手动替换语言文件）。

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
define('WPLANG', 'zh_CN');
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
docker compose up -d --build  # 构建（如有变化）并启动
docker compose build          # 仅构建镜像
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
