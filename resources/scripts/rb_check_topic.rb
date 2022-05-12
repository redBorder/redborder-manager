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
require 'getopt/std'
require_relative '/usr/lib/redborder/lib/check/check_functions.rb'
require_relative '/usr/lib/redborder/lib/check/kafka-messages/rb_check_kafka-messages_functions.rb'


opt = Getopt::Std.getopts("hqt:")

def usage()
  logit "rb_check_topic.rb [-h][-t <topic>]"
  logit "    -h         -> Show this help"
  logit "    -t         -> Topic"
  logit "Example: rb_check_topic.rb -t rb_monitor"
end

if opt["h"]
  usage
  exit 0
end

if opt["t"].nil?
  logit "ERROR: You must provide a topic."
  usage
  exit 1
else
  topic = opt["t"].to_s.strip
end

output, return_value = check_topic(topic)

puts output

exit 1 if return_value != 0
