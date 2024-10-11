#!/bin/bash

PGUSER="redborder"
PGDB="redborder"

# Retrieve database details from the configuration file
line=$(awk '/redborder/{ print NR; exit }' /var/www/rb-rails/config/database.yml)
PGPASSWORD=$(tail -n +$line /var/www/rb-rails/config/database.yml | grep "password: " | head -n 1 | awk '{print $2}')
PGHOSTNAME=$(tail -n +$line /var/www/rb-rails/config/database.yml | grep "host: " | head -n 1 | awk '{print $2}')
PGPORT=$(tail -n +$line /var/www/rb-rails/config/database.yml | grep "port: " | head -n 1 | awk '{print $2}')

# If host or port is not found, set default values
[ "x$PGHOSTNAME" == "x" ] && PGHOSTNAME="master.postgresql.service"
[ "x$PGPORT" == "x" ] && PGPORT=5432

# Execute the query to check the recovery status (if it is in slave or master mode)
IS_SLAVE=$(/bin/psql -U ${PGUSER} -h ${PGHOSTNAME} -p ${PGPORT} -d ${PGDB} -t -c "SELECT pg_is_in_recovery();" | tr -d '[:space:]')

if [ "$IS_SLAVE" == "t" ]; then
  echo "true"
else
  echo "false"
fi
