require 'open3'

TABLE_WIDTH = 70

def cluster_nodes
  `serf members`.lines.map do |line|
    parts = line.split
    { name: parts[0], ip: parts[1].split(':').first }
  end
end

def remote_cmd(node_ip, cmd)
  `ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null \
  -o PasswordAuthentication=no -o StrictHostKeyChecking=no \
  -i /var/www/rb-rails/config/rsa root@#{node_ip} "#{cmd}"`.strip
end

def ping_remote(from_node_ip, target_ip)
  cmd = "ping -c 1 -W 1 #{target_ip}"
  output = remote_cmd(from_node_ip, cmd)
  m = output.match(/time=(.*?) ms/)
  m ? m[1].to_f : nil
end

def build_latency_matrix(nodes)
  matrix = {}
  nodes.each do |src|
    matrix[src[:ip]] ||= {}
    nodes.each do |dst|
      matrix[src[:ip]][dst[:ip]] = (src[:ip] == dst[:ip]) ? 0 : ping_remote(src[:ip], dst[:ip])
    end
  end
  matrix
end

def print_latency_table(nodes, matrix)
  puts "╔" + "═" * (TABLE_WIDTH - 2) + "╗"
  puts "║#{'RB_LATENCY'.center(TABLE_WIDTH - 2)}║"
  puts "╠" + "═" * (TABLE_WIDTH - 2) + "╣"

  nodes.each_with_index do |node, idx|
    node_line = " Node: #{node[:name]} (#{node[:ip]}) "
    puts "║#{node_line.ljust(TABLE_WIDTH - 2)}║"
    puts "╠" + "═" * (TABLE_WIDTH - 2) + "╣"

    matrix[node[:ip]].each do |dst_ip, latency|
      line_content = "#{node[:ip]} -> #{dst_ip} : #{latency}"
      puts "║ #{line_content.ljust(TABLE_WIDTH - 4)} ║"
    end

    puts "╠" + "═" * (TABLE_WIDTH - 2) + "╣" unless idx == nodes.size - 1
  end

  puts "╚" + "═" * (TABLE_WIDTH - 2) + "╝"
end

nodes = cluster_nodes
latencies = build_latency_matrix(nodes)
print_latency_table(nodes, latencies)
