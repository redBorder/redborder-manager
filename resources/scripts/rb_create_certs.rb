#!/usr/bin/env ruby

require 'json'
require 'openssl'
require 'base64'
require 'getopt/std'

def usage
  printf("rb_create_certs [-h] -a <application> [-c cdomain]\n")
  printf("  -h  -> print this help\n")
	printf("  -a application  -> application for this certificate \n")
	printf("  -c cdomain  -> cluster domain \n")
  exit 0
end

def create_cert(cn)
	key = OpenSSL::PKey::RSA.new 4096
	name = OpenSSL::X509::Name.parse "CN=#{cn}/DC=redborder"
	cert = OpenSSL::X509::Certificate.new
	cert.version = 2
	cert.serial = 0
	cert.not_before = Time.now
	cert.not_after = Time.now + (3600 *24 *365 *10)
	cert.public_key = key.public_key
	cert.subject = name
	cert.issuer = name
	cert.sign key, OpenSSL::Digest::SHA1.new
  	{ :key => key, :crt => cert}
end

opt = Getopt::Std.getopts("ha:c:")

usage if opt["h"]

if !opt["a"].nil? or !opt["c"].nil?
	cdomain = opt["c"]
  ret_json = { "id" => opt["a"] }
  cert_hash = create_cert("#{opt["a"]}.#{cdomain}")
  ret_json["#{opt["a"]}_crt"] = Base64.urlsafe_encode64(cert_hash[:crt].to_pem)
  ret_json["#{opt["a"]}_key"] = Base64.urlsafe_encode64(cert_hash[:key].to_pem)

  #open "/tmp/redborder.#{cdomain}.crt", 'w' do |io|
  #	io.write cert_hash[:crt].to_pem
  #end

  printf JSON.pretty_generate(ret_json)+"\n"
else
	printf("ERROR: You must specificate server and application name  \n")
	usage
end
