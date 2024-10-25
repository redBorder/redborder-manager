#!/usr/bin/env ruby
########################################################################    
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

require 'json'
require 'socket'
require 'aws'
require 'aws-sdk-s3'
require 'zk'
require 'pg'
require 'iso8601'
require 'fileutils'

def removeFiles(path, limitDate)
  files = Dir[path]
  removed = 0
  files.each do |file|
    split = file.split("/")
    lastStr = split[split.length - 1]
    return if lastStr.nil?
    split = lastStr.split("_")
    return if (split.length - 2) < 0
    date = Time.parse split[split.length - 2]
    if date < limitDate
      #puts "Removing directory #{file}"
      FileUtils.rm_rf(file)
      removed += 1
    end
  end

  logit "#{removed} directories removed"
end

def logit(text)
  printf("%s\n", text)
end

Aws.config.update({ssl_verify_peer: false,
                 force_path_style: true
                 })

zk_config = YAML.load_file("/var/www/rb-rails/config/rbdruid_config.yml")
zk = ZK.new zk_config["production"]["zk_connect"]

remove_only_indexCache = false

# Do nothing if path exists
if zk.exists? '/cleanDruidSegments'
  logit "Another node have the lock. Only remove local data..."
  remove_only_indexCache = true
else
  zk.create('/cleanDruidSegments', '', :ephemeral => false)
end

# PG connection
druid_config = YAML.load_file("/var/www/rb-rails/config/database.yml")
db =  PG.connect(dbname: druid_config["druid"]["database"], user: druid_config["druid"]["username"],
                 password: druid_config["druid"]["password"], port: druid_config["druid"]["port"],
                 host: druid_config["druid"]["host"])
  
# Get rules info from PG
rules = []
db.exec("SELECT DISTINCT ON (datasource) *
  FROM druid_rules
  ORDER BY datasource, version DESC") do |result|
  result.each do |row|
    if row["payload"] && !row["payload"].empty?
      # Decode the payload of the rule
      begin
        decoded_payload = JSON.parse(row["payload"][2..-1].gsub(/../) { |pair| pair.hex.chr })
        rules << {rules_set: decoded_payload, datasource: row["datasource"]}
      rescue JSON::ParserError => e
        logit "Unacceptable druid rules format for datasource #{row["datasource"]}: #{e.message}"
      end
    else
      logit "Skipping row due to empty or invalid payload for datasource #{row["datasource"]}"
    end
  end
end

default_rules_set = rules.find { |rule| rule[:datasource] == '_default' }&.dig(:rules_set)

if default_rules_set.empty?
  logit "Unacceptable druid rules format"
  exit
end

rules.each do |rule|
  rules_set = rule[:rules_set]
  datasource = rule[:datasource]

  logit("---------------------Segments from datasource: #{datasource}---------------------")

  if rules_set.empty?
    logit "No rules set found for datasource, applying default rules set"
    rules_set = default_rules_set
  end
  if not rules_set.first["tieredReplicants"].nil?
    tieredReplicants = rules_set.first.fetch("tieredReplicants", {}).fetch("_default_tier", 0).to_i
    logit "tieredReplicants = #{tieredReplicants}"
    type = rules_set.first["type"]
    #if tieredReplicants == 1 and type == "loadForever"
    if type == "loadForever"
      logit "No segments must be removed because druid period is 'forever'"
      next
    end
  end
    
  # Get default tier data and the period to mantain the data
  defaultTier = rules_set.select{|x| 
                            #x["tier"] == "_default_tier" if !x["tier"].nil?
                            x["tieredReplicants"].first.first == "_default_tier" if !x["tieredReplicants"].nil?                        
                            }.first
  logit "defaultTier is #{defaultTier}"
  if defaultTier.nil?
    logit "No default tier exists on PG. Exiting..."
    next
  end
    
  period = defaultTier["period"].upcase
  periodInSecs = ISO8601::Duration.new(period).to_seconds
  limitDate = Time.now - periodInSecs
  logit "limitDate is #{limitDate}"
    
  if period == "P5000Y"
    logit "No segments must be removed because druid period is 'forever'"
    next
  end

  if !remove_only_indexCache
    # Create the lock
    path = zk.create("/cleanDruidSegments/#{datasource}", ephemeral: true)
    
    logit "Deleting segments older than #{limitDate} (Period #{period})"
    
    # Get all the segments from PG
    segments_to_delete_from_pg = []
    db.exec("SELECT * FROM druid_segments WHERE datasource = '#{datasource}'") do |result|
      result.each do |row|
        date = Time.parse row.values_at('start').first
        if date < limitDate
          segments_to_delete_from_pg << row
        end
      end
    end
    
    # Remove segments from PG
    if segments_to_delete_from_pg.size > 0
      logit "#{segments_to_delete_from_pg.size} segments marked for removing on PG"
    
      segments_to_delete_from_pg.each do |segment|
        #puts "Removing PG segment id #{segment['id']}"
    
        # Remove it from PG
        db.exec("DELETE FROM druid_segments WHERE id = '#{segment['id']}'")
      end
    else
      logit "No segments must be removed from PG"
    end
    
    # Remove segments from S3 if necessary
    if File.exist? "/var/www/rb-rails/config/aws.yml"
      s3_config = YAML.load_file("/var/www/rb-rails/config/aws.yml")
      s3 = Aws::S3::Client.new(access_key_id: s3_config["production"]["access_key_id"],
        secret_access_key: s3_config["production"]["secret_access_key"],
        region: 'us-east-1',
        endpoint: endpoint = s3_config["production"]["s3_protocol"].concat("://", s3_config["production"]["s3_host_name"])
        )
      bucket_name = s3_config["production"]["bucket"].chomp!('/')

    
      # Get all the segments from S3
      segments_to_delete_from_s3 = []
      segments_on_s3 = []
      continuation_token = nil

      begin
        response = s3.list_objects_v2(bucket: bucket_name, prefix: "rbdata/#{datasource}/",continuation_token: continuation_token)
        segments_on_s3.concat(response.contents.map(&:key))
        continuation_token = response.next_continuation_token
      end while continuation_token

      # Filter by date
      segments_on_s3.each do |segment|
        date = Time.parse segment.split("/")[2].split("_")[0]
        if date < limitDate
          segments_to_delete_from_s3 << segment
        end

      end
      #end
      # Remove segments from S3
      if segments_to_delete_from_s3.size > 0
        logit "#{segments_to_delete_from_s3.size} objects marked for removing on S3"
        segments_to_delete_from_s3.each do |object_key|
          # puts "Removing S3 object with path #{object_key}"
          # Delete the object
          s3.delete_object(bucket: bucket_name, key: object_key)
        end
      else
        logit "No segments must be removed from S3"
      end
    end

    # Remove zk node
    # zk.delete("/clean_segments/barrier")
    zk.delete path
  end

  # Remove segments from historical indexCache
  logit "Removing files from druid historical indexCache"
  removeFiles("/var/druid/historical/indexCache/#{datasource}/*", limitDate)
  # Remove segments from localStorage
  logit "Removing files from localStorage"
  removeFiles("/var/druid/data/#{datasource}/*", limitDate)
end
zk.delete ('/cleanDruidSegments')
zk.close!