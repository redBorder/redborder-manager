#!/bin/bash

#
#
#
source /etc/profile

serf-join /etc/serf/00first.json
serf-choose-leader.sh			\
	-c 	"mode=core|full"		\
	-r 	"consul=ready"			\
	-t 	"leader=wait"			\
	-l 	"rb_bootstrap_leader /etc/redborder/rb_init_conf.yml"	\
	-f  "rb_bootstrap_custom.sh"
