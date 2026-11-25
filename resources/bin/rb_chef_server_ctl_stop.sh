#!/bin/bash

#######################################################################
# Copyright (c) 2014 ENEO Tecnología S.L.
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

if [ -f /opt/cinc-project/bin/cinc-server-ctl ]; then
  # cinc-server-ctl runs on the ruby embedded in cinc-server: without the gems
  # of the rvm ruby, which are not compatible with it
  unset GEM_HOME GEM_PATH GEM_ROOT RUBYOPT RUBYLIB BUNDLE_GEMFILE

  echo "Calling cinc-server-ctl graceful-kill.."
  /opt/cinc-project/bin/cinc-server-ctl graceful-kill
  
  echo "Calling cinc-server-ctl stop.."
  /opt/cinc-project/bin/cinc-server-ctl stop
fi
