require 'socket'

module CloudModel
  module Livestatus  
    class Connection
      def initialize options = {}
        @options = options
      end

      def socket
        begin
          @socket ||= TCPSocket.new(CloudModel.config.livestatus_host, CloudModel.config.livestatus_port)
        rescue
          nil
        end
        #socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end
    
      def request query, options = {}
        command = query.strip
        
        return Hash.new(state: -1) unless socket
    
        unless options[:where].blank?
          options[:where].each do |k,v|
            command += "\r\nFilter: #{k} = #{v}"
          end
        end

        unless options[:only].blank?
          command += "\r\nColumns: #{options[:only] * ' '}" 
        end

        command += "\r\nColumnHeaders: on\r\nOutputFormat: json\r\n\r\n" 

        socket.print(command)
        json_data = socket.gets
        socket.close

        # puts json_data

        data = []
        begin
          raw_data = JSON.parse json_data
          header = raw_data.shift

          raw_data.each do |raw_line|
            line = {}
 
            i = 0
            raw_line.each do |v|
              line[header[i]] = v
              i += 1
            end
 
            data << line
          end
        rescue
        end

        data
      end
    end
  end
end


