require_relative '/usr/lib/redborder/lib/check/check_functions.rb'

def check_license(colorless, quiet=false)
  has_errors = false
  nodes = get_nodes_with_service

  title_ok("Checking licenses",colorless, quiet)

  nodes.each do |node|
    p "TODO" unless quiet
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

  title_ok("Install log files",colorless, quiet)

  nodes.each do |node|
    %w[.install-chef-server.log  .install-ks-post.log  .install-redborder-boot.log
       .install-redborder-cloud.log .install-redborder-db.log .restore-manager.log].each do |log_file|
      subtitle("Checking #{log_file} error on #{node}", colorless, quiet)
      p "TODO"
    end
  end

  title_ok("Install time",colorless, quiet)
  nodes.each do |node|
    subtitle("Checking install time on #{node}", colorless, quiet)
    p "TODO" unless quiet
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