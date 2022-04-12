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

function usage(){
  echo "$0 [ -h ] [ -e ]"
  echo "  -h      print this help"
  echo "  -e      send email to administrator"
  exit 0
}

email=0

while getopts "he" opt ; do
  case $opt in
    h) usage;;
    e) email=1;;
  esac
done

source /etc/profile
 
lictime=$(/usr/lib/redborder/scripts/rb_read_license.rb | grep expire_time|awk '{print $2}')

if [ "x$lictime" != x ]; then
  currenttime=$(date +%s)

  [ $email -eq 0 ] && echo "Current time: $(date -d @${currenttime})   (unix: ${currenttime})"
  [ $email -eq 0 ] && echo "License time: $(date -d @${lictime})   (unix: ${lictime})"

  if [ ${lictime} -lt ${currenttime} ]; then
    msg="The license for $(hostname -f) has expired $(date -d @${lictime})"
  else
    msg="The license for $(hostname -f) is about to expire $(date -d @${lictime})"
  fi

  lictime=$(( $lictime - 7 * 24 * 3600))

  [ $email -eq 0 ] && echo "Limit time:   $(date -d @${lictime})   (unix: ${lictime})"

  if [ ${lictime} -lt ${currenttime} ]; then
    if [ $email -eq 0 ]; then
      echo "INFO: $msg"
    else
      pushd /var/www/rb-rails &>/dev/null
      bundle exec rake redBorder:admin_email["License expiration for $(hostname -f)","$msg"]
      popd &>/dev/null
    fi
  fi
fi
  
