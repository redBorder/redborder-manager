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

source /etc/profile

RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
set_color() {
    if [ "x$BOOTUP" != "xnone" ]; then
        green="echo -en \\033[1;32m"
        red="echo -en \\033[1;31m"
        yellow="echo -en \\033[1;33m"
        orange="echo -en \\033[0;33m"
        blue="echo -en \\033[1;34m"
        black="echo -en \\033[1;30m"
        white="echo -en \\033[255m"
        cyan="echo -en \\033[0;36m"
        purple="echo -en \\033[0;35m"
        browm="echo -en \\033[0;33m"
        gray="echo -en \\033[0;37m"
        norm="echo -en \\033[1;0m"
        eval \$$1
    fi
}
e_ok() {
        $MOVE_TO_COL
        echo -n "["
        set_color green
        echo -n $"  OK  "
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 0
}

e_fail() {
        $MOVE_TO_COL
        echo -n "["
        set_color red
        echo -n $"FAILED"
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 1
}
function print_result(){
    if [ "x$1" == "x0" ]; then
        e_ok
    else
        e_fail
    fi
}

SCRIPTNAME=$(basename $0)
RESULT=""

function usage() {
    echo "Usage: $SCRIPTNAME <OPTIONS>"
    echo "Madatory parameters:"
    echo " -d <DOMAIN> (mandatory)"
    echo "Optional parameters:"
    echo " -c <CLUSTER>"
    echo " -i <PUBLIC_IP_HOST>"
    echo " -p <PRIVATE_IP_HOST>"
    echo " -n <HOST_NAME>"
    echo " -x <PRIVATE_UNIQUE_HOSTNAME>"
    echo " -y <PUBLIC_UNIQUE_HOSTNAME"
    echo "Only in AWS:"
    echo " -v <VPC_ID> : "
    echo " -r <REGION>"
    echo " -a <PUBLIC_HOSTED_ZONE_ID>"
    echo " -b <PRIVATE_HOSTED_ZONE_ID>"
}

function examples() {
    echo
    echo "Examples: "
    echo "-> $SCRIPTNAME -n rbhost -i 10.10.10.10 -d redbordercloud.com"
    echo "      will create rbhost.redbordercloud.com"
    echo "-> $SCRIPTNAME -n rbhost -i 10.10.10.10 -d redbordercloud.com -c cluster01"
    echo "      will create rbhost.cluster01.redbordercloud.com"
}
#This function looks for a HostedZone with a name and with a type (public or private) and
#returns its id.
function getHostedZoneId() {
    DOMAIN_TO_SEARCH=$1
    TYPE_TO_SEARCH=$2
    if [ "x$DOMAIN_TO_SEARCH" = "x" ] ; then
        echo "Error in function getHostedZoneId(), Domain to search required"
        exit 1
    elif [ "x$TYPE_TO_SEARCH" != "xprivate" -a "x$TYPE_TO_SEARCH" != "xpublic" ] ; then
        echo "getHostedZoneId: Type to search not found, setting to public"
        TYPE_TO_SEARCH="public"
    fi
    if [ "$TYPE_TO_SEARCH" = "public" ] ; then
        TYPE_IS_PRIVATE="false"
    else 
        TYPE_IS_PRIVATE="true"
    fi
    HOSTED_ZONE_LIST=$(aws route53 list-hosted-zones)
    COUNTER=0
    EXIT=0
    RESULT=""
    SEARCHNAME="0"
    while [ "x$SEARCHNAME" != "xnull" -a "x$SEARCHNAME" != "x" -a $EXIT -eq 0 ] ; do
        SEARCHNAME=$(echo $HOSTED_ZONE_LIST | jq -r .HostedZones[$COUNTER].Name)
        SEARCHTYPE=$(echo $HOSTED_ZONE_LIST | jq -r .HostedZones[$COUNTER].Config.PrivateZone)
        if [ "$DOMAIN_TO_SEARCH." = "$SEARCHNAME" ] ; then
            if [ "$TYPE_IS_PRIVATE" = "$SEARCHTYPE" ] ; then
                RESULT=$(echo $HOSTED_ZONE_LIST | jq -r .HostedZones[$COUNTER].Id)
                EXIT=1
            fi
        fi
        let COUNTER=COUNTER+1
        if [ $COUNTER -eq 10000 ] ; then
            echo "Infinite loop detected"
            exit 1
        fi
    done    
}
function setNameServers() {
    DOMAIN_FIRST_LEVEL=$(echo $DOMAIN | sed -r 's/.*\.([^.]+\.[^.]+)$/\1/')
    NAMESERVERS_HOSTED_ZONE=$(aws route53 get-hosted-zone --id $HOSTED_ZONE_ID)
    getHostedZoneId $DOMAIN_FIRST_LEVEL public
    DOMAIN_HOSTED_ZONE_ID=$RESULT
    if [ "x$DOMAIN_HOSTED_ZONE_ID" != "x" -a "x$DOMAIN_HOSTED_ZONE_ID" != "xnull" ] ; then
        NAMESERVERS_UPSERT=$(aws route53 change-resource-record-sets --hosted-zone-id $DOMAIN_HOSTED_ZONE_ID --change-batch \
        "{ \"Changes\": [                                                                                       \
            {                                                                                                   \
                \"Action\":\"UPSERT\",                                                                          \
                \"ResourceRecordSet\": {                                                                        \
                    \"Name\":\"$CLUSTER_NAME$DOMAIN\",                                                          \
                    \"Type\":\"NS\",                                                                            \
                    \"TTL\":300,                                                                                \
                    \"ResourceRecords\" : [                                                                     \
                        {\"Value\":\"$(echo $NAMESERVERS_HOSTED_ZONE | jq -r .DelegationSet.NameServers[0])\"}, \
                        {\"Value\":\"$(echo $NAMESERVERS_HOSTED_ZONE | jq -r .DelegationSet.NameServers[1])\"}, \
                        {\"Value\":\"$(echo $NAMESERVERS_HOSTED_ZONE | jq -r .DelegationSet.NameServers[2])\"}, \
                        {\"Value\":\"$(echo $NAMESERVERS_HOSTED_ZONE | jq -r .DelegationSet.NameServers[3])\"}  \
                    ]                                                                                           \
                }                                                                                               \
            }                                                                                                   \
        ] }")
        NAMESERVERS_UPSERT_ID=$(echo $NAMESERVERS_UPSERT | jq -r .ChangeInfo.Id)
    else
        NAMESERVERS_UPSERT_ID=""
    fi
}

function existsRecordSet() {
    RECORD_SET_LISTS=$(aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID )
    COUNTER=0
    EXIT=0
    RESULT=1
    SEARCHNAME="0"
    while [ "x$SEARCHNAME" != "xnull" -a "x$SEARCHNAME" != "x" -a $EXIT -eq 0 ] ; do
        SEARCHNAME=$(echo $RECORD_SET_LISTS | jq -r .ResourceRecordSets[$COUNTER].Name)
       
        if [ "x$SEARCHNAME" = "x$RECORD_SET_HOST_NAME.$DOMAIN."  ] ; then
            EXIT=1
            RESULT=0
        fi
        let COUNTER=COUNTER+1
        if [ $COUNTER -eq 10000 ] ; then
            echo "Infinite loop detected, exiting..."
            exit 1
        fi
    done
    return $RESULT
}

#Deletes a record set (type A) from a HostedZone. Parameters:
# $1 Hosted zone id
# $2 Hostname to delete
function deleteRecordSet() {
  HOSTED_ZONE=$1
  
  echo -n "Deleting $HOST_NAME.$CLUSTER_NAME$DOMAIN from $HOSTED_ZONE_TYPE hosted zone"

  LIST=$(aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE)
  COUNTER=0
  EXIT=0
  TYPE=$(echo $LIST | jq -r .ResourceRecordSets[$COUNTER].Type)
  while [ "x$TYPE" != "x" -a "x$TYPE" != "xnull" -a $EXIT -eq 0 ] ; do
    #getting record sets
    if [ "x$TYPE" = "xA" ] ; then
      NAME=$(echo $LIST | jq -r .ResourceRecordSets[$COUNTER].Name)
      TTL=$(echo $LIST | jq -r .ResourceRecordSets[$COUNTER].TTL)
      #deleting record sets
      
      if [ "x$TTL" != "x" -a "x$TTL" != "xnull" -a "x$HOST_NAME.$DOMAIN." = "x$NAME" ] ; then
        TTL=$(echo $LIST | jq -r .ResourceRecordSets[$COUNTER].TTL)
        IP_HOST=$(echo $LIST | jq -r .ResourceRecordSets[$COUNTER].ResourceRecords[0].Value)
        DELETE_RESULT=$(aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE --change-batch     \
            "{ \"Changes\": [                                                                    \
                {                                                                                \
                    \"Action\":\"DELETE\",                                                       \
                    \"ResourceRecordSet\": {                                                     \
                        \"Name\": \"$NAME\",                                                     \
                        \"Type\": \"$TYPE\",                                                     \
                        \"TTL\": $TTL,                                                           \
                        \"ResourceRecords\": [                                                   \
                            {                                                                    \
                                \"Value\" : \"$IP_HOST\"                                         \
                            }                                                                    \
                        ]                                                                        \
                    }                                                                            \
                }                                                                                \
            ] }")
        if [ $? -eq 0 ] ; then
            print_result 0
        else
            print_result 1
            echo $DELETE_RESULT
        fi
        EXIT=1
      fi
    fi
    let COUNTER=COUNTER+1
    TYPE=$(echo $LIST | jq -r .ResourceRecordSets[$COUNTER].Type)
  done
  if [ $EXIT -eq 0 ] ; then
    echo
    echo "Entry $HOST_NAME$DOMAIN not found"
  fi

}

function createRecordSet() {
    #CREATING RECORDSET
    echo -n "Creating $RECORD_SET_HOST_NAME$CLUSTER_NAME$DOMAIN"

    #If hosted zone is a private hosted zone, ip host must be private ip
    if [ "x$HOSTED_ZONE_TYPE" = "xprivate" ] ; then
        IP_HOST=$PRIVATE_IP_HOST
    else #If hosted zone is a public hosted, zone, ip host could be public or private ip
        #If exists a private hosted zone, ip host must be public ip
        if [ "x$VPC_ID" != "x" -a "x$REGION" != "x" ] || [ "x$PRIVATE_HOSTED_ZONE_ID" != "x" ] ; then                
            IP_HOST=$PUBLIC_IP_HOST
        #If doesn't exist a private hosted zone but there are a private ip host defined, ip host must be
        # private ip
        elif [ "x$PRIVATE_IP_HOST" != "x" ] ; then 
            IP_HOST=$PRIVATE_IP_HOST
        #If doesn't exists a private hosted zone and there isn't a private ip host, ip host must be public ip
        elif [ "x$PUBLIC_IP_HOST" != "x" ] ; then
            IP_HOST=$PUBLIC_IP_HOST
        fi
    fi
    #Querying to aws...
    RECORD_SETS_DATA=$(aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch  \
        "{ \"Changes\": [                                                                                       \
            {                                                                                                   \
                \"Action\":\"UPSERT\",                                                                          \
                \"ResourceRecordSet\": {                                                                        \
                    \"Name\": \"$RECORD_SET_HOST_NAME$CLUSTER_NAME$DOMAIN\",                                    \
                    \"Type\": \"A\",                                                                            \
                    \"TTL\": 300,                                                                               \
                    \"ResourceRecords\": [                                                                      \
                        {                                                                                       \
                            \"Value\" : \"$IP_HOST\"                                                            \
                        }                                                                                       \
                    ]                                                                                           \
                }                                                                                               \
            }                                                                                                   \
        ] }" )
    #Checking if response is OK
    CHANGE_INFO_ID=$(echo $RECORD_SETS_DATA | jq -r .ChangeInfo.Id)
    if [ "x" = "x$CHANGE_INFO_ID" ] ; then
        print_result 1
        echo "Error creating record set for this host"
        echo $RECORD_SETS_DATA
        exit 1
    else 
        print_result 0
    fi    
}

function createHostedZone() {
    echo -n "$HOSTED_ZONE_TYPE HostedZone $CLUSTER_NAME$DOMAIN doesn't exists, creating"
    if [ "$HOSTED_ZONE_TYPE" = "public" ] ; then
        HOSTED_ZONE_DATA=$(aws route53 create-hosted-zone --name $DOMAIN --caller-reference "public$HOST_NAME" )
    else 
        HOSTED_ZONE_DATA=$(aws route53 create-hosted-zone --name $DOMAIN --caller-reference "private$HOST_NAME" --vpc VPCRegion=$REGION,VPCId=$VPC_ID )
    fi
    HOSTED_ZONE_ID=$(echo $HOSTED_ZONE_DATA | jq -r .HostedZone.Id)
    if [ "x" = "x$HOSTED_ZONE_ID" ]; then
        print_result 1
        echo "Error creating a new $HOSTED_ZONE_TYPE hosted zone $CLUSTER_NAME$DOMAIN"
        echo $HOSTED_ZONE_DATA
        exit 1
    else
        print_result 0
    fi
}

# Hosted zone management. Parameters: 
# $1 HOSTED_ZONE_TYPE (Public or private)
# $2 HOSTED_ZONE_ID   (optional)
function configureHostedZone() {    
    HOSTED_ZONE_TYPE=$1
    HOSTED_ZONE_ID=$2
    #Checking if hosted zone type value is valid (public or private)
    if [ "x$HOSTED_ZONE_TYPE" != "xpublic" -a "x$HOSTED_ZONE_TYPE" != "xprivate" ] ; then
        echo "configureHostedZone: Invalid Hosted Zone type"
    else
        
        #If not hosted zone id provided, search it by hosted zone name 
        if [ "x$HOSTED_ZONE_ID" = "x" ] ; then
            getHostedZoneId $CLUSTER_NAME$DOMAIN $HOSTED_ZONE_TYPE
            HOSTED_ZONE_ID=$RESULT
        fi
        
        #If not hosted zone id provided or not found, create one.
        if [ "xnull" == "x$HOSTED_ZONE_ID" -o "x" == "x$HOSTED_ZONE_ID" ] ; then
            createHostedZone
        else #If hosted zone id provided or found, ok
            echo -n "$HOSTED_ZONE_TYPE HostedZone already exists ($HOSTED_ZONE_ID)"
            print_result 0
        fi

        #Checking if hosted zone id is valid
        if [ "xnull" = "x$HOSTED_ZONE_ID" -o "x" = "x$HOSTED_ZONE_ID" ]; then
            print_result 1
            echo "Error obtaining HostedZone ID"
            echo $HOSTED_ZONE_LIST
            exit 1
        fi
        
        #If hosted zone is public, create NS entries in second level domain
        if [ "x$HOSTED_ZONE_TYPE" = "xpublic" ] ; then
            echo -n "Creating NS entry for $HOSTED_ZONE_TYPE HostedZone"
            setNameServers
            #Checking if NS entry have been created sucessfully
            if [ "x$NAMESERVERS_UPSERT_ID" = "x" -o "x$NAMESERVERS_UPSERT_ID" = "xnull" ] ; then
                print_result 1
                echo "NS entry not created, maybe domain is not registered in AWS Route 53"
                echo $NAMESERVERS_UPSERT
            else
                print_result 0
            fi
        fi

        #Create record set
        RECORD_SET_HOST_NAME=$HOST_NAME
        createRecordSet

        #Create optional record sets (-x option)
        if [ "x$HOSTED_ZONE_TYPE" = "xprivate" -a "x$PRIVATE_UNIQUE_HOSTNAME" != "x" ] ; then
            for RECORD_SET_HOST_NAME in $(echo $PRIVATE_UNIQUE_HOSTNAME | tr ',' ' '); do
                existsRecordSet
                if [ $? -eq 0 ] ; then
                    echo "Name $RECORD_SET_HOST_NAME.$DOMAIN already registered, skipping..."
                else
                    RECORD_SET_HOST_NAME="$RECORD_SET_HOST_NAME."
                    createRecordSet
                fi
            done
        fi

        if [ "x$HOSTED_ZONE_TYPE" = "xpublic" -a "x$PUBLIC_UNIQUE_HOSTNAME" != "x" ] ; then
            for RECORD_SET_HOST_NAME in $(echo $PRIVATE_UNIQUE_HOSTNAME | tr ',' ' '); do
                existsRecordSet
                if [ $? -eq 0 ] ; then
                    echo "Name $RECORD_SET_HOST_NAME$DOMAIN already registered, skipping..."
                else
                    RECORD_SET_HOST_NAME="$RECORD_SET_HOST_NAME."
                    createRecordSet
                fi
            done
        fi
        
    fi
}

#
# MAIN EXECUTION
#

DELETE=0
PRIVATE_IP_SPECIFIED=0 #Indicates if there is a parameter that specifies a private ip.
PUBLIC_IP_SPECIFIED=0  #Indicates if there is a parameter that specifies a public ip

#PARSING PARAMETERS
while getopts "hc:n:d:i:p:v:r:a:b:ex:y:" opt ; do
    case $opt in
        h) usage; examples; HELP="YES";;
    	c) CLUSTER_NAME=$OPTARG.;;
    	n) HOST_NAME=$OPTARG;;
        x) PRIVATE_UNIQUE_HOSTNAME=$OPTARG;;
        y) PUBLIC_UNIQUE_HOSTNAME=$OPTARG;;
    	i) PUBLIC_IP_HOST=$OPTARG && PUBLIC_IP_SPECIFIED=1;;
        p) PRIVATE_IP_HOST=$OPTARG && PRIVATE_IP_SPECIFIED=1;;
    	d) DOMAIN=$OPTARG;;
        v) VPC_ID=$OPTARG;;
        r) REGION=$OPTARG;;
        a) PUBLIC_HOSTED_ZONE_ID=$OPTARG;;
        b) PRIVATE_HOSTED_ZONE_ID=$OPTARG;;
        e) DELETE=1
    esac
done


 
if [ "x$HELP" != "xYES" ] ; then #If -h is specified, don't execute anything

    #Obtaining hostname if it is not set
    [ "x$HOST_NAME" == "x" ] && HOST_NAME=$(hostname -s)

    #If delete option is not set
    if [ $DELETE -eq 0 ] ; then 

        #Obtaining Host IPs (Amazon EC2 instances). If -i and -p options aren't used, both ips are obtained.
        #If only one is option is setted, only obtain for this option (if it is necessary).
        if [ "x$PUBLIC_IP_HOST" == "x" -a $PRIVATE_IP_SPECIFIED -eq 0 ]; then
            if [ -d /sys/class/net/bond0 ]; then
                PUBLIC_IP_HOST=$(curl -sS http://169.254.169.254/latest/meta-data/public-ipv4)
            fi
        fi
        if [ "x$PRIVATE_IP_HOST" == "x" -a $PUBLIC_IP_SPECIFIED -eq 0 ]; then
            if [ -d /sys/class/net/bond0 ]; then
                PRIVATE_IP_HOST=$(ip a s bond0 2>/dev/null |grep inet|grep brd|awk '{print $2}'|head -n 1|tr '/' ' '|awk '{print $1}')
            fi
        fi

        if [ "x" != "x$DOMAIN" -a "x" != "x$HOST_NAME" -a "x$HELP" != "xYES" ] ; then
            
            #If hostname doesn't finish with . we will add it.
            echo $HOST_NAME | grep -q "\.$" 
        	[ $? -ne 0 ] && HOST_NAME="${HOST_NAME}."

            if [ "x$PUBLIC_IP_HOST" != "x" ] ; then
                HOSTED_ZONE_ID=""
                configureHostedZone public $PUBLIC_HOSTED_ZONE_ID
            fi
            if [ "x$PRIVATE_IP_HOST" != "x" ] ; then
                if [ "x$REGION" != "x" -a "x$VPC_ID" != "x" ] || [ "x$PRIVATE_HOSTED_ZONE_ID" != "x" ] || [ $PRIVATE_IP_SPECIFIED -eq 1 ] ; then
                    HOSTED_ZONE_ID=""
                    configureHostedZone private $PRIVATE_HOSTED_ZONE_ID
                fi
            fi
        else 
            echo "You must specify the Domain"
            usage
        fi
    
    #If delete option is set...
    else
        #Locate public hostedzone
        HOSTED_ZONE_TYPE=public
        getHostedZoneId $CLUSTER_NAME$DOMAIN $HOSTED_ZONE_TYPE
        HOSTED_ZONE_ID=$RESULT
        #Delete record set (type A) for this hostname and cdomain
        deleteRecordSet $HOSTED_ZONE_ID

        #Locate private hostedzone
        HOSTED_ZONE_TYPE=private
        getHostedZoneId $CLUSTER_NAME$DOMAIN $HOSTED_ZONE_TYPE
        HOSTED_ZONE_ID=$RESULT
        #Delete record set (type A) for this hostname and cdomain
        deleteRecordSet $HOSTED_ZONE_ID
    fi
fi
