#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2026 ENEO Tecnología S.L.
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

require 'optparse'
require 'json'
require 'logger'
require 'net/http'

logger = Logger.new($stdout)
logger.level = Logger::DEBUG
logger.formatter = proc do |severity, _datetime, _progname, msg|
  "#{severity}: #{msg}\n"
end

# Define default options
options = { redirect: false, status: 200, timeout: 5, headers: {} }

OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [-i IP_ADDRESS] [-p PORT] [-t TYPE] [-b BODY] [-h HEADERS] [-status STATUS]"
  opts.on('-u URL', '--url URL', 'URL to connect to and retrieve data') { |v| options[:url] = v }
  opts.on('-X TYPE', '--type TYPE', 'Request method type: GET, POST, PUT or HEAD') { |v| options[:type] = v.upcase }
  opts.on('-d BODY', '--body BODY', 'Request body') { |v| options[:body] = v }
  opts.on('-H HEADERS', '--headers HEADERS', 'Custom request headers (JSON)') do |v|
    options[:headers] = JSON.parse(v)
  rescue JSON::ParserError
    logger.error("Invalid JSON for headers: #{v}")
    exit 1
  end
  opts.on('-s STATUS', '--status STATUS', Integer, 'Expected HTTP response status') { |v| options[:status] = v }

  opts.on('-L', '--redirect', 'Follow HTTP redirects') { options[:redirect] = true }
  opts.on('-x PROXY', '--proxy PROXY', 'HTTP Proxy URL using format [protocol://][username[:password]@]proxy.example.com[:port]') { |v| options[:proxy] = v }

  opts.on('-a AUTH', '--http-auth AUTH', 'HTTP server authentication method') { |v| options[:http_auth] = v }
  opts.on('-U USER', '--user USER', 'HTTP server authentication user') { |v| options[:http_user] = v }
  opts.on('-P PASS', '--password PASS', 'HTTP server authentication password') { |v| options[:http_pass] = v }

  opts.on('--ssl-verify-peer', 'Verify SSL peer') { options[:ssl_peer] = true }
  opts.on('--ssl-ca-file FILE', 'Path to CA certificate file for SSL verification') { |v| options[:ssl_ca_file] = v }
  opts.on('--ssl-cert CERT', 'Path to SSL certificate') { |v| options[:ssl_cert] = v }
  opts.on('--ssl-key KEY', 'Path to SSL private key') { |v| options[:ssl_key] = v }
  opts.on('--ssl-key-pass PASS', 'Password for SSL private key') { |v| options[:ssl_key_pass] = v }

  opts.on('--timeout TIMEOUT', Integer, 'Request timeout in seconds') { |v| options[:timeout] = v if v > 0 }
  opts.on('-h', '--help', 'Show this help') { puts opts; exit }
end.parse!

unless options[:url] && options[:type]
  logger.error('Must specify --url URL and --type TYPE')
  exit 1
end

if (options[:ssl_cert] && !options[:ssl_key]) || (!options[:ssl_cert] && options[:ssl_key])
  logger.error('Both --ssl-cert and --ssl-key must be provided together')
  exit 1
end

begin
  uri = URI(options[:url])
  http = if options[:proxy]
           proxy_uri = URI(options[:proxy])
           proxy_user = proxy_uri.user
           proxy_pass = proxy_uri.password
           Net::HTTP.new(uri.host, uri.port, proxy_uri.host, proxy_uri.port, proxy_user, proxy_pass)
         else
           Net::HTTP.new(uri.host, uri.port)
         end

  http.use_ssl = (uri.scheme == 'https')

  if http.use_ssl?
    if options[:ssl_peer]
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      cert_store = OpenSSL::X509::Store.new
      cert_store.set_default_paths
      cert_store.add_file(options[:ssl_ca_file]) if options[:ssl_ca_file]

      http.cert_store = cert_store
    else
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
  end

  if options[:ssl_cert] && options[:ssl_key]
    http.cert = OpenSSL::X509::Certificate.new(File.read(options[:ssl_cert]))
    http.key = OpenSSL::PKey::RSA.new(File.read(options[:ssl_key]), options[:ssl_key_pass])
  elsif options[:ssl_cert] || options[:ssl_key]
    logger.error('Both -ssl-cert and -ssl-key must be specified together')
    exit 1
  end
  http.open_timeout = options[:timeout] if options[:timeout]
  http.read_timeout = options[:timeout] if options[:timeout]

  request_class = case options[:type].upcase
                  when 'GET' then Net::HTTP::Get
                  when 'POST' then Net::HTTP::Post
                  when 'PUT' then Net::HTTP::Put
                  when 'HEAD' then Net::HTTP::Head
                  else
                    logger.error("Unsupported request type: #{options[:type]}")
                    exit 1
                  end

  request = request_class.new(uri)
  options[:headers]&.each { |k, v| request[k] = v }
  request.body = options[:body] if options[:body]

  if options[:http_auth]
    case options[:http_auth]&.downcase
    when 'basic'
      request.basic_auth(options[:http_user], options[:http_pass])
    # TODO: Implement other authentication methods if needed
    # when 'digest'
    # when 'ntlm'
    # when 'kerberos'
    else
      logger.error("Unsupported HTTP authentication method: #{options[:http_auth]}")
      exit 1
    end
  end

  response = http.request(request)

  if options[:redirect]
    while response.is_a?(Net::HTTPRedirection)
      uri = URI(response['location'])
      request = request_class.new(uri)
      response = http.request(request)
    end
  end

  if response
    result = {
      status: response.code.to_i,
      message: response.message,
      headers: response.each_header.to_h,
      body: response.body
    }

    puts JSON.pretty_generate(result)
  end

  if response.code.to_i == options[:status]
    logger.info("Request successful with expected status #{options[:status]}")
    exit 0
  else
    logger.error("Unexpected response status: #{response.code}")
    exit 1
  end
rescue => e
  logger.error("Request failed: #{e.message}")
  exit 1
end
