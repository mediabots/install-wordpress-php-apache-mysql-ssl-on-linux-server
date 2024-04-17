#!/usr/bin/bash

#set -x # debug
 
# ENV for the Script
export DEBIAN_FRONTEND=noninteractive
 export HISTCONTROL=ignoredups:ignorespace

# - color
GREEN='\033[0;32m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Global vars
mysql_installed=0

NON_DEFAULT_MYSQL_PORT=3307

MYSQL_CONNECTION=100

#db_name_prefix=wp_db
db_host_local='localhost'
db_host_int='%'
db_user_local=wp_local_user
db_user_int=wp_net_user

# - port
MIN_PORT=30000
MAX_PORT=62000

# set sitename
if [ ! -z $1 ]; then
	SITENAME=$1
else
	if [ -z $SITENAME ]; then
		echo "sitename is not provided by you, please check our Script document to set the sitename"
		exit 1;
	fi
fi

echo $SITENAME

# replace . or - with _ from the sitename to populate database name prefix. Because a database name could not conatin - or .
db_name_prefix=${SITENAME//[-.]/_} 

# check whether MySQL database is already installed
if [ $(which mysql | grep 'mysql' -i | wc -l) -ge 1 ];then 
	mysql_installed=1
fi

# ------- MySQL server Installation

if [ $mysql_installed -eq 1 ]; then
	# check whether MySQL root user has auth_socket plugin enabled 
	mysql_root_user_permission=$(sudo mysql -e "select user, plugin from mysql.user" | grep root | grep auth_socket | wc -l)
	
	if [ $mysql_root_user_permission -eq 0 ]; then
		echo "Your server already has a MySQL installation, and its root user has incorrect permission, please check our Script document to make it correct"
		exit 1;
	fi
	# update & upgrade apt packages
	sudo apt update && sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" upgrade -qq -y --allow-change-held-packages
	sudo apt autoremove --yes
	
	# install a dependency
	sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" -qq -y install dos2unix --allow-change-held-packages
else
	# update & upgrade apt packages
	sudo apt update && sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" upgrade -qq -y --allow-change-held-packages
	sudo apt autoremove --yes

	# install MySQL server & dependency
	sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" -qq -y install mysql-server dos2unix --allow-change-held-packages

	#print MySQL version info
	mysql --version

	# set MySQL to auto start on every system reboot
	sudo systemctl enable --now mysql

	# set a non-default port for MYSQL
	if [ ! -z $RANDOMPORT ]; then
		MYSQL_PORT=$(($RANDOM%($MAX_PORT-$MIN_PORT+1)+$MIN_PORT))
	else
		if [ ! -z "${MYSQL_PORT//[0-9]}" ]; then
			if [ ! -n "$MYSQL_PORT" ]; then
				MYSQL_PORT=$NON_DEFAULT_MYSQL_PORT
			else
				if [ ! $MYSQL_PORT -ge $MIN_PORT ] || [ ! $MYSQL_PORT -le $MAX_PORT ]; then
					MYSQL_PORT=$NON_DEFAULT_MYSQL_PORT
				fi
			fi
		else
			MYSQL_PORT=$NON_DEFAULT_MYSQL_PORT
		fi
	fi

	# set max connection allowed for your MYSQL database
	if [ ! -z "${MAX_CONNECTION//[0-9]}" ]; then
		if [ ! -n "$MAX_CONNECTION" ]; then
			MAX_CONNECTION=$MYSQL_CONNECTION
		fi
	else
		MAX_CONNECTION=$MYSQL_CONNECTION
	fi

	# Change MySQL config
	# - uncomment iff you want remote access of your MySQL server
	#sudo sed -i 's/^bind-address.*$/bind-address = 0.0.0.0/g' /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i "s/#\?.*max_connections.*$/max_connections = ${MAX_CONNECTION}/g" /etc/mysql/mysql.conf.d/mysqld.cnf
	sudo sed -i "s/#\?.*port.*=.*$/port = ${MYSQL_PORT}/g" /etc/mysql/mysql.conf.d/mysqld.cnf

	# restart MySQL server to make above changes
	sudo systemctl restart mysql

	# securing MySQL root user by not allowing access to it by any remote host
        sudo mysql -e "SELECT count(1) from mysql.user where User='root'"
        sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
        sudo mysql -e "FLUSH PRIVILEGES"
        sudo mysql -e "SELECT count(1) from mysql.user where User='root'"

fi
	
# generate a random password for MySQL non-root user
export MYSQLPASSWORD=$(tr </dev/urandom -dc A-Za-z0-9*%^+~ | head -c12)$(tr </dev/urandom -dc 0-9 | head -c2)$(tr </dev/urandom -dc *%^+~ | head -c2)

# for every new wordpress website a new database name need to be selected. So, it will give the ability of multi-site in a single hosting 
while :; do
	echo "inside while loop"
	db_name=${db_name_prefix}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c4)
	db_exists=$(sudo mysql -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${db_name}'" | wc -l)
	if [ "$db_exists" == 0 ]; then
		break;
	fi
done

db_user_local=${db_user_local}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c6)
db_user_int=${db_user_int}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c6)

# MySQL local non-root user creation 
sudo mysql -e "CREATE DATABASE $db_name"
sudo mysql -e "CREATE USER '$db_user_local'@'$db_host_local' IDENTIFIED WITH caching_sha2_password BY '$MYSQLPASSWORD'"
sudo mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_local'@'$db_host_local' WITH GRANT OPTION"
sudo mysql -e "FLUSH PRIVILEGES"
# MySQL remote non-root user creation
#sudo mysql -e "CREATE USER '$db_user_int'@'$db_host_int' IDENTIFIED WITH caching_sha2_password BY '$MYSQLPASSWORD'"
#sudo mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_int'@'$db_host_int' WITH GRANT OPTION"
#sudo mysql -e "FLUSH PRIVILEGES"
# confirm MySQL user creation
sudo mysql -e "select user, plugin, host from mysql.user"
sudo mysql -e "show databases"


# ------- Wordpress Download and Configure

# Download Wordpress
wget http://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz

# Pre Configuring Wordpress
cp ./wordpress/wp-config-sample.php ./wordpress/wp-config.php
sed -i '/put your unique phrase here/d' ./wordpress/wp-config.php # delete matching pattern
sed -i '$d' ./wordpress/wp-config.php # delete last line
# - for an extra layer of security, replace default table prefix of Wordpress for MySQL
table_prefix=$(tr </dev/urandom -dc A-Za-z | head -c6)_ || WP_
sed -i 's/wp_/'$table_prefix'/g' ./wordpress/wp-config.php
# - place MySQL database information on wrodpress config
sed -i 's/database_name_here/'$db_name'/g' ./wordpress/wp-config.php
sed -i 's/username_here/'$db_user_local'/g' ./wordpress/wp-config.php
sed -i 's/password_here/'$MYSQLPASSWORD'/g' ./wordpress/wp-config.php
sed -i "s/define( 'DB_HOST', 'localhost' );/define( 'DB_HOST', '${db_host_local}' );/g" ./wordpress/wp-config.php
# - set up SALT to enhance Wordpress security
curl -s https://api.wordpress.org/secret-key/1.1/salt/ > ./wordpress/keys.txt
cat ./wordpress/keys.txt >> ./wordpress/wp-config.php
#sudo bash -c "cat ./wordpress/keys.txt >> ./wordpress/wp-config.php"
# - enable to update WordPress Directly without using any FTP
#sudo bash -c 'echo -en "define('FS_METHOD', 'direct');\r\nrequire_once(ABSPATH . 'wp-settings.php');" >> ./wordpress/wp-config.php'
echo -en "define('FS_METHOD', 'direct');\r\ndefine('WP_HOME','http://www.${SITENAME}');\r\ndefine('WP_SITEURL','http://www.${SITENAME}');\r\nrequire_once(ABSPATH . 'wp-settings.php');" >> ./wordpress/wp-config.php
dos2unix ./wordpress/wp-config.php
#rm -f ./wordpress/keys.txt

# ------- Installation of Php, Apache, Firewall, zip, sendmail, etc 

sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" -qq -y install liblua5.3-0 php-common php8.1-cli php8.1-common php8.1-opcache php8.1-readline php-json php8.1-cgi php8.1-curl php8.1-gd php8.1-mbstring php8.1-xml php8.1-xmlrpc php8.1-soap php8.1-intl php8.1-zip  --allow-change-held-packages

sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" -qq -y install apache2 libapache2-mod-php8.1 libxml2-dev zip php8.1-mysql sendmail --allow-change-held-packages

# configure sendmail
yes 'y' | sudo sendmailconfig 

# configure Apache
sudo systemctl enable --now apache2
sudo chown -R "$USER":root /var/www

# enable reverse proxy & load balancing capability for Apache
sudo a2enmod proxy proxy_http proxy_balancer lbmethod_byrequests

# - prepare Website for Apache
mkdir /var/www/html/$SITENAME
sudo touch /var/www/html/$SITENAME/.htaccess
APACHE_LOG_DIR=/var/log/apache2
cat << EOF | sudo tee /etc/apache2/sites-available/${SITENAME}.conf
<Directory /var/www/html/$SITENAME>
	AllowOverride All
</Directory>
<VirtualHost *:80>
	ServerAdmin admin@$SITENAME
	ServerName $SITENAME
	DocumentRoot /var/www/html/$SITENAME
	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# - enable the Wordpress site in Apache
sudo a2ensite ${SITENAME}.conf
#sudo systemctl reload apache2
# - disable the default Apache site
sudo a2dissite 000-default.conf
# - reload & restart to take the effect of above changes 
sudo systemctl reload apache2
sudo a2enmod rewrite
sudo systemctl restart apache2

# install Wordpress
sudo rsync -avP ./wordpress/ /var/www/html/$SITENAME/
# - enable uploading in Wordpress site
mkdir /var/www/html/$SITENAME/wp-content/uploads
# - set correct owner for /var/www/html directory
sudo chown -R www-data:www-data /var/www/html/
# - restart Apache to activate the Wordpress website
sudo systemctl restart apache2
# - set correct permissions for Wordpress files & folders
sudo find /var/www/html/$SITENAME -type d -exec chmod 750 {} \;
sudo find /var/www/html/$SITENAME -type f -exec chmod 640 {} \;

# clean
rm -rf ./wordpress/
rm -f latest.tar.gz

# ------- Firewall Installation & configuration

sudo systemctl stop ufw
sudo systemctl disable --now ufw
sleep 3
sudo apt remove --yes --purge ufw
sudo apt autoremove --yes
sudo -E apt -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" -qq -y install firewalld --allow-change-held-packages

# confirm Firewall state
sudo firewall-cmd --state

# replace ssh default port to the extracted ssh port so Firewall will whitelist that new port for incoming connection  
# - extarct SSH PORT
SSH_PORT=$(sudo cat /etc/ssh/sshd_config | grep -i port | head -1)
if  [[ $SSH_PORT != P* ]] ; then     
	SSH_PORT=22
else
	SSH_PORT=$(echo $SSH_PORT | awk '{print $2}')
fi
# - replace Firewall default port with extracted one
sudo sed -i "s/port=\".*\"/port=\"$SSH_PORT\"/g" /usr/lib/firewalld/services/ssh.xml
	
# reload Firewall to take the effect of the above config changes
sudo firewall-cmd --reload

# set Firewall to auto start on every system reboot
sudo systemctl enable --now firewalld

# set Firewall rules to allow HTTP & HTTPS traffic
sudo firewall-cmd --zone=public --add-port=80/tcp
sudo firewall-cmd --zone=public --permanent --add-port=80/tcp
sudo firewall-cmd --zone=public --add-port=443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=443/tcp

# list Firewall rules, etc 
sudo firewall-cmd --list-all
sudo firewall-cmd --get-default-zone
sudo firewall-cmd --get-active-zones

# ------- Info

echo "db_name=$db_name"
echo "db_user_local=$db_user_local"
echo "db_user_int=$db_user_int"
echo "MYSQLPASSWORD=$MYSQLPASSWORD"
