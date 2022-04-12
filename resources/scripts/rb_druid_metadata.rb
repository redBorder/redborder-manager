#!/usr/bin/ruby

#######################################################################
## Copyright (c) 2014 ENEO Tecnología S.L.
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

require "pg"
require "getopt/std"
require "yaml"
require "json"
require 'json/ext'

def usage()
  printf "rb_druid_metadata.rb [-h] [-d <datasource>] [-s <start_time>] [-e <end_time>][-f <file>]\n"
  printf "   -h             : print this help\n"
  printf "   -a             : get all metadata instead of first one\n"
  printf "   -d <datasource>: filter by datasource or change to this datasource in recover mode\n"
  printf "   -p <partition> : filter by partition  (ignored on recover mode)\n"
  printf "   -s <start_time>: filter by start time (ignored on recover mode)\n"
  printf "   -e <end_time>  : filter by end time   (ignored on recover mode)\n"
  printf "   -i <identifier>: filter by identifier (ignored on recover mode)\n"
  printf "   -f <file>      : recover database from file\n"
end

opt = Getopt::Std.getopts("d:s:he:f:p:i:a")

if opt["h"].nil?
  datasource=opt["d"]
  start_time=opt["s"]
  end_time=opt["e"]
  partition=opt["p"]
  identifier=opt["i"]
  
  config=YAML.load_file("/var/www/rb-rails/config/database.yml")
  
  if config["druid"] and config["druid"]["database"] and config["druid"]["username"] and config["druid"]["password"] and config["druid"]["host"] and config["druid"]["port"]
    conn = PG::Connection.open(:dbname => config["druid"]["database"], :host => config["druid"]["host"], :port => config["druid"]["port"].to_i, :user => config["druid"]["username"], :connect_timeout => config["druid"]["timeout"], :password => config["druid"]["password"])

    if opt["f"].nil?
      cmd="SELECT * from druid_segments"
      conditions=[]
      conditions << "datasource = '#{datasource}'" unless datasource.nil?
      conditions << "start = '#{start_time}'" unless start_time.nil?
      conditions << "end = '#{end_time}'" unless end_time.nil?
      conditions << "id = '#{identifier}'" unless identifier.nil? 
  
      if identifier.nil?
        if partition.nil? or partition.to_i==0
          conditions << "id like '%Z'"
        else
          conditions << "id like '%Z_#{partition}'"
        end
      end
  
      cmd="#{cmd} where #{conditions.join(" and ")}" if conditions.size>0
      cmd="#{cmd} limit 1" if opt["a"].nil?
      res = conn.exec_params(cmd)

      unless res.none?
        res.each do |data|
          data["payload"]=JSON.parse(data["payload"][2..-1].gsub(/../) { |pair| pair.hex.chr }) if data["payload"]
          puts JSON.pretty_generate(data, :indent => "  ")
          break if opt["a"].nil?
        end
      end
    elsif File.exists?(opt["f"])
      file = File.read(opt["f"])
      data = JSON.parse(file)

      if data["payload"] and data["datasource"] and data["start"] and data["end"] and data["id"]
        error=false

        unless datasource.nil?
          data["datasource"] = datasource 
          data["payload"]["dataSource"] = datasource 

          #detecting if this segment has been reindexed
          match = data["payload"]["loadSpec"]["key"].match(/^rbdata\/([^\/]*)\/([^\/]*)/)
          if !match.nil? and match.size>=3
            if match[1]==match[2]
              data["payload"]["loadSpec"]["key"] = data["payload"]["loadSpec"]["key"].gsub(/^rbdata\/([^\/]*)\/([^\/]*)\//, "rbdata/#{datasource}/#{datasource}/")
            else
              data["payload"]["loadSpec"]["key"] = data["payload"]["loadSpec"]["key"].gsub(/^rbdata\/([^\/]*)/, "rbdata/#{datasource}")
            end
          else
            error=true
          end
        end
        data["id"] = "#{data["datasource"]}_#{data["start"]}_#{data["end"]}_#{data["version"]}#{( (data["payload"]["shardSpec"] and data["payload"]["shardSpec"]["partitionNum"] and data["payload"]["shardSpec"]["partitionNum"].to_i!=0) ? "_#{data["payload"]["shardSpec"]["partitionNum"]}" : "" ) }"
        data["payload"]["identifier"] = data["id"]

        if !error
          #isert data into database
          res = conn.exec_params("SELECT * from druid_segments where id = '#{data["id"]}' limit 1")
          if res.none?
            cmd = "insert into druid_segments (id, datasource, created_date, start, \"end\", partitioned, version, used, payload ) VALUES ('#{data["id"]}', '#{data["datasource"]}', '#{data["created_date"]}', '#{data["start"]}', '#{data["end"]}', '#{data["partitioned"]}', '#{data["version"]}', '#{data["used"]}', '\\x#{data["payload"].to_json.unpack("H*")[0]}')"
          else
            cmd = "update druid_segments set datasource='#{data["datasource"]}', created_date='#{data["created_date"]}', start='#{data["start"]}', \"end\"='#{data["end"]}', partitioned='#{data["partitioned"]}', version='#{data["version"]}', used='#{data["used"]}', payload='\\x#{data["payload"].to_json.unpack("H*")[0]}' where id='#{data["id"]}'"
          end
          res = conn.exec_params(cmd)
        end
      end
      puts JSON.pretty_generate(data.to_hash)

    end
  end
else
  usage
end
  
  
#jsondata=JSON.parse(x.to_json)
#p jsondata
