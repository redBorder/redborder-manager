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
        if Config_utils.check_ipv4({:ip => iface['ip'], :netmask => iface['netmask']})  and Config_utils.check_ipv4(:ip => iface['gateway'])
          f.puts "IPADDR=#{iface['ip']}"
          f.puts "NETMASK=#{iface['netmask']}"
          f.puts "GATEWAY=#{iface['gateway']}" unless iface['gateway'].nil?
        else
          p err_msg = "Invalid network configuration for device #{dev}. Please review #{INITCONF} file"
          exit 1
        end
      end
      dev_uuid = File.read("/proc/sys/kernel/random/uuid").chomp
      f.puts "BOOTPROTO=#{iface_mode}"
      f.puts "DEVICE=#{dev}"
      f.puts "ONBOOT=yes"
      f.puts "UUID=#{dev_uuid}"
    }
  end

  # Restart NetworkManager
  system('service network restart &> /dev/null')
end

# TODO: check network connectivity. Try to resolve repo.redborder.com

####################
# Set UTC timezone #
####################

system("timedatectl set-timezone UTC")
system("ntpdate pool.ntp.org")

######################
# Serf configuration #
######################
SERFJSON="/etc/serf/00first.json"
TAGSJSON="/etc/serf/tags"
SERFSNAPSHOT="/etc/serf/snapshot"

serf_conf = {}
serf_tags = {}
sync_net = serf['sync_net']
encrypt_key = serf['encrypt_key']
multicast = serf['multicast']

# local IP to bind to
unless sync_net.nil?
    # Initialize network device
    System.get_all_ifaddrs.each do |netdev|
        if IPAddr.new(sync_net).include?(netdev[:inet_addr])
            serf_conf["bind"] = netdev[:inet_addr].to_s
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
  # Allow multicast packets from sync_net. This rule allows a new serf node publish it in multicast address
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -s #{sync_net} -m pkttype --pkt-type multicast -j ACCEPT &>/dev/null")
  # Allow traffic from 5353/udp and sync_net. This rule allows other serf nodes to communicate with the new node
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --sport 5353 -j ACCEPT &>/dev/null")

  #Consul ports
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8300 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8301 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 8301 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8302 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 8302 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8400 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8500 -j ACCEPT &>/dev/null")

  #DNS
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 53 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 53 -j ACCEPT &>/dev/null")

  #Chef server
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 4443 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 5432 -j ACCEPT &>/dev/null")

  #Rabbitmq
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 5672 -j ACCEPT &>/dev/null")

  #zookeeper
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 2888 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 3888 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 2181 -j ACCEPT &>/dev/null")

  #kafka
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 9092 -j ACCEPT &>/dev/null")

  #http2k
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 7980 -j ACCEPT &>/dev/null")

  #f2k
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 2055 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2055/udp &>/dev/null")

  #sfacctd (pmacctd)
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 6343 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=6343/udp &>/dev/null")

  #rsyslogd 
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 514 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 514 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=514/tcp &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=514/udp &>/dev/null")
 
  #freeradius
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 1812 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=1812/udp &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 1813 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=1813/udp &>/dev/null")

  #rb-ale
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 7779 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=7779/tcp &>/dev/null")

  #n2klocd
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 2056 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2056/tcp &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 2057 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2057/tcp &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 2058 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=2058/tcp &>/dev/null")
 
  #druid
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8080 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8081 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8083 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 8084 -j ACCEPT &>/dev/null")

  #minio
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 9000 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp -s #{sync_net} -m tcp --dport 9001 -j ACCEPT &>/dev/null")

  #snmp
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 161 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=161/udp &>/dev/null")
  system("firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp -s #{sync_net} -m udp --dport 162 -j ACCEPT &>/dev/null")
  system("firewall-cmd --permanent --zone=public --add-port=162/udp &>/dev/null")

  # Reload firewalld configuration
  system("firewall-cmd --reload &>/dev/null")

end

# Node reboot
# add path in rc.local
system (echo "/usr/lib/redborder/scripts/rb_chef_server_reload.sh >> /etc/rc.d/rc.local")
# modify permissions to rc.local
system("chmod a+x /etc/rc.d/rc.local")


# Upgrade system
system('yum install systemd -y')

# Enable and start SERF
system('systemctl enable serf &> /dev/null')
system('systemctl start serf &> /dev/null')
# wait a moment before start serf-join to ensure connectivity
sleep(3)
system('systemctl start rb-bootstrap &> /dev/null')
