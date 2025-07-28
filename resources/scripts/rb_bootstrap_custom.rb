#!/usr/bin/env ruby

puts "INFO: execute rb_bootstrap_common.sh"
system("rb_bootstrap_common.sh")
#Wait for tag leader=ready
counter = 1
while system("serf members -status alive -tag leader=ready | grep -q leader=ready") == false
  puts "INFO: Waiting for leader to be ready... (#{counter})"
  counter += 1
  sleep 5
end
puts "INFO: execute rb_configure_custom.sh"
system("rb_configure_custom.sh")
