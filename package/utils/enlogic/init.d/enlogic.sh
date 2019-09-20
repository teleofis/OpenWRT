#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1
NAME=enlogic
PP=/usr/share/enlogic
PROG=$PP/enlogic

start_service()
{
	echo "Starting EnLogic system"
	ln -s $PP/network.conf.$(fw_printenv rtc_device | awk -F '=' '{print $2}' 2>/dev/null) $PP/network.conf
	cd $PP/
	$PP/start
}

start()
{
	start_service
}

stop()
{
	echo "Stopping EnLogic"
	killall spy
	killall enlogic
}

restart()
{
	stop
	start
}

