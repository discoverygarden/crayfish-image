FROM debian:12.8-slim

ARG CRAYFISH_COMPOSER_SPEC=4.x-dev
ARG SYN_COMPOSER_SPEC="dev-feature/syn-config as 1.x-dev"

ARG TARGETARCH
ARG TARGETVARIANT
ARG PHP_INI_DIR=/etc/php/8.2

ENV COMPOSER_HOME=/home/composer
ARG COMPOSER_UID=2000
ARG WWW_DATA_UID=33
ARG WWW_DATA_GID=33

EXPOSE 80

RUN \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=debian-apt-lists-$TARGETARCH$TARGETVARIANT \
  --mount=type=cache,target=/var/cache/apt/archives,sharing=locked,id=debian-apt-archives-$TARGETARCH$TARGETVARIANT \
  <<'EOS'
set -e
apt-get -qqy update
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confnew" --no-install-recommends --no-install-suggests \
  ca-certificates curl git openssl sudo unzip \
  ffmpeg imagemagick tesseract-ocr \
  apache2 apache2-utils php php-common php-dev libapache2-mod-php \
  php-ctype php-iconv php-simplexml php-curl \
  poppler-utils ghostscript
EOS

# composer install
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

COPY --link imagemagick_policy.xml /etc/ImageMagick-6/policy.xml

#--------------------------------------------------------------
# setup PHP
WORKDIR $PHP_INI_DIR
COPY --link dgi_99-config.ini dgi/99-config.ini
RUN ln -s $PHP_INI_DIR/dgi/99-config.ini apache2/conf.d/99-config.ini \
  && ln -s $PHP_INI_DIR/dgi/99-config.ini cli/conf.d/99-config.ini
WORKDIR /

# setup apache2
#RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf \
RUN echo 'ErrorLog /dev/stderr' >> /etc/apache2/apache2.conf \
  && echo 'TransferLog /dev/stdout' >> /etc/apache2/apache2.conf \
  && echo 'CustomLog /dev/stdout combined' >> /etc/apache2/apache2.conf \
  && chown -R $WWW_DATA_UID /var/log/apache2

# disable and enable sites
COPY --link 25-80-crayfish.conf /etc/apache2/sites-available/
RUN a2dissite default-ssl.conf \
  && a2ensite 25-80-crayfish.conf \
  && rm /etc/apache2/sites-enabled/000-default.conf

# enable apache2 modules and sites
RUN a2enmod rewrite \
  && a2enmod ssl \
  && a2enmod proxy_http \
  && a2enmod headers


RUN useradd composer -g $WWW_DATA_GID -m --uid $COMPOSER_UID -d $COMPOSER_HOME

#--------------------------------------------------------------
# setup crayfish

USER composer

WORKDIR /opt/www

RUN --mount=type=cache,target=/home/composer/cache,uid=$COMPOSER_UID \
  composer create-project --no-dev --no-interaction -- "islandora/crayfish:${CRAYFISH_COMPOSER_SPEC}" crayfish

WORKDIR crayfish

COPY --link --chown=$COMPOSER_UID:$WWW_DATA_GID crayfish/Homarus/ crayfish/common/ Homarus/config/
COPY --link --chown=$COMPOSER_UID:$WWW_DATA_GID crayfish/Hypercube/ crayfish/common/ Hypercube/config/
COPY --link --chown=$COMPOSER_UID:$WWW_DATA_GID crayfish/Houdini/ crayfish/common/ Houdini/config/

COPY --link --chown=$COMPOSER_UID:$WWW_DATA_GID crayfish/syn-settings.xml syn-settings.xml

RUN \
  --mount=type=secret,id=composer-auth,target=/home/composer/auth.json,uid=$COMPOSER_UID \
  --mount=type=cache,target=/home/composer/cache,uid=$COMPOSER_UID \
  <<EOS
for i in "Homarus" "Houdini" "Hypercube"; do \
  composer require --working-dir=$i --no-update --no-interaction -- \
    "discoverygarden/crayfish-commons-syn:${SYN_COMPOSER_SPEC}" ; \
  composer install --working-dir=$i --no-dev --no-interaction ; \
done
EOS

USER root

RUN chown -R $WWW_DATA_UID:$WWW_DATA_GID .

#--------------------------------------------------------------

USER root
# Set ENV var OMP_THREAD_LIMIT=1 to avoid multi-threading
ENV OMP_THREAD_LIMIT=1

CMD ["/usr/sbin/apachectl", "-D", "FOREGROUND"]
