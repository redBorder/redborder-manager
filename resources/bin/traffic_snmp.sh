#!/bin/bash

# Default values
IFACE="ens160"
INTERVAL=60
TARGET_IP="10.1.32.158"

# Parse command-line options
while getopts "i:t:I:" opt; do
    case "$opt" in
        i) IFACE="$OPTARG" ;;
        t) TARGET_IP="$OPTARG" ;;
        I) INTERVAL="$OPTARG" ;;
        r) RESTART="true" ;;  # Set boolean if -r is passed
        *) echo "Usage: $0 [-i interface] [-t target_ip] [-I interval_seconds]"
           exit 1 ;;
    esac
done

# Ask interactively if not set
if [ -z "$IFACE" ]; then
    read -rp "Enter network interface (default ens160): " IFACE
    IFACE=${IFACE:-ens160}
fi

if [ -z "$TARGET_IP" ]; then
    read -rp "Enter target IP (default 10.1.32.158): " TARGET_IP
    TARGET_IP=${TARGET_IP:-10.1.32.158}
fi

if [ -z "$INTERVAL" ]; then
    read -rp "Enter interval in seconds (default 60): " INTERVAL
    INTERVAL=${INTERVAL:-60}
fi

if [ -n "$RESTART" ]; then
    service redborder-monitor restart
fi

echo "Monitoring SNMP on interface: $IFACE"
echo "Target IP: $TARGET_IP"
echo "Interval: $INTERVAL seconds"

echo "Monitors in Device (the external SNMP agent):"
jq '.sensors[6].monitors | length' /etc/redborder-monitor/config.json


# Run tcpdump and aggregate SNMP packets over INTERVAL
tcpdump -l -n -i "$IFACE" udp port 161 2>/dev/null | \
awk -v interval="$INTERVAL" '
{
    split($1, t, ":");
    sec = t[1]*3600 + t[2]*60 + t[3];

    if (window_start == "") window_start = sec;

    # Extract PDU length inside parentheses
    len=0;
    if (match($0, /\(([0-9]+)\)/, arr)) len = arr[1];

    # Outgoing (queries) vs incoming (responses)
    if ($0 ~ /GetRequest|GetBulk/) { 
        q++; out_bytes += len; 
    }
    if ($0 ~ /GetResponse/) { 
        r++; in_bytes += len; 
    }

    # Interval elapsed → print stats and reset counters
    if (sec - window_start >= interval) {
        out_bw = out_bytes / interval / 1024;
        in_bw  = in_bytes / interval / 1024;

        avg_q = (q>0) ? out_bytes/q : 0;
        avg_r = (r>0) ? in_bytes/r : 0;

        qr_ratio = (r>0) ? q/r : "inf";

        printf "%s - %ds Queries=%d Responses=%d Out=%.2f KB/s In=%.2f KB/s AvgQuery=%d AvgResponse=%d QR=%.2f\n", \
               strftime("%H:%M:%S"), interval, q, r, out_bw, in_bw, avg_q, avg_r, qr_ratio;

        q=0; r=0; out_bytes=0; in_bytes=0;
        window_start = sec;
    }
}'