#!/usr/bin/env ruby

require 'chef'
require 'json'
require 'netaddr'
require "getopt/std"
require 'yaml'

def usage
  printf("rb_user_s3 [-h] [-a] [-q] [-u <username>] [-e <email>]\n")
  printf("  -h  -> print this help\n")
  printf("  -a  -> create admin user (if it is not already created)\n")
  printf("  -u username\n")
  printf("  -e email -> assign this email to the created user\n")
  printf("  -q -> show only json output\n")
  exit 1
end

def translate_upload_json(data, domain)
  if data["id"].nil? or data["key_id"].nil? or data["key_secret"].nil?
    printf "ERROR: key_id and key_secret not present\n"
  else
    # Add new keys
    data["riak-cs_id"] = data["id"]
    data["id"] = DBINAME
    data["hostname"] = "s3.#{domain}"
    data["bucket"] = "redborder"
    data["key_created"] = true
    # Create new data bag item --> passwords.s3_secrets
    databag_item  = Chef::DataBagItem.new
    databag_item.data_bag DBNAME
    databag_item.raw_data = Chef::JSONCompat.from_json(data.to_json)
    if databag_item.save
      printf "Databag #{DBINAME} created\n"
    end
  end
end

opt = Getopt::Std.getopts("he:u:aq")

usage if opt["h"]

riak_cs_ip = NetAddr::CIDR.create(`grep listener /etc/riak-cs/riak-cs.conf | grep -v "^#" | awk '{print $3;}' | cut -d ":" -f 1`.strip).ip

DBINAME="s3_secrets"
DBNAME="passwords"
S3FILE="/etc/redborder/s3user.txt"
CDOMAIN=File.open("/etc/redborder/cdomain").first.chomp

if opt["a"]
  username = "redborder" if opt["u"].nil?
  email    = "admin@#{CDOMAIN}" if opt["e"].nil?

  Chef::Config.from_file("/etc/chef/client.rb")
  Chef::Config[:node_name]  = "admin"
  Chef::Config[:client_key] = "/etc/opscode/admin.pem"
  Chef::Config[:http_retry_count] = 5

  #chef if we can create admin users:
  anonymous_user_creation = `grep anonymous_user_creation /etc/riak-cs/riak-cs.conf | grep anonymous_user_creation | grep -v "^#" | grep "= on"`

  if anonymous_user_creation==""
    printf "ERROR: the riak-cs doesn't allow create user with anonymous user\n"
    ret=1
  else
    riak_cs_ip="127.0.0.1" if (riak_cs_ip.nil? or riak_cs_ip=="" or riak_cs_ip=="0.0.0.0")
    begin
      begin
        #we check first if the user is already created in chef
        data = Chef::DataBagItem.load(DBNAME, DBINAME)
      rescue
        #we try second time after some
        sleep 2
        data = Chef::DataBagItem.load(DBNAME, DBINAME)
      end

      if data['key_id'].nil? or data["key_secret"].nil? or data['key_id'] == "admin-key" or data["key_secret"] == "admin-secret"
        # The databag doesn't contain proper values. Then we have to create new user
        create=true
      else
        printf "INFO: The databag item #{DBINAME} already exists\n"
      end

    rescue Errno::ECONNREFUSED
      printf "ERROR: cannot contact chef-server #{Chef::Config[:chef_server_url]}\n"
      ret=1
    rescue Net::HTTPServerException
      create=true
    end

    # New admin user creation
    if create
      printf "Creating username #{username} (#{email}) into riak-cs server (#{riak_cs_ip}):\n"
      out  = `curl -H 'Content-Type: application/json' -X POST http://#{riak_cs_ip}:8088/riak-cs/user --data '{"email":"#{email}", "name":"#{username}"}'`# 2>/dev/null`
      begin
        data = JSON.parse(out);
        f = File.new(S3FILE, "w")
        f.write(out)
        f.close
        translate_upload_json(data, CDOMAIN)
      rescue
        if out.include?("The specified email address has already been registered")
          printf "INFO: the username #{username} (#{email}) already exists into riak-cs\n"
          if File.exist?(S3FILE)
            data = JSON.parse(File.read(S3FILE))
            translate_upload_json(data, CDOMAIN)
          end
        else
          printf "ERROR: #{out}\n"
          ret=1
        end
      end
    end
  end
else
  # New user (no admin) creation
  riak_cs_ip="riak.#{mdat["DOMAIN"]}" if (riak_cs_ip.nil? or riak_cs_ip=="" or riak_cs_ip=="0.0.0.0")
  username=opt["u"]
  email=opt["e"]
  unless username.nil? or email.nil?
    printf "Creating username #{username} (#{email}) into riak-cs server (#{riak_cs_ip}):\n" if !opt["q"]
    `curl -H 'Content-Type: application/json' -X POST http://#{riak_cs_ip}:8088/riak-cs/user --data '{"email":"#{email}", "name":"#{username}"}'`# 2>/dev/null`
  end
  print("\n")
end
