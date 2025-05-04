#!/bin/bash

# ────────────────────────────────────────────────────────────────
# Deploy Snipe-IT on Ubuntu 22.04 with Apache, PHP 8.3, MySQL
# Author: ChatGPT (OpenAI) + User Customizations
# ────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Settings ───────────────────────────────────────────────────
SNIPEIT_DIR="/var/www/snipe-it"
DB_NAME="snipeit"
DB_USER="snipeuser"
DB_PASS="snipepass"
ADMIN_EMAIL="admin@example.com"
APP_URL="http://$(hostname -I | awk '{print $1}')"

# ─── Functions ───────────────────────────────────────────────────
echo_section() {
  echo -e "\n\033[1;32m[+] $1\033[0m"
}

# ─── Prerequisites ───────────────────────────────────────────────
echo_section "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# ─── Install PHP 8.3 ─────────────────────────────────────────────
echo_section "Installing PHP 8.3 and dependencies..."
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install -y php8.3 php8.3-cli php8.3-mbstring php8.3-bcmath php8.3-curl php8.3-xml php8.3-mysql php8.3-zip php8.3-common php8.3-gd php8.3-readline php8.3-soap php8.3-intl php8.3-pgsql php8.3-fpm

sudo update-alternatives --set php /usr/bin/php8.3

# ─── Install Apache, MariaDB, Composer ───────────────────────────
echo_section "Installing Apache, MariaDB, Git, and Composer..."
sudo apt install -y apache2 mariadb-server unzip curl git
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# ─── Configure MariaDB ───────────────────────────────────────────
echo_section "Configuring MariaDB..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# ─── Clone Snipe-IT ──────────────────────────────────────────────
echo_section "Cloning Snipe-IT repository..."
sudo rm -rf ${SNIPEIT_DIR}
sudo git clone https://github.com/snipe/snipe-it ${SNIPEIT_DIR}
sudo chown -R $USER:www-data ${SNIPEIT_DIR}
cd ${SNIPEIT_DIR}

# ─── Install Dependencies ────────────────────────────────────────
echo_section "Installing PHP dependencies via Composer..."
composer install --no-dev --prefer-dist

# ─── Environment Configuration ───────────────────────────────────
echo_section "Copying .env file..."
cp .env.example .env

sed -i "s|APP_URL=http://localhost|APP_URL=${APP_URL}|g" .env
sed -i "s|DB_DATABASE=homestead|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|DB_USERNAME=homestead|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|DB_PASSWORD=secret|DB_PASSWORD=${DB_PASS}|g" .env

# ─── Laravel Key & Migrations ────────────────────────────────────
echo_section "Setting application key..."
sudo php artisan key:generate

echo_section "Running migrations and seeding database..."
sudo php artisan migrate --seed --force

# ─── Apache Configuration ────────────────────────────────────────
echo_section "Configuring Apache..."
SITE_CONF="/etc/apache2/sites-available/snipeit.conf"
sudo tee ${SITE_CONF} > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot ${SNIPEIT_DIR}/public
    <Directory ${SNIPEIT_DIR}/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/snipeit_error.log
    CustomLog \${APACHE_LOG_DIR}/snipeit_access.log combined
</VirtualHost>
EOF

sudo a2ensite snipeit
sudo a2enmod rewrite
sudo systemctl reload apache2

# ─── Configure Supervisor ────────────────────────────────────────
echo_section "Configuring Supervisor for queue management..."
SUPERVISOR_CONF="/etc/supervisor/conf.d/snipeit.conf"
sudo tee ${SUPERVISOR_CONF} > /dev/null <<EOF
[program:snipeit]
process_name=%(program_name)s_%(process_num)02d
command=php ${SNIPEIT_DIR}/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/supervisor/snipeit.log
EOF

sudo supervisorctl reread
sudo supervisorctl update

# ─── Done ────────────────────────────────────────────────────────
echo -e "\n✅ Snipe-IT installation and configuration completed."
echo "Access it at: ${APP_URL}/"
