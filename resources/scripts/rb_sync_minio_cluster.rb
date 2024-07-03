#!/usr/bin/env ruby
# frozen_string_literal: true

#######################################################################
# Copyright (c) 2024 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

require 'net/http'
require 'uri'
require 'json'

module RedBorder
  # Add a logger for the RedBorder module
  module Logger
    # clean way to do puts :)
    def self.log(msg)
      puts msg
    end
  end

  # Module for initializing Minio replication
  module MinioReplication
    # Initializes Minio replication if the current node is the cluster leader.
    #
    # @return [void]
    def self.init_minio_replication
      return unless RedBorder::Serf.im_leader?

      RedBorder::Minio.set_minio_replicas
    end
  end

  # Module for interacting with Serf
  module Serf
    # Checks if the current node is the cluster leader.
    #
    # @return [Boolean] Returns true if the current node is the cluster leader, otherwise false.
    def self.im_leader?
      output = `serf members`
      leader = ''
      if $?.success?
        leader_node = output.lines.find { |line| line.include?('leader=ready') }

        leader = leader_node.split[1].split(':')[0] if leader_node
      end

      my_ips = `hostname -I`.split(' ')
      my_ips.include? leader
    end

    # Gets the name of the cluster leader.
    #
    # @return [String] The name of the cluster leader.
    def self.cluster_leader
      output = `serf members`
      leader = ''
      if $?.success?
        leader_node = output.lines.find { |line| line.include?('leader=ready') }

        if leader_node
          parts = leader_node.split
          leader = parts[0]
        end
      end

      leader
    end
  end

  # Module for making HTTP requests
  module HTTP
    HTTP_OPEN_TIMEOUT = 900
    HTTP_READ_TIMEOUT = 900
    # Sends an HTTP request.
    #
    # @param url [String] The URL to request.
    # @param method [String] The HTTP method (GET, POST, DELETE).
    # @param body [String] The request body (optional).
    # @param cookie [String] The cookie to include in the request (optional).
    # @param log [Boolean] log response (optional).
    # @return [Net::HTTPResponse] The HTTP response.
    def self.request(url, method, body = nil, cookie = nil, log: false)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = HTTP_READ_TIMEOUT
      http.open_timeout = HTTP_OPEN_TIMEOUT

      request_class = { 'POST' => Net::HTTP::Post, 'DELETE' => Net::HTTP::Delete }[method.upcase] || Net::HTTP::Get
      request = request_class.new(uri.request_uri)
      request['Content-Type'] = 'application/json' if body
      request['Cookie'] = cookie if cookie
      request.body = body if body

      response = http.request(request)
      RedBorder::Logger.log(response.body) if log

      response
    end
  end

  # Module for interacting with Consul
  module Consul
    CONSUL_ENDPOINT = 'http://127.0.0.1:8500'

    # Retrieves S3 nodes from Consul.
    #
    # @return [Array<Hash>] An array of hashes containing S3 node information.
    #   Each hash contains keys :name, :console_endpoint, and :api_endpoint.
    def self.s3_nodes_from_consul
      response = RedBorder::HTTP.request("#{CONSUL_ENDPOINT}/v1/catalog/service/s3", 'GET')
      JSON.parse(response.body).map do |node|
        {
          name: node['Node'],
          console_endpoint: "http://#{node['Address']}:9000",
          api_endpoint: "http://#{node['Address']}:9001"
        }
      end
    end
  end

  # Module for interacting with Minio
  module Minio
    MINIO_CONFIG_PATH = '/etc/default/minio'
    LOCAL_MINIO_ENDPOINT = 'http://127.0.0.1:9001'
    MINIO_USER_KEY = 'MINIO_ROOT_USER='
    MINIO_ROOT_PASSWORD = 'MINIO_ROOT_PASSWORD='
    BUCKET = 'bucket'
    MINIMUM_MINIO_HOSTS = 1
    CLEAN_S3_DEF_BODY = [{ 'path' => '/', 'versionID' => '', 'recursive' => true }].to_json

    # Retrieves the Minio session ID.
    #
    # @param host [String] The Minio host.
    # @return [String] The Minio session ID.
    def self.minio_session_id(host = LOCAL_MINIO_ENDPOINT)
      credentials = RedBorder::Minio.minio_credentials

      body = {
        accessKey: credentials[:accessKey],
        secretKey: credentials[:secretKey]
      }.to_json

      response = RedBorder::HTTP.request("#{host}/api/v1/login", 'POST', body)
      response['Set-Cookie']
    end

    # Retrieves Minio credentials.
    #
    # @return [Hash] Minio credentials containing :accessKey and :secretKey.
    def self.minio_credentials
      credentials = {}
      File.foreach(MINIO_CONFIG_PATH) do |line|
        if line.start_with?(MINIO_USER_KEY)
          credentials[:accessKey] = line.split('=').last.strip
        elsif line.start_with?(MINIO_ROOT_PASSWORD)
          credentials[:secretKey] = line.split('=').last.strip
        end
      end
      credentials
    end

    # Cleans S3 replication.
    #
    # @return [Net::HTTPResponse] The HTTP response.
    def self.clean_s3_replication
      RedBorder::Logger.log('Cleaning S3 replications...')
      hosts = RedBorder::Consul.s3_nodes_from_consul
      cookie = RedBorder::Minio.minio_session_id
      names = hosts.map { |node| node[:name] }

      body = {
        'all' => true,
        'sites' => names
      }.to_json

      RedBorder::HTTP.request("#{LOCAL_MINIO_ENDPOINT}/api/v1/admin/site-replication", 'DELETE', body, cookie)
    end

    # Cleans S3 slave buckets.
    #
    # @return [void]
    def self.clean_s3_slaves_buckets
      RedBorder::Logger.log('Cleaning S3 Slaves Buckets...')
      hosts = RedBorder::Consul.s3_nodes_from_consul
      hosts.each do |host|
        next if RedBorder::Serf.cluster_leader == host[:name]

        cookie = RedBorder::Minio.minio_session_id host[:api_endpoint]

        RedBorder::HTTP.request("#{host[:api_endpoint]}/api/v1/buckets/bucket/delete-objects?all_versions=true",
                                'POST', CLEAN_S3_DEF_BODY, cookie)
      end
    end

    # Deletes S3 slave buckets.
    #
    # @return [void]
    def self.delete_s3_slaves_buckets
      RedBorder::Logger.log('Deleting S3 Slaves Buckets...')
      hosts = RedBorder::Consul.s3_nodes_from_consul
      hosts.each do |host|
        next if RedBorder::Serf.cluster_leader == host[:name]

        cookie = RedBorder::Minio.minio_session_id host[:api_endpoint]

        body = { 'name' => BUCKET }.to_json

        RedBorder::HTTP.request("#{host[:api_endpoint]}/api/v1/buckets/#{BUCKET}", 'DELETE', body, cookie)
      end
    end

    # Restarts Minio.
    #
    # @return [void]
    def self.restart
      RedBorder::Logger.log('Restarting Minio Service (master)')
      system('service minio restart > /dev/null 2>&1')
      system('sleep 30')
    end

    # Initializes cluster synchronization by performing the following steps:
    #   1. Restart Minio service on the master node.
    #   2. Clean S3 replication configurations.
    #   3. Clean S3 buckets on slave nodes.
    #   4. Delete S3 buckets on slave nodes.
    #   5. Fetches information about S3 hosts from Consul.
    #   6. Retrieves Minio session ID (cookie).
    #   7. Retrieves Minio credentials.
    #
    # @return [Hash] A hash containing information about the initialized cluster synchronization.
    def self.init_cluster_sync
      RedBorder::Minio.restart
      RedBorder::Minio.clean_s3_replication
      RedBorder::Minio.clean_s3_slaves_buckets
      RedBorder::Minio.delete_s3_slaves_buckets
      {
        hosts: RedBorder::Consul.s3_nodes_from_consul,
        cookie: RedBorder::Minio.minio_session_id,
        credentials: RedBorder::Minio.minio_credentials
      }
    end

    # Sets Minio replicas.
    #
    # @return [Net::HTTPResponse] The HTTP response.
    def self.set_minio_replicas
      cluster_data = RedBorder::Minio.init_cluster_sync

      body = cluster_data[:hosts].map do |host|
        { accessKey: cluster_data[:credentials][:accessKey], secretKey: cluster_data[:credentials][:secretKey],
          name: host[:name], endpoint: host[:console_endpoint] }
      end.to_json
      
      return unless cluster_data[:hosts].size > MINIMUM_MINIO_HOSTS

      RedBorder::HTTP.request("#{LOCAL_MINIO_ENDPOINT}/api/v1/admin/site-replication", 'POST', body,
                              cluster_data[:cookie], log: true)
    end
  end
end

# Initialize Minio replication
RedBorder::MinioReplication.init_minio_replication
