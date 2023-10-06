#!/usr/bin/ruby
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
require 'colorize'
require 'yaml'
require 'chef'
require 'fileutils'
require 'syslog'

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

def read_chef_file
  # Chef config
  Chef::Config.from_file("/root/.chef/knife.rb")
  Chef::Config[:node_name]  = "admin"
  Chef::Config[:client_key] = "/root/.chef/admin.pem"
  Chef::Config[:http_retry_count] = 5
end

def check_oper (cmd, mode, type, message)
  commands = cmd.split(';')
  if mode == "verbose"
    printf "".center(120,'#').colorize(:light_blue)
    printf "\n# #{message}\n".colorize(:light_blue)
    printf "".center(120,'#').colorize(:light_blue)
    printf "\n"
    check = "KO"
    commands.each {|cmd|
      if cmd[0] == " "
        cmd[0] = ""
      end
      output = system("#{cmd}")
      check = $?.success?
      open("/root/.#{type}-manager.log", "a") { |f|
        f.puts "#{output}"
      }
    }
    if "#{check}" == "true"
      printf " [  OK  ] ".center(120,'#').colorize(:light_blue)
      printf "\n"
      log("#{message}  [  OK  ] ", "info")
    else
      printf " [  KO  ] ".center(120,'#').colorize(:red)
      printf "\n"
      log("Error in process: #{message} - STOP","error")
      exit 0
    end
  else
    printf message
    file_log = File.open("/root/.#{type}-manager.log", "a")
    file_log.puts "*******************************************************************************************************\n"
    file_log.puts "* #{message}\n"
    file_log.puts "* #{cmd}\n"
    file_log.puts "*******************************************************************************************************\n"
    file_log.close
    check = "KO"
    commands.each {|cmd|
      if cmd[0] == " "
        cmd[0] = ""
      end
      output = `#{cmd} 2>&1 >>/root/.#{type}-manager.log`
      check = $?.success?
    }
    if "#{check}" == "true"
      printf "[  OK  ]\n".colorize(:green).rjust(140-message.length)
      log("#{message}  [  OK  ] ", "info")
    else
      printf "[  KO  ]\n".colorize(:red).rjust(140-message.length)
      log("Error in process: #{message} - STOP","error")
      exit 0
    end
  end
end

# Global var
opt                            = Getopt::Std.getopts("f:bhvprms3k:nc:")
time                           = Time.new
date                           = time.strftime("%Y%m%d-%H%M%S")
rsa_key                        = "/var/www/rb-rails/config/rsa"
hostname                       = `hostname -s 2>/dev/null`.strip()
encrypted_data_bag_secret_path = "/etc/chef/encrypted_data_bag_secret"
nring                          = 60    # Max Number of backup files to store on S3


# Check compatibile options
usage() if opt['h'] or (opt['f'].nil? and opt['f']) or (opt['f'] and opt['s']) or (opt['3'] and opt['s']) or (opt['k'].nil? and opt['k'] and opt['3']) or (!opt['m'] and opt['p'])

read_chef_file

#################
# Backup option #
#################
if opt['b']
  # Init variables
  type = "backup"
  tar = "tar --ignore-failed-read -zvcPf"
  if opt['v']
    verbose   = "verbose"
    s3verbose = "-v"
  else
    verbose   = "quiet"
    s3verbose = "-q"
  end

  # Verify if log file exists
  FileUtils.rm_f("/root/.backup-manager.log") if File.exists?("/root/.backup-manager.log")

  # Check backup destination
  if opt['f']
    if File.exists?(opt['f'])
      printf "File #{opt['f']} already exits\n".colorize(:red)
      exit 0
    else
      file_path = File.expand_path(opt['f'])
    end
  elsif opt['3']
    s3cfg          = (opt['s'] ? "/root/.s3cfg-backup" : "/root/.s3cfg")
    file_path_name = "#{date}-#{hostname}-backup.tar.gz"
    file_path      = "/tmp/#{file_path_name}"
    s3bucket       = `cat /etc/druid/base.properties | grep druid.storage.bucket= | tr '=' ' '|awk '{print $2}'`.strip

    # Check Options
    if s3bucket == "" or File.exist?(s3cfg) == "false"
      printf "Please, check your AWS config, exiting\n".colorize(:red)
      exit 0
    end
    check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} ls s3://#{s3bucket}/",verbose, type, "Checking s3://#{s3bucket}/ access ")
    nbackup = `s3cmd -c #{s3cfg} -v ls s3://#{s3bucket}/backup/ | sort | cut -d/ -f5`
    if nbackup.lines.count >= nring
      deletefile = nbackup.lines.first.strip()
      check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} rm s3://#{s3bucket}/backup/#{deletefile}",verbose, type, "Deleting #{deletefile} backup file ... ")
    end
    printf "The backup will be stored in s3://#{s3bucket}/backup/#{file_path_name}\n"
  else
    printf "Destination error, check your choice\n".colorize(:red)
    exit 0
  end

  node_config  = Chef::Node.load(hostname)

  # # Looking if actual node is the master
  if (node_config["redborder"]["manager"]["mode"] == "master") or (node_config["redborder"]["manager"]["mode"] == "corezk") or (node_config["redborder"]["manager"]["mode"] == "core") or (node_config["redborder"]["manager"]["mode"] == "chef")
    manager_info = File.open("/tmp/#{hostname}-backup-#{date}.txt", "w")
    manager_info.puts "Backup date: #{date}\n"
    manager_info.puts "Node: #{hostname}"
    manager_info.puts "Version: #{`rpm -aq | sed -e '/redborder-manager/!d'`}"
    manager_info.puts "Management IP Address: #{node_config["redborder"]["manager"]["bond0"]["ip"]}"
    manager_info.puts "Management Prefixlen: #{node_config["redborder"]["manager"]["bond0"]["prefixlen"]}"
    manager_info.puts "Sync Ip Address: #{node_config["redborder"]["manager"]["bond1"]["ip"]}"
    manager_info.puts "Sync Prefixlen: #{node_config["redborder"]["manager"]["bond1"]["prefixlen"]}"
    manager_info.close

    # Make database backup
    check_oper("nice -n 19 ionice -c2 -n7 su - opscode-pgsql -m -s /bin/bash -c \"/opt/opscode/embedded/bin/pg_dumpall -c | gzip --fast > /tmp/#{hostname}-postgresql-dump-#{date}.gz\"; sync", verbose, type, "Database backup in progress ... ")      # Make important data backup
    if opt['m']
      tarcmd = "nice -n 19 ionice -c2 -n7 #{tar} #{file_path} --exclude=/var/opt/chef-server/nginx/html --exclude=/opt/rb/root/.chef/syntax_check_cache --exclude=/opt/rb/var/chef/cookbooks --exclude=/opt/rb/var/chef/backup --exclude=/opt/rb/var/chef/data --exclude=/opt/rb/var/chef/backups --exclude=/var/opt/chef-server/bookshelf/data /opt/rb/root/.chef /etc/chef-server /opt/rb/etc/chef /opt/rb/var/chef /opt/rb/var/www/rb-rails/config /opt/rb/etc/mode /etc/hosts /opt/rb/etc/keepalived/keepalived.conf /opt/rb/var/pgdata/pg_hba.conf /var/opt/chef-server/nginx/ca /var/opt/chef-server/erchef/etc /opt/rb/etc/manager_index /tmp/#{hostname}-postgresql-dump-#{date}.gz /tmp/#{hostname}-backup-#{date}.txt"
    else
      tarcmd = "nice -n 19 ionice -c2 -n7 #{tar} #{file_path} --exclude=/var/opt/chef-server/nginx/html --exclude=/opt/rb/root/.chef/syntax_check_cache --exclude=/opt/rb/var/chef/cookbooks --exclude=/opt/rb/var/chef/backup --exclude=/opt/rb/var/chef/data --exclude=/opt/rb/var/chef/cache --exclude=/opt/rb/var/chef/backups --exclude=/var/opt/chef-server/bookshelf/data /opt/rb/root/.chef /etc/chef-server /opt/rb/etc/chef /opt/rb/var/chef /opt/rb/var/www/rb-rails/config /opt/rb/etc/mode /etc/hosts /opt/rb/etc/keepalived/keepalived.conf /opt/rb/var/pgdata/pg_hba.conf /var/opt/chef-server/nginx/ca /var/opt/chef-server/erchef/etc /opt/rb/etc/manager_index /tmp/#{hostname}-postgresql-dump-#{date}.gz /tmp/#{hostname}-backup-#{date}.txt"
    end

    if opt['f'] # To path
      check_oper("#{tarcmd}; sync", verbose, type, "Making backup of #{hostname} node ... ")
    elsif opt['3'] # To S3 AWS
      check_oper("#{tarcmd}; nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} sync #{file_path} s3://#{s3bucket}/backup/; rm -f #{file_path}", verbose, type, "Making backup of #{hostname} node on s3 ... ")
    end

    # Delete temporal files
    message = "Deleting temporal files ... "
    check_oper("nice -n 19 ionice -c2 -n7 rm -f /tmp/#{hostname}-postgresql-dump-#{date}.gz; nice -n 19 ionice -c2 -n7 rm -f /tmp/#{hostname}-backup-#{date}.txt", verbose, type, message)

  else
    printf "Actual node is not the master/core/corezk/chef, exiting\n".colorize(:red)
    exit 0
  end

##################
# Restore Option #
##################
elsif opt['r']
  type       = "restore"
  verified   = false

  if opt['v']
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

  if opt['n']
    verified = true
    check_oper("rm -f /opt/rb/etc/blocked/*; touch /opt/rb/etc/s3user.txt; rm -f /opt/rb/etc/cluster.lock", verbose, type, "Deleting locking files ... ")
  else
    node_config = Chef::Node.load(hostname)
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
    if opt['f'] and opt['3'].nil? and File.exists?(opt['f'])
      path = File.expand_path(opt['f'])
    elsif opt['3']
      s3cfg    = (opt['s'] ? "/root/.s3cfg-backup" : "/root/.s3cfg")
      s3bucket = (opt['k'] ? opt['k'] : (externals.nil? ? "redborder" : externals['S3BUCKET']))
      s3bucket = "redborder" if s3bucket.nil? or s3bucket.empty?

      check_oper("nice -n 19 ionice -c2 -n7 s3cmd -c #{s3cfg} #{s3verbose} ls s3://#{s3bucket}/", verbose, type, "Checking S3 access ... ")
      nbackup = `s3cmd -c #{s3cfg} -v ls s3://#{s3bucket}/backup/ | sort | cut -d/ -f5`
      if opt['f'].nil?
        if nbackup.lines.count == 0
          printf "There is no backup files to restore on s3://#{s3bucket}/backup/\n"
          exit 0
        else
          file_to_restore = nbackup.lines.last.strip()
        end
      else
        message = "Checking s3://#{s3bucket}/backup/#{opt['f']} ... "
        printf message
        if `s3cmd -c #{s3cfg} ls s3://#{s3bucket}/backup/#{opt['f']}` == ""
          printf "[  KO  ]\n".colorize(:red).rjust(140-message.length)
          printf "The file doesn't exists\n"
          exit 0
        else
          printf "[  OK  ]\n".colorize(:green).rjust(140-message.length)
          file_to_restore = opt['f']
        end
      end
      path = "/tmp/#{file_to_restore}"
      message = "Downloading #{file_to_restore} file ... "
      check_oper("s3cmd -c #{s3cfg} #{s3verbose} sync s3://#{s3bucket}/backup/#{file_to_restore} /tmp/", verbose, type, message)
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
    failed = true if (opt['m']) and (`tar -tf #{path} | grep "opt/rb/var/chef/cache/cookbooks"` == "")

    if noderestore.nil? or ipmagntorestore.nil? or ipsynctorestore.nil? or failed
      printf "The backup is not valid.\n".colorize(:red)
      exit 0
    end

    if hostname != noderestore
      check_oper("hostname #{noderestore}", verbose, type, "Changing #{hostname} node name to #{noderestore} node name ... ")
    end

    # Stop chef-client
    check_oper("rb_service stop chef druid awslogs rb-cloudwatch rb-monitor rb-workers rb-webui nprobe n2klocd memcached kafka hadoop_ stanchion riak zookeeper pgpool nginx freeradius postgresql keepalived", verbose, type, "Stoping all services ... ")
    # Restore the node
    check_oper("#{tar} #{path} -C /", verbose, type, "Restoring files ... ")
    `sed -i '/rb_aws_secondary_ip.sh/d' /etc/keepalived/keepalived.conf`
    # we need to change remote ips for current ips on /etc/hosts
    check_oper("sed -i 's/^#{ipmagntorestore} /127.0.0.1 /g' /etc/hosts; sed -i 's/^#{ipsynctorestore} /127.0.0.1 /g' /etc/hosts;", verbose, type, "Replacing ips on /etc/hosts ... ")
    # Start postgress on chef-server
    check_oper("rb_service start keepalived postgresql", verbose, type, "Restoring postgresql service ... ")
    # Restore chef-server data
    check_oper("su - opscode-pgsql -m -s /bin/bash -c \"gunzip -q -c /tmp/*-postgresql-dump-*.gz | /opt/chef-server/embedded/bin/psql -U \"opscode-pgsql\" -d postgres\"", verbose, type, "Restoring chef-server database ...")
    # Ensure chef is running
    check_oper("rb_chef restart; sleep 5; rb_create_rabbitusers.sh", verbose, type, "Starting chef-server services ... ")

    if opt['n']
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
    secret = Chef::EncryptedDataBagItem.load_secret(encrypted_data_bag_secret_path)

    # Change s3 domains if proceed
    if opt['n']
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
          check_oper("/opt/rb/bin/rb_create_cert.sh -n #{cert}", verbose, type, "Creating #{cert} cert ...")
          check_oper("/opt/rb/bin/rb_upload_certs.sh #{cert}"  , verbose, type, "Uploading #{cert} cert ...")
        end
      end

      check_oper("mkdir -p /root/.chef/trusted_certs/; rsync /var/opt/chef-server/nginx/ca/erchef.#{domain_rbglobal}.crt /var/opt/chef-server/nginx/ca/#{domain_rbglobal}.crt /opt/rb/root/.chef/trusted_certs/; mkdir -p /home/redborder/.chef/trusted_certs/; rsync /var/opt/chef-server/nginx/ca/erchef.#{domain_rbglobal}.crt /var/opt/chef-server/nginx/ca/#{domain_rbglobal}.crt /home/redborder/.chef/trusted_certs/; chown -R redborder:redborder /home/redborder/.chef", verbose, type, "Copying certs to trusted certs")

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
        `echo "127.0.0.1 erchef.#{new_domain["name"]} postgresql.#{new_domain["name"]}" >> /etc/extrahosts` if opt['n']
        new_domain["name"] = domain_rbglobal
        new_domain.save
      end

      new_publicdomain_rbglobal = Chef::DataBagItem.load('rBglobal','publicdomain') rescue new_publicdomain_rbglobal=nil
      if !new_publicdomain_rbglobal.nil? and new_publicdomain_rbglobal["name"] == ""
        new_publicdomain_rbglobal["name"] = publicdomain_rbglobal
        new_publicdomain_rbglobal.save
      end

      # empty virtual ips on new environment
      ["ipvirtual-external-erchef", "ipvirtual-external-freeradius", "ipvirtual-external-kafka", "ipvirtual-external-n2klocd", "ipvirtual-external-n2kmobiled", "ipvirtual-external-nprobe", "ipvirtual-external-rb-reputation", "ipvirtual-external-rb-webui", "ipvirtual-external-riak", "ipvirtual-external-trap2kafka", "ipvirtual-internal-cep", "ipvirtual-internal-drill", "ipvirtual-internal-erchef", "ipvirtual-internal-hadoop_namenode", "ipvirtual-internal-hadoop_resourcemanager", "ipvirtual-internal-kafka", "ipvirtual-internal-n2kmetricd", "ipvirtual-internal-oozie", "ipvirtual-internal-postgresql"].each do |x|
        db_temp = Chef::DataBagItem.load('rBglobal', x ) rescue db_temp = nil
        if !db_temp.nil? and !db_temp["ip"].nil? and db_temp["ip"]!=""
          db_temp["ip"] = ""
          db_temp.save
        end
      end
    end
    `echo "127.0.0.1 erchef.#{domain_rbglobal} postgresql.#{domain_rbglobal}" >> /etc/extrahosts` if opt['n']

    if !opt['c'].nil? and !opt['c'].empty?
      printf "CMD: #{opt['c']}\n"
      system(opt['c'])
    end

    if hostname != noderestore and !opt['p']
      # Change node to original
      check_oper("rb_change_hostname.sh -s -f -n #{hostname}", verbose, type, "Restoring #{hostname} node name ... ")

      # Check if noderestore exists
      if `knife node list | grep #{noderestore}` != ""
        check_oper("knife node delete #{noderestore} -y; knife client delete #{noderestore} -y; knife role delete #{noderestore} -y", verbose, type, "Deleting #{noderestore} client and node ... ")
      end
    end

    # Run chef once
    check_oper("rb_run_chef_once.sh", verbose, type, "Applying chef config 1/2 (please, be patient) ... ")
    check_oper("rb_run_chef_once.sh", verbose, type, "Applying chef config 2/2 (please, be patient) ... ")

    # Deleting old certs if the domain has changed
    if !domain_restore.nil? and domain_restore != domain_rbglobal
      [domain_restore,"chefwebui.#{domain_restore}","data.#{domain_restore}","erchef.#{domain_restore}","repo.#{domain_restore}","s3.#{domain_restore}","webui.#{domain_restore}"].each do |cert|
        check_oper("knife data bag delete certs http_#{cert}_pem -y", verbose, type, "Deleting #{cert} data bag item ... ")
        FileUtils.rm_f("/var/opt/chef-server/nginx/ca/#{cert}.crt") if File.exists?"/var/opt/chef-server/nginx/ca/#{cert}.crt"
      end
    end

    if opt['m']
      #  reset riak config if necessary
      check_oper("rb_reset_riak_conf.rb -y -v", verbose, type, "Restarting riak config ... ")

      # upload cookbooks to s3
      check_oper("rb_upload_cookbooks.sh -f", verbose, type, "Uploading cookbooks to riak ... ")
    end

    # start all cluster services
    check_oper("rb_service start", verbose, type, "Starting all cluster services ... ")

    # Delete temporal files
    message = "Deleting temporal files ... "
    if opt['f']
      check_oper("nice -n 19 ionice -c2 -n7 rm -f /tmp/*-postgresql-dump-*; nice -n 19 ionice -c2 -n7 rm -f #{file_config}; rm -f /opt/rb/etc/extrahosts", verbose, type, message)
    else
      check_oper("nice -n 19 ionice -c2 -n7 rm -f /tmp/*-postgresql-dump-*; nice -n 19 ionice -c2 -n7 rm -f #{file_config}; nice -n 19 ionice -c2 -n7 rm -f /tmp/#{file_to_restore}; rm -f /opt/rb/etc/extrahosts", verbose, type, message)
    end
    printf "Node restored successfully!!!\n".colorize(:green)
  else
    printf "Actual node is not the master, exiting\n".colorize(:red)
    exit 0
  end
else
  usage()
end
