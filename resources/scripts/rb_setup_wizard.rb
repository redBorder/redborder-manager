#!/usr/bin/env ruby

require 'json'
require 'mrdialog'
require 'yaml'
require "#{ENV['RBLIB']}/rb_wiz_lib"
require "#{ENV['RBLIB']}/rb_config_utils.rb"

CONFFILE = "#{ENV['RBETC']}/rb_init_conf.yml"
DIALOGRC = "#{ENV['RBETC']}/dialogrc"
if File.exist?(DIALOGRC)
    ENV['DIALOGRC'] = DIALOGRC
end

def cancel_wizard()

    dialog = MRDialog.new
    dialog.clear = true
    dialog.title = "Setup Wizard Cancelled"

    text = <<EOF

The setup wizard has been cancelled.

To resume the installation, please run the setup again.

EOF
    result = dialog.msgbox(text, 11, 41)
    exit(1)

end


if File.exist?('/etc/redborder/cluster-installed.txt')

    dialog = MRDialog.new
    dialog.clear = true
    dialog.title = "Manager already installed"
    text = <<EOF

Redborder manager is already installed in this machine.

EOF

result = dialog.msgbox(text, 11, 41)
cancel_wizard

end


puts "\033]0;redborder - setup wizard\007"

general_conf = {
    "hostname" => "",
    "cdomain" => "",
    "cloud" => false,
    "network" => {
        "interfaces" => [],
        "dns" => []
        },
    "serf" => {
        "multicast" => true,
        "sync_net" => "",
        "encrypt_key" => ""
        },
    "s3" => {
        "access_key" => "",
        "secret_key" => "",
        "bucket" => "",
        "endpoint" => ""
        },
    "postgresql" => {
        "superuser" => "",
        "password" => "",
        "host" => "",
        "port" => ""
        },
    "mode" => "full" # default mode
    }

# general_conf will dump its contents as yaml conf into rb_init_conf.yml

# TODO: intro to the wizard, define color set, etc.

text = <<EOF


This wizard will guide you through the essential steps to configure your 
device as a Redborder node within a Redborder cluster.

The configuration process includes the following steps:

    - Network settings: Set up your network configuration
    - Serf configuration: Establish Serf communication settings
    - System settings: Configure the hostname, domain, and DNS
    - Node mode selection: Choose the node mode, which determines 
    the set of services the node will run and its weight within the cluster

Would you like to proceed with the configuration?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure wizard"
yesno = dialog.yesno(text,0,0)

unless yesno # yesno is "yes" -> true
    cancel_wizard
end

text = <<EOF


In the next step, you'll configure your device's network settings.

First, you'll be asked to choose one of your interfaces to serve as the management interface. Then, you'll be prompted to select an interface for synchronization.

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure Network"
dialog.msgbox(text,0,0)

netconf = NetConf.new
network_interfaces = netconf.get_network_interfaces()

if network_interfaces.empty?
    dialog = MRDialog.new
    dialog.clear = true
    dialog.title = "Error"
    
    dialog.msgbox("Error: No network interfaces found. The script will now exit.", 0, 0)
    exit
end

netconf.doit(network_interfaces)
cancel_wizard if netconf.cancel

network_interfaces.delete_if { |iface| iface[0] == netconf.management_iface }

netconf.doitsync(network_interfaces)
cancel_wizard if netconf.cancel

netconf.confdev.each_key do |interface|
    netconf.conf << netconf.confdev[interface].merge("device" => interface)
end

general_conf["network"]["management_interface"] = netconf.management_iface
general_conf["network"]["sync_interface"] = netconf.sync_interface
general_conf["network"]["interfaces"] = netconf.conf
management_iface_ip = netconf.management_iface_ip

text = <<EOF

In this step, you will configure the Serf service, which is responsible for creating and managing the cluster. Serf coordinates communication between nodes, handles certificate exchange, and determines the initial master node during cluster formation.

For this configuration, you will need to provide the following three parameters:

    - Synchronism network: Define the network for node synchronization.
    - Unicast/Multicast mode: Select the communication mode for cluster coordination.
    - Secret key: Set a key to encrypt Serf network traffic for secure communication.

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure Cluster Service (Serf)"
dialog.no_label = "Cancel"
yesno = dialog.yesno(text,0,0)

cancel_wizard unless yesno

# Initialize hshnet for using in SerfSync configuration
hshnet = {}
listnetdev = Dir.entries("/sys/class/net/").select {|f| !File.directory? f}
listnetdev.each do |netdev|
    # loopback and devices with no pci nor mac are not welcome!
    next if netdev == "lo"
    general_conf["network"]["interfaces"].each do |i|
        if i["device"] == netdev && netdev != general_conf["network"]["management_interface"]
            begin
                n = NetAddr::CIDRv4.create("#{i["ip"]}/#{i["netmask"]}") # get network address from device ipaddr
                hshnet[netdev] = "#{n.network}#{n.netmask}" # format 192.168.1.0/24
            rescue NetAddr::ValidationError => e
                hshnet[netdev] = nil
            end
            break
        end
    end
    if hshnet[netdev].nil? or hshnet[netdev].empty?
        hshnet.delete(netdev)
    end
end

if hshnet.empty?
  text = <<~CONFIGURE_SYNC_NET

    Would you like to automatically configure the synchronism network based on your management interface IP?
    If decide not to, you will need to manually configure it.

  CONFIGURE_SYNC_NET

  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = 'Configure Sync Network?'
  yesno = dialog.yesno(text, 0, 0)

  if yesno
    subnet = management_iface_ip.split('.')[0..2].join('.') + '.0/24'
    general_conf['serf']['sync_net'] = subnet
  else
    text = <<~SYNC_NETWORK_CONFIGURATION

      Please configure the synchronism network.

      Select one of the device networks to designate as the synchronism network. This network is essential for connecting nodes and building the cluster. It also facilitates communication between internal services.

      In some cases, the synchronism network may not have a default gateway and could be isolated from other networks.

    SYNC_NETWORK_CONFIGURATION

    dialog = MRDialog.new
    dialog.clear = true
    dialog.title = 'Configure Sync Network'
    dialog.msgbox(text, 0, 0)

    syncconf = SerfSyncDevConf.new
    syncconf.networks = hshnet
    syncconf.doit(general_conf['network']['sync_interface'])
    cancel_wizard if syncconf.cancel
    general_conf['serf']['sync_net'] = syncconf.conf
  end
else
  text = <<~SYNC_NETWORK_CONFIGURATION

    Please configure the synchronism network.

    Select one of the device networks to designate as the synchronism network. This network is essential for connecting nodes and building the cluster. It also facilitates communication between internal services.

    In some cases, the synchronism network may not have a default gateway and could be isolated from other networks.

  SYNC_NETWORK_CONFIGURATION

  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = 'Configure Sync Network'
  dialog.msgbox(text, 0, 0)

  syncconf = SerfSyncDevConf.new
  syncconf.networks = hshnet
  syncconf.doit(general_conf['network']['sync_interface'])
  cancel_wizard if syncconf.cancel
  general_conf['serf']['sync_net'] = syncconf.conf
end

# Select multicast or unicast
mcastconf = SerfMcastConf.new
mcastconf.doit # launch wizard
cancel_wizard if mcastconf.cancel
general_conf["serf"]["multicast"] = mcastconf.conf

# Password for serf
cryptconf = SerfCryptConf.new
cryptconf.doit # launch wizard
cancel_wizard if cryptconf.cancel
general_conf["serf"]["encrypt_key"] = cryptconf.conf

# Conf for hostname and domain
hostconf = HostConf.new
hostconf.doit # launch wizard
cancel_wizard if hostconf.cancel
general_conf["hostname"] = hostconf.conf[:hostname]
general_conf["cdomain"] = hostconf.conf[:domainname]

# Conf for DNS
    text = <<EOF

Would you like to manually configure DNS servers?

If your network is set to Dynamic and you are receiving DNS servers automatically via DHCP, it is recommended to select 'No' for this option.

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure DNS"
yesno = dialog.yesno(text,0,0)

if yesno # yesno is "yes" -> true
    # configure dns
    dnsconf = DNSConf.new
    dnsconf.doit # launch wizard
    cancel_wizard if dnsconf.cancel
    general_conf["network"]["dns"] = dnsconf.conf
else
    general_conf["network"].delete("dns")
end

# External S3 storage
text = <<EOF

Do you need to use Amazon S3 Storage service?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Confirm Configuration"
dialog.dialog_options = "--defaultno"
yesno = dialog.yesno(text,8,50)

if yesno # yesno is "yes" -> true
    # configure dns
    s3conf = S3Conf.new
    s3conf.doit # launch wizard
    cancel_wizard if s3conf.cancel
    general_conf["s3"] = s3conf.conf
else
    general_conf.delete("s3")
end

# External Postgres DataBase
text = <<EOF

Do you want to use Amazon RDS service or other
external PostygreSQL DataBase?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Confirm Configuration"
dialog.dialog_options = "--defaultno"
yesno = dialog.yesno(text,8,50)

if yesno # yesno is "yes" -> true
    # configure dns
    rdsconf = RDSConf.new
    rdsconf.doit # launch wizard
    cancel_wizard if rdsconf.cancel
    general_conf["postgresql"] = rdsconf.conf
else
    general_conf.delete("postgresql")
end


# Set mode
modeconf = ModeConf.new
modeconf.doit # launch wizard
cancel_wizard if modeconf.cancel
general_conf["mode"] = modeconf.conf

# Confirm
text = <<EOF

You have selected the following parameter values for your configuration:
EOF

unless general_conf["network"]["interfaces"].empty?
    text += "\n- Networking:\n"
    general_conf["network"]["interfaces"].each do |i|
        text += "\n    device: #{i["device"]}\n"
        text += "    mode: #{i["mode"]}\n"
        if i["mode"] == "static"
            text += "    ip: #{i["ip"]}\n"
            text += "    netmask: #{i["netmask"]}\n"
            unless i["gateway"].nil? or i["gateway"] == ""
                text += "    gateway: #{i["gateway"]}\n"
            end
        end
    end
end

unless general_conf["network"]["management_interface"].nil?
    text += "\n- Management Interface:\n"
    text += "    #{general_conf["network"]["management_interface"]}\n"
end

unless general_conf["network"]["sync_interface"].nil?
    text += "\n- Synchronism Interface:\n"
    text += "    #{general_conf["network"]["sync_interface"]}\n"
end

unless general_conf["s3"].nil?
    text += "\n- AWS S3:\n"
    text += "    AWS access key: #{general_conf["s3"]["access_key"]}\n"
    text += "    AWS secret key: #{general_conf["s3"]["secret_key"]}\n"
    text += "    bucket: #{general_conf["s3"]["bucket"]}\n"
    text += "    endpoint: #{general_conf["s3"]["endpoint"]}\n"
end

unless general_conf["postgresql"].nil?
    text += "\n- AWS RDS or External PostgreSQL:\n"
    text += "    superuser: #{general_conf["postgresql"]["superuser"]}\n"
    text += "    password: #{general_conf["postgresql"]["password"]}\n"
    text += "    host: #{general_conf["postgresql"]["host"]}\n"
    text += "    port: #{general_conf["postgresql"]["port"]}\n"
end

text += "\n- Serf:\n"
text += "    mode: #{general_conf["serf"]["multicast"] ? "multicast" : "unicast"}\n"
unless general_conf["serf"]["sync_net"].nil? || general_conf["serf"]["sync_net"].empty?
    text += "    sync net: #{general_conf["serf"]["sync_net"]}\n"
end
text += "    encrypt key: #{general_conf["serf"]["encrypt_key"]}\n"

text += "\n- Mode: #{general_conf["mode"]}\n\n"

unless general_conf["network"]["dns"].nil?
    text += "- DNS:\n"
    general_conf["network"]["dns"].each do |dns|
        text += "    #{dns}\n"
    end
end

text += "\nWould you like to proceed with the installation?\n \n"

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Confirm configuration"
yesno = dialog.yesno(text,0,0)

unless yesno # yesno is "yes" -> true
    cancel_wizard
end

File.open(CONFFILE, 'w') {|f| f.write general_conf.to_yaml } #Store

#exec("#{ENV['RBBIN']}/rb_init_conf.sh")
command = "#{ENV['RBBIN']}/rb_init_conf"

dialog = MRDialog.new
dialog.clear = false
dialog.title = "Applying Configuration"
dialog.prgbox(command,20,100, "Executing rb_init_conf")

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
