# 基于官方镜像，预置中文语言包
ARG WORDPRESS_VERSION=7.1.5
FROM wordpress:${WORDPRESS_VERSION}

# 语言代码：zh_CN / zh_TW / ja / ...
ARG WP_LANG=zh_CN

# 语言包放进 /usr/src/wordpress（官方 entrypoint 的源目录，非 VOLUME，可正常写入）。
# 首次启动且 /var/www/html 为空时，官方 entrypoint 会把整个目录复制进数据卷
# （tar 管道，--owner www-data），语言包随之生效，无需修改官方 ENTRYPOINT。
# 站点语言为英文（en_US 为源语言，官方无语言包，会 404）时预置 zh_CN 包：
# 站点仍是英文，但后台可随时切换成中文，无需重建镜像。
RUN set -eux; \
    ver="$(php -r 'include "/usr/src/wordpress/wp-includes/version.php"; echo $wp_version;')"; \
    pack="${WP_LANG}"; \
    case "$pack" in en|en_US|en_US.*) pack="zh_CN" ;; esac; \
    echo "WordPress ${ver} / site language ${WP_LANG} / pack ${pack}"; \
    lang_dir="/usr/src/wordpress/wp-content/languages"; \
    mkdir -p "$lang_dir"; \
    curl -fsSL -o /tmp/lang.zip "https://downloads.wordpress.org/translation/core/${ver}/${pack}.zip"; \
    php -r '$z = new ZipArchive; $z->open("/tmp/lang.zip"); $z->extractTo("/usr/src/wordpress/wp-content/languages/"); $z->close();'; \
    rm -f /tmp/lang.zip; \
    ls "$lang_dir" | wc -l
