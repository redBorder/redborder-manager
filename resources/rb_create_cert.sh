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



# Script configura y genera llave RSA para comunicar el manager con los sensores.

#RBDIR=${RBDIR-/opt/rb}

source /etc/profile
RET=0

function usage() {
  echo "$0 -n property_name [ -e property_email ] [ -c property_country ] [ -s property_state ] [ -l property_locality ] [ -o property_organization ] [ -v ]"
  exit 1
}

dirname="/var/opt/chef-server/nginx/ca"
p_country="ES"
p_state="Spain"
p_locality="Seville"
p_organization="Eneo Tecnologia S.L."
p_name="$(hostname -f)"
p_email="info@redborder.net"
verbose=0

while getopts "d:f:hn:c:s:l:o:v" name
do
  case $name in
    h) usage;;
    f) filename=$OPTARG;;
    n) p_name=$OPTARG;;
    e) p_email=$OPTARG;;
    c) p_country=$OPTARG;;
    s) p_state=$OPTARG;;
    l) p_locality=$OPTARG;;
    o) p_organization=$OPTARG;;
    v) verbose=1;;
  esac
done

[ "x$p_name" == "x" -o "x$dirname" == "x" ] && usage
[ ! -d $dirname ] && usage


if [ -f ${dirname}/${p_name}.crt ]; then
  echo "The certificate ${dirname}/${p_name}.crt already exists"
  openssl x509 -in ${dirname}/${p_name}.crt -text -noout
  echo -n "Would you like to overwrite it? (y/N) "
  read VAR
  [ "x$VAR" != "xy" -a "x$VAR" != "xY" ] && exit 1
fi

tmpfile="${dirname}/${p_name}-ssl.conf"

cat > $tmpfile <<- _RBEOF_
  [ req ]
  distinguished_name = req_distinguished_name
  prompt = no

  [ req_distinguished_name ]
  C                      = ${p_country}
  ST                     = ${p_state}
  L                      = ${p_locality}
  O                      = ${p_organization}
  OU                     = redBorder
  CN                     = ${p_name}
  emailAddress           = ${p_email}
_RBEOF_

chmod 644 $tmpfile

echo -n "Generating ${p_name}.crt"
/opt/chef-server/embedded/bin/openssl req -config $tmpfile -new -x509 -nodes -sha1 -days 3650 -key ${dirname}/localhost.key -out ${dirname}/${p_name}.crt
RET=$?
print_result $RET

[ $verbose -eq 1 ] && openssl x509 -in ${dirname}/${p_name}.crt -text -noout

exit $RET

