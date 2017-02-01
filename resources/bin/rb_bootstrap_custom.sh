#!/bin/bash

echo "INFO: execute rb_bootstrap_common.sh"
rb_bootstrap_common.sh
#Wait for tag leader=ready
counter=1
serf members -status alive -tag leader=ready | grep -q leader=ready
while [ $? -ne 0 ] ; do
	echo "INFO: Waiting for leader to be ready... ($counter)"
	let counter=counter+1	
	sleep 5
	serf members -status alive -tag leader=ready | grep -q leader=ready
done
echo "INFO: execute rb_configure_custom.sh"
rb_configure_custom.sh

