#!/bin/bash

# 0. Init libs and functions
usage() {
  echo "Usage: $0 [-v vip_value]"
  echo '  -v vip_value   Optional VIP argument'
  echo if no argument provided, the set of valid vips are going to be initialized
  echo "if -v argument is provided, it will migrate vip from anotther one"
  echo webui will migrate webui vip into nginx vip 
}

init_vips() {
  # Create the directory once
  mkdir -p /var/chef/data/data_bag/rBglobal

  # List of IDs to generate
  ids=(
    ipvirtual-external-nginx
    ipvirtual-external-f2k
    ipvirtual-external-sfacctd
    ipvirtual-external-kafka
    ipvirtual-internal-postgresql
  )

    # Generate each JSON file
  for id in "${ids[@]}"; do
    cat > "/var/chef/data/data_bag/rBglobal/${id}.json" <<-_RBEOF_
{
  "id": "${id}"
}
_RBEOF_
    echo "/var/chef/data/data_bag/rBglobal/${id}.json created"
  done
}

# If you update manager bellow the version that includes https://redmine.redborder.lan/issues/20693 changes
# You have to run migrate 
migrate_webui() { #...to nginx
  cp /var/chef/data/data_bag/rBglobal/ipvirtual-external-webui.json /var/chef/data/data_bag/rBglobal/ipvirtual-external-nginx.json
  sed --in-place 's/webui/nginx/g' /var/chef/data/data_bag/rBglobal/ipvirtual-external-nginx.json
  echo /var/chef/data/data_bag/rBglobal/ipvirtual-external-nginx.json created
}

# 1. Parse options
vip=''
while getopts "v:h" opt; do
  case "$opt" in
    v) vip="$OPTARG" ;;
    h) usage 
        exit 0;;
    *) usage
        exit 1;;
  esac
done
shift $((OPTIND - 1))

# 2. Run the function
if [[ "$vip" == "webui" ]]; then
  migrate_webui
else
  init_vips
fi
