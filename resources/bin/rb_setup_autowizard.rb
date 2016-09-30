#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'net/ip'
require 'netaddr'
require 'arp_scan'
require File.join(ENV['RBDIR'].nil? ? '/usr/lib/redborder' : ENV['RBDIR'],'lib/rb_config_utils.rb')

CONFFILE = "#{ENV['RBETC']}/rb_init_conf.yml"

general_conf = {
    "hostname" => "",
    "cdomain" => "",
    "cloud" => false, 
    "network" => nil,
    "serf" => {
        "multicast" => false,
        "sync_net" => "",
        "encrypt_key" => ""
        },
    "s3" => nil,
    "mode" => "full" # default mode
    }

# Network is unnecessary to setup in autowizzard
general_conf["network"] = nil

# Set cluster domain to default
general_conf["cdomain"] = "redborder.cluster"

# set random hostname
general_conf["hostname"] = "rb-#{rand(36**10).to_s(36)}"

# look for sync network
sync_net = {}

# first, look for the first device with no default route associated
Net::IP.routes.each do |r|
	route = r.to_h
	if Config_utils.has_default_route?(route[:dev])
		next
	else
		if sync_net.empty?
			sync_net = route
		else
			x = NetAddr::CIDRv4.create(route[:prefix])
			y = NetAddr::CIDRv4.create(sync_net[:prefix])
			# we select network address with integer number bigger
			if x.to_i >= y.to_i
				sync_net = route
			end
		end
	end
end

if sync_net.empty?
	# there is no network without default route associated!
	# looking for a network with maximun metric for default
	dev = Config_utils.get_default_max_metric
	sync_net = Config_utils.get_first_route(dev)
end

if sync_net.empty?
	p "Unable to determine sync network ... exiting"
	exit(1)
end

# we don't know if multicast it is allowed, so unicast by default
general_conf["serf"]["multicast"] = false

# set the sync network to general_conf
general_conf["serf"]["sync_net"] = sync_net[:prefix]

# administrator is unable to insert any password, so we decide to encrypt based on the sync network string
general_conf["serf"]["encrypt_key"] = Config_utils.get_encrypt_key(sync_net[:prefix])

# s3 is disabled by default
general_conf["s3"] = nil

# Mode: "core" if it is the only one, in other case "custom"
if Config_utils.has_default_route?(sync_net[:dev])
	gateway = Config_utils.get_gateway(sync_net[:dev])
end
count = 3
discover = false
while count > 0
    report_arpscan = ARPScan("-I #{sync_net[:dev]} #{sync_net[:prefix]}")
    report_arpscan.hosts.each do |host|
        # avoid own local ip and gateway
        next if local_ip?(host.ip_addr)
        unless gateway.nil?
        	next if gateway == host.ip_addr
        end
        # found one host different from localip and gateway
        discover = true
    end
    break if discover
    # scan every 1 seconds
    count = count - 1
    p "Warning: no node found, trying again #{count} times" if count > 0
    sleep(1)
end

if discover
	general_conf["mode"] = "custom"
else
	general_conf["mode"] = "core"
end
