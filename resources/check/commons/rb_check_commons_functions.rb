require 'json'
require_relative '/usr/lib/redborder/lib/check/check_functions.rb'

def check_license(colorless, quiet=false)
  has_errors = false
  nodes = get_nodes_with_service
  time = Time.new.to_i

  title_ok("Licenses",colorless, quiet)

  nodes.each do |node|
    subtitle("Node #{node}", colorless, quiet)
    licenses = execute_command_on_node(node, "ls /etc/licenses/").split("\n")
    licenses.each do | license |
      command = "cat /etc/licenses/#{license}"
      license_values = JSON.parse(execute_command_on_node(node, command))
      expire_at = license_values["info"]["expire_at"]
      license_uuid = license_values["info"]["uuid"]

      if expire_at > time
        return_value = 0
      else
        return_value = 1
        has_errors = true
      end

      print_command_output(license_uuid, return_value, colorless, quiet)

    end
  end
  exit 1 if has_errors
end

def check_io(colorless, quiet=false)
  has_errors = false
  nodes = get_nodes_with_service

  title_ok("I/O errors proccess",colorless, quiet)

  nodes.each do |node|
    errors = 0
    io_errors = execute_command_on_node(node,"dmesg |grep end_request |grep I/O |grep error").split("\n")

    io_errors.each do |entry|
      print_error(node + ": " + entry, colorless)
      has_errors = true
      errors += 1
    end
    print_ok(node, colorless, quiet) if errors == 0
  end
  exit 1 if has_errors
end

def check_install(colorless, quiet=false)
  has_errors = false
  nodes = get_nodes_with_service

  title_ok("Installation log files",colorless, quiet)
  # /var/www/rb-rails/log/install-redborder-db.log
  # /root/.install-chef-client.log
  # /root/.install-chef-server.log
  nodes.each do |node|
    subtitle(node, colorless, quiet)
    %w[ /root/.install-chef-client.log /root/.install-chef-server.log /var/www/rb-rails/log/install-redborder-db.log
        /root/.install-redborder-boot.log
        .install-ks-post.log .install-redborder-cloud.log .restore-manager.log].each do |log_file|
      execute_command_on_node(node,"test -f #{log_file}")

      if $?.success?
        file_name = log_file.partition("/").last
        command = "grep -i 'error\|fail\|denied' #{log_file}"
        command += " | grep -v \"To check your SSL configuration, or troubleshoot errors, you can use the\""
        command += " | grep -v \"INFO: HTTP Request Returned 404 Object Not Found: error\""
        command += " | grep -v task.drop.deserialization.errors"
        command += " | grep -v \"Will not attempt to authenticate using SASL\""
        command += " | grep -v \"already exists\""
        command += " | grep -v 'retry [123]/5'|"

        errors = execute_command_on_node(node,command).split("\n")

        if errors.empty? #No error messages in log file
          print_ok(file_name,colorless, quiet)
        else
          has_errors = true
          print_error(file_name,colorless, quiet)
          errors.each_with_index { |error, i| logit("  " + i.to_s + ". " + error) unless quiet }
        end
      end
    exit 1 if has_errors
    end
  end

  title_ok("Installation time",colorless, quiet)
  nodes.each do |node|
    subtitle("TODO", colorless, quiet)
  end

  exit 1 if has_errors
end

def check_memory(colorless, quiet=false)
  has_errors = false
  nodes = get_nodes_with_service

  title_ok("Memory",colorless, quiet)

  nodes.each do |node|
    mem = execute_command_on_node(node,"free |grep Mem:").split()
    memtotal = mem[1].to_i
    memfree = mem[5].to_i
    percent = 100 * (memtotal - memfree) / memtotal

    if percent > 90
      print_error(node + " " + percent.to_s + "%",colorless, quiet)
      has_errors = true
    else
      print_ok(node + " " + percent.to_s + "%",colorless, quiet)
    end
  end

  exit 1 if has_errors
end

def check_hd(colorless, quiet=false)
  has_errors = false
  nodes = get_nodes_with_service

  title_ok("Hard Disk",colorless, quiet)

  nodes.each do |node|
    errors = 0
    max = 0
    disk_space = execute_command_on_node(node,"df --output=source,pcent").split("\n")
    disk_space.each do |entry|
      source, pcent = entry.split()
      pcent = pcent.chomp('%').to_i
      max = pcent if pcent > max
      if pcent >= 90
        errors = 1
        print_error("ERROR: Disk space problem at #{node} (#{pcent}%%) in #{source}", colorless, quiet)
        has_errors = true
      end
    end
    print_ok(node + " (max #{max}%%)",colorless, quiet) if errors == 0
  end
  exit 1 if has_errors
end

def check_killed(colorless, quiet=false)
  has_errors = false

  nodes = get_nodes_with_service

  title_ok("Killed proccesses",colorless, quiet)

  nodes.each do |node|
    errors = 0
    killed = execute_command_on_node(node,"dmesg |grep killed |grep Task").split("\n")

    killed.each do |entry|
      print_error(node + ": " + entry, colorless, quiet)
      has_errors = true
      errors += 1
    end
    print_ok(node,colorless, quiet) if errors == 0
  end
  exit 1 if has_errors
end