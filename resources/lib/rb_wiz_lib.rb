#!/usr/bin/env ruby

require 'mrdialog'
require 'net/ip'
require 'system/getifaddrs'
require 'netaddr'
require 'uri'
require File.join(ENV['RBDIR'].nil? ? '/usr/lib/redborder' : ENV['RBDIR'],'lib/rb_config_utils.rb')

class WizConf

    # Read propierties from sysfs for a network devices
    def netdev_property(devname)
        netdev = {}
        IO.popen("udevadm info -q property -p /sys/class/net/#{devname} 2>/dev/null").each do |line|
            unless line.match(/^(?<key>[^=]*)=(?<value>.*)$/).nil?
                netdev[line.match(/^(?<key>[^=]*)=(?<value>.*)$/)[:key]] = line.match(/^(?<key>[^=]*)=(?<value>.*)$/)[:value]
            end
        end
        if File.exist?"/sys/class/net/#{devname}/address"
            f = File.new("/sys/class/net/#{devname}/address",'r')
            netdev["MAC"] = f.gets.chomp
            f.close
        end
        if File.exist?"/sys/class/net/#{devname}/operstate"
            f = File.new("/sys/class/net/#{devname}/operstate",'r')
            netdev["STATUS"] = f.gets.chomp
            f.close
        end

        netdev
    end

end

# Class to create a Network configuration box
class NetConf < WizConf

    attr_accessor :conf, :confdev, :cancel, :management_iface, :sync_interface

    def initialize()
        @cancel = false
        @returning_from_cancel = false
        @conf = []
        @confdev = {}
        @devmode = { "dhcp" => "Dynamic", "static" => "Static" }
        @devmodereverse = { "Dynamic" => "dhcp", "Static" => "static" }
        @management_iface = nil
        @sync_interface = nil 
    end

    def doit(network_interfaces)
        dialog = MRDialog.new
        dialog.clear = true
        dialog.title = "Management Interface Selection"
        loop do
            self.management_iface = dialog.radiolist("Please select an interface to use as the management interface:", network_interfaces, 0, 0, 4)
            return cancel_wizard unless management_iface
            selected_interface = network_interfaces.find { |iface| iface[0] == management_iface }
            if selected_interface[1].include?("IP: ")
                dialog = MRDialog.new
                dialog.clear = true
                dialog.title = "Skip Network Configuration"
                if dialog.yesno("The interface '#{selected_interface[0]}' already has an IP. Do you want to skip network configuration?", 6, 60)
                    return
                end
            end
            configure_interface(management_iface, network_interfaces)
            break if !@returning_from_cancel
            @returning_from_cancel = false
        end
    end

    def doitsync(network_interfaces)
        return if network_interfaces.empty?

        dialog = MRDialog.new
        dialog.clear = true
        dialog.title = "Synchronism Interface Selection"
        loop do
            self.sync_interface = dialog.radiolist("Please select an interface to use as the synchronism interface:", network_interfaces, 0, 0, 4)
            return cancel_wizard unless sync_interface
            selected_interface = network_interfaces.find { |iface| iface[0] == sync_interface }
            if selected_interface[1].include?("IP: ")
                dialog = MRDialog.new
                dialog.clear = true
                dialog.title = "Skip Network Configuration"
                if dialog.yesno("The interface '#{selected_interface[0]}' already has an IP. Do you want to skip network configuration?", 6, 60)
                    return
                end
            end
            configure_sync_interface(sync_interface)
            break if !@returning_from_cancel
            @returning_from_cancel = false
        end
    end

    def get_network_interfaces
        network_interfaces = []
        radiolist_data = Struct.new(:tag, :item, :select)
        first_interface = true
        # loop over list of net devices
        listnetdev = Dir.entries("/sys/class/net/").select {|f| !File.directory? f}
        listnetdev.each do |netdev|
            # loopback and devices with no pci nor mac are not welcome!
            next if netdev == "lo"
            netdevprop = netdev_property(netdev)
            next unless (netdevprop["ID_BUS"] == "pci" and !netdevprop["MAC"].nil?)
    
            # Fetch network scripts to get IP information
            ip = get_ip_for_interface(netdev)
            get_network_scripts(netdev)

            data = radiolist_data.new
            data.tag = netdev
            data.item = "MAC: " + netdevprop["MAC"] + ", Vendor: " + netdevprop["ID_MODEL_FROM_DATABASE"]
            data.item += ", IP: #{ip}" unless ip.nil? # Add IP if available
            data.select = first_interface ? true : false
            first_interface = false if first_interface
    
            network_interfaces.push(data.to_a)
        end
        return network_interfaces
    end
    
    # Helper method to extract the IPv4 address from the network script
    def get_ip_for_interface(netdev)
        if File.exist?("/etc/sysconfig/network-scripts/ifcfg-#{netdev}")
            config_file = File.read("/etc/sysconfig/network-scripts/ifcfg-#{netdev}")
            if config_file.match(/^IPADDR=/)
                return config_file.match(/^IPADDR=(?<ip>.*)$/)[:ip]
            end
        end
        return nil # Return nil if no IP found
    end

    def configure_interface(interface, network_interfaces)
        dialog = MRDialog.new
        dialog.clear = true
        dialog.title = "Interface Configuration"
        if network_interfaces.length == 1 || dialog.yesno("\nWould you like to assign a static IP to this interface?\n\nIf you choose not to, the interface will default to DHCP for automatic IP configuration.\n", 0, 0)
            dev = DevConf.new(interface, self)
            dev.conf = @confdev[interface] if @confdev[interface]
            dev.doit
            if dev.conf.empty?
                get_network_scripts(interface)
                @returning_from_cancel = true
                return
            else
                @confdev[interface] = {
                    "mode" => "static",
                    "ip" => dev.conf['IP:'],
                    "netmask" => dev.conf['Netmask:'],
                    "gateway" => dev.conf['Gateway:'].to_s.empty? ? "" : dev.conf['Gateway:']
                }
            end
        else
            @confdev[interface] = {"mode" => "dhcp"}
        end
    end

    def configure_sync_interface(interface)
        dev = DevConf.new(interface, self)
        dev.conf = @confdev[interface] if @confdev[interface]
        dev.doit
        @confdev[interface] = {
            "mode" => "static",
            "ip" => dev.conf['IP:'],
            "netmask" => dev.conf['Netmask:'],
            "gateway" => dev.conf['Gateway:'].to_s.empty? ? "" : dev.conf['Gateway:']
        } unless dev.conf.empty?
        if dev.conf.empty?
            get_network_scripts(interface)
            @returning_from_cancel = true
            return
        end
    end

    def get_network_scripts(netdev)
        if File.exist?("/etc/sysconfig/network-scripts/ifcfg-#{netdev}")
            config_file = File.read("/etc/sysconfig/network-scripts/ifcfg-#{netdev}")
            
            if config_file.match(/^IPADDR=/)
                ip = config_file.match(/^IPADDR=(?<ip>.*)$/)&.[](:ip)
                netmask = config_file.match(/^NETMASK=(?<netmask>.*)$/)&.[](:netmask) || "255.255.255.0"
                gateway = config_file.match(/^GATEWAY=(?<gateway>.*)$/)&.[](:gateway) || ""

                @confdev[netdev] = {
                    "mode" => "static", 
                    "ip" => ip, 
                    "netmask" => netmask,
                    "gateway" => gateway
                }
            else
                @confdev[netdev] = {"mode" => "dhcp"}
            end
        else
            @confdev[netdev] = {"mode" => "dhcp"}
        end
    end
end

class DevConf < WizConf

    attr_accessor :device_name, :conf, :cancel

    def initialize(x, parent)
        @cancel = false
        @device_name = x
        @conf = {}
        @parent = parent
    end

    def doit
        dialog = MRDialog.new
        dialog.clear = true
        text = <<EOF

You are about to configure the network device #{@device_name}, which has the following properties:
EOF
        netdevprop = netdev_property(@device_name)

        text += " \n"
        text += "MAC: #{netdevprop["MAC"]}\n"
        text += "DRIVER: #{netdevprop["ID_NET_DRIVER"]}\n" unless netdevprop["ID_NET_DRIVER"].nil?
        text += "PCI PATH: #{netdevprop["ID_PATH"]}\n" unless netdevprop["ID_PATH"].nil?
        text += "VENDOR: #{netdevprop["ID_VENDOR_FROM_DATABASE"]}\n" unless netdevprop["ID_VENDOR_FROM_DATABASE"].nil?
        text += "MODEL: #{netdevprop["ID_MODEL_FROM_DATABASE"]}\n" unless netdevprop["ID_MODEL_FROM_DATABASE"].nil?
        text += "STATUS: #{netdevprop["STATUS"]}\n" unless netdevprop["STATUS"].nil?
        text += " \n"

        @conf['IP:'] = Config_utils.get_ipv4_network(@device_name)[:ip] if @conf['IP:'].nil?
        @conf['Netmask:'] = Config_utils.get_ipv4_network(@device_name)[:netmask] if @conf['Netmask:'].nil?
        @conf['Gateway:'] = Config_utils.get_ipv4_network(@device_name)[:gateway] if @conf['Gateway:'].nil?

        flen = 20
        form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen)

        loop do
            items = []
            label = "IP:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = @conf[label]
            data.iy = 1
            data.ix = 10
            data.flen = flen
            data.ilen = 0
            items.push(data.to_a)

            label = "Netmask:"
            data = form_data.new
            data.label = label
            data.ly = 2
            data.lx = 1
            data.item = @conf[label]
            data.iy = 2
            data.ix = 10
            data.flen = flen
            data.ilen = 0
            items.push(data.to_a)

            label = "Gateway:"
            data = form_data.new
            data.label = label
            data.ly = 3
            data.lx = 1
            data.item = @conf[label]
            data.iy = 3
            data.ix = 10
            data.flen = flen
            data.ilen = 0
            items.push(data.to_a)

            dialog.title = "Network configuration for #{@device_name}"
            @conf = dialog.form(text, items, 20, 60, 0)

            # need to check result
            if @conf.empty?
                # Cancel was pressed
                break
            else
                # ok pressed
                @conf['Mode:'] = "Static"
                if Config_utils.check_ipv4({:ip => @conf['IP:']}) and Config_utils.check_ipv4({:netmask => @conf['Netmask:']})
                    # seems to be ok
                    unless @conf['Gateway:'] == "" || Config_utils.check_ipv4({:ip => @conf['Gateway:']})
                        next
                    end
                else
                    # error detected
                    dialog = MRDialog.new
                    dialog.clear = true
                    dialog.title = "Network Configuration Error"
                    text = <<EOF

An error has been detected in the network configuration.

Please review the IP, Netmask, and Gateway address settings.
EOF
                    dialog.msgbox(text, 10, 41)
                    next
                end
                break
            end
        end
    end
end

class HostConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = {}
    end

    def doit

        host = {}
        @conf["Hostname:"] = ""
        @conf["Domain name:"] = ""
        fullhostname = `hostnamectl --static`.chomp
        unless fullhostname.match(/^(?<hostname>[^.]+)(\.(?<domain>.*))?$/).nil?
            @conf["Hostname:"] = fullhostname.match(/^(?<hostname>[^.]+)(\.(?<domain>.*))?$/)[:hostname]
            @conf["Domain name:"] = fullhostname.match(/^(?<hostname>[^.]+)(\.(?<domain>.*))?$/)[:domain]
        end
        if @conf["Hostname:"] == "rbmanager" or @conf["Hostname:"] == "localhost" or @conf["Hostname:"] = ""
            @conf["Hostname:"] = "rb-#{rand(36**10).to_s(36)}"
            @conf["Domain name:"] = "redborder.cluster"
        end

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF

Please enter the hostname and domain name for the device.

The hostname can include only ASCII letters ('a' to 'z', case-insensitive), digits ('0' to '9'), and hyphens ('-'). According to RFC1123, hostname labels can begin with a letter or digit but cannot start or end with a hyphen.

Additionally, each label in the hostname and domain name must be between 1 and 63 characters, and the entire hostname must not exceed 253 ASCII characters.

For guidance on choosing an appropriate hostname, please refer to RFC1178.

EOF
            items = []
            form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen, :attr)

            items = []
            label = "Hostname:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = @conf[label]
            data.iy = 1
            data.ix = 14
            data.flen = 63
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "Domain name:"
            data = form_data.new
            data.label = label
            data.ly = 2
            data.lx = 1
            data.item = @conf[label]
            data.iy = 2
            data.ix = 14
            data.flen = 253
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            dialog.title = "Hostname and Domain Name Configuration"
            host = dialog.mixedform(text, items, 20, 80, 0)

            if host.empty?
                # Cancel button pushed
                @cancel = true
                break
            else
                if Config_utils.check_hostname(host["Hostname:"]) and Config_utils.check_domain(host["Domain name:"])
                    # need to confirm lenght
                    if host["Hostname:"].length < 64 and (host["Hostname:"].length + host["Domain name:"].length) < 254
                        break
                    end
                end
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "Hostname or Domain Name Configuration Error"
            text = <<EOF

            An error has been detected in the hostname or domain name configuration.

            Please review the character set and length to ensure they meet the required standards.
EOF
            dialog.msgbox(text, 0, 0)

        end

        @conf[:hostname] = host["Hostname:"]
        @conf[:domainname] = host["Domain name:"]

    end

end

class DNSConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = []
    end

    def doit

        dns = {}
        count=1
        @conf.each do |x|
            dns["DNS#{count}:"] = x
            count+=1
        end

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF

Please, set DNS servers.

You can set up to 3 DNS servers, but only one is mandatory. Set DNS values in order, first, second (optional) and then third (optional).

Please, insert each value fo IPv4 address in dot notation.
 
EOF
            items = []
            form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen, :attr)

            items = []
            label = "DNS1:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = dns[label]
            data.iy = 1
            data.ix = 8
            data.flen = 16
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "DNS2:"
            data = form_data.new
            data.label = label
            data.ly = 2
            data.lx = 1
            data.item = dns[label]
            data.iy = 2
            data.ix = 8
            data.flen = 16
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "DNS3:"
            data = form_data.new
            data.label = label
            data.ly = 3
            data.lx = 1
            data.item = dns[label]
            data.iy = 3
            data.ix = 8
            data.flen = 16
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            dialog.title = "DNS Configuration"
            dns = dialog.mixedform(text, items, 20, 60, 0)

            if dns.empty?
                # Cancel button pushed
                @cancel = true
                break
            else
                if Config_utils.check_ipv4({:ip=>dns["DNS1:"]})
                    unless dns["DNS2:"].empty?
                        if Config_utils.check_ipv4({:ip=>dns["DNS2:"]})
                            unless dns["DNS3:"].empty?
                                if Config_utils.check_ipv4({:ip=>dns["DNS3:"]})
                                    break
                                end
                            else
                                break
                            end
                        end
                    else
                        break
                    end
                end
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "DNS Configuration Error"
            text = <<EOF

An error has been detected in the DNS or search configuration.

Please review the DNS settings and ensure that only IPv4 addresses in dot notation are used.
EOF
            dialog.msgbox(text, 12, 60)
        end

        unless dns.empty?
            @conf << dns["DNS1:"]
            unless dns["DNS2:"].empty?
                @conf << dns["DNS2:"]
                unless dns["DNS3:"].empty?
                    @conf << dns["DNS3:"]
                end
            end
        end

    end

end

class SerfSyncDevConf < WizConf

    attr_accessor :conf, :cancel, :networks

    def initialize()
        @cancel = false
        @returning_from_cancel = false
        @conf = ""
        @networks = {}
    end

    def doit(sync_interface)

        dialog = MRDialog.new
        dialog.clear = true

        text = <<EOF

Please configure the synchronism network.

Select one of the device networks to designate as the synchronism network. This network is essential for connecting nodes and building the cluster. It also facilitates communication between internal services.
        
In some cases, the synchronism network may not have a default gateway and could be isolated from other networks.

EOF

        network_interfaces = []
        radiolist_data = Struct.new(:tag, :item, :select)

        select = true
        networks.each do |k,v|
            data = radiolist_data.new
            data.tag = k
            data.item = v 
            data.select = select
            if k == sync_interface
                data.select = true
                select = false
            else
                data.select = false
            end
            network_interfaces.push(data.to_a)
        end

        network_interfaces.push(radiolist_data.new("Manual", "Manually set a sync network", false).to_a)

        dialog.title = "Synchronism Network configuration"

        loop do
            sync_interface = dialog.radiolist("Please select a network to use as the synchronism network:", 
                                                network_interfaces, 10, 80, 0)
            return cancel_wizard unless sync_interface
            sync_network = network_interfaces.find { |ni| ni[0] == sync_interface }[1]
            self.conf = configure_interface(sync_network)
            break unless @returning_from_cancel
            @returning_from_cancel = false
        end
    end

    def configure_interface(sync_network)
        synchronism_network_config = SerfSyncConf.new(sync_network)
        synchronism_network_config.doit()
        cancel_wizard if synchronism_network_config.cancel
        if synchronism_network_config.conf.empty?
            @returning_from_cancel = true
            return
        else
            return synchronism_network_config.conf
        end
    end
end


class SerfSyncConf < WizConf

    attr_accessor :conf, :cancel

    def initialize(sync_network)
        @cancel = false
        @returning_from_cancel = false
        @conf = {}
        @sync_network = sync_network
    end

    def doit
        if Config_utils.check_ipv4(@sync_network)
            sync_netaddr = NetAddr::CIDRv4.create(@sync_network)
            return self.conf = "#{sync_netaddr.network}#{sync_netaddr.netmask}"
        end

        sync = {}

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF

Please configure the synchronism network.

You need to provide the synchronism network in two formats:

IPv4 CIDR format (e.g., 192.168.1.0/24)
IPv4 mask format (e.g., 192.168.1.0/255.255.255.0)

This network is essential for connecting nodes and building the cluster, as it enables communication between internal services.

In some cases, this network may not have a default gateway and could be isolated from other networks.

EOF
            items = []
            form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen, :attr)

            items = []
            label = "Sync Network:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = sync[label]
            data.iy = 1
            data.ix = 15
            data.flen = 31
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            dialog.title = "Sync Network Configuration"
            sync = dialog.mixedform(text, items, 24, 80, 0)

            if dialog.exit_code == dialog.dialog_ok
                if Config_utils.check_ipv4(sync["Sync Network:"])
                    # it is ok
                    break
                else
                    # error
                end
            else
                # Cancel button pushed
                @returning_from_cancel = true
                break
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "Sync Network Configuration Error"
            text = <<EOF

An error has been detected in the Sync Network configuration.

Please review the settings and ensure that the IPv4 address is in dot notation, followed by either the mask length or the netmask. For example: 192.168.100.0/24.

EOF
            dialog.msgbox(text, 15, 41)
        end

        begin
            sync_netaddr = NetAddr::CIDRv4.create(sync["Sync Network:"])
            self.conf = "#{sync_netaddr.network}#{sync_netaddr.netmask}"
        rescue
        end
    end
end

class SerfMcastConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = ""
    end

    def doit

        dialog = MRDialog.new
        dialog.clear = true
        text = <<EOF

Please select the configuration type:

    - Multicast: Configures the Serf agent to operate in Multicast mode. In this mode, Serf automatically discovers the cluster using a multicast address and the domain name as the cluster domain.

    - Unicast: Configures the Serf agent to operate in Unicast mode. In this mode, Serf attempts to join an existing cluster by scanning via ARP over the Synchronism network.

In both modes, the Synchronism network is used to identify and bind to the appropriate network device.
        
EOF
        items = []
        radiolist_data = Struct.new(:tag, :item, :select)
        data = radiolist_data.new
        data.tag = "Multicast"
        data.item = "Multicast over a cluster domain"
        data.select = true # default
        items.push(data.to_a)

        data = radiolist_data.new
        data.tag = "Unicast"
        data.item = "Unicast over the synchronism network"
        data.select = false # default
        items.push(data.to_a)

        dialog.title = "Communication Cluster Mode"
        selected_item = dialog.radiolist(text, items, 22, 80, 0)

        if dialog.exit_code == dialog.dialog_ok
            @conf = ( selected_item == "Multicast" ? true : false )
        else
            @cancel = true
        end
    end
end

class SerfCryptConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = ""
    end

    def doit

        result = {}

        loop do

            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            dialog.title = "Serf Encryption Key"
            text = <<EOF

Please provide a password to encrypt Serf network traffic.

This password will prevent unauthorized nodes from connecting to the cluster. You may use any printable characters, with a length of 6 to 20 characters.
 
EOF

            flen = 20
            form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen)


            items = []
            label = "Password:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = ""
            data.iy = 1
            data.ix = 15
            data.flen = flen
            data.ilen = 0
            items.push(data.to_a)

            label = "Enter again:"
            data = form_data.new
            data.label = label
            data.ly = 2
            data.lx = 1
            data.item = ""
            data.iy = 2
            data.ix = 15
            data.flen = flen
            data.ilen = 0
            items.push(data.to_a)


            result = dialog.passwordform(text, items, 16, 60, 0)

            if dialog.exit_code == dialog.dialog_ok
                if result["Password:"] == result["Enter again:"]
                    if result["Password:"].length < 6 or result["Password:"].length > 20
                        # error, incorrect length
                    else
                        # it is ok
                        break
                    end
                else
                    # error, password does not match
                end
            else
                @cancel = true
                break
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "Serf Encryption Key Error"
            text = <<EOF

An error has been detected in the Serf encryption key.

Please ensure the key is between 6 and 20 characters long, and that both fields match.

EOF
            dialog.msgbox(text, 12, 60)

        end

        @conf = Config_utils.get_encrypt_key(result["Password:"])

    end
end

class ModeConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = ""
    end

    def doit

        modelist = [
            {"name"=>"custom", "description"=>"Minimum set of services to join into a cluster"},
            {"name"=>"core", "description"=>"Basic set of services to create a cluster"},
            {"name"=>"full", "description"=>"All services running to perform a full cluster experience"}
            ] # default values

        if File.exist?("#{ENV['RBDIR']}/mode-list.yml")
            modelist = YAML.load_file("#{ENV['RBDIR']}/mode-list.yml")
        end

        dialog = MRDialog.new
        dialog.clear = true
        text = <<EOF

Please select the mode of operation for the manager node.

    - If this is the first installation of a Redborder manager and you plan to create a cluster with multiple nodes, select 'core' mode.
    - For additional nodes in the cluster, choose 'custom' mode.
    - If this is a standalone manager installation, select 'full' mode.

EOF
        items = []
        radiolist_data = Struct.new(:tag, :item, :select)

        modelist.each do |m|
            data = radiolist_data.new
            data.tag = m['name']
            data.item = m['description']
            data.select = m['name'] == 'full' ? true : false
            items.push(data.to_a)
        end

        dialog.title = "Manager Mode"
        selected_item = dialog.radiolist(text, items)

        if dialog.exit_code == dialog.dialog_ok
            @conf = selected_item
        else
            @cancel = true
        end
    end
end

class RDSConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = {
        "superuser" => "",
        "password" => "",
        "host" => "",
        "port" => ""
        }
    end

    def doit

        rdsconf = {
        "Superuser:" => "",
        "Password:" => "",
        "Host:" => "",
        "Port:" => 5432
        }

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF

You need to provide the following parameters to use the Amazon RDS database service or an external PostgreSQL database:

    - Superuser: The user with privileges to create and manage databases, users, and permissions.
    - Password: The password for the superuser account.
    - Host: The IP address or hostname of the database service.
    - Port: The port for the database service (default: 5432).
   
Please enter these PostgreSQL parameters:

EOF
            items = []
            form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen, :attr)

            items = []
            label = "Superuser:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = rdsconf[label]
            data.iy = 1
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "Password:"
            data = form_data.new
            data.label = label
            data.ly = 2
            data.lx = 1
            data.item = rdsconf[label]
            data.iy = 2
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "Host:"
            data = form_data.new
            data.label = label
            data.ly = 3
            data.lx = 1
            data.item = rdsconf[label]
            data.iy = 3
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "Port:"
            data = form_data.new
            data.label = label
            data.ly = 4
            data.lx = 1
            data.item = rdsconf[label]
            data.iy = 4
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            dialog.title = "RDS/PostgreSQL Configuration"
            rdsconf = dialog.mixedform(text, items, 0, 0, 0)

            if dialog.exit_code == dialog.dialog_ok
                unless rdsconf["Superuser:"].empty? or rdsconf["Password:"].empty? or rdsconf["Host:"].empty? or rdsconf["Port:"].empty?
                    @conf['superuser'] = rdsconf["Superuser:"]
                    @conf['password'] = rdsconf["Password:"]
                    @conf['host'] = rdsconf["Host:"]
                    @conf['port'] = rdsconf["Port:"]
                    break
                end
            else
                @cancel = true
                break
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "S3 Configuration Error"
            text = <<EOF

An error has been detected in the S3 configuration.

Please provide valid values for the required parameters.

EOF
            dialog.msgbox(text, 12, 41)

        end

    end

end


class S3Conf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = { "access_key" => "", "secret_key" => "" }
    end

    def doit

        s3conf = { "AWS access key:" => "", "AWS secret key:" => "" }

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF

You need to provide the following parameters to use the Amazon S3 Storage Service:

    - AWS Access Key: A unique alphanumeric string that identifies your Amazon Web Services (AWS) account.
    - AWS Secret Key: An encoded password used to authenticate your identity.
    - Bucket: A logical storage unit in AWS S3, where objects are stored.
    - Endpoint: The URL that serves as the entry point for the web service.

Please enter these S3 parameters:

EOF
            items = []
            form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen, :attr)

            items = []
            label = "AWS access key:"
            data = form_data.new
            data.label = label
            data.ly = 1
            data.lx = 1
            data.item = s3conf[label]
            data.iy = 1
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "AWS secret key:"
            data = form_data.new
            data.label = label
            data.ly = 2
            data.lx = 1
            data.item = s3conf[label]
            data.iy = 2
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "Bucket:"
            data = form_data.new
            data.label = label
            data.ly = 3
            data.lx = 1
            data.item = s3conf[label]
            data.iy = 3
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            label = "Endpoint:"
            data = form_data.new
            data.label = label
            data.ly = 4
            data.lx = 1
            data.item = s3conf[label]
            data.iy = 4
            data.ix = 17
            data.flen = 42
            data.ilen = 0
            data.attr = 0
            items.push(data.to_a)

            dialog.title = "S3 Configuration"
            s3conf = dialog.mixedform(text, items, 0, 0, 0)

            if dialog.exit_code == dialog.dialog_ok
                unless s3conf["AWS access key:"].empty? or s3conf["AWS secret key:"].empty? or s3conf["Bucket:"].empty? or s3conf["Endpoint:"].empty?
                    @conf['access_key'] = s3conf["AWS access key:"]
                    @conf['secret_key'] = s3conf["AWS secret key:"]
                    @conf['bucket'] = s3conf["Bucket:"]
                    @conf['endpoint'] = s3conf["Endpoint:"]
                    break
                end
            else
                @cancel = true
                break
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "S3 configuration Error"
            text = <<EOF

An error has been detected in the S3 configuration.

Please provide valid values for the required parameters.

EOF
            dialog.msgbox(text, 12, 41)

        end

    end

end

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:

