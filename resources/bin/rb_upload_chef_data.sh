# Author: Pablo Nebrera Herrera
# Script sube el directorio data al chef server

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

#RBDIR=${RBDIR-/opt/rb}
DATADIR="/var/chef/data"
ANSWERYES=0

source $RBLIB/rb_manager_functions.sh

function upload_data_bag(){
	X="data bag"
	key="$1"
  local files=$2

	if [ "x$key" == "x" ]; then
		DIRDB="data_bag"
	else
		DIRDB="data_bag_encrypted"
	fi

	if [ -d $DATADIR/$DIRDB ]; then
		echo -en "* Uploading \"$X"
		[ "x$key" != "x" ] && echo -n " encrypted"
		echo "\":"

    if [ "x$files" != "x" ]; then
			for n2 in `ls $files 2>/dev/null`; do
        n1=$(dirname $n2|sed 's|.*/||')
		VAR="y"
				if [ $ANSWERYES -eq 0 ]; then
					echo -n "    Would you like to upload $n1/`basename $n2` $X? (y/N) "
					read VAR
					if [ "x$VAR" == "y" -o "x$VAR" == "Y" -o "x$VAR" == "s" -o "x$VAR" == "S" ]; then
						VAR="y"
					fi
				fi
				if [ "x$VAR" == "xy" ]; then
					echo -n "    - $(echo $n2 | sed "s|/var/chef/data/||")"
					if [ "x$key" != "x" ]; then
            knife data bag -c /root/.chef/knife.rb from file $n1 $n2 --secret-file $key &>/dev/null
            RET=$?
            [ $RET -eq 0 ] && rm -f $n2
          else
            knife data bag -c /root/.chef/knife.rb from file $n1 $n2 &>/dev/null
            RET=$?
          fi
					print_result $?
				fi
			done
		else
			[ "x$(ls $DATADIR/$DIRDB 2>/dev/null)" == "x" ] && echo -n "    - no databags to upload" && print_result 0

			for n1 in `ls $DATADIR/$DIRDB 2>/dev/null`; do
				if [ -d $DATADIR/$DIRDB/$n1 ]; then
					echo -n "  > Uploading \"$n1\" data bag:"
					[ "x$key" != "x" ] && echo -n " encrypted"

					#knife data bag -c $RBDIR/root/.chef/knife.rb create $n1 &>/dev/null
					if [ "x$key" != "x" ]; then
						knife data bag -c /root/.chef/knife.rb create $n1 --secret-file $key &>/dev/null
						RET=$?
					else
						knife data bag -c /root/.chef/knife.rb create $n1 &>/dev/null
						RET=$?
					fi
					print_result $?

					for n2 in `ls $DATADIR/$DIRDB/$n1/*.json 2>/dev/null`; do
						VAR="y"
						if [ $ANSWERYES -eq 0 ]; then
							echo -n "    Would you like to upload `basename $n1`/`basename $n2` $X? (y/N) "
							read VAR
							if [ "x$VAR" == "y" -o "x$VAR" == "Y" -o "x$VAR" == "s" -o "x$VAR" == "S" ]; then
								VAR="y"
							fi
						fi
						if [ "x$VAR" == "xy" ]; then
							echo -n "    - $(echo $n2 | sed "s|${RBDIR}/var/chef/data/||")"
							if [ "x$key" != "x" ]; then
								knife data bag -c /root/.chef/knife.rb from file $n1 $n2 --secret-file $key &>/dev/null
								RET=$?
								[ $RET -eq 0 ] && rm -f $n2
							else
								knife data bag -c /root/.chef/knife.rb from file $n1 $n2 &>/dev/null
								RET=$?
							fi
					    print_result $?
						fi
					done
				fi
			done
		fi
	fi
}

function upload_x(){
	X=$1
  local files=$2
  [ "x$files" == "x" ] && files="$DATADIR/$X/*.json"

	if [ "x$X" != "x" ]; then
		echo -e "* Uploading \"$X\":"
		[ "x$(ls $DATADIR/$X 2>/dev/null)" == "x" ] && echo -n "    - nothing to upload" && print_result 0
		if [ -d $DATADIR/$X ]; then
			for n in `ls $files 2>/dev/null`; do
				if [ "x$X" == "xenvironment" -a "x`basename $n`" == "x_default.json" ]; then
					echo "    - INFO: Enviroment _default cannot be uploaded";
					continue
				fi
				VAR="y"
				if [ $ANSWERYES -eq 0 ]; then
					echo -n "  Would you like to upload `basename $n` $X? (y/N) "
					read VAR
					if [ "x$VAR" == "y" -o "x$VAR" == "Y" -o "x$VAR" == "s" -o "x$VAR" == "S" ]; then
						VAR="y"
					fi
				fi
				if [ "x$VAR" == "xy" ]; then
					echo -n "    - $(echo $n | sed "s|/var/chef/data/||")"
					knife $X -c /root/.chef/knife.rb from file $n &>/dev/null
				    	print_result $?
				fi
			done
		fi
	fi
}

function usage(){

	echo "$0 [-d][-y]"
	echo "    -d: directory where the json data is stored"
	echo "    -y: answer yes by default"
	echo "    -f: use this file to upload"
	echo "    -h: print this help"
	exit 1
}


while getopts "hd:yf:" name
do
  case $name in
    d) DATADIR=$OPTARG;;
    y) ANSWERYES=1;;
	  f) FILE=$OPTARG;;
	  h) usage;;
  esac
done

if [ "x$DIRCANDIDATE" != "x" ]; then
	if [ -d $DIRCANDIDATE ]; then
		if [ -d $DIRCANDIDATE/role -o -d $DIRCANDIDATE/client -o -d $DIRCANDIDATE/environment -o -d $DIRCANDIDATE/node ]; then
			DATADIR=$DIRCANDIDATE
		else
			echo "ERROR: $DIRCANDIDATE contains no valid data!!"
			exit 1
		fi
	else
		echo "ERROR: $DIRCANDIDATE not found!!"
		exit 1
	fi
fi

[ ! -f /root/.chef/knife.rb -a -f /root/.chef/knife.rb.default ] && cp /root/.chef/knife.rb.default /root/.chef/knife.rb

if [ "x$FILE" != "x" ]; then
	cheftype=$(dirname $FILE|sed 's|.*/||')
	if [ "x$cheftype" == "xenvironment" ]; then
		upload_x "environment" $FILE
	elif [ "x$cheftype" == "xnode" ]; then
		upload_x "node" $FILE
	elif [ "x$cheftype" == "xrole" ]; then
		upload_x "role" $FILE
  else #DataBags
		chefdatabag=$(basename $(dirname $(dirname $FILE)))
		if [ "x$chefdatabag" == "xdata_bag" ]; then
			upload_data_bag "" $FILE
		elif [ "x$chefdatabag" == "xdata_bag_encrypted" -a -f /etc/chef/encrypted_data_bag_secret ]; then
			upload_data_bag /etc/chef/encrypted_data_bag_secret $FILE
		fi
	fi
else
	echo "Uploading chef information from $DATADIR: "
	#upload_x "client"
	echo
	upload_x "environment"
	echo
	upload_x "node"
	echo
	upload_x "role"
	echo
	upload_data_bag
	[ -f /etc/chef/encrypted_data_bag_secret ] && echo && upload_data_bag /etc/chef/encrypted_data_bag_secret
fi
