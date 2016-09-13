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

    # TODO ipv6 support
    def get_ipv4_network(devname)
        hsh = {}
        # looking for device with default route
        Net::IP.routes.each do |r|
            unless r.to_h[:via].nil?
                if r.to_h[:dev] == devname
                    if r.to_h[:prefix] == "default" or r.to_h[:prefix] == "0.0.0.0/0"
                        hsh[:gateway] = r.to_h[:via]
                        break
                    end
                end
            end
        end
        System.get_all_ifaddrs.each do |i|
            if i[:interface].to_s == devname
                if i[:inet_addr].ipv4?
                    hsh[:ip] = i[:inet_addr].to_s
                    hsh[:netmask] = i[:netmask].to_s
                end
            end
        end
        hsh
    end
  
end

# Class to create a Network configuration box
class NetConf < WizConf

    attr_accessor :conf, :cancel

    def initialize
        @cancel = false
        @conf = []
        @confdev = {}
        @devmode = { "dhcp" => "Dynamic", "static" => "Static" }
        @devmodereverse = { "Dynamic" => "dhcp", "Static" => "static" }
    end

    def doit
        dialog = MRDialog.new
        dialog.clear = true
        dialog.title = "CONFIGURE NETWORK"
        loop do
            text = <<EOF

This is the network device configuration box.

Please, choose a network device to configure. Once you
have entered and configured all devices, you must select 
last choise (Finalize) and 'Accept' to continue.

Any device not configured will be set to Dynamic (DHCP)
mode by default.
 
EOF
            items = []
            menu_data = Struct.new(:tag, :item)
            data = menu_data.new
            # loop over list of net devices
            listnetdev = Dir.entries("/sys/class/net/").select {|f| !File.directory? f}
            listnetdev.each do |netdev|
                # loopback and devices with no pci nor mac are not welcome!
                next if netdev == "lo"
                netdevprop = netdev_property(netdev)
                next unless (netdevprop["ID_BUS"] == "pci" and !netdevprop["MAC"].nil?)
                data.tag = netdev
                # set default value
                @confdev[netdev] = {"mode" => "dhcp"} if @confdev[netdev].nil?
                data.item = "MAC: "+netdevprop["MAC"]+", Vendor: "+netdevprop["ID_MODEL_FROM_DATABASE"]
                items.push(data.to_a)
            end
            data.tag = "Finalize"
            data.item = "Finalize network device configuration"
            items.push(data.to_a)
            height = 0
            width = 0
            menu_height = 4
            selected_item = dialog.menu(text, items, height, width, menu_height)

            if selected_item
                unless selected_item == "Finalize"
                    dev = DevConf.new(selected_item)
                    unless @confdev[selected_item].nil?
                        dev.conf = {'IP:' => @confdev[selected_item]["ip"],
                                    'Netmask:' => @confdev[selected_item]["netmask"],
                                    'Gateway:' => @confdev[selected_item]["gateway"],
                                    'Mode:' => @devmode[@confdev[selected_item]["mode"]]}
                    end
                    dev.doit
                    unless dev.conf.empty?
                        @confdev[selected_item] = {}
                        @confdev[selected_item]["mode"] = @devmodereverse[dev.conf['Mode:']]
                        if dev.conf['Mode:'] == "Static"
                            @confdev[selected_item]["ip"] = dev.conf['IP:']
                            @confdev[selected_item]["netmask"] = dev.conf['Netmask:']
                            unless dev.conf['Gateway:'].nil? or dev.conf['Gateway:'] == ""
                                @confdev[selected_item]["gateway"] = dev.conf['Gateway:']
                            end

                        end
                    end
                else
                    break
                end
            else
                # Cancel pressed
                @cancel = true
                break
            end
        end
        @confdev.each_key do |interface|
            @conf << @confdev[interface].merge("device" => interface)
        end
    end
end

class DevConf < WizConf
        
    attr_accessor :device_name, :conf, :cancel

    def initialize(x)
        @cancel = false
        @device_name = x
        @conf = {}
    end

    def doit
        # first, set mode dynamic or static
        dialog = MRDialog.new
        dialog.clear = true
        text = <<EOF

Please, select type of configuration:

Dynamic: set dynamic IP/Netmask and Gateway
         via DHCP client.
Static: You will provide configuration for
        IP/Netmask and Gateway, if needed.
 
EOF
        items = []
        radiolist_data = Struct.new(:tag, :item, :select)
        data = radiolist_data.new
        data.tag = "Dynamic"
        data.item = "IP/Netmask and Gateway via DHCP"
        if @conf['Mode:'].nil?
            data.select = true # default
        else
            if @conf['Mode:'] == "Dynamic"
                data.select = true
            else
                data.select = false
            end
        end
        items.push(data.to_a)

        data = radiolist_data.new
        data.tag = "Static"
        data.item = "IP/Netamsk and Gateway static values"
        if @conf['Mode:'].nil?
            data.select = false # default
        else
            if @conf['Mode:'] == "Static"
                data.select = true
            else
                data.select = false
            end
        end
        items.push(data.to_a)

        dialog.title = "Network Device Mode"
        selected_item = dialog.radiolist(text, items)
        exit_code = dialog.exit_code

        case exit_code
        when dialog.dialog_ok
            # OK Pressed
            
            # TODO ipv6 support
            if selected_item == "Static"
                dialog = MRDialog.new
                dialog.clear = true
                text = <<EOF
        
You are about to configure the network device #{@device_name}. It has the following propierties:
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
    
                @conf['IP:'] = get_ipv4_network(@device_name)[:ip] if @conf['IP:'].nil?
                @conf['Netmask:'] = get_ipv4_network(@device_name)[:netmask] if @conf['Netmask:'].nil?
                @conf['Gateway:'] = get_ipv4_network(@device_name)[:gateway] if @conf['Gateway:'].nil?
    
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
                    ret = true
                    if @conf.empty?
                        # Cancel was pressed
                        break
                    else
                        # ok pressed
                        @conf['Mode:'] = "Static"
                        if Config_utils.check_ipv4({:ip => @conf['IP:']}) and Config_utils.check_ipv4({:netmask => @conf['Netmask:']})
                            # seems to be ok
                            unless @conf['Gateway:'] == ""
                                if Config_utils.check_ipv4({:ip => @conf['Gateway:']})
                                    # seems to be ok
                                    ret = false
                                end
                            else
                                ret = false
                            end
                        else
                            # error!
                            ret = true
                        end
                    end
                    if ret
                        # error detected
                        dialog = MRDialog.new
                        dialog.clear = true
                        dialog.title = "ERROR in network configuration"
                        text = <<EOF

We have detected an error in network configuration.

Please, review IP/Netmask and/or Gateway address configuration.
EOF
                        dialog.msgbox(text, 10, 41)
                    else
                        # all it is ok, breaking loop
                        break
                    end
                end
            else
                # selected_item == "Dynamic"
                @conf['Mode:'] = "Dynamic"
            end

        when dialog.dialog_cancel
            # Cancel Pressed

        when dialog.dialog_esc
            # Escape Pressed

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
        if @conf["Hostname:"] == "rbmanager" or @conf["Hostname:"] == "localhost"
            @conf["Hostname:"] = "rb-#{rand(36**10).to_s(36)}"
            @conf["Domain name:"] = "redborder.cluster"
        end

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF

Please, set hostname and domain name.
 
The hostname may only contain ASCII letters 'a'
through 'z' (in a case-insensitive manner), the
digits '0' through '9' and the hyphen ('-').
 
The RFC1123 permits hostname labels to start with digits
or letters but not to start or end with hyphen.
Also, the hostname and each label of the domain name
must be between 1 and 63 characters, and the entire
hostname has a maximum of 253 ASCII characters.

Please, consult RFC1178 to choose an appropiate hostname.
 
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

            dialog.title = "Hostname and domain name configuration"
            host = dialog.mixedform(text, items, 24, 60, 0)
            
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
            dialog.title = "ERROR in name configuration"
            text = <<EOF

We have detected an error in hostname or domain name configuration.

Please, review character set and length for name configuration.
EOF
            dialog.msgbox(text, 10, 41)

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

            dialog.title = "DNS configuration"
            dns = dialog.mixedform(text, items, 20, 42, 0)
            
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
            dialog.title = "ERROR in DNS or search configuration"
            text = <<EOF

We have detected an error in DNS configuration.

Please, review content for DNS configuration. Remember, you
must introduce only IPv4 address in dot notation.
EOF
            dialog.msgbox(text, 12, 41)

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

class SerfSyncConf < WizConf

    attr_accessor :conf, :cancel

    def initialize()
        @cancel = false
        @conf = {}
    end

    def doit
        
        sync = {}

        loop do
            dialog = MRDialog.new
            dialog.clear = true
            dialog.insecure = true
            text = <<EOF
 
Please, set the synchronism network.
 
You must set a synchronism network in two formats:
- IPv4 CIDR format: i.e. 192.168.1.0/24
- IPv4 mask format: i.e. 192.168.1.0/255.255.255.0
 
This network is needed to connect nodes and build the cluster. Also,
internal services will use it to communicate between them.

Usually, this network has no default gateway and is isolated from
rest of the networks.
 
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

            dialog.title = "Sync Network configuration"
            sync = dialog.mixedform(text, items, 24, 54, 0)

            if dialog.dialog_ok
                if Config_utils.check_ipv4(sync["Sync Network:"])
                    # it is ok
                    break
                else
                    # error
                end
            else
                # Cancel button pushed
                @cancel = true
                break
            end

            # error, do another loop
            dialog = MRDialog.new
            dialog.clear = true
            dialog.title = "ERROR in Sync Network configuration"
            text = <<EOF

We have detected an error in Sync Network configuration.

Please, review content for Sync Network configuration. Remember, you
must introduce only IPv4 address in dot notation followed by mask
length or netmask, i.e. 192.168.100.0./24.
 
EOF
            dialog.msgbox(text, 15, 41)

        end

        # normalizing
        sync_netaddr = NetAddr::CIDRv4.create(sync["Sync Network:"])
        @conf = "#{sync_netaddr.network}#{sync_netaddr.netmask}"
 
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

Please, select type of configuration:

Multicast: set Multicast mode of operation for serf agent.
           In this mode, serf autodiscover the cluster using
           a multicast address and the domain name as cluster domain.
Unicast:   set Unicast mode of operation for serf agent.
           In this mode, serf try to join to an existing cluster
           scanning via ARP using the Synchronism network.

In both cases, the Synchronism network is used to find the correct
network device and bind to it.
 
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

        dialog.title = "Communication cluster mode"
        selected_item = dialog.radiolist(text, items)

        if dialog.dialog_ok
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
            dialog.title = "Serf encryption key"
            text = <<EOF

Please, provide a password for encryption of serf network traffic.

This password will avoid not allowed connection from nodes not belonging to the cluster. Any printable character is allowed, and you can use from 6 to 20 characters.
  
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
 

            result = dialog.passwordform(text, items, 20, 60, 0)

            if dialog.dialog_ok
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
            dialog.title = "ERROR in the Serf encryption key"
            text = <<EOF

We have detected an error in Serf encryption key.

Please, remember that the minimum length is 6 and maximum is 20 characters. Also, both fields must match.
 
EOF
            dialog.msgbox(text, 15, 41)
            
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

        if File.exist?("#{ENV['RBETC']}/mode-list.yml")
            modelist = YAML.load_file("#{ENV['RBETC']}/mode-list.yml")
        end
        
        dialog = MRDialog.new
        dialog.clear = true
        text = <<EOF

Please, select mode of operation of the manager node.

If this is the first installation of a redborder manager, and you are planning to create a cluster based on multiple nodes, you should select 'core' mode. For the rest of nodes, you should select 'custom' mode.

If this is an stand alone manager installation, you should select 'full' mode.
 
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

        dialog.title = "Set manager mode"
        selected_item = dialog.radiolist(text, items)

        if dialog.dialog_ok
            @conf = selected_item
        else
            @cancel = true
        end
    end
end


## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
