#!/bin/bash

# Automated Snipe-IT deployment script using Apache on Ubuntu 22.04

set -e

echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "Installing required packages..."
sudo apt install -y apache2 mariadb-server php php-mysql php-curl php-mbstring php-xml php-bcmath php-zip php-gd php-cli unzip git curl composer supervisor

echo "Cloning Snipe-IT repository..."
sudo git clone https://github.com/snipe/snipe-it /var/www/snipe-it
cd /var/www/snipe-it

echo "Setting ownership..."
sudo chown -R www-data:www-data /var/www/snipe-it
sudo chmod -R 755 /var/www/snipe-it

echo "Copying .env file..."
cp .env.example .env

echo "Installing PHP dependencies with Composer..."
sudo -u www-data composer install --no-interaction --prefer-dist --optimize-autoloader

echo "Generating application key..."
sudo -u www-data php artisan key:generate

echo "Configuring .env file..."
sed -i 's/DB_DATABASE=homestead/DB_DATABASE=snipeit/' .env
sed -i 's/DB_USERNAME=homestead/DB_USERNAME=root/' .env
sed -i 's/DB_PASSWORD=secret/DB_PASSWORD=/' .env

echo "Creating database..."
sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS snipeit CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "Running migrations and seeding database..."
sudo -u www-data php artisan migrate --seed --force

echo "Configuring Apache..."
sudo tee /etc/apache2/sites-available/snipeit.conf > /dev/null <<EOL
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot /var/www/snipe-it/public
    ServerName snipeit.local

    <Directory /var/www/snipe-it/public>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/snipeit_error.log
    CustomLog \${APACHE_LOG_DIR}/snipeit_access.log combined
</VirtualHost>
EOL

sudo a2ensite snipeit
sudo a2enmod rewrite
sudo systemctl reload apache2
sudo systemctl restart apache2

echo "Configuring Supervisor for queue management..."
sudo tee /etc/supervisor/conf.d/snipeit.conf > /dev/null <<EOL
[program:snipeit]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/snipe-it/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/www/snipe-it/storage/logs/worker.log
EOL

sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start snipeit

echo "Snipe-IT deployment complete! Access it via your server IP or hostname."
