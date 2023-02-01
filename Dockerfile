FROM debian:11-slim

ENV CRAYFISH_GIT_REF=3.x

EXPOSE 80

RUN apt-get -qqy update \
  && apt-get -qqy --no-install-recommends install \
     ca-certificates curl git openssl sudo unzip \
     ffmpeg imagemagick tesseract-ocr \
     apache2 apache2-utils php php-common php-dev libapache2-mod-php \
     php-ctype php-iconv php-simplexml \
  && apt-get clean

# composer install
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 

COPY imagemagick_policy.xml /etc/ImageMagick-6/policy.xml


#--------------------------------------------------------------
# setup PHP
RUN mkdir -p /etc/php/7.4/dgi
COPY dgi_99-config.ini /etc/php/7.4/dgi/99-config.ini
RUN ln -s /etc/php/7.4/dgi/99-config.ini /etc/php/7.4/apache2/conf.d/99-config.ini \
  && ln -s /etc/php/7.4/dgi/99-config.ini /etc/php/7.4/cli/conf.d/99-config.ini

# setup apache2
#RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf \
RUN echo 'ErrorLog /dev/stderr' >> /etc/apache2/apache2.conf \
  && echo 'TransferLog /dev/stdout' >> /etc/apache2/apache2.conf \
  && echo 'CustomLog /dev/stdout combined' >> /etc/apache2/apache2.conf \
  && chown -R www-data /var/log/apache2

# disable and enable sites
COPY 25-80-crayfish.conf /etc/apache2/sites-available/
RUN a2dissite default-ssl.conf \
  && a2ensite 25-80-crayfish.conf \
  && rm /etc/apache2/sites-enabled/000-default.conf

# enable apache2 modules and sites
RUN a2enmod rewrite \
  && a2enmod ssl \
  && a2enmod proxy_http \
  && a2enmod headers 


RUN useradd composer -g www-data -m --uid 2000

#--------------------------------------------------------------
# setup crayfish

RUN mkdir -p /opt/www \
  && cd /opt/www/ \
  && git clone https://github.com/Islandora/Crayfish.git crayfish \
  && cd crayfish \
  && git checkout ${CRAYFISH_GIT_REF}

COPY crayfish/Homarus/ /opt/www/crayfish/Homarus/config/
COPY crayfish/Hypercube/ /opt/www/crayfish/Hypercube/config/
COPY crayfish/Houdini/ /opt/www/crayfish/Houdini/config/

COPY crayfish/common/ /opt/www/crayfish/Homarus/config/
COPY crayfish/common/ /opt/www/crayfish/Hypercube/config/
COPY crayfish/common/ /opt/www/crayfish/Houdini/config/

COPY crayfish/syn-settings.xml /opt/www/crayfish/syn-settings.xml

RUN ln -s /opt/www/crayfish/Houdini/config/services_dev.yaml /opt/www/crayfish/Houdini/config/services_prod.yaml \
  && chown -R composer:www-data /opt/www/crayfish


USER composer

RUN --mount=type=cache,target=/home/composer/cache,uid=2000 \
  cd /opt/www/crayfish/Homarus \
  && composer install --no-interaction \
  && cd /opt/www/crayfish/Houdini \
  && composer install --no-interaction \
  && cd /opt/www/crayfish/Hypercube \
  && composer install --no-interaction

USER root

RUN chown -R www-data:www-data /opt/www/crayfish


#--------------------------------------------------------------

USER root 

WORKDIR /opt/www/crayfish

CMD ["/usr/sbin/apachectl", "-D", "FOREGROUND"]
