#!/bin/bash

## Available environment variables to control this script
# BS_COLORS: Set to 0 to disable color output
# BS_DEBUG: Set to 1 to enable debug output
# BS_USER: The user to create files as (defaults to current user)
# BS_GROUP: The group to create files as (defaults to current user's primary group)
# BS_SKIP_SYSTEMD: Set to 1 to skip systemd installation
# BS_SYSTEMD_SERVICE_NAME: The name of the systemd service to create (default: nio-provisioning)
# BS_SYSTEMD_SALT_EXEC: The path to the salt-minion executable
# BS_SYSTEMD_SALT_CONF_DIR: The path to the provisioning configuration directory (default /opt/nio/provisioning)
# BS_SKIP_MINION: Set to 1 to skip minion configuration
# BS_MINION_MASTER: The master host of the provisioning server
# BS_PYTHON_EXEC: The path to the python3 executable for creating a virtualenv


_COLORS=${BS_COLORS:-$(tput colors 2>/dev/null || echo 0)}
__detect_color_support() {
	# shellcheck disable=SC2181
	if [ $? -eq 0 ] && [ "$_COLORS" -gt 2 ]; then
        RC='\033[1;31m'
        GC='\033[1;32m'
        BC='\033[1;34m'
        YC='\033[1;33m'
        CC='\033[1;36m'
        EC='\033[0m'
    else
        RC=""
        GC=""
        BC=""
        YC=""
        CC=""
        EC=""
    fi
}
__detect_color_support

echofatal() {
    printf "${RC} * FATAL${EC}: %s\\n" "$@" 1>&2;
	exit 1
}
echoerror() {
    printf "${RC} * ERROR${EC}: %s\\n" "$@" 1>&2;
}
echosuccess() {
    printf "${GC} SUCCESS${EC}: %s\\n" "$@";
}
echoinfo() {
    printf "${CC} *  INFO${EC}: %s\\n" "$@";
}
echowarn() {
    printf "${YC} *  WARN${EC}: %s\\n" "$@";
}
echodebug() {
    if [ "$_ECHO_DEBUG" -eq 1 ]; then
        printf "${BC} * DEBUG${EC}: %s\\n" "$@";
    fi
}

_ECHO_DEBUG=${BS_DEBUG:-0}
_USER=${BS_USER:-$(whoami)}
_GROUP=${BS_GROUP:-$(id -gn)}

if [ ! -x "$(command -v git)" ]; then
	echofatal "This script requires git. Make sure git is installed and run again."
fi

if [ ! -x "$(command -v virtualenv)" ]; then
	echofatal "This script requires running nio in a virtual environment. Make sure virtualenv is installed and run again."
fi

if [ "${BS_SKIP_SYSTEMD}" != "1" ] && [ ! -x "$(command -v systemctl)" ]; then
	echofatal "This script must be run on a systemd compatible device. Install systemd and try again."
fi

echoinfo "Some of this script requires root/sudo access, you may be prompted for your password"
sudo -v

read -p "nio Device ID (required): " DEVICE_ID </dev/tty
if [ -z "$DEVICE_ID" ]; then
	echofatal "A device ID is required, get this from the nio device manager"
fi

BOOTSTRAP_DIR=`mktemp -d`
echodebug "Using temp dir for bootstrapping:" $BOOTSTRAP_DIR

echoinfo "Downlaoding bootstrap repository"
git clone -q git://github.com/niolabs/provisioning.git $BOOTSTRAP_DIR

read -p "nio resource root folder (/opt/nio): " NIO_ROOT_PATH </dev/tty
NIO_ROOT_PATH=${NIO_ROOT_PATH:-/opt/nio}

if [ ! -d "$NIO_ROOT_PATH" ]; then
	sudo mkdir -p "$NIO_ROOT_PATH"
	sudo chown $_USER:$_GROUP "$NIO_ROOT_PATH"
fi

if [ -z "$VIRTUAL_ENV" ]; then
	read -p "No active virtualenv detected, which virtual env to use or create? ($NIO_ROOT_PATH/env) " VIRTUAL_ENV </dev/tty
	VIRTUAL_ENV=${VIRTUAL_ENV:-"$NIO_ROOT_PATH"/env}
	if [ ! -f "$VIRTUAL_ENV/bin/activate" ]; then
		echoinfo "No virtualenv detected at $VIRTUAL_ENV, creating one"
		PYTHON_EXEC=${BS_PYTHON_EXEC:-$(command -v python3)}
		echodebug "virtualenv -p \"$PYTHON_EXEC\" \"$VIRTUAL_ENV\""
		virtualenv -p "$PYTHON_EXEC" "$VIRTUAL_ENV"
	fi
	echoinfo "Activating virtualenv at $VIRTUAL_ENV"
	source "$VIRTUAL_ENV/bin/activate"
fi

if [ ! -x "$(command -v salt-minion)" ]; then
	echoinfo "Salt package not detected, installing now"
	pip install salt || echofatal "Unable to install salt, exiting"
fi

read -p "Path to nio project ($NIO_ROOT_PATH/project): " NIO_PROJECT_PATH </dev/tty
NIO_PROJECT_PATH=${NIO_PROJECT_PATH:-$NIO_ROOT_PATH/project}

if [ ! -f "$NIO_PROJECT_PATH/nio.conf" ]; then
	read -p "No nio project found at $NIO_PROJECT_PATH, would you like to create one? [Y,n]? " _CREATE_NIO_PROJ </dev/tty
	_CREATE_NIO_PROJ=${_CREATE_NIO_PROJ:-Y}
	if [ "${_CREATE_NIO_PROJ}" == "y" ] || [ "${_CREATE_NIO_PROJ}" == "Y" ]; then
		echoinfo "Creating nio project at $NIO_PROJECT_PATH"
		git clone -q git://github.com/niolabs/project_template.git $NIO_PROJECT_PATH
	fi
fi

if [ "${BS_SKIP_MINION}" != "1" ]; then
	echoinfo "Creating provisioning folder"
	mkdir -p "$NIO_ROOT_PATH/provisioning"
	cp -r "$BOOTSTRAP_DIR"/minion_conf/* "$NIO_ROOT_PATH/provisioning"
	MINION_MASTER_HOST=${BS_MINION_MASTER:-provisioning.n.io} \
		MINION_DEVICE_ID=$DEVICE_ID \
		NIO_PROJECT_DIR=$NIO_PROJECT_PATH \
		NIO_VIRTUALENV_DIR=$VIRTUAL_ENV \
		envsubst < "$BOOTSTRAP_DIR/minion_conf/minion" > "$NIO_ROOT_PATH/provisioning/minion"
fi

if [ "${BS_SKIP_SYSTEMD}" != "1" ]; then
	echoinfo "Creating systemd service file"
	SYSTEMD_SERVICE_NAME=${BS_SYSTEMD_SERVICE_NAME:-nio-provisioning}
	SYSTEMD_SALT_EXEC=${BS_SYSTEMD_SALT_EXEC:-$(command -v salt-minion)}
	SYSTEMD_SALT_CONF_DIR=${BS_SYSTEMD_SALT_CONF_DIR:-$NIO_ROOT_PATH/provisioning}
	SYSTEMD_FOLDER=/etc/systemd/system

	SYSTEMD_SERVICE_NAME=$SYSTEMD_SERVICE_NAME SYSTEMD_SALT_EXEC=$SYSTEMD_SALT_EXEC SYSTEMD_SALT_CONF_DIR=$SYSTEMD_SALT_CONF_DIR envsubst < "$BOOTSTRAP_DIR/systemd.service" > "$SYSTEMD_FOLDER/$SYSTEMD_SERVICE_NAME.service"

	echoinfo "Reloading systemd daemon and enabling provisioning service"
	sudo systemctl daemon-reload
	sudo systemctl enable $SYSTEMD_SERVICE_NAME.service
	echosuccess "Restart the provisioning service by running \"sudo service $SYSTEMD_SERVICE_NAME restart\""
fi

echosuccess "Node has been bootstrapped successfully!"
