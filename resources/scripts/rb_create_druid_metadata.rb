#!/usr/bin/env ruby

require "getopt/std"
require "json"
require "fileutils"

def usage()
  printf "rb_create_druid_metadata.rb [-h] -u|-m -d <datasource> [-b <bucket>] [-g <regex>]\n"
  printf "   -h              : print this help\n"
  printf "   -u              : create and upload rule.json to S3 bucket (into druid segment folder)\n"
  printf "   -m              : create and insert synthetic druid metadata into postgresql\n"
  printf "   -d <datasource> : Filter by datasource\n"
  printf "   -b <bucket>     : Set bucket. Use redborder bucket if not set\n"
  printf "   -g <regex>      : Set filter by regex\n"
end

opt = Getopt::Std.getopts("d:hb:t:g:um")

if opt["h"] or (opt["u"].nil? and opt["m"].nil?) or opt["d"].nil?
  usage
  exit 0
end

# Initialize vars
opt["b"].nil? ? bucket="bucket" : bucket=opt["b"]
datasource=opt["d"]
s3cfg_file="/root/.s3cfg_initial"
# s3cfg_file="/root/.s3cfg-redborder"

tmpdir = "/tmp/segment_rules"
opt["g"].nil? ? filter = "" : filter="| grep #{opt["g"]}"

# Create temporal folder
FileUtils.mkdir_p(tmpdir)

bannertxt = ""
opt["u"] ? bannertxt = "Upload rule.json" : bannertxt = "Creating synthetic rule.json"

printf "\n============================================================\n"
puts " Create Druid metadata - #{bannertxt} mode "
printf "============================================================\n\n"

`s3cmd ls s3://#{bucket}/rbdata/#{datasource}/ 2>/dev/null | awk '{print $2}' | cut -d "/" -f 6 #{filter}`.split("\n").each do |segment|

  created_date = `s3cmd -c #{s3cfg_file} ls s3://#{bucket}/rbdata/#{datasource}/#{segment}/ 2>/dev/null | awk '{print $2}' | cut -d "/" -f 7`.chomp

  # get descriptor.json from segment
  system("s3cmd -c #{s3cfg_file} get s3://#{bucket}/rbdata/#{datasource}/#{segment}/#{created_date}/0/descriptor.json #{tmpdir} &>/dev/null")
  descriptor_file = JSON.parse(File.read("#{tmpdir}/descriptor.json"))
  descriptor_id = descriptor_file['identifier']

  if opt["u"] #OPTION 1: create and upload rule.json to S3 bucket (into druid segment folder)
    # Create rule.json from database stores metadata
    puts "Generating druid segment metadata for segment #{segment}"
    system("/usr/lib/redborder/scripts/rb_druid_metadata.rb -i #{descriptor_id} > #{tmpdir}/rule.json")
    # Upload rule.json to S3 bucket into segment folder
    puts "Uploading rule.json to s3://#{bucket}/rbdata/#{datasource}/#{segment}/#{created_date}/0/"
    system("s3cmd -c #{s3cfg_file} put #{tmpdir}/rule.json s3://#{bucket}/rbdata/#{datasource}/#{segment}/#{created_date}/0/ &>/dev/null")
    puts ""
  elsif opt["m"] #OPTION 2: create and insert synthetic druid metadata into postgresql
    #Creating synthetic druid metadata rule file
    druid_rule = {
      "id" => "#{datasource}_#{segment}_#{created_date}",
      "datasource" => datasource,
      "created_date" => created_date,
      "start" => segment.split("_").first,
      "end" => segment.split("_").last,
      "partitioned" => "t",
      "version" => created_date,
      "used" => "t",
      "payload" => {
        "dataSource" => datasource,
        "interval" => "#{segment.split("_").first}/#{segment.split("_").last}",
        "version" => created_date,
        "loadSpec" => {
          "type" => "s3_zip",
          "bucket" => "#{bucket}",
          "key" => "rbdata/#{datasource}/#{segment}/#{created_date}/0/index.zip"
        },
        "dimensions" => descriptor_file['dimensions'],
        "metrics" => descriptor_file['metrics'],
        "shardSpec" => {
          "type" => "linear",
          "partitionNum" => 0
        },
        "binaryVersion" => 9,
        "size" => 0,
        "identifier" => "#{datasource}_#{segment}_#{created_date}"
      }
    }

    open "#{tmpdir}/rule.json", 'w' do |io|
      io.write JSON.pretty_generate(druid_rule)
    end

    puts "Generating druid segment metadata for segment #{segment}"
    system("/usr/lib/redborder/scripts/rb_druid_metadata.rb -f #{tmpdir}/rule.json &>/dev/null")
    puts ""

  end
end

FileUtils.rmdir(tmpdir)
exit 0
