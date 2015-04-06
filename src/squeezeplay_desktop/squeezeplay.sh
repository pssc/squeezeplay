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

cd ${SP_INSTALL_DIR}/bin && exec ./jive
