def get_consul_members_status
  `consul members | sed '1d' | awk '{print $1" "$2" "$3}'`.split("\n")
end

def service_registered?(service)
  `curl -X GET http://localhost:8500/v1/catalog/service/#{service}`
end