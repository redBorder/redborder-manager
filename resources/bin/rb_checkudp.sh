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

HOST="$1"
PORT="$2"
RET=1

if [ "x$HOST" != "x" -a "x$PORT" != "x" ]; then
    RET=0
    ping -c 1 $HOST &>/dev/null
    if [ $? -ne 0 ]; then
        sleep 1
        ping -c 1 $HOST &>/dev/null
        if [ $? -ne 0 ]; then
            RET=1
        fi
    fi

    if [ $RET -eq 0 ]; then
        nc -znu -w 3 $HOST $PORT &>/dev/null
        RET=$?
    fi
else
    echo "Usage: $0 host port"
fi

exit $RET
