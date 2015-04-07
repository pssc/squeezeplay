#!/bin/bash

## For running squeezplay under x with vnc client.

## Change these if you changed your install path
INSTALL_DIR=/opt/squeezeplay-old/

## Start up
export SDL_VIDEO_CENTERED=y
export SDL_VIDEODRIVER=x11
export SDL_FBDEV=/dev/fb0

if [ -z "$DISPLAY" ];then
	export SDL_VIDEODRIVER=fbcon
	x11vnc -no6 -mdns -nolookup -nopw -shared -many -rawfb $SDL_FBDEV &
	VNC=$!
else
	x11vnc -no6 -mdns -nolookup -nopw -shared -many &
	VNC=$!
fi

cd $INSTALL_DIR/bin && ./squeezeplay.sh
[ -z "$VNC" ] || kill $VNC
