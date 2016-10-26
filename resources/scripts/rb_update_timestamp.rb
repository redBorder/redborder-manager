#!/usr/bin/env ruby

require 'chef'
require 'json'

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/opscode/admin.pem"
Chef::Config[:http_retry_count] = 5

hostname = `hostname -s`.strip
node = Chef::Node.load(hostname)
role = Chef::Role.load(hostname)

if !node.nil? and !role.nil?
  if node["redborder"] and node["redborder"]["manager"] and node["redborder"]["manager"]["mode"]=="master"
    now_utc = 0
  else
    now_utc = Time.now.getutc
  end

  role.override_attributes[:rb_time] = now_utc.to_i
  if role.save
    printf("Time '%s' saved into role[%s]\n", now_utc, hostname)
  else
    printf("ERROR: cannot save %s (UTC) saved\n", now_utc)
  end
end
