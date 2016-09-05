#!/usr/bin/env ruby

require 'yaml'
require 'net/ip'
require 'system/getifaddrs'
require 'netaddr'

@modelist_path="/usr/lib/redborder/mode-list.yml"

module Config_utils
    #Function to check if mode is valid (if defined in mode-list.yml)
    #Returns true if it's valid and false if not
    #TODO: protect from exception like file not found
    def Config_utils.check_mode(mode)
        mode_list = YAML.load_file(@modelist_path)
        return mode_list.include?(mode)
    end

    # Function to check a valid IPv4 IP address
    def Config_utils.check_ipv4(ipv4)
      ret = true
      begin
        x = NetAddr::CIDRv4.create("#{ipv4[:ip].nil? ? "0.0.0.0" : ipv4[:ip]}/#{ipv4[:netmask].nil? ? "255.255.255.255" : ipv4[:netmask]}")
      rescue NetAddr::ValidationError => e
        # error: netmask incorrect
        ret = false
      rescue => e
        # general error"
        ret = false
      end
      ret
    end

   # Functon to chefk a valid domain. Based on rfc1123 and sethostname().
   # Suggest rfc1178
   # Max of 253 characters with hostname
   def Config_utils.check_domain(domain)
     ret = false
     unless (domain =~ /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/).nil?
       ret = true
     end
     ret
   end

   # Function to check hostname. # Based on rfc1123 and sethostname()
   # Max of 63 characters
   def Config_utils.check_hostname(name)
     ret = false
     unless (name =~ /^([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/).nil?
       ret = true
     end
     ret
   end

end
