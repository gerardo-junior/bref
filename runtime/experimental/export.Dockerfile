FROM bref/runtime/php:latest
# Use the bash shell, instead of /bin/sh
SHELL ["/bin/bash", "-c"]

# We do not support running pear functions in Lambda
RUN rm -rf /opt/bref/lib/php/PEAR
RUN rm -rf /opt/bref/share/doc
RUN rm -rf /opt/bref/share/man
RUN rm -rf /opt/bref/share/gtk-doc
RUN rm -rf /opt/bref/include
RUN rm -rf /opt/bref/tests
RUN rm -rf /opt/bref/doc
RUN rm -rf /opt/bref/docs
RUN rm -rf /opt/bref/man
RUN rm -rf /opt/bref/www
RUN rm -rf /opt/bref/cfg
RUN rm -rf /opt/bref/libexec
RUN rm -rf /opt/bref/var
RUN rm -rf /opt/bref/data

WORKDIR /opt
COPY bootstraps/cli.bootstrap /tmp/cli.bootstrap
RUN export PHP_ZIP_NAME=/export/php-$(php -r '$version = explode(".", phpversion());printf("%d.%d", $version[0], $version[1]);'); \
 mkdir -p /export; \
 rm -rf /export/*; \
 rm -rf /bootstrap; \
 zip -qr ${PHP_ZIP_NAME}.zip . -x "*php-cgi"; \
 cp ${PHP_ZIP_NAME}.zip ${PHP_ZIP_NAME}-cli.zip; \
 zip -d ${PHP_ZIP_NAME}-cli.zip bref/sbin/php-fpm bin/php-fpm; \
 cp /tmp/cli.bootstrap /bootstrap; \
 chmod 755 /bootstrap; \
 zip -u ${PHP_ZIP_NAME}-cli.zip /bootstrap; \
 cp ${PHP_ZIP_NAME}.zip ${PHP_ZIP_NAME}.fpm.zip; \
 zip -d ${PHP_ZIP_NAME}.fpm.zip bref/bin/php /bin/php