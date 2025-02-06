#!/usr/bin/env ruby
########################################################################
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
require 'fileutils'
require 'yaml'
require 'json'
require 'logger'
require 'openssl'
require 'base64'

def get_fingerprint(message, hash_key, hash_function)
    digest = OpenSSL::Digest.new(hash_function)
    hmac = OpenSSL::HMAC.hexdigest(digest, hash_key, message)
    return hmac
end

logger = Logger.new('/var/log/rb_get_raw_vault.log', 10, 1024000)
logger.level = Logger::INFO

opt = Getopt::Std.getopts("Y:M:D:H:m:d:b:h")

if (opt["Y"].nil? || opt["M"].nil? || opt["D"].nil? || opt["H"].nil? || opt["m"].nil? || (opt["d"].nil? && opt["b"].nil?))
    exit 1
else
    #Obtain bucket name
    bucket = "redborder"
    s3cmd_config = "/root/.s3cfg-redborder"
    begin
        logger.debug("Trying to read externals.yml")
        externals_conf = YAML.load_file("/etc/externals.yml") rescue externals_conf = nil
        bucket = external_conf["S3BUCKET"]
        s3cmd_config = "/root/.s3cfg"
        logger.debug("bucket=#{bucket} obtained suscessfully from externals.yml")
    rescue
        logger.warn("Can't read /etc/externals, using default configuration")
    end

    #Obtain fingerprint specifications from chef
    check_fingerprint = true
    begin
        logger.debug("Loading chef gem")
        require 'chef'
        logger.debug("Loading fingerprint spec from chef node")
        Chef::Config.from_file("/root/.chef/knife.rb")
        Chef::Config[:node_name]  = "admin"
        Chef::Config[:client_key] = "/etc/chef/admin.pem"

        hostname = `hostname -s`.strip

        node = Chef::Node.load(hostname)
        hash_key = node["redBorder"]["rsyslog"]["hash_key"]
        hash_function = node["redBorder"]["rsyslog"]["hash_function"]
        logger.debug("Fingerprint Hash Key: #{hash_key}")
        logger.debug("Fingerprint Hash Function: #{hash_function}")
    rescue
        logger.error("Can't get fingerprint spec from chef node, it won't be calculated")
        check_fingerprint = false
    end

    #Obtain date with minute granularity from options
    year = opt["Y"]
    month = opt["M"]
    day = opt["D"]
    hour = opt["H"]
    minute = opt["m"]
    dims = []
    plain_dims = opt["d"].is_a?(Array) ? opt["d"] : [opt["d"]]

    # Decode encoded dimensions (-b parameter)
    encoded_dims = opt["b"].is_a?(Array) ? opt["b"] : [opt["b"]]
    decoded_dims = encoded_dims.map { |d|
        Base64.urlsafe_decode64(d)
    }
    # Join dimensions with encoded dimensions
    if !plain_dims.nil?
        dims.concat(plain_dims)
    end
    if !decoded_dims.nil?
        dims.concat(decoded_dims)
    end
    dims = dims.compact

    logger.info("Query for date #{year}/#{month}/#{day}-#{hour}:#{minute} and dimensions #{dims}")

    dimension_hash = {}
    dims.each do |d|
      dimName, dimValue = d.split('=', 2)
      dimension_hash[dimName] = dimValue
    end
    logger.debug("dimension array = #{dimension_hash}")

    #Temporal files generation    
    pid = Process.pid
    tmp_dir = "/tmp/raw_vault/#{pid}"
    logger.debug("Creating tmp_dir at #{tmp_dir}")
    FileUtils.mkdir_p tmp_dir

    debug=`/usr/bin/python /bin/s3cmd -c /root/.s3cfg_initial get --recursive s3://bucket/rbraw/rb_vault_post/default/dt=#{year}-#{month}-#{day}/hr=#{hour}/min=#{minute}/1_ #{tmp_dir}`
    logger.debug(debug)

    if !Dir.glob("#{tmp_dir}/*.gz").empty?
       system("gzip -c -d #{tmp_dir}/*.gz > #{tmp_dir}/raw.json")
       #Compress and normalize json with jq:
       raw_json = `jq -cM . #{tmp_dir}/raw.json`
       result = ""
       begin
           raw_json.each_line do |event|
               raw = JSON.parse(event)
               #Filter
               logger.debug("RAW: #{raw}")
               merged = raw.merge(dimension_hash)
               logger.debug("MERGED: #{merged}")
               if(raw == merged)
                   logger.debug("JSON RAW MATCH")
                   message = raw["raw-message"]
                   fingerprint = get_fingerprint(message, hash_key, hash_function)
                   logger.debug("Verified fingerprint: #{fingerprint}")
                   raw["verified_fingerprint"] = fingerprint
                   result.concat("#{JSON.pretty_generate(raw)}\n\n")
               else
                   logger.debug("JSON RAW NOT MATCH")
               end
           end
       rescue
           logger.error("Can't generate fingerprint, returning original json")
           result = raw_json
       end
       puts result
    end

    logger.debug("Deleting tmp_dir at #{tmp_dir}")
    FileUtils.rm_rf tmp_dir
end