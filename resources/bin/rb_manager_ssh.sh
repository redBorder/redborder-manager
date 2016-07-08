# Author: Pablo Nebrera Herrera
# Connect to other manager

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

RBDIR=${RBDIR-/opt/rb}
RSA="${RBDIR}/var/www/rb-rails/config/rsa"
RET=0

[ "x$(whoami)" == "xopscode-pgsql" ] && RSA="/var/opt/chef-server/postgresql/rsa"

source /usr/lib/redborder/bin/rb_manager_functions.sh
[ -f /etc/redborder/manager.conf ] && source /etc/redborder/manager.conf
[ "x$DOMAIN" == "x" ] && DOMAIN="redborder.cluster"

if [ "x$*" == "x" ]; then
  echo "$0 node|all [ \"cmd1\" \"cmd2\" ... ]"
elif [ "x$1" != "xall"  ]; then
  ALLREMOTENODES=$(echo $1 | awk '{print $1}')
  shift
  for REMOTENODES in $(echo $ALLREMOTENODES | tr ',' ' '); do
    REMOTENODES=$(echo $REMOTENODES | sed 's/:.*//g')
    isnum $REMOTENODES
    [ $? -eq 0 ] && REMOTENODES="rbmanager-$REMOTENODES"

    if [ "x$REMOTENODES" == "x$(hostname -s)" ]; then
      bash -c "$*"
    else
      grep rbmanager- /etc/hosts | grep -q " ${REMOTENODES} "
      RET1=$?
      if [ $RET1 -ne 0 ]; then 
          grep rbmanager- /etc/hosts | grep -q " ${REMOTENODES}$"
          RET1=$?
      fi
      grep .${DOMAIN} /etc/hosts | egrep -q " ${REMOTENODES}$| ${REMOTENODES} "
      RET2=$?
      echo "${REMOTENODES}" |grep -q "\.${DOMAIN}$"
      RET3=$?
      valid_ip ${REMOTENODES}
      RET4=$?
      if [ $RET1 -eq 0 -o $RET2 -eq 0 -o $RET3 -eq 0 -o $RET4 -eq 0 ]; then
        ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o StrictHostKeyChecking=no -i ${RSA} root@$REMOTENODES $*
        RET=$?
      else
        #it could be a valid cluster service 
        if [ -f /etc/redborder/mode/${REMOTENODES} -o -f /etc/redborder/role-${REMOTENODES}.list ]; then
          allnodes=$(/usr/lib/redborder/bin/rb_nodes_with_service.rb ${REMOTENODES})
          if [ "x$allnodes" != "x" ]; then
            allnodescount=$(echo $allnodes | wc -w)
            if [ "x$*" == "x" -a  $allnodescount -gt 1 ]; then
              echo "There are $allnodescount with this service enabled: "
              pcount=1
              for p in $allnodes; do 
                [ $pcount -lt 10 ] && echo -n " "
                echo "      $pcount.- $p"
                pcount=$(($pcount +1))
              done
              echo -n "Choose one node: "
              read indexp
              echo
              if [[ $indexp == ?(-)+([0-9]) ]]; then
                allnodesarray=($allnodes)
                REMOTENODES=${allnodesarray[$(($indexp-1))]}
              else
                REMOTENODES=$(echo $indexp|awk '{print $1}')
              fi
            else
              REMOTENODES=$allnodes
            fi

            if [ "x$REMOTENODES" != "x" ]; then
              allnodescount=$(echo $REMOTENODES|wc -w)
              for pp in $REMOTENODES; do 
                if [ $allnodescount -gt 1 ]; then
                  [ "x$BOOTUP" != "xnone" ] && set_color cyan
                  echo "##############################################" 
                  echo -n "#  Node: "
                  [ "x$BOOTUP" != "xnone" ] && set_color blue 
                  echo "$pp"
                  [ "x$BOOTUP" != "xnone" ] && set_color cyan
                  echo "##############################################" 
                  [ "x$BOOTUP" != "xnone" ] && set_color norm
                fi
        
                ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o StrictHostKeyChecking=no -i ${RSA} root@$pp $*
                RET=$?
              done
            fi
          else
            echo "ERROR: There is no managers with this service enabled" >/dev/stderr
            RET=1
          fi
        else
          echo "ERROR: Unknown manager node name (${REMOTENODES})" >/dev/stderr
          RET=1
        fi
      fi
    fi
  done
else
  if [ "x$2" != "x" ]; then
    shift
    REMOTENODES=$(/usr/lib/redborder/bin/rb_get_managers.rb -c 2>/dev/null| sed 's/ $//')
    if [ $? -eq 0 -a "x$REMOTENODES" != "x" ]; then
      for n in $REMOTENODES; do 
        [ "x$BOOTUP" != "xnone" ] && set_color cyan
        echo "##############################################" 
        echo -n "#  Node: "
        [ "x$BOOTUP" != "xnone" ] && set_color blue
        echo "$n"
        [ "x$BOOTUP" != "xnone" ] && set_color cyan
        echo "##############################################" 
        [ "x$BOOTUP" != "xnone" ] && set_color norm
        ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o StrictHostKeyChecking=no -i ${RSA} root@$n $*
        [ $RET -eq 0 ] && RET=$?
      done
    else
      echo "ERROR: cannot get manager nodes" >/dev/stderr
    fi
  else
    echo "ERROR: you must specify any command to execute on all cluster" >/dev/stderr
  fi
fi

exit $RET
