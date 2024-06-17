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

function read_from_ip() {
    # check from ips readed from interface
    while read line; do
        IP=$(echo $line | awk '{print $2}' | tr '/' ' ' | awk '{print $1}')
        n=$(echo $line | sed 's/.*lo//')

        if [ "x$n" == "x" ]; then
            ip a del ${IP}/32 dev lo
        else
            n=$(echo $line | sed 's/.*lo://')
            if [ -f /etc/sysconfig/network-scripts/ifcfg-lo\:$n ]; then
                source /etc/sysconfig/network-scripts/ifcfg-lo\:$n
                [ "x$IPADDR" != "x$IP" ] && ip a del ${IP}/32 dev lo:$n 
            else
                ip a del ${IP}/32 dev lo:$n
            fi
        fi
    done <<< "$(ip a s lo|grep "lo"|grep inet | grep global)"

}

read_from_ip

for n in $(ls /etc/sysconfig/network-scripts/ifcfg-lo\:* | sed 's|/etc/sysconfig/network-scripts/ifcfg-lo:||'); do 
    if [ -f /etc/sysconfig/network-scripts/ifcfg-lo\:$n ]; then
        source /etc/sysconfig/network-scripts/ifcfg-lo\:$n
  
        if [ "x$IPADDR" != "x" ]; then
            CURRENT=$(ip a s lo |grep "lo:$n$" |grep inet|grep -v "127.0.0.1/8"|grep "global"| awk '{print $2}' | tr '/' ' ' | awk '{print $1}' | head -n 1)
            if [ "x$CURRENT" != "x$IPADDR" ]; then
                ifdown lo:$n
                [ "x$CURRENT" != "x" ] && ip a del ${CURRENT}/32 dev lo:$n
                ifup lo:$n
            fi
        fi
    fi
done