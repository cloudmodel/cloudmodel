require File.expand_path('../shinken_helpers', __FILE__)

def query_check_mk host, label
  
  s = TCPSocket.new host, 6556

  result = ""
  started = false

  while line = s.gets
    started = false if line[0..2] == "<<<"
    result << line if started
    started = true if line.strip == "<<<#{label}>>>"
  end

  s.close    
  
  result      
end
