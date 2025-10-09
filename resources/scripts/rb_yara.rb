#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

# === CONSTANTS ===
DEFAULT_PATH_YARA_RULES = '/tmp/yara_rules_src'
PATH_RAILS = '/var/www/rb-rails'
RAILS_ENV = ENV['RAILS_ENV'] || 'production'

# === HELP ===
def usage
  puts <<~HELP
    Usage:
      rb_yara import [yara_rules_path]
      rb_yara clear

    Examples:
      rb_yara import                  # Uses default path: /tmp/yara_rules_src
      rb_yara import /tmp/yara_rules_sources/6
      rb_yara clear
  HELP
  exit 1
end

# === HELPER FUNCTIONS ===
def log(msg)
  puts "[*] #{msg}"
end

def run_cmd(cmd, cwd: nil)
  log("Running: #{cmd.join(' ')}")
  success = Dir.chdir(cwd || Dir.pwd) { system(*cmd) }
  abort("Error executing: #{cmd.join(' ')}") unless success
end

# === IMPORT YARA RULES ===
def import_yara_rules(source_path, source_id=nil)
  unless Dir.exist?(source_path)
    abort("Path not found: #{source_path}")
  end

  tar_name = "yaraRules_#{File.basename(source_path)}.tar.gz"
  tmp_tar_path = File.join("/tmp", tar_name)
  
  log("Creating temporary file #{tmp_tar_path} from #{source_path} ...")
  run_cmd(["tar", "czf", tmp_tar_path, "-C", source_path, "." ])
  
  dest_path = File.join(PATH_RAILS, tar_name)
  log("Moving file to #{dest_path} ...")
  FileUtils.mv(tmp_tar_path, dest_path, force: true)

  log("Importing YARA rules into Rails ...")
  rake_task = "redBorder:import_yara_rules[#{tar_name}#{source_id ? ",#{source_id}" : ""}]"
  run_cmd(["bundle", "exec", "rake", rake_task, "RAILS_ENV=#{RAILS_ENV}"], cwd: PATH_RAILS)

  log("Import completed for #{source_path}")
ensure
  FileUtils.rm_f(File.join(PATH_RAILS, tar_name)) if File.exist?(File.join(PATH_RAILS, tar_name))
end

# === CLEAR YARA RULES ===
def clear_yara_rules
  log("Clearing YARA rules from the system ...")
  run_cmd(["bundle", "exec", "rake", "redBorder:clear_yara_rules", "RAILS_ENV=#{RAILS_ENV}"], cwd: PATH_RAILS)
  log("YARA rules cleared.")
end

# === MAIN ===
usage if ARGV.empty?

action = ARGV[0].downcase
source_path = ARGV[1] || DEFAULT_PATH_YARA_RULES

case action
when "import"
  import_yara_rules(source_path)
when "clear"
  clear_yara_rules
else
  usage
end
