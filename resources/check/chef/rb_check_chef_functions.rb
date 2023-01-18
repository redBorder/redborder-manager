require 'chef'

def check_last_chef_run(node_name)

  Chef::Config.from_file("/etc/chef/client.rb")
  Chef::Config[:client_key] = "/etc/chef/client.pem"
  Chef::Config[:http_retry_count] = 5
  node = Chef::Node.load(node_name)
  last_chef_time = Time.at(node['ohai_time'])
  interval = node['chef-client']["interval"]
  splay =    node["chef-client"]["splay"]
  time_now = Time.new

  seconds_from_last_run = (time_now - last_chef_time).to_i.round
  if seconds_from_last_run < 3 * (interval + splay)
    [0, seconds_from_last_run, interval, splay]
  else
    [1, seconds_from_last_run, interval, splay]
  end
end