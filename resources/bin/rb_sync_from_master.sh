#!/bin/bash

source /etc/profile 

master=$1
hostname=`hostname`

if [ "x$master" == "x" ]; then
    echo "need to provide master IP" 
    exit 1
fi

rm -f /tmp/postgresql.trigger
pushd /var/lib/pgsql

echo Stopping PostgreSQL
sudo service postgresql stop

echo Cleaning up old cluster directory
sudo -u postgres rm -rf /var/lib/pgsql/data

echo Starting base backup as replicator
retries=3
count=0
while [ $count -lt $retries ]; do
    sudo -u postgres pg_basebackup -h $master -D /var/lib/pgsql/data -U rep -R -v 2> /tmp/pg_basebackup_error.log
    if [ $? -eq 0 ]; then
        echo "pg_basebackup completed successfully."
        break
    fi
    echo "pg_basebackup failed. Retrying... ($((count + 1))/$retries)"
    count=$((count + 1))
    sleep 5
done

if [ $count -eq $retries ]; then
    echo "pg_basebackup failed after $retries attempts. Check /tmp/pg_basebackup_error.log for details."
    cat /tmp/pg_basebackup_error.log
    exit 1
fi

echo "Creating standby.signal file"
sudo -u postgres bash -c "touch /var/lib/pgsql/data/standby.signal"

[ -f /var/lib/pgsql/data/recovery.done ] && rm -f /var/lib/pgsql/data/recovery.done

sed -i '/^primary_conninfo/d' /var/lib/pgsql/data/postgresql.conf
sed -i '/^promote_trigger_file/d' /var/lib/pgsql/data/postgresql.conf
sed -i '/^standby_mode/d' /var/lib/pgsql/data/postgresql.conf
sudo -u postgres bash -c "cat >> /var/lib/pgsql/data/postgresql.conf <<- _EOF1_
#standby_mode = 'on'
primary_conninfo = 'host=$master port=5432 user=rep application_name=$hostname'
promote_trigger_file = '/tmp/postgresql.trigger'
_EOF1_
"

echo "Starting PostgreSQL"
sudo service postgresql start

echo "restart webui in all nodes"
rbcli node execute all systemctl restart webui
popd