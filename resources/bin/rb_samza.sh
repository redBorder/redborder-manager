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

#RBDIR=${RBDIR-/opt/rb}
source /etc/profile

function usage(){
  echo "$0 [-h][-e][-u][-k][-l][-c <count>][-m <memory>]"
  echo "    -h: print this help"
  echo "    -e: execute the task"
  echo "    -v: print the version"
  echo "    -k: kill running tasks"
  echo "    -l: list running tasks"
  echo "    -t: set type of task: enrichment, indexing, pms, all (default)"
  echo "    -c: set samza containers (default: 1)"
  echo "    -m: set samza container memory (default: 1024)"
  echo "    -s: show samza container info"
  echo " example:" 
  echo "   - upload: rb_samza.sh -t enrichment -e"
  echo "   -   kill: rb_samza.sh -t enrichment -k"
  echo "   -   list: rb_samza.sh -l"   
  exit 1
}

f_execute=0
f_kill=0
f_list=0
f_cont=0
f_mem=0
containers=1
memory=1024
f_version=0
f_type="all"
f_show=0

while getopts "hevklt:c:m:s" name
do
  case $name in
    h) usage;;
    e) f_execute=1;;
    k) f_kill=1;;
    l) f_list=1;;
    v) f_version=1;;
    t) f_type=$OPTARG;;
    c) f_cont=1; containers=$OPTARG;;
    m) f_mem=1; memory=$OPTARG;;
    s) f_show=1;;
  esac
done

if [ $f_version -eq 1 ]; then
  ls /var/rb-samza-bi/app/rb-samza-bi.tar.gz -l|sed 's/.*-> //'|awk '{print $1}' | sed 's/rb-samza-bi-//' | sed 's/-.*$//'
else
  [ $f_cont -eq 1 ] && rb_set_samzacontainers.rb -c $containers
  [ $f_mem -eq 1 ] && rb_set_samzacontainersmemory.rb -m $memory
  [ $f_show -eq 1 ] && rb_set_samzacontainers.rb -s && rb_set_samzacontainersmemory.rb -s
  if [ $f_kill -eq 1 ]; then
    if [ "x$f_type" == "xenrichment" ] || [ "x$f_type" == "xall" ]; then
      application="$(yarn application -list | grep enrichment | awk '{print $1}')"
      running="x$application";
      if [ $running != "x" ]; then
        yarn application -kill $application &>/dev/null
        echo "Killed application $application (enrichment)"
      else
        echo "The enrichment application was not running"
      fi
    fi

    if [ "x$f_type" == "xlocation" ] || [ "x$f_type" == "xall" ]; then
      application="$(yarn application -list | grep location | awk '{print $1}')"
      running="x$application";
      if [ $running != "x" ]; then
        yarn application -kill $application &>/dev/null
        echo "Killed application $application (location)"
      else
        echo "The location application was not running"
      fi
    fi

    if [ "x$f_type" == "xindexing" ] || [ "x$f_type" == "xall" ]; then
      application="$(yarn application -list | grep indexing | awk '{print $1}')"
      running="x$application";
      if [ $running != "x" ]; then
        yarn application -kill $application &>/dev/null
        echo "Killed application $application (indexing)"
      else
        echo "The indexing application was not running"
      fi
    fi

    if [ "x$f_type" == "xmalware" ] || [ "x$f_type" == "xall" ]; then
      application="$(yarn application -list | grep samza-malware | awk '{print $1}')"
      running="x$application";
      if [ $running != "x" ]; then
        yarn application -kill $application &>/dev/null
        echo "Killed application $application (malware)"
      else
        echo "The malware application was not running"
      fi
    fi

    if [ "x$f_type" == "xpms" ] || [ "x$f_type" == "xall" ]; then
      application="$(yarn application -list | grep pms | awk '{print $1}')"
      running="x$application";
      if [ $running != "x" ]; then
        yarn application -kill $application &>/dev/null
        echo "Killed application $application (pms)"
      else
        echo "The pms application was not running"
      fi
    fi
  fi
  
  if [ $f_list -eq 1 ]; then
     timeout 60 yarn application -list | egrep "(Samza|Application-Id)"
  fi
  
  if [ $f_execute -eq 1 ]; then
   if [ "x$f_type" == "xmalware" ]; then

      rm -rf /var/rb-samza-malware/bin/*
      rm -rf /var/rb-samza-malware/lib/*
      tar xfz /var/rb-samza-malware/app/rb-samza-malware.tar.gz -C /var/rb-samza-malware

      application="$(yarn application -list | grep samza-malware | awk '{print $1}')"
      running="x$application";
      if [ $running == "x" ]; then
         /var/rb-samza-malware/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory --config-path=file:/var/rb-samza-malware/config/malware.properties
      else
        echo "Application $application (malware) is already running."
      fi
   else
      rm -rf /var/rb-samza-bi/bin/*
      rm -rf /var/rb-samza-bi/lib/*
      tar xfz /var/rb-samza-bi/app/rb-samza-bi.tar.gz -C /var/rb-samza-bi
    
      if [ "x$f_type" == "xenrichment" ] || [ "x$f_type" == "xall" ]; then
        application="$(yarn application -list | grep enrichment | awk '{print $1}')"
        running="x$application";
        if [ $running == "x" ]; then
           /var/rb-samza-bi/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory --config-path=file:/var/rb-samza-bi/config/enrichment.properties
        else
          echo "Application $application (enrichment) is already running."
        fi
      fi

      if [ "x$f_type" == "xlocation" ] || [ "x$f_type" == "xall" ]; then
        rm -rf /var/rb-samza-location/bin/*
        rm -rf /var/rb-samza-location/lib/*
        tar xfz /var/rb-samza-location/app/rb-samza-location.tar.gz -C /var/rb-samza-location

        application="$(yarn application -list | grep location | awk '{print $1}')"
        running="x$application";
        if [ $running == "x" ]; then
           /var/rb-samza-location/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory --config-path=file:/var/rb-samza-location/config/location.properties
        else
          echo "Application $application (location) is already running."
        fi
      fi

      if [ "x$f_type" == "xindexing" ] || [ "x$f_type" == "xall" ]; then
        application="$(yarn application -list | grep indexing | awk '{print $1}')"
        running="x$application";
        if [ $running == "x" ]; then
           /var/rb-samza-bi/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory --config-path=file:/var/rb-samza-bi/config/indexing.properties
        else
          echo "Application $application (indexing) is already running."
        fi
      fi
    fi
  fi
  
fi
