#!/bin/bash -e

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

source $RBBIN/rb_manager_functions.sh
source /etc/profile

logger -t "rb_aws_secondary_ip" "Creating new secondary ip for AWS"

function usage() {
	echo "USAGE:$(basename $0) [OPTIONS]"
	echo " -i <PRIVATE_IP> (secondary ip to assign. By default reservates a new IP)"
	echo " -b <INTERFACE> (index of interface that will be the IP assigned. By default is bond1"
	echo " -d (delete secondary ip)"
	echo " -h (command help)"
	echo " -g (get IPs assigned to interface)"
	echo " -a (allocate a new secondary ip)"
}

function getIps() {
    GET_IPS_RESPONSE=$(aws ec2 describe-instances --instance-ids $(hostname)  | \
        jq -r .Reservations[0].Instances[0].NetworkInterfaces) 
    COUNT=0
    IPS=""
    for m in $(echo $GET_IPS_RESPONSE | jq -r .[].MacAddress); do
        if [ "x$m" = "x$MAC" ] ; then
            IPS=$(echo $GET_IPS_RESPONSE | jq -r .[$COUNT].PrivateIpAddresses[].PrivateIpAddress | tr '\0' '\n')
        fi
        let COUNT=COUNT+1
    done
    if [ "x$IPS" = "x" ] ; then
        echo "ERROR: can't find secondary ip"
    fi
}

#Default values:
iface="bond1";
DELETE_IP="false";
HELP="0";
FORCE_IP_ASSIGN="false";
GET_IP="false";
ADD_IP="false";

while getopts "ahdgi:b:" opt ; do
    case $opt in
        h) usage; HELP="1";;
        i) PRIVATE_IP=$OPTARG;;
        b) iface=$OPTARG;;
        d) DELETE_IP="true";;
        g) GET_IP="true";;
        a) ADD_IP="true";;
    esac
done

# MAIN EXECUTION ####################

#ETH_INDEX=$(echo $iface|sed 's/^eth//'|sed 's/^bond//')

if [ $HELP = "0" ] ; then
	if [ -f /sys/class/net/$iface/address ]; then		
		MAC=$(head /sys/class/net/$iface/address)
		ENI_ID=$(curl -sS http://169.254.169.254/2014-11-05/meta-data/network/interfaces/macs/$MAC/interface-id)
		getIps
		if [ "x$GET_IP" = "xtrue" ] ; then
			if [ "x$PRIVATE_IP" = "x" ] ; then
				printf "$IPS"
				echo
			else 
				printf "$IPS" | grep $PRIVATE_IP
				echo
			fi
		elif [ "x$PRIVATE_IP" = "x" -a "x$DELETE_IP" != "xtrue" -a "x$ADD_IP" = "xtrue" ] ; then			
			echo -n "Assigning a new secondary IP address to $iface"
				#getIps
				NUM_IPS=$(printf "$IPS\n" | wc -l)				
				aws ec2 assign-private-ip-addresses --network-interface-id $ENI_ID --secondary-private-ip-address-count 1
				print_result $?				
				COUNTER=1
				NEW_NUM_IPS=$(printf "$IPS\n" | wc -l)				
				getIps				
				while [ "x$NEW_NUM_IPS" = "x$NUM_IPS" -a $COUNTER -le 10 ] ; do
					echo "Waiting for IP... ($COUNTER/10)"
					sleep 1;
					getIps
					NEW_NUM_IPS=$(printf "$IPS\n" | wc -l)					
					let COUNTER=COUNTER+1
				done				
				SECONDARY_IP=$(printf "$IPS\n" | tail -n 1)
				echo "IP: $SECONDARY_IP"
		elif [ "x$PRIVATE_IP" = "x" -a "x$DELETE_IP" = "xtrue" ] ; then
			echo "Private IP must be specified"
		elif [ "x$PRIVATE_IP" != "x" -a "x$DELETE_IP" = "xtrue" ] ; then
			echo -n "Deleting secondary IP $PRIVATE_IP"
			aws ec2 unassign-private-ip-addresses --network-interface-id $ENI_ID --private-ip-addresses $PRIVATE_IP
			print_result $?
		elif [ "x$PRIVATE_IP" != "x" -a "x$DELETE_IP" != "xtrue" ] ; then			
			echo -n "Assigning secondary IP address ($PRIVATE_IP) to $iface"
			aws ec2 assign-private-ip-addresses --network-interface-id $ENI_ID --private-ip-addresses $PRIVATE_IP --allow-reassignment
			print_result $?
		else
			usage
		fi		
	else
		echo "Network interface $iface not found, exiting..."
	fi
fi
