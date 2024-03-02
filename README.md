# Install Wordpress(Php,Apache,MySQL) & Firewall on a Linux server and add an SSL Certificate to your website
Script to auto install Wordpress and its dependencies such as: Php, Apache2, MySQL. 
Also, the script will automatically add an SSL certificate to your domain, and it will be configured to auto-renew your SSL periodically.

## Firewall:
Script will install a feature-rich Firewall and will configure it to allow only HTTP, HTTPS traffic.
In this case, the Firewall being used is Firewall-cmd, recommended by RedHat.

## MySQL (Relational Database Engine)
Script will install a MySQL databse securely. And Script will autoconfigure MySQL in such a way that only your Wordpress Application running on your remote host can access it.
So the database can't be accessible from outside your remote machine.
Since MySQL will not be accessible via the Internet. So your database will be super secure.

Script will create a non-root MySQL user for your Wordpress Application.



