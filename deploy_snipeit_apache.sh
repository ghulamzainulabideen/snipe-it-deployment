#!/bin/bash
set -e

log() {
  echo -e "\033[1;32m👉 $1\033[0m"
}

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

log "🔧 Updating package index and upgrading system..."
apt update && apt upgrade -y

log "📦 Installing dependencies..."
apt install -y software-properties-common curl gnupg2 ca-certificates lsb-release unzip zip git nginx mariadb-server php-cli php-common php-mbstring php-xml php-curl php-mysql php-zip php-bcmath php-gd php-intl php-readline

log "🧼 Cleaning up existing install (if any)..."
rm -rf /var/www/snipe-it

log "🐙 Cloning Snipe-IT repository..."
git clone https://github.com/snipe/snipe-it /var/www/snipe-it
cd /var/www/snipe-it

log "🔐 Setting permissions..."
chown -R www-data:www-data /var/www/snipe-it
chmod -R 755 /var/www/snipe-it

log "🧪 Checking PHP version..."
CURRENT_PHP=$(php -r 'echo PHP_VERSION;')
REQUIRED_PHP=8.2

if dpkg --compare-versions "$CURRENT_PHP" lt "$REQUIRED_PHP"; then
  log "⚠️ PHP version is $CURRENT_PHP. Upgrading to PHP 8.3..."

  add-apt-repository ppa:ondrej/php -y
  apt update
  apt install -y php8.3 php8.3-{cli,fpm,common,mbstring,xml,curl,mysql,zip,bcmath,gd,intl,readline}

  update-alternatives --set php /usr/bin/php8.3
  update-alternatives --set phar /usr/bin/phar8.3
  update-alternatives --set phar.phar /usr/bin/phar.phar8.3

  log "✅ PHP upgraded to $(php -r 'echo PHP_VERSION;')"
else
  log "✅ PHP version $CURRENT_PHP is sufficient."
fi

log "🧱 Installing Composer dependencies..."
cd /var/www/snipe-it
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
composer install --no-dev --optimize-autoloader

log "✅ Snipe-IT is installed and ready. You can now configure your .env file and web server."
