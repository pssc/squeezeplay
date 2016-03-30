
## This is the linux configuration file
# use 'scons -h' to see the list of command line options available

import os
prefix = os.getenv("PREFIX")

# Compiler flags (based on Debian's installation of lua)
#LINKFLAGS = ['-g']
CCFLAGS = ['-I/usr/local/include','-I'+prefix+'/include', '-O2', '-ansi', '-Wall']
#CCFLAGS = ['-I/usr/include/lua50', '-g']

# this is the default directory for installation. Files will be installed on
# <prefix>/bin, <prefix>/lib and <prefix>/include when you run 'scons install'
#
# You can also specify this directory on the command line with the 'prefix'
# option
#
# You can see more 'generic' options for POSIX systems on config_posix.py

# libraries (based on Debian's installation of lua)
LIBPATH = [prefix+'/lib','/usr/local/lib',prefix+'/lib']
LIBS = ['lua', 'dl', 'm']

