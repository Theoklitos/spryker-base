#!/bin/sh

#
# This script installs the PHP extensions and is able to install PECL extensions as well
#

#get amount of available prozessors * 2 for faster compiling of sources
COMPILE_JOBS=$((`getconf _NPROCESSORS_ONLN`*2))

# a list of common PHP extensions required to run a spryker shop... so you don't have to
# specify them within every shop implementation.
COMMON_PHP_EXTENSIONS="bcmath gd gmp intl mcrypt redis"

#
#  Install PHP extensions
#

# helper to deduplicate common code
# installs special php extension dependencies before "install" is called
# removes those dependencies after "install" finishes
# arg1: extension name; arg2: list of dependencies
install_simple_extension() {
  EXTENSION=$1
  DEPS="$2"
  
  $apk_add --virtual .phpmodule-deps $DEPS
  docker-php-ext-install -j$COMPILE_JOBS $EXTENSION
  apk del .phpmodule-deps
}

install_imagick() {
  $apk_add --virtual .phpmodule-deps imagemagick-dev libtool
  $apk_add imagemagick

  pecl install imagick-3.4.3
  docker-php-ext-enable imagick

  apk del .phpmodule-deps
}

install_gd() {
  $apk_add --virtual .phpmodule-deps freetype-dev \
        libjpeg-turbo-dev \
        libmcrypt-dev \
        libpng-dev
  
  docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/
  docker-php-ext-install -j$COMPILE_JOBS gd
  apk del .phpmodule-deps
  
  $apk_add libpng libjpeg-turbo freetype
}

install_xcache() {
  # FIXEM: replace by opcache - no support for PHP 7.x!
  curl -fsSL 'https://xcache.lighttpd.net/pub/Releases/3.2.0/xcache-3.2.0.tar.gz' -o xcache.tar.gz \
    && mkdir -p /tmp/xcache \
    && tar -xf xcache.tar.gz -C /tmp/xcache --strip-components=1 \
    && rm xcache.tar.gz \
    && docker-php-ext-configure /tmp/xcache --enable-xcache \
    && docker-php-ext-install -j$COMPILE_JOBS /tmp/xcache \
    && rm -r /tmp/xcache
}

install_redis() {
  $apk_add --virtual .phpmodule-deps redis
  
  pecl install redis
  docker-php-ext-enable redis
  apk del .phpmodule-deps
}

install_bz2() {
  install_simple_extension $ext "bzip-dev"
  $apk_add bzip2
}

install_curl() {
  install_simple_extension $ext "curl-dev"
  $apk_add libcurl
}

install_mcrypt() {
  install_simple_extension $ext "libmcrypt-dev"
  $apk_add libmcrypt
}

install_gmp() {
  install_simple_extension $ext "gmp-dev"
  $apk_add gmp
}

install_intl() {
  install_simple_extension $ext "icu-dev libintl"
  $apk_add libintl icu-libs
}

install_pgsql() {
  install_simple_extension $ext "postgresql-dev"
  $apk_add postgresql-dev
}

install_pdo_pgsql() {
  install_simple_extension $ext "postgresql-dev"
  $apk_add postgresql-dev
}

install_readline() {
  install_simple_extension $ext "readline-dev libedit-dev"
  $apk_add readline libedit
}

install_dom() {
  install_simple_extension $ext "libxml2-dev"
  $apk_add libxml2
}

install_xml() {
  install_simple_extension $ext "libxml2-dev"
  $apk_add libxml2
}

install_zip() {
  install_simple_extension $ext "zlib-dev"
}

php_install_extensions() {
  docker-php-source extract
  $apk_add re2c
  
  for ext in $COMMON_PHP_EXTENSIONS $PHP_EXTENSIONS; do
    infoText "installing PHP extension $ext"
    if type install_$ext; then
      install_$ext
    else
      # try to install unknown extensions as it is possible, that they are part of the core
      # TODO: check, if the ext is part of the core
      docker-php-ext-install -j$COMPILE_JOBS $ext
    fi
  done
  
  apk del re2c
  docker-php-source delete
}


php_install_extensions


#
#   Composer
#

infoText "download and verify download of PHP composer"
curl -sS -o /tmp/composer-setup.php https://getcomposer.org/installer
curl -sS -o /tmp/composer-setup.sig https://composer.github.io/installer.sig
php -r "if (hash('SHA384', file_get_contents('/tmp/composer-setup.php')) !== trim(file_get_contents('/tmp/composer-setup.sig'))) { unlink('/tmp/composer-setup.php'); echo 'Invalid installer' . PHP_EOL; exit(1); }"


infoText "install PHP composer to /usr/bin/"
php /tmp/composer-setup.php --install-dir=/usr/bin/


# make the installation process of `composer install` faster by parallel downloads
composer.phar global require hirak/prestissimo


#
#  Clean up
#

infoText "clean up PHP and composer installation"
rm -rf /tmp/composer-setup*

# remove php-fpm configs as they are adding a "www" pool, which does not exist
rm /usr/local/etc/php-fpm.d/*