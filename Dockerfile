FROM ubuntu:22.04

LABEL maintainer="Taylor Otwell"


ARG WWWGROUP=1000
ARG NODE_VERSION=20
ARG MYSQL_CLIENT="mysql-client"

WORKDIR /var/www/html

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV SUPERVISOR_PHP_COMMAND="/usr/bin/php -d variables_order=EGPCS /var/www/html/artisan serve --host=0.0.0.0 --port=80"
ENV SUPERVISOR_PHP_USER="sail"
ENV PLAYWRIGHT_BROWSERS_PATH=0

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ADD sources.list /etc/apt/

# 基础系统工具 + PHP 8.1 + Composer + Node.js (仅 npm)
RUN apt-get update && apt-get upgrade -y \
    && mkdir -p /etc/apt/keyrings \
    && apt-get install -y gnupg gosu curl ca-certificates zip unzip git supervisor sqlite3 libcap2-bin libpng-dev python3 dnsutils nano \
    # 安装 Ondřej PHP PPA 源
    && curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xb8dc7e53946656efbce4c1dd71daeaab4ad4cab6' | gpg --dearmor | tee /etc/apt/keyrings/ppa_ondrej_php.gpg > /dev/null \
    && echo "deb [signed-by=/etc/apt/keyrings/ppa_ondrej_php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main" > /etc/apt/sources.list.d/ppa_ondrej_php.list \
    && apt-get update \
    && apt-get install -y \
        php8.1-cli \
        php8.1-dev \
        php8.1-fpm \
        php8.1-curl \
        php8.1-mysql \
        php8.1-mbstring \
        php8.1-xml \
        php8.1-zip \
        php8.1-bcmath \
        php8.1-intl \
    # 安装 Composer
    && php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php --install-dir=/usr/bin --filename=composer \
    && php -r "unlink('composer-setup.php');" \
    # 安装 Node.js + npm（仅 npm，移除了 pnpm/bun）
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && npm install -g npm \
    && npm cache clean --force \
    # 安装 MySQL 客户端（如果项目用 MySQL）
    && apt-get install -y $MYSQL_CLIENT \
    # 清理
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN setcap "cap_net_bind_service=+ep" /usr/bin/php8.1

# 确保 /usr/bin/php 指向 php8.1
RUN update-alternatives --set php /usr/bin/php8.1

RUN groupadd --force -g $WWWGROUP sail \
    && useradd -ms /bin/bash --no-user-group -g $WWWGROUP -u 1337 sail
RUN git config --global --add safe.directory /var/www/html

COPY start-container /usr/local/bin/start-container
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY php.ini /etc/php/8.1/cli/conf.d/99-sail.ini
RUN chmod +x /usr/local/bin/start-container

# ✅ 复制项目代码
COPY . /var/www/html

# ✅ 使用 Composer 国内镜像加速（可选）
ENV COMPOSER_MIRROR=https://mirrors.aliyun.com/composer/

# ✅ 安装生产依赖（生产环境无需 --dev）
RUN composer install --no-dev --optimize-autoloader --no-interaction --working-dir=/var/www/html

# ✅ 修正文件所有者为 sail
RUN chown -R sail:sail /var/www/html

EXPOSE 80/tcp

ENTRYPOINT ["start-container"]
