#!/bin/bash
#######################################################################
# Copyright (c) 2026 ENEO Tecnología S.L.
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
#
# Shows the status of the SeaweedFS cluster (the S3 service of the managers): this node, the
# masters (Raft), filers, volume servers, replication, connectivity and buckets.
# Exit code: 0 everything OK, 1 warnings, 2 errors.

SCRIPT=$(basename "$0")
WEED=/usr/bin/weed
S3_PORT=8333
VERBOSE=0
WARNINGS=0
ERRORS=0

usage() {
  echo "Shows the status of the SeaweedFS (S3) cluster"
  echo ""
  echo "Usage: $SCRIPT [-v] [-m <master ip:port>]"
  echo "  -v  also show the raw output of the weed shell commands"
  echo "  -m  master to ask (default: the masters of /etc/default/seaweedfs-volume)"
  echo "  -h  show this help"
}

if [ -t 1 ]; then
  GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; BOLD="\033[1m"; NORM="\033[0m"
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; NORM=""
fi

title() { echo -e "\n${BOLD}$1${NORM}"; }
ok()    { printf "  %-34s ${GREEN}%s${NORM}\n" "$1" "$2"; }
warn()  { printf "  %-34s ${YELLOW}%s${NORM}\n" "$1" "$2"; WARNINGS=$((WARNINGS + 1)); }
err()   { printf "  %-34s ${RED}%s${NORM}\n" "$1" "$2"; ERRORS=$((ERRORS + 1)); }
info()  { printf "  %-34s %s\n" "$1" "$2"; }

human() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0}B"; }

# Runs one weed shell command against the masters
weed_shell() {
  printf '%s\n' "$1" | timeout 60 "$WEED" shell -master="$MASTERS" 2>/dev/null
}

option_of() { # option_of <unit> <option> : value of -<option>= in /etc/default/<unit>
  grep -oE "(^|[ \"])-$2=[^ \"]+" "/etc/default/$1" 2>/dev/null | head -1 | sed "s/.*-$2=//"
}

while getopts "vm:h" opt; do
  case $opt in
    v) VERBOSE=1 ;;
    m) MASTERS="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "This script must be run as root (it reads /etc/seaweedfs/security.toml)"; exit 2; }
[ -x "$WEED" ] || { echo "SeaweedFS is not installed in this node (redborder-seaweedfs)"; exit 2; }

[ -z "$MASTERS" ] && MASTERS=$(option_of seaweedfs-volume mserver)
[ -z "$MASTERS" ] && MASTERS=$(option_of seaweedfs-filer master)

echo -e "${BOLD}SeaweedFS status in $(hostname -s) - $(date '+%Y-%m-%d %H:%M:%S')${NORM}"

# ======================
# THIS NODE
# ======================
title "This node"
for unit in seaweedfs-master seaweedfs-volume seaweedfs-filer; do
  enabled=$(systemctl is-enabled "$unit" 2>/dev/null)
  active=$(systemctl is-active "$unit" 2>/dev/null)
  if [ "$enabled" != "enabled" ]; then
    info "$unit" "not enabled in this node"
  elif [ "$active" == "active" ]; then
    ok "$unit" "running (since $(systemctl show "$unit" -p ActiveEnterTimestamp --value | awk '{print $2, $3}'))"
  else
    err "$unit" "$active"
  fi
done

IP=$(option_of seaweedfs-filer ip)
if systemctl is-enabled --quiet seaweedfs-filer 2>/dev/null; then
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://${IP:-127.0.0.1}:$S3_PORT/" 2>/dev/null)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    ok "S3 gateway ${IP:-127.0.0.1}:$S3_PORT" "answering (HTTP $code)"
  else
    err "S3 gateway ${IP:-127.0.0.1}:$S3_PORT" "not answering"
  fi
fi

if [ -d /var/lib/seaweedfs ]; then
  used=$(du -sb /var/lib/seaweedfs 2>/dev/null | awk '{print $1}')
  read -r size avail pct < <(df -B1 --output=size,avail,pcent /var/lib/seaweedfs | tail -1)
  msg="$(human "$used") used by SeaweedFS, $(human "$avail") free of $(human "$size") (${pct} used)"
  if [ "${pct%\%}" -ge 90 ]; then err "Disk /var/lib/seaweedfs" "$msg"
  elif [ "${pct%\%}" -ge 80 ]; then warn "Disk /var/lib/seaweedfs" "$msg"
  else ok "Disk /var/lib/seaweedfs" "$msg"; fi
fi

consul=$(curl -s -m 5 "http://localhost:8500/v1/health/service/s3" 2>/dev/null |
  python3 -c 'import json,sys
try:
    print(" ".join("%s:%s(%s)" % (x["Node"]["Node"], x["Service"]["Port"], x["Checks"][0]["Status"]) for x in json.load(sys.stdin)))
except Exception:
    pass' 2>/dev/null)
if [ -z "$consul" ]; then
  warn "Consul service s3" "not registered (or Consul not available)"
elif echo "$consul" | grep -qvE '^([^ ]+:8333\(passing\) ?)+$'; then
  warn "Consul service s3" "$consul"
else
  ok "Consul service s3" "$consul"
fi

if [ -z "$MASTERS" ]; then
  err "Masters" "unknown: this node has no /etc/default/seaweedfs-volume (use -m <ip:port>)"
  echo
  exit 2
fi

# ======================
# CLUSTER
# ======================
# The weed shell commands run in parallel (each one takes a few seconds)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
weed_shell cluster.raft.ps > "$TMP/raft" &
weed_shell cluster.ps > "$TMP/ps" &
weed_shell cluster.check > "$TMP/check" &
weed_shell volume.list > "$TMP/volumes" &
weed_shell s3.bucket.list > "$TMP/buckets" &
wait
RAFT=$(cat "$TMP/raft"); PS=$(cat "$TMP/ps"); CHECK=$(cat "$TMP/check")
VOLUMES=$(cat "$TMP/volumes"); BUCKETS=$(cat "$TMP/buckets")

title "Masters (Raft) - $MASTERS"
if [ -z "$RAFT" ]; then
  err "Masters" "no answer from $MASTERS"
else
  total=$(echo "$RAFT" | grep -oE 'has [0-9]+ servers' | grep -oE '[0-9]+')
  leader=$(echo "$RAFT" | grep '(Leader)' | awk '{print $2}')
  echo "$RAFT" | grep -E '^\s+\*' | while read -r _ http _ role; do
    info "$http" "${role:-(Follower)}"
  done
  if [ -n "$leader" ]; then
    ok "Leader" "$leader ($total master$([ "${total:-0}" -ne 1 ] && echo s))"
  else
    err "Leader" "no leader: the cluster cannot write"
  fi
  [ "${total:-0}" -eq 2 ] && warn "Quorum" "2 masters: losing one stops the cluster (use 1 or 3)"
fi

title "Filers (filer + S3 gateway)"
filers=$(echo "$PS" | awk '/^\* filers /{f=1; next} /^\* /{f=0} f && /^  \* /{print $2}')
if [ -z "$filers" ]; then
  err "Filers" "none registered"
else
  # Filers are listed as <ip>:<http port>.<grpc port>
  for f in $filers; do ok "${f%.*}" "version $(echo "$PS" | grep -F "$f (" | head -1 | grep -oE '\([^)]*\)' | head -1 | awk '{print $2}')"; done
  # Last metadata change each filer received from the others
  echo "$PS" | awk '/metadata sync time/{dst=$3} /^    [0-9]/ && dst {print dst, $1, $2, $3}' |
    while read -r dst src day time; do
      info "  metadata ${src%.*} -> ${dst%.*}" "last change received $day ${time%%.*}"
    done
fi
s3servers=$(echo "$PS" | grep -oE '^\* s3 servers [0-9]+' | grep -oE '[0-9]+$')
info "S3 gateways registered" "${s3servers:-0}"

title "Volume servers"
nodes=$(echo "$VOLUMES" | grep -E '^\s+DataNode .*hdd\(')
if [ -z "$nodes" ]; then
  err "Volume servers" "none in the topology"
else
  echo "$nodes" | while read -r _ addr usage; do
    used=$(echo "$usage" | grep -oE 'volume:[0-9]+/[0-9]+' | cut -d: -f2)
    ok "$addr" "volumes $used ($(echo "$usage" | grep -oE 'free:[0-9]+' | cut -d: -f2) slots free)"
  done
fi
nfilers=$(echo "$filers" | grep -c .)
nvolumes=$(echo "$nodes" | grep -c .)
[ "$nfilers" -ne "$nvolumes" ] && warn "Filers / volume servers" "$nfilers filers but $nvolumes volume servers"

title "Replication"
replication=$(option_of seaweedfs-filer defaultReplicaPlacement)
info "Configured replication" "${replication:-unknown} ($([ "$replication" == "000" ] && echo "1 copy" || echo "2 copies in different managers"))"
# Copies of each volume in volume.list against the ones its ReplicaPlacement asks for
# (xyz: x + y + z + 1 copies, 001 = 2)
under=$(echo "$VOLUMES" | grep -oE 'volume Id:[0-9]+, .*ReplicaPlacement:[0-9]{3}' |
  sed -E 's/volume Id:([0-9]+),.*ReplicaPlacement:([0-9]{3})/\1 \2/' |
  awk '{n[$1]++; r=$2; want[$1]=substr(r,1,1)+substr(r,2,1)+substr(r,3,1)+1}
       END {c=0; for (v in n) if (n[v] < want[v]) c++; print c}')
if [ -z "$VOLUMES" ]; then
  warn "Under replicated volumes" "unknown (volume.list did not answer)"
elif [ "$under" -gt 0 ]; then
  err "Under replicated volumes" "$under"
  if [ "$nfilers" -gt "$nvolumes" ]; then
    info "" "a volume server is missing: start it, its replicas come back with it"
  else
    info "" "copy the missing replicas: printf 'lock\\nvolume.fix.replication -apply\\nunlock\\n' | weed shell -master=$MASTERS"
  fi
else
  ok "Under replicated volumes" "0"
fi
ro=$(echo "$VOLUMES" | grep -c "ReadOnly:true")
if [ "$ro" -gt 0 ]; then
  warn "Read only volumes" "$ro (full disk or volume size limit reached)"
else
  ok "Read only volumes" "0"
fi
total_volumes=$(echo "$VOLUMES" | grep -oE 'Topology .*hdd\(volume:[0-9]+' | grep -oE '[0-9]+$')
info "Volumes (with replicas)" "${total_volumes:-0}"

title "Garbage (deleted data not reclaimed yet)"
# A deleted object only marks its bytes as deleted inside the volume: the masters compact (vacuum)
# a volume when its deleted bytes go over garbageThreshold, every vacuumIntervalSeconds
threshold=$(option_of seaweedfs-master garbageThreshold); threshold=${threshold:-0.3}
interval=$(option_of seaweedfs-master vacuumIntervalSeconds); interval=${interval:-840}
# Sum of all the copies: <deleted bytes> <total bytes> <copies over the threshold> <copies with garbage>
read -r g_deleted g_size g_over g_some < <(echo "$VOLUMES" | grep -E 'volume Id:[0-9]+, ' |
  sed -E 's/.* Size:([0-9]+),.*DeletedByteCount:([0-9]+),.*/\1 \2/' |
  awk -v t="$threshold" '{s+=$1; d+=$2; if ($2 > 0) some++; if ($1 > 0 && $2 / $1 > t) over++}
       END {printf "%d %d %d %d\n", d, s, over, some}')
if [ -z "$VOLUMES" ]; then
  warn "Garbage" "unknown (volume.list did not answer)"
else
  g_pct=$(awk -v d="${g_deleted:-0}" -v s="${g_size:-0}" 'BEGIN {printf "%.1f", (s > 0) ? d * 100 / s : 0}')
  msg="$(human "${g_deleted:-0}") of $(human "${g_size:-0}") stored (${g_pct}%) in ${g_some:-0} volume copies"
  if [ "${g_over:-0}" -gt 0 ]; then
    # Not a warning: it is the normal state after deleting data until the next vacuum sweep
    info "Garbage" "$msg"
    info "Over the vacuum threshold" "${g_over} volume copies (> $(awk -v t="$threshold" 'BEGIN {print t * 100}')%), compacted automatically within $((interval / 60)) min"
  else
    ok "Garbage" "$msg"
    info "Vacuum threshold" "$(awk -v t="$threshold" 'BEGIN {print t * 100}')% per volume, checked every $((interval / 60)) min"
  fi
  # volume.list shows the stats of the last heartbeat of each volume server: after a vacuum the
  # numbers take about a minute to go down
  [ "${g_deleted:-0}" -gt 0 ] &&
    info "" "reclaim it now: printf 'lock\\nvolume.vacuum -garbageThreshold 0.01\\nunlock\\n' | weed shell -master=$MASTERS"
fi

title "Connectivity (cluster.check)"
checks_ok=$(echo "$CHECK" | grep -c '\.\.\. ok')
checks_failed=$(echo "$CHECK" | grep -E '^checking ' | grep -vc '\.\.\. ok')
if [ -z "$CHECK" ]; then
  err "Checks" "cluster.check did not answer"
elif [ "$checks_failed" -gt 0 ]; then
  err "Checks" "$checks_ok ok, $checks_failed failed:"
  echo "$CHECK" | grep -E '^checking ' | grep -v '\.\.\. ok' | sed 's/^/    /'
else
  ok "Checks" "$checks_ok ok (master, volume servers and filers reach each other)"
fi
skew=$(echo "$CHECK" | grep -oE 'clock delta -?[0-9.]+(ms|s)' | awk '{v=$3; if (v ~ /ms$/) {sub("ms","",v); v=v/1000} else sub("s","",v); if (v<0) v=-v; if (v>m) m=v} END {printf "%.3f", m+0}')
if awk "BEGIN {exit !(${skew:-0} > 1)}"; then
  warn "Clock skew" "${skew}s between nodes (check chrony)"
else
  info "Clock skew" "${skew:-0}s max"
fi

title "Buckets"
if [ -z "$BUCKETS" ]; then
  warn "Buckets" "s3.bucket.list did not answer"
else
  echo "$BUCKETS" | grep -E 'size:' | while read -r name rest; do
    size=$(echo "$rest" | grep -oE '^size:[0-9]+' | cut -d: -f2)
    logical=$(echo "$rest" | grep -oE 'logical:[0-9]+' | cut -d: -f2)
    chunks=$(echo "$rest" | grep -oE 'chunk:[0-9]+' | cut -d: -f2)
    info "$name" "$(human "$logical") of data, $(human "$size") on disk, $chunks chunks"
  done
fi

if [ $VERBOSE -eq 1 ]; then
  for c in RAFT PS CHECK BUCKETS; do
    title "weed shell: $c"
    echo "${!c}"
  done
fi

echo
if [ $ERRORS -gt 0 ]; then
  echo -e "${RED}${BOLD}ERROR${NORM}: $ERRORS errors, $WARNINGS warnings"
  exit 2
elif [ $WARNINGS -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}WARNING${NORM}: $WARNINGS warnings"
  exit 1
fi
echo -e "${GREEN}${BOLD}OK${NORM}: the SeaweedFS cluster is healthy"
exit 0
