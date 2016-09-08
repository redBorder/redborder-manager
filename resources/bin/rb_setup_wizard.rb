#!/usr/bin/env ruby

require 'json'
require 'mrdialog'
require 'yaml'

require File.join(ENV['RBDIR'].nil? ? '/usr/lib/redborder' : ENV['RBDIR'],'lib/rb_wiz_lib')

RBETC = ENV['RBETC'].nil? ? '/etc/redborder' : ENV['RBETC']

CONFFILE = "#{RBETC}/rb_init_conf.yml"
DIALOGRC = "#{RBETC}/dialogrc"
if File.exist?(DIALOGRC)
    ENV['DIALOGRC'] = DIALOGRC
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


def cancel_wizard() 

    dialog = MRDialog.new
    dialog.clear = true
    dialog.title = "SETUP wizard cancelled"

    text = <<EOF
The setup has been cancelled or stopped.

If you want to complete the setup wizard, please execute it again.

EOF
    result = dialog.msgbox(text, 10, 41)
    exit(1)

end

# Conf for network

#text = <<EOF
#Do you want to configure network in your system?
#
#EOF

#dialog = MRDialog.new
#dialog.clear = true
#dialog.title = "CONFIGURE NETWORK"
#yesno = dialog.yesno(text,0,0)

#if yesno # yesno is "yes" -> true
    # configure network
    netconf = NetConf.new
    netconf.doit # launch wizard
    cancel_wizard if netconf.cancel
    general_conf["network"]["interfaces"] = netconf.conf
#else
#    cancel_wizard
#end

# Conf for hostname

# configure hostname and domain name
hostconf = HostConf.new
hostconf.doit # launch wizard
cancel_wizard if hostconf.cancel
general_conf["hostname"] = hostconf.conf[:hostname]
general_conf["cdomain"] = hostconf.conf[:domainname]

# Conf for DNS

# configure dns and hostname
dnsconf = DNSConf.new
dnsconf.doit # launch wizard
cancel_wizard if dnsconf.cancel
general_conf["network"]["dns"] = dnsconf.conf

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

File.open(CONFFILE, 'w') {|f| f.write general_conf.to_yaml } #Store

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
