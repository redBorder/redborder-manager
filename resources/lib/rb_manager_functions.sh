#!/bin/bash

KNIFECFG="/root/.chef/knife.rb"

HOME="/root"
DEBUG=0
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"

CERT="/etc/chef/client.pem"
RSA="/var/www/rb-rails/config/rsa"

function valid_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function isnum() {
    return `echo "$1" | awk -F"\n" '{print ($0 != $0+0)}'`
}

function get_mode() {
    if [ -f /etc/redborder/mode/$1 ]; then
        mode=`</etc/redborder/mode/$1`
    else
        chkconfig --list $1 2>/dev/null|grep -q "3:on"
        if [ $? -eq 0 ]; then
          mode="enabled"
        else
          mode="disabled"
        fi
    fi
}

function e_title() {
    set_color cyan
    echo "######################################################################################################"
    echo -n "#  "
    set_color blue
    echo "$*"
    set_color cyan
    echo "######################################################################################################"
    set_color norm
}

function error_title() {
    set_color red
    echo "######################################################################################################"
    echo -n "#  "
    set_color orange
    echo "$*"
    set_color red
    echo "######################################################################################################"
    set_color norm
}


#
# function set_color(), next print will be in color
# colors: green, red, blue, norm
set_color() {
    if [ "x$BOOTUP" != "xnone" ]; then
        green="echo -en \\033[1;32m"
        red="echo -en \\033[1;31m"
        yellow="echo -en \\033[1;33m"
        orange="echo -en \\033[0;33m"
        blue="echo -en \\033[1;34m"
        black="echo -en \\033[1;30m"
        white="echo -en \\033[255m"
        cyan="echo -en \\033[0;36m"
        purple="echo -en \\033[0;35m"
        browm="echo -en \\033[0;33m"
        gray="echo -en \\033[0;37m"
        norm="echo -en \\033[1;0m"
        eval \$$1
    fi
}

delete_line() {
        echo -en "\033[2K"
        #echo -en "\033[1K"
}



e_ok() {
        $MOVE_TO_COL
        echo -n "["
        set_color green
        echo -n $"  OK  "
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 0
}

e_fail() {
        $MOVE_TO_COL
        echo -n "["
        set_color red
        echo -n $"FAILED"
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 1
}

function upload_pem() {
    NAMECERT="$1"
    LOCATIONCERT="$2"
    local ret=0

    if [ -f ${CERT} -a "x${LOCATIONCERT}" != "x" ]; then
        echo -n "Uploading $NAMECERT certificate ... "
        #this key is valid
        JSON="${LOCATIONCERT}.json"
        cat > $JSON <<- _RBEOF_
{
    "id": "${NAMECERT}_pem",
    "certname": "${NAMECERT}",
    "private_rsa": "`cat ${LOCATIONCERT} | tr '\n' '|' | sed 's/|/\\\\n/g'`"
}
_RBEOF_
        knife data bag delete certs ${NAMECERT}_pem -y &>/dev/null
        knife data bag from file certs $JSON &>/dev/null
        if [ $? -eq 0 ]; then
            ret=0
            e_ok
        else
            ret=0
            e_fail
        fi
        rm -f $JSON
    else
        ret=1
    fi
    return $ret
}

function print_result(){
    if [ "x$1" == "x0" ]; then
        e_ok
    else
        e_fail
    fi
}

function print_result_opposite(){
    if [ "x$1" == "x0" ]; then
        e_fail
    else
        e_ok
    fi
}



f_ticker_start() {
    local lock_ticker_file=$1
        {
        echo -n " "
        while : ; do
            for i in \\\\ \| / - ; do
                echo -e -n "\b$i"
                if [ -f /var/lock/${lock_ticker_file} ]; then
                    echo -e -n "\b"
                    sleep 1
                    rm -f /var/lock/${lock_ticker_file}
                    exit 0
                fi
                sleep 1
            done
        done

        } &
}

f_ticker_stop() {
    local lock_ticker_file=$1
    touch /var/lock/${lock_ticker_file}
    sleep 2
}

function wait_file() {
  local counter=0
  file=$1

  if [ "x$file" != "x" ]; then
    while [ ! -f $file -a $counter -lt 30 ]; do
        counter=$(($counter + 1 ))
        sleep 1
    done
  fi
}
function wait_service() {
  local counter=0
  local servret=0
  local service=$1

  if [ "x$service" != "x" ]; then
    service $service status &>/dev/null
    servret=$?

    while [ $servret -ne 0 -a $counter -lt 30 ]; do
        sleep 1
        service $service status &>/dev/null
        servret=$?
        counter=$(($counter + 1 ))
    done
  fi
}

function wait_port(){
  local port=$1
  if [ "x$port" != "x" ]; then
    nc -vz 127.0.0.1 $port &>/dev/null
    local flag=$?
    local counter=1
    local maxwait=$2
    [ "x$maxwait" == "x" ] && maxwait=10
    while [ $counter -lt $maxwait -a $flag -ne 0 ]; do
      nc -vz 127.0.0.1 $port &>/dev/null
      flag=$?
      counter=$(($counter + 1 ))
      sleep 1
    done
  fi
}

function executeToAll(){
  local script=$1
  nodes=$(/bin/serf members -status alive -format=json | /bin/jq -r .members[].name | /bin/cut -d ":" -f 1)

  for n in $nodes
  do
    execute $n $script
  done
}

function copyToAll(){
  local path=$1
  nodes=$(/bin/serf members -status alive -format=json | /bin/jq -r .members[].name | /bin/cut -d ":" -f 1)

  host=$(/usr/bin/hostname -s)

  for n in $nodes
  do
    if [ "$n" != "$host" ]; then
      copy_files $n $path
    fi
  done
}

function execute(){
  local node=$1
  local script=$2
  echo "Executing $script in $node"
  ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o StrictHostKeyChecking=no -i $RSA root@$node $script
}

function copy_files(){
  local node=$1
  local path=$2
  target="${path%/*}/"
  echo "Copying $path -> $1:$target"
  /usr/bin/scp -r -i $RSA -o StrictHostKeyChecking=no -o PasswordAuthentication=no $path root@$node:$target
}
