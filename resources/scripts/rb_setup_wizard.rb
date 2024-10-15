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
    dialog.title = "SETUP wizard cancelled"

    text = <<EOF

The setup has been cancelled or stopped.

If you want to complete the setup wizard, please execute it again.

EOF
    result = dialog.msgbox(text, 11, 41)
    exit(1)

end


unless File.exist?('/etc/redborder/cluster-installed.txt')

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

This wizard will guide you through the necessary configuration of the device
in order to convert it into a redborder node within a redborder cluster.

It will go through the following required steps: network configuration,
configuration of hostname, domain and DNS, Serf configuration, and finally
the node mode (the mode determines the minimum group of services that make up
the node, giving it more or less weight within the cluster).

Would you like to continue?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure wizard"
yesno = dialog.yesno(text,0,0)

unless yesno # yesno is "yes" -> true
    cancel_wizard
end

text = <<EOF

Next, you will be able to configure network settings. If you have
the network configured manually, you can "SKIP" this step and go
to the next step.

Please, Select an option.

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure Network"
dialog.cancel_label = "SKIP"
dialog.no_label = "SKIP"
yesno = dialog.yesno(text,0,0)

if yesno # yesno is "yes" -> true

    # Conf for network
    netconf = NetConf.new
    netconf.doit # launch wizard
    cancel_wizard if netconf.cancel
    general_conf["network"]["interfaces"] = netconf.conf

    static_interface = general_conf["network"]["interfaces"].find { |i| i["mode"] == "static" }
    dhcp_interfaces = general_conf["network"]["interfaces"].select { |i| i["mode"] == "dhcp" }

    if general_conf["network"]["interfaces"].size > 1
        if static_interface && static_interface.size == 1 && dhcp_interfaces.size >= 1
            general_conf["network"]["management_interface"] = static_interface["device"]
        else
            interface_options = general_conf["network"]["interfaces"].map { |i| [i["device"]] }
            text = <<EOF
You have multiple network interfaces configured.
Please select one to be used as the management interface.
EOF
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "Select Management Interface"
            management_iface = dialog.menu(text, interface_options, 10, 50)

            if management_iface.nil? || management_iface.empty?
                cancel_wizard
            else
                general_conf["network"]["management_interface"] = management_iface
            end
        end
    else
        if general_conf["network"]["interfaces"].size == 1
            if !static_interface.nil?
              general_conf["network"]["management_interface"] = static_interface["device"]
            else
              general_conf["network"]["management_interface"] = dhcp_interfaces.first["device"]
            end
        end         
    end
    # Conf for DNS
    text = <<EOF

Do you want to configure DNS servers?

If you have configured the network as Dynamic and
you get the DNS servers via DHCP, you should say
'No' to this  question.

EOF

    dialog = MRDialog.new
    dialog.clear = true
    dialog.title = "CONFIGURE DNS"
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
end

# Conf for hostname and domain
hostconf = HostConf.new
hostconf.doit # launch wizard
cancel_wizard if hostconf.cancel
general_conf["hostname"] = hostconf.conf[:hostname]
general_conf["cdomain"] = hostconf.conf[:domainname]

text = <<EOF

Next, you must configure settings for serf service.

Serf service is the service that create the cluster
and coordinate nodes between them, interchange certificates
and decide which will be the first master in the cluster
formation.

You will need to provide three parameters for this configuration:
the synchronism network, the unicast/multicast mode and
a secret key for encryption of serf network traffic.

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Configure Cluster Service (Serf)"
dialog.msgbox(text,0, 0)

# Initialize hshnet for using in SerfSync configuration
hshnet = {}
listnetdev = Dir.entries("/sys/class/net/").select {|f| !File.directory? f}
listnetdev.each do |netdev|
    # loopback and devices with no pci nor mac are not welcome!
    next if netdev == "lo"
    general_conf["network"]["interfaces"].each do |i|
        if i["device"] == netdev
            # found device!
            next unless i["mode"] == "static"
            n = NetAddr::CIDRv4.create("#{i["ip"]}/#{i["netmask"]}") # get network address from device ipaddr
            hshnet[netdev] = "#{n.network}#{n.netmask}" # format 192.168.1.0/24
            break
        end
    end
    # this netdev not configured via wizard? ... getting from system
    if hshnet[netdev].nil?
        hshnet[netdev] = Config_utils.get_first_route(netdev)[:prefix]
    end
    # No setting from wizard nor systems ... strange! better remove from the list.
    if hshnet[netdev].nil? or hshnet[netdev].empty?
        hshnet.delete(netdev)
    end
end

flag_serfsyncmanual = false
unless hshnet.empty?
    # Conf synchronization network
    syncconf = SerfSyncDevConf.new
    syncconf.networks = hshnet
    syncconf.doit # launch wizard
    cancel_wizard if syncconf.cancel
    if syncconf.conf == "Manual"
        flag_serfsyncmanual = true
    else
        general_conf["serf"]["sync_net"] = syncconf.conf
    end
else
    flag_serfsyncmanual = true
end

if flag_serfsyncmanual
    # Conf synchronization network
    syncconf = SerfSyncConf.new
    syncconf.doit # launch wizard
    cancel_wizard if syncconf.cancel
    general_conf["serf"]["sync_net"] = syncconf.conf
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

# External S3 storage
text = <<EOF

Do you want to use Amazon S3 Storage service?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "Confirm configuration"
dialog.dialog_options = "--defaultno"
yesno = dialog.yesno(text,0,0)

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
dialog.title = "Confirm configuration"
dialog.dialog_options = "--defaultno"
yesno = dialog.yesno(text,0,0)

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
    text += "- Networking:\n"
    general_conf["network"]["interfaces"].each do |i|
        text += "    device: #{i["device"]}\n"
        text += "    mode: #{i["mode"]}\n"
        if i["mode"] == "static"
            text += "    ip: #{i["ip"]}\n"
            text += "    netmask: #{i["netmask"]}\n"
            unless i["gateway"].nil? or i["gateway"] == ""
                text += "    gateway: #{i["gateway"]}\n"
            end
        end
        text += "\n"
    end
end

unless general_conf["network"]["management_interface"].nil?
    text += "- Management Interface:\n"
    text += "    #{general_conf["network"]["management_interface"]}\n"
    text += "\n"
end

unless general_conf["network"]["dns"].nil?
    text += "- DNS:\n"
    general_conf["network"]["dns"].each do |dns|
        text += "    #{dns}\n"
    end
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
text += "    sync net: #{general_conf["serf"]["sync_net"]}\n"
text += "    encrypt key: #{general_conf["serf"]["encrypt_key"]}\n"

text += "\n- Mode: #{general_conf["mode"]}\n"

text += "\nPlease, is this configuration ok?\n \n"

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
dialog.title = "Applying configuration"
dialog.prgbox(command,20,100, "Executing rb_init_conf")

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
