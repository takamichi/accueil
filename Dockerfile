FROM composer:1.6.5 AS composer

RUN set -xe; \
    : "Install Composer plugin \"prestissimo\" ..."; \
    composer global require hirak/prestissimo

COPY . /app

RUN set -xe; \
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
    : "Cleanup files and directories ..."; \
    find \
        "bootstrap/cache/" \
        "storage/" \
        -type f -exec rm -f {} \; ; \
    rm -rf \
        ".idea/" \
        "tests/" \
        ".dockerignore" \
        ".gitattributes" \
        ".gitignore" \
        ".composer.json" \
        ".composer.lock" \
        "docker-compose.yml" \
        "docker-compose.yml.example" \
        "Dockerfile" \
        "package.json" \
        "phpunit.xml" \
        "README.md" \
        "server.php" \
        "webpack.mix.js"


FROM php:7.2.6-fpm-alpine3.7
MAINTAINER Takamichi Urata <taka@seraphimis.net>

RUN set -xe; \
    apk add --update --no-cache \
        ca-certificates \
        tzdata

ARG VERSION="dev"
ARG CODE_REVISION="no-rev"

ENV EXT_AMQP_VER="1.9.3" \
    EXT_APCU_VER="5.1.11" \
    EXT_AST_VER="0.1.6" \
    EXT_DS_VER="1.2.4" \
    EXT_GEOIP_VER="1.1.1" \
    EXT_GRPC_VER="1.10.0" \
    EXT_IGBINARY_VER="2.0.5" \
    EXT_IMAGICK_VER="3.4.3" \
    EXT_MEMCACHED_VER="3.0.4" \
    EXT_MONGODB_VER="1.4.0" \
    EXT_OAUTH_VER="2.0.2" \
    EXT_REDIS_VER="3.1.6" \
    EXT_TIDEWAYS_XHPROF_VER="4.1.6" \
    EXT_XDEBUG_VER="2.6.0" \
    EXT_YAML_VER="2.0.2" \
    PHP_ERROR_REPORTING="E_ALL & ~E_DEPRECATED & ~E_STRICT" \
    PHP_MAX_INPUT_TIME="60" \
    PHP_OUTPUT_BUFFERING="4096" \
    PHP_TRACK_ERRORS="Off" \
    PHP_VARIABLES_ORDER="GPCS" \
    PHP_MAX_EXECUTION_TIME="60" \
    PHP_MAX_INPUT_TIME="60" \
    PHP_MAX_INPUT_VARS="1000" \
    PHP_MEMORY_LIMIT="256M" \
    PHP_DISPLAY_ERRORS="Off" \
    PHP_DISPLAY_STARTUP_ERRORS="Off" \
    PHP_POST_MAX_SIZE="32M" \
    PHP_UPLOAD_MAX_FILESIZE="32M" \
    PHP_MAX_FILE_UPLOADS="20" \
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

ENV APP_ENV="local" \
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
        geoip \
        gmp \
        icu-libs \
        imagemagick \
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
        postgresql-client \
        rabbitmq-c \
        yaml; \
    apk add --update --no-cache -t .build-deps \
        autoconf \
        cmake \
        build-base \
        bzip2-dev \
        freetype-dev \
        geoip-dev \
        gmp-dev \
        icu-dev \
        imagemagick-dev \
        jpeg-dev \
        libjpeg-turbo-dev \
        libmemcached-dev \
        libpng-dev \
        libtool \
        libxslt-dev \
        pcre-dev \
        postgresql-dev \
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
        calendar \
        exif \
        gmp \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
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
    pecl install \
        "amqp-${EXT_AMQP_VER}" \
        "apcu-${EXT_APCU_VER}" \
        "ast-${EXT_AST_VER}" \
        "ds-${EXT_DS_VER}" \
        "geoip-${EXT_GEOIP_VER}" \
        "grpc-${EXT_GRPC_VER}" \
        "igbinary-${EXT_IGBINARY_VER}" \
        "imagick-${EXT_IMAGICK_VER}" \
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
        imagick \
        geoip \
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

COPY ./environment/php.ini ${PHP_INI_DIR}/php.ini
COPY ./environment/php-fpm.conf /usr/local/etc/php-fpm.conf

COPY --from=composer /app ${APP_ROOT}
WORKDIR ${APP_ROOT}

RUN set -xe; \
    : "Fix directory permissions ..."; \
    chmod -R 775 ${APP_ROOT}; \
    chown -R www-data:www-data ${APP_ROOT}; \
    : "Set version and code revision files ..."; \
    echo ${VERSION} > ${APP_ROOT}/VERSION; \
    echo ${CODE_REVISION} > ${APP_ROOT}/REVISION;
