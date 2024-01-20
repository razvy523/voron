#!/bin/bash

# bash script that downloads and installs karmen websocket-proxy
# download latest release from https://github.com/fragaria/websocket-proxy/
# and install it to /home/biqu/websocket-proxy

# check if nodejs is installed
# install nodejs if not installed
# download latest release and extract it to /home/pi/websocket-proxy
# create systemd service file for karmen websocket-proxy
# start karmen websocket-proxy

# Install nodejs first!
# curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - && sudo apt install nodejs -y
# And then:
# curl -s https://raw.githubusercontent.com/fragaria/karmen-gists/main/ws-install.sh | sudo bash -s KEY

set -e
set -u  # unset variable is error

die() {
    echo "$*"
    exit 1
}

if [ ${EUID} -ne 0 ]; then
    echo "This script must be run as root. Cancelling" >&2
    exit 1
fi

if [ -z "${1-}" ]
then
      echo "No karmen key provided. Use ./install.sh <key>"
      exit 1
fi

KEY=$1
echo ""
sudo -v

LOGIN=pi
GROUP=pi
USER_HOME=/home/$LOGIN

AS_PI_USER="sudo -u $LOGIN"

# download latest release

cd $USER_HOME || die "Could not cd to home dir, exitting."
$AS_PI_USER git clone --depth 1 https://github.com/fragaria/websocket-proxy.git
cd $USER_HOME/websocket-proxy/ || die "Something is wrong, could not switch to $USER_HOME/websocket-proxy"
$AS_PI_USER npm install --only=production

echo "Preparing config for websocket proxy"
CONFFILE=$USER_HOME/printer_data/config/websocket-proxy.conf
$AS_PI_USER tee $CONFFILE > /dev/null <<EOF
KARMEN_URL=https://karmen.fragaria.cz
NODE_ENV=production
PATH=/bin
FORWARD_TO=http://127.0.0.1
KEY=$KEY
SERVER_URL=wss://cloud.karmen.tech
FORWARD_TO_PORTS=80,8888
EOF
echo Done


echo "Creating websocket-proxy service"
WS_SERVICE_FILE=/etc/systemd/system/websocket-proxy.service
cat > $WS_SERVICE_FILE <<EOD
[Unit]
Description=Karmen websocket proxy tunnel client
Wants=network-online.target
After=network.target network-online.target

[Service]
ExecStart=node client
Restart=always
RestartSec=5
User=$LOGIN
Group=$GROUP
Environment=PATH=/usr/bin:/usr/local/bin
EnvironmentFile=$CONFFILE
WorkingDirectory=$USER_HOME/websocket-proxy/

[Install]
WantedBy=multi-user.target
EOD
echo Done

echo "Setting up Karmen key to be visible in configs"
# setup Karmen printer key (necessary for ws proxy to be able to connect
WS_KEY_FILE=$USER_HOME/printer_data/config/karmen-key.txt
if [ ! -f  $WS_KEY_FILE ]; then
    $AS_PI_USER tee $WS_KEY_FILE > /dev/null <<<"$KEY"
fi
echo Done

echo "Setting up Moonraker Update Manager to manage websocket-proxy service"
# setup moonraker
$AS_PI_USER tee -a $USER_HOME/printer_data/config/moonraker.conf > /dev/null <<EOF
[update_manager websocket-proxy]
type: git_repo
path: ~/websocket-proxy
origin: https://github.com/fragaria/websocket-proxy.git
enable_node_updates: True
managed_services:
    websocket-proxy
EOF
# allow moonraker to manage websocket-proxy systemd service
MOONSVC=$USER_HOME/printer_data/moonraker.asvc
if ! cat $MOONSVC | grep websocket-proxy > /dev/null; then
        echo "websocket-proxy" >> $MOONSVC
    else
        echo "Websocket already enabled!";
fi
echo Done


echo "Fixing possible permission problems"
chmod 755 $USER_HOME/
echo Done

echo "Starting websocket proxy service"
systemctl daemon-reload
systemctl enable websocket-proxy.service
systemctl restart websocket-proxy.service
echo Done
