require File.expand_path('../shinken_helpers', __FILE__)
require 'socket'

def query_check_mk host
  begin
    s = TCPSocket.new host, 6556

    result = []
    started = false
    while line = s.gets
      result << line
    end
    s.close
  rescue Errno::ECONNREFUSED
    puts "CRITICAL - Connection refused |"
    exit STATE_CRITICAL
  end  
  result
end

def filter_check_mk data, label
  result = ""
  started = false

  data.each do |line|
    started = false if line[0..2] == "<<<"
    result << line if started
    started = true if line.strip == "<<<#{label}>>>"
  end
  
  result
end