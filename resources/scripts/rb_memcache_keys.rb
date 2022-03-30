#!/usr/bin/env ruby
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

# List all keys stored in memcache.
# Credit to Graham King at http://www.darkcoding.net/software/memcached-list-all-keys/ for the original article on how to get the data from memcache in the first place.
# Adapted by Pablo Nebrera (pablonebrera@eneotecnologia.com)

require 'net/telnet'
require 'yaml'
require "getopt/std"
require 'colorize'

opt = Getopt::Std.getopts("k:s:a")

keys=nil
if opt["k"]
  if opt["k"].class==Array
    keys=[]
    opt["k"].each do |k|
      k.split(",").each do |k2|
        keys<<k2
      end
    end
  elsif opt["k"].respond_to?"split"
    keys=opt["k"].split(",") if opt["k"]
  end
end

memcachservers=nil
if opt["s"]
  if opt["s"].class==Array
    memcachservers=[]
    opt["s"].each do |k|
      memcachservers<<k
    end
  elsif opt["s"].respond_to?"split"
    memcachservers=opt["s"].split(",") if opt["s"]
  end
elsif opt["a"]
  config = YAML.load_file('/var/www/rb-rails/config/memcached_config.yml')
  memcachservers=config["production"]["servers"]
else
  config = YAML.load_file('/var/www/rb-rails/config/memcached_config.yml')
  memcachservers=[config["production"]["servers"].sample]
end

headings = %w(id expires bytes cache_key)

memcachservers.each_with_index do |memhost, index1|
  rows = []
  memhost_ip=memhost.split(':')[0]
  memhost_port=memhost.split(':')[1]
  memhost_port="11211" if memhost_port.nil?

  if index1!=0
    puts ""
    puts "#####################################################################################################################".colorize(:red)
    puts ""
  end
  printf "Contacting #{memhost_ip}:#{memhost_port} ...\n"
  begin
    host = Net::Telnet::new("Host" => memhost_ip, "Port" => memhost_port.to_i, "Timeout" => 5)

    if !keys.nil? and !keys.empty?
      keys.each do |key|
        content = (host.cmd("String" => "get #{key}", "Match" => /^END/) {|c| c}).gsub(/^END$/, "").gsub(/^VALUE /, "").gsub(/^\n$/, "")
        rows << {:cache_key => key, :content => content}
      end
      rows.each_with_index do |row, index2|
        puts "---------------------------------------------------------------------------------------------------------------------".colorize(:light_blue) if index2==0
        puts "Cache Key: #{row[:cache_key]}".colorize(:blue)
        puts "---------------------------------------------------------------------------------------------------------------------".colorize(:light_blue)
        puts "#{row[:content]}"
        puts "---------------------------------------------------------------------------------------------------------------------".colorize(:light_blue)
      end
    else
      matches   = host.cmd("String" => "stats items", "Match" => /^END/).scan(/STAT items:(\d+):number (\d+)/)
      slabs = matches.inject([]) { |items, item| items << Hash[*['id','items'].zip(item).flatten]; items }

      longest_key_len = 0

      slabs.each do |slab|
        begin
          host.cmd("String" => "stats cachedump #{slab['id']} #{slab['items']}", "Match" => /^END/) do |c|
            matches = c.scan(/^ITEM (.+?) \[(\d+) b; (\d+) s\]$/).each do |key_data|
              cache_key, bytes, expires_time = key_data
              rows << [slab['id'], Time.at(expires_time.to_i), bytes, cache_key]
              longest_key_len = [longest_key_len,cache_key.length].max
            end
          end
        rescue
        end
      end

      row_format = %Q(|%8s | %28s | %12s | %-#{longest_key_len}s | )
      puts row_format%headings
      rows.each{|row| puts row_format%row}
    end
  rescue

  ensure
    host.close unless host.nil?
  end
end
