def check_postgres_database(database)
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

  `echo "select id from #{table} LIMIT 1; " | rb_psql #{database} &>/dev/null`
  $?.exitstatus

end