#!/bin/bash
#
# Copyright (c) 2013 Peter Rowlands <peter@pmrowla.com>
#
# Installs the CS:GO dedicated server and sourcemod, along with the standard
# Ubuntu firewall.
#
# <UDF name="notify_email" Label="send email notification to" example="Email address to send notification and system alerts. You will receive a notification when your Linode is done being configured." />
# <UDF name="hostname" label="Your system's Hostname" />
# <UDF name="fqdn" label="Your system's Fully Qualified Domain Name" />
# <UDF name="user_name" label="Unprivilged user account name" example="This is the account you will normally use to log in. THIS IS DIFFERENT THAN THE SRCDS USER." />
# <UDF name="user_password" label="User password" />
# <UDF name="user_shell" label="User shell" oneof"/bin/zsh,/bin/bash" default="/bin/bash" />
# <UDF name="srcds_user" label="The name for the srcds user" default="srcds" />
# <UDF name="sshd_permitrootlogin" label="Permit SSH root login" oneof="No,Yes" default="No">

set -e
set -u

USER_GROUPS=sudo

exec &> /root/stackscript.log

source <ssinclude StackScriptID=1> # StackScript Bash Library
source <ssinclude StackScriptID=123> # lib-system-ubuntu

# Configure system
system_update
system_update_hostname "$HOSTNAME"
echo $(system_primary_ip) $HOSTNAME $FQDN >> /etc/hosts
touch /tmp/restart-hostname

# Create main user
system_add_user "$USER_NAME" "$USER_PASSWORD" "$USER_GROUPS" "$USER_SHELL"

# Configure sshd
system_sshd_permitrootlogin "$SSHD_PERMITROOTLOGIN"

# Install postfix
postfix_install_loopback_only

# Install logcheck
system_security_logcheck

# Install fail2ban
system_security_fail2ban

# Setup firewall
system_security_ufw_install
system_security_ufw_configure_basic
ufw allow 27015 # srcds
ufw allow 27020/udp # SourceTV

# Install byobu
aptitude -y install byobu tmux

# Configure the srcds user
SRCDS_HOME=/opt/srcds
system_add_system_user "$SRCDS_USER" "$SRCDS_HOME" ""

# Install srcds
STEAMCMD_DIR=$SRCDS_HOME/steamcmd
CSGO_DIR=$SRCDS_HOME/csgo-ds
sudo -u $SRCDS_USER mkdir -p $STEAMCMD_DIR
sudo -u $SRCDS_USER mkdir -p $CSGO_DIR
cd $SRCDS_HOME/steamcmd
sudo -u $SRCDS_USER wget http://blog.counter-strike.net/wp-content/uploads/2012/04/steamcmd.tar.gz
sudo -u $SRCDS_USER tar zxvf steamcmd.tar.gz
rm steamcmd.tar.gz
sudo -u $SRCDS_USER STEAMEXE=steamcmd ./steam.sh +login anonymous +force_install_dir $CSGO_DIR +app_update 740 validate

# Install metamod
cd $CSGO_DIR/csgo
sudo -u $SRCDS_USER wget http://www.metamodsource.net/mmsdrop/1.10/mmsource-1.10.0-hg816-linux.tar.gz
sudo -u $SRCDS_USER tar zxvf mmsource-1.10.0-*-linux.tar.gz
rm mmsource-1.10.0-*-linux.tar.gz
sudo -u $SRCDS_USER cat > addons/metamod.vdf <<EOD
"Plugin"
{
    "file"  "../csgo/addons/metamod/bin/server"
}
EOD

# Install sourcemod updater and sourcemod
cd $SRCDS_HOME
aptitude -y install lynx wget findutils rsync
wget https://github.com/bcserv/sourcemod-updater/archive/master.zip -O sourcemod-updater.zip
unzip sourcemod-updater.zip
rm sourcemod-updater.zip
mv sourcemod-updater-master sourcemod-updater
chown -R $SRCDS_USER:$SRCDS_USER sourcemod-updater
cd sourcemod-updater
chmod u+x update.sh
chmod u+w packagecache
sudo -u $SRCDS_USER ./update.sh $CSGO_DIR/csgo --snapshot-dev --install --dontask --fixpermissions

# Set up the init script
cd /etc/init.d
wget https://raw.github.com/pmrowla/srcds-service/master/srcds.sh
chmod +x srcds.sh
sed -i -e "s/^SRCDS_USER=.*$/SRCDS_USER=\"$SRCDS_USER\"/" srcds.sh
sed -i -e "s/^DIR=.*$/DIR=\"$CSGO_DIR\"/" srcds.sh
sed -i -e "s/^PARAMS=.*$/DIR=\"-game csgo\"/" srcds.sh

restart_services
restart_initd_services

# Send info message
cat > ~/setup_message <<EOD
Hi,

Your Linode VPS configuration is completed.

You will need to update /etc/init.d/srcds.sh with your server parameters.

EOD

mail -s "Your Linode VPS is ready" "$NOTIFY_EMAIL" < ~/setup_message
