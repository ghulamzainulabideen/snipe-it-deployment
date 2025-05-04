#!/bin/bash

set -e

APP_DIR="/var/www/snipe-it"
REPO_URL="https://github.com/snipe/snipe-it.git"
DB_NAME="snipeit"
DB_USER="snipeituser"
DB_PASS="snipeitpass"
APP_URL="http://$(hostname -I | awk '{print $1}')"

echo "🔄 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "🧰 Installing dependencies..."
sudo apt install -y apache2 php php-cli php-common php-curl php-mbstring php-mysql php-xml php-bcmath php-gd php-zip php-readline php-tokenizer php-intl php-sqlite3 unzip curl git mariadb-server composer supervisor

echo "🧼 Cleaning up existing install (if any)..."
sudo systemctl stop apache2 || true
sudo rm -rf "$APP_DIR"
sudo mkdir -p "$APP_DIR"

echo "🐙 Cloning Snipe-IT repository..."
sudo git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

echo "🔐 Setting permissions..."
sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"

echo "🧱 Installing Composer dependencies..."
sudo composer install --no-dev --optimize-autoloader

echo "🛠️ Creating .env file..."
sudo cp .env.example .env

echo "⚙️ Configuring environment variables..."
sudo sed -i "s|APP_URL=.*|APP_URL=${APP_URL}|" .env
sudo sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
sudo sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
sudo sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env

echo "🗄️ Setting up MySQL database..."
sudo mysql -u root <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "🔑 Generating application key..."
sudo php artisan key:generate

echo "📦 Running database migrations..."
sudo php artisan migrate --seed --force

echo "🌐 Configuring Apache..."
SNIPE_CONF="/etc/apache2/sites-available/snipeit.conf"
sudo tee "$SNIPE_CONF" > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $APP_DIR/public
    <Directory $APP_DIR/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/snipeit_error.log
    CustomLog \${APACHE_LOG_DIR}/snipeit_access.log combined
</VirtualHost>
EOF

sudo a2dissite 000-default.conf
sudo a2ensite snipeit.conf
sudo a2enmod rewrite
sudo systemctl reload apache2

echo "🧃 Configuring Supervisor for queue worker..."
SUPERVISOR_CONF="/etc/supervisor/conf.d/snipeit.conf"
sudo tee "$SUPERVISOR_CONF" > /dev/null <<EOF
[program:snipeit]
process_name=%(program_name)s_%(process_num)02d
command=php $APP_DIR/artisan queue:work --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=$APP_DIR/storage/logs/worker.log
EOF

sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start snipeit

echo "✅ Snipe-IT installation completed successfully!"
echo "🌍 Access it at: ${APP_URL}"
