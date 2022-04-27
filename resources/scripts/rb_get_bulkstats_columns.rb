#!/usr/bin/env ruby
#########################################################################    
### Copyright (c) 2014 ENEO Tecnología S.L.
### This file is part of redBorder.
### redBorder is free software: you can redistribute it and/or modify
### it under the terms of the GNU Affero General Public License License as published by
### the Free Software Foundation, either version 3 of the License, or
### (at your option) any later version.
### redBorder is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### GNU Affero General Public License License for more details.
### You should have received a copy of the GNU Affero General Public License License
### along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#########################################################################

require "getopt/std"
require "fileutils"
require "yaml"
require "net/http"
require "openssl"
require "resolv"

##########################
## Methods
## #######################
def usage()
  printf "rb_get_bulkstats_columns.rb [-h]\n"
  printf "   -h               : print this help\n"
end

def get_domain
if File.exists?("/etc/externals.yml")
    externals             = YAML.load_file('/etc/externals.yml')
    domain_rbglobal       = externals['CDOMAIN']
  elsif File.exists?("/etc/manager.yml")
    manager_config        = YAML.load_file('/etc/manager.yml')
    domain_rbglobal       = manager_config['DOMAIN']
  elsif File.exists?("/etc/resolv.conf")
    domain_rbglobal = `cat /etc/resolv.conf | grep domain | cut -d " " -f2`.strip()
  end
  domain_rbglobal       = "redborder.cluster" if (domain_rbglobal.nil? or domain_rbglobal == "")
  domain_rbglobal
end

def get_bulkstats_columns_targz(outfile)
  new_tar = false
  http = Net::HTTP.new(Resolv.getaddress("data.#{get_domain}"), 443)

  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  path = '/api/v1/monitor/get_bulkstats_columns'
  headers = {
    'Content-Type' => 'application/json'
  }
  
  begin
    puts "domain is #{get_domain}"
    puts "call to #{path}"
    resp = http.get(path, headers)
    if ( resp.code == '200')
      puts "200 received"
      file = File.open(outfile, "w") {|f| f.write(resp.body)}
      puts "tar file written to #{outfile}"
      new_tar=true
    else
      puts resp.code
    end
  rescue *ALL_NET_HTTP_ERRORS => e
    #puts e.message
    false
  end
  new_tar
end

###############################
# MAIN
##############################

ALL_NET_HTTP_ERRORS = [
  Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
  Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
]


opt = Getopt::Std.getopts("h")

bulkstats_columns_tar_gz="/share/bulkstats.tar.gz"

if opt["h"]
  usage
  exit 0
end


get_bulkstats_columns_targz(bulkstats_columns_tar_gz)

exit 0
