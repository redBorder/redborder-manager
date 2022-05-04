#!/bin/bash

source /etc/profile

/opt/opscode/embedded/bin/rabbitmqctl rotate_logs &>/dev/null
exit 0;