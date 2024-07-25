#!/usr/bin/env ruby

require 'json'
require 'openssl'
require 'base64'
require 'securerandom'

def create_cert(cn)
	key = OpenSSL::PKey::RSA.new 4096
	name = OpenSSL::X509::Name.parse "CN=#{cn}/DC=redborder"
	cert = OpenSSL::X509::Certificate.new
	cert.version = 2
	cert.serial = SecureRandom.random_number(2**128)
	cert.not_before = Time.now
	cert.not_after = Time.now + (3600 *24 *365 *10)
	cert.public_key = key.public_key
	cert.subject = name
	extension_factory = OpenSSL::X509::ExtensionFactory.new nil, cert
	cert.add_extension extension_factory.create_extension('basicConstraints', 'CA:FALSE', true)
	cert.add_extension extension_factory.create_extension('keyUsage', 'keyEncipherment,dataEncipherment,digitalSignature')
	cert.add_extension extension_factory.create_extension('subjectKeyIdentifier', 'hash')
	cert.issuer = name
	cert.sign key, OpenSSL::Digest::SHA256.new
  	{ :key => key, :crt => cert}
end

cdomain = (ENV["CDOMAIN"].nil?) ? "redborder.cluster" : ENV["CDOMAIN"].to_s

ret_json = { "id" => "nginx" }
[ "webui" ].each do |service|
	cert_hash = create_cert("redborder.#{cdomain}")
	ret_json["#{service}_crt"] = Base64.urlsafe_encode64(cert_hash[:crt].to_pem)
	ret_json["#{service}_key"] = Base64.urlsafe_encode64(cert_hash[:key].to_pem)
end

#open "/tmp/redborder.#{cdomain}.crt", 'w' do |io|
#	io.write cert_hash[:crt].to_pem
#end

printf JSON.pretty_generate(ret_json)+"\n"
