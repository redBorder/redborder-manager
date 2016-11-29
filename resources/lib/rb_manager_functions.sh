#!/bin/bash
#######################################################################
# Copyright (c) 2014 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

KNIFE="/usr/bin/knife"

if [ "x$UID" == "x0" ]; then
  KNIFECFG="/root/.chef/knife.rb"
else
  KNIFECFG="/var/www/rb-rails/config/knife.rb"
fi

HOME="/root"
DEBUG=0
RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"

CERT="/etc/chef-server/chef-webui.pem"
CERTUSER="chef-webui"

if [ ! -f $CERT ]; then
  CERT="/root/.chef/root.pem"
  CERTUSER="root"
  if [ ! -f $CERT ]; then
    CERT="/var/www/rb-rails/config/rb-chef-webui.pem"
    CERTUSER="rb-chef-webui"
  fi
fi

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
        $KNIFE data bag delete certs ${NAMECERT}_pem -c $KNIFECFG -y &>/dev/null
        $KNIFE data bag -c $KNIFECFG from file certs $JSON &>/dev/null
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
