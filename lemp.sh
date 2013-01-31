#!/bin/bash
#
# Copyright (c) 2013 Peter Rowlands <peter@pmrowla.com>
#
# Installs a base Ubuntu system along with nginx, mysql, php and/or python
#
# <UDF name="notify_email" Label="send email notification to" example="Email address to send notification and system alerts. You will receive a notification when your Linode is done being configured." />
# <UDF name="hostname" label="Your system's Hostname" />
# <UDF name="fqdn" label="Your system's Fully Qualified Domain Name" />
# <UDF name="user_name" label="Unprivilged user account name" example="This is the account you will normally use to log in. THIS IS DIFFERENT THAN THE SRCDS USER." />
# <UDF name="user_password" label="User password" />
# <UDF name="user_shell" label="User shell" oneof"/bin/zsh,/bin/bash" default="/bin/bash" />
# <UDF name="sshd_permitrootlogin" label="Permit SSH root login?" oneof="No,Yes" default="No">
# <UDF name="setup_nginx" label="Install nginx?" oneof="Yes,No" default="No" />
# <UDF name="nginx_ppa" label="Use nginx PPA?" oneof="Yes,No" default="No" />
# <UDF name="setup_mysql" label="Install MySQL?" oneof="Yes,No" default="No" />
# <UDF name="mysql_database_password" label="MySQL root password" default="" />
# <UDF name="setup_php" label="Install PHP?" oneof="Yes,No" default="No" example="Installs PHP, PHP-FPM" />
# <UDF name="setup_python" label="Install Python?" oneof="Yes,No" default="No" example="Installs Python, uWSGI" />

USER_GROUPS=sudo

source <ssinclude StackScriptID=1> # StackScript Bash Library
source <ssinclude StackScriptID=123> # lib-system-ubuntu
source <ssinclude StackScriptID=124> # lib-system
source <ssinclude StackScriptID=126> # lib-python

# Configure system
system_update
system_update_hostname "$HOSTNAME"
echo $(system_primary_ip) $HOSTNAME $FQDN >> /etc/hosts

# Create main user
system_add_user "$USER_NAME" "$USER_PASSWORD" "$USER_GROUPS" "$USER_SHELL"

# Configure sshd
system_sshd_permitrootlogin "$SSHD_PERMITROOTLOGIN"

# Install postfix
postfix_install_loopback_only
aptitude -y install mailutils

# Install logcheck
system_security_logcheck

# Install fail2ban
system_security_fail2ban

# Setup firewall
system_security_ufw_install
system_security_ufw_configure_basic

# Install byobu
aptitude -y install byobu tmux

# Install python
python_install

# Install generic dev tools
system_install_utils
system_install_build
system_install_git
system_install_mercurial

# Install nginx
if [ "$SETUP_NGINX" == "Yes" ]; then
    if ["$NGINX_PPA" == "Yes"]; then
        apt-add-repository ppa:nginx/stable
        aptitude update
    fi
    aptitude -y install nginx
fi

if [ "$SETUP_MYSQL" == "Yes" ]; then
    set +u
    mysql_install "$MYSQL_DATABASE_PASSWORD" && mysql_tune 25
    # re-enable innodb, since Linode's script disables it
    sed -i -e 's/^skip-innodb/#skip-innodb/' /etc/mysql/my.cnf
    set -u
fi

if ["$SETUP_PHP" == "Yes" ]; then
    aptitude -y install php5 php5-fpm
    if [ "$SETUP_MYSQL" == "Yes" ]; then
        aptitude -y install php5-mysql
    fi
fi

if ["$SETUP_PYTHON" == "Yes" ]; then
    aptitude -y install uwsgi uwsgi-plugin-python
    if [ "$SETUP_MYSQL" == "Yes" ]; then
        yes | pip install MySQL-python
    fi
fi

restart_services
restart_initd_services

# Send info message
cat > ~/setup_message <<EOD
Hi,

Your Linode VPS configuration is completed.

EOD

mail -s "Your Linode VPS is ready" "$NOTIFY_EMAIL" < ~/setup_message
