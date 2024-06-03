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
      if RedBorder::Serf.is_cluster_leader
        RedBorder::Minio.set_minio_replicas
      end
    end
  end

  # Module for interacting with Serf
  module Serf
    # Checks if the current node is the cluster leader.
    #
    # @return [Boolean] Returns true if the current node is the cluster leader, otherwise false.
    def self.is_cluster_leader
      output = `serf members`
      leader = ''
      if $?.success?
        leader_node = output.lines.find { |line| line.include?("leader=ready") }

        if leader_node
          parts = leader_node.split
          leader = parts[1].split(':')[0]
        end
      end

      my_ips = `hostname -I`.split(' ')
      my_ips.include? leader
    end

    # Gets the name of the cluster leader.
    #
    # @return [String] The name of the cluster leader.
    def self.get_cluster_leader
      output = `serf members`
      leader = ''
      if $?.success?
        leader_node = output.lines.find { |line| line.include?("leader=ready") }

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
    # Sends an HTTP request.
    #
    # @param url [String] The URL to request.
    # @param method [String] The HTTP method (GET, POST, DELETE).
    # @param body [String] The request body (optional).
    # @param cookie [String] The cookie to include in the request (optional).
    # @return [Net::HTTPResponse] The HTTP response.
    def self.request(url, method, body = nil, cookie = nil)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)

      case method.upcase
      when 'POST'
        request = Net::HTTP::Post.new(uri.request_uri)
      when 'DELETE'
        request = Net::HTTP::Delete.new(uri.request_uri)
      when 'GET'
        return Net::HTTP.get_response(uri)
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

      request['Content-Type'] = 'application/json' if body
      request['Cookie'] = cookie if !cookie.nil?
      request.body = body if body

      response = http.request(request)
      response
    end
  end

  # Module for interacting with Consul
  module Consul

    CONSUL_ENDPOINT = "http://127.0.0.1:8500".freeze

    # Retrieves S3 nodes from Consul.
    #
    # @return [Array<Hash>] An array of hashes containing S3 node information.
    #   Each hash contains keys :name, :console_endpoint, and :api_endpoint.
    def self.get_s3_nodes_from_consul
      response = RedBorder::HTTP.request("#{CONSUL_ENDPOINT}/v1/catalog/service/s3", "GET")
      s3_nodes = JSON.parse(response.body).map do |node|
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

    MINIO_CONFIG_PATH = "/etc/default/minio"
    LOCAL_MINIO_ENDPOINT = "http://127.0.0.1:9001"
    MINIO_USER_KEY = "MINIO_ROOT_USER="
    MINIO_ROOT_PASSWORD = "MINIO_ROOT_PASSWORD="
    BUCKET = "bucket"
    MINIMUM_MINIO_HOSTS = 1

    # Retrieves the Minio session ID.
    #
    # @param host [String] The Minio host.
    # @return [String] The Minio session ID.
    def self.get_minio_session_id(host=LOCAL_MINIO_ENDPOINT)
      credentials = RedBorder::Minio.get_minio_credentials

      body = {
        accessKey: credentials[:accessKey],
        secretKey: credentials[:secretKey]
      }.to_json

      response = RedBorder::HTTP.request("#{host}/api/v1/login", "POST", body)
      response['Set-Cookie'] if response['Set-Cookie']
    end

    # Retrieves Minio credentials.
    #
    # @return [Hash] Minio credentials containing :accessKey and :secretKey.
    def self.get_minio_credentials
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
      RedBorder::Logger.log("Cleaning S3 replications...")
      hosts = RedBorder::Consul.get_s3_nodes_from_consul
      cookie = RedBorder::Minio.get_minio_session_id
      names = hosts.map { |node| node[:name] }

      body = {
        "all" => true,
        "sites" => names
      }.to_json

      RedBorder::HTTP.request("#{LOCAL_MINIO_ENDPOINT}/api/v1/admin/site-replication", "DELETE", body, cookie)
    end

    # Cleans S3 slave buckets.
    #
    # @return [void]
    def self.clean_s3_slaves_buckets
      RedBorder::Logger.log("Cleaning S3 Slaves Buckets...")
      hosts = RedBorder::Consul.get_s3_nodes_from_consul
      hosts.each do |host|
        next if RedBorder::Serf.get_cluster_leader == host[:name]
        cookie = RedBorder::Minio.get_minio_session_id host[:api_endpoint]

        body = [
          {
            "path" => "/",
            "versionID" => "",
            "recursive" => true
          }
        ].to_json

        RedBorder::HTTP.request("#{host[:api_endpoint]}/api/v1/buckets/bucket/delete-objects?all_versions=true", "POST", body, cookie)
      end
    end

    # Deletes S3 slave buckets.
    #
    # @return [void]
    def self.delete_s3_slaves_buckets
      RedBorder::Logger.log("Deleting S3 Slaves Buckets...")
      hosts = RedBorder::Consul.get_s3_nodes_from_consul
      hosts.each do |host|
        next if RedBorder::Serf.get_cluster_leader == host[:name]
        cookie = RedBorder::Minio.get_minio_session_id host[:api_endpoint]

        body = { "name" => BUCKET }.to_json

        RedBorder::HTTP.request("#{host[:api_endpoint]}/api/v1/buckets/#{BUCKET}", "DELETE", body, cookie)
      end
    end

    # Restarts Minio.
    #
    # @return [void]
    def self.restart
      RedBorder::Logger.log("Restarting Minio Service (master)")
      system("service minio restart > /dev/null 2>&1")
      system("sleep 30")
    end

    # Sets Minio replicas.
    #
    # @return [Net::HTTPResponse] The HTTP response.
    def self.set_minio_replicas
      RedBorder::Minio.restart
      RedBorder::Minio.clean_s3_replication
      RedBorder::Minio.clean_s3_slaves_buckets
      RedBorder::Minio.delete_s3_slaves_buckets
      hosts = RedBorder::Consul.get_s3_nodes_from_consul

      cookie = RedBorder::Minio.get_minio_session_id
      credentials = RedBorder::Minio.get_minio_credentials

      body = hosts.map do |host|
        {
          accessKey: credentials[:accessKey],
          secretKey: credentials[:secretKey],
          name: host[:name],
          endpoint: host[:console_endpoint]
        }
      end.to_json

      if hosts.size > MINIMUM_MINIO_HOSTS
        response = RedBorder::HTTP.request("#{LOCAL_MINIO_ENDPOINT}/api/v1/admin/site-replication", "POST", body, cookie)

        if response.respond_to?(:body) && response.body
          data = response.body

          if data['success']
            message = "Replication re-configured :)"
          else
            message = "There was an error while reconfiguring Minio Replicas :("
          end

          RedBorder::Logger.log(message)
        else
          RedBorder::Logger.log("Error: Unable to retrieve response body")
        end
      end
    end
  end
end

# Initialize Minio replication
RedBorder::MinioReplication.init_minio_replication
