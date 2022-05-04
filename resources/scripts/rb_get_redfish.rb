#!/usr/bin/env ruby

require 'ilo-sdk'
require 'optparse'

def showHelp
  puts @options[:help]
  exit
end

def showTypes
  puts "supported types : "
  puts "  - Timezone"
  puts "  - Fan"
  puts "  - Ambient_Temp"
  puts "  - CPU_Temp"
  puts "  - Power_Health"
  puts "  - System_Health"
  puts "  - iLO_Health"
  puts "  - Memory_Health"
  puts "  - Bios_Health"
  puts "  - Fan_Health"
  puts "  - Storage_Health"
  puts "  - Temperature_Health"
  exit
end

@options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: redfish.rb [options]"

  opts.on('-i', '--ip HOST-IP', 'ip address') { |o| @options[:host] = o }
  opts.on('-u', '--user USER', 'username') { |o| @options[:user] = o }
  opts.on('-p', '--password PASSWORD', 'password') { |o| @options[:password] = o }
  opts.on('-t', '--type TYPE', 'type') { |o| @options[:type] = o }

  @options[:help] = opts.help
end.parse!

showHelp if !@options[:host]
showHelp if !@options[:user]
showHelp if !@options[:password]
showTypes if !@options[:type]

client = ILO_SDK::Client.new(
  host: "https://#{@options[:host]}",
  user: @options[:user],              # This is the default
  password: @options[:password],
  ssl_enabled: false,                  # This is the default and strongly encouraged
  logger: Logger.new(STDOUT),         # This is the default
  log_level: :error,                   # This is the default
  disable_proxy: true                 # Default is false. Set to disable, even if ENV['http_proxy'] is set
)

case @options[:type].downcase
  when "timezone"
    timezone = client.get_time_zone
    puts timezone

  when "ambient_temp"
    temperature_metrics = client.get_temperature_metrics_5
    temperature_metrics.each do |temp|
      puts temp['CurrentReading'] if temp['Name'] == '15-Front Ambient'
    end

  when "fan"
    fans = ""
    fan_metrics = client.get_fan_metrics_5
    fan_metrics.each do |fan|
      fans = fans+fan['CurrentReading'].to_s+";"
    end
    puts fans.chop

  when "cpu_temp"
    temperature_metrics = client.get_temperature_metrics_5
    temperature_metrics.each do |temp|
      puts temp['CurrentReading'] if temp['Name'] == '02-CPU 1'
    end

  when "power_health"
    power = ""
    power_metrics = client.get_power_metrics_5
    power_metrics.each do |pow|
      if pow['Health'] == "OK"
        power = power+1.to_s+";"
      else
        power = power+0.to_s+";"
      end
   end
   puts power.chop

  when "memory_health"
    memory = ""
    memory_metrics = client.get_memory_metrics_5
    memory_metrics.each do |mem|
      if mem['Health'] == "OK"
        memory = memory+1.to_s+";"
      else
        memory = memory+0.to_s+";"
      end
   end
   puts memory.chop

  when "system_health"
    system_metrics = client.get_system_metrics_5
    system_metrics.each do |sys|
      if sys['System_Health'] == "OK"
        puts 1
      else
        puts 0
      end
   end

  when "ilo_health"
    system_metrics = client.get_system_metrics_5
    system_metrics.each do |sys|
      if sys['iLO_Health'] == "OK"
        puts 1
      else
        puts 0
      end
   end

  when "bios_health"
    bios_metrics = client.get_system_spec_metrics_5
    bios_metrics.each do |bios|
      if bios['Bios_Health'] == "OK"
        puts 1
      else
        puts 0
      end
   end

  when "fan_health"
    fan_metrics = client.get_system_spec_metrics_5
    fan_metrics.each do |fan|
      if fan['Fan_Health'] == "OK"
        puts 1
      else
        puts 0
      end
   end

  when "storage_health"
    storage_metrics = client.get_system_spec_metrics_5
    storage_metrics.each do |stor|
      if stor['Storage_Health'] == "OK"
        puts 1
      else
        puts 0
      end
   end

  when "temperature_health"
    temp_metrics = client.get_system_spec_metrics_5
    temp_metrics.each do |temp|
      if temp['Temp_Health'] == "OK"
        puts 1
      else
        puts 0
      end
   end
   
else
  showTypes
end

