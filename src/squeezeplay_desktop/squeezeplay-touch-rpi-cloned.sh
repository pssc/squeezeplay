#!/bin/sh

## Change this if you changed your install path
INSTALL_DIR=${SP_INSTALL_DIR:="/opt/squeezeplay"}

# General
LIB_DIR=${INSTALL_DIR}/lib
OLD_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
LD_LIBRARY_PATH=$LIB_DIR:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH

# rpi-fbcp delay from fbtft if possible
# direct module load
FPS=$(awk 'match($0, /^options fbtft_device .* fps=([0-9]+)/) { print substr($0,RSTART,RLENGTH) }' /etc/modprobe.d/*.conf| awk 'match($0, /fps=([0-9]+)/) { print substr($0,RSTART,RLENGTH) }' | sed 's/fps=//')
# device tree
[ -z "$FPS" ] && FPS=$(awk 'match($0, /fps=([0-9]+)/) { print substr($0,RSTART,RLENGTH) }' /boot/config.txt| awk 'match($0, /fps=([0-9]+)/) { print substr($0,RSTART,RLENGTH) }' | sed 's/fps=//')
export FPS=${FPS:-12}

cd ${INSTALL_DIR}/bin || exit 1

## Start up
FBDEV=${FBDEV:-"/dev/fb1"} ./fbcp &
LD_LIBRARY_PATH=$OLD_LD_LIBRARY_PATH ./squeezeplay-touch.sh
FBCP=$!
[ ! -z '$FBCP' ] && kill $FBCP
