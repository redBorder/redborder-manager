require 'chef'

def get_time_from_last_run(node_name)
  node = Chef::Node.load(node_name)
  puts node[:lastrun]
end