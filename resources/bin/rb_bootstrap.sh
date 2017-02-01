#!/bin/bash

#
#
#

serf-join /etc/serf/00first.json
serf-choose-leader 				\
	-c 	mode=chef|full			\
	-r 	consul=ready			\
	-t 	leader=wait				\
	-l 	rb_bootstrap_leader		\
	-f  rb_bootstrap_common.sh
