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
      if iface_mode != 'dhcp'
        if Config_utils.check_ipv4({:ip => iface['ip'], :netmask => iface['netmask']})
          f.puts "IPADDR=#{iface['ip']}"
          f.puts "NETMASK=#{iface['netmask']}"
          unless iface['gateway'].nil? or iface['gateway'].empty? or not Config_utils.check_ipv4(:ip => iface['gateway'])
            if network['interfaces'].count > 1 and not Config_utils.network_contains(serf['sync_net'], iface['gateway'])
              f.puts "GATEWAY=#{iface['gateway']}"
            elsif network['interfaces'].count == 1
              f.puts "GATEWAY=#{iface['gateway']}"
            end
          end
        else
          p err_msg = "Invalid network configuration for device #{dev}. Please review #{INITCONF} file"
          exit 1
        end
      else
        interface_info=Config_utils.get_ipv4_network(iface['device'])
        ip=interface_info[:ip]
        f.puts "DEFROUTE=no" if network['interfaces'].count > 1 and Config_utils.network_contains(serf['sync_net'], ip)
      end
      dev_uuid = File.read("/proc/sys/kernel/random/uuid").chomp
      f.puts "BOOTPROTO=#{iface_mode}"
      f.puts "DEVICE=#{dev}"
      f.puts "ONBOOT=yes"
      f.puts "UUID=#{dev_uuid}"
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

      metric=Config_utils.network_contains(serf['sync_net'], ip) ? 101:100
      cidr=Config_utils.to_cidr_mask(netmask)
      iprange=Config_utils.serialize_ipaddr(ip+cidr)

      open("/etc/iproute2/rt_tables", 'a') { |f|
        f.puts "#{metric} #{iface['device']}tbl" #if File.readlines("/etc/iproute2/rt_tables").grep(/#{metric} #{iface['device']}tbl/).any?
      }
      open("/etc/sysconfig/network-scripts/route-#{dev}", 'w') { |f|
        f.puts "default via #{gateway} dev #{iface['device']} table #{iface['device']}tbl" unless gateway.nil? or gateway.empty?
        f.puts "#{iprange} dev #{iface['device']} table #{iface['device']}tbl"
        f.puts "#{iprange} dev #{iface['device']} table main"
      }
      open("/etc/sysconfig/network-scripts/rule-#{dev}", 'w') { |f|
        f.puts "from #{iprange} table #{iface['device']}tbl"
      }
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
unless sync_net.nil?
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

#Firewall rules
if !network.nil? #Firewall rules are not needed in cloud environments
  if sync_interface != ""
    system("firewall-cmd --permanent --zone=home --add-interface=#{sync_interface}")
  end
  system("firewall-cmd --permanent --zone=home --add-source=#{sync_net} &>/dev/null")
  system("firewall-cmd --zone=home --add-protocol=igmp &>/dev/null")

  #nginx
  system("firewall-cmd --permanent --zone=home --add-port=443/tcp &>/dev/null") 

  # mDNS / serf
  system("firewall-cmd --permanent --zone=home --add-source-port=5353/udp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=7946/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=7946/udp &>/dev/null") 
  
  #Consul ports
  system("firewall-cmd --permanent --zone=home --add-port=8300/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=8301/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=8301/udp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=8302/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=8302/udp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=8400/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=8500/tcp &>/dev/null") 
  
  #DNS
  system("firewall-cmd --permanent --zone=home --add-port=53/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=53/udp &>/dev/null") 

  #Chef server
  system("firewall-cmd --permanent --zone=home --add-port=4443/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=5432/tcp &>/dev/null") 

  #zookeeper
  system("firewall-cmd --permanent --zone=home --add-port=2888/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=3888/tcp &>/dev/null") 
  system("firewall-cmd --permanent --zone=home --add-port=2181/tcp &>/dev/null") 

  #kafka
  system("firewall-cmd --permanent --zone=home --add-port=9092/tcp &>/dev/null") 

  #http2k
  system("firewall-cmd --permanent --zone=home --add-port=7980/tcp &>/dev/null") 

  #f2k
  system("firewall-cmd --permanent --zone=home --add-port=2055/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2055/udp &>/dev/null")

  #sfacctd (pmacctd)
  system("firewall-cmd --permanent --zone=home --add-port=6343/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=6343/udp &>/dev/null")

  #rsyslogd 
  system("firewall-cmd --permanent --zone=home --add-port=514/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=514/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=514/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=514/udp &>/dev/null")
 
  #freeradius
  system("firewall-cmd --permanent --zone=home --add-port=1812/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=1812/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=1813/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=1813/udp &>/dev/null")

  #rb-ale
  system("firewall-cmd --permanent --zone=public --add-port=7779/tcp &>/dev/null")

  #n2klocd
  system("firewall-cmd --permanent --zone=home --add-port=2056/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2056/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=2057/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2057/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=2058/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2058/tcp &>/dev/null")
 
  #druid
  system("firewall-cmd --permanent --zone=home --add-port=8080/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=8081/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=8083/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=8084/tcp &>/dev/null")

  #minio
  system("firewall-cmd --permanent --zone=home --add-port=9000/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=9001/tcp &>/dev/null")

  #snmp
  system("firewall-cmd --permanent --zone=home --add-port=161/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=161/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=home --add-port=162/udp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=162/udp &>/dev/null")

  # Reload firewalld configuration
  system("firewall-cmd --reload &>/dev/null")

end

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
