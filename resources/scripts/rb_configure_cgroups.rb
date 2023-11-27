#!/usr/bin/env ruby

#######################################################################
# Copyright (c) 2024 ENEO Tecnologia S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# You should have received a copy of the GNU Affero General Public License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
# Authors:
# Miguel Alvarez <malvarez@redborder.com>
#######################################################################
require 'yaml'

# Module to interact with Cgroup v2 in an easy way
module RedBorder
  # Super easy to use API for configuring redBorder cgroups with cgroup v2
  # Echo ops are not regular writes, as the kernel patches the commands
  # More info https://facebookmicrosites.github.io/cgroup2/
  module Cgroups
    def self.fetch_cgroup_sys
      '/sys/fs/cgroup'
    end

    def self.fetch_cgroup_main(name)
      "/sys/fs/cgroup/#{name}.slice"
    end

    def self.fetch_cgroup_path(name, srv)
      "/sys/fs/cgroup/#{name}.slice/#{name}-#{srv.delete('-')}.slice"
    end

    def self.write_kernel_main_cgroup_io
      RedBorder::Logger.log('Enabling cgroup kernel IO')
      controller = "#{fetch_cgroup_sys}/cgroup.subtree_control"
      system("echo +io > #{controller}")
    end

    def self.write_kernel_sub_cgroup_io(name)
      RedBorder::Logger.log("Enabling sub-cgroup kernel IO for #{name}")
      controller = "#{fetch_cgroup_main(name)}/cgroup.subtree_control"
      system("echo +io > #{controller}")
    end

    def self.assign_memory_limit(name, srv, limit, max_limit)
      max_limit = RedBorder::Binary.kb_to_bytes(max_limit)
      limit = RedBorder::Binary.kb_to_bytes(limit)
      max_mem = "#{fetch_cgroup_path(name, srv)}/memory.max"
      mem = "#{fetch_cgroup_path(name, srv)}/memory.high"
      RedBorder::Logger.log("Assigning #{limit} for #{srv}")
      system("echo #{max_limit} > #{max_mem}") if max_limit != 0
      system("echo #{limit} > #{mem}")
    end

    def self.assign_io_limit(name, srv)
      limit = (srv == 'zookeeper') || (srv == 'postgresql') ? 1000 : 100
      io = "#{fetch_cgroup_path(name, srv)}/io.bfq.weight"
      system("echo #{limit} > #{io}")
    end

    def self.verify_unit(name, srv)
      unit = unit_file(srv)
      cgroup = File.read(unit)
      cgroup.include?("Slice=#{name}-#{srv.delete('-')}.slice")
    end

    def self.unit_file(srv)
      d = `systemctl show #{srv} | grep FragmentPath | awk -F'=' '{print $2}'`
      d.strip
    end

    def self.assign_cgroup(cgroup, srv)
      unit = unit_file(srv)
      slice = "#{cgroup}-#{srv.delete('-')}.slice"
      content = File.read(unit)

      content.gsub!(/^Slice=.*/, "Slice=#{slice}") if content[/^Slice=/]
      content += "\n[Service]\nSlice=#{slice}\n" unless content['Slice=']
      File.write(unit, content)
      system('systemctl daemon-reload > /dev/null 2>&1')
    end
  end

  # Module to make binary operations
  module Binary
    def self.kb_to_bytes(kbs)
      bytes = 0
      bytes = kbs * 1024 unless kbs.nil?
      bytes
    end
  end

  # Module to check and assign cgroups to services
  module Checker
    def self.check_units(cgroup, services)
      services.each do |srv, data|
        next unless data['memory'] > 0
        RedBorder::Logger.log("Checking cgroup for #{srv}")
        next if RedBorder::Cgroups.verify_unit(cgroup, srv)
        RedBorder::Logger.log("Assigning cgroup #{cgroup} for #{srv}")
        RedBorder::Cgroups.assign_cgroup(cgroup, srv)
        system("systemctl restart #{srv} > /dev/null 2>&1")
      end
    end

    def self.patch_cgroup_kernel(cgroup)
      RedBorder::Cgroups.write_kernel_main_cgroup_io
      RedBorder::Cgroups.write_kernel_sub_cgroup_io(cgroup)
    end

    def self.reassign_memory(cgroup, services)
      patch_cgroup_kernel(cgroup)

      services.each do |srv, data|
        next unless (memory = data['memory']) > 0

        max_limit = data['max_limit']
        RedBorder::Logger.log("Reassign memory for #{srv}")
        system("systemctl stop #{srv} > /dev/null 2>&1")

        RedBorder::Cgroups.assign_memory_limit(cgroup, srv, memory, max_limit)
        RedBorder::Cgroups.assign_io_limit(cgroup, srv)

        system("systemctl start #{srv} > /dev/null 2>&1")
      end
    end

    def self.conf
      services = begin
                   YAML.load_file('/etc/cgroup.conf')
                 rescue StandardError
                   {}
                 end
      services.each do |srv, data|
        services.delete(srv) if data['memory'].to_i <= 0 ||
                                !File.exist?(RedBorder::Cgroups.unit_file(srv))
      end

      services
    end
  end

  # Add a logger for the RedBorder module
  module Logger
    def self.log(msg)
      puts msg
    end
  end
end

services = RedBorder::Checker.conf || (exit 1)
RedBorder::Checker.check_units('redborder', services)
RedBorder::Checker.reassign_memory('redborder', services)
