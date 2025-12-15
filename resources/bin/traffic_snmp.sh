#!/bin/bash

# Network interface
IFACE="ens160"

# Interval in seconds (default 5)
INTERVAL=${1:-60}

echo "Monitors in Device (the external snmp agent): "
cat /etc/redborder-monitor/config.json | jq '.sensors[6].monitors | length'
service redborder-monitor restart
# Run tcpdump and aggregate SNMP packets over INTERVAL
sudo tcpdump -l -n -i "$IFACE" udp port 161 2>/dev/null | \

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
        # Bandwidth in KB/s
        out_bw = out_bytes / interval / 1024;
        in_bw  = in_bytes / interval / 1024;

        # Average PDU sizes
        avg_q = (q>0) ? out_bytes/q : 0;
        avg_r = (r>0) ? in_bytes/r : 0;

        # Query/Response ratio
        qr_ratio = (r>0) ? q/r : "inf";

        printf "%s - %ds Queries=%d Responses=%d Out=%.2f KB/s In=%.2f KB/s AvgQuery=%d AvgResponse=%d QR=%.2f\n", \
               strftime("%H:%M:%S"), interval, q, r, out_bw, in_bw, avg_q, avg_r, qr_ratio;

        # Reset counters
        q=0; r=0; out_bytes=0; in_bytes=0;
        window_start = sec;
    }
}'
