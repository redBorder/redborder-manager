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

source $RBBIN/rb_manager_functions.sh
source /etc/profile

[ -f /etc/redborder/manager.conf ] && source /etc/redborder/manager.conf
[ "x$DOMAIN" == "x" ] && DOMAIN="redborder.cluster"

NAME="rb_upload_cookbooks"
LOCKFILE="/var/lock/$NAME.lock"
S3CFGFILE="/root/.s3cfg-rbookshelf"
  
function check_daemon() {
  local service=$1
  if [ -f /etc/init.d/$service ]; then
    /etc/init.d/$service status &>/dev/null
    if [ $? -ne 0 ]; then
      echo "$service must be running. Exiting!"
      rm -f $LOCKFILE
      exit 1
    fi
  else
    echo "$service doesn't exist. Exiting!"
    rm -f $LOCKFILE
    exit 1
  fi
}

function check_files() {
  local file=$1
  if [ "x$file" != "x" ]; then
    if [ ! -f $file ]; then
      echo "File $file doesn't exist. Exiting!"
      rm -f $LOCKFILE
      exit 1
    fi
  else
    echo "File $2 not found. Exiting!"
    rm -f $LOCKFILE
    exit 1
  fi
}

cmd=""
quiet=0

if [ -f $LOCKFILE ]; then
  PIDLOCK=$(<$LOCKFILE)
  if [ "x$PIDLOCK" != "x" -a -f /proc/$PIDLOCK/cmdline ]; then
    strings /proc/$PIDLOCK/cmdline | grep -q $NAME
    if [ $? -ne 0 ]; then
      echo "ERROR: other program with same lock. Deleting lock file ($LOCKFILE)"
      rm -f $LOCKFILE
    fi
  else
    rm -f $LOCKFILE
  fi
fi

if [ -f $LOCKFILE ]; then
  echo "$NAME locked at $LOCKFILE (pid: $PIDLOCK)"
  files=$(find /var/opt/chef-server/bookshelf/data/bookshelf/ -type f -name 'organization-*' 2>/dev/null | wc -l)
  if [ "x$files" != "x0" ]; then
    echo "INFO: $files cookbooks files rest to upload"
  fi
else
  echo $$ > /var/lock/$NAME.lock

  if [ "x$1" == "x-i" ]; then
    S3CMD=$(which s3cmd 2>/dev/null)
    COUNTER_FAILS=0
    
    [ "x$S3CMD" == "x" ] && S3CMD="s3cmd"
    
    check_files "$S3CMD" "s3cmd"
    check_files "$S3CFGFILE"
    
    #Checking data
    s3host=$(grep host_base $S3CFGFILE  |sed 's/.*= //')
    if [ "x$s3host" == "xs3.${DOMAIN}" ]; then
      s3bucket="rbookshelf"
    else
      check_files /var/www/rb-rails/config/aws.yml
      s3bucket=$(cat /var/www/rb-rails/config/aws.yml |grep bucket|head -n 1|sed 's/.*: //')
    fi
    
    TMPDIR="/tmp/rb_upload_bookshelf_$$.tmp"
    mkdir -p $TMPDIR
  
    files=$(find /var/opt/chef-server/bookshelf/data/bookshelf/ -type f -name 'organization-*' 2>/dev/null)
  
    if [ "x$files" != "x" ]; then
      mkdir -p /var/opt/chef-server/bookshelf/data/bookshelf.bak

      for n in $files; do
        file_name=$(basename $n)
        remote_name=$(echo $file_name | sed 's/^[^%]*%2F//');
        organization_name=$(echo $file_name | sed 's/%2F.*$//');
        if [ $COUNTER_FAILS -lt 5 ]; then
          echo -n "Copying $remote_name: "
      
          mkdir -p $TMPDIR/$organization_name
          rm -f $TMPDIR/$organization_name/$remote_name
          $RBBIN/rb_md5_file.py $n>$TMPDIR/$organization_name/$remote_name
      
          s3cmd -c $S3CFGFILE put $TMPDIR/$organization_name/$remote_name s3://${s3bucket}/$organization_name/ &>/dev/null
          if [ $? -eq 0 ]; then
            e_ok
            n2=$(echo $n | sed 's|/var/opt/chef-server/bookshelf/data/bookshelf/|/var/opt/chef-server/bookshelf/data/bookshelf.bak/|')
            mkdir -p $(dirname $n2)
            mv $n $n2
            #rm -f $n
          else
            e_fail
            COUNTER_FAILS=$(( $COUNTER_FAILS +1 ))
          fi
          rm -f $TMPDIR/$organization_name/$remote_name
        else
          echo "Maximum number of failures reached. Ignored: $n"
        fi
      done
    else
      rm -rf /var/opt/chef-server/bookshelf/data/bookshelf/*
    fi
    rm -rf $TMPDIR
  
  else
    [ "x$1" == "x-q" ] && shift && quiet=1
    if [ "x$1" == "x-f" ]; then 
      shift
      e_title "Deleting opscode_chef cookbook database "
      echo "delete from cookbook_version_checksums; delete from checksums;" | rb_psql opscode_chef
    fi
    [ "x$1" == "x-q" ] && shift && quiet=1
    [ $quiet -eq 0 ] && cmd="$cmd -V"
    
    for n in $(ls -d /var/chef/cookbooks/*$1* 2>/dev/null); do
      name=$(basename $n)
      if [ "x$name" != "xchefignore" ]; then
        e_title $name
        knife cookbook upload $name $cmd
      fi
    done
  fi
fi
    
rm -f $LOCKFILE
