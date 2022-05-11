def logit(text)
  printf("%s\n", text)
end

def print_ok(text="", colorless, quiet)
  unless quiet
    spec_char = text.count('%')/2
    printf(text)
    printf("%*c", 94 + spec_char - text.size, ' ')
    unless colorless
      printf("[ \e[32m OK \e[0m ]\n")
    else
      printf("[  OK  ]\n")
    end
  end
end

def print_error(text="", colorless, quiet)
  unless quiet
    spec_char = text.count('%')/2
    printf(text)
    printf("%*c", 94 + spec_char - text.size, ' ')
    unless colorless
      printf("[\e[31mFAILED\e[0m]\n")
    else
      printf("[FAILED]\n")
    end
  end
end

def title_ok(text, colorless, quiet)
  unless quiet
    unless colorless
      printf("\e[36m######################################################################################################\n#")
      printf("\e[34m %s\e[36m\n", text)
      printf("######################################################################################################\e[0m\n")
    else
      printf("######################################################################################################\n#")
      printf(" %s\n", text)
      printf("######################################################################################################\n")
    end
  end
end

def title_error(text, colorless, quiet)
  unless quiet
    unless colorless
      printf("\e[31m######################################################################################################\n#")
      printf("\e[1m\e[31m %s\e[0m\e[31m\n", text)
      printf("######################################################################################################\e[0m\n")
    else
      printf("######################################################################################################\n#")
      printf(" %s \n", text)
      printf("######################################################################################################\n")
    end
  end
end

def get_nodes_with_service(service=nil)
  utils = Utils.instance
  members = utils.get_consul_members
  nodes = []

  if services.nil?
    nodes = members
  else
    members.each do |node|
      node_info = utils.get_node(node)
      node_services = node_info.attributes.redborder.services
      nodes.push(service) if node_services.include? service
    end
  end

  nodes
end

def get_service_status(service,node)
  service_status = 1

  if ["barnyard","snort"].include? service
    #TODO
  else
    service_state = `/usr/lib/redborder/bin/rb_manager_utils.sh -e -n #{node} -s "systemctl show #{service} -p ActiveState"`
    service_state = service_state.gsub("ActiveState=","").gsub("\n","")
    service_status = 0 if service_state == "active"
  end
  service_status
end

def print_service_status(service, node, status, colorless, quiet)

  if status == 0
    print_ok(text="Service #{service} is running on node #{node}.", colorless, quiet)
  else
    print_error(text="Service #{service} is not running on #{node} and it should.", colorless, quiet)
  end
end

def print_command_output(output, return_value, colorless, quiet)
  if return_value == 0
    print_ok(text=output, colorless, quiet)
  else
    print_error(text=output, colorless, quiet)
  end
end



def check_service(service)
  result = []
  ret_value = []
  case service


  when "druid-coordinator"
    command = `/usr/lib/redborder/scripts/rb_get_druid_coordinators.rb`
    command_return = $?.to_s.split(" ")[3].to_i
    result.push(command)
    ret_value.push(command_return)



  when "druid-broker"
    command = `/usr/lib/redborder/scripts/rb_get_druid_brokers.rb`
    command_return = $?.to_s.split(" ")[3].to_i
    result.push(command)
    ret_value.push(command_return)



  when "druid-historical"
    command = `/usr/lib/redborder/scripts/rb_get_druid_historicals.rb`
    command_return = $?.to_s.split(" ")[3].to_i
    result.push(command)
    ret_value.push(command_return)



  when "druid-realtime"
    command = `/usr/lib/redborder/scripts/rb_get_druid_historicals.rb`
    command_return = $?.to_s.split(" ")[3].to_i
    result.push(command)
    ret_value.push(command_return)



  when "zookeeper"
    command = `echo '' | zkCli.sh -server zookeeper.service:2181 | head -n 1`.gsub("\n","")
    command_return = $?.to_s.split(" ")[3].to_i
    result.push("  " + command)
    ret_value.push(command_return)


  when "memcached"
  else
    return ret_value, result
  end

  [ret_value, result]
end


