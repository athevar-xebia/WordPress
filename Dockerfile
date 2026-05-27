# syntax=docker/dockerfile:1.7
#
# Single-container minimal image for testing this WordPress fork.
# Runs nginx + php-fpm side-by-side on Alpine. ~340 MB total (~135 MB of
# that is the WordPress source itself, which is the floor for this repo).
FROM php:8.3-fpm-alpine

RUN set -eux; \
    apk add --no-cache \
        nginx \
        freetype \
        icu-libs \
        libjpeg-turbo \
        libpng \
        libwebp \
        libzip; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        freetype-dev \
        icu-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" \
        exif \
        gd \
        intl \
        mysqli \
        opcache \
        zip; \
    apk del --no-network .build-deps; \
    rm -rf /tmp/* /var/cache/apk/*; \
    # Send nginx logs to the container's stdout/stderr so `docker logs` works.
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log

COPY config/nginx.conf /etc/nginx/http.d/default.conf
COPY config/php.ini    /usr/local/etc/php/conf.d/wordpress.ini

# Entrypoint: render wp-config.php on first boot, start php-fpm in the
# background, then exec nginx as PID 1. If nginx exits, the container
# exits — same lifecycle semantics as a single-process container.
COPY <<'ENTRYPOINT' /usr/local/bin/wp-entrypoint.sh
#!/bin/sh
set -e

if [ ! -f /var/www/html/wp-config.php ] && [ -f /var/www/html/wp-config-sample.php ]; then
    case "${WORDPRESS_DEBUG:-}" in
        1|true|yes|on) wp_debug=true ;;
        *) wp_debug=false ;;
    esac
    sed \
        -e "s/database_name_here/${WORDPRESS_DB_NAME:-wordpress}/" \
        -e "s/username_here/${WORDPRESS_DB_USER:-wordpress}/" \
        -e "s/password_here/${WORDPRESS_DB_PASSWORD:-wordpress}/" \
        -e "s/localhost/${WORDPRESS_DB_HOST:-db}/" \
        -e "s/define( 'WP_DEBUG', false );/define( 'WP_DEBUG', ${wp_debug} );/" \
        /var/www/html/wp-config-sample.php > /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
fi

php-fpm -D
exec nginx -g 'daemon off;'
ENTRYPOINT
RUN chmod +x /usr/local/bin/wp-entrypoint.sh

WORKDIR /var/www/html
COPY --chown=www-data:www-data . /var/www/html/

EXPOSE 80
ENTRYPOINT ["wp-entrypoint.sh"]
