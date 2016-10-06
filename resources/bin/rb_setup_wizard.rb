#!/usr/bin/env ruby

require 'json'
require 'mrdialog'
require 'yaml'
require "#{ENV['RBLIB']}/rb_wiz_lib"

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
        "secret_key" => ""
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

# Conf for network
netconf = NetConf.new
netconf.doit # launch wizard
cancel_wizard if netconf.cancel
general_conf["network"]["interfaces"] = netconf.conf

# Conf for hostname and domain
hostconf = HostConf.new
hostconf.doit # launch wizard
cancel_wizard if hostconf.cancel
general_conf["hostname"] = hostconf.conf[:hostname]
general_conf["cdomain"] = hostconf.conf[:domainname]

# Conf for DNS
text = <<EOF

Do you to configure DNS servers?

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

# Conf synchronization network
syncconf = SerfSyncConf.new
syncconf.doit # launch wizard
cancel_wizard if syncconf.cancel
general_conf["serf"]["sync_net"] = syncconf.conf

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

unless general_conf["network"]["dns"].nil?
    text += "- DNS:\n"
    general_conf["network"]["dns"].each do |dns|
        text += "    #{dns}\n"
    end
end

unless general_conf["s3"].nil?
    text += "\n- S3:\n"
    text += "    AWS access key: #{general_conf["s3"]["access_key"]}\n"
    text += "    AWS secret key: #{general_conf["s3"]["secret_key"]}\n"
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
command = "#{ENV['RBBIN']}/rb_init_conf.sh"

dialog = MRDialog.new
dialog.clear = false
dialog.title = "Applying configuration"
dialog.prgbox(command,20,100, "Executing rb_init_conf.sh")

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
