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
    "mode" => "full" # default mode
    }

# general_conf will dump its contents as yaml conf into rb_init_conf.yml

# TODO: intro to the wizard, define color set, etc.

text = <<EOF
 
Este wizard le guiará a través de la configuración necesaria del 
equipo para poder convertirlo en un nodo redborder dentro de un cluster redborder.

Los pasos necesarios por los que pasará son: configuración de red,
configuración de hostname, dominio y DNS, configuración de serf (servicio de
cluster) y, por último, el modo del nodo (el modo determina el conjunto mínimo
de servicios que conforma el nodo, dotándolo de mayor o menor peso dentro
del cluster).

¿Desea continuar?

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

unless general_conf["network"]["dns"].empty?
    text += "- DNS:\n"
    general_conf["network"]["dns"].each do |dns|
        text += "    #{dns}\n"
    end
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

# TODO: execute rb_init_conf.sh into a progress dialog

#exec("#{ENV['RBBIN']}/rb_init_conf.sh")

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
