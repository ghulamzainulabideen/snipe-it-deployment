#!/bin/bash

# Exit on error
set -e

# Variables
MYSQL_ROOT_PASSWORD="Mis@$0786"
DB_NAME="tms"
DB_USER="tms"
DB_PASS="Mis@$0786"
ADMIN_EMAIL="samis.home@punjab.gov.pk"
ADMIN_PASSWORD="Mis@$1441420"
APP_URL="http://$(hostname -I | awk '{print $1}')"
TIMEZONE="Asia/Karachi"

echo "🧼 Updating system..."
apt update && apt upgrade -y

echo "🐬 Installing MariaDB..."
debconf-set-selections <<< "mariadb-server mariadb-server/root_password password $MYSQL_ROOT_PASSWORD"
debconf-set-selections <<< "mariadb-server mariadb-server/root_password_again password $MYSQL_ROOT_PASSWORD"
apt install -y mariadb-server mariadb-client

echo "🔧 Configuring MariaDB..."
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "🌐 Installing Apache, PHP 8.3, and dependencies..."
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y apache2 php8.3 libapache2-mod-php8.3 php8.3-{cli,mbstring,xml,bcmath,curl,zip,gd,mysql} unzip git curl composer

echo "📁 Installing Snipe-IT..."
rm -rf /var/www/snipe-it
git clone https://github.com/snipe/snipe-it /var/www/snipe-it
cd /var/www/snipe-it

cp .env.example .env
sed -i "s|APP_URL=.*|APP_URL=$APP_URL|" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=$TIMEZONE|" .env

echo "🧱 Installing PHP dependencies with Composer..."
composer install --no-interaction --prefer-dist --optimize-autoloader

echo "🔐 Setting permissions..."
chown -R www-data:www-data /var/www/snipe-it
chmod -R 755 /var/www/snipe-it

echo "🔑 Generating app key, running migrations, and seeding..."
php artisan key:generate --force
php artisan migrate --force
php artisan db:seed --force

echo "🧍 Creating admin user..."
php artisan snipeit:create-admin --email="$ADMIN_EMAIL" --password="$ADMIN_PASSWORD" --first_name="Sami" --last_name="Admin"

echo "🌍 Configuring Apache..."
cat > /etc/apache2/sites-available/snipeit.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/snipe-it/public

    <Directory /var/www/snipe-it/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf
a2ensite snipeit.conf
a2enmod rewrite
systemctl reload apache2

echo "✅ Snipe-IT installed and ready at $APP_URL"
