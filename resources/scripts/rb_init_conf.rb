#!/usr/bin/env ruby

# Run initial server configuration from /etc/redborder/rb_init_conf.yml
# 1. Set hostname + cdomain
# 2. Configure network (on-premise only)
# 3. Configure dns (on-premise only)
# 4. Create serf configuration files
#
# note: Don't calculate encrypt_key

require 'yaml'
require 'ipaddr'
require 'netaddr'
require 'system/getifaddrs'
require 'json'
require File.join(ENV['RBLIB'].nil? ? '/usr/lib/redborder/lib' : ENV['RBLIB'],'rb_config_utils.rb')

RBETC = ENV['RBETC'].nil? ? '/etc/redborder' : ENV['RBETC']
INITCONF="#{RBETC}/rb_init_conf.yml"

init_conf = YAML.load_file(INITCONF)

management_interface = init_conf['network']['management_interface'] if init_conf['network'] && init_conf['network']['management_interface']
hostname = init_conf['hostname']
cdomain = init_conf['cdomain']
network = init_conf['network']
serf = init_conf['serf']
mode = init_conf['mode']

# Create file with bash env variables
open("/etc/redborder/rb_init_conf.conf", "w") { |f|
  f.puts "#REBORDER ENV VARIABLES"
  if init_conf.has_key?("elasticache")
    f.puts "ELASTICACHE_ADDRESS=#{init_conf["elasticache"]["cfg_address"]}" if init_conf["elasticache"].has_key?("cfg_address")
    f.puts "ELASTICACHE_PORT=#{init_conf["elasticache"]["cfg_port"]}" if init_conf["elasticache"].has_key?("cfg_port")
  end
}

# Configure HOSTNAME and CDOMAIN
if Config_utils.check_hostname(hostname)
  if Config_utils.check_domain(cdomain)
    system("hostnamectl set-hostname #{hostname}.#{cdomain}")
    # Set cdomain file
    File.open("/etc/redborder/cdomain", 'w') { |f| f.puts "#{cdomain}" }
    # Also set hostname with this IP in /etc/hosts
    File.open("/etc/hosts", 'a') { |f| f.puts "127.0.0.1  #{hostname} #{hostname}.#{cdomain}" } unless File.open("/etc/hosts").grep(/#{hostname}/).any?
  else
    p err_msg = "Invalid cdomain. Please review #{INITCONF} file"
    exit 1
  end
else
  p err_msg = "Invalid hostname. Please review #{INITCONF} file"
  exit 1
end

unless network.nil? # network will not be defined in cloud deployments

  # Disable and stop NetworkManager
  system('systemctl disable NetworkManager &> /dev/null')
  system('systemctl stop NetworkManager &> /dev/null')

  system('systemctl enable network &> /dev/null')
  system('systemctl start network &> /dev/null')

  # Configure DNS
  unless network['dns'].nil?
    dns = network['dns']
    open("/etc/sysconfig/network", "w") { |f|
      dns.each_with_index do |dns_ip, i|
        if Config_utils.check_ipv4({:ip => dns_ip})
          f.puts "DNS#{i+1}=#{dns_ip}"
        else
          p err_msg = "Invalid DNS Address. Please review #{INITCONF} file"
          exit 1
        end
      end
      f.puts "SEARCH=#{cdomain}"
    }
  end

  # Configure NETWORK
  network['interfaces'].each do |iface|
    dev = iface['device']
    iface_mode = iface['mode']
    open("/etc/sysconfig/network-scripts/ifcfg-#{dev}", 'w') { |f|
      # Commom configuration to all interfaces
      f.puts "BOOTPROTO=#{iface_mode}"
      f.puts "DEVICE=#{dev}"
      f.puts "ONBOOT=yes"
      dev_uuid = File.read("/proc/sys/kernel/random/uuid").chomp
      f.puts "UUID=#{dev_uuid}"

      if iface_mode != 'dhcp'
          # Specific handling for static and management interfaces
        if dev == management_interface || Config_utils.check_ipv4(ip: iface['ip'], netmask: iface['netmask'], gateway: iface['gateway'])
          f.puts "IPADDR=#{iface['ip']}" if iface['ip']
          f.puts "NETMASK=#{iface['netmask']}" if iface['netmask']
          unless iface['gateway'].nil? or iface['gateway'].empty? or not Config_utils.check_ipv4(:ip => iface['gateway'])
            if network['interfaces'].count > 1 and not Config_utils.network_contains(serf['sync_net'], iface['gateway'])
              f.puts "GATEWAY=#{iface['gateway']}"
            elsif network['interfaces'].count == 1
              f.puts "GATEWAY=#{iface['gateway']}"
            end

            if dev == management_interface
              f.puts "DEFROUTE=yes"
            else
              f.puts "DEFROUTE=no"
            end

          end
        else
          p err_msg = "Invalid network configuration for device #{dev}. Please review #{INITCONF} file"
          exit 1
        end
      else
        interface_info=Config_utils.get_ipv4_network(iface['device'])
        ip=interface_info[:ip]
        if network['interfaces'].count >= 1
          if dev == management_interface
            f.puts "DEFROUTE=yes"
          else
            f.puts "DEFROUTE=no"
          end
        end
      end
    }

    # if we have management and sync network
    # define the routing tables for each interface
    if network['interfaces'].count > 1
      if iface['mode'] == "dhcp"
        interface_info=Config_utils.get_ipv4_network(iface['device'])
        ip=interface_info[:ip]
        netmask=interface_info[:netmask]
        gateway=Config_utils.get_gateway(iface['device'])
      else
        ip=iface['ip']
        netmask=iface['netmask']
        gateway=iface['gateway'] unless iface['gateway'].nil? or iface['gateway'].empty?
      end

      # No extra configuration is require if the interface has no IP/Netmask (for now)
      next unless ip && !ip.empty?

      management_iface_info = network['interfaces'].find { |i| i['device'] == management_interface }
      if management_iface_info && Config_utils.network_contains(serf['sync_net'], management_iface_info['ip'])
        # Management and sync are on the same network, treat as single interface
        open("/etc/sysconfig/network-scripts/route-#{dev}", 'w') { |f|
          f.puts "default via #{gateway} dev #{iface['device']}" unless gateway.nil? or gateway.empty?
        }
      else
        metric = Config_utils.network_contains(serf['sync_net'], ip) ? 101 : 100
        cidr = Config_utils.to_cidr_mask(netmask)
        iprange = Config_utils.serialize_ipaddr(ip + cidr)

        open("/etc/iproute2/rt_tables", 'a') { |f|
          f.puts "#{metric} #{iface['device']}tbl"
        }
        open("/etc/sysconfig/network-scripts/route-#{dev}", 'w') { |f|
          if dev == management_interface
            f.puts "default via #{gateway} dev #{iface['device']} table #{iface['device']}tbl" unless gateway.nil? or gateway.empty?
          end
          f.puts "#{iprange} dev #{iface['device']} table #{iface['device']}tbl"
          f.puts "#{iprange} dev #{iface['device']} table main"
        }
        open("/etc/sysconfig/network-scripts/rule-#{dev}", 'w') { |f|
          f.puts "from #{iprange} table #{iface['device']}tbl"
        }
      end
    end
  end

  # Enable network service
  system('ip route flush table main &> /dev/null')
  system('systemctl restart network &> /dev/null')
end

# TODO: check network connectivity. Try to resolve repo.redborder.com

####################
# Set UTC timezone #
####################

system("timedatectl set-timezone UTC")
#system("ntpdate pool.ntp.org")

######################
# Serf configuration #
######################
SERFJSON="/etc/serf/00first.json"
TAGSJSON="/etc/serf/tags"
SERFSNAPSHOT="/etc/serf/snapshot"

serf_conf = {}
serf_tags = {}
sync_interface = ""
sync_net = serf['sync_net']
encrypt_key = serf['encrypt_key']
multicast = serf['multicast']

# local IP to bind to
unless sync_net.nil? || sync_net.empty?
    # Initialize network device
    System.get_all_ifaddrs.each do |netdev|
        if IPAddr.new(sync_net).include?(netdev[:inet_addr])
            serf_conf["bind"] = netdev[:inet_addr].to_s
            sync_interface = netdev[:interface]
        end
    end
    if serf_conf["bind"].nil?
        p "Error: no IP address to bind"
        exit 1
    end
else
  p "Error: unknown sync network"
  exit 1
end

if multicast # Multicast configuration
  serf_conf["discover"] = cdomain
end

unless encrypt_key.nil?
  serf_conf["encrypt_key"] = encrypt_key
end

serf_conf["tags_file"] = TAGSJSON
serf_conf["node_name"] = hostname
serf_conf["snapshot_path"] = SERFSNAPSHOT
serf_conf["rejoin_after_leave"] = true

# defined role in tags
serf_tags["mode"] = mode

# Create json file configuration
file_serf_conf = File.open(SERFJSON,"w")
file_serf_conf.write(serf_conf.to_json)
file_serf_conf.close

# Create json tags file
file_serf_tags = File.open(TAGSJSON,"w")
file_serf_tags.write(serf_tags.to_json)
file_serf_tags.close

# stop firewall till chef-client install and run the cookbook-rb-firewall
# this allow serf/consul communication while leader is in "configuring" state
system("systemctl stop firewalld &>/dev/null")

# TODO: maybe we should stop using rc.local and start using systemd for this
# Configure rc.local scripts
system("chmod a+x /etc/rc.d/rc.local")
# Stop chef-server-ctl when system boots
system ("echo /usr/lib/redborder/bin/rb_chef_server_ctl_stop.sh >> /etc/rc.d/rc.local")

# Upgrade system
system('yum install systemd -y')

# Enable and start SERF
system('systemctl enable serf &> /dev/null')
system('systemctl start serf &> /dev/null')
# wait a moment before start serf-join to ensure connectivity
sleep(3)
system('systemctl start rb-bootstrap &> /dev/null')
