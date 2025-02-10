#!/bin/bash

source /etc/profile 

master=$1
hostname=`hostname`

if [ "x$master" == "x" ]; then
    echo "Need to provide master IP"
    exit 1
fi

rm -f /tmp/postgresql.trigger
backup_dir="/var/lib/pgsql/data_tmp"
data_dir="/var/lib/pgsql/data"

# Ensure previous backup attempt directory is clean
rm -rf "$backup_dir"

echo "Starting base backup as replicator to temporary directory..."
retries=3
count=0
while [ $count -lt $retries ]; do
    sudo -u postgres pg_basebackup -h "$master" -D "$backup_dir" -U rep -R -v 2> /tmp/rb_notify_postgresql_pg_basebackup_error.log
    if [ $? -eq 0 ]; then
        echo "pg_basebackup completed successfully."
        break
    fi
    echo "pg_basebackup failed. Retrying... ($((count + 1))/$retries)"
    count=$((count + 1))
    sleep 5
done

if [ $count -eq $retries ]; then
    echo "pg_basebackup failed after $retries attempts. Keeping the existing data directory."
    cat /tmp/rb_notify_postgresql_pg_basebackup_error.log
    exit 1
fi

echo "Stopping PostgreSQL"
systemctl stop postgresql

echo "Replacing old data directory with new backup"
rm -rf "$data_dir"
mv "$backup_dir" "$data_dir"

echo "Creating standby.signal file"
sudo -u postgres touch "$data_dir/standby.signal"

[ -f "$data_dir/recovery.done" ] && rm -f "$data_dir/recovery.done"

sed -i '/^primary_conninfo/d' "$data_dir/postgresql.conf"
sed -i '/^promote_trigger_file/d' "$data_dir/postgresql.conf"
sed -i '/^standby_mode/d' "$data_dir/postgresql.conf"

sudo -u postgres bash -c "cat >> $data_dir/postgresql.conf <<- _EOF1_
#standby_mode = 'on'
primary_conninfo = 'host=$master port=5432 user=rep application_name=$hostname'
promote_trigger_file = '/tmp/postgresql.trigger'
_EOF1_
"

echo "Starting PostgreSQL"
service postgresql start

echo "restart webui in all nodes"
rbcli node execute all systemctl restart webui
