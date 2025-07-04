
#!/usr/bin/env ruby
require 'getopt/long'
require File.join(ENV['RBDIR'].nil? ? '/usr/lib/redborder' : ENV['RBDIR'],'lib/rb_config_utils.rb')

def usage
  puts "Usage: #{$0} [-h|--help]"
  puts "  -h, --help\tShow this help message"
  puts
  puts "Set the serf encryption key in /root/rb_init_conf.yml"
  puts "The encryption key is used to secure communication between serf nodes in the cluster"
  puts
  puts "If the file exists, it will update the existing serf:encryption_key value"
  puts "If the file or key doesn't exist, it will create the necessary structure"
  exit 0
end

def serf_password
  print "Please enter serf password: "
  pass1 = STDIN.noecho(&:gets).chomp
  puts ""
  print "Please enter serf password again: "
  pass2 = STDIN.noecho(&:gets).chomp
  puts ""
  
  if pass1 == pass2
    return pass1
  else
    puts "Passwords do not match. Please try again."
    serf_password
  end
end

def save_serf_encryption_key(pass)
  # Load config file
  config_file = "/root/rb_init_conf.yml"
  config = YAML.load_file(config_file) rescue {}

  # Set serf encryption key
  config["serf"] ||= {}
  config["serf"]["encryption_key"] = Config_utils.get_encrypt_key(pass)

  # Save config back to file
  File.open(config_file, "w") do |f|
    f.write(config.to_yaml)
  end
end

opt = Getopt::Long.getopts(
  ["--help", "-h", Getopt::BOOLEAN]
)

usage if opt["help"]

## MAIN ##
save_serf_encryption_key (serf_password)
