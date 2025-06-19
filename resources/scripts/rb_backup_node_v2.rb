#!/usr/bin/env ruby
#######################################################################
## Copyright (c) 2016 ENEO Tecnología S.L.
## This file is part of redBorder.
## redBorder is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
## redBorder is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License License for more details.
## You should have received a copy of the GNU Affero General Public License License
## along with redBorder. If not, see <http://www.gnu.org/licenses/>.
########################################################################

require 'getopt/std'
require 'fileutils'
require 'time'
require 'zlib'

PG_HBA_CONF = '/var/lib/pgsql/data/pg_hba.conf'
PG_HBA_BACKUP = '/var/lib/pgsql/data/pg_hba.conf.bak'
LOCAL_ENTRY = "local   all             postgres                                trust\n"

def usage
  puts <<-USAGE
Usage: rb_backup_node_v2.rb [-e] [-i tar_file] [-x start_date] [-y stop_date] [-v]
    -e                      -> export data (both PostgreSQL and segments)
    -p path                 -> path to put the file of exported data
    -i tar_file             -> import data from a tar.gz file (includes PostgreSQL and segments)
    -x start date           -> start date for segment export (format: 2024-08-18T22:00:00.000Z)
    -y stop date            -> stop date for segment export (format: 2024-08-19T22:00:00.000Z)
    -v                      -> verbose mode
  USAGE
  exit 0
end

def reload_postgresql
  system("sudo systemctl reload postgresql")
end

def modify_pg_hba(action, verbose)
  if action == :add
    puts "Adding local connection entry to pg_hba.conf..." if verbose
    File.open(PG_HBA_CONF, 'a') { |f| f.puts LOCAL_ENTRY }
  elsif action == :remove
    puts "Removing local connection entry from pg_hba.conf..." if verbose
    pg_hba_content = File.read(PG_HBA_CONF)
    new_content = pg_hba_content.gsub(LOCAL_ENTRY, '')
    File.open(PG_HBA_CONF, 'w') { |f| f.write(new_content) }
  end

  reload_postgresql
  puts "PostgreSQL configuration reloaded." if verbose
end

def backup_pg_hba
  FileUtils.cp(PG_HBA_CONF, PG_HBA_BACKUP)
end

def restore_pg_hba
  FileUtils.mv(PG_HBA_BACKUP, PG_HBA_CONF)
end

def export_postgresql_all(output, verbose)
  pg_command = "pg_dumpall -U postgres -f #{output}"
  pg_command << " -v" if verbose
  system(pg_command)
  if $?.success?
    puts "[  OK  ] PostgreSQL databases exported successfully" if verbose
  else
    puts "[  KO  ] Failed to export PostgreSQL databases"
    exit 1
  end
end

def export_segments(options, verbose)
  segment_file_path = "/tmp/segments_export_#{Time.now.strftime('%Y%m%d-%H%M%S')}.tar"
  puts segment_file_path
  command = "/usr/lib/redborder/bin/rb_export_import_segments.sh"
  command << " -x #{options[:start_date]}" if options[:start_date]
  command << " -y #{options[:stop_date]}" if options[:stop_date]
  command << " -t #{segment_file_path}" # Export segments to this file
  command << " -n"
  command << " -v" if verbose
  puts "Running segment export command: #{command}" if verbose
  system(command)

  if File.exist?(segment_file_path)
    puts "[  OK  ] Segments exported successfully to #{segment_file_path}" if verbose
    create_tar_gz("#{segment_file_path}.gz", [segment_file_path], true)
    return "#{segment_file_path}.gz"
  else
    puts "[  KO  ] Segment export file #{segment_file_path} not found. Please check the export process."
    exit 1
  end
end

def create_tar_gz(tarball, files, verbose)

  puts "Creating tar.gz archive..." if verbose
  tar_command = "tar -czf #{tarball} #{files.join(' ')}"
  puts "Running tar command: #{tar_command}" if verbose
  system(tar_command)
  if $?.success?
    puts "[  OK  ] Archive created at #{tarball}" if verbose
  else
    puts "[  KO  ] Failed to create archive"
    exit 1
  end
end

def extract_tar_gz(tarball, output_dir, verbose)
  puts "Extracting tar.gz archive..." if verbose
  tar_command = "tar -xzf #{tarball} -C #{output_dir}"
  puts "Running tar command: #{tar_command}" if verbose
  system(tar_command)
  if $?.success?
    puts "[  OK  ] Archive extracted to #{output_dir}" if verbose
  else
    puts "[  KO  ] Failed to extract archive"
    exit 1
  end
end

def import_postgresql_all(input, verbose)
  pg_command = "psql -U postgres -f #{input}"
  puts pg_command
  system(pg_command)
  if $?.success?
    puts "[  OK  ] PostgreSQL databases imported successfully" if verbose
  else
    puts "[  KO  ] Failed to import PostgreSQL databases"
    exit 1
  end
end

def import_segments(input, verbose)
  command = "/usr/lib/redborder/bin/rb_export_import_segments.sh"
  command << " -r -f #{input}" # Import segments from this file
  command << " -v" if verbose
  puts input
  puts "Running segment import command: #{command}" if verbose
  system(command)

  if $?.success?
    puts "[  OK  ] Segments imported successfully from #{input}" if verbose
  else
    puts "[  KO  ] Failed to import segments"
    exit 1
  end
end

# Main script starts here
opt = Getopt::Std.getopts("x:y:vep:i:")
verbose = opt['v'] ? true : false

if opt['e'] == opt['i']
  usage
end

timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
pg_dump_file = "/tmp/postgresql_backup_#{timestamp}.sql"
segment_file_path = "/tmp/segments_export_#{timestamp}.tar"
final_archive_path = "/tmp/"

if opt['p']
  final_archive_path = opt['p']
  final_archive_path = final_archive_path + "/" unless final_archive_path.end_with?("/")
end

final_archive = "#{final_archive_path}backup_all_#{timestamp}.tar.gz"

if opt['e']
  puts "Final archive will be in #{final_archive}"

  # Export option
  puts "Starting export process..." if verbose

  # Backup pg_hba.conf
  backup_pg_hba

  # Modify pg_hba.conf to allow local connections
  modify_pg_hba(:add, verbose)

  # Export PostgreSQL (all databases)
  export_postgresql_all(pg_dump_file, verbose)

  # Export Segments
  segment_file_path = export_segments({ start_date: opt['x'], stop_date: opt['y'] }, verbose)

  # Remove the temporary pg_hba.conf entry
  modify_pg_hba(:remove, verbose)
  
  # Restore original pg_hba.conf
  restore_pg_hba if File.exists?(PG_HBA_BACKUP)

  # Create tar.gz archive of all files
  create_tar_gz(final_archive, [pg_dump_file, segment_file_path], verbose)

  # Clean up temporary files
  FileUtils.rm_f([pg_dump_file, segment_file_path])
  puts "Export completed." if verbose

elsif opt['i']
  # Import option
  puts "Starting import process..." if verbose
  tar_file = opt['i']
  timestamp_match = tar_file.match(/(\d{8})-(\d{6})/)

  if timestamp_match
    date_part = timestamp_match[1]
    time_part = timestamp_match[2]
    timestamp = "#{date_part}-#{time_part}"
    puts "Extracted timestamp: #{timestamp}"
  else
    puts "No timestamp found in the file name."
  end

  temp_dir = "/tmp/import_temp_#{timestamp}"

  # Create temporary directory for extraction
  FileUtils.mkdir_p(temp_dir)
  # Extract tarball
  extract_tar_gz(tar_file, temp_dir, verbose)

  # Find the extracted files
  pg_file = Dir.glob("#{temp_dir}/tmp/postgresql_backup_*.sql").first
  segments_file = Dir.glob("#{temp_dir}/tmp/segments_export_*.tar").first
  unless pg_file && segments_file
    puts "[  KO  ] PostgreSQL or segments file does not exist in the tarball."
    exit 1
  end

  # Restore PostgreSQL databases
  #import_postgresql_all(pg_file, verbose)

  # Import Segments
  import_segments(segments_file, verbose)

  # Clean up temporary directory
#  FileUtils.rm_rf(temp_dir)
  puts "Import completed." if verbose
else
  usage
end

