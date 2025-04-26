#!/bin/bash

# Set variables
SNIPEIT_DIR="/var/www/snipe-it"
WEB_USER="www-data"
APACHE_CONF_DIR="/etc/apache2/sites-available"

# Update system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install dependencies
echo "Installing dependencies..."
sudo apt install -y \
    curl \
    git \
    unzip \
    php-cli \
    php-mbstring \
    php-xml \
    php-curl \
    php-zip \
    php-mysql \
    mariadb-server \
    apache2 \
    libapache2-mod-php \
    composer \
    supervisor \
    curl \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev

# Set up MariaDB database
echo "Setting up MariaDB..."
sudo mysql -e "CREATE DATABASE snipeit;"
sudo mysql -e "CREATE USER 'snipeituser'@'localhost' IDENTIFIED BY 'yourpassword';"
sudo mysql -e "GRANT ALL PRIVILEGES ON snipeit.* TO 'snipeituser'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Clone Snipe-IT repository
echo "Cloning Snipe-IT repository..."
cd /var/www
sudo git clone https://github.com/snipe/snipe-it.git snipe-it
cd snipe-it

# Install Composer dependencies
echo "Installing Composer dependencies..."
sudo composer install --no-dev --prefer-dist

# Set permissions for storage, bootstrap/cache, and .env
echo "Setting permissions..."
sudo chown -R $WEB_USER:$WEB_USER $SNIPEIT_DIR
sudo chmod -R 775 $SNIPEIT_DIR/storage $SNIPEIT_DIR/bootstrap/cache
sudo chmod 664 $SNIPEIT_DIR/.env

# Generate application key
echo "Generating application key..."
sudo php artisan key:generate

# Configure .env file for database connection
echo "Configuring .env file..."
sudo sed -i 's/DB_DATABASE=laravel/DB_DATABASE=snipeit/' .env
sudo sed -i 's/DB_USERNAME=root/DB_USERNAME=snipeituser/' .env
sudo sed -i 's/DB_PASSWORD=/DB_PASSWORD=yourpassword/' .env

# Run database migrations and seed
echo "Running migrations and seeding database..."
sudo php artisan migrate --seed

# Configure Apache
echo "Configuring Apache..."
sudo bash -c 'cat > /etc/apache2/sites-available/snipeit.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/snipe-it/public
    ServerName your-domain.com

    <Directory /var/www/snipe-it/public>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF'

# Enable Apache site and rewrite module
sudo a2ensite snipeit.conf
sudo a2enmod rewrite
sudo systemctl restart apache2

# Configure Supervisor for queue management
echo "Configuring Supervisor for queue management..."
sudo bash -c 'cat > /etc/supervisor/conf.d/snipeit.conf <<EOF
[program:snipeit]
process_name=%(program_name)s
command=php /var/www/snipe-it/artisan queue:work
autostart=true
autorestart=true
stderr_logfile=/var/log/snipeit.err.log
stdout_logfile=/var/log/snipeit.out.log
EOF'

# Update supervisor and start queue worker
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start snipeit

# Final message
echo "Snipe-IT installation and configuration complete. You can now access it at your-domain.com."
