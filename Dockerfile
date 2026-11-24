# 基于官方镜像，预置中文语言包
ARG WORDPRESS_VERSION=7.1.5
FROM wordpress:${WORDPRESS_VERSION}

# 语言代码：zh_CN / zh_TW / ja / ...
ARG WP_LANG=zh_CN

# 语言包放进 /usr/src/wordpress（官方 entrypoint 的源目录，非 VOLUME，可正常写入）。
# 首次启动且 /var/www/html 为空时，官方 entrypoint 会把整个目录复制进数据卷
# （tar 管道，--owner www-data），语言包随之生效，无需修改官方 ENTRYPOINT。
RUN set -eux; \
    ver="$(php -r 'include "/usr/src/wordpress/wp-includes/version.php"; echo $wp_version;')"; \
    echo "WordPress ${ver} / language ${WP_LANG}"; \
    lang_dir="/usr/src/wordpress/wp-content/languages"; \
    mkdir -p "$lang_dir"; \
    curl -fsSL -o /tmp/lang.zip "https://downloads.wordpress.org/translation/core/${ver}/${WP_LANG}.zip"; \
    php -r '$z = new ZipArchive; $z->open("/tmp/lang.zip"); $z->extractTo("/usr/src/wordpress/wp-content/languages/"); $z->close();'; \
    rm -f /tmp/lang.zip; \
    ls "$lang_dir" | wc -l
