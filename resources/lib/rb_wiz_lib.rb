#!/usr/bin/env ruby

require 'mrdialog'
require 'net/ip'
require 'system/getifaddrs'

class NetDev
    
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

    def check_ipv4(ipv4)
        ret = true
        begin
            x = NetAddr::CIDRv4.create("#{ipv4[:ip].nil? ? "0.0.0.0" : ipv4[:ip]}/#{ipv4[:netmask].nil? ? "255.255.255.255" : ipv4[:netmask]}")
        rescue NetAddr::ValidationError => e
            # error: netmask incorrect
            ret = false
        rescue => e
            # general error
            ret = false
        end
        ret
    end

    def get_network(devname)
        hsh = {}
        # looking for device with default route
        Net::IP.routes.each do |r|
            unless r.to_h[:via].nil?
                if r.to_h[:prefix] == "default" or r.to_h[:prefix] == "0.0.0.0/0"
                    hsh[r.to_h[:dev]] = { :default_gateway => r.to_h[:via] }
                    break
                end
            end
        end
        System.get_ifaddrs.each do |i|
            
        end
        hsh
    end
   
end

# Class to create a Network configuration box
class NetConf < NetDev

    attr_accessor :configured_devices, :network_conf

    def initialize
        @configured_devices = {}
        @network_conf = {}
    end

    def doit
        dialog = MRDialog.new
        dialog.clear = true
        dialog.title = "CONFIGURE NETWORK"
        loop do
            text = <<EOF
This is a menubox to select a network device.

You can use the UP/DOWN arrow keys, the first
letter of the choice as a hot key, or the
number keys 1-9 to choose an option.

Please, choose a network device to configure:

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
                data.item = "MAC: "+netdevprop["MAC"]+", Vendor: "+netdevprop["ID_MODEL_FROM_DATABASE"]
                items.push(data.to_a)
            end
            height = 0
            width = 0
            menu_height = 4
            selected_item = dialog.menu(text, items, height, width, menu_height)

            if selected_item
                dev = DevConf.new(selected_item)
                dev.doit
            else
                break
            end
        end
    end



end

class DevConf < NetDev
        
        attr_accessor :device_name

        def initialize(x)
            @device_name = x
            @hsh = {}
        end

        def show_warning
            msg = ''
            label = 'IP:'
            if @hsh[label].length == 0
                msg << "#{label} field is empty"
            end
            label = 'Netmask:'
            if @hsh[label].length == 0 or !checkip(@hsh[label])
                msg << "\n"
                msg << "#{label} field is empty"
            elsif !checkip(@hsh[label])
                msg << "\n"
                msg << "#{label} incorrect value"
            end
            dialog = MRDialog.new
            dialog.title = "ERROR"
            dialog.clear = true
            dialog.msgbox(msg, 10, 41)
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
            data.select = true
            items.push(data.to_a)

            data = radiolist_data.new
            data.tag = "Static"
            data.item = "IP/Netamsk and Gateway static values"
            data.select = false
            items.push(data.to_a)

            dialog.title = "Network Device Mode"
            selected_item = dialog.radiolist(text, items)
            exit_code = dialog.exit_code

            case exit_code
            when dialog.dialog_ok
                # OK Pressed

                if selected_item == "Static"
                    dialog = MRDialog.new
                    dialog.clear = true
                    text = <<EOF
        
You are about to configure the network device #{@device_name}. It has the following propierties:
EOF
                    netdevprop = netdev_property(@device_name)
                    text += "MAC: #{netdevprop["MAC"]}\n"
                    text += "DRIVER: #{netdevprop["ID_NET_DRIVER"]}\n" unless netdevprop["ID_NET_DRIVER"].nil?
                    text += "PCI PATH: #{netdevprop["ID_PATH"]}\n" unless netdevprop["ID_PATH"].nil?
                    text += "VENDOR: #{netdevprop["ID_VENDOR_FROM_DATABASE"]}\n" unless netdevprop["ID_VENDOR_FROM_DATABASE"].nil?
                    text += "MODEL: #{netdevprop["ID_MODEL_FROM_DATABASE"]}\n" unless netdevprop["ID_MODEL_FROM_DATABASE"].nil?
                    text += "STATUS: #{netdevprop["STATUS"]}\n" unless netdevprop["STATUS"].nil?
        
                    text += " \n"
        
                    @hsh['IP:'] = get_network(@device_name)[:ip]
                    @hsh['Netmask:'] = get_network(@device_name)[:netmask]
                    @hsh['Gateway:'] = get_network(@device_name)[:gateway]
        
                    flen = 20
                    form_data = Struct.new(:label, :ly, :lx, :item, :iy, :ix, :flen, :ilen)
        
                    loop do
                        items = []
                        label = "IP:"
                        data = form_data.new
                        data.label = label
                        data.ly = 1
                        data.lx = 1
                        data.item = @hsh[label]
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
                        data.item = @hsh[label]
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
                        data.item = @hsh[label]
                        data.iy = 3
                        data.ix = 10
                        data.flen = flen
                        data.ilen = 0
                        items.push(data.to_a)
        
                        dialog.title = "Network configuration for #{@device_name}"
                        @hsh = dialog.form(text, items, 20, 60, 0)
        
                    end
                else
                    # selected_item == "Dynamic"

                end

            when dialog.dialog_cancel
                # Cancel Pressed

            when dialog.dialog_esc
                # Escape Pressed

            end
            


        end

end


## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
