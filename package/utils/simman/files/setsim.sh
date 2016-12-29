#!/bin/sh

OPTIND=1

GPIO_PATH=/sys/class/gpio
CONFIG_DIR=/etc/simman
tag=simman

sim=""
mode=""
pow=""

while getopts "h?s:mp" opt; do
        case "$opt" in
        h|\?)
                echo "Usage: ./setsim.sh [option]"
				echo "Options:"
				echo "	-s - number sim card, 0 - SIM1 1 - SIM2"
				echo "  -m - without SIMDET_PIN pushed"
				echo "  -p - modem power down"
				echo "Example: ./setsim.sh -s 1"
                exit 0
        ;;
		s) sim=$OPTARG
		;;
		m) mode="1"
		;;
		p) pow="1"
		;;
        esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

[ -z "$sim" ] && {
	sim="0"
}

[ -z "$mode" ] && {
	mode="0"
}

[ -z "$pow" ] && {
	pow="0"
}

# read GPIO configuration
GSMPOW_PIN=$(uci -q get simman.core.gsmpow_gpio_pin)
[ -z "$GSMPOW_PIN" ] && {
	logger -t $tag "Not set GSMPOW_PIN" && exit 0 
}

SIMDET_PIN=$(uci -q get simman.core.simdet_gpio_pin)
[ -z "$SIMDET_PIN" ] && {
	logger -t $tag "Not set SIMDET_PIN" && exit 0
}

SIMADDR_PIN=$(uci -q get simman.core.simaddr_gpio_pin)
[ -z "$SIMADDR_PIN" ] && {
	logger -t $tag "Not set SIMADDR_PIN" && exit 0
}

SIMDET0_PIN=$(uci -q get simman.core.simdet0_gpio_pin)
[ -z "$SIMDET0_PIN" ] && {
	logger -t $tag "Not set SIMDET0_PIN" && exit 0
}

SIMDET1_PIN=$(uci -q get simman.core.simdet1_gpio_pin)
[ -z "$SIMDET1_PIN" ] && {
	logger -t $tag "Not set SIMDET1_PIN" && exit 0
}

# GPIO ports configure 
if [ ! -d "$GPIO_PATH/gpio$GSMPOW_PIN" ]; then
	echo $GSMPOW_PIN > $GPIO_PATH/export
	echo out > $GPIO_PATH/gpio$GSMPOW_PIN/direction
	logger -t $tag "Exporting gpio$GSMPOW_PIN"
fi

if [ ! -d "$GPIO_PATH/gpio$SIMDET_PIN" ]; then
	echo $SIMDET_PIN > $GPIO_PATH/export
	echo out > $GPIO_PATH/gpio$SIMDET_PIN/direction
	logger -t $tag "Exporting gpio$SIMDET_PIN"
fi

if [ ! -d "$GPIO_PATH/gpio$SIMADDR_PIN" ]; then
	echo $SIMADDR_PIN > $GPIO_PATH/export
	echo out > $GPIO_PATH/gpio$SIMADDR_PIN/direction
	logger -t $tag "Exporting gpio$SIMADDR_PIN"
fi

if [ ! -d "$GPIO_PATH/gpio$SIMDET0_PIN" ]; then
	echo $SIMDET0_PIN > $GPIO_PATH/export
	echo in > $GPIO_PATH/gpio$SIMDET0_PIN/direction
	logger -t $tag "Exporting gpio$SIMDET0_PIN"
fi

if [ ! -d "$GPIO_PATH/gpio$SIMDET1_PIN" ]; then
	echo $SIMDET1_PIN > $GPIO_PATH/export
	echo in > $GPIO_PATH/gpio$SIMDET1_PIN/direction
	logger -t $tag "Exporting gpio$SIMDET1_PIN"
fi

# find 3g interface
iface=$(uci show network | grep "proto='3g'" | awk -F'.' '{print $2}')

[ -z "$iface" ] && logger -t $tag "Not found 3g interface" && exit 0 

# Check if SIM card placed in holder
sim1=$(cat $GPIO_PATH/gpio$SIMDET0_PIN/value)
sim2=$(cat $GPIO_PATH/gpio$SIMDET1_PIN/value)
ac_sim=$(uci -q get simman.core.sim)

if [ "$sim1" == "1" ] && [ "$sim2" == "1" ]; then
	logger -t $tag "Both SIM cards are not inserted"
	[ "$ac_sim" != "0" ] && uci -q set simman.core.sim=0
	# release SIM_DET pin
	echo "0" > $GPIO_PATH/gpio$SIMDET_PIN/value
	exit 0
fi

[ "$sim" == "0" ] && {
	[ "$sim1" == "1" ] && logger -t $tag "Not inserted sim 1" && exit 0 
	[ "$ac_sim" == "1" ] && [ "$pow" != "1" ]  && ubus call network.interface.$iface down && logger -t $tag "SIM 1 is already active" && ubus call network.interface.$iface up && exit 0
	logger -t $tag "Set SIM card 1"
}

[ "$sim" == "1" ] && {
	[ "$sim2" == "1" ] && logger -t $tag "Not inserted sim 2" && exit 0 
	[ "$ac_sim" == "2" ] && [ "$pow" != "1" ] && ubus call network.interface.$iface down && logger -t $tag "SIM 2 is already active" && ubus call network.interface.$iface up && exit 0
	logger -t $tag "Set SIM card 2"
}

# set down 3g interface
ubus call network.interface.$iface down

# setting new apn, GPRS settings (pincode, user name, password)
apn=$(uci -q get simman.@sim$sim[0].GPRS_apn)
if [ -z "$apn" ]; then
 uci -q delete network.$iface.apn
else
 uci -q set network.$iface.apn=$apn
fi

pin=$(uci -q get simman.@sim$sim[0].pin)
if [ -z "$pin" ]; then
 uci -q delete network.$iface.pincode
else
 uci -q set network.$iface.pincode=$pin
fi

user=$(uci -q get simman.@sim$sim[0].GPRS_user)
if [ -z "$user" ]; then
 uci -q delete network.$iface.username
else
 uci -q set network.$iface.username=$user
fi

pass=$(uci -q get simman.@sim$sim[0].GPRS_pass)
if [ -z "$pass" ]; then
 uci -q delete network.$iface.password
else
 uci -q set network.$iface.password=$pass
fi

# Set sim card
if [ "$mode" == "0" ]; then
 echo "0" > $GPIO_PATH/gpio$SIMDET_PIN/value
 
 sleep 1

 # Power switch
 if [ "$pow" == "1" ]; then

  logger -t $tag "Reset pin toggle"
  # release SIMADDR
  echo "0" > $GPIO_PATH/gpio$SIMADDR_PIN/value  

  sleep 2
  # power down
  echo "1" > $GPIO_PATH/gpio$GSMPOW_PIN/value

  sleep 2

  # power up
  echo "0" > $GPIO_PATH/gpio$GSMPOW_PIN/value

  sleep 4
 else
  retry=0



  while [ $retry -lt 10 ]; do
     retry=`expr $retry + 1`

     reg=$($CONFIG_DIR/getreg.sh)

     [ "$reg" == "'UNKNOWN'" ] || [ "$reg" == "'NOT REGISTERED'" ] || [ "$reg" == "NONE" ] && break

	 logger -t $tag "retry #$retry reading CREG, now registration status $reg"

	 sleep 1
  done
 fi  
fi

if [ "$sim" == "1" ]; then
 echo "1" > $GPIO_PATH/gpio$SIMADDR_PIN/value
 uci -q set simman.core.sim=2 
else
 echo "0" > $GPIO_PATH/gpio$SIMADDR_PIN/value
 uci -q set simman.core.sim=1 
fi

sleep 1

if [ "$mode" == "0" ]; then
 echo "1" > $GPIO_PATH/gpio$SIMDET_PIN/value
fi 

# store uci changes
uci commit 

# network reload
ubus call network reload

# reload 
ubus call network.interface.$iface up

exit 0
