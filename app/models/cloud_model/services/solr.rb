module CloudModel
  module Services
    class Solr < Base
      field :port, type: Integer, default: 8080
      belongs_to :deploy_solr_image, class_name: '::CloudModel::SolrImage', inverse_of: :services

      def kind
        :http
      end

      def components_needed
        ([:"solr@#{deploy_solr_image.solr_version}"] + super).uniq
      end

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

      def service_status
        #base_url = "http#{ssl_supported ? 's' : ''}://#{guest.private_address}:8080/solr/admin"
        base_url = "http://#{guest.private_address}:#{port}/solr/admin"

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

      def heap_size
        "#{guest.memory_size / 1024 / 1024 - 128}m"
      end
    end
  end
end