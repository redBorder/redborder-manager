#!/usr/bin/env ruby

require 'json'
require 'mrdialog'

require File.join(ENV['RBDIR'].nil? ? '/usr/lib/redborder' : ENV['RBDIR'],'lib/rb_wiz_lib')


puts "\033]0;redborder - setup wizard\007"

general_conf = {}

# TODO: intro to the wizard, define color set, etc.

# Conf for network


text = <<EOF
Do you want to configure network in your system?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "CONFIGURE NETWORK"
yesno = dialog.yesno(text,0,0)

if yesno # yesno is "yes" -> true
    # configure network
    netconf = NetConf.new
    netconf.doit # launch wizard for network configuration
    general_conf[:network] = netconf.conf
    p general_conf # it contains configuration parameters for network
end

# Conf for hostname

text = <<EOF
Do you want to configure hostname and domainname in your system?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "CONFIGURE Hostname"
yesno = dialog.yesno(text,0, 0)

if yesno
    # configure dns and hostname
    hostconf = HostConf.new
    hostconf.doit # launch wizard for hostname configuration
    general_conf[:hostname] = hostconf.conf
    p "configuring hostname"
end

# Conf for DNS

text = <<EOF
Do you want to configure DNS servers in your system?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "CONFIGURE DNS"
yesno = dialog.yesno(text,0, 0)

if yesno
    # configure dns and hostname
    dnsconf = DNSConf.new
    dnsconf.doit # launch wizard for hostname configuration
    general_conf[:dns] = dnsconf.conf
    p "configuring dns"
end


# Conf synchronization network




## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
