#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Try using: sudo $0"
   exit 1
fi

echo "Updating and installing dependencies..."
apt update && apt upgrade -y
apt install -y apache2 mysql-server php php-cli php-mysql php-curl php-mbstring php-xml php-bcmath php-zip php-gd php-tokenizer php-fileinfo unzip curl git composer supervisor

echo "Cloning Snipe-IT repository..."
git clone https://github.com/snipe/snipe-it /var/www/snipe-it
cd /var/www/snipe-it

echo "Setting ownership..."
chown -R www-data:www-data /var/www/snipe-it
chmod -R 755 /var/www/snipe-it

echo "Installing PHP dependencies via Composer..."
sudo -u www-data composer install --no-dev --prefer-source

echo "Copying .env file..."
sudo -u www-data cp .env.example .env

echo "Configuring .env file..."
sed -i "s/DB_DATABASE=homestead/DB_DATABASE=snipeit/" .env
sed -i "s/DB_USERNAME=homestead/DB_USERNAME=root/" .env
sed -i "s/DB_PASSWORD=secret/DB_PASSWORD=/" .env

echo "Setting application key..."
sudo -u www-data php artisan key:generate --force

echo "Running migrations and seeding database..."
sudo -u www-data php artisan migrate --force
sudo -u www-data php artisan db:seed --force

echo "Configuring Apache..."
cat <<EOL > /etc/apache2/sites-available/snipeit.conf
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot /var/www/snipe-it/public
    <Directory /var/www/snipe-it/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/snipeit_error.log
    CustomLog \${APACHE_LOG_DIR}/snipeit_access.log combined
</VirtualHost>
EOL

a2ensite snipeit.conf
a2enmod rewrite
systemctl reload apache2
systemctl restart apache2

echo "Configuring Supervisor for queue management..."
cat <<EOF > /etc/supervisor/conf.d/snipeit-worker.conf
[program:snipeit]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/snipe-it/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/www/snipe-it/storage/logs/worker.log
EOF

supervisorctl reread
supervisorctl update
supervisorctl start snipeit:*

echo "✅ Snipe-IT installation and configuration completed."
echo "Access it at: http://your-server-ip/"
