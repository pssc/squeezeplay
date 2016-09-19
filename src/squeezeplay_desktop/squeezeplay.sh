#!/bin/sh
##
## This script is a startup script for the SqueezePlay binary (jive) that requires a few environment variables be set.
##

## Change these if you changed your install path
SP_INSTALL_DIR=${SP_INSTALL_DIR:-"/opt/squeezeplay"}
# /usr/lib added to pick up system codecs such as libmad as they are not ditrbuted with squeezeplay by default
LIB_DIR=${SP_INSTALL_DIR}/lib/`uname -m`:${SP_INSTALL_DIR}/lib:/usr/lib

#SDL Options thay may be available to us.
# no wait for vsync
# export SDL_FBCON_DONT_CLEAR=1
# SDL_FBCON_NOVBL=1
# export SDL_FBCON_NOVBL
# DISPMAX ACCEL if available auto detection broken atm see fbset -i
# To force No ACCEL
# SDL_FBACCEL=0
# Most options are now in the SqueezePi Advanced menu.
if [ -r "/boot/bcm2708-rpi-b.dtb" ]; then
	# Work round borked auto detection for Pi
	SDL_FBACCEL=${SDL_FBACCEL:-176}
	export SDL_FBACCEL
fi
# DISPMANX_ID_FORCE_TV  5
# DISPMANX_ID_FORCE_LCD 4
# DISPMANX_ID_FORCE_OTHER 6 /* non-default display */
# SDL_DISPMANX_DISPLAY=5
# export SDL_DISPMANX_DISPLAY
# SDL_DISPMANX_DISPLAY_ALT=5
# export SDL_DISPMANX_DISPLAY_ALT
JIVE_NICE=-3
[ -r "${SP_INSTALL_DIR}/etc/default/squeezeplay" ] && . ${SP_INSTALL_DIR}/etc/default/squeezeplay
[ -r "${SP_INSTALL_DIR}/etc/default/squeezeplay-common" ] && . ${SP_INSTALL_DIR}/etc/default/squeezeplay-common

## Start up
LD_LIBRARY_PATH=$LIB_DIR:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH
PATH=$PATH:${SP_INSTALL_DIR}/bin
export PATH
JIVE_FR=${JIVE_FR:-22}
export JIVE_FR

##
# alsa threads are given an audio based RT PRi by the backend code
# but for audio to be streamed we need the data provided form the jive network thread
# stream... so elevate above the rest of the system
CHRT="nice -n ${JIVE_NICE:--3}"
if [ -n "${JIVE_RT_PRI}" ] then
	chrt --version  >/dev/null 2>&1 || NF="$NF chrt"
	if [ -n "$NF" ];then
		echo "did not find$NF" >&2
	else
		CHRT="chrt -r ${JIVE_RT_PRI}"
	fi
fi
#: >${JIVE_WATCHDOG_FILE:-/tmp/jive}
ulimit -c unlimited >/dev/null 2>&1
cd ${SP_INSTALL_DIR}/bin && exec ${CHRT} ./jive
