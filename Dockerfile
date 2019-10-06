# syntax = docker/dockerfile:1.0-experimental

#
# Stage `composer`: PHP dependency packages
#

FROM takamichi/composer:latest AS composer

ENV APP_ROOT="/var/www/html"

COPY backend/composer.json backend/composer.lock ${APP_ROOT}/
# database dir require for autoload classmap
COPY ./backend/database ${APP_ROOT}/database

WORKDIR ${APP_ROOT}
RUN --mount=type=cache,target=/tmp/cache \
    set -xe; \
    : "Validate composer.json ..."; \
    composer validate --working-dir=${APP_ROOT} --strict --no-check-publish --no-interaction; \
    : "Install dependency packages ..."; \
    composer install \
        --working-dir=${APP_ROOT} \
        --ignore-platform-reqs \
        --no-dev \
        --no-interaction \
        --no-progress \
        --no-scripts \
        --optimize-autoloader \
        --prefer-dist;

COPY backend/app ${APP_ROOT}/app
COPY backend/bootstrap ${APP_ROOT}/bootstrap
COPY backend/config ${APP_ROOT}/config
COPY backend/database ${APP_ROOT}/database
COPY backend/public ${APP_ROOT}/public
COPY backend/resources ${APP_ROOT}/resources
COPY backend/src ${APP_ROOT}/src
COPY backend/storage ${APP_ROOT}/storage
COPY backend/artisan ${APP_ROOT}/

RUN : "Cleanup files and directories ..."; \
    (find \
        "${APP_ROOT}/bootstrap/cache/" \
        "${APP_ROOT}/storage/" \
        "${APP_ROOT}/public/assets" \
        -type f | xargs rm -f); \
    rm -f \
        "${APP_ROOT}/public/storage" \
        "${APP_ROOT}/public/mix-manifest.json";

VOLUME ["/tmp"]


FROM node:11 AS node

ENV APP_ROOT="/var/www/html"

COPY frontend/package.json frontend/yarn.lock ${APP_ROOT}/

WORKDIR ${APP_ROOT}
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn/v1 \
    set -xe; \
    : "Install dependency packages ..."; \
    yarn install --frozen-lockfile --non-interactive;

COPY frontend/webpack.mix.js ${APP_ROOT}/
COPY frontend/** ${APP_ROOT}/

RUN : "Cleanup files and directories ..."; \
    rm -rf ${APP_ROOT}/build; \
    : "Build frontend assets ..."; \
    yarn production;


#
# Stage 1: Accueil docker image
#

FROM php:7.3.10-fpm-alpine3.9
MAINTAINER Takamichi Urata <taka@seraphimis.net>

RUN set -xe; \
    apk add --update --no-cache \
        ca-certificates \
        tzdata

ARG VERSION="dev"
ARG CODE_REVISION="no-rev"

ENV NGINX_VERSION 1.17.4
ENV NJS_VERSION   0.3.5
ENV PKG_RELEASE   1

RUN set -x \
# create nginx user/group first, to be consistent throughout docker variants
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
    && apkArch="$(cat /etc/apk/arch)" \
    && nginxPackages=" \
        nginx=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-xslt=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-geoip=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-image-filter=${NGINX_VERSION}-r${PKG_RELEASE} \
        nginx-module-njs=${NGINX_VERSION}.${NJS_VERSION}-r${PKG_RELEASE} \
    " \
    && case "$apkArch" in \
        x86_64) \
# arches officially built by upstream
            set -x \
            && KEY_SHA512="e7fa8303923d9b95db37a77ad46c68fd4755ff935d0a534d26eba83de193c76166c68bfe7f65471bf8881004ef4aa6df3e34689c305662750c0172fca5d8552a *stdin" \
            && apk add --no-cache --virtual .cert-deps \
                openssl \
            && wget -O /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
            && if [ "$(openssl rsa -pubin -in /tmp/nginx_signing.rsa.pub -text -noout | openssl sha512 -r)" = "$KEY_SHA512" ]; then \
                echo "key verification succeeded!"; \
                mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/; \
            else \
                echo "key verification failed!"; \
                exit 1; \
            fi \
            && printf "%s%s%s\n" \
                "https://nginx.org/packages/mainline/alpine/v" \
                `egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release` \
                "/main" \
            | tee -a /etc/apk/repositories \
            && apk del .cert-deps \
            ;; \
        *) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published packaging sources
            set -x \
            && tempDir="$(mktemp -d)" \
            && chown nobody:nobody $tempDir \
            && apk add --no-cache --virtual .build-deps \
                gcc \
                libc-dev \
                make \
                openssl-dev \
                pcre-dev \
                zlib-dev \
                linux-headers \
                libxslt-dev \
                gd-dev \
                geoip-dev \
                perl-dev \
                libedit-dev \
                mercurial \
                bash \
                alpine-sdk \
                findutils \
            && su nobody -s /bin/sh -c " \
                export HOME=${tempDir} \
                && cd ${tempDir} \
                && hg clone https://hg.nginx.org/pkg-oss \
                && cd pkg-oss \
                && hg up ${NGINX_VERSION}-${PKG_RELEASE} \
                && cd alpine \
                && make all \
                && apk index -o ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz ${tempDir}/packages/alpine/${apkArch}/*.apk \
                && abuild-sign -k ${tempDir}/.abuild/abuild-key.rsa ${tempDir}/packages/alpine/${apkArch}/APKINDEX.tar.gz \
                " \
            && echo "${tempDir}/packages/alpine/" >> /etc/apk/repositories \
            && cp ${tempDir}/.abuild/abuild-key.rsa.pub /etc/apk/keys/ \
            && apk del .build-deps \
            ;; \
    esac \
    && apk add --no-cache $nginxPackages \
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
    && if [ -n "$tempDir" ]; then rm -rf "$tempDir"; fi \
    && if [ -n "/etc/apk/keys/abuild-key.rsa.pub" ]; then rm -f /etc/apk/keys/abuild-key.rsa.pub; fi \
    && if [ -n "/etc/apk/keys/nginx_signing.rsa.pub" ]; then rm -f /etc/apk/keys/nginx_signing.rsa.pub; fi \
# remove the last line with the packages repos in the repositories file
    && sed -i '$ d' /etc/apk/repositories \
# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
# Bring in tzdata so users could set the timezones through the environment
# variables
    && apk add --no-cache tzdata \
# forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

ENV EXT_AMQP_VER="1.9.4" \
    EXT_APCU_VER="5.1.17" \
    EXT_AST_VER="1.0.0" \
    EXT_DS_VER="1.2.6" \
    EXT_GRPC_VER="1.17.0" \
    EXT_IGBINARY_VER="3.0.0" \
    EXT_MEMCACHED_VER="3.1.3" \
    EXT_MONGODB_VER="1.5.3" \
    EXT_OAUTH_VER="2.0.3" \
    EXT_REDIS_VER="4.3.0" \
    EXT_XDEBUG_VER="2.7.2" \
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
        libzip \
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
        libzip-dev \
        pcre-dev \
        rabbitmq-c-dev \
        yaml-dev; \
    \
    apk add -U --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/community/gnu-libiconv=1.15-r2; \
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

COPY --chown=www-data:www-data --from=composer ${APP_ROOT} ${APP_ROOT}
COPY --chown=www-data:www-data --from=node ${APP_ROOT}/build ${APP_ROOT}/public/assets

WORKDIR ${APP_ROOT}
RUN set -xe; \
    : "Fix directory permissions ..."; \
    chmod -R 775 ${APP_ROOT}; \
    : "Set version and code revision files ..."; \
    echo ${VERSION} > ${APP_ROOT}/VERSION; \
    echo ${CODE_REVISION} > ${APP_ROOT}/REVISION;

ENTRYPOINT ["entrypoint"]
CMD ["service"]

EXPOSE 80
