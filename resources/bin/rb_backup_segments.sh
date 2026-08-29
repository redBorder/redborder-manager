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
        echo " [OK]"
    else
        echo " [FAILED]"
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
  echo "    -t: export to specific tarfile"
  echo "    -g: regex grep filter to export only those files that match the filter"
  echo "    -x: start date of the segments to import/export"
  echo "    -y: end date of the segments to import/export"
  echo "    -s: segment ids to export, comma separated"
  echo ""
  echo "    -n: do not ask. just do it"
  echo "    -b: restore full druid database / is deleting current druid database in postgresql!! you loose current druid data in postgresql!!"
  echo "    -v: be verbose (debug)"
  exit 1
}

function print_system() {
  if [ -f "$1" ]; then
    dirfilename=$(dirname "$1")
    echo "Free space: $(df -h "$dirfilename" | grep / | awk '{print $5}') ($(df -h "$dirfilename" | grep / | awk '{print $4}'))  load average: $(uptime|sed 's/.*load average: //')"
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
segment_ids=""

newerthan=""
olderthan=""

start_time=$(date +%s)
hostname=$(hostname -s)
currenttime="$(date +"%Y%m%d%H%M")"
tmpdir="/tmp/segment.tmp-${currenttime}.$$"

renice -n 19 $$ &>/dev/null

while getopts "href:t:nbg:vx:y:s:" name
do
  case $name in
    h) usage;; 
    r) import=1;; 
    e) enableallsegments=1;; 
    f) filename="$OPTARG";;
    t) exportfile="$OPTARG";;
    g) filter="$OPTARG";;
    v) debug=1;; 
    n) ask=0;; 
    b) restoredb=1;; 
    x) startdate="$OPTARG";;
    y) stopdate="$OPTARG";;
    s) segment_ids="$OPTARG";;
  esac
done

if [ ! -f /etc/druid/_common/common.runtime.properties ];then
  echo "ERROR: /etc/druid/_common/common.runtime.properties file is missing. This file is needed to connect to the database of druid, cannot continue..."
  exit 1
fi

if [ "x$exportfile" != "x" ]; then
  exportpath=$(dirname "$exportfile")
  if [ ! -d "$exportpath" ]; then
    echo "ERROR: path where we need to store the tar file does not exist!"
    exit 1
  fi

  if [[ "$exportfile" != *.tar ]]; then
    echo "ERROR: export file should end with .tar"
    exit 1
  fi
fi

# get druid connection data
s3currentbucket=$(grep "^druid.storage.bucket=" /etc/druid/_common/common.runtime.properties 2>/dev/null | cut -d'=' -f2)
[ -z "$s3currentbucket" ] && s3currentbucket="bucket"
s3basekey=$(grep "^druid.storage.baseKey=" /etc/druid/_common/common.runtime.properties 2>/dev/null | cut -d'=' -f2)
[ -z "$s3basekey" ] && s3basekey="rbdata"
druid_db_uri=$(grep "^druid.metadata.storage.connector.connectURI=" /etc/druid/_common/common.runtime.properties 2>/dev/null | cut -d'=' -f2)
druid_db_pass=$(grep "^druid.metadata.storage.connector.password=" /etc/druid/_common/common.runtime.properties 2>/dev/null | cut -d'=' -f2)

# we are going to import the segments in the local s3
if [ $import -eq 1 ]; then
  confirm=0
  if [ -z "$filename" ]; then
    echo "ERROR: The option -f is mandatory to import segments"
    exit 1
  elif [ -d "$filename" ]; then
    echo "ERROR: The selected file is a directory"
    exit 1
  elif [ ! -f "$filename" ]; then
    echo "ERROR: The selected file $filename doesn't exist"
    exit 1
  else
    if file "$filename" | grep -q "gzip compressed data"; then
      echo "WARNING: Restoring backup from $filename file"
      print_system "$filename"
      if [ $ask -eq 1 ]; then
        echo -n "Would you like to continue? (y/N) "
        read -r VAR
        if [ "$VAR" == "y" ] || [ "$VAR" == "Y" ]; then
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
    if [ -e "$tmpdir" ]; then
      echo "ERROR: The temporal directory $tmpdir already exist!!"
      exit 1
    else
      mkdir -p "$tmpdir"

      echo -n "- uncompress file $filename"
      nice -n 19 ionice -c2 -n7 tar xzf "$filename" -C "$tmpdir"
      RET1=$?
      print_result $RET1

      if [ $RET1 -eq 0 ]; then
        if [ ! -f "$tmpdir/conf/db-druid-dump.psql" ]; then
          echo "ERROR: postgresql database segments file not found!"
        elif [ ! -d "$tmpdir/segments" ]; then
          echo "ERROR: segments directory not found!"
        else
          FILES_COUNT=$(find "$tmpdir/segments" -type f -name "*.zip" | wc -l)
          if [ "$FILES_COUNT" -eq 0 ]; then
            echo "ERROR: there are no segments in this backup"
          else
            if [ $restoredb -eq 1 ]; then

              PGHOSTNAME="$(echo "$druid_db_uri" | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
              PGPORT="$(echo "$druid_db_uri" | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"

              echo -n "- delete previous segments database !!"
              echo "delete from druid_segments;" | PGPASSWORD="$druid_db_pass" psql -h "$PGHOSTNAME" -p "$PGPORT" -U druid -d druid &>/dev/null
              RET2=$?
              print_result $RET2

              echo -n "- restore segments database :"
              PGPASSWORD="$druid_db_pass" pg_restore -t druid_segments -h "$PGHOSTNAME" -p "$PGPORT" -U druid -d druid --data-only -F c "$tmpdir/conf/db-druid-dump.psql"
              RET3=$?
              print_result $RET3
            else
              RET2=0
              RET3=0
            fi

            if [ $RET2 -eq 0 ] && [ $RET3 -eq 0 ]; then
              echo -n "- preparing data : "
              mapfile -t segments_to_sync < <(find "$tmpdir/segments" -type f -name "*.zip")
              
              if [[ -n "$startdate" || -n "$stopdate" ]]; then
                  filtered_sync=()
                  for n in "${segments_to_sync[@]}"; do
                      timestamp=$(echo "$n" | awk -F '/' '{print $3}')
                      if [[ -n "$startdate" && "$timestamp" < "$startdate" ]]; then
                          continue
                      fi
                      if [[ -n "$stopdate" && "$timestamp" > "$stopdate" ]]; then
                          continue
                      fi
                      filtered_sync+=("$n")
                  done
                  segments_to_sync=("${filtered_sync[@]}")
              fi
              echo "100%"

              counter=0
              RET4=0
              echo -n "- import segments : "
              if [ $debug -eq 1 ]; then
                echo ""
              fi
              for n in "${segments_to_sync[@]}"; do
                ((counter++))
                progress=$(printf "%.0f" "$(echo "scale=2; $counter / ${#segments_to_sync[@]} * 100" | bc)")
                if [ $debug -eq 1 ]; then
                  echo -n "  sync $n to s3 : [${progress}%]"
                fi
                s3_target_path=$(echo "$n" | sed "s|${tmpdir}/segments/||")
                nice -n 19 ionice -c2 -n7 /usr/local/bin/mcli --quiet cp "$n" "${hostname}/${s3currentbucket}/${s3basekey}/${s3_target_path}"
                RET4=$?
                if [ $debug -eq 1 ]; then
                  print_result $RET4
                else
                  printf "\r- import segments : %.0f%%" "$progress"
                fi
              done
              echo ""

              if [ $restoredb -ne 1 ]; then
                RET5=0
                echo -n "- import/update druid metadata : "
                mapfile -t rule_files < <(find "$tmpdir/segments" -type f -name "rule.json")
                counter=0
                numberofrules=${#rule_files[@]}
                for rule in "${rule_files[@]}"; do
                    ((counter++))
                    progress=$(printf "%.0f" "$(echo "scale=2; $counter * 100 / $numberofrules" | bc)")
                    if [ "$enableallsegments" -eq 1 ]; then
                      if [ $debug -eq 1 ]; then
                        echo -n "   enable segment and "
                      fi
                      sed -i 's/"used": "f",/"used": "t",/' "$rule"
                    fi
                    if [ $debug -eq 1 ]; then
                      echo -n "add $rule in druid database... [$progress%]"
                    else
                      printf "\r- import/update druid metadata : %.0f%%" "$progress"
                    fi
                    rvm ruby-2.7.5@web do rb_druid_metadata -f "$rule" &>/dev/null
                    RET5=$?
                    if [ $debug -eq 1 ]; then
                      print_result $RET5
                    fi
                done
              fi
            fi
          fi
        fi
      fi
      echo -n "- remove temporary files :"
      rm -rf "$tmpdir"
      print_result $?

      end_time=$(date +%s)
      elapsed_seconds=$((end_time - start_time))
      elapsed_time=$(printf "%d:%02d:%02d" "$((elapsed_seconds / 3600))" "$(( (elapsed_seconds % 3600) / 60 ))" "$((elapsed_seconds % 60))" )
      echo "- total runtime: $elapsed_time (HH:MM:SS)"
    fi
  fi
else # we are going to export the segments to a tar
  if [ -z "$exportfile" ]; then
    filename="/var/backup/segments/segment-${currenttime}.tar"
    mkdir -p /var/backup/segments/
  else
    filename=${exportfile}
  fi

  confirm=1
  if [ -f "$filename" ]; then
    print_system "$filename"
    if [ $ask -eq 1 ]; then
      echo -n "The file $filename exist. Would you like to overwrite it? (y/N) "
      read -r VAR
      if [ "$VAR" == "y" ] || [ "$VAR" == "Y" ]; then
        confirm=1
      else
        confirm=0
      fi
    else
      confirm=1
    fi
  fi

  if [ $confirm -eq 1 ]; then
    rm -f "$filename"

    if [ -e "$tmpdir" ]; then
      echo "ERROR: The temporal dir $tmpdir already exist!!"
    else
      mkdir -p "$tmpdir/conf"
      echo -n "- backup full druid database $tmpdir/conf/db-druid-dump.psql"

      PGHOSTNAME="$(echo "$druid_db_uri" | sed 's|jdbc:postgresql://||' | sed 's/:.*//')"
      PGPORT="$(echo "$druid_db_uri" | sed 's|jdbc:postgresql://||' | sed 's/.*://' | sed 's|/.*||')"
      PGPASSWORD="$druid_db_pass" pg_dump -U druid -h "$PGHOSTNAME" -p "$PGPORT" -F c -b -f "$tmpdir/conf/db-druid-dump.psql"
      RET1=$?
      print_result $RET1

      mkdir -p "$tmpdir/segments"
      pushd "$tmpdir/segments" &>/dev/null

      echo "- getting segments info from s3: "
      
      minio_find_cmd="nice -n 19 ionice -c2 -n7 /usr/local/bin/mcli find \"${hostname}/${s3currentbucket}/${s3basekey}/\" --regex \"$filter\""
      
      if [ -n "$startdate" ]; then
          minio_find_cmd+=" --newer-than \"${startdate}\""
      fi
      if [ -n "$stopdate" ]; then
          minio_find_cmd+=" --older-than \"${stopdate}\""
      fi

      if [ -n "$segment_ids" ]; then
        miniofiles=()
        IFS=',' read -ra ids <<< "$segment_ids"
        for id in "${ids[@]}"; do
          IFS='_' read -ra id_parts <<< "$id"
          num_parts=${#id_parts[@]}
          version=${id_parts[num_parts-1]}
          interval_end=${id_parts[num_parts-2]}
          interval_start=${id_parts[num_parts-3]}
          interval="${interval_start}_${interval_end}"
          datasource_parts=("${id_parts[@]:0:num_parts-3}")
          datasource=$(IFS=_ ; echo "${datasource_parts[*]}")
          s3_path_prefix="${datasource}/${interval}/${version}"
          
          mapfile -t segment_files < <(nice -n 19 ionice -c2 -n7 /usr/local/bin/mcli find "${hostname}/${s3currentbucket}/${s3basekey}/${s3_path_prefix}/" --regex ".*" | sed "s|${hostname}/${s3currentbucket}/${s3basekey}/||")
          miniofiles+=("${segment_files[@]}")
        done
        print_result $?
      else
        mapfile -t miniofiles < <(eval "$minio_find_cmd" | sed "s|${hostname}/${s3currentbucket}/${s3basekey}/||")
        print_result $?
      fi

      counter=0
      numberofsegments=${#miniofiles[@]}
      batch_size=8
      pids=()
      RET2=0
      
      echo -n "- copy segment data :"
      if [ $debug -eq 1 ]; then
        echo ""
      fi

      for i in "${!miniofiles[@]}"; do
        n="${miniofiles[$i]}"
        
        mkdir -p "./$(dirname "$n")"

        (
          nice -n 19 ionice -c2 -n7 /usr/local/bin/mcli --quiet get "${hostname}/${s3currentbucket}/${s3basekey}/$n" "$n"
          if [ $? -ne 0 ]; then echo "ERROR: Download of $n failed" >&2; exit 1; fi
        ) &
        pids+=($!)
        
        if (( ${#pids[@]} >= batch_size || i == numberofsegments - 1 )); then
          for pid in "${pids[@]}"; do
            wait "$pid" || RET2=1
          done
          pids=()

          processed_count=$((i + 1))
          progress=$(printf "%.0f" "$(echo "scale=2; $processed_count * 100 / $numberofsegments" | bc)")
          if [ $debug -eq 0 ]; then
            printf "\r- copy segment data : %d%%" "$progress"
          fi
        fi
      done
      
      echo ""

      counter=0
      echo -n "- create metadata :"
      if [ $debug -eq 1 ]; then
          echo ""
      fi
      
      mapfile -t zip_files < <(find . -type f -name "index.zip")
      numberofzips=${#zip_files[@]}

      for n in "${zip_files[@]}"; do
        ((counter++))
        progress=$(printf "%.0f" "$(echo "scale=2; $counter * 100 / $numberofzips" | bc)")
        if [ $debug -eq 1 ]; then
          echo -n "  creating $(dirname "$n")/rule.json: [$progress%]"
        else
          printf "\r- create metadata : %d%%" "$progress"
        fi
        if [ -s "$n" ]; then
          IFS='/' read -ra parts <<< "${n#./}"
          descriptorid="${parts[1]}_${parts[2]}_${parts[3]}"
          if [ -n "$descriptorid" ]; then
            rule_file="$(dirname "$n")/rule.json"
            rvm ruby-2.7.5@web do rb_druid_metadata -i "$descriptorid" > "$rule_file" 2>/dev/null
            if [ $debug -eq 1 ]; then
              if [ -s "$rule_file" ]; then
                print_result 0
              else
                print_result 1
              fi
            fi
          elif [ $debug -eq 1 ]; then
            print_result 1 
          fi
        elif [ $debug -eq 1 ]; then
          print_result 1 
        fi
      done
      echo ""
      popd &>/dev/null

      echo -n "- compress data into $(basename "$filename")"
      nice -n 19 ionice -c2 -n7 tar czf "$filename" -C "$tmpdir" .
      RET3=$?
      print_result $RET3

      echo -n "- deleting temporal data $tmpdir"
      rm -rf "$tmpdir"
      print_result $?
      echo ""
      echo -n "Backup file $filename saved"
      if [ $RET1 -eq 0 ] && [ $RET2 -eq 0 ] && [ $RET3 -eq 0 ]; then
        print_result 0
      else
        echo -n " (with errors) "
        print_result 1
      fi
      end_time=$(date +%s)
      elapsed_seconds=$((end_time - start_time))
      elapsed_time=$(printf "%d:%02d:%02d" "$((elapsed_seconds / 3600))" "$(( (elapsed_seconds % 3600) / 60 ))" "$((elapsed_seconds % 60))" )
      echo "- total runtime: $elapsed_time (HH:MM:SS)"
    fi
  fi
fi
