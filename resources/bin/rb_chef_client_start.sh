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

source /etc/profile

PID=$(ps aux|grep chef-client|egrep "node-name|worker"|grep -v grep |grep -v vim |grep -v once|grep -v init.d|grep -v service | awk '{print $2}')

if [ "x$PID" != "x" ]; then
  echo "chef-client is already running. Killing it before starting the service ($PID)"
  kill -9 $PID
  rm -f /var/run/chef/client.pid
fi

# check /etc/chef/client.pem
if [ ! -f /etc/chef/client.pem ]; then
  if [ -f /root/.chef/knife.rb ]; then
    HOME="/root" knife client -c $RBDIR/root/.chef/knife.rb --disable-editing create $HOSTNAME > /etc/chef/client.pem
    if [ $? -eq 0 ]; then
      HOME="/root" knife node -c $RBDIR/root/.chef/knife.rb --disable-editing create $HOSTNAME
      HOME="/root" knife node -c $RBDIR/root/.chef/knife.rb run_list add $CLIENTNAME "role[manager]"
    fi
  fi
fi

exec /usr/bin/env /usr/bin/chef-client -c /etc/chef/client.rb --node-name $(hostname -s) -j /etc/chef/role-manager.json

