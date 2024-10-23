#!/bin/bash -

#######################################################################
# Copyright (c) 2024 ENEO Tecnologia S.L.
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

if [ ! -d /var/www/rb-rails ]; then
    echo 'ERROR: rb-rails not found!'
    exit 1
fi

source /etc/profile

pushd /var/www/rb-rails &>/dev/nul

rvm gemset use web &>/dev/null

RAILS_ENV=production rails console

exit 0
