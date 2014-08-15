#!/bin/sh

##
## This script is a basic startup script for the SqueezePlay binary (jive) that requires a few environment variables be set.
##

## Change these if you changed your install path
INSTALL_DIR=/opt/squeezeplay/
LIB_DIR=$INSTALL_DIR/lib
INC_DIR=$INSTALL_DIR/inc

## Start up
export LD_LIBRARY_PATH=$LIB_DIR:$LD_LIBRARY_PATH
export LD_INCLUDE_PATH=$INC_DIR:$LD_INCLUDE_PATH
export PATH=$PATH:$INSTALL_DIR/bin

export SDL_VIDEODRIVER=fbcon
export SDL_MOUSEDRV=TSLIB
export SDL_FBDEV=/dev/fb1
export TSLIB_TSDEVICE=/dev/input/event5
export TSLIB_CALIBFILE=/var/tmp/pointercal
export TSLIB_CONFFILE=/var/tmp/ts.conf
export TSLIB_PLUGINDIR=/opt/squeezeplay/src/sp/build/linux/lib/ts
export JIVE_NOCURSOR=1
cd $INSTALL_DIR/bin
./jive

