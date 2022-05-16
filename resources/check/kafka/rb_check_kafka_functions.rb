def check_topic(topic)
  system("timeout 60s /usr/lib/redborder/bin/rb_consumer.sh -t #{topic} -c 1 2>&1 | grep -q -F '1 messages'")
  command_return = $?.exitstatus
  command_return == 0 ? output = "Kafka is receiving messages at the topic #{topic}" :
    output = "Kafka is not receiving messages at the topic #{topic}"

  [output, command_return]
end
