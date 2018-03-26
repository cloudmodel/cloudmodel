#!/bin/bash

#
# installimage main start script
#
# originally written by Florian Wicke and David Mayr
# (c) 2007-2015, Hetzner Online AG
#


# simple params - restart with other params
case $1 in
  proxmox4)             exec "$0" -c proxmox4 -x proxmox4 ;;
  proxmox5)             exec "$0" -c proxmox5 -x proxmox5 ;;
  hsa-baculadir)        exec "$0" -c hsa-baculadir -x hsa-baculadir ;;
  hsa-minimal64)        exec "$0" -c hsa-minimal64 -x hsa-minimal64 ;;
  hsa-managed)          exec "$0" -c hsa-managed -x hsa-managed ;;
  hsa-sql)              exec "$0" -c hsa-sql -x hsa-sql ;;
esac


clear
wd=$(pwd)
export wd

# important: set pipefile bash option, see bash manual
set -o pipefail

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export EXITCODE=0

# invalidate all caches, so we get the latest version from nfs
echo 3 >/proc/sys/vm/drop_caches


# realconfig
SCRIPTPATH="$(dirname "$0")"
REALCONFIG="$SCRIPTPATH/config.sh"

FOLD="$(mktemp -d /installimage.XXXXX)"

# copy our config file and read global variables and functions
cp -a "$REALCONFIG" /tmp/install.vars
. /tmp/install.vars

# clear debugfile
echo > "$DEBUGFILE"

# cleanup on EXIT
trap cleanup EXIT

# get command line options
if [ $# -lt 1 ] && [ ! -e "$AUTOSETUPCONFIG" ] ; then
  echo ""
  echo -e "${YELLOW}run  'installimage -h'  to get help for command line arguments."
  echo -e "${GREEN}starting interactive mode ...${NOCOL}"
  echo ""
  # press any key or sleep 1 sec ...
  read -n1 -t1
fi
. "$GETOPTIONSFILE"


# deleting possible existing files and create dirs
{
  umount -l "$FOLD/*"
  rm -rf "$FOLD"
  mkdir -p "$FOLD/nfs"
  mkdir -p "$FOLD/hdd"
} >/dev/null 2>&1
cd "$FOLD" || exit 1
myip=$(ifconfig eth0 | grep "inet addr" | cut -d: -f2 | cut -d ' ' -f1)
debug "# starting installimage on [ $myip ]"


# log hardware data
debug "-------------------------------------"
hwdata="/usr/local/bin/hwdata"
[ -f $hwdata ] && $hwdata | grep -v "^$" | debugoutput
debug "-------------------------------------"


# generate new config file with our parameters and the template config from the nfs-server
debug "# make clean config"
if [ -f /tmp/install.vars ]; then
  . /tmp/install.vars
else
  debug "=> FAILED"
fi

# Unmount all partitions and print an error message if it fails
output=$(unmount_all) ; EXITCODE=$?
if [ $EXITCODE -ne 0 ] ; then
  echo ""
  echo -e "${RED}ERROR unmounting device(s):$NOCOL"
  echo "$output"
  echo ""
  echo -e "${RED}Cannot continue, device(s) seem to be in use.$NOCOL"
  echo "Please unmount used devices manually or reboot the rescuesystem and retry."
  echo ""
  exit 1
fi
stop_lvm_raid ; EXITCODE=$?
if [ $EXITCODE -ne 0 ] ; then
  echo ""
  echo -e "${RED}ERROR stopping LVM and/or RAID device(s):$NOCOL"
  echo ""
  echo -e "${RED}Cannot continue, device(s) seem to be in use.$NOCOL"
  echo "Please stop used lvm/raid manually or reboot the rescuesystem and retry."
  echo ""
  exit 1
fi


# check if we have a autosetup-file, else we start the menu
if [ -e "$AUTOSETUPCONFIG" ] ; then

  # start autosetup
  export AUTOSETUP="true"
  cp "$AUTOSETUPCONFIG" "$FOLD/install.conf"
  [ "$OPT_CONFIGFILE" ] && mv "$AUTOSETUPCONFIG" "$AUTOSETUPCONFIG.bak-$(date +%Y%m%d-%H%M%S)"
  debug "# executing autosetup ..."
  if [ -f "$AUTOSETUPFILE" ] ; then
     . "$AUTOSETUPFILE" ; EXITCODE=$?
  else
    echo ""
    echo -e "${RED}ERROR: $AUTOSETUPFILE does not exist${NOCOL}"
    debug "=> FAILED, $AUTOSETUPFILE does not exist"
  fi

else

  # start the menu
  debug "# executing setupfile"
  if [ -f "$SETUPFILE" ] ; then
     . "$SETUPFILE" ; EXITCODE=$?
  else
    debug "=> FAILED, $SETUPFILE does not exist"
    echo ""
    echo -e "${RED}ERROR: Cant find files${NOCOL}"
  fi
fi

if [ "$EXITCODE" = "1" ]; then
  exit 1
fi