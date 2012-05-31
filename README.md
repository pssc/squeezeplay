# ReduceBrightness

This is a fork of the squeezeplay repository from Logitech for the
ReduceBrightness patch.

The Squeezebox Touch and Radio have two brightness settings: manual and automatic.
The manual setting always has the same brightness level whether the Squeezebox
is being used, playing, stopped, or off. The automatic settings sets the
brightness based on the environment light conditions. It doesn't really
work if you try to control the player in a dark room, and the minimal
brightness level is set to a low level, because that the screen would be
at the lowest level, and you can't see a thing. This patch changes this
behaviour. It changes the implementation of both automatic and manual setting.

For the automatic setting, it introduces four new brightness settings:

- Active maximum
- Active minimum
- Screen saver maximum
- Screen saver minimum

When the system is active (you touch the screen, or use the remote control)
the brightness will remain between the active minimum and maximum. If
a screen saver is on, the brightness will remain between the screen saver
minimum and maximum.
There is an option to always use the active setting when the Squeezebox is
playing.

For the manual setting, you can set a manual brightness and a minimal brightness.
Manual brightness is the brightness when the system is active, minimum brightness
is the brightness when the screen saver is on. There are options to control when
the screen should reduce its brightness to the minimum setting: when playing,
when stopped, and/or when off.

Please note that the Now Playing screen saver is not really a screen saver, so
the brightness cannot be reduced when you use this screen saver.

This patch is originally developed for the Squeezebox Touch, but is also
reported to work on the Squeezebox Radio.

Included here are the source files, and a script to building a patch which can be
applied using the Patch Installer applet. If you just want to apply this patch to 
your Squeezebox, you do not need the code here: this patch is included in the 3rd
party repository.

To install, first install the Patch Installer applet:

1. Enable 3rd Party Plugins on the Squeezebox
1. On the Squeezebox, go to Settings/Advanced/Applet Installer/Patch Installer
1. Restart the Squeezebox
1. On the Squeezebox, go to Settings/Advanced/Patch Installer/Reduce Screensaver Brightness
1. Restart the Squeezebox

Settings can be found under Settings/Brightness.
