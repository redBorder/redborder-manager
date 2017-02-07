#!/usr/bin/env ruby

#
#
#

require 'yaml'

#Check what services are necessary
external_services = [ "s3", "postgresql" ]
required_services = []

initconf_file = ARGV[0] if !ARGV.empty?
if !File.exist? initconf_file
	puts "ERROR: can't open init conf file (#{initconf_file})"
	exit(1)
else
	initconf = YAML.load_file(initconf_file)
	external_services.each { |service|
		if !initconf.key? service
			required_services << service
		end
	}
end

#Set serf tags for required services
required_services.each { |service|
	system("serf tags -set #{service}_required=true")
}

#Execution of rb_bootstrap_common
puts "INFO: execute bootstrap common script"
system("rb_bootstrap_common.sh")

#Wait for external services tags
required_services.each { |service|
	count = 1
	until system("serf members -status alive -tag #{service}=ready | grep -q #{service}=ready") do
		puts "INFO: Waiting for #{service} to be ready... (#{count})"
		count = count + 1
		sleep 5
	end
	if !system("serf-query-file -q #{service}_conf > /etc/redborder/#{service}_init_conf.yml")
		puts "ERROR: can't obtain #{service} configuration"
	end
}

#Set tag leader=inprogress
puts "INFO: setting leader tag to inprogress"
system("serf tags -set leader=inprogress")
#Clean required tags
required_services.each { |service|
	system("serf tags -delete #{service}_required")
}


#Execute configure leader script
puts "INFO: execute configure leader script"
system("rb_configure_leader.sh")

#Set tag leader=ready
puts "INFO: setting leader tag to ready"
system("serf tags -set leader=ready")
