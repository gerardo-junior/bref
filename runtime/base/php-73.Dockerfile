# The container we build here contains everything needed to compile PHP + PHP.
#
# It can be used as a base to compile extra extensions.

# PHP Build
# https://github.com/php/php-src/releases
# Needs:
#   - zlib
#   - libxml2
#   - openssl
#   - readline
#   - sodium

FROM bref/tmp/step-1/build-environment as build-environment

ARG PHP_BUILD_DIR=${BUILD_DIR}/php
ARG PHP_VERSION=7.3.7
ARG PHP_SOURCE_URL=https://secure.php.net/get
ARG PHP_VERSION_SHA256=4230bbc862df712b013369de94b131eddea1e5e946a8c5e286b82d441c313328
RUN set -xe && \
    mkdir -p ${PHP_BUILD_DIR} && \
    curl -L -o php-${PHP_VERSION}.tar.gz ${PHP_SOURCE_URL}/php-${PHP_VERSION}.tar.gz/from/this/mirror && \
    if [ -n "$PHP_VERSION_SHA256" ]; then \
		echo "${PHP_VERSION_SHA256}  php-${PHP_VERSION}.tar.gz" | sha256sum -c - \
	; fi && \
    tar xvf php-${PHP_VERSION}.tar.gz -C ${PHP_BUILD_DIR} --strip-components=1 && \
    rm -f php-${PHP_VERSION}.tar.gz
WORKDIR  ${PHP_BUILD_DIR}/

# Configure the build
# -fstack-protector-strong : Be paranoid about stack overflows
# -fpic : Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# -fpie : Support Address Space Layout Randomization (see -fpic)
# -O3 : Optimize for fastest binaries possible.
# -I : Add the path to the list of directories to be searched for header files during preprocessing.
# --enable-option-checking=fatal: make sure invalid --configure-flags are fatal errors instead of just warnings
# --enable-ftp: because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
# --enable-mbstring: because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
# --enable-maintainer-zts: build PHP as ZTS (Zend Thread Safe) to be able to use pthreads
# --with-zlib and --with-zlib-dir: See https://stackoverflow.com/a/42978649/245552
# --enable-opcache-file: allows to use the `opcache.file_cache` option
#
RUN set -xe \
 && ./buildconf --force \
 && CFLAGS="-fstack-protector-strong -fpic -fpie -O3 -I${INSTALL_DIR}/include -I/usr/include -ffunction-sections -fdata-sections" \
    CPPFLAGS="-fstack-protector-strong -fpic -fpie -O3 -I${INSTALL_DIR}/include -I/usr/include -ffunction-sections -fdata-sections" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib -Wl,-O1 -Wl,--strip-all -Wl,--hash-style=both -pie" \
    ./configure \
        --build=x86_64-pc-linux-gnu \
        --prefix=${INSTALL_DIR} \
        --enable-option-checking=fatal \
        --enable-maintainer-zts \
        --enable-sockets \
        --with-config-file-path=${INSTALL_DIR}/etc/php \
        --with-config-file-scan-dir=${INSTALL_DIR}/etc/php/conf.d:/var/task/php/conf.d \
        --enable-fpm \
        --disable-cgi \
        --enable-cli \
        --disable-phpdbg \
        --disable-phpdbg-webhelper \
        --with-sodium \
        --with-readline \
        --with-openssl \
        --with-zlib=${INSTALL_DIR} \
        --with-zlib-dir=${INSTALL_DIR} \
        --with-curl \
        --enable-exif \
        --enable-ftp \
        --with-gettext \
        --enable-mbstring \
        --with-pdo-mysql=shared,mysqlnd \
        --with-mysqli \
        --enable-pcntl \
        --enable-zip \
        --enable-bcmath \
        --with-pdo-pgsql=shared,${INSTALL_DIR} \
        --enable-intl=shared \
        --enable-opcache-file \
        --enable-soap \
        --with-xsl=${INSTALL_DIR} \
        --with-gd \
        --with-png-dir=${INSTALL_DIR} \
        --with-jpeg-dir=${INSTALL_DIR}
RUN make -j $(nproc)
# Run `make install` and override PEAR's PHAR URL because pear.php.net is down
RUN set -xe; \
 make install PEAR_INSTALLER_URL='https://github.com/pear/pearweb_phars/raw/master/install-pear-nozlib.phar'; \
 { find ${INSTALL_DIR}/bin ${INSTALL_DIR}/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; }; \
 make clean; \
 cp php.ini-production ${INSTALL_DIR}/etc/php/php.ini

# Symlink all our binaries into /opt/bin so that Lambda sees them in the path.
RUN mkdir -p /opt/bin
RUN ln -s /opt/bref/bin/* /opt/bin
RUN ln -s /opt/bref/sbin/* /opt/bin

# Install extensions
# We can install extensions manually or using `pecl`
RUN pecl install mongodb
RUN pecl install redis
RUN pecl install APCu
RUN pecl install imagick

# pthreads
ENV PTHREADS_BUILD_DIR=${BUILD_DIR}/pthreads
# Build from master because there are no pthreads release compatible with PHP 7.3
RUN set -xe; \
    mkdir -p ${PTHREADS_BUILD_DIR}/bin; \
    curl -Ls https://github.com/krakjoe/pthreads/archive/master.tar.gz \
    | tar xzC ${PTHREADS_BUILD_DIR} --strip-components=1
WORKDIR  ${PTHREADS_BUILD_DIR}/
RUN set -xe; \
    phpize \
 && ./configure \
 && make \
 && make install


# Run the next step in the previous environment because the `clean.sh` script needs `find`,
# which isn't installed by default
FROM build-environment as build-environment-cleaned
# Remove extra files to make the layers as slim as possible
COPY clean.sh /tmp/clean.sh
RUN /tmp/clean.sh && rm /tmp/clean.sh


# Now we start back from a clean image.
# We get rid of everything that is unnecessary (build tools, source code, and anything else
# that might have created intermediate layers for docker) by copying online the /opt directory.
FROM amazonlinux:2018.03
ENV PATH="/opt/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/bref/lib64:/opt/bref/lib"

# Copy everything we built above into the same dir on the base AmazonLinux container.
COPY --from=build-environment-cleaned /opt /opt

# Set the workdir to the same directory as in AWS Lambda
WORKDIR /var/task
