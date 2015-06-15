#!/bin/sh

NF=""
CHRT=""
pactester -v >/dev/null 2>&1 || NF="$NF pactester"
autossh -v   >/dev/null 2>&1 || NF="$NF autossh"
connect-proxy -n >/dev/null 2>&1 || NF="$NF connect-proxy"
curl --version >/dev/null 2>&1 || NF="$NF curl"
chrt --version >/dev/null 2>&1 && [ -n "${JIVE_RT_TUNNEL}" ] && CHRT="sudo chrt -r ${JIVE_RT_TUNNEL} sudo -u $(id -u -n)"
if [ -n "$NF" ];then
	echo "did not find$NF"
	exit 1
fi

if [ -z "$1" ];then
	echo "$0	TUNNEL_HOST [PORT] [DIRECT_PORT]"
	exit 1
fi

SCRIPT=$0
if [ "$1" = '-P' ];then
	# ProxyCommand for ssh
	HOST=$2
	PORT=${3:-22}
	DPORT=${4:-22}
else
	HOST=$1
	PORT=${2:-22}
	DPORT=${3:-22}
	SSHPROXY="ProxyCommand $SCRIPT -P %h %p ${DPORT}"
	AUTOSSH_POLL=30
	AUTOSSH_LOGLEVEL=5
	export AUTOSSH_POLL AUTOSSH_LOGLEVEL
	exec $CHRT autossh -M 2000:7 -o "$SSHPROXY" -L 10000:localhost:9000 -L 4483:localhost:3483 -L 8888:localhost:8888 -o "ExitOnForwardFailure yes" -p ${PORT} -N squeezeplay@${HOST} &
	# Ideally we would have a tunnel per function but we would need to reestart independantly
	#autossh -M 2000:7 -o "$SSHPROXY" -L 10000:localhost:9000 -o "ExitOnForwardFailure yes" -p ${PORT} -N squeezeplay@${HOST} &
	#autossh -M 2001:7 -o "$SSHPROXY" -L 4483:localhost:3483 -o "ExitOnForwardFailure yes" -p ${PORT} -N squeezeplay@${HOST} &
	#autossh -M 2002:7 -o "$SSHPROXY" -L 8888:localhost:8888 -o "ExitOnForwardFailure yes" -p ${PORT} -N squeezeplay@${HOST} &
	wait
	exit
fi

PROXY=$(curl -s http://wpad/wpad.dat | pactester -p - -u ssh://squeezeplay@${HOST}:${PORT})
case $PROXY in 
	PROXY*)
		PROXY=$(echo "$PROXY "|sed 's/PROXY //')
	;;
	*)
		PROXY=""
		PORT=$DPORT
	;;
esac

if [ "$PROXY" ];then
	exec connect-proxy -H ${PROXY} ${HOST} ${PORT}
else
	exec connect-proxy ${HOST} ${PORT}
fi
