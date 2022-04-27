#!/usr/bin/env ruby
#########################################################################    
### Copyright (c) 2014 ENEO Tecnología S.L.
### This file is part of redBorder.
### redBorder is free software: you can redistribute it and/or modify
### it under the terms of the GNU Affero General Public License License as published by
### the Free Software Foundation, either version 3 of the License, or
### (at your option) any later version.
### redBorder is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### GNU Affero General Public License License for more details.
### You should have received a copy of the GNU Affero General Public License License
### along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#########################################################################

require "getopt/std"
require "fileutils"
require "yaml"
require "json"
require "socket"
require "net/http"
require "openssl"
require "pathname"

##########################
## Methods
## #######################
def usage()
  printf "rb_create_bulkstats_columns.rb [-h] [-b <bucket>]\n"
  printf "   -h               : print this help\n"
  printf "   -b <bucket>      : Set bucket. Use redborder bucket if not set\n"
  #printf "   -f <schema-file> : schema file to process\n"
end

# Recieve an array of dimensions
# Ouputting an array of Custom Tab as Hash
def build_custom_tabs(dimensions = [])
  custom_tabs = []
  dimensions.each  do |dim|
    custom_tab = Hash.new
    custom_tab[:name] = dim.gsub('_',' ')
    custom_tab[:enabled] = true
    custom_tab[:percentage] = false
    custom_tab[:category] = 'Bulkstats'
    custom_tab[:units] = ''
    custom_tabs.push(custom_tab)
  end
  custom_tabs
end

def get_domain
if File.exists?("/etc/externals.yml")
    externals             = YAML.load_file('/etc/externals.yml')
    domain_rbglobal       = externals['CDOMAIN']
  elsif File.exists?("/etc/manager.yml")
    manager_config        = YAML.load_file('/etc/manager.yml')
    domain_rbglobal       = manager_config['DOMAIN']
  elsif File.exists?("/etc/resolv.conf")
    domain_rbglobal = `cat /etc/resolv.conf | grep domain | cut -d " " -f2`.strip()
  end
  domain_rbglobal       = "redborder.cluster" if (domain_rbglobal.nil? or domain_rbglobal == "")
  domain_rbglobal
end

def update_rbwebui_tabs_with_dimensions(dimensions = [])
  custom_tabs = build_custom_tabs(dimensions)

  http = Net::HTTP.new("rb-webui.#{get_domain}", 443)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  path = '/api/v1/custom_tabs/import'
  headers = {
    'Content-Type' => 'application/json'
  }

  # Payload of Import Custom Tabs request
  data = {
    "custom_tabs" => custom_tabs,
  }

  begin
    resp, data = http.post(path, data.to_json, headers)
    response_json = JSON.parse(resp.body)
  rescue Exception => e
    puts e.to_s
  end
end

def retrieve_s3_schema_files(s3file = "", s3cfg_file, bucket, tmpdir)
  if s3file.empty?
    system("s3cmd -c #{s3cfg_file} get --recursive s3://#{bucket}/rb-webui/monitor_categories/ #{tmpdir}")
  else
    system("s3cmd -c #{s3cfg_file} get #{s3file} #{tmpdir}")
  end
end

def process_schema_file(schemafile, schema_id)
  puts "processing #{schemafile}..."
  columns = {}

  # open schemafile an parse the data into the variable pattern
  File.open(schemafile, "r").each_line do |line|
     # only parse the lines the contain EMS
     # trim the lines and split by comma
     # the first element after the split is seen as "head", that will be split and only last part is used, which should be "EMS"
     # the first part of the head is used for the patternsname
     if line.include? "EMS"
       dimensions=line.strip.tr("-","_").tr("%","").split(",")
       head = dimensions[0]
       head_split = head.split(" ")
       dimensions[0]=head_split.last
       columns[dimensions[1]] = dimensions
       @dimensions_used += dimensions
     end
  end
  columns
end

def save_columns_file(outdir, schema_id, columns)
  begin
    outfile=outdir+schema_id
    file = File.open(outfile, "w")
    file.write JSON.dump(columns)
    puts "new file written to #{outfile}"
  rescue IOError => e
    #some error occur, dir not writable etc.
  ensure
    file.close unless file.nil?
  end
end

###############################
# MAIN
##############################

opt = Getopt::Std.getopts("hcb:f:")

s3cfg_file="/root/.s3cfg_initial"
tmpdir = "/tmp/bulkstats_columns"
outdir = "/tmp/bulkstats-#{Time.now.to_i}/"
bulkstats_columns_tar_gz="/share/bulkstats.tar.gz"

opt["b"].nil? ? bucket="redborder" : bucket=opt["b"]
opt["f"].nil? ? s3file = "" : s3file = opt["f"]

if opt["h"]
  usage
  exit 0
end

# Create temporal folder
FileUtils.mkdir_p(tmpdir)

#clean the schema outdir to create the tar from 
FileUtils.rm_rf(outdir)

# create bulkstats columns directory
FileUtils.mkdir_p(outdir)

# retrieve the necesary schema files
retrieve_s3_schema_files(s3file, s3cfg_file, bucket, tmpdir)

@dimensions_used = []

# process the schema files
schemafiles = Dir.glob("#{tmpdir}/**/*").reject { |file_path| File.directory? file_path }
schemafiles.each do |schemafile|
   # retrieve the schema id from the directory where the schemafile is stored (parent directory)
   schema_id = (Pathname.new(schemafile).parent).to_s.split("/").last

   columns = process_schema_file(schemafile, schema_id)   
   save_columns_file(outdir, schema_id, columns)
end

# Build bulkstats.tar.gz from outdir
system("tar -C #{outdir} -cvzf #{bulkstats_columns_tar_gz} .")

#copy the processed schema files to all nodes
system("rb_manager_scp.sh all #{bulkstats_columns_tar_gz}")

# send all new dimensions used to the platform to add them in the rails part
puts @dimensions_used.sort.uniq.to_s
update_rbwebui_tabs_with_dimensions(@dimensions_used.sort.uniq)

# cleanup all temparary directories and files
FileUtils.rm_rf(tmpdir)
FileUtils.rm_rf(outdir)

exit 0
