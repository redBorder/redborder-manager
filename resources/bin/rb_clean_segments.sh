#!/bin/bash

source /etc/profile.d/rvm.sh

rvm gemset use default &>/dev/null
/usr/lib/redborder/scripts/rb_clean_segments.rb
exit 0;