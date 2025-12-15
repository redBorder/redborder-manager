#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'optparse'
require 'securerandom'

def multiplicate_monitors(file_path, factor, test: false, sensor_name: 'Device')
  # Leer y parsear el JSON
  sensor_index = -1
  json_data = JSON.parse(File.read(file_path))

  json_data['sensors'].each_with_index do |sensor, i|
    next unless [sensor_name].include? sensor['sensor_name'] # <-- filter target sensor only
    next unless sensor['monitors'].is_a?(Array)

    sensor_index = i
    if factor >= 1
      sensor['monitors'] = sensor['monitors'] * factor

      sensor['monitors'].each do |mon|
        next unless mon['name']
        mon['name'] = SecureRandom.uuid
      end

      puts sensor['monitors'].last
    else
      sensor['monitors'] = sensor['monitors'].first((factor * sensor['monitors'].size).floor)
    end
  end

  # Determinar la ruta de salida
  output_path = if test
                  dirname = File.dirname(file_path)
                  basename = File.basename(file_path, '.*')
                  extname = File.extname(file_path)
                  File.join(dirname, "#{basename}_test#{extname}")
                else
                  file_path
                end

  # Sobrescribir o escribir en archivo de prueba
  File.open(output_path, 'w') do |f|
    f.write(JSON.pretty_generate(json_data))
  end

  puts "Situación de monitores actualizada en: #{output_path}"
  puts "Cada 'monitors' ha sido multiplicado por #{factor}."
  puts "Total de sensores procesados: #{json_data['sensors'].size}"
  return sensor_index, json_data['sensors'].size
end

def usage
  "Uso: ruby #{__FILE__} -f <archivo.json> -n <factor> [--test]\n" \
  'Opciones:\n' \
  '  -f, --file PATH       Ruta al archivo JSON\n' \
  '  -n, --factor N        Factor de multiplicación (entero)\n' \
  '  -t, --test            Crear archivo de prueba en lugar de sobrescribir\n' \
  '  -h, --help            Mostrar esta ayuda'
end

# ===== Parseo de argumentos =====
options = {
  file: '/etc/redborder-monitor/config.json',
  factor: 2,
  test: false
}

OptionParser.new do |opts|
  opts.banner = usage

  opts.on('-f', '--file PATH', 'Ruta al archivo JSON') { |v| options[:file] = v }
  opts.on('-n', '--factor N', Float, 'Factor de multiplicación') { |v| options[:factor] = v }
  opts.on('-t', '--test', 'Crear archivo de prueba') { options[:test] = true }
  opts.on('-h', '--help', usage) do
    puts opts
    exit
  end
end.parse!

# Ejecutar función
sensor_index, s_proc = multiplicate_monitors(options[:file], options[:factor], test: options[:test])

puts "Total de sensores procesados: #{s_proc}"
# puts `cat /etc/redborder-monitor/config.json | jq '.sensors[sensor_index]'`

puts `cat /etc/redborder-monitor/config.json | jq '.sensors[#{sensor_index}].monitors | length'`
