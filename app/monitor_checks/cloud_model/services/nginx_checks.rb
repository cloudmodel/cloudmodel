module CloudModel
  module Services
    class NginxChecks < CloudModel::Services::BaseChecks
      def get_result
        data = {}
        uri = URI(@subject.status_uri)

        http = Net::HTTP.new(uri.host, uri.port)
        if @subject.ssl_supported
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        request = Net::HTTP::Get.new(uri.request_uri)

        begin
          res = http.request(request)
        rescue Exception => e
          return {key: :not_reachable, error: e.to_s, severity: :critical}
        end
  
        begin  
          data['http_version'] = res.http_version
          data['active'] = res.body.lines[0].gsub('Active connections: ', '').to_i
          data['accepted'], data['handled'], data['requests'] = res.body.lines[2].strip.split(' ').map(&:to_i)

          res.body.lines[3].gsub(/\W*:\W*/, ':').split(' ').each do |pair|
            k,v = pair.split ':'
            data["#{k.downcase}"] = v
          end
        rescue Exception => e
           return {key: :parse_result, error: e.to_s, severity: :warning}
        end

        if res.code == '404'
          return {key: :no_nginx_status, error: "404: nginx_status not found on server, but server running", severity: :warning}
        end
        if res.code == '403'
          return {key: :ngnix_status_forbidden, error: "403: no privileges to access nginx_status on server", severity: :warning}
        end
        
        data
      end
    
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable', 
          no_nginx_status: 'status available', 
          ngnix_status_forbidden: 'status forbidden', 
          parse_result: 'parse status'
        }
      end
    end
  end
end