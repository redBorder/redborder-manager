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

knifefile=${KNIFEFILE-/root/.chef/knife.rb}
webuifile=${WEBUIFILE-/etc/chef-server/chef-webui.pem}
rootpemfile=${ROOTPEMFILE-/root/.chef/admin.pem}
webuifile="/etc/chef-server/chef-webui.pem"
KNIFE="/usr/bin/knife"
RET=0

. /etc/init.d/functions
source /etc/profile

if [ -f $knifefile -a -f ${CERT} ]; then
    if [ "x$*" != "x" ]; then
        for n in $*; do
            npath="/var/opt/chef-server/nginx/ca/${n}.crt"
            if [ -f /var/opt/chef-server/nginx/ca/${n}.crt ]; then
                upload_pem "http_${n}" "/var/opt/chef-server/nginx/ca/${n}.crt"
                [ $? -ne 0 ] && RET=1
            fi
        done
    else
        echo "Checking certificates: "
        echo -n " * chef web interface certificate: "
        $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^chef_webui_pem$"
        if [ $? -ne 0 ]; then
            echo
            echo -n "      "
            upload_pem "chef_webui" "${webuifile}"
            [ $? -ne 0 ] && RET=1
        else
            echo_success
            echo
        fi
        echo -n " * redBorder web interface certificate: "
        $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^rb_chef_webui_pem$"
        if [ $? -ne 0 ]; then
            echo
            echo -n "      "
            upload_pem "rb_chef_webui" "/var/www/rb-rails/config/rb-chef-webui.pem"
            [ $? -ne 0 ] && RET=1
        else
            echo_success
            echo
        fi
        echo -n " * knife root certificate: "
        $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^root_pem$"
        if [ $? -ne 0 ]; then
            echo
            echo -n "      "
            upload_pem "root" "${rootpemfile}"
            [ $? -ne 0 ] && RET=1
        else
            echo_success
            echo
        fi
        echo -n " * validation certificate: "
        $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^validation_pem$"
        if [ $? -ne 0 ]; then
            echo
            echo -n "      "
            upload_pem "validation" "/etc/chef/validation.pem"
            [ $? -ne 0 ] && RET=1
        else
            echo_success
            echo
        fi
        echo -n " * sensor's certificate: "
        $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^rsa_pem$"
        if [ $? -ne 0 ]; then
            echo
            echo -n "      "
            upload_pem "rsa" "/var/www/rb-rails/config/rsa"
            [ $? -ne 0 ] && RET=1
        else
            echo_success
            echo
        fi
        echo -n " * http private key: "
        $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^http_private_pem$"
        if [ $? -ne 0 ]; then
            echo
            echo -n "      "
            upload_pem "http_private" "/var/opt/chef-server/nginx/ca/localhost.key"
            [ $? -ne 0 ] && RET=1
        else
            echo_success
            echo
        fi

        for npath in $(ls /var/opt/chef-server/nginx/ca/*.crt); do
            n=$(basename $npath | sed 's/\.crt$//')
            if [ -f /var/opt/chef-server/nginx/ca/${n}.crt ]; then
                echo -n " * http $n certificate: "
                $KNIFE data bag show certs --key ${CERT} -u ${CERTUSER} -c /root/.chef/knife.rb | sed 's/ //g' | grep -q "^http_${n}_pem$"
                if [ $? -ne 0 ]; then
                    echo
                    echo -n "      "
                    upload_pem "http_${n}" "/var/opt/chef-server/nginx/ca/${n}.crt"
                    [ $? -ne 0 ] && RET=1
                else
                    echo_success
                    echo
                fi
            fi
        done
    fi
fi

exit $RET
