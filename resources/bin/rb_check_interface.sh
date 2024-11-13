#!/bin/bash

check_sync_interface_status() {
    local manager=$1
    local sync_ip=$2

    if ! ping -c 1 "$sync_ip" &> /dev/null; then
        systemctl restart keepalived
    fi
}

input_json=$1

for manager in $(echo "$input_json" | jq -r 'keys[]'); do
    sync_ip=$(echo "$input_json" | jq -r ".\"$manager\".ipaddress_sync")
    check_sync_interface_status "$manager" "$sync_ip"
done
