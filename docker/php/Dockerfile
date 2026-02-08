FROM php:8.4-apache

# Installazione dipendenze di sistema
RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libzip-dev zip unzip git curl libicu-dev \
    xvfb libgtk2.0-0 libgtk-3-0 libgbm-dev libnotify-dev \
    libnss3 libxss1 libasound2 libxtst6 xauth \
    && rm -rf /var/lib/apt/lists/*

# Configurazione ed installazione estensioni PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd zip mysqli pdo_mysql intl bcmath

# Installazione Xdebug e Redis
RUN pecl install xdebug redis && docker-php-ext-enable xdebug redis

# Abilitazione mod_rewrite per Apache
RUN a2enmod rewrite

# Installazione Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Installazione Node.js (per build assets)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Installazione globale Cypress
RUN npm install -g cypress && cypress install

WORKDIR /var/www/html