FROM wordpress:php8.3-apache

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

# Install igbinary for better Redis serialization
RUN pecl install igbinary \
    && docker-php-ext-enable igbinary

# Install zstd PHP extension for compression support
RUN pecl install zstd \
    && docker-php-ext-enable zstd

# Install phpredis with igbinary and zstd support
RUN git clone --depth=1 https://github.com/phpredis/phpredis.git /tmp/phpredis \
    && cd /tmp/phpredis \
    && phpize \
    && ./configure --enable-redis-zstd --enable-redis-igbinary \
    && make -j$(nproc) \
    && make install \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/phpredis

# Copy WordPress core from /usr/src/wordpress to /var/www/html at BUILD time
RUN cp -rp /usr/src/wordpress/. /var/www/html/

# Set proper ownership (www-data is uid 33 in the base image, but we'll run as 1000)
RUN chown -R 1000:1000 /var/www/html