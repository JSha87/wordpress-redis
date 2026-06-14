# Use official Wordpress image with PHP 8.3 and Apache as base
FROM wordpress:php8.3-apache AS build

# Install dependencies including zstd for Redis compression
RUN apt-get update && apt-get install -y \
    libzip-dev \
    zlib1g-dev \
    libzstd-dev \
    libzstd1 \
    zstd \
    git \
    autoconf \
    make \
    && rm -rf /var/lib/apt/lists/*

# Install PECL extensions
RUN pecl install igbinary zstd \
    && docker-php-ext-enable igbinary zstd

# Build phpredis with igbinary and zstd support
RUN git clone --depth=1 https://github.com/phpredis/phpredis.git /tmp/phpredis \
    && cd /tmp/phpredis \
    && phpize \
    && ./configure --enable-redis-zstd --enable-redis-igbinary \
    && make -j$(nproc) \
    && make install \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/phpredis

# Final stage
FROM wordpress:php8.3-apache

# Copy build artifacts from previous stage
COPY --from=build /usr/local/etc/php /usr/local/etc/php
COPY --from=build /usr/local/lib/php /usr/local/lib/php
COPY --from=build /usr/local/bin/phpredis.so /usr/local/lib/php/extensions/no-debug-non-zts-20230219/

# Set proper ownership for files used at build time
RUN chown -R 1000:1000 /var/www/html

# Create a non-root user and switch to it
RUN useradd --home-dir=/nonexistent --shell=/bin/sh www-data && \
    addgroup www-data www-data && \
    chown -R www-data:www-data /var/www/html

USER www-data

# Copy WordPress core from /usr/src/wordpress to /var/www/html at BUILD time
RUN cp -rp /usr/src/wordpress/. /var/www/html/

# Add a health check mechanism
HEALTHCHECK CMD curl --fail http://localhost || exit 1

# Override the entrypoint to skip file copying logic and go straight to Apache
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["apache2-foreground"]