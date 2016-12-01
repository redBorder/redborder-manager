#!/bin/bash

function usage() {
  echo "$0 [-h] -u username -p password -i host"
  exit 1
}

username=""
password=""
host=""

while getopts "hu:p:i:" name; do
  case $name in
    u) username="$OPTARG";;
    p) password="$OPTARG";;
    i) host="$OPTARG";;
    h) usage;;

        esac
done

if [ "x$username" == "x" -o "x$password" == "x" -o "x$host" == "x" ]; then
    usage
fi

((echo open $host
sleep 1
echo $username
sleep 1
echo $password
sleep 1
echo term leng 0
sleep 1
echo show ip nat statis
sleep 1
echo exit) | telnet 2>/dev/null) | awk '/active/ {print $4}'
