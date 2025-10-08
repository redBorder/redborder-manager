#!/bin/bash
#
# Health check PostgreSQL replication
#

THRESHOLD_BYTES=${1:-16777216} # 16MB by default
THRESHOLD_SECONDS=${2:-180}    # 3 minutes by default
PGUSER="rep"
PGMASTERUSER="postgres"
PGPORT=5432
DATABASE="postgres"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ROLE=$(psql -h localhost -U "$PGUSER" -p "$PGPORT" -d "$DATABASE" -t -A \
    -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'slave' ELSE 'master' END;" 2>/dev/null | tr -d '[:space:]')

STATUS="OK"

# -----------------------
# Check TCP port 5432
# -----------------------
nc -z -w3 localhost $PGPORT
if [ $? -ne 0 ]; then
    PORT_STATUS="closed"
    STATUS="OUT_OF_SYNC"
else
    PORT_STATUS="open"
fi

# -----------------------
# Ping master service
# -----------------------
ping -c 1 -W 2 master.postgresql.service >/dev/null 2>&1
if [ $? -ne 0 ]; then
    PING_MASTER_STATUS="unreachable"
    STATUS="OUT_OF_SYNC"
else
    PING_MASTER_STATUS="reachable"
fi

if [ "$ROLE" == "master" ]; then
    # Master: Check replication walsender processes
    REPLICAS=$(psql -h localhost -U "$PGUSER" -p "$PGPORT" -d "$DATABASE" -t -A -F"," \
        -c "SELECT pid, usename, application_name, client_addr, client_port, backend_start, query_start, state_change, state 
            FROM pg_stat_activity WHERE backend_type='walsender';")

    REPLICA_ARRAY="[]"

    if [ -n "$REPLICAS" ]; then
        REPLICA_ARRAY="["
        while IFS=',' read -r pid usename app addr port bstart qstart schange state; do
            [ "$REPLICA_ARRAY" != "[" ] && REPLICA_ARRAY+=","
            REPLICA_ARRAY+="{\"pid\":$pid,\"usename\":\"$usename\",\"application_name\":\"$app\",\"client_addr\":\"$addr\",\"client_port\":$port,\"backend_start\":\"$bstart\",\"query_start\":\"$qstart\",\"state_change\":\"$schange\",\"state\":\"$state\"}"
            if [ "$state" != "active" ]; then
                STATUS="OUT_OF_SYNC"
            fi
        done <<< "$REPLICAS"
        REPLICA_ARRAY+="]"
    fi

    OUTPUT="{\"role\":\"$ROLE\",\"timestamp\":\"$TIMESTAMP\",\"status\":\"$STATUS\",\"port_status\":\"$PORT_STATUS\",\"ping_master_status\":\"$PING_MASTER_STATUS\",\"replicas\":$REPLICA_ARRAY}"

elif [ "$ROLE" == "slave" ]; then
    # Slave: Check replication lag
    MASTER_IP=$(psql -h localhost -U "$PGMASTERUSER" -p "$PGPORT" -d "$DATABASE" -t -A \
        -c "SHOW primary_conninfo;" 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i ~ /^host=/){split($i,a,/=/); print a[2]}}}')

    if [ -z "$MASTER_IP" ]; then
        STATUS="OUT_OF_SYNC"
    else
        MASTER_LSN=$(psql -h "$MASTER_IP" -U "$PGUSER" -p $PGPORT -d "$DATABASE" -t -A \
            -c "SELECT pg_current_wal_lsn();" 2>/dev/null | tr -d '[:space:]')
        SLAVE_LSN=$(psql -h localhost -U "$PGUSER" -p $PGPORT -d "$DATABASE" -t -A \
            -c "SELECT pg_last_wal_replay_lsn();" 2>/dev/null | tr -d '[:space:]')

        if [ -z "$MASTER_LSN" ] || [ -z "$SLAVE_LSN" ]; then
            STATUS="OUT_OF_SYNC"
        else
            LAG_BYTES=$(psql -h "$MASTER_IP" -U "$PGUSER" -p $PGPORT -d "$DATABASE" -t -A \
                -c "SELECT pg_wal_lsn_diff('$MASTER_LSN', '$SLAVE_LSN');" 2>/dev/null | tr -d '[:space:]')
            [ "$LAG_BYTES" -lt 0 ] && LAG_BYTES=0

            REPLICATION_DELAY=$(psql -h localhost -U "$PGUSER" -p "$PGPORT" -d "$DATABASE" -t -A \
                -c "SELECT EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())::int;" 2>/dev/null)

            (( LAG_BYTES > THRESHOLD_BYTES || REPLICATION_DELAY > THRESHOLD_SECONDS )) && STATUS="OUT_OF_SYNC"
        fi
    fi

    OUTPUT="{\"role\":\"$ROLE\",\"timestamp\":\"$TIMESTAMP\",\"status\":\"$STATUS\",\"port_status\":\"$PORT_STATUS\",\"ping_master_status\":\"$PING_MASTER_STATUS\",\"lag_bytes\":${LAG_BYTES:-null},\"threshold_bytes\":$THRESHOLD_BYTES,\"replication_delay\":${REPLICATION_DELAY:-null},\"threshold_seconds\":$THRESHOLD_SECONDS}"

else
    STATUS="OUT_OF_SYNC"
    OUTPUT="{\"role\":\"unknown\",\"timestamp\":\"$TIMESTAMP\",\"status\":\"$STATUS\",\"port_status\":\"$PORT_STATUS\",\"ping_master_status\":\"$PING_MASTER_STATUS\"}"
fi

echo "$OUTPUT"
[ "$STATUS" == "OUT_OF_SYNC" ] && exit 1 || exit 0
