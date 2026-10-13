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

source /etc/profile.d/redborder-*
source /etc/profile.d/rvm.sh

pushd /var/www/rb-rails/ &>/dev/null

# The webui has its own ruby: the default one belongs to the platform scripts
if [[ "$GEM_HOME" != *ruby-3.4.11@web ]]; then
    rvm use ruby-3.4.11@web
fi

rake redBorder:request_trial_license

popd &>/dev/null
