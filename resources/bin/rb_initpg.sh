#!/bin/bash

force=0
verbose=0
locally=1
stop_chef=1
chef_started=0
initialize=0
saveexternal=0
remote=""
username="opscode-pgsql"
password=""
pgdata="/var/pgdata"
tmpfile="/tmp/rb_initpg-$$.tmp"
ret=0

source $RBBIN/rb_manager_functions.sh

function usage() {
  echo "$0 [-h][-f][-c][-v][-s][-r <psql_server_address>][-u <username>][-p <password>]"
  echo "  -h -> print this help"
  echo "  -f -> force initialization"
  echo "  -c -> create data locally from cluster instead of locally"
  echo "  -v -> verbose"
  echo "  -s -> do not stop chef-client"
  echo "  -r <psql_server_address> -> remote host server instead of local one"
  echo "  -d <database> -> main database"
  echo "  -u <username> -> remote username"
  echo "  -p <password> "
  echo "  -i -> inicialice data with data from (postgresql.redborder.cluster) (mandatory -r)"
  echo "  -e -> add this as external in chef (mandatory -r)"
  exit 1
}

function send_command(){
  local database=$1
  shift
  set_color cyan
  echo "$*"
  set_color norm
  echo $* | env PGPASSWORD="$password" psql -U $username -h $remote -d $database
  return $?
}

function copy_data(){
  local database="$1"
  local usernamel="$2"
  local passwordl="$3"
  
  if [ "x$database" != "x" ]; then
    [ "x$usernamel" == "x" ] && usernamel="${username}"
    [ "x$passwordl" == "x" ] && passwordl="${password}"

    set_color cyan
    echo "su - opscode-pgsql -s /bin/bash -c \"pg_dump -U opscode-pgsql -a -F c -b $1\" > $tmpfile"
    set_color norm
    su - opscode-pgsql -s /bin/bash -c "pg_dump -U opscode-pgsql -a -F c -b $1" > $tmpfile

    set_color cyan
    echo "env PGPASSWORD=\"${passwordl}\" pg_restore -v -U ${usernamel} -d $1 -h ${remote} $tmpfile"
    set_color norm
    env PGPASSWORD="${passwordl}" pg_restore -v -U ${usernamel} -d $1 -h ${remote} $tmpfile
    rm -f $tmpfile
  fi
}

while getopts "hfcvsr:d:u:p:ie" name; do
  case $name in
    h) usage;;
    f) force=1;;
    c) locally=0;;
    v) verbose=1;;
    s) stop_chef=0;;
    r) remote=$OPTARG;;
    d) database=$OPTARG;;
    u) username=$OPTARG;;
    p) password=$OPTARG;;
    i) initialize=1;;
    e) saveexternal=1;;
  esac
done

OPTVERBOSE=""
[ $verbose -eq 1 ] && OPTVERBOSE="-v"

if [ $force -eq 0 ]; then
  if [ "x$remote" != "x" ]; then
    echo -n "Are you sure you want to initialize '$remote' postgresql server? (y/N) "
  else
    echo -n "Are you sure you wan to delete current postgresql data and initialize it again? (y/N) "
  fi
  read VAR
else
  VAR="y"
fi

if [ "x$VAR" == "xy" -o "x$VAR" == "xY" ]; then
  
  if [ "x$remote" != "x" ]; then
    if [ "x$username" != "x" -a "x$password" != "x" ]; then
      [ "x$database" == "x" ] && database="$username"
      send_command $database "SELECT version();"

      if [ $? -ne 0 ]; then
        echo "ERROR: cannot contact $remote ($database) with username ${username}"
        ret=1
      else
        if [ "x$database" != "xredborder" ]; then
          [ "x$username" != "xredborder" ] && send_command redborder "DROP ROLE IF EXISTS redborder;"
          send_command $database "DROP DATABASE redborder;"
          [ "x$username" != "xredborder" ] && send_command redborder "DROP ROLE IF EXISTS redborder;"
          send_command $database "CREATE DATABASE redborder;"
        fi
        if [ "x$username" != "xredborder" ]; then
          send_command redborder "CREATE USER redborder WITH PASSWORD 'EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT';" 
          send_command redborder "ALTER USER redborder WITH PASSWORD 'EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT';" 
        fi
  
        if [ "x$database" != "xdruid" ]; then 
          [ "x$username" != "xdruid" ] && send_command druid "DROP ROLE IF EXISTS druid;"
          send_command $database "DROP DATABASE druid;"
          send_command $database "CREATE DATABASE druid;"
        fi
        if [ "x$username" != "xdruid" ]; then
          send_command druid "CREATE USER druid WITH PASSWORD 'F1uHbF1Yy5VPrHigmjXYqG0EhtTfxFFXygWLl20hWT8kZGWLXAuRyaxXh6uNVT4OiugvoShNfqd37HXdKAWG3xhLpzgMIxWhDIQvklzKi1QaE4laWWBddZ9toUTbDxLP';"
          send_command druid "ALTER USER druid WITH PASSWORD 'F1uHbF1Yy5VPrHigmjXYqG0EhtTfxFFXygWLl20hWT8kZGWLXAuRyaxXh6uNVT4OiugvoShNfqd37HXdKAWG3xhLpzgMIxWhDIQvklzKi1QaE4laWWBddZ9toUTbDxLP';"
        fi

        if [ "x$database" != "xoozie" ]; then 
          send_command $database "DROP DATABASE oozie;"
          [ "x$username" != "xoozie" ] && send_command oozie "DROP ROLE IF EXISTS oozie;"
          send_command $database "CREATE DATABASE oozie;"
        fi
        if [ "x$username" != "xoozie" ]; then
          send_command oozie "CREATE USER oozie WITH PASSWORD 'FrhX22ypuPEx1NPxIBYIh7Eh6alLdXo3NTC7cfs4IZKJfAR1UurQjpyPcO8u3ojOBGPcfjcpklCiYsOVQ9y64TWlBfwXD0hHODMTEHOFaTi3OetZ4rDagiBwiTALLlON';"
          send_command oozie "ALTER USER oozie WITH PASSWORD 'FrhX22ypuPEx1NPxIBYIh7Eh6alLdXo3NTC7cfs4IZKJfAR1UurQjpyPcO8u3ojOBGPcfjcpklCiYsOVQ9y64TWlBfwXD0hHODMTEHOFaTi3OetZ4rDagiBwiTALLlON';"
        fi

        if [ "x$database" != "xopscode_chef" ]; then
          [ "x$username" != "xopscode_chef" ] && send_command opscode_chef "DROP ROLE IF EXISTS opscode_chef;"
          [ "x$username" != "xopscode-pgsql" ] && send_command opscode_chef "DROP ROLE IF EXISTS \"opscode-pgsql\";"
          [ "x$username" != "xopscode_chef_ro" ] && send_command opscode_chef "DROP ROLE IF EXISTS \"opscode_chef_ro\";"
          send_command $database "DROP DATABASE \"opscode_chef\";"
          send_command $database "CREATE DATABASE \"opscode_chef\";"
        fi
        if [ "x$username" != "xopscode_chef" ]; then
          send_command opscode_chef "CREATE USER \"opscode_chef\" WITH PASSWORD '15fbeda966a6677912b01d92a04c987713e0acb7c226d79298f6dc164d02505bf3fa2ad050ab98d773b8771de9f46d57a30f';"
          send_command opscode_chef "ALTER USER \"opscode_chef\" WITH PASSWORD '15fbeda966a6677912b01d92a04c987713e0acb7c226d79298f6dc164d02505bf3fa2ad050ab98d773b8771de9f46d57a30f';"
        fi
        if [ "x$username" != "xopscode-pgsql" ]; then
          send_command opscode_chef "CREATE USER \"opscode-pgsql\" WITH PASSWORD '15fbeda966a6677912b01d92a04c987713e0acb7c226d79298f6dc164d02505bf3fa2ad050ab98d773b8771de9f46d57a30f';"
          send_command opscode_chef "ALTER USER \"opscode-pgsql\" WITH PASSWORD '15fbeda966a6677912b01d92a04c987713e0acb7c226d79298f6dc164d02505bf3fa2ad050ab98d773b8771de9f46d57a30f';"
        fi
        if [ "x$username" != "xopscode_chef_ro" ]; then
          send_command opscode_chef "CREATE USER \"opscode_chef_ro\" WITH PASSWORD 'shmunzeltazzen';"
          send_command opscode_chef "ALTER USER \"opscode_chef_ro\" WITH PASSWORD 'shmunzeltazzen';"
        fi
  
        send_command opscode_chef "CREATE SCHEMA sqitch;"
        send_command opscode_chef "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA sqitch to opscode_chef;"
        send_command opscode_chef "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA sqitch to \"opscode-pgsql\";"
        send_command opscode_chef "GRANT \"opscode-pgsql\" to ${username};"
  
        if [ $initialize -eq 1 ]; then
          set_color cyan
          set_color norm
  
          RAILSTMPDIR="/var/www/rb-rails-$$"
          rsync -a /var/www/rb-rails/ $RAILSTMPDIR
  
          pushd $RAILSTMPDIR &>/dev/null
          
          cat > config/database.yml <<rBEOF
production:
  adapter: postgresql
  database: redborder
  pool: 32
  timeout: 5000
  username: redborder
  password: EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT
  host: ${remote}
  port: 5432
rBEOF
          env NO_MODULES=1 RAILS_ENV=production rake db:migrate
          env NO_MODULES=1 RAILS_ENV=production rake db:migrate:modules
          popd &>/dev/null
  
          rm -rf $RAILSTMPDIR
          echo "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public to redborder; DELETE from schema_migrations;" | env PGPASSWORD="EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT" psql -U redborder -d redborder -h ${remote}
          copy_data "redborder" "redborder" "EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT"
  
          [ -f /etc/druid/database.sql ] && cat /etc/druid/database.sql | env PGPASSWORD="${password}" psql -U ${username} -d druid -h ${remote}
          send_command druid "DELETE FROM druid_rules;"
          copy_data "druid"


          #if [ -f /opt/rb/var/oozie/bin/ooziedb.sh ]; then
          #  pushd /opt/rb/var/oozie &>/dev/null
          #  sed -i "s/postgresql.redborder.cluster/${remote}/" conf/oozie-site.xml 
          #  ./bin/ooziedb.sh create -sqlfile /opt/rb/etc/oozie/database.sql -run &>/root/.install-oozie-db.log
          #  popd &>/dev/null
          #fi
          
          if [ -f /etc/oozie/database.sql  ]; then
            cat /etc/oozie/database.sql | sed 's/\([^;]\)$/\1;/'  | env PGPASSWORD="${password}" psql -U ${username} -d oozie -h ${remote}
          fi
          copy_data "oozie"
        
          set_color cyan
          echo "su - opscode-pgsql -s /bin/bash -c \"pg_dump -s -U opscode-pgsql opscode_chef\" | env PGPASSWORD=\"${password}\" psql -U ${username} -d opscode_chef -h ${remote}" 
          set_color norm
          su - opscode-pgsql -s /bin/bash -c "pg_dump -s -U opscode-pgsql opscode_chef" | env PGPASSWORD="${password}" psql -U ${username} -d opscode_chef -h ${remote}

          if [ $saveexternal -eq 1 ]; then
            rb_external_postgresql -f -r "${remote}" -t redborder    -u "redborder" -w "EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT"
            rb_external_postgresql -f -r "${remote}" -t druid        -u "druid"     -w "F1uHbF1Yy5VPrHigmjXYqG0EhtTfxFFXygWLl20hWT8kZGWLXAuRyaxXh6uNVT4OiugvoShNfqd37HXdKAWG3xhLpzgMIxWhDIQvklzKi1QaE4laWWBddZ9toUTbDxLP"
            rb_external_postgresql -f -r "${remote}" -t oozie        -u "oozie"     -w "FrhX22ypuPEx1NPxIBYIh7Eh6alLdXo3NTC7cfs4IZKJfAR1UurQjpyPcO8u3ojOBGPcfjcpklCiYsOVQ9y64TWlBfwXD0hHODMTEHOFaTi3OetZ4rDagiBwiTALLlON"
            rb_external_postgresql -f -r "${remote}" -t opscode_chef -u "opscode_chef"   -w "15fbeda966a6677912b01d92a04c987713e0acb7c226d79298f6dc164d02505bf3fa2ad050ab98d773b8771de9f46d57a30f"
          fi
          copy_data "opscode_chef"
        fi 
  
        send_command druid "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public to druid;"
        send_command oozie "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public to oozie;"
        send_command opscode_chef "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public to opscode_chef;"
        send_command opscode_chef "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA sqitch to \"opscode-pgsql\";"
        send_command opscode_chef "GRANT SELECT ON ALL TABLES IN SCHEMA public to opscode_chef_ro;"
      fi
    else
      echo "ERROR: username and password ar mandatory to inialize remote database"
      ret=1
    fi
  else
  
    if [ $stop_chef -eq 1 ]; then
      service chef-client status &>/dev/null
      if [ $? -eq 0 ]; then 
        chef_started=1
        service chef-client stop
      fi
    else
      chef_started=0
    fi
    service postgresql stop
    sleep 5
    service postgresql stop &>/dev/null
    rm -rf $pgdata
    mkdir -p $pgdata
    chown opscode-pgsql:opscode-pgsql $pgdata
    chmod 700 $pgdata
  
    if [ $locally -eq 1 ]; then
      su - opscode-pgsql -s /bin/bash -c "cd $pgdata; initdb -D ."
    
      service postgresql start
    
      for n in opscode-pgsql redborder opscode_chef druid oozie; do 
        echo "Creating database: $n"
        su - opscode-pgsql -s /bin/bash -c "createdb $n"
      done
    
      echo -n "Creating role redborder: "
      su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER redborder WITH PASSWORD 'EwrTvXElMI3frYCsRvUazcg43d5UqlPFaEm5nzmqKlVGiyMPRTpIFeEyI6pYBjxJ5RFVi1uMa1NFRAmnO7oRKX5oVSOKmHxdVceC5EXiZSdPbDFLyeZONAfUPTOnurcT';\" | psql"
      echo -n "Creating role druid: "
      su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER druid WITH PASSWORD 'F1uHbF1Yy5VPrHigmjXYqG0EhtTfxFFXygWLl20hWT8kZGWLXAuRyaxXh6uNVT4OiugvoShNfqd37HXdKAWG3xhLpzgMIxWhDIQvklzKi1QaE4laWWBddZ9toUTbDxLP';\" | psql "
      echo -n "Creating role oozie: "
      su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER oozie WITH PASSWORD 'FrhX22ypuPEx1NPxIBYIh7Eh6alLdXo3NTC7cfs4IZKJfAR1UurQjpyPcO8u3ojOBGPcfjcpklCiYsOVQ9y64TWlBfwXD0hHODMTEHOFaTi3OetZ4rDagiBwiTALLlON';\" | psql "
      echo -n "Creating role opscode_chef: "
      su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER opscode_chef WITH PASSWORD '15fbeda966a6677912b01d92a04c987713e0acb7c226d79298f6dc164d02505bf3fa2ad050ab98d773b8771de9f46d57a30f';\" | psql"
      echo -n "Creating role opscode_chef_ro: "
      su - opscode-pgsql -s /bin/bash -c "echo \"CREATE USER opscode_chef_ro WITH PASSWORD 'shmunzeltazzen';\" | psql"
      
      service postgresql stop
    else
      echo "Creating $pgdata from postgresql.redborder.cluster: "
      su - opscode-pgsql -s /bin/bash -c "pg_basebackup $OPTVERBOSE -X stream -D $pgdata -U opscode-pgsql -h postgresql.redborder.cluster"
    fi
  
    if [ $chef_started -eq 1 ]; then
      service chef-client start
    else
      echo "chef-client is stopped. Please execute it to finish configuration"
    fi
  fi
fi

exit $ret
