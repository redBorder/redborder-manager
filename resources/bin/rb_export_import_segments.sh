#!/bin/bash

# Author: David Vanhoucke
# Script to export/import s3 segments and its metadata

RES_COL=100
MOVE_TO_COL="printf \\033[${RES_COL}G"

function set_color() {
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

e_ok() {
        $MOVE_TO_COL
        echo -n " ["
        set_color green
        echo -n $"OK"
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 0
}

e_fail() {
        $MOVE_TO_COL
        echo -n " ["
        set_color red
        echo -n $"FAILED"
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 1
}

function print_result(){
    if [ "x$1" == "x0" ]; then
        e_ok
    else
        e_fail
    fi
}

function usage(){
  echo "$0 [-h][-f filename][-r][-s][-t <path>] [-x start date] [-y stop date]"
  echo "    default action is export the segments from the local s3 database (s3://bucket/)"
  echo "    start and stop date should have following format : 2024-08-18T22:00:00.000Z"
  echo ""
  echo ""
  echo "    -h: print this help"
  echo "    -r: import backup file (-f is mandatory)"
  echo "    -f: import from a specified file."
  echo "    -s: import/export from remote s3"
  echo "    -t: import/export from/to a file path instead of a bucket"
  echo "    -p: change namespace when doing export. Example: NS-4037448272"
  echo "    -q: remove namespace when doing export"
  echo "    -d: change datasource when making export. Example: rb_flow_NS-4037448272 (use this option if you know what you do)"
  echo "    -b: restore full druid database / is deleting current druid database in postgresql!! you loose current druid data in postgresql!!"
  echo "    -c <file>: use this file as s3 config file instead of /root/.s3cfg_initial"
  echo "    -n: do not ask. just do it"
  echo "    -g: regex grep filter to export only those files that match the filter"
  echo "    -j: add this to s3 string"
  echo "    -k: overwrite remote bucket"
  echo "    -v: be verbose (debug)"
  echo "    -e: enable all imported segments"
  echo "    -x: start date of the segments to import/export"
  echo "    -y: stop date of the segments to import/export"
  exit 1
}

function print_system() {
  if [ -f $1 ]; then
    dirfilename=$(dirname $1)
    echo "Free space: $(df -h $dirfilename|grep / |awk '{print $5}') ($(df -h $dirfilename|grep / |awk '{print $4}'))  load average: $(uptime|sed 's/.*load average: //')"
  fi
}

source /etc/profile

enableallsegments=0
import=0
filename=""
debug=0
s3config=""
backups3=0
backuppath=""
filter="."
appendpath=""
ask=1
datasource=""
namespace=""
removenamespace=0
restoredb=0

currenttime="$(date +"%Y%m%d%H%M")"
tmpdir="/tmp/segment.tmp-${currenttime}.$$"

renice -n 19 $$ &>/dev/null

[ -f /root/.s3cfg_initial ] && s3config="/root/.s3cfg_initial"

while getopts "hrf:d:snbg:vk:p:t:j:qex:y:" name
do
  case $name in
    h) usage;;
    r) import=1;;
    f) filename="$OPTARG";;
    c) s3config="$OPTARG";;
    g) filter="$OPTARG";;
    j) appendpath="/$OPTARG";;
    d) datasource="$OPTARG";;
    p) namespace="$OPTARG";;
    q) removenamespace=1;;
    e) enableallsegments=1;;
    v) debug=1;;
    s) backups3=1;;
    t) backuppath="$OPTARG";;
    n) ask=0;;
    b) restoredb=1;;
    k) backupbucket="$OPTARG";;
    x) startdate="$OPTARG";;
    y) stopdate="$OPTARG";;
  esac
done

if [ ! -f /etc/druid/_common/common.runtime.properties ];then
  echo "/etc/druid/_common/common.runtime.properties file is missing. This file is needed to connect to the database of druid, cannot continue..."
  exit 1
fi

# get connection data
s3currentbucket=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null |grep "^druid.storage.bucket="|tr '=' ' '|awk '{print $2}')
[ "x$s3currentbucket" == "x" ] && s3currentbucket="bucket"
s3basekey=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null |grep "^druid.storage.baseKey="|tr '=' ' '|awk '{print $2}')
[ "x${s3basekey}" == "x" ] && s3basekey="rbdata"
druid_db_uri=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null |grep "^druid.metadata.storage.connector.connectURI="|tr '=' ' '|awk '{print $2}')
druid_db_pass=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null |grep "^druid.metadata.storage.connector.password="|tr '=' ' '|awk '{print $2}')

# checking flags
if [ $backups3 -eq 1 -a ! -f $s3config ]; then
  echo "ERROR: The remote s3 for backup has not been specified"
  exit 1
fi

if [ $backups3 -eq 1 -a "x$backuppath" != "x" ]; then
  echo "Option -s and -t <path> are incompatibles"
  exit 1
fi

# we are going to import the segments in s3
if [ $import -eq 1 ]; then
  confirm=0
  if [ $backups3 -eq 0 -a "x$backuppath" == "x"  ]; then
    if [ "x$filename" == "x" ]; then
      echo "ERROR: The option -f is mandatory to import segments"
    elif [ -d $filename ]; then
      echo "ERROR: The selected file is a directory"
    elif [ ! -f $filename ]; then
      echo "ERROR: The selected file $filename doesn't exist"
    else
      file $filename | grep -q "gzip compressed data"
      if [ $? -eq 0 ]; then
        set_color red
        echo -n "WARNING: "
        set_color norm
        echo -n "Restoring backup from "
        set_color blue
        echo -n "$filename"
        set_color norm
        echo " file"
        print_system $filename
        if [ $ask -eq 1 ]; then
          echo -n "Would you like to continue? (y/N) "
          read VAR
          if [ "x$VAR" == "xy" -o "x$VAR" == "xY" ]; then
            confirm=1
          else
            confirm=0
          fi
        else
          confirm=1
        fi
      else
        echo "ERROR: The selected file $filename is not a backup segment file"
      fi
    fi

    if [ $confirm -eq 1 ]; then
      if [ -f $tmpdir -o -d $tmpdir ]; then
        echo "ERROR: The temporal dir $tmpdir already exist!!"
      else
        mkdir -p $tmpdir

        echo -n "Uncompressing file $filename "
        nice -n 19 ionice -c2 -n7 tar xzf $filename -C $tmpdir
        RET1=$?
        print_result $RET1

        if [ $? -eq $RET1 ]; then
          if [ ! -f $tmpdir/conf/db-druid-dump.psql ]; then
            echo "ERROR: Postgresql database segments file not found!"
          elif [ ! -d $tmpdir/segments ]; then
            echo "ERROR: Segments directory not found!"
          else
            FILES=$(find $tmpdir/segments/ -type d | head -n 5 | wc -l)
            if [ "x$FILES" != "x5" ]; then
              echo "ERROR: There is no segments on this backup"
            else
              if [ $restoredb -eq 1 ]; then

                PGHOSTNAME="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
                PGPORT="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"

                echo -n "Deleting previous segments database !!"
                echo "delete from druid_segments;" | PGPASSWORD="$druid_db_pass" psql -h $PGHOSTNAME -p $PGPORT -U druid -d druid &>/dev/null
                RET2=$?
                print_result $RET2

                echo -n "Restoring segments database"
                PGPASSWORD="$druid_db_pass" pg_restore -t druid_segments -h $PGHOSTNAME -p $PGPORT -U druid -d druid --data-only -F c $tmpdir/conf/db-druid-dump.psql
                RET3=$?
                print_result $RET3
              else
                RET2=0
                RET3=0
              fi

              if [ $RET2 -eq 0 -a $RET3 -eq 0 ]; then
                RET4=0
                for n in $(ls $tmpdir/segments); do
                  echo -n "Syncing $n to s3 "
                  timestamp=$(echo "$n" | awk -F '/' '{print $3}')
                  tocopy=1
                  if [[ -n $startdate && "$timestamp" < "$startdate" ]]; then
                      tocopy=0
                  fi
                  if [[ -n $stopdate && "$timestamp" > "$stopdate" ]]; then
                      tocopy=0
                  fi

                  if [ $tocopy -eq 1 -a $RET4 -eq 0 ]; then
                    if [ $debug -eq 1 ]; then
                      nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync $tmpdir/segments/$n s3://$s3currentbucket/${s3basekey}/
                      RET4=$?
                    else
                      nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync $tmpdir/segments/$n s3://$s3currentbucket/${s3basekey}/ &>/dev/null
                      RET4=$?
                    fi
                    print_result $RET4
                  else
                    echo " - ignored"
                    print_result 1
                  fi
                done
                if [ $RET4 -eq 0 ]; then
                  echo -n "Backup $filename restored successfully"
                  print_result 0
                fi
                if [ $restoredb -ne 1 ]; then
                  RET=0
                  echo -n "update druid segments table with the metadata"

                  for module in $(ls $tmpdir/segments); do
                      for rule in $(find $tmpdir/segments/$module/*/*/*/ -name "rule.json"); do
                          rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -f $rule
                          RET=$? || $RET
                      done
                  done

                  print_result $RET
                fi
              fi
            fi
          fi
        fi
        echo -n "removing temporary directory"
        rm -rf $tmpdir
        print_result $?
      fi
    fi
  elif [ "x$backupbucket" != "x" -o "x$backuppath" != "x" ]; then
    set_color red
    echo -n "WARNING: "
    set_color norm
    echo -n "Restoring backup from "
    set_color blue
    if [ "x$backuppath" != "x" ]; then
      echo -n "file://$backuppath"
    else
      echo -n "s3://$backupbucket"
    fi
    set_color norm
    echo
    if [ $ask -eq 1 ]; then
      echo -n "Would you like to continue? (y/N) "
      read VAR
      if [ "x$VAR" == "xy" -o "x$VAR" == "xY" ]; then
        confirm=1
      else
        confirm=0
      fi
    fi

    if [ $confirm -eq 1 ]; then
      if [ -f $tmpdir -o -d $tmpdir ]; then
        echo "ERROR: The temporal dir $tmpdir already exist!!"
      else
        mkdir -p $tmpdir
        pushd $tmpdir &>/dev/null

        echo -n "Getting local S3 md5 files info: "
        declare -A localfile
        eval "localfile=($(nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd ls -c $s3config --list-md5 --recursive s3://$s3currentbucket/${s3basekey}${appendpath}|sed "s|s3://$s3currentbucket/||" | awk '{printf("[\"%s\"]=\"%s\" ", $5, $4)}'))"
        print_result $?

        if [ "x$backuppath" != "x" ]; then
          echo -n "Getting md5 files info: "
          declare -A remotefile
          eval "remotefile=($(nice -n 19 ionice -c2 -n7 find $backuppath -type f -exec md5sum {} \; | sed "s|$backuppath||" |sed 's| /| |' | egrep "$filter" | grep -v "rule.json$" | sed 's|segments/last/||' | awk '{printf("[\"%s\"]=\"%s\" ", $2, $1)}'))"
          print_result $?
        else
          echo -n "Getting remote S3 md5 files info: "
          declare -A remotefile
          eval "remotefile=($(nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd ls -c $s3config --list-md5 --recursive s3://$backupbucket/segments/last/rbdata${appendpath} | sed "s|s3://$backupbucket/segments/last/||" | egrep "$filter" | grep -v "rule.json$" |awk '{printf("[\"%s\"]=\"%s\" ", $5, $4)}'))"
          print_result $?
        fi

        filescopy=""

        for n in $(echo ${!remotefile[@]}|tr ' ' '\n' | sort -r); do
          localn="$n"
          if [ "x$removenamespace" == "x0" ]; then
            if [ "x$namespace" != "x" ]; then
              currentds=$(echo $n | sed "s/${s3basekey}\///" | sed 's|/.*||')
              if [ "x$currentds" != "x" ]; then
                temp=$(echo $currentds | grep -oE "[^_]+$" | cut -d "/" -f 1)
                datasource=$(echo $currentds | sed "s/\(rb.*\)\($temp\).*/\1$namespace/")
                localn=$(echo $n |sed "s/\/${currentds}\//\/${datasource}\//g")
              else
                datasource=""
              fi
            elif [ "x$datasource" != "x" ]; then
              currentds=$(echo $n | sed "s/${s3basekey}\///" | sed 's|/.*||')
              if [ "x$currentds" != "x" ]; then
                localn=$(echo $n |sed "s/\/${currentds}\//\/${datasource}\//g")
              fi
            fi
          else
            currentds=$(echo $n | sed "s/${s3basekey}\///" | sed 's|/.*||')
            if [ "x$currentds" != "x" ]; then
              temp=$(echo $currentds | grep -oE "[^_]+$" | cut -d "/" -f 1)
              datasource=$(echo $currentds | sed "s/\(rb.*\)\($temp\).*/\1$namespace/")
              localn=$(echo $n |sed "s/\/${currentds}\//\/${datasource}\//g")
            else
              datasource=""
            fi
          fi
          if [ "x${localfile[$localn]}" == "x" -o "x${remotefile[$n]}" != "x${localfile[$localn]}" ]; then
            f=$(basename $n)
            rm -f $f
            if [ "x$backuppath" != "x" ]; then
              echo -n "Getting file://$backuppath/segments/last/$n: "
              nice -n 19 ionice -c2 -n7 rsync -a $backuppath/segments/last/$n . &>/dev/null
            else
              echo -n "Getting s3://$backupbucket/segments/last/$n: "
              nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync s3://$backupbucket/segments/last/$n . &>/dev/null
            fi
            if [ -f $f ]; then
              set_color green
              echo OK
              set_color norm
              if [ "x$f" == "xdescriptor.json" -a "x$datasource" != "x" ]; then
                current_datasource=$(cat $f |jq .dataSource|sed 's/"//g')
                sed -i "s/\"${current_datasource}/\"${datasource}/g" $f
              fi
              echo -n "Copying s3://$s3currentbucket/${localn}: "
              nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync $f s3://$s3currentbucket/${localn} &>/dev/null
              if [ $? -eq 0 ]; then
                set_color green
                echo OK
                if [ "x$f" == "xdescriptor.json" ]; then
                  rm -f $f
                  f="rule.json"
                  set_color norm
                  if [ "x$backuppath" != "x" ]; then
                    echo -n "Getting file://$backuppath/segments/last/$(dirname $n)/$f: "
                    nice -n 19 ionice -c2 -n7 rsync -a $backuppath/segments/last/$(dirname $n)/$f . &>/dev/null
                  else
                    echo -n "Getting s3://$backupbucket/segments/last/$(dirname $n)/$f: "
                    nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync s3://$backupbucket/segments/last/$(dirname $n)/$f . &>/dev/null
                  fi
                  if [ -f $f ]; then
                    set_color green
                    echo OK
                    set_color norm
                    echo -n "Inserting rule for $(dirname $localn)/$f: "
                    identifier=$(cat $f | jq .id|sed 's/"//g')
                    [ "x$enableallsegments" == "x1" ] && sed -i 's/"used": "f",/"used": "t",/' $f
                    if [ "x$identifier" != "x" -a "x$identifier" != "xnull" ]; then
                      #changed bucket to current bucket
                      sed -i "s/\"bucket\":.*/\"bucket\": \"$s3currentbucket\",/" $f
                      if [ "x$datasource" != "x" ]; then
                        rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -d "$datasource" -f $f > ${f}.3
                        rm -f ${f}
                        mv ${f}.3 ${f}
                        identifier=$(cat $f | jq .id|sed 's/"//g')
                      else
                        rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -f $f &>/dev/null
                      fi
                      rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -i $identifier > ${f}.2
                      fmd5=$(md5sum $f |awk '{print $1}')
                      f2md5=$(md5sum ${f}.2 |awk '{print $1}')
                      if [ "x$fmd5" == "x$f2md5" ]; then
                        set_color green
                        print_result 0
                      else
                        set_color red
                        print_result 1
                      fi
                    else
                      set_color red
                      echo FAILED unknown identifier
                    fi
                  else
                    set_color red
                    echo FAILED s3://$backupbucket
                  fi
                fi
              else
                set_color red
                echo FAILED s3://$s3currentbucket
              fi
            else
              set_color red
              echo FAILED s3://$backupbucket
            fi
            set_color norm
            rm -f $f
          fi
        done

        if [ $restoredb -eq 1 ]; then
          if [ "x$backuppath" != "x" ]; then
            remotemetadata="$backuppath/segments/druid-metadata/$(ls $backuppath/segments/druid-metadata/|sort | tail -n 1 |awk '{print $1}')"
          else
            remotemetadata=$(/usr/bin/python /usr/bin/s3cmd -c $s3config ls s3://$backupbucket/segments/druid-metadata/|tail -n 1 |awk '{print $4}')
          fi
          if [ "x$remotemetadata" != "x" ]; then
            echo $remotemetadata | grep -q  "^s3://$backupbucket/segments/druid-metadata/"
            if [ $? -eq 0 ]; then
              filename=$(basename $remotemetadata)
              if [ "x$backuppath" != "x" ]; then
                echo -n "Downloading $filename "
                rsync -a $remotemetadata .
                print_result $?
              else
                echo -n "Downloading $filename "
                /usr/bin/python /usr/bin/s3cmd -c $s3config sync $remotemetadata . &>/dev/null
                print_result $?
              fi

              if [ -f $filename ]; then
                source /etc/druid/config.sh

                PGHOSTNAME="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
                PGPORT="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"

                echo -n "Deleting previous segments database "
                echo "delete from druid_segments;" | PGPASSWORD="$druid_db_pass" psql -h $PGHOSTNAME -p $PGPORT -U druid -d druid &>/dev/null
                RET2=$?
                print_result $RET2

                echo -n "Restoring segments database"
                PGPASSWORD="$druid_db_pass" pg_restore -t druid_segments -h $PGHOSTNAME -p $PGPORT -U druid -d druid --data-only -F c $tmpdir/$filename
                RET3=$?
                print_result $RET3
              else
                echo "File $filename not found!!"
                print_result 1
              fi
            fi
          fi
        fi
        popd &>/dev/null
        rm -rf $tmpdir
      fi
    fi
  fi
else
  if [ "x$filename" == "x" ]; then
     filename="/var/backup/segments/segment-${currenttime}.tar"
     mkdir -p /var/backup/segments/
  fi

  confirm=1
  if [ -d $filename ]; then
    echo "ERROR: The selected file is a directory"
  elif [ -f $filename ]; then
    print_system $filename
    if [ $ask -eq 1 ]; then
      echo -n "The file $filename exist. Would you like to overwrite it? (y/N) "
      read VAR
      if [ "x$VAR" == "xy" -o "x$VAR" == "xY" ]; then
        confirm=1
      else
        confirm=0
      fi
    else
      confirm=1
    fi
  else
    if [ "x$backuppath" != "x" ]; then
      echo -n "The backup will be created in "
      set_color blue
      echo -n "$backuppath"
      set_color norm
      echo " directory"
    elif [ $backups3 -eq 0 ]; then
      echo -n "The backup will be created in "
      set_color blue
      echo -n "$filename"
      set_color norm
      echo " file"
    else
      echo -n "The backup will be created in "
      set_color blue
      echo "s3://$backupbucket"
      set_color norm
    fi
    print_system $filename
    if [ $ask -eq 1 ]; then
      echo -n "Would you like to continue? (Y/n) "
      read VAR
      [ "x$VAR" == "xn" -o "x$VAR" == "xN" ] && confirm=0
    else
      confirm=1
    fi
  fi

  if [ $confirm -eq 1 ]; then
    rm -f $filename

    if [ -f $tmpdir -o -d $tmpdir ]; then
      echo "ERROR: The temporal dir $tmpdir already exist!!"
    else
      mkdir -p $tmpdir/conf
      echo -n "Backup full druid database db-druid-dump.psql "

      PGHOSTNAME="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
      PGPORT="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"

      PGPASSWORD="$druid_db_pass" pg_dump -U druid -h $PGHOSTNAME -p $PGPORT -F c -b -f $tmpdir/conf/db-druid-dump.psql
      RET1=$?
      print_result $RET1

      count=1
      RET2=1

      if [ $backups3 -eq 0 -a "x$backuppath" == "x" ]; then
        mkdir $tmpdir/segments
        pushd $tmpdir/segments &>/dev/null

        echo -n "Getting local files info: "
        declare -A localfile
        eval "localfile=($(nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd ls -c $s3config --list-md5 --recursive s3://${s3currentbucket}/${s3basekey}${appendpath}|grep -v '\$'|sed "s|s3://${s3currentbucket}/||" | egrep "$filter" | awk '{printf("[\"%s\"]=\"%s\" ", $5, $4)}'))"
        print_result $?

        for n in $(echo ${!localfile[@]}|tr ' ' '\n' | sort -r|sed "s/^${s3basekey}\///"); do
          timestamp=$(echo "$n" | awk -F '/' '{print $3}')
          tocopy=1

          if [[ $tocopy -eq 1 ]]; then
            echo -n "Copying $n: "
            mkdir -p ./$(dirname $n)
            nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config get s3://$s3currentbucket/${s3basekey}/$n $n &>/dev/null
            if [ $? -eq 0 ]; then
              set_color green
              echo OK
            else
              set_color red
              echo FAILED
            fi
            set_color norm
          else
            if [ $debug -eq 1 ]; then
              echo "skipping $n"
            fi
          fi
        done

        RET2=0
        for n in $(find $tmpdir/segments -name descriptor.json); do
          echo -n "Creating $(dirname $n)/rule.json: "
          if [ -s $n ]; then
            descriptorid=$(cat $n | jq .identifier|sed 's/"//g')
            if [ "x$descriptorid" != "x" ]; then
              rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -i "$descriptorid" > "$(dirname $n)/rule.json"
              if [ -s $f ]; then
                set_color green
                echo OK
              else
                set_color red
                echo FAILED
              fi
            else
              set_color red
              echo FAILED
            fi
          else
            set_color red
            echo FAILED
          fi
          set_color norm
        done
        popd &>/dev/null

        echo -n "Compressing data into $(basename $filename)"
        nice -n 19 ionice -c2 -n7 tar czf $filename -C $tmpdir .
        print_result $?

        echo -n "Backup file $filename saved"
        if [ $RET1 -eq 0 -a $RET2 -eq 0 ]; then
          print_result 0
        else
          echo -n " (with errors) "
          print_result 1
        fi
      elif [ "x$backupbucket" != "x" -o "x$backuppath" != "x" ]; then
        #overstr=$(date '+%Y-%m-%dT%H:%M:%S')
        overstr=$(date +"%Y%m%d%H%M")

        echo -n "Uploading db-druid-dump.psql.$overstr: "
        if [ "x$backuppath" != "x" ]; then
          mkdir -p $backuppath/segments/druid-metadata/
          nice -n 19 ionice -c2 -n7 rsync -a $tmpdir/conf/db-druid-dump.psql $backuppath/segments/druid-metadata/db-druid-dump.psql.$overstr
          print_result $?
        else
          nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd sync -c $s3config $tmpdir/conf/db-druid-dump.psql s3://$backupbucket/segments/druid-metadata/db-druid-dump.psql.$overstr &>/dev/null
          print_result $?
        fi

        echo -n "Getting local S3 md5 files info: "
        declare -A localfile
        eval "localfile=($(nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd ls -c $s3config --list-md5 --recursive s3://${s3currentbucket}/${s3basekey}${appendpath}|grep -v '\$'|sed "s|s3://${s3currentbucket}/||" | egrep "$filter" | awk '{printf("[\"%s\"]=\"%s\" ", $5, $4)}'))"
        print_result $?

        if [ "x$backuppath" != "x" ]; then
          echo -n "Getting md5 files info: "
          declare -A remotefile
          eval "remotefile=($(nice -n 19 ionice -c2 -n7 find $backuppath -type f -exec md5sum {} \; | sed "s|$backuppath||" |sed 's| /| |' | egrep "$filter" | grep -v "rule.json$" | sed 's|segments/last/||' | awk '{printf("[\"%s\"]=\"%s\" ", $2, $1)}'))"
          print_result $?
        else
          echo -n "Getting remote S3 md5 files info: "
          declare -A remotefile
          eval "remotefile=($(nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd ls -c $s3config --list-md5 --recursive s3://$backupbucket/segments/last/rbdata${appendpath} | grep -v '\$' | grep -v "rule.json$" | sed "s|s3://$backupbucket/segments/last/||" | egrep "$filter" | awk '{printf("[\"%s\"]=\"%s\" ", $5, $4)}'))"
          print_result $?
        fi

        for n in $(echo ${!localfile[@]}|tr ' ' '\n' | sort -r); do
          timestamp=$(echo "$n" | awk -F '/' '{print $3}')
          if [[ -n $startdate && "$timestamp" < "$startdate" ]]; then
	    echo "Skipping $n"
            continue
          fi
          if [[ -n $stopdate && "$timestamp" > "$stopdate" ]]; then
	    echo "Skipping $n"
            continue
          fi

          if [ "x${remotefile[$n]}" == "x" ]; then
            f=$(basename $n)
            rm -f $f
            echo -n "Copying $n: "
            nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync s3://${s3currentbucket}/$n $f &>/dev/null
            if [ -f $f ]; then
              if [ "x$backuppath" != "x" ]; then
                mkdir -p $backuppath/segments/last/$(dirname $n)
                nice -n 19 ionice -c2 -n7 mv $f $backuppath/segments/last/$n &>/dev/null
                vret=$?
              else
                nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync $f s3://$backupbucket/segments/last/$n &>/dev/null
                vret=$?
              fi
              if [ $vret -eq 0 ]; then
                set_color green
                echo OK
                set_color norm
                if [ "x$f" == "xdescriptor.json" ]; then
                  echo -n "Copying $(dirname $n)/rule.json: "
                  #upload segment metadata
                  if [ "x$backuppath" != "x" ]; then
                    descriptorid=$(cat $backuppath/segments/last/$n | jq .identifier|sed 's/"//g')
                  else
                    descriptorid=$(cat $f | jq .identifier|sed 's/"//g')
                  fi
                  if [ "x$descriptorid" != "x" ]; then
                    rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -i "$descriptorid" > $f
                    if [ -s $f ]; then
                      if [ "x$backuppath" != "x" ]; then
                        mkdir -p $backuppath/segments/last/$(dirname $n)
                        nice -n 19 ionice -c2 -n7 mv $f $backuppath/segments/last/$(dirname $n)/rule.json &>/dev/null
                        vret=$?
                      else
                        nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync $f s3://$backupbucket/segments/last/$(dirname $n)/rule.json &>/dev/null
                        vret=$?
                      fi
                      if [ $vret -eq 0 ]; then
                        set_color green
                        echo OK
                      else
                        set_color red
                        echo FAILED s3://$backupbucket
                      fi
                    else
                      set_color red
                      echo FAILED unknown metadata
                    fi
                  else
                    set_color red
                    echo FAILED unknown id
                  fi
                fi
              else
                set_color red
                echo FAILED s3://$backupbucket
              fi
            else
              set_color red
              echo FAILED s3://${s3currentbucket}
            fi
            set_color norm
            rm -f $f
          elif [ "x${remotefile[$n]}" != "x${localfile[$n]}" ]; then
            f=$(basename $n)
            rm -f $f
            echo -n "Copying $n: "
            nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync s3://${s3currentbucket}/$n . &>/dev/null
            if [ -f $f ]; then
              if [ "x$backuppath" != "x" ]; then
                mkdir -p $backuppath/segments/overwrite/$overstr/$(dirname $n)
                nice -n 19 ionice -c2 -n7 rsync -a $backuppath/segments/last/$n $backuppath/segments/overwrite/$overstr/$n &>/dev/null
                vret=$?
              else
                nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config mv s3://$backupbucket/segments/last/$n s3://$backupbucket/segments/overwrite/$overstr/$n &>/dev/null
                vret=$?
              fi
              if [ $vret -eq 0 ]; then
                if [ "x$backuppath" != "x" ]; then
                  mkdir -p $backuppath/segments/last/$(dirname $n)
                  nice -n 19 ionice -c2 -n7 rsync -a $f $backuppath/segments/last/$n &>/dev/null
                  vret=$?
                else
                  nice -n 19 ionice -c2 -n7 /usr/bin/python /usr/bin/s3cmd -c $s3config sync $f s3://$backupbucket/segments/last/$n &>/dev/null
                  vret=$?
                fi
                if [ $vret -eq 0 ]; then
                  set_color green
                  echo OK
                else
                  set_color red
                  echo FAILED s3://$backupbucket
                fi
              else
                set_color red
                echo FAILED overwrite s3://$backupbucket
              fi
            else
              set_color red
              echo FAILED s3://${s3currentbucket}
            fi
            set_color norm
            rm -f $f
          fi
        done
        popd &>/dev/null
      fi

      echo -n "Deleting temporal data $tmpdir"
      rm -rf $tmpdir
      print_result $?
    fi
  fi
fi
