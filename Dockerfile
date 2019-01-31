# syntax = docker/dockerfile:1.0-experimental

#
# Step 1: dockerize
#

FROM alpine:latest AS dockerize

RUN set -xe; \
    apk add --update --no-cache \
        ca-certificates \
        openssl

ENV DOCKERIZE_VERSION v0.6.1
RUN set -xe; \
    : "Download \"dockerize\" ..."; \
    wget https://github.com/jwilder/dockerize/releases/download/${DOCKERIZE_VERSION}/dockerize-alpine-linux-amd64-${DOCKERIZE_VERSION}.tar.gz; \
    tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-${DOCKERIZE_VERSION}.tar.gz; \
    chmod +x /usr/local/bin/dockerize; \
    rm dockerize-alpine-linux-amd64-${DOCKERIZE_VERSION}.tar.gz;


#
# Step 2: PHP dependency packages
#

FROM takamichi/composer:latest AS composer

ENV APP_ROOT="/var/www/html"

COPY . /app

RUN --mount=type=cache,target=/tmp/cache \
    set -xe; \
    : "Create APP_ROOT directory ..."; \
    mkdir -p ${APP_ROOT}; \
    : "Validate composer.json ..."; \
    composer validate --strict --no-check-publish --no-interaction; \
    : "Install dependency packages ..."; \
    composer install \
        --ignore-platform-reqs \
        --no-dev \
        --no-interaction \
        --no-progress \
        --no-scripts \
        --optimize-autoloader \
        --prefer-dist; \
    : "Copy application files ..."; \
    cp -r /app/app ${APP_ROOT}/; \
    cp -r /app/bootstrap ${APP_ROOT}/; \
    cp -r /app/config ${APP_ROOT}/; \
    cp -r /app/database ${APP_ROOT}/; \
    cp -r /app/public ${APP_ROOT}/; \
    cp -r /app/resources ${APP_ROOT}/; \
    cp -r /app/src ${APP_ROOT}/; \
    cp -r /app/storage ${APP_ROOT}/; \
    cp -r /app/vendor ${APP_ROOT}/; \
    cp /app/artisan ${APP_ROOT}/; \
    : "Cleanup files and directories ..."; \
    find \
        "${APP_ROOT}/bootstrap/cache/" \
        "${APP_ROOT}/storage/" \
        -type f -exec rm -f {} \; ;

VOLUME ["/tmp"]


#
# Step 3: Accueil docker image
#

FROM php:7.2.14-fpm-alpine3.8
MAINTAINER Takamichi Urata <taka@seraphimis.net>

RUN set -xe; \
    apk add --update --no-cache \
        ca-certificates \
        tzdata

ARG VERSION="dev"
ARG CODE_REVISION="no-rev"

ENV NGINX_VERSION 1.15.8

RUN GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
    && CONFIG="\
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_stub_status_module \
        --with-http_auth_request_module \
        --with-http_xslt_module=dynamic \
        --with-http_image_filter_module=dynamic \
        --with-http_geoip_module=dynamic \
        --with-threads \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module \
        --with-stream_geoip_module=dynamic \
        --with-http_slice_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-compat \
        --with-file-aio \
        --with-http_v2_module \
    " \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && apk add --no-cache --virtual .build-deps \
        gcc \
        libc-dev \
        make \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        linux-headers \
        curl \
        gnupg1 \
        libxslt-dev \
        gd-dev \
        geoip-dev \
    && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
    && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc  -o nginx.tar.gz.asc \
    && export GNUPGHOME="$(mktemp -d)" \
    && found=''; \
    for server in \
        ha.pool.sks-keyservers.net \
        hkp://keyserver.ubuntu.com:80 \
        hkp://p80.pool.sks-keyservers.net:80 \
        pgp.mit.edu \
    ; do \
        echo "Fetching GPG key $GPG_KEYS from $server"; \
        gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
    gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
    && rm -rf "$GNUPGHOME" nginx.tar.gz.asc \
    && mkdir -p /usr/src \
    && tar -zxC /usr/src -f nginx.tar.gz \
    && rm nginx.tar.gz \
    && cd /usr/src/nginx-$NGINX_VERSION \
    && ./configure $CONFIG --with-debug \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && mv objs/nginx objs/nginx-debug \
    && mv objs/ngx_http_xslt_filter_module.so objs/ngx_http_xslt_filter_module-debug.so \
    && mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
    && mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
    && mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
    && ./configure $CONFIG \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html/ \
    && mkdir /etc/nginx/conf.d/ \
    && mkdir -p /usr/share/nginx/html/ \
    && install -m644 html/index.html /usr/share/nginx/html/ \
    && install -m644 html/50x.html /usr/share/nginx/html/ \
    && install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
    && install -m755 objs/ngx_http_xslt_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_xslt_filter_module-debug.so \
    && install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
    && install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
    && install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
    && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
    && strip /usr/sbin/nginx* \
    && strip /usr/lib/nginx/modules/*.so \
    && rm -rf /usr/src/nginx-$NGINX_VERSION \
    \
    # Bring in gettext so we can get `envsubst`, then throw
    # the rest away. To do this, we need to install `gettext`
    # then move `envsubst` out of the way so `gettext` can
    # be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && apk add --no-cache --virtual .nginx-rundeps $runDeps \
    && apk del .build-deps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    \
    # Bring in tzdata so users could set the timezones through the environment
    # variables
    && apk add --no-cache tzdata \
    \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

ENV EXT_AMQP_VER="1.9.3" \
    EXT_APCU_VER="5.1.12" \
    EXT_AST_VER="1.0.0" \
    EXT_DS_VER="1.2.6" \
    EXT_GRPC_VER="1.16.0" \
    EXT_IGBINARY_VER="2.0.8" \
    EXT_MEMCACHED_VER="3.0.4" \
    EXT_MONGODB_VER="1.5.3" \
    EXT_OAUTH_VER="2.0.2" \
    EXT_REDIS_VER="4.2.0" \
    EXT_TIDEWAYS_XHPROF_VER="4.1.6" \
    EXT_XDEBUG_VER="2.6.1" \
    EXT_YAML_VER="2.0.4" \
    PHP_ERROR_REPORTING="E_ALL & ~E_DEPRECATED & ~E_STRICT" \
    PHP_MAX_INPUT_TIME="60" \
    PHP_OUTPUT_BUFFERING="4096" \
    PHP_MAX_EXECUTION_TIME="60" \
    PHP_MAX_INPUT_TIME="60" \
    PHP_MAX_INPUT_VARS="1000" \
    PHP_MEMORY_LIMIT="256M" \
    PHP_DISPLAY_ERRORS="Off" \
    PHP_DISPLAY_STARTUP_ERRORS="Off" \
    PHP_POST_MAX_SIZE="32M" \
    PHP_UPLOAD_MAX_FILESIZE="32M" \
    PHP_MAX_FILE_UPLOADS="20" \
    PHP_ASSERTIONS="-1" \
    PHP_ASSERT_EXCEPTION="0" \
    PHP_OPCACHE_ENABLE="1" \
    PHP_OPCACHE_ENABLE_CLI="0" \
    PHP_OPCACHE_MEMORY_CONSUMPTION="128" \
    PHP_OPCACHE_INTERNED_STRINGS_BUFFER="8" \
    PHP_OPCACHE_MAX_ACCELERATED_FILES="10000" \
    PHP_OPCACHE_MAX_WASTED_PERCENTAGE="5" \
    PHP_OPCACHE_USE_CWD="1" \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS="1" \
    PHP_OPCACHE_REVALIDATE_FREQ="2" \
    PHP_OPCACHE_REVALIDATE_PATH="0" \
    PHP_OPCACHE_SAVE_COMMENTS="1" \
    PHP_OPCACHE_ENABLE_FILE_OVERRIDE="0" \
    PHP_OPCACHE_OPTIMIZATION_LEVEL="0x7FFFBFFF" \
    PHP_OPCACHE_MAX_FILE_SIZE="0" \
    PHP_OPCACHE_CONSISTENCY_CHECKS="0" \
    PHP_OPCACHE_FORCE_RESTART_TIMEOUT="180" \
    PHP_OPCACHE_LOG_VERBOSITY_LEVEL="1" \
    PHP_OPCACHE_PROTECT_MEMORY="0" \
    PHP_OPCACHE_FILE_CACHE_ONLY="0" \
    PHP_OPCACHE_FILE_CACHE_CONSISTENCY_CHECKS="1" \
    PHP_OPCACHE_FILE_CACHE_FALLBACK="1" \
    PHP_OPCACHE_HUGE_CODE_PAGES="1" \
    PHP_OPCACHE_VALIDATE_PERMISSION="0" \
    PHP_OPCACHE_VALIDATE_ROOT="0" \
    PHP_OPCACHE_OPT_DEBUG_LEVEL="0"

ENV ACCUEIL_VERSION=${VERSION} \
    ACCUEIL_REVISION=${CODE_REVISION} \
    APP_ENV="local" \
    APP_KEY="" \
    APP_DEBUG="false" \
    APP_DOMAIN="" \
    APP_SCHEME="https" \
    APP_LOCALE="ja" \
    APP_TIMEZONE="Asia/Tokyo" \
    APP_ROOT="/var/www/html" \
    DB_HOST="" \
    DB_PORT="3306" \
    DB_DATABASE="" \
    DB_USERNAME="" \
    DB_PASSWORD=""

RUN set -xe; \
    apk add --update --no-cache -t .php-rundeps \
        c-client \
        fcgi \
        findutils \
        freetype \
        gmp \
        icu-libs \
        jpegoptim \
        libbz2 \
        libjpeg-turbo \
        libjpeg-turbo-utils \
        libltdl \
        libmemcached-libs \
        libpng \
        libxslt \
        make \
        mariadb-client \
        openssh-client \
        patch \
        rabbitmq-c \
        yaml; \
    apk add --update --no-cache -t .build-deps \
        autoconf \
        cmake \
        build-base \
        bzip2-dev \
        freetype-dev \
        gmp-dev \
        icu-dev \
        jpeg-dev \
        libjpeg-turbo-dev \
        libmemcached-dev \
        libpng-dev \
        libtool \
        libxslt-dev \
        pcre-dev \
        rabbitmq-c-dev \
        yaml-dev; \
    \
    apk add -U -X http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted gnu-libiconv; \
    \
    docker-php-source extract; \
    \
    NPROC=$(getconf _NPROCESSORS_ONLN); \
    docker-php-ext-install "-j${NPROC}" \
        bcmath \
        bz2 \
        gmp \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        soap \
        sockets \
        xmlrpc \
        xsl \
        zip; \
    \
    docker-php-ext-configure gd \
        --with-gd \
        --with-freetype-dir=/usr/include/ \
        --with-png-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/; \
    docker-php-ext-install "-j${NPROC}" gd; \
    \
    : "PECL extensions ..."; \
    pecl config-set php_ini "${PHP_INI_DIR}/php.ini"; \
    pecl channel-update pecl.php.net; \
    pecl install \
        "amqp-${EXT_AMQP_VER}" \
        "apcu-${EXT_APCU_VER}" \
        "ast-${EXT_AST_VER}" \
        "ds-${EXT_DS_VER}" \
        "grpc-${EXT_GRPC_VER}" \
        "igbinary-${EXT_IGBINARY_VER}" \
        inotify \
        "memcached-${EXT_MEMCACHED_VER}" \
        "mongodb-${EXT_MONGODB_VER}" \
        "oauth-${EXT_OAUTH_VER}" \
        "redis-${EXT_REDIS_VER}" \
        "xdebug-${EXT_XDEBUG_VER}" \
        "yaml-${EXT_YAML_VER}"; \
    \
    docker-php-ext-enable \
        amqp \
        apcu \
        ast \
        ds \
        igbinary \
        inotify \
        grpc \
        memcached \
        mongodb \
        oauth \
        redis \
        yaml; \
    \
    : "Blackfire extension ..."; \
    mkdir -p /tmp/blackfire; \
    version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;"); \
    blackfire_url="https://blackfire.io/api/v1/releases/probe/php/alpine/amd64/${version}"; \
    wget -qO- "${blackfire_url}" | tar xz --no-same-owner -C /tmp/blackfire; \
    mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get('extension_dir');")/blackfire.so; \
    \
    : "Cleanup ..."; \
    docker-php-source delete; \
    apk del --purge .build-deps; \
    pecl clear-cache; \
    \
    rm -rf \
        /usr/src/php/ext/ast \
        /usr/src/php/ext/uploadprogress \
        /usr/include/php \
        /usr/lib/php/build \
        /tmp/* \
        /var/cache/apk/*;

COPY ./environment/entrypoint /usr/local/bin/
COPY ./environment/php.ini ${PHP_INI_DIR}/php.ini
COPY ./environment/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./environment/nginx.conf /etc/nginx/nginx.conf

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/dockerize
COPY --from=composer ${APP_ROOT} ${APP_ROOT}

WORKDIR ${APP_ROOT}
RUN set -xe; \
    : "Fix directory permissions ..."; \
    chmod -R 775 ${APP_ROOT}; \
    chown -R www-data:www-data ${APP_ROOT}; \
    : "Set version and code revision files ..."; \
    echo ${VERSION} > ${APP_ROOT}/VERSION; \
    echo ${CODE_REVISION} > ${APP_ROOT}/REVISION;

ENTRYPOINT ["entrypoint"]
CMD ["service"]

EXPOSE 80
