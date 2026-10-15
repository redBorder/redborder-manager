#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2016 ENEO Tecnología S.L.
## This file is part of redBorder.
## redBorder is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
## redBorder is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License License for more details.
## You should have received a copy of the GNU Affero General Public License License
## along with redBorder. If not, see <http://www.gnu.org/licenses/>.
########################################################################

require 'optparse'
require 'yaml'
require 'chef'
require 'fileutils'
require 'syslog'
require 'io/console'

def validate_options(options)
  # -- 1. Needs -b or -r
  unless options[:backup] || options[:restore]
    abort("Error: You must specify either --backup (-b) or --restore (-r).")
  end

  # -- 2. Needs at least one of -f or -s or -p
  unless options[:file] || options[:s3]
    abort("Error: You must specify at least one of --file (-f), --s3 (-s).")
  end

  # -- 3. -f and -s cannot be together
  if options[:file] && options[:s3]
    abort("Error: --file (-f) and --s3 (-s) cannot be used together.")
  end

  # -- 5. -k cannot be used without -s
  if options[:k] && !options[:s3]
    abort("Error: --bucket (-k) can only be used with --s3 (-s).")
  end

  # -- 6. --restore (-r) requires -f or -s
  if options[:restore] && !(options[:file] || options[:s3])
    abort("Error: --restore (-r) requires either --file (-f) or --s3 (-s).")
  end
end

def check_single_use!(options, key, option_name)
  if options.key?(key)
    abort("Error: #{option_name} cannot be used more than once.")
  end
end

# -- Indicate Status for each step
def print_status(status: :OK, fill: "-")
  color  = COLORS[status] || "\e[36m"
  reset  = COLORS[:RESET]
  message = " [ #{color}#{status}#{reset} ] "
  puts message.center(TERMINAL_WIDTH, fill)
end

def log (message, type)
  # $0 is the current script name
  if type == "warning"
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning message }
  elsif type == "error"
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.err message }
  elsif type == "info"
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.info message }
  end
end

def check_oper (cmd, type, message)
  commands = cmd.split(';')
  log_file = "/root/.#{type}-manager.log"

  puts "\t#{message}" if OPT[:verbose]
  File.open(log_file, "a") { |f| f.puts message }
  
  check = false
  commands.each do |c|
    c.strip!
    output = `#{c} 2>&1`
    puts "\t\t#{output}" if OPT[:verbose]
    File.open(log_file, "a") { |f| f.puts output }
    check = $?.success?
  end
  
  if check
    print_status(status: :OK) if OPT[:verbose]
    log("#{message}  [  OK  ]", "info")
  else
    print_status(status: :FAIL)
    log("Error in process: #{message} - STOP", "error")
    exit 0
  end
end

def read_chef_file
  # Chef config
  Chef::Config.from_file("/root/.chef/knife.rb")
  Chef::Config[:node_name]  = "admin"
  Chef::Config[:client_key] = "/etc/chef/admin.pem"
  Chef::Config[:http_retry_count] = 5
end

def check_leader()
  serf_output = `serf members 2>&1`
  check_oper("serf members", 'backup', 'Checking leader of cluster...')
  leader_data = serf_output.each_line.map { |l| l.strip }.find { |l| l.include?("leader=ready") }
  if leader_data.nil?
    puts "No leader node found."
    exit 1
  end
  if HOSTNAME != leader_data.split.first
    puts "Need to be executed in cluster leader node:\n\t#{leader_data.split.first} | #{leader_data.split[1].split(':').first}"
    exit 1
  end
end

# Helper to process a folder into unique/common
def process_folder(base, dest, hashes = nil, deduplicate: false)
  Dir.glob("#{base}/**/*", File::FNM_DOTMATCH).each do |path|
    next if [".", ".."].include?(File.basename(path))
    next if File.directory?(path)
    next if PATH_TO_EXCLUDE.any? { |ex| path.start_with?(ex) }

    final_dest = dest 

    if deduplicate
      digest = Digest::SHA256.file(path).hexdigest
      final_dest   = hashes[digest] ? dest[:common] : dest[:unique]
      hashes[digest] ||= path
    end

    rel_path = path.sub(%r{^/}, "")
    target   = File.join(final_dest, rel_path)

    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(path, target)
  end
end

def limit_saved_files(pattern, limit)
  backups = Dir.glob(pattern).sort_by { |f| File.mtime(f) }

  if backups.size > limit
    old_backups = backups[0...(backups.size - limit)]
    old_backups.each do |dir|
      puts "Removing old backup: #{dir}"
      FileUtils.rm_rf(dir)
    end
  end
end

def select_backup(opt_f, opt_s)
  backups = []

  # -- Local backups
  if opt_f
    base_dir = "/tmp/backups"
    local_backups = Dir.glob(File.join(base_dir, "backup-*")).select { |f| File.directory?(f) }
    backups += local_backups
  end

  # -- S3 backups
  if opt_s
    s3bucket = `cat /etc/druid/_common/common.runtime.properties | grep druid.storage.bucket= | tr '=' ' '|awk '{print $2}'`.strip
    cmd = "s3cmd -c #{opt_s} ls s3://#{s3bucket}/backup/"
    output = `#{cmd}`
    s3_backups = output.split("\n").map { |line| line.split.last }.compact
    backups += s3_backups
  end

  if backups.empty?
    abort("No backups found to restore based on selected options.")
  end

  # -- Display menu
  puts "Available backups:"
  backups.each_with_index do |b, i|
    type = File.directory?(b) ? "Local" : "S3"
    puts "  [#{i + 1}] #{File.basename(b)} (#{type})"
  end

  print "Choose a backup to restore [1-#{backups.size}]: "
  choice = $stdin.gets.to_i

  if choice < 1 || choice > backups.size
    abort("Invalid choice.")
  end

  selected = backups[choice - 1]
  puts "You selected: #{File.basename(selected)}"

  selected
end


# Global var
DATE                           = Time.new.strftime("%Y%m%d-%H%M%S")
HOSTNAME                       = `hostname -s 2>/dev/null`.strip()
ENCRYPTED_DATA_BAG_SECRET_PATH = "/etc/chef/encrypted_data_bag_secret"
LIMIT_FILES_SAVE               = 5
TERMINAL_WIDTH                 = IO.console.winsize[1] rescue 120
VALID_MODES                    = %w[full s3 core chef]
TAR_CREATE                     = "tar --ignore-failed-read -zcPf"
TAR_EXTRACT                    = "tar --ignore-failed-read -zvxPf"

COLORS = {
  OK:    "\e[32m",
  FAIL:  "\e[31m",
  WARN:  "\e[33m",
  RESET: "\e[0m"
}

PATH_TO_EXCLUDE = [
  "/var/opt/opscode/nginx/html",
  "/root/.chef/syntax_check_cache",
  "/var/chef/cookbooks",
  "/var/chef/backup",
  "/var/chef/data",
  "/var/lib/pgsql/data"
]

PATH_TO_BACKUP_UNIQUE = [
  "/etc/chef/client.rb",
  "/etc/chef/chef_guid",
  "/etc/chef/client.pem",
  "/etc/sysconfig/druid_*",
  "/etc/sysconfig/network",
  "/etc/sysconfig/webui",
  "/etc/sysconfig/zookeeper",
  "/etc/sysconfig/network-scripts/ifcfg-ens*",
  "/boot/grub2",
  "/etc/hosts",
  "/etc/hostname",
  "/etc/fstab",
  "/etc/ssh/"
]

PATH_TO_BACKUP_LEADER = [
  "/etc/opscode/admin.pem",
  "/etc/opscode/pivotal.pem",
  "/etc/opscode/redborder-validator.pem",
  "/etc/opscode/webui_priv.pem",
  "/etc/opscode/webui_pub.pem",
  "/var/chef/nodes",
  # "/var/lib/pgsql/data",
  "/var/opt/opscode/nginx/ca",
  "/opt/opscode/embedded/service/opscode-erchef/etc"
]

PATH_TO_BACKUP_COMMON = [
  "/root/.chef",
  "/var/chef/",
  "/var/www/rb-rails/config/",
  "/etc/pki/tls/",
  "/etc/ssl/",
  "/etc/group",
  "/etc/sudoers",
  "/etc/sudoers.d/",
  "/etc/selinux/",
  "/var/chef/cookbooks/keepalived/templates/default/keepalived.conf.erb"
]

OPT = {}

DEFAULT_ARGS = {
  file: "default",
  s3: "/root/.s3cfg",
  s3_NG: "/root/.s3cfg_initial"
}

opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: rb_backup_node.rb [options]"

  opts.on("-h", "--help", "Print this help") do
    puts opts
    exit
  end

  opts.on("-v", "--verbose", "Verbose mode") do
    check_single_use!(OPT, :verbose, "--verbose (-v)")
    OPT[:verbose] = true
  end

  opts.on("-c", "--cluster", "Action in all cluster") do |file|
    check_single_use!(OPT, :cluster, "--cluster (-c)")
    OPT[:cluster] = true
  end

  opts.on("-b", "--backup", "Perform backup") do
    check_single_use!(OPT, :backup, "--backup (-b)")
    OPT[:backup] = true
  end

  opts.on("-r", "--restore", "Perform restore") do
    check_single_use!(OPT, :restore, "--restore (-r)")
    OPT[:restore] = true
  end

  opts.on("-f[FILE]", "--file[=FILE]", "File to use for backup/restore (default: #{DEFAULT_ARGS[:file]})") do |file|
    check_single_use!(OPT, :file, "--file (-f)")
    if file.nil?
      puts "Warning: -f option missing argument, using default: #{DEFAULT_ARGS[:file]}"
    end
    OPT[:file] = file || DEFAULT_ARGS[:file]
  end

  opts.on("-s[FILE]", "--s3[=FILE]", "Use AWS S3 storage (default: #{DEFAULT_ARGS[:s3]})") do |file|
    check_single_use!(OPT, :s3, "--s3 (-s)")
    
    if file.nil?
      puts "Warning: -s option missing argument, using default: #{DEFAULT_ARGS[:s3]}"
    end
    
    OPT[:s3] = file || DEFAULT_ARGS[:s3]
    
    unless File.exist?(OPT[:s3])
      if File.exist?(DEFAULT_ARGS[:s3_NG])
        OPT[:s3] = DEFAULT_ARGS[:s3_NG]
      else
        print_status(status: :FAIL)        
        abort("Please, check your AWS config file (Not found: #{file} nor #{DEFAULT_ARGS[:s3]} nor #{DEFAULT_ARGS[:s3_NG]}), exiting")
      end
    end
  end

  # opts.on("-k NAME", "--bucket NAME", "Use this bucket for S3 restore") do |name|
  #   OPT[:bucket] = name
  # end
  # 
  # opts.on("-n", "Restore into new cluster (preserve current cdomain)") do
  #   OPT[:new_cluster] = true
  # end
  # 
  opts.on("-m", "Running on physical or virtual machine") do
    OPT[:m] = true
  end
  # 
  # opts.on("-d", "Preserve hostname from backup") do
  #   OPT[:preserve_hostname] = true
  # end  
end

opt_parser.parse!
validate_options(OPT)

check_leader if OPT[:cluster]

read_chef_file

#################
# Backup option #
#################
if OPT[:backup]
  # Init variables
  type = "backup"
  tar = "tar --ignore-failed-read -zvcPf"
  log_file = "/root/.#{type}-manager.log"
  backup_path = "/tmp/backups"
  FileUtils.mkdir_p(backup_path)

  # Verbose in commands
  s3verbose = OPT[:verbose] ? "-v" : "-q"

  # Verify if log file exists
  FileUtils.rm_f(log_file) if File.exists?(log_file)

  puts "Step 1. Destination"

  # Check backup destination
  if OPT[:file]
    if File.extname(OPT[:file]).empty?
      OPT[:file] += ".tar.gz"
    elsif File.basename(OPT[:file]) !~ /\.tar\.gz\z/
      print_status(status: :FAIL)
      puts "Invalid file extension. Only '.tar.gz' is allowed."
      exit 0
    end

    if OPT[:file].include?("/")
      file_path = OPT[:file]
    else
      file_path = File.join(backup_path, File.basename(OPT[:file]))
    end

    if File.exist?(file_path)
      print_status(status: :WARN)
      puts "File #{OPT[:file]} already exists, replacing..."
      File.delete(file_path)
    end
  elsif OPT[:s3]
    s3cfg          = OPT[:s3]
    file_path_name = "#{DATE}-#{HOSTNAME}-backup.tar.gz"
    file_path      = File.join(backup_path, file_path_name)
    s3bucket       = `cat /etc/druid/_common/common.runtime.properties | grep druid.storage.bucket= | tr '=' ' '|awk '{print $2}'`.strip

    if s3bucket == "" or File.exist?(s3cfg) == "false"
      print_status(status: :FAIL)
      puts "Please, check your AWS config, exiting"
      exit 0
    end
    
    message = "Checking s3://#{s3bucket}/ access "
    check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} ls s3://#{s3bucket}/", type, message)
    nbackup = `s3cmd -c #{s3cfg} -v ls s3://#{s3bucket}/backup/ | sort | cut -d/ -f5`

    if nbackup.lines.count >= LIMIT_FILES_SAVE
      deletefile = nbackup.lines.first.strip()
      message = "Deleting #{deletefile} backup file ... "
      check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} rm s3://#{s3bucket}/backup/#{deletefile}", type, message)
    end
    puts "\tThe backup will be stored in s3://#{s3bucket}/backup/#{file_path_name}"
  else
    print_status(status: :FAIL)
    puts "No backup destination specified"
    exit 0
  end

  puts "\nStep 1. Finish"
  print_status(status: :OK)

  puts "Step 2. Create backup tar.gz"

  node_config  = Chef::Node.load(HOSTNAME)

  if VALID_MODES.include?(node_config["redborder"]["mode"].to_s)
    
    tmp_dir    = OPT[:cluster] ? File.join(backup_path, "backup-cluster-#{DATE}") : File.join(backup_path, "backup-#{HOSTNAME}-#{DATE}")
    common_dir = File.join(tmp_dir, "common")
    unique_dir = File.join(tmp_dir, "unique", HOSTNAME)
    leader_dir = File.join(tmp_dir, "leader")
    database_dir = File.join(tmp_dir, "db")

    FileUtils.rm_rf(tmp_dir) if Dir.exist?(tmp_dir) && tmp_dir != "/" && !tmp_dir.strip.empty?
    FileUtils.mkdir_p(common_dir)
    FileUtils.mkdir_p(unique_dir)
    FileUtils.mkdir_p(leader_dir)
    FileUtils.mkdir_p(database_dir)

    PATH_TO_EXCLUDE << "/var/chef/cache" unless OPT['m']

    hashes = {}

    # -------------------------------
    # 1. Leader-only files
    # -------------------------------
    PATH_TO_BACKUP_LEADER.each do |base|
      next if PATH_TO_EXCLUDE.any? { |ex| base.start_with?(ex) }
      process_folder(base, leader_dir)
    end

    # -------------------------------
    # 2. Unique files for this node
    # -------------------------------
    PATH_TO_BACKUP_UNIQUE.each do |base|
      next if PATH_TO_EXCLUDE.any? { |ex| base.start_with?(ex) }
      process_folder(base, { unique: unique_dir, common: common_dir }, hashes, deduplicate: true)
    end

    # -------------------------------
    # 3. Common files
    # -------------------------------
    PATH_TO_BACKUP_COMMON.each do |base|
      next if PATH_TO_EXCLUDE.any? { |ex| base.start_with?(ex) }
      process_folder(base, { unique: unique_dir, common: common_dir }, hashes, deduplicate: true)
    end

    # -------------------------------
    # 4. If cluster mode, fetch other nodes
    # -------------------------------
    if OPT[:cluster]
      serf_output = `serf members 2>&1`
      cluster_nodes = serf_output.each_line.map { |l| l.split.first }.reject { |n| n == HOSTNAME }
      nodes_dir  = File.join(tmp_dir, "nodes")
      FileUtils.mkdir_p(nodes_dir)
    
      puts "Cluster nodes detected: #{cluster_nodes.join(", ")}"
      puts "Sync IP Address (this node): #{node_config['ipaddress_sync']}"
    
      cluster_nodes.each do |node|
        line = serf_output.each_line.find { |l| l.start_with?(node) }
        next unless line
      
        sync_ip = line.split[1].to_s.split(':').first
        next if sync_ip.nil? || sync_ip.empty?
      
        node_tmp_dir = File.join(nodes_dir, node)
        FileUtils.mkdir_p(node_tmp_dir)
      
        # Fetch files into temporal folder (node_tmp_dir)
        paths_str    = (PATH_TO_BACKUP_UNIQUE + PATH_TO_BACKUP_COMMON).join(" ")
        exclude_opts = PATH_TO_EXCLUDE.map { |e| "--exclude '#{e}'" }.join(" ")
      
        system("rsync -az #{exclude_opts} root@#{sync_ip}:#{paths_str} #{node_tmp_dir}")
      
        # Organize fetched files into unique/common
        (PATH_TO_BACKUP_UNIQUE + PATH_TO_BACKUP_COMMON).each do |base|
          node_base = File.join(node_tmp_dir, File.basename(base))
          process_folder(node_base, { unique: File.join(tmp_dir, "unique", node), common: common_dir }, hashes, deduplicate: true) if Dir.exist?(node_base)
        end
      end

      # Clear temporal folder
      FileUtils.rm_rf(nodes_dir)
    end

    # -------------------------------
    # 5. Manager info (leader only)
    # -------------------------------
    manager_info_path = File.join(leader_dir, "#{HOSTNAME}-backup-#{DATE}.txt")
    File.open(manager_info_path, "w") do |f|
      f.puts "Backup date: #{DATE}\n"
      f.puts "Node: #{HOSTNAME}"
      f.puts "Version: #{`rpm -aq | sed -e '/redborder-manager/!d'`}"
      f.puts "Management IP Address: #{node_config['ipaddress']}"
      f.puts "Sync Ip Address: #{node_config['ipaddress_sync']}"
    end
    puts "Manager_info to #{manager_info_path} >> complete!!"
    print_status(status: :OK)

    # -------------------------------
    # 6. Database backup (leader only)
    # -------------------------------
    puts "PG BACKUP DUMP"
    pg_dumpall_path = File.join(database_dir, "#{HOSTNAME}-postgresql-dump-#{DATE}.gz")
    message = "COMPLETE Database backup to #{pg_dumpall_path}"
    check_oper("nice -n 19 ionice -c2 -n7 pg_dumpall -h master.postgresql.service -U postgres -c | gzip --fast > #{pg_dumpall_path}; sync", type, message)
    
    puts "PG BACKUP COPY"
    message = "Stop PostgreSQL service"
    check_oper("systemctl stop postgresql", type, message)
    
    pg_copy_path = File.join(database_dir,"#{HOSTNAME}-postgresql-copy-#{DATE}.tar.gz")
    message = "Copy /lib/var/pgsql/data/ to #{pg_copy_path}"
    cmd_tar_backup = "sudo tar -czpf #{pg_copy_path} -C /var/lib/pgsql data"
    check_oper(cmd_tar_backup, type, message)
    
    message = "Start PostgreSQL service"
    check_oper("systemctl start postgresql", type, message)

    # -------------------------------
    # 7. Generate tar.gz backup
    # -------------------------------
    tarcmd = "nice -n 19 ionice -c2 -n7 #{TAR_CREATE} #{file_path} -C #{tmp_dir} ."
    backup_pattern = OPT[:cluster] ? File.join(backup_path, "backup-cluster-*") : File.join(backup_path, "backup-#{HOSTNAME}-*")
    backup_file_pattern = File.join(backup_path, "*.tar.gz")
    
    if OPT[:file]
      message = "Making backup in tar.gz file: #{file_path}"
      check_oper("#{tarcmd}; sync", type, message)
      # -- Limit folders with backup data --
      limit_saved_files(backup_pattern, LIMIT_FILES_SAVE)
      # -- Limit tar.gz backup files --
      limit_saved_files(backup_file_pattern, LIMIT_FILES_SAVE)
    elsif OPT[:s3]
      message = "Making backup on s3"
      check_oper("#{tarcmd}; nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} sync #{file_path} s3://#{s3bucket}/backup/; rm -f #{file_path}", type, message)
      FileUtils.rm_rf(tmp_dir) if Dir.exist?(tmp_dir) && tmp_dir != "/" && !tmp_dir.strip.empty?
    end
  else
    print_status(status: :FAIL)
    puts "Actual node is not the #{VALID_MODES}, exiting"
    exit 0
  end

  puts "\nStep 2. Finish"
  print_status(status: :OK)

##################
# Restore Option #
##################
elsif OPT[:restore]
  type = "restore"
  # -- Select backup --
  src = select_backup(OPT[:file], OPT[:s3])
  backup_selected = File.basename(src)

  # -- Locate restore folder for this specific backup --
  backup_name = backup_selected.sub(/\.tar\.gz$/, "")
  backup_path = File.join("/tmp/backups", "restore_#{backup_name}")

  already_exists = Dir.exist?(backup_path)

  unless already_exists
    # -- Remove other restore_* folders except this one
    Dir.glob("/tmp/backups/restore_*").each do |folder|
      FileUtils.rm_rf(folder) if File.directory?(folder)
    end

    # -- Create the restore folder
    FileUtils.mkdir_p(backup_path)
  else
    puts "Backup folder #{backup_path} already exists, skipping download/extract."
  end
  
  unless already_exists
    if OPT[:file]
      backup_file_folder_path = File.join(src, "db/.")

      puts "Copying backup file: #{backup_file_folder_path} -> #{backup_path}"
      Dir.glob(File.join(backup_file_folder_path, '*')).each do |file|
        FileUtils.cp_r(file, backup_path)
      end
    else
      # -- Get backup from s3 --
      puts "Get backup from s3: #{src} -> #{backup_path}"
      system("s3cmd -c #{OPT[:s3]} get #{src} #{backup_path}")
      backup_s3_path = File.join(backup_path, backup_selected)
      # -- Descompress backup from s3 --
      puts "Extracting tar.gz backup: #{backup_s3_path} -> #{backup_path}"
      system("tar -xzf #{backup_s3_path} -C #{backup_path}") or abort("Error: failed to extract #{backup_s3_path}")
    end  
  end

  if OPT[:s3]
    db_tar_dir = File.join(backup_path, "db")
    unless Dir.exist?(db_tar_dir)
      abort("No 'db' directory found in backup path: #{db_tar_dir}")
    end
  else
    db_tar_dir = backup_path
  end

  # -- Find all files inside db directory
  restore_files = Dir.glob(File.join(db_tar_dir, "*.gz"))
  if restore_files.empty?
    abort("No restore files found in #{db_tar_dir}")
  end
  # -- Display menu
  puts "Restore type options:"
  restore_files.each_with_index do |file, i|
    puts "  [#{i + 1}] #{File.basename(file)}"
  end
  puts "Choose a restore file [1-#{restore_files.size}]: "
  choice = $stdin.gets.to_i
  if choice < 1 || choice > restore_files.size
    abort("Invalid choice.")
  end
  selected_file = restore_files[choice - 1]
  puts "You selected: #{File.basename(selected_file)}"
  file_selected_path = File.join(db_tar_dir, File.basename(selected_file))
  puts "Restore file to uncompress: #{file_selected_path}"
  # -- Decide based on file name pattern
  if File.basename(selected_file).include?("dump")
    puts ">> Running RESTORE from Dump (pg_dumpall)..."
    service_name = "postgresql"
    
    # -- 1. Check service postgreSQL is running
    status = `systemctl is-active #{service_name}`.strip
    abort("#{service_name} service needs to be running.") unless status == "active"
    
    # -- 2. Stop postgresql
    message = "Stop PostgreSQL service"
    check_oper("systemctl stop #{service_name}", type, message)
    
    # -- 3. mv /var/lib/pgsql/data
    message = "Save a copy & Clean /var/lib/pgsql/data"
    mv_folder = "/var/lib/pgsql/data.bak"
    FileUtils.rm_rf(mv_folder) if Dir.exist?(mv_folder) && mv_folder != "/" && !mv_folder.strip.empty?
    cmd = "mv /var/lib/pgsql/data #{mv_folder}"
    check_oper(cmd, type, message)
    
    # -- 4. Initdb
    message = "Initialize Database in /var/lib/pgsql/data"
    cmd = "sudo -u postgres initdb -D /var/lib/pgsql/data"
    check_oper(cmd, type, message)
    
    # -- 5. Start postgresql
    message = "Start PostgreSQL service"
    check_oper("systemctl start #{service_name}", type, message)
    
    # -- 6. Restore file with gunzip
    message = "Restore file with gunzip"
    cmd = "gunzip -c #{file_selected_path} | psql -U postgres -h localhost -d postgres"
    check_oper(cmd, type, message)
    
    # -- 7. Adjust configuration to access PostgreSQL
    message = "Adjust connection: postgresql.conf"
    config_path = "/var/lib/pgsql/data/postgresql.conf"
    content = File.read(config_path)
    new_listen = "listen_addresses = '*'"
    content.sub!(/^\s*listen_addresses\s*=.*$/, new_listen) || content << "\n#{new_listen}\n"
    new_port = "port = 5432"
    content.sub!(/^\s*port\s*=.*$/, new_port) || content << "\n#{new_port}\n"
    File.open(config_path, "w") { |f| f.write(content) } rescue abort("Error when writing in: #{config_path}")
    cmd = "echo '#{config_path} updated'"

    message = "Adjust connection: pg_hba.conf"
    config_path = "/var/lib/pgsql/data/pg_hba.conf"
    content = File.read(config_path)
    new_host = "host    all             all           10.0.209.0/24         trust"
    content << "\n#{new_host}\n"
    File.open(config_path, "w") { |f| f.write(content) } rescue abort("Error when writing in: #{config_path}")
    cmd = "echo '#{config_path} updated'"
    check_oper(cmd, type, message)

    # -- 8. Restart postgresql
    message = "Restart PostgreSQL service"
    check_oper("systemctl restart #{service_name}", type, message)

    # -- 9. Restart services to see graph in modules
    message = "Restart Druid Services"
    check_oper("systemctl restart druid-*;systemctl restart rb-druid-indexer.service", type, message)

    message = "Restart Webui service"
    check_oper("systemctl restart webui", type, message)

    puts ">> RESTORE COMPLETE"
    puts "It would take some minutes to show data on module graphs!!!"
  elsif File.basename(selected_file).include?("copy")
    abort("RESTORE from Copy (/var/lib/pgsql/data): Not available yet.")
  else
    abort("Invalid choice (Not a compressed file).")
  end

  exit 1
  # -- Exit here (in next tasks about restore of Node and other services)

  type       = "restore"
  verified   = false

  if OPT[:verbose]
    verbose   = "verbose"
    s3verbose = "-v"
  else
    verbose   = "quiet"
    s3verbose = "-q"
  end

  manufacturer=`dmidecode -t 1| grep "Manufacturer:" | sed 's/.*Manufacturer: //'`.chomp

  if File.exists?("/opt/rb/etc/externals.yml")
    externals             = YAML.load_file('/opt/rb/etc/externals.yml')
    domain_rbglobal       = externals['CDOMAIN']
    publicdomain_rbglobal = externals['PUBLICCDOMAIN']
  elsif File.exists?("/opt/rb/etc/manager.yml")
    manager_config        = YAML.load_file('/opt/rb/etc/manager.yml')
    domain_rbglobal       = manager_config['DOMAIN']
  elsif File.exists?("/etc/resolv.conf")
    domain_rbglobal = `cat /etc/resolv.conf | grep domain | cut -d " " -f2`.strip()
  end

  domain_rbglobal       = "redborder.cluster" if (domain_rbglobal.nil? or domain_rbglobal == "")
  publicdomain_rbglobal = domain_rbglobal     if publicdomain_rbglobal.nil?

  if OPT['n']
    verified = true
    check_oper("rm -f /opt/rb/etc/blocked/*; touch /opt/rb/etc/s3user.txt; rm -f /opt/rb/etc/cluster.lock", type, "Deleting locking files ... ")
  else
    node_config = Chef::Node.load(HOSTNAME)
    if ( !node_config.nil? and !node_config["redborder"].nil? and !node_config["redborder"]["manager"].nil? and ( (node_config["redborder"]["manager"]["mode"] == "master") or (node_config["redborder"]["manager"]["mode"] == "corezk") or (node_config["redborder"]["manager"]["mode"] == "core") or (node_config["redborder"]["manager"]["mode"] == "chef") ) )
      verified = true
    end
  end

  if verified
    # Init variables
    tar = "tar --ignore-failed-read -zvxPf"

    # Delete previous restore files
    FileUtils.rm_f("/tmp/*-postgresql-dump-*.gz") if !Dir.glob('/tmp/*-postgresql-dump-*.gz').empty?

    # Check backup source
    if OPT[:file] and OPT[:s3].nil? and File.exists?(OPT[:file])
      path = File.expand_path(OPT[:file])
    elsif OPT[:s3]
      s3cfg    = (OPT[:s3] ? "/root/.s3cfg-backup" : "/root/.s3cfg")
      s3bucket = (OPT['k'] ? OPT['k'] : (externals.nil? ? "redborder" : externals['S3BUCKET']))
      s3bucket = "redborder" if s3bucket.nil? or s3bucket.empty?

      check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} ls s3://#{s3bucket}/", type, "Checking S3 access ... ")
      nbackup = `s3cmd -c #{s3cfg} -v ls s3://#{s3bucket}/backup/ | sort | cut -d/ -f5`
      if OPT[:file].nil?
        if nbackup.lines.count == 0
          printf "There is no backup files to restore on s3://#{s3bucket}/backup/\n"
          exit 0
        else
          file_to_restore = nbackup.lines.last.strip()
        end
      else
        message = "Checking s3://#{s3bucket}/backup/#{OPT[:file]} ... "
        printf message
        if `s3cmd -c #{s3cfg} ls s3://#{s3bucket}/backup/#{OPT[:file]}` == ""
          printf "[  KO  ]\n".colorize(:red).rjust(140-message.length)
          printf "The file doesn't exists\n"
          exit 0
        else
          printf "[  OK  ]\n".colorize(:green).rjust(140-message.length)
          file_to_restore = OPT[:file]
        end
      end
      path = "/tmp/#{file_to_restore}"
      message = "Downloading #{file_to_restore} file ... "
      check_oper("s3cmd -c #{s3cfg} #{s3verbose} sync s3://#{s3bucket}/backup/#{file_to_restore} /tmp/", type, message)
    else
      printf "Source error, check your choice. Option -f or -3 are mandatory\n".colorize(:red)
      exit 0
    end

    # Extract node to restore info
    noderestore     = nil
    ipmagntorestore = nil
    ipsynctorestore = nil

    file_config = `#{tar} #{path} *-backup-*.txt`.strip()
    filet = File.open(file_config, "r")
    filet.each_line { |line|
      if line.include? "Management I"
        ipmagntorestore = line.slice(line.index(": ")+2..-1).strip()
      elsif line.include? "Sync I"
        ipsynctorestore = line.slice(line.index(": ")+2..-1).strip()
      elsif line.include? "Node"
        noderestore = line.slice(line.index(": ")+2..-1).strip()
      end
    }
    filet.close()

    # If its a machine restore verify the correct content of files
    failed = true if (OPT['m']) and (`tar -tf #{path} | grep "opt/rb/var/chef/cache/cookbooks"` == "")

    if noderestore.nil? or ipmagntorestore.nil? or ipsynctorestore.nil? or failed
      printf "The backup is not valid.\n".colorize(:red)
      exit 0
    end

    if HOSTNAME != noderestore
      check_oper("hostname #{noderestore}", type, "Changing #{HOSTNAME} node name to #{noderestore} node name ... ")
    end

    # Stop chef-client
    check_oper("rb_service stop chef druid awslogs rb-cloudwatch rb-monitor rb-workers rb-webui nprobe n2klocd memcached kafka stanchion riak zookeeper pgpool nginx freeradius postgresql keepalived", type, "Stoping all services ... ")
    # Restore the node
    check_oper("#{tar} #{path} -C /", type, "Restoring files ... ")
    `sed -i '/rb_aws_secondary_ip.sh/d' /etc/keepalived/keepalived.conf`
    # we need to change remote ips for current ips on /etc/hosts
    check_oper("sed -i 's/^#{ipmagntorestore} /127.0.0.1 /g' /etc/hosts; sed -i 's/^#{ipsynctorestore} /127.0.0.1 /g' /etc/hosts;", type, "Replacing ips on /etc/hosts ... ")
    # Start postgress on chef-server
    check_oper("rb_service start keepalived postgresql", type, "Restoring postgresql service ... ")
    # Restore chef-server data
    check_oper("su - opscode-pgsql -m -s /bin/bash -c \"gunzip -q -c /tmp/*-postgresql-dump-*.gz | /opt/chef-server/embedded/bin/psql -U \"opscode-pgsql\" -d postgres\"", type, "Restoring chef-server database ...")
    # Ensure chef is running
    check_oper("rb_chef restart; sleep 5; rb_create_rabbitusers.sh", type, "Starting chef-server services ... ")

    if OPT['n']
      # With this option we conserve original domain
      domain_restore = `cat /etc/chef/client.rb | grep erchef | cut -d/ -f3 | cut -d: -f1 | cut -d. -f2-`.strip()
      puts "New Domain:    #{domain_rbglobal}"
      puts "Backup Domain: #{domain_restore}"
    else
      # if -n is not prsent we set new domain to backup domain
      domain_rbglobal = domain_restore
    end

    # re-read chef config file
    read_chef_file

    # Delete nodes except actual node
    Chef::Node.list.keys.sort.each do |m|
      if m != noderestore and !m.start_with?"rbflow-" and !m.start_with?"rbflow-"
        node = Chef::Node.load m
        if node.run_list?"role[manager]" and node.name != noderestore
          message = "Deleting node #{node.name} from cluster config ... "
          printf "#{message}"
          `knife node delete #{node.name} -y; knife role delete #{node.name} -y; knife client delete #{node.name} -y`
          printf "[  OK  ]\n".colorize(:green).rjust(140-message.length)
        end
      end
    end

    # Change resolv_dns if we change from cloud environment to not cloud
    if manufacturer.downcase!="xen" and externals.nil?
      resolv_dns_db = Chef::DataBagItem.load("rBglobal", "resolv_dns")
      resolv_dns_db["enable"] = true
      resolv_dns_db.save
    end

    # Create new certs and delete old certs
    secret = Chef::EncryptedDataBagItem.load_secret(ENCRYPTED_DATA_BAG_SECRET_PATH)

    # Change s3 domains if proceed
    if OPT['n']
      s3_secrets_temp = Chef::DataBagItem.load('passwords','s3_secrets') rescue s3_secrets_temp=nil
      if !s3_secrets_temp.nil? and !s3_secrets_temp["hostname"].nil? and s3_secrets_temp["hostname"].end_with? "#{domain_restore}"
        s3_secrets_temp["hostname"] = s3_secrets_temp["hostname"].sub(domain_restore,domain_rbglobal)
        if !s3_secrets_temp["email"].nil?
          email_new = s3_secrets_temp["email"].sub(domain_restore,domain_rbglobal)
          s3_secrets_temp["email"] = email_new
        end
        s3_secrets_temp.save
      end

      if !domain_restore.nil? and domain_restore != domain_rbglobal
        #recreate certs
        [ domain_rbglobal, "chefwebui.#{domain_rbglobal}", "data.#{domain_rbglobal}", "erchef.#{domain_rbglobal}", "repo.#{domain_rbglobal}", "s3.#{domain_rbglobal}", "webui.#{domain_rbglobal}" ].each do |cert|
          FileUtils.rm_f("/var/opt/chef-server/nginx/ca/#{cert}.crt") if File.exists?"/var/opt/chef-server/nginx/ca/#{cert}.crt"
          check_oper("/opt/rb/bin/rb_create_cert.sh -n #{cert}", type, "Creating #{cert} cert ...")
          check_oper("/opt/rb/bin/rb_upload_certs.sh #{cert}"  , type, "Uploading #{cert} cert ...")
        end
      end

      check_oper("mkdir -p /root/.chef/trusted_certs/; rsync /var/opt/chef-server/nginx/ca/erchef.#{domain_rbglobal}.crt /var/opt/chef-server/nginx/ca/#{domain_rbglobal}.crt /opt/rb/root/.chef/trusted_certs/; mkdir -p /home/redborder/.chef/trusted_certs/; rsync /var/opt/chef-server/nginx/ca/erchef.#{domain_rbglobal}.crt /var/opt/chef-server/nginx/ca/#{domain_rbglobal}.crt /home/redborder/.chef/trusted_certs/; chown -R redborder:redborder /home/redborder/.chef", type, "Copying certs to trusted certs")

      # Change domain an public domain for database
      db_list = ["db_opscode_chef","db_druid","db_oozie","db_radius","db_redborder"]
      db_list.each { |db|
        db_hash=Chef::EncryptedDataBagItem.load("passwords", db, secret).to_hash
        if db_hash["hostname"].end_with?"#{domain_restore}"
          db_hash["hostname"]=db_hash["hostname"].sub(domain_restore,domain_rbglobal)
          db_enc  = Chef::EncryptedDataBagItem.encrypt_data_bag_item(db_hash, secret)
          db_item = Chef::DataBagItem.from_hash(db_enc)
          db_item.data_bag("passwords")
          db_item.save
        end
      }

      FileUtils.rm_f("/etc/extrahosts") if File.exists?"/etc/extrahosts"

      # Overwrite domains
      new_domain = Chef::DataBagItem.load('rBglobal','domain') rescue new_domain=nil
      if !new_domain.nil? and new_domain["name"] != domain_rbglobal
        `echo "127.0.0.1 erchef.#{new_domain["name"]} postgresql.#{new_domain["name"]}" >> /etc/extrahosts` if OPT['n']
        new_domain["name"] = domain_rbglobal
        new_domain.save
      end

      new_publicdomain_rbglobal = Chef::DataBagItem.load('rBglobal','publicdomain') rescue new_publicdomain_rbglobal=nil
      if !new_publicdomain_rbglobal.nil? and new_publicdomain_rbglobal["name"] == ""
        new_publicdomain_rbglobal["name"] = publicdomain_rbglobal
        new_publicdomain_rbglobal.save
      end

      # empty virtual ips on new environment
      ["ipvirtual-external-erchef", "ipvirtual-external-freeradius", "ipvirtual-external-kafka", "ipvirtual-external-n2klocd", "ipvirtual-external-n2kmobiled", "ipvirtual-external-nprobe", "ipvirtual-external-rb-reputation", "ipvirtual-external-rb-webui", "ipvirtual-external-riak", "ipvirtual-external-trap2kafka", "ipvirtual-internal-cep", "ipvirtual-internal-drill", "ipvirtual-internal-erchef", "ipvirtual-internal-kafka", "ipvirtual-internal-n2kmetricd", "ipvirtual-internal-oozie", "ipvirtual-internal-postgresql"].each do |x|
        db_temp = Chef::DataBagItem.load('rBglobal', x ) rescue db_temp = nil
        if !db_temp.nil? and !db_temp["ip"].nil? and db_temp["ip"]!=""
          db_temp["ip"] = ""
          db_temp.save
        end
      end
    end
    `echo "127.0.0.1 erchef.#{domain_rbglobal} postgresql.#{domain_rbglobal}" >> /etc/extrahosts` if OPT['n']

    if !opt['c'].nil? and !opt['c'].empty?
      printf "CMD: #{OPT['c']}\n"
      system(OPT['c'])
    end

    if HOSTNAME != noderestore and !opt['p']
      # Change node to original
      check_oper("rb_change_hostname.sh -s -f -n #{HOSTNAME}", type, "Restoring #{HOSTNAME} node name ... ")

      # Check if noderestore exists
      if `knife node list | grep #{noderestore}` != ""
        check_oper("knife node delete #{noderestore} -y; knife client delete #{noderestore} -y; knife role delete #{noderestore} -y", type, "Deleting #{noderestore} client and node ... ")
      end
    end

    # Run chef once
    check_oper("rb_run_chef_once.sh", type, "Applying chef config 1/2 (please, be patient) ... ")
    check_oper("rb_run_chef_once.sh", type, "Applying chef config 2/2 (please, be patient) ... ")

    # Deleting old certs if the domain has changed
    if !domain_restore.nil? and domain_restore != domain_rbglobal
      [domain_restore,"chefwebui.#{domain_restore}","data.#{domain_restore}","erchef.#{domain_restore}","repo.#{domain_restore}","s3.#{domain_restore}","webui.#{domain_restore}"].each do |cert|
        check_oper("knife data bag delete certs http_#{cert}_pem -y", type, "Deleting #{cert} data bag item ... ")
        FileUtils.rm_f("/var/opt/chef-server/nginx/ca/#{cert}.crt") if File.exists?"/var/opt/chef-server/nginx/ca/#{cert}.crt"
      end
    end

    if OPT['m']
      #  reset riak config if necessary
      check_oper("rb_reset_riak_conf.rb -y -v", type, "Restarting riak config ... ")

      # upload cookbooks to s3
      check_oper("rb_upload_cookbooks.sh -f", type, "Uploading cookbooks to riak ... ")
    end

    # start all cluster services
    check_oper("rb_service start", type, "Starting all cluster services ... ")

    # Delete temporal files
    message = "Deleting temporal files ... "
    if OPT[:file]
      check_oper("nice -n 19 ionice -c2 -n7 rm -f /tmp/*-postgresql-dump-*; nice -n 19 ionice -c2 -n7 rm -f #{file_config}; rm -f /opt/rb/etc/extrahosts", type, message)
    else
      check_oper("nice -n 19 ionice -c2 -n7 rm -f /tmp/*-postgresql-dump-*; nice -n 19 ionice -c2 -n7 rm -f #{file_config}; nice -n 19 ionice -c2 -n7 rm -f /tmp/#{file_to_restore}; rm -f /opt/rb/etc/extrahosts", type, message)
    end
    printf "Node restored successfully!!!\n".colorize(:green)
  else
    printf "Actual node is not the master, exiting\n".colorize(:red)
    exit 0
  end
else
  usage()
end
