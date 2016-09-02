#!/usr/bin/env ruby

require 'yaml'
require './rb_config_utils.rb'

@userdata_path="/var/lib/cloud/instance/user-data.txt"
@userdataconfig_path="/var/lib/cloud/instance/user-data-config.yml"
@instanceid_path="/var/lib/cloud/data/instance-id"
@parameterlist_path="/var/lib/redborder/parameter-list.yml"
@initconf_path="/etc/redborder/init-conf.yml"

# Function to obtain instance-id from cloud-init files
# TODO: protect from file open failures or empty files
def getInstanceId()
    instanceid = nil
    File.open(@instanceid_path, "r") { |f|
        instanceid = f.gets.chomp
    }
    return instanceid
end

# Function to read user data parameters (not cloud-config) in yaml
# Returns a hash with parameters
# TODO: protect from mal-formed ymls.
def readUserData()
    userdata_config = {}
    #Read yml from user-data
    if File.exist? File.expand_path @userdataconfig_path
        userdata_config = YAML.load_file @userdataconfig_path
    else
        userdata_config = YAML.load_file @userdata_path
    end
    return userdata_config
end

# Function to read allowed user-data parameters
# Returns a hash with parameter data
# TODO: protect from errors reading file
def readParameterList()
    return YAML.load_file @parameterlist_path
end

# Function to check if a parameter value is correct, using allowed_pattern
# regex defined in parameter object (read from parameter-list.yml)
# Return true if value is valid or false if not.
def check_parameter_pattern(parameter, value)
    result = true
    if parameter.values[0].has_key?("allowed_pattern")
        prueba = /#{parameter.values[0]["allowed_pattern"]}/.match(value)
    end
    if parameter.values[0].has_key?("allowed_pattern") and
            /#{parameter.values[0]["allowed_pattern"]}/.match(value).nil?
        result = false
    end
    return result
end

def processUserDataParameters(userdata_config, parameter_list)
    config = {}
    parameter_list.each { |parameter|
        parameter_name=parameter.keys[0]
        #First calculate default value
        if parameter.values[0].has_key?("default")
            config[parameter_name] = parameter.values[0]["default"]
        else
            config[parameter_name] = nil
        end
        #Then, if there is a valid value, it will be overrided
        if userdata_config.has_key?(parameter_name)
            if check_parameter_pattern(parameter, userdata_config[parameter_name])
                config[parameter_name] = userdata_config[parameter_name]
            else
                puts "ERROR: Value #{userdata_config[parameter_name]} for parameter #{parameter_name} is not valid, setting to default (#{config[parameter_name] = parameter.values[0]["default"]})"
            end
        end
    }
    return config
end


# MAIN EXECUTION

userdata_config = readUserData()
parameter_list = readParameterList()
config = processUserDataParameters(userdata_config, parameter_list)

#Adding more parameters
if !config.has_key?("hostname") or config["hostname"] == "rbmanager"
    config["hostname"] = getInstanceId()
    puts "#{getInstanceId()}"
end

# Checking if mode is correct
if !Config_utils.check_mode(config["mode"])
    default_mode = parameter_list.select{|parameter| parameter.keys[0]=="mode"}[0]["mode"]["default"]
    puts "WARNING: unrecognized mode. Setting to #{default_mode} (default) mode "
    config["mode"] = default_mode
end

config["network"] = "dhcp"
File.write(@initconf_path, config.to_yaml)
