#! /usr/bin/env ruby

# -----------------------
# Author: Andreas Paul (ANDPAUL) <andreas.paul@1und1.de>
# Date: 2017-02-13 15:00
# Version: 0.1
# -----------------------
#
# https://www.elastic.co/guide/en/logstash/current/monitoring.html

require 'rubygems'
require 'optparse'
require 'open-uri'
require 'uri'
require 'json'
require 'socket'
require 'timeout'

$debug = false
$checkmk = false
$host = ''
$timeout = 5
$port = 9600

opt = OptionParser.new
opt.on("--debug", "-d", "print debug information, defaults to #{$debug}") do |f|
    $debug = true
end
opt.on("--checkmk", "append HTML </br> to each line in the long output to display line breaks in the check_mk GUI, defaults to #{$checkmk}") do |c|
    $checkmk = true
end
opt.on("--host [LOGSTASHSERVER]", "-H", String, "Your logstash hostname, MANDATORY parameter") do |host_p|
    $host = host_p
end
opt.on("--port [PORT]", "-p", Integer, "Your logstash port, defaults to #{$port}") do |port_p|
    $port = port_p
end
opt.on("--timeout [SECONDS]", "-t", Integer, "Timeout for each HTTP GET request, defaults to #{$timeout} seconds") do |timeout_p|
    $timeout = timeout_p
end
opt.parse!

if ENV.key?('VIMRUNTIME')
    $debug = true
    $host = '10.77.202.30'
end


if $host == '' || $host == nil
    puts 'ERROR: Please specify your logstash server with -H <LOGSTASHSERVER>'
    puts "Example: #{__FILE__} -H logstash.domain.tld"
    puts opt
    exit 3
end

# http://stackoverflow.com/a/517638/682847
def is_port_open?(ip, port)
  begin
    Timeout::timeout($timeout) do
      begin
        s = TCPSocket.new(ip, port)
        s.close
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        return false
      end
    end
  rescue Timeout::Error
  end

  return false
end

def doRequest(url)
  out = {:returncode => 0}
  puts "sending GET to #{url}" if $debug
  begin
    uri = URI.parse(url)
    response = uri.read(:read_timeout => $timeout)
    puts "Response: #{response}" if $debug
    out[:data] = JSON.load(response)
  rescue OpenURI::HTTPError, Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, Errno::ECONNREFUSED,
    Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
    out[:text] = "WARNING: Error '#{e}' while sending request to #{url}"
    out[:returncode] = 1
  end
  puts "Parsed: #{out[:data]}" if $debug
  return out
end

def pipelineMetrics()
  result = {:perfdata => ''}
  url = "http://#{$host}:#{$port}/_node/stats/pipeline"

  data = doRequest(url)
  if data[:returncode] == 0
    puts data if $debug
    eventsIn = data[:data]['pipeline']['events']['in'].to_i
    eventsOut = data[:data]['pipeline']['events']['out'].to_i
    eventsFil = data[:data]['pipeline']['events']['filtered'].to_i
    eventsDur = data[:data]['pipeline']['events']['duration_in_millis'].to_i
    result[:text] = "#{eventsIn} IN events #{eventsOut} OUT events #{eventsFil} filtered events #{eventsDur} duration in ms"
    result[:returncode] = 0
    result[:perfdata] = "events_in=#{eventsIn}c events_out=#{eventsOut}c events_filtered=#{eventsFil}c events_dur=#{eventsDur}ms"
  else
    result[:text] = data[:text].!gsub("\n", '')
    result[:returncode] = data[:returncode]
  end
  return result
end

def jvmMetrics()
  result = {:perfdata => ''}
  url = "http://#{$host}:#{$port}/_node/stats/jvm"

  data = doRequest(url)
  if data[:returncode] == 0
    puts data if $debug
    heapPerc = data[:data]['jvm']['mem']['heap_used_percent'].to_i
    heapBytes = data[:data]['jvm']['mem']['heap_used_in_bytes'].to_i
    heapBytesMax = data[:data]['jvm']['mem']['heap_max_in_bytes'].to_i
    uptime = data[:data]['jvm']['uptime_in_millis'].to_i
    result[:text] = "#{heapPerc}% of JVM heap used (#{heapBytes / 1024 ** 2}MB of max #{heapBytesMax / 1024 ** 2}MB) uptime: #{uptime / 1000 / 60 ** 2 } hours"
    result[:returncode] = 0
    result[:perfdata] = "heap_perc=#{heapPerc}% heap_bytes=#{heapBytes/ 1024 ** 2}MB uptime=#{uptime / 1000}s"
  else
    result[:text] = data[:text].!gsub("\n", '')
    result[:returncode] = data[:returncode]
  end
  return result
end

results = []

if ! is_port_open?($host, $port)
  results << {:text => "CRITICAL: Could not connect to plain HTTP port #{$host}:#{$port}", :returncode => 2}
else
  if $debug == false
    # threading
    threads = []
    threads << Thread.new{ results << pipelineMetrics() }
    threads << Thread.new{ results << jvmMetrics() }

    threads.each do |t|
      t.join
    end
  else
    results << pipelineMetrics()
    results << jvmMetrics()
  end
end

puts results if $debug

# Aggregate check results
output = {}
output[:returncode] = 0
output[:text] = ''
output[:text_if_ok] = ''
output[:multiline] = ''
output[:perfdata] = ''
results.each do |result|
  output[:perfdata] += "#{result[:perfdata]} " if result[:perfdata] != ''
  if result[:returncode] >= 1
    output[:text] += "#{result[:text]} "
    case result[:returncode]
    when 3
      output[:returncode] = 3 if result[:returncode] > output[:returncode]
    when 2
      output[:returncode] = 2 if result[:returncode] > output[:returncode]
    when 1
      output[:returncode] = 1 if result[:returncode] > output[:returncode]
    end
  else
    output[:text_if_ok] += "#{result[:text]} "
    br = ''
    br = '</br>' if $checkmk
    output[:multiline] += "#{result[:text]}#{br}\n"
  end
end

if output[:text] == ''
  output[:text] = output[:text_if_ok]
end

puts "#{output[:text]}|#{output[:perfdata]}\n#{output[:multiline].chomp()}"

exit output[:returncode]
