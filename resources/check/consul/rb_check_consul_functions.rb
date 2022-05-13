def get_consul_members_status
  `consul members | awk '{print $1" "$2" "$3}'`.split("\n")
end