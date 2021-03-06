#!/bin/ksh

grey="\033[01;30m"
red="\033[01;31m"
green="\033[01;32m"
yellow="\033[01;33m"
blue="\033[01;34m"
magenta="\033[01;35m"
cyan="\033[01;35m"
bold="\033[01;39m"

white="\033[0m"

set -A sets 'comp' 'game' 'man' 'etc' 'base'
set -A xsets 'xbase' 'xfont' 'xserv' 'xshare' 'xetc'
base_sig='SHA256.sig'

function usage {
  cat <<EOF

snap options:

  -s force snap to use snapshots.
  -S do not check signatures.
  -c specify location of config file (default is ~/.snaprc)
  -e just extract sets in DST.
  -f force snap to use ftp sources (http is default).
  -a <arch> use <arch> instead of what is 'arch' returns.
  -m <machine> use <machine> instead of what 'machine -s' returns.
  -v <version> used to force snap to use <version> (examples: snapshots or 5.3).
  -V <setversion> used to force snap to use <setversion> for sets (example: -V 5.3). Note: this will only apend 53 to sets, ie base53.tgz
  -r run sysmerge after extracting {x}sets.
  -x do not extract x11 sets.
  -M specify a mirror to use (example: " -M ftp3.usa.openbsd.org")
  -i interactive with colors
  -n force using bsd.mp as bsd
  -k only install kernels and exit
  -B do not backup current kernel
  -h help

  Examples:
    To update to the latest snapshot using the fastest mirror for your
    region:

      snap -s -M ftp3.usa.openbsd.org

    To update to the lastest version of 5.3 without updating xsets:

      snap -v 5.3 -V 5.3 -x -M ftp3.usa.openbsd.org

  Example ~/.snaprc
    INTERACTIVE:true
    DST:/tmp/upgrade
    MERGE:true
    MIRROR:ftp3.usa.openbsd.org
    NO_X11:true
    PROTO:ftp

EOF
  exit 0
}

function get_conf_var {
  RET=''
  if [ -e $CONF_FILE ]; then
    RET=$( grep $1 $CONF_FILE | awk -F\: '{print $2}' )
  fi

  if [ "${RET}X" == "X" ]; then
    return 1
  else
    echo $RET
  fi
}

function set_conf_var {
  MAKE=false
  if [ -e $CONF_FILE ]; then
    MAKE=true
  fi
}

function mkd {
  if [ ! -e $1 ]; then
    msg "mkdir: ${1}"
    mkdir -p $1
  fi
}
#  Saving this for a later date. 
##function ksd {
#   if [ ! -e $2 ]; then
#      msg "mkdir: ${2}
#       mkdir -p $2
#
#    fi
#

function msg {
  if [ $INTERACTIVE == true ]; then
    echo "${green}${1}${white}"
  fi
}

function error {
  if [ $INTERACTIVE == true ]; then
    echo "${red}${1}${white}"
  fi
  exit 1
}

function backup {
  FAIL=0
  cp /bsd /obsd || FAIL=1
  cp /bsd.rd /obsd.rd || FAIL=1
  cp /sbin/reboot /sbin/oreboot || FAIL=1

  if [ $FAIL == 1 ]; then
    error "Failed to backup, are you root?"
  else
    msg "Backed up the following:
    ${bold}/bsd => /obsd
    /bsd.rd => /obsd.rd
    /sbin/reboot => /sbin/oreboot${green}"
  fi
}

function verisigs {
  KEY=/etc/signify/openbsd-${SETVER}-base.pub
  VALID=true

  for i in $@; do
    signify -V -e -p ${KEY} -x SHA256.sig -m - | sha256 -C - ${i} \
      || VALID=false
  done

  if [ $VALID == false ]; then
    error "Invalid signature found! They are after you!"
  fi
}

function update_kernel {
  FAIL=0
  if [ $SKIP_SIGN == false ]; then
    verisigs "bsd*"
  fi
  cp ${KERNEL} /bsd || FAIL=1
  cp ${RD} /bsd.rd || FAIL=1
  if [ $FAIL == 1 ]; then
    error "Failed to copy new kernel, are you root?"
  else
    msg "Set primary kernel to ${KERNEL}:
    ${KERNEL} => /bsd"
  fi
}

function fetch {
  /usr/bin/ftp $FTP_OPTS $1
  if [ $? == 0 ]; then
    return 0
  else
    return $?
  fi
}

function extract {
  FAIL=0
  if [ $PV == 1 ]; then
    pv ${1} | tar -C / -xzphf - || FAIL=1
  else
    tar -C / -vxzphf $1 || FAIL=1
  fi

  if [ $FAIL == 1 ]; then
    error "Extract of ${1} failed, permissions?"
  fi
}

function copy {
  FAIL=0
  cp $1 $2 || FAIL=1
  if [ $FAIL == 1 ]; then
    error "Can't copy ${1} to ${2}"
  fi
}

ARCH=$( arch -s )
CONF_FILE=~/.snaprc
SKIP_SIGN=false
CPUS=$( sysctl hw.ncpufound | awk -F\= '{print $2}' )
INTERACTIVE=$( get_conf_var 'INTERACTIVE' || echo 'false' )
DST=$( get_conf_var 'DST' || echo '/tmp/upgrade' )
EXTRACT_ONLY=false
KERNEL_ONLY=false
FTP_OPTS=" -V "
MACHINE=$( machine )
MERGE=$( get_conf_var 'MERGE' || echo 'false' )
NO_X11=$( get_conf_var 'NO_X11' || echo 'false' )
PROTO=$( get_conf_var 'PROTO' || echo 'http' )
PV=0
SETVER=$( uname -r | sed -e 's/\.//' )
VER=$( uname -r )
VIRTUAL=$( sysctl hw.model | cut -d\= -f 2 | awk '{print $1}' )

if [ -e ~/.last_snap ]; then
  msg "last snap run: ${white}$(cat ~/.last_snap)"
fi

sysctl kern.version | grep -q "\-current"
if [ $? == 0 ]; then
  msg "kern.version: ${white}reporting as -current"
  VER='snapshots'
fi

if [ -x /usr/local/bin/pv ]; then
  PV=1
fi

MIRROR=$( get_conf_var 'MIRROR' || echo 'ftp3.usa.openbsd.org' )

while getopts "sSfea:sm:sv:srV:spxR:sAM:shiBkn" arg; do
  case $arg in
    s)
      VER='snapshots'
      ;;
    c)
      CONF_FILE=$OPTARG
      ;;
    S)
      SKIP_SIGN=true
      ;;
    f)
      PROTO=ftp
      ;;
    a)
      ARCH=$OPTARG
      ;;
    e)
      EXTRACT_ONLY=true
      ;;
    m)
      MACHINE=$OPTARG
      ;;
    v)
      VER=$OPTARG
      ;;
    V)
      SETVER=$( echo $OPTARG | sed -e 's/\.//' )
      ;;
    x)
      NO_X11=true
      ;;
    r)
      MERGE=true
      ;;
    M)
      MIRROR=$OPTARG
      ;;
    h)
      usage
      ;;
    i)
      INTERACTIVE=true
      ;;
    B)
      NO_KBACKUPS=true
      ;;
    k)
      KERNEL_ONLY=true
      ;;
    n)
      FORCE_MP=true
      ;;
  esac
done

if [ -z $NO_KBACKUPS ]; then
  backup
fi

mkd $DST

URL="${PROTO}://${MIRROR}/pub/OpenBSD/${VER}/${MACHINE}"

msg "${white}Fetching from repo: ${green}${URL}"

(
  cd $DST

  # first element should be bsd, second should be mp for given kernel names.
  if [ "${MACHINE}" == "armv7" ]; then
    TYPE=$(uname -v | awk -F\- '{print $NF}' | cut -d# -f1)
    # Currently there is no bsd.mp
    #set -A bsds "bsd.${TYPE}" "bsd.mp.${TYPE}" "bsd.rd.${TYPE}" "bsd.${TYPE}.umg"
    set -A bsds "bsd.${TYPE}" "" "bsd.rd.${TYPE}" "bsd.${TYPE}.umg"
  else
    set -A bsds 'bsd' 'bsd.mp' 'bsd.rd'
  fi

  RD=${bsds[2]}

  if [ "${CPUS}" == "1" ] && [ -z $FORCE_MP ]; then
    msg "${white}Using ${green}bsd.."
    KERNEL=${bsds[0]}
  else
    msg "${white}Using ${green}bsd.mp.."
    KERNEL=${bsds[1]}
  fi

  if [ $SKIP_SIGN == false ]; then
    fetch "${URL}/${base_sig}" || error "Can't fetch signature file!"
  fi

#TODO mount msdos volume and copy umg files.
# It is likeley I will never do this. 


  if [ $EXTRACT_ONLY == false ]; then
    msg "Fetching bsds..."
    for bsd in ${bsds[@]}; do
      fetch "${URL}/${bsd}" || error "Can't find bsds at ${URL}"
    done

    update_kernel

    if [ $KERNEL_ONLY == true ]; then
      exit 0
    fi

     msg "Fetching sets"
     for set in ${sets[@]}; do
       fetch "${URL}/${set}${SETVER}.tgz" || error "Perhaps you need to specify -V to set version. Example 5.2"
     done

     if [ "${NO_X11}" == "false" ]; then
       msg "Fetching xsets"
       for set in ${xsets[@]}; do
         fetch "${URL}/${set}${SETVER}.tgz" || error "Perhaps you need to specify -V to set version. Example -V 5.2"
       done
     fi
  fi

  if [ $SKIP_SIGN == false ]; then
    verisigs "*.tgz"
  fi

  msg "Extracting sets"
  for set in ${sets[@]}; do

    if [ "${set}" != "etc" ]; then
      extract ${set}${SETVER}.tgz
    fi

    if [ "${set}" == "man" ] && [ "${NO_X11}" == "false" ]; then
      msg "Extracting xsets ${white} will continue with sets after. ${green}"

      for xset in ${xsets[@]}; do
        if [ "${xset}" != "xetc" ]; then
          extract ${xset}${SETVER}.tgz
        fi
      done
    fi
  done
 # # MERGE THE STOPS
  if [ $MERGE ]; then
    MERG_OPT=""
    if [ $SKIP_SIGN == true ]; then
      MERG_OPT="-S"
    fi
    if [ "${NO_X11}" == "false" ]; then
      sysmerge ${MERG_OPT} -s etc${SETVER}.tgz -x xetc${SETVER}.tgz
    else
      sysmerge ${MERG_OPT} -s etc${SETVER}.tgz
    fi
  else
    echo "Don't forget to run:\n\tsysmerge -s ${DST}/etc${SETVER}.tgz -x ${DST}/xetc${SETVER}.tgz"
  fi

## ADDED THIS FOR MY VIRUTAL BOXES N STUFF
  if [ "${VIRTUAL}" == "QEMU" ]; then
    msg "Running as VM, please disable mpbios"
    config -e -f /bsd
  fi

  date > ~/.last_snap
)
