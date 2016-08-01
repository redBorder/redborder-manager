#!/usr/bin/env ruby

require 'json'
require 'mrdialog'

require File.join(ENV['RBDIR'].nil? ? '/usr/lib/redborder' : ENV['RBDIR'],'lib/rb_wiz_lib')


puts "\033]0;redborder - setup wizard\007"


# TODO: intro to the wizard, define color set, etc.

# Conf for network


text = <<EOF
Do you want to configure network in your system?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "CONFIGURE NETWORK"
yesno = dialog.yesno(text,0, 0)

if yesno # yesno is "yes" -> true
    # configure network
    netconf = NetConf.new
    netconf.doit # launch wizard for network configuration
    netconf.conf # it contains configuration parameters for network
end

# Conf for DNS / hostname

text = <<EOF
Do you want to configure DNS and hostname in your system?

EOF

dialog = MRDialog.new
dialog.clear = true
dialog.title = "CONFIGURE DNS / Hostname"
yesno = dialog.yesno(text,0, 0)

if yesno
    # configure network
    p "configuring dns and hostname!"
    exit(0)
end

# Conf synchronization network




## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
