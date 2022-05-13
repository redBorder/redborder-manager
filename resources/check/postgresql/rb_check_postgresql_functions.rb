def check_postgres_database(node,database)

  rb_manager_utils = "/usr/lib/redborder/bin/rb_manager_utils.sh"
  rb_psql = "/usr/lib/redborder/bin/rb_psql"

  case database
  when "druid"
    table = "druid_rules"

  when "opscode_chef"
    table = "cookbooks"

  when "radius"
    table = "nas"

  when "redborder"
    table = "users"

  else
    return 1
  end

  command = rb_manager_utils + ' -e -n ' + node + ' -s "echo -e \"select id from ' + table + '\;\" | ' +  rb_psql + ' ' + database

  system(command) ? 0 : 1

end