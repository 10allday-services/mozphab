FROM php:7.3.11-fpm-alpine

LABEL maintainer "mars@mozilla.com"

# These are unlikely to change from version to version of the container
EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
CMD ["/app/entrypoint.sh", "start"]

# Git commit SHAs for the build artifacts we want to grab.
# From https://github.com/phacility/phabricator/tree/stable
# Promote 2020 Week 6
ENV PHABRICATOR_GIT_SHA ff6f24db2bc016533bca9040954a218c54ca324e
# From https://github.com/phacility/arcanist/tree/stable
# Promote 2020 Week 5
ENV ARCANIST_GIT_SHA 729100955129851a52588cdfd9b425197cf05815
# From https://github.com/phacility/libphutil/tree/stable
# Promote 2020 Week 5
ENV LIBPHUTIL_GIT_SHA 034cf7cc39940b935e83923dbb1bacbcfe645a85
# Should match the phabricator 'repository.default-local-path' setting.
ENV REPOSITORY_LOCAL_PATH /repo
# Explicitly set TMPDIR
ENV TMPDIR /tmp

# Runtime dependencies
RUN apk --no-cache --update add \
    curl \
    freetype \
    g++ \
    git \
    libjpeg-turbo \
    libmcrypt \
    libpng \
    make \
    mariadb-client \
    ncurses \
    procps \
    py-pygments \
    libzip

# Install mercurial from source b/c it's wicked out of date on main
COPY mercurial_requirements.txt requirements.txt
RUN apk add python-dev py-pip && \
    pip install --require-hashes -r requirements.txt

# Build PHP extensions
RUN apk --no-cache add --virtual build-dependencies \
        $PHPIZE_DEPS \
        curl-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libzip-dev \
        mariadb-dev \
    && docker-php-ext-configure gd \
        --with-freetype-dir=/usr/include \
        --with-jpeg-dir=/usr/include \
        --with-png-dir=/usr/include \
    && docker-php-ext-install -j "$(nproc)" \
        curl \
        gd \
        iconv \
        mbstring \
        mysqli \
        pcntl \
    && pecl install apcu-5.1.17 \
    && docker-php-ext-enable apcu \
    && pecl install mcrypt-1.0.2 \
    && docker-php-ext-enable mcrypt \
    && pecl install zip-1.15.4 \
    && docker-php-ext-enable zip \
    && apk del build-dependencies

RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64 && if test -f /usr/local/bin/dumb-init; then chmod 755 /usr/local/bin/dumb-init; fi

# The container does not log errors by default, so turn them on
RUN { \
        echo 'php_admin_flag[log_errors] = on'; \
        echo 'php_flag[display_errors] = off'; \
    } | tee /usr/local/etc/php-fpm.d/zz-log.conf

# Phabricator recommended settings (skipping these will result in setup warnings
# in the application).
RUN { \
        echo 'always_populate_raw_post_data=-1'; \
        echo 'post_max_size="32M"'; \
    } | tee /usr/local/etc/php/conf.d/phabricator.ini

# add a non-privileged user for installing and running the application
RUN addgroup -g 10001 app && adduser -D -u 10001 -G app -h /app -s /bin/sh app

COPY . /app
WORKDIR /app
RUN mkdir tmpfiles

# Install Phabricator code
RUN curl -fsSL https://github.com/phacility/phabricator/archive/${PHABRICATOR_GIT_SHA}.tar.gz -o phabricator.tar.gz \
    && curl -fsSL https://github.com/phacility/arcanist/archive/${ARCANIST_GIT_SHA}.tar.gz -o arcanist.tar.gz \
    && curl -fsSL https://github.com/phacility/libphutil/archive/${LIBPHUTIL_GIT_SHA}.tar.gz -o libphutil.tar.gz \
    && tar xzf phabricator.tar.gz \
    && tar xzf arcanist.tar.gz \
    && tar xzf libphutil.tar.gz \
    && mv phabricator-${PHABRICATOR_GIT_SHA} phabricator \
    && mv arcanist-${ARCANIST_GIT_SHA} arcanist \
    && mv libphutil-${LIBPHUTIL_GIT_SHA} libphutil \
    && rm phabricator.tar.gz arcanist.tar.gz libphutil.tar.gz \
    && ./libphutil/scripts/build_xhpast.php

# Create version.json
RUN chmod +x /app/merge_versions.py && /app/merge_versions.py

RUN chmod +x /app/entrypoint.sh /app/wait-for-mysql.php \
    && mkdir $REPOSITORY_LOCAL_PATH \
    && chown -R app:app /app $REPOSITORY_LOCAL_PATH

USER app
VOLUME ["$REPOSITORY_LOCAL_PATH"]
