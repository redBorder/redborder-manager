#######################################################################
# Copyright (c) 2026 ENEO Tecnología S.L.
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

#!/usr/bin/env bash
set -euo pipefail

# ============================
# Configuration
# ============================

DATABAGS=(
  passwords
  certs
)

ALLOWED_CLIENTS=(
  # s3-uploader
)

# ============================
# Functions
# ============================

info() {
  echo -e "\e[34m[INFO]\e[0m $1"
}

ok() {
  echo -e "\e[32m[OK]\e[0m $1"
}

warn() {
  echo -e "\e[33m[WARN]\e[0m $1"
}

# ============================
# Execution
# ============================

info "Applying security ACLs to data bags..."

for BAG in "${DATABAGS[@]}"; do
  info "Processing data bag: $BAG"

  # Correct knife syntax:
  # knife acl remove MEMBER_TYPE MEMBER_NAME OBJECT_TYPE OBJECT_NAME PERMS
  if knife acl remove group clients data "$BAG" read 2>/dev/null; then
    ok "Group 'clients' removed from READ access on data bag '$BAG'"
  else
    warn "Group 'clients' already had no READ access on '$BAG'"
  fi

  for CLIENT in "${ALLOWED_CLIENTS[@]}"; do
    if knife acl add client "$CLIENT" data "$BAG" read 2>/dev/null; then
      ok "Client '$CLIENT' granted READ access on '$BAG'"
    else
      warn "Client '$CLIENT' already has READ access on '$BAG'"
    fi
  done
done

ok "ACLs successfully applied."
