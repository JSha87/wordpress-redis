# syntax=docker/dockerfile:1
#
# WordPress + Redis (igbinary/zstd) — immutable core image
# ==========================================================================
# Design:
#   - Core (wp-admin, wp-includes, top-level *.php) is owned by root and
#     read-only to the runtime user. Any non-root UID can read/execute it
#     but cannot write, rename, or delete it.
#   - The runtime user is configurable via build args (default 1300) so
#     this matches whatever UID your orchestrator's securityContext
#     enforces (Kubernetes runAsUser, OpenShift restricted SCC, etc).
#   - wp-content is left writable by that same UID so plugins/themes can
#     be installed/updated normally, whether it's baked into the image
#     or overlaid by a mounted volume/PVC at runtime.
# ==========================================================================

ARG WP_UID=1300
ARG WP_GID=1300

# Defaults to the floating tag for convenience when building locally.
# CI pins this to an exact digest (wordpress@sha256:...) on every build, so
# each pushed image tag is fully reproducible and traceable to a specific
# upstream release — see the "Build & Push" workflow.
ARG BASE_IMAGE=wordpress:php8.3-apache

# ============================================================================
# STAGE 1: build PHP extensions (discarded after — no build tools ship in
# the final image, keeping it smaller and reducing attack surface)
# ============================================================================
FROM ${BASE_IMAGE} AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    libzip-dev \
    zlib1g-dev \
    libzstd-dev \
    libzstd1 \
    zstd \
    git \
    autoconf \
    make \
    && rm -rf /var/lib/apt/lists/*

# igbinary: compact binary serialization format
# zstd: compression support for cached values
RUN pecl install igbinary zstd \
    && docker-php-ext-enable igbinary zstd

# phpredis built from source (not PECL) — needed for the
# --enable-redis-zstd / --enable-redis-igbinary configure flags, which
# enable compressed + binary-serialized values when talking to Redis.
RUN git clone --depth=1 https://github.com/phpredis/phpredis.git /tmp/phpredis \
    && cd /tmp/phpredis \
    && phpize \
    && ./configure --enable-redis-zstd --enable-redis-igbinary \
    && make -j"$(nproc)" \
    && make install \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/phpredis


# ============================================================================
# STAGE 2: final runtime image
# ============================================================================
FROM ${BASE_IMAGE}

# Re-declare ARGs after FROM — each stage gets its own ARG scope in Docker.
ARG WP_UID
ARG WP_GID

LABEL org.opencontainers.image.description="WordPress (PHP 8.3, Apache) with Redis (igbinary/zstd) support and an immutable, read-only core filesystem" \
      org.opencontainers.image.source="https://github.com/phpredis/phpredis"

# Pull only the compiled extensions + their config out of the build stage.
COPY --from=build /usr/local/etc/php /usr/local/etc/php
COPY --from=build /usr/local/lib/php /usr/local/lib/php

# Runtime user. UID/GID are build args so any deployer can override them
# to match their own orchestrator's required UID, e.g.:
#   docker build --build-arg WP_UID=1000 --build-arg WP_GID=1000 .
# --home-dir=/nonexistent, --shell=/sbin/nologin: service account only,
# never an interactive login shell.
RUN groupadd -g "${WP_GID}" wpuser \
    && useradd -u "${WP_UID}" -g "${WP_GID}" --home-dir=/nonexistent --shell=/sbin/nologin wpuser

# Lay down WordPress core into the webroot at build time.
RUN cp -rp /usr/src/wordpress/. /var/www/html/

# --- Immutable core ---
# root:root ownership, 755 on dirs / 644 on files. The runtime user can
# read and execute (needed for PHP to include these files) but cannot
# write, rename, or delete them — this is what actually makes core
# immutable, independent of which UID the container runs as.
#
# --- wp-content stays writable by the runtime user ---
# In-image ownership here is a sane default for anyone running this image
# standalone (no external volume mounted). If wp-content is overlaid by a
# volume/PVC at runtime (common in Kubernetes), that mount's own ownership
# takes over and these in-image permissions become irrelevant — set the
# volume's ownership to match WP_UID/WP_GID on the storage side in that case.
RUN chown -R root:root /var/www/html \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \; \
    && chown -R "${WP_UID}:${WP_GID}" /var/www/html/wp-content \
    && find /var/www/html/wp-content -type d -exec chmod 775 {} \; \
    && find /var/www/html/wp-content -type f -exec chmod 664 {} \;

# Run as the configured non-root UID for the rest of the build and at
# container start — matches whatever the orchestrator's securityContext
# (runAsUser) enforces, so local `docker run` behavior matches production.
USER ${WP_UID}

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl --fail http://localhost || exit 1

ENTRYPOINT ["docker-php-entrypoint"]
CMD ["apache2-foreground"]
