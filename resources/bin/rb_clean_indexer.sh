#!/usr/bin/env bash

#######################################################################
# Copyright (c) 2025 ENEO Tecnología S.L.
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

set -euo pipefail

RED="\033[0;31m"
YELLOW="\033[0;33m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m"

DRUID_ROUTER="http://druid-router.service:8888"

auto_confirm="false"
supervisor_filter=""
action="both"

usage() {
  echo -e "${BLUE}Usage:${NC} ${0##*/} [-y] [-s supervisor_id] [-a action]"
  cat <<EOF
Options:
  -y               Auto-confirm all actions
  -s supervisor_id Target a specific supervisor (defaults to all)
  -a action        Action to perform: reset, resetOffsets, or both (default: both)
  -h               Show this help message and exit
EOF
  exit 1
}

while getopts ":ys:a:h" opt; do
  case $opt in
    y) auto_confirm="true" ;;
    s) supervisor_filter="${OPTARG}" ;;
    a)
      case ${OPTARG} in
        reset|resetOffsets|both) action="${OPTARG}" ;;
        *) echo -e "${RED}Error:${NC} Invalid action: ${OPTARG}" >&2; usage ;;
      esac
      ;;
    h) usage ;;
    :) echo -e "${RED}Error:${NC} Option -${OPTARG} requires an argument." >&2; usage ;;
    \?) echo -e "${RED}Error:${NC} Unknown option: -${OPTARG}" >&2; usage ;;
  esac
done

if [[ "$action" == "resetOffsets" || "$action" == "both" ]]; then
  echo -e "\n${YELLOW}WARNING:${NC} This will remove all Kafka offsets for the chosen supervisors – data ingestion state will be lost!"
  if [[ "$auto_confirm" != "true" ]]; then
    read -r -p "Do you want to continue? [y/N] " confirm_warn
    case "$confirm_warn" in
      [Yy]*) echo -e "${BLUE}Proceeding...${NC}\n" ;;
      *) echo -e "${RED}Aborting.${NC}"; exit 1 ;;
    esac
  else
    echo -e "${BLUE}Auto-confirm enabled: proceeding...${NC}\n"
  fi
fi

mapfile -t all_supervisors < <(curl -fsS "${DRUID_ROUTER}/druid/indexer/v1/supervisor" | jq -r '.[]')
if [[ ${#all_supervisors[@]} -eq 0 ]]; then
  echo -e "${RED}Error:${NC} No supervisors found or cannot reach Druid Router!"
  exit 1
fi

if [[ -n "$supervisor_filter" ]]; then
  supervisors=("$supervisor_filter")
else
  supervisors=("${all_supervisors[@]}")
fi

echo -e "${BLUE}Supervisors to process:${NC} ${supervisors[*]}"

perform_action() {
  local id="$1" act="$2" url
  case $act in
    reset)
      url="${DRUID_ROUTER}/druid/indexer/v1/supervisor/${id}/reset" ;;
    resetOffsets)
      url="${DRUID_ROUTER}/druid/indexer/v1/supervisor/${id}/resetOffsets" ;;
    both)
      curl -fsS -X POST -H "Content-Type: application/json" "${DRUID_ROUTER}/druid/indexer/v1/supervisor/${id}/reset" > /dev/null
      url="${DRUID_ROUTER}/druid/indexer/v1/supervisor/${id}/resetOffsets" ;;
    *) return 1 ;;
  esac
  curl -fsS -X POST -H "Content-Type: application/json" "$url" > /dev/null
}

for sup in "${supervisors[@]}"; do
  echo -e "\n${BLUE}== Supervisor:${NC} ${sup} =="

  if [[ "$auto_confirm" != "true" ]]; then
    read -r -p "Proceed with '${action}' for '${sup}'? [y/N] " ans
    case "$ans" in
      [Yy]*) echo -e "${BLUE}Executing...${NC}" ;;
      *) echo -e "${YELLOW}Skipping ${sup}.${NC}"; continue ;;
    esac
  else
    echo -e "${BLUE}Auto-confirm: executing '${action}' for '${sup}'...${NC}"  
  fi

  if perform_action "$sup" "$action"; then
    echo -e "${GREEN}Success:${NC} Completed '${action}' for '${sup}'"
  else
    echo -e "${RED}Error:${NC} Failed to perform '${action}' on '${sup}'"
  fi
done