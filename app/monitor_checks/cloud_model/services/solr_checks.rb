module CloudModel
  module Services
    class SolrChecks < CloudModel::Services::BaseChecks
      def read_solr_json uri
        begin
          res = nil

          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => uri.scheme == 'https', 
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

            req = Net::HTTP::Get.new uri.request_uri
            res = http.request req 
          end
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

      #  data['http_version'] = res.http_version

        if res.code == '404'
          return {key: :no_solr_status, error: "404: solr status not found on server, but server running", severity: :warning}
        end
        if res.code == '401'
          return {key: :solr_status_forbidden, error: "401: no privileges to access solr status on server", severity: :warning}
        end

        begin
          status = JSON.parse(res.body)
        rescue
          return {key: :parse_result, error: "can't parse solr json for #{uri}\n\n#{res.body}", severity: :warning}
        end
      end
      
      def get_result        
        #base_url = "http#{@subject.ssl_supported ? 's' : ''}://#{@guest.private_address}:8080/solr/admin"
        base_url = "http://#{@guest.private_address}:8080/solr/admin"

        data = {}
        status_uri = URI("#{base_url}/info/system?wt=json")
        cores_uri = URI("#{base_url}/cores?wt=json")

        status = read_solr_json status_uri
        cores = read_solr_json cores_uri

        begin
          solr_start_at = Time.parse status['jvm']['jmx']['startTime']
          core_start_at = if cores['status'].empty?
            Time.now
          else
            Time.parse cores['status'].values.first['startTime']
          end
  
          data['core_start_time'] = core_start_at - solr_start_at
        rescue
          return {key: :parse_result, error: "Could not parse core_start_time", severity: :warning}
        end

        begin  
          data['memory_free'] = status['jvm']['memory']['raw']['free']
          data['memory_total'] = status['jvm']['memory']['raw']['total']
          data['memory_usage'] = status['jvm']['memory']['raw']['used%']
          data['cores_running'] = cores['status'].count
  
          #puts cores.to_yaml
        rescue Exception => e
          return {key: :parse_result, error: "could not parse status json: #{e}", severity: :warning}
        end

        if data['cores_running'] == 0
          return {key: :not_reachable, error: "No core running after #{'%.1f' % data['core_start_time']}s", severity: :critical}
        end
        
        data
      end
      
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable',
          no_solr_status: 'status available', 
          solr_status_forbidden: 'status forbidden', 
          parse_result: 'parse status'
        }
        
        do_check_value :mem_usage, @result['memory_usage'], {
          warning: 80,
          critical: 90
        }
      end
    end
  end
end

