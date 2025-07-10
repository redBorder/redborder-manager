#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'mrdialog'
require 'yaml'
require 'netaddr'
require "#{ENV['RBLIB']}/rb_wiz_lib"
require "#{ENV['RBLIB']}/rb_config_utils.rb"
require 'i18n'

CONFFILE = "#{ENV['RBETC']}/rb_init_conf.yml"
DIALOGRC = "#{ENV['RBETC']}/dialogrc"
ENV['DIALOGRC'] = DIALOGRC if File.exist?(DIALOGRC)

# Load translations
I18n.load_path << "#{ENV['RBLIB']}/en.yml"
I18n.default_locale = :en
def cancel_wizard
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = I18n.t('wizard.cancelled.message')
  dialog.msgbox(I18n.t('wizard.cancelled.message'), 11, 41)
  exit 1
end

def show_error
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = 'Error'
  dialog.msgbox(I18n.t('wizard.network.error'), 0, 0)
  exit
end

def check_if_installed
  return unless File.exist?('/etc/redborder/cluster-installed.txt')

  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = I18n.t('wizard.installed.title')
  dialog.msgbox(Il8n.t('wizard.installed.message'), 11, 41)
  cancel_wizard
end
check_if_installed

puts "\033]0;redborder - setup wizard\007"

general_conf = {
  'hostname' => '',
  'cdomain' => '',
  'cloud' => false,
  'network' => {
    'interfaces' => [],
    'dns' => []
  },
  'serf' => {
    'multicast' => true,
    'sync_net' => '',
    'encrypt_key' => ''
  },
  's3' => {
    'access_key' => '',
    'secret_key' => '',
    'bucket' => '',
    'endpoint' => ''
  },
  'postgresql' => {
    'superuser' => '',
    'password' => '',
    'host' => '',
    'port' => ''
  },
  'mode' => 'full' # default mode
}

# general_conf will dump its contents as yaml conf into rb_init_conf.yml

# TODO: intro to the wizard, define color set, etc.
def welcome_setup
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = Il8n.t('wizard.welcome.title')
  yesno = dialog.yesno(Il8n.t('wizard.welcome.message', 0, 0))
  cancel_wizard unless yesno
end

welcome_setup

def network_setup
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = I18n.t('wizard.network.title')
  dialog.msgbox(I18n.t('wizard.network.message'), 0, 0)

  netconf = NetConf.new
  network_interfaces = netconf.get_network_interfaces

  show_error if network_interfaces.empty?

  netconf.doit(network_interfaces)
  cancel_wizard if netconf.cancel

  network_interfaces.delete_if { |iface| iface[0] == netconf.management_iface }

  netconf.doitsync(network_interfaces)
  cancel_wizard if netconf.cancel

  netconf.confdev.each_key do |interface|
    netconf.conf << netconf.confdev[interface].merge('device' => interface)
  end

  general_conf['network']['management_interface'] = netconf.management_iface
  general_conf['network']['sync_interface'] = netconf.sync_interface
  general_conf['network']['interfaces'] = netconf.conf
end

network_setup

def init_hshnet
  # Initialize hshnet for using in SerfSync configuration
  hshnet = {}
  listnetdev = Dir.entries('/sys/class/net/').reject { |f| File.directory?(f) }
  listnetdev.each do |netdev|
    # loopback and devices with no pci nor mac are not welcome!
    next if netdev == 'lo'

    general_conf['network']['interfaces'].each do |i|
      next unless i['device'] == netdev && netdev != general_conf['network']['management_interface']

      begin
        n = NetAddr::CIDRv4.create("#{i['ip']}/#{i['netmask']}") # get network address from device ipaddr
        hshnet[netdev] = "#{n.network}#{n.netmask}" # format 192.168.1.0/24
      rescue NetAddr::ValidationError
        hshnet[netdev] = nil
      end
      break
    end
    hshnet.delete(netdev) if hshnet[netdev].nil? || hshnet[netdev].empty?
  end
end
def serf_setup
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = I18n.t('wizard.serf.title')
  dialog.no_label = I18n.t('wizard.cancel.that')
  yesno = dialog.yesno(I18n.t('wizard.serf.message'), 0, 0)
  cancel_wizard unless yesno

  hshnet = init_hshnet

  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = Il8n('wizard.sync_network.title')
  if hshnet.empty?
    # text = <<~CONFIGURE_SYNC_NET

    #   Would you like to automatically configure the synchronism network based on your management interface IP?
    #   If decide not to, you will need to manually configure it.

    # CONFIGURE_SYNC_NET
    yesno = dialog.yesno(Il8n('wizard.sync_network.ask'), 0, 0)

    if yesno
      ip = "#{netconf.conf[0]['ip'].split('.')[0..2].join('.')}.0"
      netmask = netconf.conf[0]['netmask']
      cidr = NetAddr::CIDR.create("#{ip}/#{netmask}")
      general_conf['serf']['sync_net'] = cidr.to_s
    else
      dialog = MRDialog.new
      dialog.clear = true
      dialog.title = Il8n('wizard.sync_network.title')
      # text = <<~SYNC_NETWORK_CONFIGURATION

      #   Please configure the synchronism network.

      #   Select one of the device networks to designate as the synchronism network. This network is essential for connecting nodes and building the cluster. It also facilitates communication between internal services.

      #   In some cases, the synchronism network may not have a default gateway and could be isolated from other networks.

      # SYNC_NETWORK_CONFIGURATION
      dialog.msgbox(Il8n('wizard.sync_network.demand'), 0, 0)

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
  general_conf['serf']['multicast'] = mcastconf.conf

  # Password for serf
  cryptconf = SerfCryptConf.new
  cryptconf.doit # launch wizard
  cancel_wizard if cryptconf.cancel
  general_conf['serf']['encrypt_key'] = cryptconf.conf
end

serf_setup

# Conf for hostname and domain
hostconf = HostConf.new
hostconf.doit # launch wizard
cancel_wizard if hostconf.cancel
general_conf['hostname'] = hostconf.conf[:hostname]
general_conf['cdomain'] = hostconf.conf[:domainname]

def dns_setup
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = Il8n('wizard.dns.title')
  #   text = <<EOF

  # Would you like to manually configure DNS servers?

  # If your network is set to Dynamic and you are receiving DNS servers automatically via DHCP, it is recommended to select 'No' for this option.

  # EOF
  yesno = dialog.yesno(Il8n('wizard.dns.message'), 0, 0)

  if yesno # yesno is "yes" -> true
    # configure dns
    dnsconf = DNSConf.new
    dnsconf.doit # launch wizard
    cancel_wizard if dnsconf.cancel
    general_conf['network']['dns'] = dnsconf.conf
  else
    general_conf['network'].delete('dns')
  end
end
dns_setup

def s3_setup
  # External S3 storage
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = Il8n('wizard.s3.title')
  dialog.dialog_options = '--defaultno'
  yesno = dialog.yesno(Il8n('wizard.s3.message'), 8, 50)

  if yesno # yesno is "yes" -> true
    # configure dns
    s3conf = S3Conf.new
    s3conf.doit # launch wizard
    cancel_wizard if s3conf.cancel
    general_conf['s3'] = s3conf.conf
  else
    general_conf.delete('s3')
  end
end
s3_setup

# External Postgres DataBase
def external_db_setup
  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = 'Confirm Configuration'
  dialog.dialog_options = '--defaultno'
  yesno = dialog.yesno(I18n.t('wizard.postgres.message'), 8, 50)

  if yesno # yesno is "yes" -> true
    # configure dns
    rdsconf = RDSConf.new
    rdsconf.doit # launch wizard
    cancel_wizard if rdsconf.cancel
    general_conf['postgresql'] = rdsconf.conf
  else
    general_conf.delete('postgresql')
  end
end
external_db_setup

# Set mode
modeconf = ModeConf.new
modeconf.doit # launch wizard
cancel_wizard if modeconf.cancel
general_conf['mode'] = modeconf.conf

# Confirm
def confirm_setup
  text = Il8n('wizard.confirm.intro')

  unless general_conf['hostname'].empty?
    text += "\n- Hostname:\n"
    text += "    #{general_conf['hostname']}\n"
  end

  unless general_conf['cdomain'].empty?
    text += "\n- Domain Name:\n"
    text += "    #{general_conf['cdomain']}\n"
  end

  unless general_conf['network']['interfaces'].empty?
    text += "\n- Networking:\n"
    general_conf['network']['interfaces'].each do |i|
      text += "\n    device: #{i['device']}\n"
      text += "    mode: #{i['mode']}\n"
      next unless i['mode'] == 'static'

      text += "    ip: #{i['ip']}\n"
      text += "    netmask: #{i['netmask']}\n"
      next if i['gateway'].nil? || i['gateway'] == ''

      text += "    gateway: #{i['gateway']}\n"
    end
  end

  unless general_conf['network']['management_interface'].nil?
    text += "\n- Management Interface:\n"
    text += "    #{general_conf['network']['management_interface']}\n"
  end

  unless general_conf['network']['sync_interface'].nil?
    text += "\n- Synchronism Interface:\n"
    text += "    #{general_conf['network']['sync_interface']}\n"
  end

  unless general_conf['s3'].nil?
    text += "\n- AWS S3:\n"
    text += "    AWS access key: #{general_conf['s3']['access_key']}\n"
    text += "    AWS secret key: #{general_conf['s3']['secret_key']}\n"
    text += "    bucket: #{general_conf['s3']['bucket']}\n"
    text += "    endpoint: #{general_conf['s3']['endpoint']}\n"
  end

  unless general_conf['postgresql'].nil?
    text += "\n- AWS RDS or External PostgreSQL:\n"
    text += "    superuser: #{general_conf['postgresql']['superuser']}\n"
    text += "    password: #{general_conf['postgresql']['password']}\n"
    text += "    host: #{general_conf['postgresql']['host']}\n"
    text += "    port: #{general_conf['postgresql']['port']}\n"
  end

  text += "\n- Serf:\n"
  text += "    mode: #{general_conf['serf']['multicast'] ? 'multicast' : 'unicast'}\n"
  unless general_conf['serf']['sync_net'].nil? || general_conf['serf']['sync_net'].empty?
    text += "    sync net: #{general_conf['serf']['sync_net']}\n"
  end
  text += "    encrypt key: #{general_conf['serf']['encrypt_key']}\n"
  text += "\n- Mode: #{general_conf['mode']}\n\n"

  unless general_conf['network']['dns'].nil?
    text += "- DNS:\n"
    general_conf['network']['dns'].each do |dns|
      text += "    #{dns}\n"
    end
  end

  text += Il8n('wizard.confirm.final_ask')

  dialog = MRDialog.new
  dialog.clear = true
  dialog.title = 'Confirm configuration'
  yesno = dialog.yesno(text, 0, 0)
  cancel_wizard unless yesno # yesno is "yes" -> true

  File.open(CONFFILE, 'w') {|f| f.write general_conf.to_yaml } # Store
end
confirm_setup

def apply_config
  dialog = MRDialog.new
  dialog.clear = false
  dialog.title = 'Applying Configuration'
  command = "#{ENV['RBBIN']}/rb_init_conf"
  dialog.prgbox(command, 20, 100, 'Executing rb_init_conf')
end
apply_config

## vim:ts=2:sw=2:expandtab:ai:nowrap:formatoptions=croqln:
