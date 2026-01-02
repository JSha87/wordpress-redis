FROM nextcloud:32.0.3-fpm-alpine

# 1. Install build dependencies for the missing modules
# We use 'apk add' for system libs and 'docker-php-ext-install' for the PHP glue
RUN apk add --no-cache \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    icu-dev \
    autoconf \
    g++ \
    make

# 2. Explicitly install/configure the modules Nextcloud is complaining about
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \
    docker-php-ext-install -j$(nproc) \
    gd \
    zip \
    pdo_mysql \
    intl \
    bcmath

# 3. Install APCu (for memory caching) via PECL
RUN pecl install apcu && \
    docker-php-ext-enable apcu

# 4. Bake the code into the image (Immutable)
RUN cp -at /var/www/html /usr/src/nextcloud/

# 5. Set the restrictive permissions we discussed
RUN mkdir -p /var/www/html/data /var/www/html/config /var/www/html/custom_apps && \
    chown -R 1003:1003 /var/www/html/data \
                       /var/www/html/config \
                       /var/www/html/custom_apps \
                       /usr/local/etc/php/conf.d

USER 1003