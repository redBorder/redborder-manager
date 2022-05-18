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

source /usr/lib/redborder/lib/rb_manager_functions.sh
source /etc/profile

#PATH=$PATH:/opt/rb/bin
CONFIG_FILE="/var/opt/chef-server/erchef/etc/app.config"
VHOST=$(grep rabbitmq_vhost, $CONFIG_FILE | sed 's/^[^"]*"//' | sed 's/".*$//')
USER=$(grep rabbitmq_user, $CONFIG_FILE | sed 's/^[^"]*"//' | sed 's/".*$//')
PASS=$(grep rabbitmq_password, $CONFIG_FILE | sed 's/^[^"]*"//' | sed 's/".*$//')
DEFAULTPASSFILE="/etc/rabbitmq/rabbitmq-pass.conf"
RET=0

if [ "x$VHOST" != "x" -a "x$USER" != "x" -a "x$PASS" != "x" ]; then
    echo $VHOST | egrep -q "^/[a-zA-Z0-9]*$"
    [ $? -ne 0 ] && VHOST=""
    echo $USER | egrep -q "^[a-zA-Z0-9]*$"
    [ $? -ne 0 ] && USER=""
fi

if [ "x$VHOST" != "x" -a "x$USER" != "x" -a "x$PASS" != "x" ]; then
    get_mode rabbitmq
    [ "x$mode" == "xenabled" ] && wait_service rabbitmq

    [ ! -f $DEFAULTPASSFILE ] && touch $DEFAULTPASSFILE
    echo -n "Checking vhost ($VHOST) : "
    rb_rabbitmqctl list_vhosts|grep -q "^$VHOST"
    if [ $? -ne 0 ]; then
        echo "doesn't exist."
        rb_rabbitmqctl add_vhost $VHOST
        RET2=$?
        print_result $RET2
        [ $RET2 -ne 0 ] && RET=1
        
    else
        print_result 0
    fi

    echo -n "Checking list_exchanges ($VHOST) : "
    out=$(rb_rabbitmqctl list_exchanges -p $VHOST)
    echo $out | grep amq.direct | grep amq.match | grep amq.headers |grep amq.rabbitmq.trace |grep amq.topic|grep -q amq.fanout
    if [ $? -ne 0 ]; then
      rb_rabbitmqctl delete_vhost $VHOST
      RET2=$?
      print_result $RET2
      [ $RET2 -ne 0 ] && RET=1
      rb_rabbitmqctl add_vhost $VHOST
      RET2=$?
      print_result $RET2
      [ $RET2 -ne 0 ] && RET=1
    else
      print_result 0
    fi
   
    echo -n "Checking user ($USER) : "
    rb_rabbitmqctl list_users 2>&1 | grep -q "^$USER"
    if [ $? -ne 0 ]; then
        echo "doesn't exist."
        rb_rabbitmqctl add_user ${USER} "$PASS"
        RET2=$?
        print_result $RET2
        [ $RET2 -ne 0 ] && RET=1
    else
        print_result 0
    fi
    
    echo -n "Checking permissions ($USER) : "
    rb_rabbitmqctl list_permissions -p ${VHOST} 2>&1 | grep -q "^$USER"
    if [ $? -ne 0 ]; then    
        echo "doesn't exist."
        /opt/opscode/embedded/bin/rabbitmqctl set_permissions -p ${VHOST} ${USER} ".*" ".*" ".*"
        RET2=$?
        print_result $RET2
        [ $RET2 -ne 0 ] && RET=1
    else
        print_result 0
    fi

    read VAR < $DEFAULTPASSFILE
    if [ "x$VAR" != "x$PASS" ]; then
        rb_rabbitmqctl change_password $USER "$PASS"
        if [ $? -eq 0 ]; then
            echo -n "$PASS" > $DEFAULTPASSFILE
        fi
    fi
    date > /etc/rabbitmq/users_created
fi

exit $RET
