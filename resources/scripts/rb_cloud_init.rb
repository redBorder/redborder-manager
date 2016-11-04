#!/usr/bin/env ruby

require 'yaml'
require '/usr/lib/redborder/lib/rb_config_utils.rb'

@userdata_path="/var/lib/cloud/instance/user-data.txt"
@userdataconfig_path="/var/lib/cloud/instance/user-data-config.yml"
@instanceid_path="/var/lib/cloud/data/instance-id"
@initconf_path="/etc/redborder/rb_init_conf.yml"

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

############ Parameter configuration functions ############

#Function to configure hostname
def config_hostname(config, userdata_config)
    if userdata_config.has_key?("hostname") and Config_utils.check_hostname(userdata_config["hostname"])
        config["hostname"] = userdata_config["hostname"]
    else
        config["hostname"] = getInstanceId()
    end
    return config
end

#Function to configure serf parameters
def config_serf(config, userdata_config)
    #Multicast configuration
    config["serf"] = {}
    if userdata_config.has_key?("multicast_enabled") and userdata_config.is_a(boolean)
        config["serf"]["multicast"] = userdata_config["multicast_enabled"]
    else #Default for cloud environment is false
        config["serf"]["multicast"] = false
    end

    #Encrypt key generation
    if userdata_config.has_key?("serf_encryptkey") and Config_utils.check_encryptkey(userdata_config.key("serf_encryptkey"))
        config["serf"]["encrypt_key"] = userdata_config.key("serf_encryptkey")
    else
        #encrypt key must be generated from cdomain
        config["serf"]["encrypt_key"] = Config_utils.get_encrypt_key(config["cdomain"])
    end

    #Sync_net configuration
    if userdata_config.has_key?("sync_net") and Config_utils.check_ipv4(userdata_config["sync_net"])
        config["serf"]["sync_net"] = userdata_config["sync_net"]
    else #TODO: search for interface that don't have default gateway
        puts "WARN: sync_net not provided"
        config["serf"]["sync_net"] = nil #TODO: Must be calculated via rb_config_utils function
    end
    return config
end

def config_cdomain(config, userdata_config)
    if userdata_config.has_key?("cdomain") and Config_utils.check_domain(userdata_config["cdomain"])
        config["cdomain"] = userdata_config["cdomain"]
    else
        puts "WARN: cdomain not provided, setting to redborder.cluster"
        config["cdomain"] = "redborder.cluster"
    end
    return config
end

def config_mode(config, userdata_config)
    if userdata_config.has_key?("mode") and Config_utils.check_mode(userdata_config["mode"])
        config["mode"] = userdata_config["mode"]
    else
        puts "WARN: mode not provided, setting to custom"
        config["mode"] = "custom"
    end
    return config
end

def config_postgresql(config, userdata_config)
    if !userdata_config.has_key?("sql_host") or !Config_utils.check_sql_host(userdata_config["sql_host"])
        puts "WARN: sql_host not valid, ignoring sql configuration"
    elsif !userdata_config.has_key?("sql_port") or !Config_utils.check_sql_port(userdata_config["sql_port"])
        puts "WARN: sql port not valid, ignoring sql configuration"
    elsif !userdata_config.has_key?("sql_superuser") or !Config_utils.check_sql_superuser(userdata_config["sql_superuser"])
        puts "WARN: sql superuser not valid, ignoring sql configuration"
    elsif !userdata_config.has_key?("sql_password") or !Config_utils.check_sql_password(userdata_config["sql_password"])
        puts "WARN: sql password not valid, ignoring sql configuration"
    else
        config["postgresql"] = {}
        config["postgresql"]["host"] = userdata_config["sql_host"]
        config["postgresql"]["port"] = userdata_config["sql_port"]
        config["postgresql"]["superuser"] = userdata_config["sql_superuser"]
        config["postgresql"]["password"] = userdata_config["sql_password"]
    end
    return config
end

def config_s3(config, userdata_config)
    if !userdata_config.has_key?("s3_bucket") or !Config_utils.check_s3bucket(userdata_config["s3_bucket"])
        puts "WARN: s3_bucket not valid, ignoring s3 configuration"
    elsif !userdata_config.has_key?("s3_endpoint") or !Config_utils.check_s3endpoint(userdata_config["s3_endpoint"])
        puts "WARN: s3_endpoint not valid, ignorig s3 configuration"
    else
        config["s3"] = {}
        if userdata_config.has_key?("aws_access_key") and Config_utils.check_accesskey(userdata_config["aws_access_key"]) and
                userdata_config.has_key?("aws_secret_key") and Config_utils.check_secretkey(userdata_config["aws_secret_key"])
            config["s3"]["access_key"] = userdata_config["aws_access_key"]
            config["s3"]["secret_key"] = userdata_config["aws_secret_key"]
        end
        config["s3"]["bucket"] = userdata_config["s3_bucket"]
        config["s3"]["endpoint"] = userdata_config["s3_endpoint"]
    end
    return config
end

def config_elasticache(config, userdata_config)
    if userdata_config.has_key?("elasticache_cfg_address") and Config_utils.check_elasticache_cfg_address(userdata_config["elasticache_cfg_address"])
        puts "INFO: Elasticache configuration provided"
        config["elasticache"] = {}
        config["elasticache"]["cfg_address"] = userdata_config["elasticache_cfg_address"]
        if userdata_config.has_key?("elasticache_cfg_port") and Config_utils.check_elasticache_cfg_port(userdata_config["elasticache_cfg_port"])
            config["elasticache"]["cfg_port"] = userdata_config["elasticache_cfg_port"]
        else
            #Set memcached default port
            config["elasticache"]["cfg_port"] = 11211
        end
    end
    return config
end

# MAIN EXECUTION

userdata_config = readUserData()
#Processing parameters
config = {}
config = config_hostname(config, userdata_config)
config = config_cdomain(config, userdata_config)
config = config_serf(config, userdata_config)
config = config_mode(config, userdata_config)
config = config_postgresql(config, userdata_config)
config = config_s3(config, userdata_config)
config = config_elasticache(config, userdata_config)

File.write(@initconf_path, config.to_yaml)
system("systemctl start rb-init-conf")
