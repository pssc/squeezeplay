#!/bin/sh

##
## This script is a basic startup script for the SqueezePlay binary (jive) that requires a few environment variables be set.
##

## Change these if you changed your install path
SP_INSTALL_DIR=${SP_INSTALL_DIR:-"/opt/squeezeplay"}
# /usr/lib added to pick up system codecs such as libmad as they are not ditrbuted with squeezeplay by default
LIB_DIR=${SP_INSTALL_DIR}/lib/`uname -m`:${SP_INSTALL_DIR}/lib:/usr/lib

#SDL Options thay may be available to us.
# no wait for vsync
#SDL_FBCON_NOVBL=1
#export SDL_FBCON_NOVBL

## Start up
LD_LIBRARY_PATH=$LIB_DIR:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH
PATH=$PATH:${SP_INSTALL_DIR}/bin
export PATH
JIVE_FR=${JIVE_FR:-14}
export JIVE_FR

##
# alsa threads are given an audio based RT PRi by the backend code
# but for audio to be streamed we need the data provided from the jive
# stream... so elevate above the rest of the system and mark as RT.
# A custom script to get all the depenacies will be needed on Maxed out systems
CHRT=""
chrt --version  >/dev/null 2>&1 || NF="$NF chrt"
if [ -n "$NF" ];then
        echo "did not find$NF" >&2
	CHRT="nice -n -1"
else
	[ -n "${JIVE_RT_PRI}" ] && CHRT="chrt -r ${JIVE_RT_PRI}"
fi
#: >${JIVE_WATCHDOG_FILE:-/tmp/jive}
cd ${SP_INSTALL_DIR}/bin && exec ${CHRT} ./jive
