#!/bin/bash

# ================================
# Script to generate a YAML file mapping MAC → type_id from PostgreSQL
# Usage:
#   ./rb_create_mac_asset_type_yaml.sh [output_file]
#   ./rb_create_mac_asset_type_yaml.sh -h
# ================================

# Show help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
Usage:
  $0 [output_path]

Description:
  This script queries the PostgreSQL database using rb_psql,
  extracts MAC addresses and their corresponding type_id,
  and generates a YAML file that can be used by Logstash for event enrichment.

Arguments:
  output_path   Optional path to save the generated YAML file.
                Default: mac_to_asset_type.yaml

Example:
  $0 /etc/logstash/mac_to_asset_type.yaml
EOF
  exit 0
fi

# Output file path parameter (optional)
OUTPUT_FILE=${1:-/etc/logstash/mac_to_asset_type_id.yaml}

# Run query and process output
echo "Generating file $OUTPUT_FILE..."

QUERY_RESULT=$(echo "SELECT r.value AS mac, t.id AS type_id FROM redborder_objects r JOIN inventory_device_type_objects t ON r.inventory_device_id = t.id WHERE r.type = 'MacObject'" | rb_psql redborder 2>&1)
if [ $? -ne 0 ]; then
  echo "Error executing SQL query:"
  echo "$QUERY_RESULT"
  exit 1
fi

echo "$QUERY_RESULT" | awk -v outfile="$OUTPUT_FILE" '
BEGIN { print "---" > outfile }
/^[[:space:]]*([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);  # trim
    split($0, arr, "|");
    mac=arr[1]; gsub(/^[ \t]+|[ \t]+$/, "", mac);
    id=arr[2]; gsub(/^[ \t]+|[ \t]+$/, "", id);
    printf "\"%s\": \"%s\"\n", mac, id >> outfile
}
'
if [ $? -ne 0 ]; then
  echo "Error processing output of the YAML."
  exit 1
fi

echo "File generated: $OUTPUT_FILE"
exit 0

