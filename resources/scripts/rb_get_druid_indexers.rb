#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2025 ENEO Tecnología S.L.
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

require 'zk'
require 'yaml'
require 'json'
require "getopt/std"

opt = Getopt::Std.getopts("ht:r")

def logit(text)
  printf("%s\n", text)
end

def print_indexer(zk, zk_id)
  logit zk_id
end

if opt["h"]
  logit "rb_get_druid_indexers.rb [-h]"
  logit "    -r       -> pick one random"
  logit "    -h       -> print this help"
  exit 0
end

random=(opt["r"] ? true : false)

zk_host="zookeeper.service:2181"

zk = ZK.new(zk_host)
indexers = zk.children("/druid/indexer/announcements").map{|k| k.to_s}.sort.uniq

if random
  print_indexer zk, indexers.shuffle.first
else
  indexers.each do |b|
    print_indexer zk, b
  end
end