#!/usr/bin/env ruby
# rb_simulate_attack.rb
#
# Kafka producer using Poseidon gem:
#   gem install poseidon
#
# Produces simulated attack events into Kafka topics:
#   - rb_flow  (netflow-like)
#   - rb_event (snort-like alerts)
#
# Attack types:
#   - ddos
#   - portscan
#   - dns_tunnel
#   - bruteforce_ssh
#
# Examples:
#   ruby rb_simulate_attack.rb bruteforce_ssh --brokers localhost:9092 --duration 30 --rate 20 --target both \
#     --namespace Tecnova --namespace-uuid ca1417ba-146d-467d-8f3b-44e6c0d64748

require "json"
require "securerandom"
require "optparse"
require "time"
require "poseidon"

TOPIC_FLOW  = "rb_flow"
TOPIC_EVENT = "rb_event"

ATTACK_TYPES = %w[ddos portscan dns_tunnel bruteforce_ssh].freeze
TARGETS = %w[flow event both].freeze

def now_epoch
  Time.now.to_i
end

def rand_ip_in_cidr_10
  "10.#{rand(0..255)}.#{rand(0..255)}.#{rand(1..254)}"
end

def rand_private_ip
  rand < 0.85 ? rand_ip_in_cidr_10 : "192.168.#{rand(0..255)}.#{rand(1..254)}"
end

def rand_mac
  bytes = Array.new(6) { rand(0..255) }
  bytes[0] = (bytes[0] | 0x02) & 0xFE # locally administered, unicast
  bytes.map { |b| format("%02x", b) }.join(":")
end

def maybe_add_dims!(h, dims)
  dims.each do |k, v|
    next if v.nil? || v.to_s.strip.empty?
    h[k] = v
  end
end

def random_sensor
  {
    "sensor_ip"   => rand_private_ip,
    "sensor_name" => ["IDS Sensor", "Cisco ISR 5000 SecureEdge", "Edge Sensor", "Branch IDS"].sample,
    "sensor_uuid" => SecureRandom.uuid
  }
end

class AttackGenerator
  def initialize(attack_type:, sensor:, dims:)
    @attack_type = attack_type
    @sensor = sensor
    @dims = dims
    @flow_sequence = rand(10_000..99_999)

    # Sticky fields so the simulation looks consistent per run
    @victim_ip_http   = "10.1.70.5"
    @victim_port_http = [80, 443].sample

    @scanner_ip   = "10.1.30.90"
    @scan_target  = "10.1.30.255"

    @dns_client   = rand_ip_in_cidr_10
    @dns_resolver = "10.1.33.30"

    @ssh_attacker = rand_ip_in_cidr_10
    @ssh_victim   = "10.1.50.10"
    @ssh_port     = 22
  end

  def next_flow
    @flow_sequence += 1

    base = {
      "type" => "netflowv10",
      "flow_sequence" => @flow_sequence.to_s,
      "ip_protocol_version" => 4,
      "input_vrf" => 0,
      "output_vrf" => 0,
      "flow_end_reason" => "idle timeout",
      "biflow_direction" => "initiator",
      "direction" => "internal",
      "lan_interface" => rand(1..32),
      "lan_interface_name" => nil,
      "lan_interface_description" => nil,
      "wan_interface" => rand(1..32),
      "wan_interface_name" => nil,
      "wan_interface_description" => nil,
      "client_mac" => rand_mac,
      "client_mac_vendor" => ["XEROX CORPORATION", "Proxmox Server Solutions GmbH", "Dell Inc.", "Hewlett Packard"].sample,
      "timestamp" => now_epoch,
      "index_partitions" => 5,
      "index_replicas" => 1,
      "proxy_uuid" => SecureRandom.uuid
    }

    base["lan_interface_name"] = base["lan_interface"].to_s
    base["lan_interface_description"] = base["lan_interface"].to_s
    base["wan_interface_name"] = base["wan_interface"].to_s
    base["wan_interface_description"] = base["wan_interface"].to_s

    base.merge!(@sensor)
    maybe_add_dims!(base, @dims)

    case @attack_type
    when "ddos"          then ddos_flow(base)
    when "portscan"      then portscan_flow(base)
    when "dns_tunnel"    then dns_tunnel_flow(base)
    when "bruteforce_ssh" then bruteforce_ssh_flow(base)
    else base
    end
  end

  def next_event
    base = {
      "timestamp" => now_epoch,
      "sensor_id_snort" => 0,
      "action" => "alert",
      "sig_generator" => 122,
      "rev" => 1,
      "priority" => "medium",
      "classification" => "Attempted Denial of Service",
      "msg" => "generic: simulated alert",
      "payload" => SecureRandom.hex(64),
      "l4_proto_name" => "udp",
      "l4_proto" => 17,
      "ethsrc" => "00:00:00:00:00:00",
      "ethdst" => "00:00:00:00:00:00",
      "ethsrc_vendor" => ["XEROX CORPORATION", "Intel Corporate", "Proxmox Server Solutions GmbH"].sample,
      "ethdst_vendor" => ["XEROX CORPORATION", "Intel Corporate", "Proxmox Server Solutions GmbH"].sample,
      "ethtype" => rand(20_000..30_000),
      "vlan" => rand(1..100),
      "vlan_name" => nil,
      "vlan_priority" => 0,
      "vlan_drop" => 0,
      "ethlength" => 0,
      "ethlength_range" => "0(0-64]",
      "src_asnum" => rand(1_000_000..4_000_000_000),
      "dst_asnum" => rand(1_000_000..4_000_000_000),
      "ttl" => rand(32..128),
      "tos" => 0,
      "id" => rand(1..65_000),
      "iplen" => rand(80..1400),
      "iplen_range" => "[128-256)",
      "dgmlen" => rand(80..1400),
      "group_uuid" => SecureRandom.uuid,
      "group_name" => "default",
      "sensor_type" => "ips",
      "domain_name" => (@dims["organization"] || "default"),
      "sensor_ip" => @sensor["sensor_ip"],
      "sensor_uuid" => @sensor["sensor_uuid"],
      "sensor_name" => @sensor["sensor_name"],
      "index_partitions" => 5,
      "index_replicas" => 1
    }

    base["vlan_name"] = base["vlan"].to_s
    maybe_add_dims!(base, @dims)

    case @attack_type
    when "ddos"          then ddos_event(base)
    when "portscan"      then portscan_event(base)
    when "dns_tunnel"    then dns_tunnel_event(base)
    when "bruteforce_ssh" then bruteforce_ssh_event(base)
    else base
    end
  end

  private

  def ddos_flow(base)
    src_ip = rand_private_ip
    src_port = rand(1024..65_535)

    base.merge!(
      "l4_proto" => 6,
      "application_id_name" => "3:#{@victim_port_http}",
      "engine_id_name" => "3",
      "wan_ip" => @victim_ip_http,
      "wan_ip_net" => "10.0.0.0/8",
      "wan_ip_net_name" => "default_1",
      "lan_ip" => src_ip,
      "lan_ip_net" => "10.0.0.0/8",
      "lan_ip_net_name" => "default_1",
      "wan_l4_port" => @victim_port_http,
      "lan_l4_port" => src_port,
      "bytes" => rand(20_000..500_000),
      "pkts" => rand(200..5000)
    )
  end

  def portscan_flow(base)
    base.merge!(
      "l4_proto" => 17,
      "application_id_name" => "3:53",
      "engine_id_name" => "3",
      "wan_ip" => @scan_target,
      "wan_ip_net" => "10.0.0.0/8",
      "wan_ip_net_name" => "default_1",
      "lan_ip" => @scanner_ip,
      "lan_ip_net" => "10.0.0.0/8",
      "lan_ip_net_name" => "default_1",
      "wan_l4_port" => rand(1..65_535),
      "lan_l4_port" => rand(1024..65_535),
      "bytes" => rand(200..3000),
      "pkts" => rand(2..40)
    )
  end

  def dns_tunnel_flow(base)
    base.merge!(
      "l4_proto" => 17,
      "application_id_name" => "3:53",
      "engine_id_name" => "3",
      "wan_ip" => @dns_resolver,
      "wan_ip_net" => "10.0.0.0/8",
      "wan_ip_net_name" => "default_1",
      "lan_ip" => @dns_client,
      "lan_ip_net" => "10.0.0.0/8",
      "lan_ip_net_name" => "default_1",
      "wan_l4_port" => 53,
      "lan_l4_port" => rand(20_000..65_000),
      "bytes" => rand(5_000..120_000),
      "pkts" => rand(50..1200)
    )
  end

  def bruteforce_ssh_flow(base)
    # Many short TCP connections to port 22
    # Keep victim stable, attacker mostly stable but can vary a bit to mimic botnets
    attacker_ip = (rand < 0.85) ? @ssh_attacker : rand_ip_in_cidr_10
    attacker_port = rand(1024..65_535)

    base.merge!(
      "l4_proto" => 6,
      "application_id_name" => "3:22",
      "engine_id_name" => "3",
      "wan_ip" => @ssh_victim,
      "wan_ip_net" => "10.0.0.0/8",
      "wan_ip_net_name" => "default_1",
      "lan_ip" => attacker_ip,
      "lan_ip_net" => "10.0.0.0/8",
      "lan_ip_net_name" => "default_1",
      "wan_l4_port" => @ssh_port,
      "lan_l4_port" => attacker_port,
      # small flows, lots of them
      "bytes" => rand(300..6_000),
      "pkts" => rand(3..60)
    )
  end

  def ddos_event(base)
    base.merge!(
      "sig_id" => 2000010,
      "priority" => "high",
      "classification" => "Attempted Denial of Service",
      "msg" => "ddos: Possible HTTP(S) flood detected",
      "l4_proto_name" => "tcp",
      "l4_proto" => 6,
      "src" => rand_private_ip,
      "src_name" => nil,
      "dst" => @victim_ip_http,
      "dst_name" => @victim_ip_http
    ).tap { |h| h["src_name"] = h["src"] }
  end

  def portscan_event(base)
    base.merge!(
      "sig_id" => 23,
      "priority" => "medium",
      "classification" => "Attempted Information Leak",
      "msg" => "portscan: UDP Filtered Portsweep",
      "l4_proto_name" => "udp",
      "l4_proto" => 17,
      "src" => @scanner_ip,
      "src_name" => @scanner_ip,
      "dst" => @scan_target,
      "dst_name" => @scan_target
    )
  end

  def dns_tunnel_event(base)
    base.merge!(
      "sig_id" => 2000042,
      "priority" => "high",
      "classification" => "Potential Corporate Privacy Violation",
      "msg" => "dns: Possible DNS tunneling / data exfiltration",
      "l4_proto_name" => "udp",
      "l4_proto" => 17,
      "src" => @dns_client,
      "src_name" => @dns_client,
      "dst" => @dns_resolver,
      "dst_name" => @dns_resolver
    )
  end

  def bruteforce_ssh_event(base)
    attacker_ip = (rand < 0.85) ? @ssh_attacker : rand_ip_in_cidr_10

    base.merge!(
      "sig_id" => 2000101,
      "priority" => "high",
      "classification" => "Attempted Administrator Privilege Gain",
      "msg" => "ssh: Brute force login attempts",
      "l4_proto_name" => "tcp",
      "l4_proto" => 6,
      "src" => attacker_ip,
      "src_name" => attacker_ip,
      "dst" => @ssh_victim,
      "dst_name" => @ssh_victim
    )
  end
end

# ---------------- CLI ----------------

options = {
  brokers: (ENV["KAFKA_BROKERS"] || "localhost:9092"),
  duration: 10,
  rate: 10,
  target: "both",
  flow_topic: TOPIC_FLOW,
  event_topic: TOPIC_EVENT,
  client_id: "rb_simulate_attack",
  sync: false,
  batch_size: 200,
  dims: {}
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby rb_simulate_attack.rb <attack_type> [options]\n\n" \
                "attack_type: #{ATTACK_TYPES.join(", ")}"

  opts.on("--brokers BROKERS", "Kafka brokers comma-separated (default: #{options[:brokers]})") { |v| options[:brokers] = v }
  opts.on("--client-id ID", "Kafka client_id (default: #{options[:client_id]})") { |v| options[:client_id] = v }
  opts.on("--duration SECONDS", Integer, "How long to run (default: #{options[:duration]})") { |v| options[:duration] = v }
  opts.on("--rate N", Integer, "Ticks per second (default: #{options[:rate]})") { |v| options[:rate] = v }
  opts.on("--target TARGET", "flow|event|both (default: #{options[:target]})") { |v| options[:target] = v }
  opts.on("--flow-topic TOPIC", "Flow topic (default: #{options[:flow_topic]})") { |v| options[:flow_topic] = v }
  opts.on("--event-topic TOPIC", "Event topic (default: #{options[:event_topic]})") { |v| options[:event_topic] = v }
  opts.on("--sync", "Send synchronously (default: async)") { options[:sync] = true }
  opts.on("--batch-size N", Integer, "Flush every N messages in async mode (default: #{options[:batch_size]})") { |v| options[:batch_size] = v }

  opts.on("--namespace VALUE") { |v| options[:dims]["namespace"] = v }
  opts.on("--namespace-uuid VALUE") { |v| options[:dims]["namespace_uuid"] = v }
  opts.on("--organization VALUE") { |v| options[:dims]["organization"] = v }
  opts.on("--organization-uuid VALUE") { |v| options[:dims]["organization_uuid"] = v }
  opts.on("--service-provider VALUE") { |v| options[:dims]["service_provider"] = v }
  opts.on("--service-provider-uuid VALUE") { |v| options[:dims]["service_provider_uuid"] = v }

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::InvalidOption => e
  warn e.message
  warn parser
  exit 1
end

attack_type = ARGV.shift
if attack_type.nil? || !ATTACK_TYPES.include?(attack_type)
  warn "Missing/invalid attack_type. Valid: #{ATTACK_TYPES.join(", ")}"
  warn parser
  exit 1
end

unless TARGETS.include?(options[:target])
  warn "Invalid --target. Valid: #{TARGETS.join(", ")}"
  exit 1
end

sensor = random_sensor
dims = options[:dims]

brokers = options[:brokers].split(",").map(&:strip).reject(&:empty?)
producer = Poseidon::Producer.new(brokers, options[:client_id])

gen = AttackGenerator.new(attack_type: attack_type, sensor: sensor, dims: dims)

start = Time.now
finish = start + options[:duration]

interval = 1.0 / [options[:rate], 1].max
next_tick = Time.now

puts "[*] Starting simulation: attack=#{attack_type} target=#{options[:target]} brokers=#{brokers.join(",")}"
puts "[*] Topics: flow=#{options[:flow_topic]} event=#{options[:event_topic]}"
puts "[*] Sensor: ip=#{sensor["sensor_ip"]} name=#{sensor["sensor_name"]} uuid=#{sensor["sensor_uuid"]}"
puts "[*] Optional dims included: #{dims.keys.sort.join(", ")}" unless dims.empty?
puts "[*] Mode: #{options[:sync] ? "sync" : "async"}"

sent = 0
pending = []

begin
  while Time.now < finish
    if Time.now >= next_tick
      if options[:target] == "flow" || options[:target] == "both"
        msg = gen.next_flow.to_json
        if options[:sync]
          producer.send_messages(Poseidon::MessageToSend.new(options[:flow_topic], msg))
        else
          pending << Poseidon::MessageToSend.new(options[:flow_topic], msg)
        end
        sent += 1
      end

      if options[:target] == "event" || options[:target] == "both"
        msg = gen.next_event.to_json
        if options[:sync]
          producer.send_messages(Poseidon::MessageToSend.new(options[:event_topic], msg))
        else
          pending << Poseidon::MessageToSend.new(options[:event_topic], msg)
        end
        sent += 1
      end

      if !options[:sync] && pending.size >= options[:batch_size]
        producer.send_messages(pending)
        pending.clear
      end

      next_tick += interval
    else
      sleep([next_tick - Time.now, 0.01].max)
    end
  end
ensure
  if !options[:sync] && !pending.empty?
    producer.send_messages(pending)
    pending.clear
  end
  producer.close
end

puts "[*] Done. Total messages produced: #{sent}"
