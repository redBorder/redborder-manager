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
require_relative '/usr/lib/redborder/lib/check_functions.rb'
require_relative 'rb_check_commons_functions.rb'


opt = Getopt::Std.getopts("hc")

def usage
  logit "rb_check_licenses.rb [-h][-c]"
  logit "    -h         -> Show this help"
  logit "    -c         -> Colorless mode (optional)"
  logit "Example: rb_check_licenses.rb"
end

if opt["h"]
  usage
  exit 0
end

if opt["c"]
  colorless = true
else
  colorless = false
end

check_license(colorless)