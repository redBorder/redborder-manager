#!/bin/bash

# Usage:
# ./rb_create_asset_type_id_yaml.sh [output_file]
# ./rb_create_asset_type_id_yaml.sh -h

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
Usage:
  $0 [output_path]

Description:
  This script queries the inventory_device_type_objects table to
  generate a YAML file mapping asset_id to asset_name.

Arguments:
  output_path   Optional path where the YAML file will be saved.
                Default: asset_type.yaml

Example:
  $0 /etc/assets/mac_to_asset_type_id.yaml
EOF
  exit 0
fi

OUTPUT_FILE=${1:-/etc/assets/mac_to_asset_type_id.yaml}

echo "Generating file $OUTPUT_FILE..."

QUERY_RESULT=$(echo "SELECT id, name FROM inventory_device_type_objects" | rb_psql redborder 2>&1)
if [ $? -ne 0 ]; then
  echo "Error executing SQL query:"
  echo "$QUERY_RESULT"
  exit 1
fi

echo "$QUERY_RESULT" | awk -v outfile="$OUTPUT_FILE" '
BEGIN { print "---" > outfile }
/^[[:space:]]*[0-9]+/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
    split($0, arr, "|");
    id=arr[1]; gsub(/^[ \t]+|[ \t]+$/, "", id);
    name=arr[2]; gsub(/^[ \t]+|[ \t]+$/, "", name);
    # Escape double quotes in name if any
    gsub(/"/, "\\\"", name);
    printf "\"%s\": \"%s\"\n", id, name >> outfile
}
'
if [ $? -ne 0 ]; then
  echo "Error processing output to generate YAML."
  exit 1
fi

echo "File generated: $OUTPUT_FILE"
exit 0

