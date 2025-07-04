#!/bin/bash

# Create the directory once
mkdir -p /var/chef/data/data_bag/rBglobal

# List of IDs to generate
ids=(
  ipvirtual-external-nginx
  ipvirtual-external-f2k
  ipvirtual-external-sfacctd
  ipvirtual-external-kafka
)

# Generate each JSON file
for id in "${ids[@]}"; do
  cat > "/var/chef/data/data_bag/rBglobal/${id}.json" <<-_RBEOF_
{
  "id": "${id}"
}
_RBEOF_
done
