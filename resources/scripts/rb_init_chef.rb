#!/usr/bin/env ruby

require 'yaml'

RBETC = ENV['RBETC'].nil? ? '/etc/redborder' : ENV['RBETC']
INITCONF = "#{RBETC}/rb_init_conf.yml"
S3INITCONF = "#{RBETC}/s3_init_conf.yml"
PGINITCONF = "#{RBETC}/postgresql_init_conf.yml"
ret = 0

####################
# S3 configuration #
####################

if File.exists?(S3INITCONF)
  s3_init_conf = YAML.load_file(S3INITCONF)
else
  s3_init_conf = YAML.load_file(INITCONF)
end

s3_conf = s3_init_conf['s3']
unless s3_conf.nil?
  s3_access = s3_conf['access_key']
  s3_secret = s3_conf['secret_key']
  s3_endpoint = s3_conf['endpoint']
  s3_bucket = s3_conf['bucket']

  # CHECK S3 CONNECTIVITY
  #unless s3_access.nil? or s3_secret.nil?
  #  # Check S3 connectivity
  #  open("/root/.s3cfg-test", "w") { |f|
  #    f.puts "[default]"
  #    f.puts "access_key = #{s3_access}"
  #    f.puts "secret_key = #{s3_secret}"
  #    f.puts "host_base = #{s3_endpoint}"
  #    f.puts "host_bucket = %(bucket)s.#{s3_endpoint}"
  #    f.puts "signature_v2 = True"
  #    f.puts "use_https = True"
  #  }
  #  out = system("/usr/bin/s3cmd -c /root/.s3cfg-test ls s3://#{s3_bucket} &>/dev/null")
  #  #File.delete("/root/.s3cfg-test")
  #else
  #  out = system("/usr/bin/s3cmd ls s3://#{s3_bucket} &>/dev/null")
  #end
  #unless out
  #  p err_msg = "ERROR: Impossible connect to S3. Please review #{INITCONF} file"
  #  ret = 1
  #end

  # Create chef-server configuration file for S3
  open("/etc/redborder/chef-server-s3.rb", "w") { |f|
    f.puts "bookshelf['enable'] = false"
    if s3_bucket == "redborder"
      f.puts "bookshelf['vip'] = \"#{s3_bucket}.#{s3_endpoint}\""
      f.puts "bookshelf['external_url'] = \"https://#{s3_bucket}.#{s3_endpoint}\""
    else
      f.puts "bookshelf['vip'] = \"#{s3_endpoint}\""
      f.puts "bookshelf['external_url'] = \"https://#{s3_endpoint}\""
    end
    f.puts "bookshelf['access_key_id'] = \"#{s3_access}\""
    f.puts "bookshelf['secret_access_key'] = \"#{s3_secret}\""
    f.puts "opscode_erchef['s3_bucket'] = \"#{s3_bucket}\""
  }
end

####################
# DB configuration #
####################

if File.exists?(PGINITCONF)
  pg_init_conf = YAML.load_file(PGINITCONF)
else
  pg_init_conf = YAML.load_file(INITCONF)
end

db_conf = pg_init_conf['postgresql']
unless db_conf.nil?
  db_superuser = db_conf['superuser']
  db_password = db_conf['password']
  db_host = db_conf['host']
  db_port = db_conf['port']

  # Check database connectivity
  out = system("env PGPASSWORD='#{db_password}' psql -U #{db_superuser} -h #{db_host} -d template1 -c '\\q' &>/dev/null")
  unless out
    p err_msg = "ERROR: Impossible connect to database. Please review #{INITCONF} file"
    ret = 1
  end

  # Create chef-server configuration file for postgresql
  open("/etc/redborder/chef-server-postgresql.rb", "w") { |f|
    f.puts "postgresql['db_superuser'] = \"#{db_superuser}\""
    f.puts "postgresql['db_superuser_password'] = \"#{db_password}\""
    f.puts "postgresql['external'] = true"
    f.puts "postgresql['port'] = #{db_port}"
    f.puts "postgresql['vip'] = \"#{db_host}\""
  }
end

exit ret
