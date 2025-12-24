FROM wordpress:php8.3-apache

RUN apt-get update && apt-get install -y \
    libzip-dev \
    zlib1g-dev \
    libzstd-dev \
    git \
    autoconf \
    make \
    && rm -rf /var/lib/apt/lists/*

RUN pecl install igbinary \
    && docker-php-ext-enable igbinary

RUN git clone --depth=1 https://github.com/phpredis/phpredis.git /tmp/phpredis \
    && cd /tmp/phpredis \
    && phpize \
    && ./configure --enable-redis-zstd --enable-redis-igbinary \
    && make -j$(nproc) \
    && make install \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/phpredis
