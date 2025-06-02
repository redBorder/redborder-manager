#!/usr/bin/env bash

function set_color() {
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
}

e_ok() {
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
  echo "$0 [-h] [-r -f filename] [-x start date] [-y stop date]"
  echo "    export segments from the local s3 database (s3://bucket/) to /var/backup/segments"
  echo "    start and stop date should have following format : 2025-05-27T09:00:00.000Z"
  echo ""
  echo "    -h: print this help"
  echo "    -r: import backup file (-f is mandatory)"
  echo "    -e: enable imported segments"
  echo "    -f: import from a specified file."
  echo "    -g: regex grep filter to export only those files that match the filter"
  echo "    -x: start date of the segments to import/export"
  echo "    -y: end date of the segments to import/export"
  echo ""
  echo "    -n: do not ask. just do it"
  echo "    -b: restore full druid database / is deleting current druid database in postgresql!! you loose current druid data in postgresql!!"
  echo "    -v: be verbose (debug)"
  exit 1
}

function print_system() {
  if [ -f $1 ]; then
    dirfilename=$(dirname $1)
    echo "Free space: $(df -h $dirfilename|grep / |awk '{print $5}') ($(df -h $dirfilename|grep / |awk '{print $4}'))  load average: $(uptime|sed 's/.*load average: //')"
  fi
}

source /etc/profile

import=0
enableallsegments=0
filename=""
debug=0
filter="."
ask=1
restoredb=0

newerthan=""
olderthan=""

start_time=$(date +%s)
hostname=$(hostname -s)
currenttime="$(date +"%Y%m%d%H%M")"
tmpdir="/tmp/segment.tmp-${currenttime}.$$"

renice -n 19 $$ &>/dev/null

while getopts "href:nbg:vx:y:" name
do
  case $name in
    h) usage;;
    r) import=1;;
    e) enableallsegments=1;;
    f) filename="$OPTARG";;
    g) filter="$OPTARG";;
    v) debug=1;;
    n) ask=0;;
    b) restoredb=1;;
    x) startdate="$OPTARG";;
    y) stopdate="$OPTARG";;
  esac
done

if [ ! -f /etc/druid/_common/common.runtime.properties ];then
  echo "/etc/druid/_common/common.runtime.properties file is missing. This file is needed to connect to the database of druid, cannot continue..."
  exit 1
fi

# get druid connection data
s3currentbucket=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null | grep "^druid.storage.bucket=" | tr '=' ' ' | awk '{print $2}')
[ "x$s3currentbucket" == "x" ] && s3currentbucket="bucket"
s3basekey=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null | grep "^druid.storage.baseKey=" | tr '=' ' ' | awk '{print $2}')
[ "x${s3basekey}" == "x" ] && s3basekey="rbdata"
druid_db_uri=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null | grep "^druid.metadata.storage.connector.connectURI=" | tr '=' ' ' | awk '{print $2}')
druid_db_pass=$(cat /etc/druid/_common/common.runtime.properties 2>/dev/null | grep "^druid.metadata.storage.connector.password=" | tr '=' ' ' | awk '{print $2}')

# we are going to import the segments in the local s3
if [ $import -eq 1 ]; then
  confirm=0
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
      exit 1
    fi
  fi

  if [ $confirm -eq 1 ]; then
    if [ -f $tmpdir -o -d $tmpdir ]; then
      echo "ERROR: The temporal directory $tmpdir already exist!!"
    else
      mkdir -p $tmpdir

      echo -n "- uncompress file $filename "
      nice -n 19 ionice -c2 -n7 tar xzf $filename -C $tmpdir
      RET1=$?
      print_result $RET1

      if [ $? -eq $RET1 ]; then
        if [ ! -f $tmpdir/conf/db-druid-dump.psql ]; then
          echo "ERROR: postgresql database segments file not found!"
        elif [ ! -d $tmpdir/segments ]; then
          echo "ERROR: segments directory not found!"
        else
          FILES=$(find $tmpdir/segments/ -type d | head -n 5 | wc -l)
          if [ "x$FILES" != "x5" ]; then
            echo "ERROR: there is no segments in this backup"
          else
            if [ $restoredb -eq 1 ]; then

              PGHOSTNAME="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
              PGPORT="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"

              echo -n "- delete previous segments database !!"
              echo "delete from druid_segments;" | PGPASSWORD="$druid_db_pass" psql -h $PGHOSTNAME -p $PGPORT -U druid -d druid &>/dev/null
              RET2=$?
              print_result $RET2

              echo -n "- restore segments database : "
              PGPASSWORD="$druid_db_pass" pg_restore -t druid_segments -h $PGHOSTNAME -p $PGPORT -U druid -d druid --data-only -F c $tmpdir/conf/db-druid-dump.psql
              RET3=$?
              print_result $RET3
            else
              RET2=0
              RET3=0
            fi

            if [ $RET2 -eq 0 -a $RET3 -eq 0 ]; then
              echo -n "- preparing data : "
              segments_to_sync=()
              counter=0
              numberofsegments=$(find $tmpdir/segments -name "*.zip" | wc -l)
              for n in $(find $tmpdir/segments -name "*.zip"); do
                ((counter++))
                progress=$(printf "%.0f" "$(echo "scale=2; $counter / ${numberofsegments} * 100" | bc)")
                timestamp=$(echo "$n" | awk -F '/' '{print $3}')
                tocopy=1
                if [[ -n $startdate && "$timestamp" < "$startdate" ]]; then
                  tocopy=0
                elif [[ -n $stopdate && "$timestamp" > "$stopdate" ]]; then
                  tocopy=0
                else
                  segments_to_sync+=("$(echo ${n} | sed "s|${tmpdir}/segments/||")")
                fi
                printf "\r- preparing data : %.0f%%" "$progress"
              done
              echo ""

              counter=0
              RET4=0
              echo -n "- import segments : "
              if [ $debug -eq 1 ]; then
                echo ""
              fi
              for n in ${segments_to_sync[@]}; do
                ((counter++))
                progress=$(printf "%.0f" "$(echo "scale=2; $counter / ${#segments_to_sync[@]} * 100" | bc)")
                if [ $debug -eq 1 ]; then
                  echo -n "  sync $n to s3 : [${progress}%]"
                fi
                nice -n 19 ionice -c2 -n7 mcli put $tmpdir/segments/$n ${hostname}/${s3currentbucket}/${s3basekey}/${n} &>/dev/null
                RET4=$?
                if [ $debug -eq 1 ]; then
                  print_result $RET4
                else
                  printf "\r- import segments : %.0f%%" "$progress"
                fi
              done
              echo ""

              if [ $restoredb -ne 1 ]; then
                RET=0
                echo -n "- import/update druid metadata : "
                counter=0
                numberofrules=$(find $tmpdir/segments -name "rule.json" | wc -l)
                for module in $(ls $tmpdir/segments); do
                  for rule in $(find $tmpdir/segments/$module/*/*/*/ -name "rule.json"); do
                    ((counter++))
                    progress=$(printf "%.0f" "$(echo "scale=2; ${counter} / ${numberofrules} * 100" | bc)")
                    if [ "x$enableallsegments" == "x1" ]; then
                      if [ $debug -eq 1 ]; then
                        echo -n "   enable segment and "
                      fi
                      sed -i 's/"used": "f",/"used": "t",/' $rule
                    else
                      if [ $debug -eq 1 ]; then  
                        echo -n "   "
                      fi
                    fi
                    if [ $debug -eq 1 ]; then
                      echo -n "add $rule in druid database... [$progress%]"
                    else
                      printf "\r- import/update druid metadata : %.0f%%" "$progress"
                    fi
                    rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -f $rule
                    if [ $debug -eq 1 ]; then
                      print_result $RET
                    fi
                  done
                done
              fi
            fi
          fi
        fi
      fi
      echo -n "- remove temporary files : "
      rm -rf $tmpdir
      print_result $?

      end_time=$(date +%s)
      elapsed_seconds=$((end_time - start_time))
      elapsed_time=$(printf "%d:%02d:%02d" $((elapsed_seconds / 3600)) $(( (elapsed_seconds % 3600) / 60 )) $((elapsed_seconds % 60)) )
      echo "- total runtime: $elapsed_time (HH:MM:SS)"
    fi
  fi
else # we are going to export the segments to a tar
  filename="/var/backup/segments/segment-${currenttime}.tar"
  mkdir -p /var/backup/segments/

  confirm=1
  if [ -f $filename ]; then
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
  fi

  if [ $confirm -eq 1 ]; then
    rm -f $filename

    if [ -f $tmpdir -o -d $tmpdir ]; then
      echo "ERROR: The temporal dir $tmpdir already exist!!"
    else
      mkdir -p $tmpdir/conf
      echo -n "- backup full druid database $tmpdir/conf/db-druid-dump.psql "

      PGHOSTNAME="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
      PGPORT="$(echo $druid_db_uri | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"
      PGPASSWORD="$druid_db_pass" pg_dump -U druid -h $PGHOSTNAME -p $PGPORT -F c -b -f $tmpdir/conf/db-druid-dump.psql
      RET1=$?
      print_result $RET1

      count=1
      RET2=1

      mkdir $tmpdir/segments
      pushd $tmpdir/segments &>/dev/null

      echo -n "- getting segments info from s3: "
      declare -A localfile
      [[ -n "$startdate" ]] && datefilter+=("--newer-than" "${startdate}")
      [[ -n "$stopdate" ]] && datefilter+=("--older-than" "${stopdate}")
      
      eval "miniofiles=($(nice -n 19 ionice -c2 -n7 mcli find "${hostname}/${s3currentbucket}/${s3basekey}/" "${datefilter[@]}" --regex "$filter" | sed "s|${hostname}/${s3currentbucket}/${s3basekey}/||"))"
      print_result $?

      counter=0
      numberofsegments=0
      echo -n "- copy segment data : "
      if [ $debug -eq 1 ]; then
           echo ""
      fi
      for n in "${miniofiles[@]}"; do
        ((counter++))
        progress=$(printf "%.0f" "$(echo "scale=2; $counter / ${#miniofiles[@]} * 100" | bc)")

        if [[ "$n" == *index.zip ]]; then
          ((numberofsegments++))
        fi
        if [ $debug -eq 1 ]; then
          echo -n "  copy $n: [$progress%] "
          mkdir -p "./$(dirname "$n")"
        else 
          printf "\r- copy segment data : %.0f%%" "$progress"
        fi 
        nice -n 19 ionice -c2 -n7 mcli get "${hostname}/${s3currentbucket}/${s3basekey}/$n" "$n" &>/dev/null
        RET=$?
        if [ $debug -eq 1 ]; then
          print_result "$RET"
        fi
      done
      echo ""
      RET2=0

      counter=0
      echo -n "- create metadata : "
      if [ $debug -eq 1 ]; then
          echo ""
      fi
      for n in $(find $tmpdir/segments -name index.zip); do
        ((counter++))
        progress=$(printf "%.0f" "$(echo "scale=2; $counter / $numberofsegments * 100" | bc)")
        if [ $debug -eq 1 ]; then
          echo -n "  creating $(dirname $n)/rule.json: [$progress%] "
        else
          printf "\r- create metadata : %.0f%%" "$progress"
        fi
        if [ -s $n ]; then
          IFS='/' read -ra parts <<< "$n"
          descriptorid="${parts[4]}_${parts[5]}_${parts[6]}"
          if [ "x$descriptorid" != "x" ]; then
            rvm ruby-2.7.5@web 2>/dev/null do rb_druid_metadata -i "$descriptorid" > "$(dirname $n)/rule.json"
            if [ $debug -eq 1 ]; then
              if [ -s $f ]; then
                e_ok
              else
                e_fail
              fi
            fi
          else
            if [ $debug -eq 1 ]; then
              e_fail 
            fi
          fi
        else
          if [ $debug -eq 1 ]; then
            e_fail 
          fi
        fi
      done
      echo ""
      popd &>/dev/null

      echo -n "- compress data into $(basename $filename)"
      nice -n 19 ionice -c2 -n7 tar czf $filename -C $tmpdir .
      print_result $?

      echo -n "- deleting temporal data $tmpdir"
      rm -rf $tmpdir
      print_result $?
      echo ""
      echo -n "Backup file $filename saved"
      if [ $RET1 -eq 0 -a $RET2 -eq 0 ]; then
        print_result 0
      else
        echo -n " (with errors) "
        print_result 1
      fi
      end_time=$(date +%s)
      elapsed_seconds=$((end_time - start_time))
      elapsed_time=$(printf "%d:%02d:%02d" $((elapsed_seconds / 3600)) $(( (elapsed_seconds % 3600) / 60 )) $((elapsed_seconds % 60)) )
      echo "- total runtime: $elapsed_time (HH:MM:SS)"
    fi
  fi
fi
