#!/usr/bin/env ruby

require 'chef'
require 'json'
require 'yaml'

CDOMAIN=File.open("/etc/redborder/cdomain").first.chomp
DBNAME="rBglobal"

buckets=["redborder", "rbookshelf"]

Chef::Config.from_file("/etc/chef/client.rb")
Chef::Config[:node_name]  = "admin"
Chef::Config[:client_key] = "/etc/opscode/admin.pem"
Chef::Config[:http_retry_count]=5

hostname = `hostname -s`.strip
node = Chef::Node.load(hostname)
ret=0

buckets.each do |b|
  dbiname="#{b}-bucket"
  data = nil
  begin
    data = Chef::DataBagItem.load(DBNAME, dbiname)
  rescue Errno::ECONNREFUSED
    printf "ERROR: cannot contact erchef #{Chef::Config[:chef_server_url]}\n"
    data = nil
    ret=1
  rescue Net::HTTPServerException
    printf "WARNING: the databag rBglobal-#{b}-bucket doesn't exist!!!\n"
    data = Chef::DataBagItem.new
    data.data_bag DBNAME
    data["id"] = dbiname
    data["created"] = false
    if data.save
      printf "INFO: the databag rBglobal-#{b}-bucket has been created\n"
    else
      printf "ERROR: cannot create databag rBglobal-#{b}-bucket\n"
      data=nil
      ret=1
    end
  end

  if !data.nil?
    found=`s3cmd ls 2>/dev/null| grep -q "s3://#{b}$"; [ $? -eq 0 ] && echo -n 1`
    if (!data["created"].nil? and (data["created"]==true or data["created"]=="true"))
      if found=="1"
        printf "INFO: the bucket #{b} is already created\n"
      else
        printf "INFO: the bucket #{b} is already created but it doesn't look working\n"
      end
    else
      out=`s3cmd --config /root/.s3cfg mb s3://#{b}`.strip if found!="1"
      if out=="Bucket 's3://#{b}/' created" or found=="1"
        user_data=`curl -H 'Content-Type: application/json' -X POST http://s3.#{CDOMAIN}:8088/riak-cs/user --data '{"email":"#{b}@#{CDOMAIN}", "name":"#{b}"}'`
        user_data_h = JSON.parse(user_data)
        data["user"] = user_data_h
        s3_grant=`s3cmd --config /root/.s3cfg --acl-grant=all:#{b}@#{CDOMAIN} setacl s3://#{b}`
        data["created"]=true
        if data.save
          if found=="1"
            printf "INFO: #{b} bucket created successfully\n"
          else
            printf "INFO: #{b} bucket updated successfully\n"
          end
        else
          printf "ERROR: cannot save #{b} bucket\n"
          ret=1
        end
      else
        printf "ERROR: #{out}\n"
        ret=1
      end
    end
  end
end

exit ret
