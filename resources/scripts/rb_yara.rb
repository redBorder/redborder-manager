#!/usr/bin/env ruby
# frozen_string_literal: true

# CONSTANTS
PATH_YARA_RULES = '/tmp/yara_rules_src'
PATH_RAILS = '/var/www/rb-rails'
TAR_NAME = 'yaraRules.tar.gz'
RAILS_ENV = ENV['RAILS_ENV'] || 'production'

# Usage help
def usage
  puts "rb_yara.rb - Script to manage Yara rules in redBorder. It can import or clear rules."
  puts "User must ensure that rvm gemset is web, otherwise rake version will be inconsistent."
  puts "Usage: rb_yara.rb [import|clear]"
  exit 1
end

# Parse action
def get_action(s)
  case s
  when /^i(m(p(o(r(t)?)?)?)?)?$/ then "import"
  when /^c(l(e(a(r)?)?)?)?$/     then "clear"
  else
    puts "Unknown action: #{s}"
    usage
  end
end

def log(msg)
  puts "[*] #{msg}"
end

def run_cmd(cmd, cwd: nil)
  log("Running: #{cmd}")
  success = Dir.chdir(cwd || Dir.pwd) { system(*cmd) }
  abort("Command failed: #{cmd}") unless success
end

# Create tarball with yara rules
def create_yara_rules_tar
  tar_path = File.join(PATH_YARA_RULES, TAR_NAME)
  log("Creating tarball #{tar_path} ...")
  run_cmd(["tar", "czf", TAR_NAME, *Dir.children(PATH_YARA_RULES)], cwd: PATH_YARA_RULES)

  log("Moving tarball to Rails app ..")
  run_cmd(["mv", tar_path, PATH_RAILS])
end

# Import rules into Rails
def import_yara_rules_tar
  log("Importing #{TAR_NAME} into Rails ..")
  run_cmd(["bundle", "exec", "rake", "redBorder:import_yara_rules[#{TAR_NAME}]", "RAILS_ENV=#{RAILS_ENV}"], cwd: PATH_RAILS)
end

# Clear yara rules
def clear_yara_rules
  log("Clearing yara rules in Rails ..")
  run_cmd(["bundle", "exec", "rake", "redBorder:clear_yara_rules", "RAILS_ENV=#{RAILS_ENV}"], cwd: PATH_RAILS)

  # log("Clearing yara rules from all Logstash nodes ..")
  # success = system("rb_manager_ssh.sh all rm -f /usr/share/logstash/yara_rules/rules.yara")
  # abort("Failed to clear remote yara rules") unless success

  log("Yara rules cleared everywhere.")
end

def validation
  current = `rvm current`.strip
  unless current == 'ruby-2.7.5@web'
    log("ERROR: Wrong Ruby version of gemset: #{current}")
    usage
    return false
  end
  if ARGV.length != 1
    log('ERROR: Check number of arguments')
    usage
    return false
  end
  return true
end

exit 1 unless validation

# Main
case get_action(ARGV[0])
when "import"
  create_yara_rules_tar
  import_yara_rules_tar
when "clear"
  clear_yara_rules
end
