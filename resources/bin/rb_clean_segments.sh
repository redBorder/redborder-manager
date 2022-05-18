#!/bin/bash

source /etc/profile.d/rvm.sh

rvm gemset use web &>/dev/null
/usr/lib/redborder/scripts/rb_clean_segments.rb &>/dev/null
exit 0;