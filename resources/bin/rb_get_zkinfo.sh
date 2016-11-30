#!/bin/bash

source /etc/profile
source $RBLIB/rb_manager_functions.sh

DIRNAME="/tmp/zkinfo-$$"
rm -rf $DIRNAME
mkdir -p $DIRNAME

ZK_HOST=$(/usr/lib/redborder/bin/rb_node_services -n zookeeper)

OIFS=$IFS
IFS=','
for n in ${ZK_HOST}; do
    host=$n
    port="2181"
    echo mntr | nc $host.node $port | awk '{printf("%-30s %-20s\n", $1, $2)}' >${DIRNAME}/${host}.node-${port}.conf
done
IFS=$OIFS

zk_files=$(ls $DIRNAME/*.conf 2>/dev/null | wc -w)

if [ "x$zk_files" == "x1" ]; then
    leader_file=$(ls $DIRNAME/*.conf)
else
    leader_file=$(grep "zk_server_state" $DIRNAME/*.conf |grep leader |tr ':' ' '|awk '{print $1}')
fi


if [ "x${leader_file}" == "x" ]; then
    leader_file=$(ls $DIRNAME/*.conf 2>/dev/null | head -n 1)
fi

if [ "x${leader_file}" != "x" ]; then
    mkdir -p $DIRNAME/leader
    mv $leader_file $DIRNAME/leader

    echo -n "---------------------------------------------------------"
    for file in $(ls $DIRNAME/*.conf 2>/dev/null); do
        echo -n "--------------------------"
    done
    echo "-----"

    printf " %-30s %-25s " "Variable" "$(basename $leader_file|sed 's/\.conf$//'| sed 's/-\([^-]*\)$/:\1/' |  sed "s/^127.0.0.1:/${HOSTNAME}:/" | sed 's/\..*$//' )"

    for file in $(ls $DIRNAME/*.conf 2>/dev/null); do
        printf "%-25s " "$(basename $file|sed 's/\.conf$//' | sed 's/-\([^-]*\)$/:\1/' | sed "s/^127.0.0.1:/${HOSTNAME}:/" | sed 's/\..*$//' )"
    done
    echo
    echo -n "---------------------------------------------------------"
    for file in $(ls $DIRNAME/*.conf 2>/dev/null); do
        echo -n "--------------------------"
    done
    echo "-----"

    printf " %-30s " "status"

    for file in $DIRNAME/leader/*.conf $(ls $DIRNAME/*.conf 2>/dev/null); do
        if [ -f $file ]; then
            host=$(basename $file|sed 's/-[^-]*\.conf$//')
            port=$(basename $file|sed 's/^.*-//'|sed 's/\.conf//')
            value=$(echo ruok | nc $host $port)
            if [ "x$value" == "ximok" ]; then
                set_color green
                printf "%-25s " "ok"
            else
                set_color red
                printf "%-25s " "fail"
            fi
            set_color norm
        fi
    done
    echo

    while read line; do
        variable=$(echo $line | awk '{print $1}')
        value=$(echo $line | awk '{print $2}')

        if [ "x$variable" != "x" -a "x$value" != "x" ]; then
            printf " %-30s " "$variable"
            if [ "x$variable" == "xzk_server_state" ]; then
                if [ "x$variable" == "xzk_server_state" -a "x$value" == "xleader" ]; then
                    set_color green
                    printf "%-25s " "$value"
                    set_color norm
                else
                    printf "%-25s " "$value"
                fi
            elif [ "x$variable" == "xzk_version" ]; then
                printf "%-25s " "$(echo $value|tr ',' ' ')"
            else
                printf "%-25s " "$value"
            fi

            value=""

            for file in $(ls $DIRNAME/*.conf 2>/dev/null); do
                value=$(grep "^$variable " $file | awk '{print $2}')
                if [ "x$value" != "x" ]; then
                    if [ "x$variable" == "xzk_version" ]; then
                        printf "%-25s " "$(echo $value|tr ',' ' ')"
                    else
                        printf "%-25s " "$value"
                    fi
                else
                    printf "%-25s " "-"
                fi
            done
            echo
        fi
    done <<< "$(cat $DIRNAME/leader/*.conf)"
else
    set_color red
    echo "Warning: Leader not found"
    set_color norm
    leader_file=$(ls ${DIRNAME}/*.conf 2>/dev/null | head -n 1)
fi

rm -rf $DIRNAME


## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
