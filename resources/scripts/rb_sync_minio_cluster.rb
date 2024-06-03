#!/usr/bin/env ruby

#######################################################################
## Copyright (c) 2024 ENEO Tecnología S.L.
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

require 'net/http'
require 'uri'
require 'json'

def is_cluster_leader
  # Leader node will have always s3
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

def get_minio_credentials
  credentials = {}
  File.foreach('/etc/default/minio') do |line|
    if line.start_with?('MINIO_ROOT_USER=')
      credentials[:accessKey] = line.split('=').last.strip
    elsif line.start_with?('MINIO_ROOT_PASSWORD=')
      credentials[:secretKey] = line.split('=').last.strip
    end
  end
  credentials
end

def get_minio_session_id
  cookie = ''
  uri = URI.parse("http://127.0.0.1:9001/api/v1/login")

  credentials = get_minio_credentials

  body = {
    accessKey: credentials[:accessKey],
    secretKey: credentials[:secretKey]
  }.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri)
  request['Content-Type'] = 'application/json'
  request.body = body

  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    cookie = response['Set-Cookie'] if response['Set-Cookie']
  end

  cookie
end

def get_s3_nodes_from_consul
  consul_uri = URI.parse('http://127.0.0.1:8500/v1/catalog/service/s3')
  response = Net::HTTP.get_response(consul_uri)

  if response.is_a?(Net::HTTPSuccess)
    s3_nodes = JSON.parse(response.body).map do |node|
      {
        name: node['Node'],
        endpoint: "http://#{node['Address']}:9000"
      }
    end
    return s3_nodes
  else
    puts "Failed to fetch S3 nodes from Consul: #{response.code} - #{response.message}"
    return []
  end
end

def set_minio_replicas
  hosts = get_s3_nodes_from_consul
  uri = URI.parse("http://127.0.0.1:9001/api/v1/admin/site-replication")

  credentials = get_minio_credentials
  cookie = get_minio_session_id

  body = hosts.map do |host|
    {
      accessKey: credentials[:accessKey],
      secretKey: credentials[:secretKey],
      name: host[:name],
      endpoint: host[:endpoint]
    }
  end.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri)
  request['Content-Type'] = 'application/json'
  request['Cookie'] = cookie unless cookie.empty?
  request.body = body
  if hosts.size > 1
    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      puts "MinIO replicas set successfully."
    else
      puts "Failed to set MinIO replicas: #{response.code} - #{response.message}"
    end
  end
end

if is_cluster_leader
  set_minio_replicas
end
