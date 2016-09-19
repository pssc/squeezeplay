#!/bin/bash

## Depends bash, awk, ts_calibrate, fbcp, fbset

## Change this if you changed your install path
SP_INSTALL_DIR=${SP_INSTALL_DIR:-"/opt/squeezeplay"}



# General
LIB_DIR=$SP_INSTALL_DIR/lib
OLD_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$LIB_DIR:$LD_LIBRARY_PATH

[ -r "${SP_INSTALL_DIR}/etc/default/squeezeplay" ] && . ${SP_INSTALL_DIR}/etc/default/squeezeplay
[ -r "${SP_INSTALL_DIR}/etc/default/squeezeplay-common" ] && . ${SP_INSTALL_DIR}/etc/default/squeezeplay-common

# TSLIB
#export TSLIB_FBDEVICE=${TSLIB_FBDEVICE:-"/dev/fb0"} ?
export TSLIB_TSDEVICE=${TSLIB_TSDEVICE:-"/dev/input/touchscreen"}
export TSLIB_CALIBFILE=${TSLIB_CALIBFILE:-"/etc/pointercal"}
export TSLIB_CONFFILE=${TSLIB_CONFFILE:-"/etc/ts.conf"}
export TSLIB_PLUGINDIR=${TSLIB_PLUGINDIR:-"${SP_INSTALL_DIR}/lib/ts"}

if [ -r "/dev/input/touchscreen-big" -a ! -r "${TSLIB_CALIBFILE}" ];then
	export TSLIB_TSDEVICE="/dev/input/touchscreen-big"
	export TSLIB_CALIBFILE="/etc/pointercal-touchscreen-big"
elif [ -r "/dev/input/touchscreen-rpi-lcd" -a ! -r "${TSLIB_CALIBFILE}" ];then
	export TSLIB_TSDEVICE="/dev/input/touchscreen-rpi-lcd"
	export TSLIB_CALIBFILE="${SP_INSTALL_DIR}/etc/pointercal-touchscreen-rpi-lcd"
	[  ! -r "$TSLIB_CALIBFILE" -a -r "$SP_INSTALL_DIR$TSLIB_CALIBFILE" ] && export TSLIB_CALIBFILE="$SP_INSTALL_DIR$TSLIB_CALIBFILE"
elif [ -r "/dev/input/touchscreen-medium" -a ! -r "${TSLIB_CALIBFILE}" ];then
	export TSLIB_TSDEVICE="/dev/input/touchscreen-medium"
	export TSLIB_CALIBFILE="/etc/pointercal-touchscreen-medium"
elif [ -r "$TSLIB_TSDEVICE" ];then
	PREFIX=$(basename $TSLIB_TSDEVICE)
	if [ -r "${TSLIB_CALIBFILE}-${PREFIX}" ];then
		export TSLIB_CALIBFILE="${TSLIB_CALIBFILE}-${PREFIX}"
	fi
fi

#RPI_LCD=$(grep -A 5 -q "FT5406 memory based driver" /proc/bus/input/devices | awk '/^H:/ { print "/dev/input/"$3;exit }' )
RPI_LCD=$(awk '/FT5406 memory based driver/ {for(a=0;a<=5;a++) {getline; {if(match($0,/event[0-9]+/)) { print "/dev/input/"substr($0, RSTART,RLENGTH);exit}}}}' /proc/bus/input/devices)
if [ ! -r "${TSLIB_TSDEVICE}" -a -n "${RPI_LCD}" ];then
	export RPI_LCD
        export TSLIB_TSDEVICE=${RPI_LCD}
	export TSLIB_CALIBFILE="${SP_INSTALL_DIR}/etc/pointercal-touchscreen-rpi-lcd"
fi

# SDL
export SDL_VIDEODRIVER=fbcon
export SDL_FBDEV=${SDL_FBDEV:-"/dev/fb0"}
if [ -r ${TSLIB_TSDEVICE} -a -r ${TSLIB_CALIBFILE} ];then
        export SDL_MOUSEDRV=TSLIB
	# Jive we dont wan't a cursor wth touchscreen.... this doesn't work in most double buffer HW anyway
	export JIVE_NOCURSOR=${JIVE_NOCURSOR:-1}
fi    

cd ${SP_INSTALL_DIR}/bin || exit 1

# Fall back to included
[ ! -r ${TSLIB_CONFFILE} ] && TSLIB_CONFFILE="${SP_INSTALL_DIR}/etc/ts.conf"

if [ ! -r ${TSLIB_TSDEVICE} ];then
                echo ${TSLIB_TSDEVICE} not vaild
                exit 1
fi

if [ -r ${TSLIB_TSDEVICE} -a ! -r ${TSLIB_CALIBFILE} ];then
	# Calibrate for res.
	printf "Resolution For Touch Screen (Display Mode Res not HW):"
	read RES
	fbset -a $RES || exit 1 #FIXME fbcp
	FBDEV=${FBDEV:-"/dev/fb1"} ./fbcp &
	FBCP=$!
	./ts_calibrate
	[ ! -z '$FBCP' ] && kill $FBCP
	exec $0 "$@"
	exit 
fi

## Start up
LD_LIBRARY_PATH=$OLD_LD_LIBRARY_PATH exec ./squeezeplay.sh
