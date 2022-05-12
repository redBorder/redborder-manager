require 'chef'

def logit(text)
  printf("%s\n", text)
end

def subtitle(text, colorless, quiet)
  unless quiet
    if colorless
      logit(text)
    else
      logit("\e[1m#{text}\e[0m")
    end
  end
end

def print_ok(text="", colorless, quiet)
  unless quiet
    spec_char = text.count('%')/2
    printf(text)
    printf("%*c", 94 + spec_char - text.size, ' ')
    if colorless
      printf("[  OK  ]\n")
    else
      printf("[ \e[32m OK \e[0m ]\n")
    end
  end
end

def print_error(text="", colorless, quiet)
  unless quiet
    spec_char = text.count('%')/2
    printf(text)
    printf("%*c", 94 + spec_char - text.size, ' ')
    if colorless
      printf("[FAILED]\n")
    else
      printf("[\e[31mFAILED\e[0m]\n")
    end
  end
end

def title_ok(text, colorless, quiet)
  unless quiet
    if colorless
      printf("######################################################################################################\n#")
      printf(" %s\n", text)
      printf("######################################################################################################\n")
    else
      printf("\e[36m######################################################################################################\n#")
      printf("\e[34m %s\e[36m\n", text)
      printf("######################################################################################################\e[0m\n")
    end
  end
end

def title_error(text, colorless, quiet)
  unless quiet
    if colorless
      printf("######################################################################################################\n#")
      printf(" %s \n", text)
      printf("######################################################################################################\n")
    else
      printf("\e[31m######################################################################################################\n#")
      printf("\e[1m\e[31m %s\e[0m\e[31m\n", text)
      printf("######################################################################################################\e[0m\n")
    end
  end
end

def execute_command_on_node(node, command)
  `/usr/lib/redborder/bin/rb_manager_utils.sh -e -n #{node} -s "#{command}"`
end

def get_consul_members
  nodes = []
  uri = URI.parse("http://localhost:8500/v1/agent/members")
  response = Net::HTTP.get_response(uri)
  if response.code == "200"
    ret = JSON.parse(response.body)
    ret.map { |member| nodes << member["Name"]}
  end
  nodes
end

def get_node(node_name)
  Chef::Config.from_file("/etc/chef/client.rb")
  Chef::Config[:client_key] = "/etc/chef/client.pem"
  Chef::Config[:http_retry_count] = 5
  node = Chef::Node.load(node_name)
end

def get_nodes_with_service(service=nil)
  members = get_consul_members
  nodes = []

  if service.nil?
    nodes = members
  else
    members.each do |node|
      node_info = get_node(node)
      node_services = node_info.attributes.redborder.services
      nodes.push(node) if node_services.include? service
    end
  end
  nodes
end

def get_service_status(service,node)
  service_status = 1

  if ["barnyard","snort"].include? service
    #TODO
  else
    service_state = execute_command_on_node(node,"systemctl show #{service} -p ActiveState")
    service_state = service_state.gsub("ActiveState=","").gsub("\n","")
    service_status = 0 if service_state == "active"
  end
  service_status
end

def print_service_status(service, node, status, colorless, quiet)

  if status == 0
    print_ok(text="  Service #{service} is running on node #{node}.\n", colorless, quiet)
  else
    print_error(text="  Service #{service} is not running on #{node} and it should.\n", colorless, quiet)
  end
end

def print_command_output(output, return_value, colorless, quiet)
  if return_value == 0
    print_ok(text="  " + output, colorless, quiet)
  else
    print_error(text="  " + output, colorless, quiet)
  end
end

