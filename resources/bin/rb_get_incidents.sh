#!/bin/bash 

#######################################################################
# Copyright (c) 2025 ENEO Tecnología S.L.
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

function usage() {
  echo "Usage: $0 [-h] [-v] [-f]"
  echo "  -h  Show this help message"
  echo "  -v  Show only visible incidents"
  echo "  -f  Show only non-visible incidents"
  exit 1
}

visible=""

while getopts "hvf" opt; do
  case $opt in
    v) visible="true" ;;
    f) visible="false" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Show all incidents if neither -v nor -f is specified
if [ -z "$visible" ]; then
  echo "select created_at, uuid, name, visible from incidents;" | rb_psql redborder
  exit 0
fi

# Show only visible incidents
if [ "$visible" = "true" ]; then
  echo "select uuid, name, visible from incidents where visible=true;" | rb_psql redborder
  exit 0
fi

# Show only non-visible incidents
if [ "$visible" = "false" ]; then
  echo "select uuid, name, visible from incidents where visible=false;" | rb_psql redborder
  exit 0
fi

# Fallback help
usage
