def check_topic(topic)
  command = `timeout 60s /usr/lib/redborder/bin/rb_consumer.sh -t #{topic} -c 1 2>&1 | grep -q -F '1 messages'`
  command_return = $?.to_s.split(" ")[3].to_i
  command_return == 0 ? ["Kafka is receiving messages at the topic #{topic}",0] :
                        ["Kafka is not receiving messages at the topic #{topic}",1]
end