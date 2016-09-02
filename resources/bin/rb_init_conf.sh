#!/bin/bash

source /etc/profile

rvm gemset use default &>/dev/null

exec $RBBIN/rb_init_conf.rb $*
