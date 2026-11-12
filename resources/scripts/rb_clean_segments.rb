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
require 'aws-sdk-s3'
require 'zk'
require 'pg'
require 'iso8601'
require 'fileutils'
require 'optparse'

module CleanDruidSegments
  DRUID_RUNTIME_PROPS = '/etc/druid/_common/common.runtime.properties'
  MINIO_DATA_DIR      = '/var/minio/data'
  DRUID_INDEX_CACHE   = '/var/druid/historical/indexCache'
  DRUID_LOCAL_DATA    = '/var/druid/data'
  ZK_HOST             = 'zookeeper.service:2181'
  ZK_LOCK_PATH        = '/cleanDruidSegments'
  
  # TODO: Reemplazar %x[cat...grep...awk] por lectura directa del archivo
  def self.read_druid_config(key)
    %x[cat #{DRUID_RUNTIME_PROPS} 2>/dev/null | grep '^#{key}=' | tr '=' ' ' | awk '{print $2}'].chomp
  end

  def self.logit(text)
    printf('%s\n', text)
  end

  def self.parse_args(args)
    options = { help: false }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [-h]"
      opts.on('-h', '--help', 'Show this help') do
        options[:help] = true
      end
    end
    parser.parse!(args)
    options
  end

  def self.acquire_zk_lock
    zk = ZK.new(ZK_HOST)
    if zk.exists?(ZK_LOCK_PATH)
      zk.close!
      return nil
    end
    zk.create(ZK_LOCK_PATH, ephemeral: true)
    zk
  rescue ZK::Exceptions::ConnectionLoss, StandardError => e
    # TODO: Rescatar solo ZK::Exceptions::ZKException, no StandardError genérico
    logit "Failed to connect to ZooKeeper: #{e.message}. Only remove local data..."
    nil
  end

  def self.release_zk_lock(zk)
    return unless zk
    zk.delete(ZK_LOCK_PATH)
    zk.close!
  end

  def self.connect_pg
    druid_db_uri  = read_druid_config('druid.metadata.storage.connector.connectURI')
    druid_db_user = read_druid_config('druid.metadata.storage.connector.user')
    druid_db_pass = read_druid_config('druid.metadata.storage.connector.password')
    druid_db_host = druid_db_uri.match(/:\/\/(.*?):/)[1]
    druid_db_port = druid_db_uri.match(/:(\d+)\//)[1]
    druid_db_name = druid_db_uri.match(/\/([^\/]+)$/)[1]

    PG.connect(dbname: druid_db_name, user: druid_db_user,
               password: druid_db_pass, port: druid_db_port,
               host: druid_db_host)
  rescue PG::Error => e
    logit "Error connecting to Druid Db: #{e.message}. Unable to load druid rules. Check druid properties"
    exit 1
  end

  def self.load_rules(db)
    rules = []
    db.exec('SELECT DISTINCT ON (datasource) * FROM druid_rules ORDER BY datasource, version DESC') do |result|
      result.each do |row|
        if row['payload'] && !row['payload'].empty?
          begin
            decoded_payload = JSON.parse(row['payload'][2..-1].gsub(/../) { |pair| pair.hex.chr })
            rules << { rules_set: decoded_payload, datasource: row['datasource'] }
          rescue JSON::ParserError => e
            logit "Unacceptable druid rules format for datasource #{row['datasource']}: #{e.message}"
          end
        else
          logit "Skipping row due to empty or invalid payload for datasource #{row['datasource']}"
        end
      end
    end

    default_rules_set = rules.find { |r| r[:datasource] == '_default' }&.dig(:rules_set)
    # TODO: default_rules_set puede ser nil → NoMethodError en .empty?

    if default_rules_set.empty?
      logit 'Unacceptable druid rules format'
      exit 1
    end

    db.exec('SELECT DISTINCT ON (datasource) datasource FROM druid_segments') do |result|
      result.each do |row|
        datasource_exists = rules.any? { |r| r[:datasource] == row['datasource'] }
        if datasource_exists
          logit "#{row['datasource']} already has rules"
        else
          logit "Create empty druid rules set for #{row['datasource']} datasource"
          rules << { rules_set: [], datasource: row['datasource'] }
        end
      end
    end

    [rules, default_rules_set]
  end

  def self.compute_limit_date(rules_set)
    return nil if rules_set.empty?

    first_rule = rules_set.first
    return nil if first_rule['type'] == 'loadForever'

    default_tier = rules_set.select do |x|
      x['tieredReplicants'] && x['tieredReplicants'].first&.first == '_default_tier'
    end.first

    return nil if default_tier.nil?

    period = default_tier['period'].upcase
    return nil if period == 'P5000Y'

    period_in_secs = ISO8601::Duration.new(period).to_seconds
    Time.now - period_in_secs
  end

  def self.extract_date_from_path(path)
    basename = File.basename(path)
    parts = basename.split('_')
    return nil if parts.length < 2
    Time.parse(parts[-2])
  rescue ArgumentError, TypeError
    nil
  end

  def self.remove_files(pattern, limit_date)
    files = Dir[pattern]
    removed = 0
    files.each do |file|
      date = extract_date_from_path(file)
      next unless date
      next unless date < limit_date
      FileUtils.rm_rf(file)
      removed += 1
    end
    logit "#{removed} directories removed"
  end

  def self.remove_from_minio(bucket_name, s3_prefix, datasource, limit_date)
    minio_storage = [MINIO_DATA_DIR, bucket_name, s3_prefix, datasource]
                      .reject { |x| x.nil? || x.empty? }
                      .join('/')
    if Dir.exist?(minio_storage)
      logit 'Removing files from MinIO storage'
      remove_files("#{minio_storage}/*", limit_date)
    end
  end

  def self.remove_from_pg(db, datasource, limit_date)
    # TODO: SQL Injection — usar query parametrizada:
    #   db.exec('SELECT * FROM druid_segments WHERE datasource = $1', datasource)
    segments_to_delete = []
    db.exec("SELECT * FROM druid_segments WHERE datasource = '#{datasource}'") do |result|
      result.each do |row|
        date = Time.parse(row.values_at('start').first)
        segments_to_delete << row if date < limit_date
      end
    end

    if segments_to_delete.size > 0
      logit "#{segments_to_delete.size} segments marked for removing on PG"
      segments_to_delete.each do |segment|
        # TODO: SQL Injection — usar query parametrizada:
        #   db.exec('DELETE FROM druid_segments WHERE id = $1', segment['id'])
        db.exec("DELETE FROM druid_segments WHERE id = '#{segment['id']}'")
      end
    else
      logit 'No segments must be removed from PG'
    end
  end

  def self.remove_from_s3(s3_client, bucket_name, s3_prefix, datasource, limit_date)
    clean_prefix = [s3_prefix, datasource]
                    .reject { |x| x.nil? || x.empty? }
                    .join('/')
                    .gsub(%r{^/+}, '')
                    .gsub(%r{/+$}, '') + '/'

    segments_on_s3 = []
    s3_client.list_objects_v2(bucket: bucket_name, prefix: clean_prefix).each_page do |page|
      segments_on_s3.concat(page.contents.map(&:key))
    end

    segments_to_delete = segments_on_s3.select do |segment|
      relative = segment.sub(/^#{Regexp.escape(clean_prefix)}/, '')
      start_date_str = relative.split('/').first&.split('_')&.first
      next false unless start_date_str
      begin
        Time.parse(start_date_str) < limit_date
      rescue ArgumentError, TypeError
        false
      end
    end

    if segments_to_delete.size > 0
      logit "#{segments_to_delete.size} objects marked for removing on S3"
      segments_to_delete.each do |object_key|
        s3_client.delete_object(bucket: bucket_name, key: object_key)
      end
    else
      logit 'No segments must be removed from S3'
    end
  end

  def self.remove_local_caches(datasource, limit_date)
    if Dir.exist?(DRUID_INDEX_CACHE)
      logit 'Removing files from druid historical indexCache'
      remove_files("#{DRUID_INDEX_CACHE}/#{datasource}/*", limit_date)
    else
      logit 'Warning: Historical folder does not exist. No segments to remove'
    end

    if Dir.exist?(DRUID_LOCAL_DATA)
      logit 'Removing files from localStorage'
      remove_files("#{DRUID_LOCAL_DATA}/#{datasource}/*", limit_date)
    else
      logit 'Warning: Druid localStorage folder does not exist. No segments to remove'
    end
  end

  def self.run(args = ARGV)
    options = parse_args(args)
    if options[:help]
      puts "Usage: #{File.basename($PROGRAM_NAME)} [-h]\n\nRemoves expired Druid segments (PG, S3, MinIO storage, and local caches) older than the retention period."
      return
    end

    Aws.config.update(ssl_verify_peer: false, force_path_style: true)

    zk = acquire_zk_lock
    remove_only_index_cache = zk.nil?
    if remove_only_index_cache
      logit 'Another node has the lock. Only remove local data...'
    end

    unless File.exist?(DRUID_RUNTIME_PROPS)
      logit 'Druid properties not found. Check if any druid service is enabled. No segments to delete'
      return
    end

    db = connect_pg
    logit 'Getting druid rules from PG...'

    begin
      rules, default_rules_set = load_rules(db)

      logit 'Adding rest of datasources without rules'

      rules.each do |rule|
        rules_set  = rule[:rules_set]
        datasource = rule[:datasource]

        logit("----- Segments from datasource: #{datasource} -----")

        rules_set = default_rules_set if rules_set.empty?

        limit_date = compute_limit_date(rules_set)
        if limit_date.nil?
          logit 'No segments must be removed (forever or no default tier)'
          next
        end

        logit "limitDate is #{limit_date}"

        druid_deep_storage = read_druid_config('druid.storage.type')
        bucket_name        = read_druid_config('druid.storage.bucket')
        s3_prefix          = read_druid_config('druid.storage.baseKey')

        unless remove_only_index_cache
          logit "Deleting segments older than #{limit_date}"

          remove_from_pg(db, datasource, limit_date)

          if druid_deep_storage == 's3'
            s3_access_key_id     = read_druid_config('druid.s3.accessKey')
            s3_secret_access_key = read_druid_config('druid.s3.secretKey')
            s3_client = Aws::S3::Client.new(
              access_key_id:     s3_access_key_id,
              secret_access_key: s3_secret_access_key,
              region:            'us-east-1',
              endpoint:          'https://s3.service'
            )
            remove_from_s3(s3_client, bucket_name, s3_prefix, datasource, limit_date)
          end
        end

        remove_local_caches(datasource, limit_date)
        remove_from_minio(bucket_name, s3_prefix, datasource, limit_date) if druid_deep_storage == 's3'
      end
    ensure
      release_zk_lock(zk) unless remove_only_index_cache
      db&.close
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  CleanDruidSegments.run
end
