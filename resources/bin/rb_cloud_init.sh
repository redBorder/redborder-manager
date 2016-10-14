#!/bin/bash

source /etc/profile

rvm gemset use default &>/dev/null

exec $RBBIN/rb_cloud_init.rb $*
