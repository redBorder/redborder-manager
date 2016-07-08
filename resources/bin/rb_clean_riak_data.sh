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

source /usr/lib/redborder/bin/rb_manager_functions.sh
alldata=0
force=0

while getopts "haf" name
do
  case $name in
    h) usage;;
    a) alldata=1;;
    f) force=1;;
  esac
done

service riak status &>/dev/null
if [ $? -eq 0 ]; then
    echo "ERROR: to delete local riak data the daemon must be stopped before"
else
    if [ $force -eq 0 ]; then
        echo -n "Are you sure you want to delete riak local data? (y/N) "
        read VAR
    else
        VAR="y"
    fi

    if [ "x$VAR" == "xy" -o "x$VAR" == "xY" ]; then
        if [ $alldata -eq 1 ]; then
           for n in `grep data_root /etc/riak/app.config | sed 's/.*{[ ]*data_root[, ]*"//'|sed 's/"[ ]*}.*$//'`; do 
               if [ -d $n ]; then
                   echo -n "Deleting local s3 data ($n) "
                   rm -rf $n/*; 
                   print_result $?
               fi
           done
           for n in `grep anti_entropy_data_dir /etc/riak/app.config | sed 's/.*{[ ]*anti_entropy_data_dir[, ]*"//'|sed 's/"[ ]*}.*$//'`; do 
               if [ -d $n ]; then
                   echo -n "Deleting local s3 anti entropy data "
                   rm -rf $n/*; 
                   print_result $?
               fi
           done
           echo -n "Deleting local s3 data "
           rm -rf /var/lib/riak/anti_entropy/*
           print_result $?
        fi
        for n in `grep ring_state_dir /etc/riak/app.config | sed 's/.*{[ ]*ring_state_dir[, ]*"//'|sed 's/"[ ]*}.*$//'`; do 
            if [ -d $n ]; then
                echo -n "Deleting local ring s3 data ($n) "
                rm -rf $n/*; 
                print_result $?
            fi
        done
    fi
fi

