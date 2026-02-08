#!/usr/bin/env bash
set -euo pipefail

# 1. Setup percorsi (Rispetto alla posizione dello script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JOOMLA_DIR="$ROOT_DIR/src"

# Carica .env se esiste
if [ -f "$ROOT_DIR/.env" ]; then
  export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

JOOMLA_BRANCH="${JOOMLA_BRANCH:-5.4-dev}"

echo ">> Inizio setup in: $ROOT_DIR"
echo ">> Branch Joomla: $JOOMLA_BRANCH"

# Creazione cartelle extensions se non esistono
mkdir -p "$ROOT_DIR/extensions/components" \
         "$ROOT_DIR/extensions/modules" \
         "$ROOT_DIR/extensions/plugins"

# 2. Clone di Joomla CMS
if [ -d "$JOOMLA_DIR" ]; then
  echo ">> Rimozione installazione precedente..."
  sudo rm -rf "$JOOMLA_DIR"
fi

echo ">> Clonando Joomla $JOOMLA_BRANCH in $JOOMLA_DIR..."
git clone --branch "$JOOMLA_BRANCH" https://github.com/joomla/joomla-cms.git "$JOOMLA_DIR"

# 3. Avvio Docker (Lanciato dalla root dove risiede docker-compose.yml)
cd "$ROOT_DIR"
echo ">> Costruzione e avvio container..."
docker compose up -d --build

# 4. Configurazione Ambiente Container
CONTAINER_PATH="/var/www/html"
echo ">> Configurazione permessi e Git Safe Directory..."
docker compose exec -T apache chown -R www-data:www-data /var/www/html
docker compose exec -T apache chmod 666 /var/www/html/configuration.php 2>/dev/null || true
docker compose exec -T apache git config --global --add safe.directory "$CONTAINER_PATH"

# 5. Composer & NPM
if [ -f "$JOOMLA_DIR/composer.json" ]; then
  echo ">> Installazione dipendenze PHP..."
  docker compose exec -T apache bash -c "cd $CONTAINER_PATH && composer install --no-interaction --ignore-platform-reqs"
fi

if [ -f "$JOOMLA_DIR/package.json" ]; then
  echo ">> Installazione dipendenze JS e build assets..."
  docker compose exec -T apache bash -c "cd $CONTAINER_PATH && npm ci && npm run build:css && npm run build:js"
fi

# Setup Cypress configuration
if [ -f "$JOOMLA_DIR/cypress.config.dist.mjs" ]; then
  echo ">> Setup Cypress configuration..."
  docker compose exec -T apache bash -c "cd $CONTAINER_PATH && cp cypress.config.dist.mjs cypress.config.mjs && \
    sed -i \"s|baseUrl: 'https://localhost/'|baseUrl: 'http://localhost:8080'|; \
    s|username: 'ci-admin'|username: 'admin'|; \
    s|password: 'joomla-17082005'|password: 'password1234'|; \
    s|db_host: 'localhost'|db_host: 'mysql'|; \
    s|db_name: 'test_joomla'|db_name: 'joomla'|; \
    s|db_user: 'root'|db_user: 'joomla'|; \
    s|db_password: ''|db_password: 'joomla'|\" cypress.config.mjs"
fi

# 6. Installazione Joomla via CLI
echo ">> Eseguo core:install di Joomla..."
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php installation/joomla.php install --site-name='Joomla 6 Dev' --admin-user='admin' --admin-username='admin' --admin-password='password1234' --admin-email='admin@example.com' --db-type='mysqli' --db-host='mysql' --db-user='joomla' --db-pass='joomla' --db-name='joomla' --db-prefix='jos_' --no-interaction"

echo "--> Applying development settings..."
# Configure Redis first (before other CLI commands that use sessions)
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set session_redis_server_host=redis"
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set session_redis_server_port=6379"
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set redis_server_host=redis"
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set redis_server_port=6379"
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set session_handler=redis"

# Enable debug mode and maximum error reporting for easier troubleshooting.
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set error_reporting=maximum"

# Configure mail settings for Mailpit
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set mailer=smtp"
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set smtphost=mailpit"
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set smtpport=1025"
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set smtpauth=0"
docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set smtpsecure=none"

# Configure Redis cache
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set cache_handler=redis"
#docker compose exec -T apache bash -c "cd $CONTAINER_PATH && php cli/joomla.php config:set caching=1"

# Ensure configuration.php is writable
docker compose exec -T apache chmod 666 /var/www/html/configuration.php
echo "✅ Development settings applied."

echo "------------------------------------------------"
echo ">> SETUP COMPLETATO!"
echo "------------------------------------------------"
echo ">> Sito: http://localhost:8080"
echo ">> Admin: http://localhost:8080/administrator"
echo "   User: admin / Password: password1234"
echo ""
echo ">> phpMyAdmin: http://localhost:8081"
echo "   User: ${MYSQL_USER:-joomla} / Password: ${MYSQL_PASSWORD:-joomla}"
echo "   Root: root / Password: ${MYSQL_ROOT_PASSWORD:-root}"
echo ""
echo ">> Mailpit UI: http://localhost:8025"
echo ""
echo ">> Redis: redis:6379 (from containers)"
echo "------------------------------------------------"