#!/usr/bin/env ruby

require 'yaml'

module Config_utils
    #Function to check if mode is valid (if defined in mode-list.yml)
    #Returns true if it's valid and false if not
    #TODO: protect from exception like file not found
    def Config_utils.check_mode(mode)
        mode_list = YAML.load_file("/var/lib/redborder/mode-list.yml")
        return mode_list.include?(mode)
    end
end
