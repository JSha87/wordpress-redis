FROM wordpress:latest

# Install dependencies including zstd and dev tools
RUN apt-get update && apt-get install -y \
    libzip-dev \
    zlib1g-dev \
    git \
    libzstd-dev \
    wget \
    make \
    autoconf \
    && rm -rf /var/lib/apt/lists/*

# Install igbinary first (before compiling redis)
RUN pecl install igbinary && docker-php-ext-enable igbinary

# Clone and compile Redis with both zstd and igbinary support
RUN git clone https://github.com/phpredis/phpredis.git /tmp/phpredis \
    && cd /tmp/phpredis \
    && phpize \
    && ./configure --enable-redis-zstd --enable-redis-igbinary \
    && make \
    && make install \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/phpredis

# Verify redis extension with all required features
RUN php -m | grep redis \
    && php -m | grep igbinary \
    && php -r "echo 'ZSTD support: ' . (extension_loaded('redis') && method_exists('Redis', 'compress') ? 'Yes' : 'No') . PHP_EOL;" \
    && php -r "echo 'igbinary support: ' . (extension_loaded('redis') && defined('Redis::SERIALIZER_IGBINARY') ? 'Yes' : 'No') . PHP_EOL;"