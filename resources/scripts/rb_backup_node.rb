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

require 'getopt/std'
require 'yaml'
require 'chef'
require 'fileutils'
require 'syslog'
require 'io/console'

def usage
  printf "Usage: rb_backup_node.rb [-f path][-b][-r][-h][-s][-v][-3][-k bucket][-n][-m][-p]\n"
  printf "    -f file (mandatory)     -> file to use for backup/restore\n"
  printf "    -s                      -> use AWS backup\n"
  printf "    -3                      -> use AWS S3 storage\n"
  printf "    -h                      -> print this help\n"
  printf "    -b                      -> use for backup\n"
  printf "    -r                      -> use for restore\n"
  printf "    -k bucket name          -> use this bucket for s3 restore\n"
  printf "    -n                      -> use to restore new cluster. Conserve current cdomain\n"
  printf "    -m                      -> use if you are on physical or virtual machine\n"
  printf "    -p                      -> preserve hostname from backup\n"
  printf "    -v                      -> verbose mode\n"
  exit 0
end

def validate_options(opt)
  # Help
  usage if opt['h']

  # Not file passed
  usage if OPT['f'] && (OPT['f'].nil? || OPT['f'].empty?)

  # Backup Or Restore (not both)
  if opt['b'] && opt['r']
    puts "Cannot use -b and -r together"
    usage
  end

  # Save in S3 or Save into local file (not both)
  if opt['3'] && opt['f']
    puts "Cannot use -3 and -f together"
    usage
  end

  # Backup has to be stored in S3 or into a file
  if opt['b'] && !opt['f'] && !opt['3']
    puts "Backup requires either -f (file) or -3 (S3)"
    usage
  end 

  # Specify .s3cfg file require option -3 (Save in S3)
  if opt['s'] && !opt['3']
    puts "Option -s requires -3"
    usage
  end

  # Specify bucket to restore from require option -3 (Save in S3)
  if opt['k'] && !opt['3']
    puts "Option -k requires -3"
    usage
  end

  # restore
  # if opt['m'] && opt['p']
  #   puts "Cannot use -m and -p together"
  #   usage
  # end
end

# Indicate Status for each step
def print_status(status: :OK, fill: "-")
  color  = COLORS[status] || "\e[36m" # default cyan if unknown
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

  puts "\t#{message}" if OPT['v']
  File.open(log_file, "a") { |f| f.puts message }
  
  check = false
  commands.each do |c|
    c.strip!
    output = `#{c} 2>&1`
    puts "\t\t#{output}" if OPT['v']
    File.open(log_file, "a") { |f| f.puts output }
    check = $?.success?
  end
  
  if check
    print_status(status: :OK) if OPT['v']
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
  


# Global var
OPT                            = Getopt::Std.getopts("f:bhvprms3k:nc")
DATE                           = Time.new.strftime("%Y%m%d-%H%M%S")
HOSTNAME                       = `hostname -s 2>/dev/null`.strip()
ENCRYPTED_DATA_BAG_SECRET_PATH = "/etc/chef/encrypted_data_bag_secret"
LIMIT_FILES_SAVE               = 5
TERMINAL_WIDTH                 = IO.console.winsize[1] rescue 120
VALID_MODES                    = %w[full s3 core chef]
TAR_CREATE                     = "tar --ignore-failed-read -zvcPf"
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
  "/var/chef/data"
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
  "/var/lib/pgsql/data",
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




#
# Only leader name -> leader_name = serf_output.each_line.map(&:strip).find { |line| line.include?("leader=ready")}&.split&.first
# line serf memeber with leader = ready -> leader_data = serf_output.each_line.map { |l| l.strip }.find { |l| l.include?("leader=ready") }
# Hostname, IP:PORT, Status, Services/Modes => "jenkins-manager1  10.0.225.20:7946  alive  s3=ready,consul=ready,leader=ready,mode=full,postgresql=ready"
# option cluster => "-c", only execute in master node if not write which node is master (name, ip, status)
# Data changes:
#   /etc      -> /etc_hostname
#   /var/opt  -> /var/opt_hostname
#   /var/lib  -> only master
#   /var/chef -> only master
#   /var/www  -> only master
#   

# Check compatibile options
# usage() if OPT['h'] or (OPT['f'].nil? and OPT['f']) or (OPT['f'] and OPT['s']) or (OPT['3'] and OPT['s']) or (OPT['k'].nil? and OPT['k'] and OPT['3']) or (OPT['m'] and OPT['p'])
validate_options(OPT)

check_leader if OPT['c']

read_chef_file

#################
# Backup option #
#################
if OPT['b']
  # Init variables
  type = "backup"
  tar = "tar --ignore-failed-read -zvcPf"
  log_file = "/root/.#{type}-manager.log"
  backup_path = "/tmp/backups"
  FileUtils.mkdir_p(backup_path)

  # Verbose in commands
  s3verbose = OPT['v'] ? "-v" : "-q"

  # Verify if log file exists
  FileUtils.rm_f(log_file) if File.exists?(log_file)

  puts "Step 1. Destination"

  # Check backup destination
  if OPT['f']
    if File.extname(OPT['f']).empty?
      # Add .tar.gz
      OPT['f'] += ".tar.gz"
    elsif File.basename(OPT['f']) !~ /\.tar\.gz\z/
      # Invalid extension
      print_status(status: :FAIL)
      puts "Invalid file extension. Only '.tar.gz' is allowed."
      exit 0
    end

    if OPT['f'].include?("/")
      file_path = OPT['f']
    else
      file_path = File.join(backup_path, File.basename(OPT['f']))
    end

    if File.exist?(file_path)
      print_status(status: :WARN)
      puts "File #{OPT['f']} already exists, replacing..."
      File.delete(file_path)
    end
  elsif OPT['3']
    s3cfg          = (OPT['s'] ? "/root/.s3cfg-backup" : "/root/.s3cfg_initial")
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
    
    tmp_dir    = OPT['c'] ? File.join(backup_path, "backup-cluster-#{DATE}") : File.join(backup_path, "backup-#{HOSTNAME}-#{DATE}")
    common_dir = File.join(tmp_dir, "common")
    unique_dir = File.join(tmp_dir, "unique", HOSTNAME)
    leader_dir = File.join(tmp_dir, "leader")

    FileUtils.rm_rf(tmp_dir) if Dir.exist?(tmp_dir) && tmp_dir != "/" && !tmp_dir.strip.empty?
    FileUtils.mkdir_p(common_dir)
    FileUtils.mkdir_p(unique_dir)
    FileUtils.mkdir_p(leader_dir)

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
    if OPT['c']
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
    message = "Database backup in progress ... "
    pg_dump_path = File.join(leader_dir, "#{HOSTNAME}-postgresql-dump-#{DATE}.gz")
    check_oper("nice -n 19 ionice -c2 -n7 pg_dumpall -h 127.0.0.1 -U postgres -c | gzip --fast > #{pg_dump_path}; sync", type, message)

    # -------------------------------
    # X. Generate tar.gz backup
    # -------------------------------
    tarcmd = "nice -n 19 ionice -c2 -n7 #{TAR_CREATE} #{file_path} -C #{tmp_dir} ."
    backup_pattern = OPT['c'] ? File.join(backup_path, "backup-cluster-*") : File.join(backup_path, "backup-#{HOSTNAME}-*")
    backup_file_pattern = File.join(backup_path, "*.tar.gz")
    
    if OPT['f']
      message = "Making backup in tar.gz file: #{file_path}"
      check_oper("#{tarcmd}; sync", type, message)
      # -- Limit folders with backup data --
      limit_saved_files(backup_pattern, LIMIT_FILES_SAVE)
      # -- Limit tar.gz backup files --
      limit_saved_files(backup_file_pattern, LIMIT_FILES_SAVE)
    elsif OPT['3']
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
elsif OPT['r']
  type       = "restore"
  verified   = false

  if OPT['v']
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
    if OPT['f'] and OPT['3'].nil? and File.exists?(OPT['f'])
      path = File.expand_path(OPT['f'])
    elsif OPT['3']
      s3cfg    = (OPT['s'] ? "/root/.s3cfg-backup" : "/root/.s3cfg")
      s3bucket = (OPT['k'] ? OPT['k'] : (externals.nil? ? "redborder" : externals['S3BUCKET']))
      s3bucket = "redborder" if s3bucket.nil? or s3bucket.empty?

      check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} ls s3://#{s3bucket}/", type, "Checking S3 access ... ")
      nbackup = `s3cmd -c #{s3cfg} -v ls s3://#{s3bucket}/backup/ | sort | cut -d/ -f5`
      if OPT['f'].nil?
        if nbackup.lines.count == 0
          printf "There is no backup files to restore on s3://#{s3bucket}/backup/\n"
          exit 0
        else
          file_to_restore = nbackup.lines.last.strip()
        end
      else
        message = "Checking s3://#{s3bucket}/backup/#{OPT['f']} ... "
        printf message
        if `s3cmd -c #{s3cfg} ls s3://#{s3bucket}/backup/#{OPT['f']}` == ""
          printf "[  KO  ]\n".colorize(:red).rjust(140-message.length)
          printf "The file doesn't exists\n"
          exit 0
        else
          printf "[  OK  ]\n".colorize(:green).rjust(140-message.length)
          file_to_restore = OPT['f']
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
    if OPT['f']
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
