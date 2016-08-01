#!/bin/bash

source /etc/profile

rvm gemset use default &>/dev/null

exec rb_setup_wizard.rb $*
