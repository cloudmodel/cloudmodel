module CloudModel
  module Services
    class Tomcat < Base
      field :port, type: Integer, default: 8080
      belongs_to :deploy_war_image, class_name: 'CloudModel::WarImage', inverse_of: :services
      validates :deploy_war_image_id, presence: true

      def kind
        :http
      end

      def components_needed
        ([:tomcat] + super).uniq
      end

      def service_status
        data = {}
        uri = URI("http://#{guest.internal_address}:8080/manager/status?XML=true")

        begin
          res = nil

          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => uri.scheme == 'https',
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

            req = Net::HTTP::Get.new uri.request_uri
            req.basic_auth 'mon', 'mon'

            res = http.request req
          end
        rescue Exception => e
           return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        data['http_version'] = res.http_version

        if res.code == '404'
          return {key: :no_tomcat_status, error: "404: tomcat status not found on server, but server running", severity: :warning}
        end
        if res.code == '401'
          return {key: :tomcat_status_forbidden, error: "401: no privileges to access tomcat status on server", severity: :warning}
        end

        begin
          doc = Nokogiri::XML(res.body)
          doc.xpath('//status/jvm/memory').first.attributes.each do |k,v|
            data["memory_#{k}"] = v.to_s.to_i
          end

          if data['memory_free'] and data['memory_total'] > 0
            data['memory_usage'] = (100.0 * (data['memory_total']-data['memory_free'])/data['memory_total'])
          end

          connector = doc.xpath('//status/connector[@name=\'"http-nio-8080"\']')
          if connector.size == 0
            connector = doc.xpath('//status/connector[@name=\'"http-bio-8080"\']')
          end
          if connector.size > 0
            connector.xpath('./requestInfo').first.attributes.each do |k,v|
              data["request_#{k}"] = v.to_s.to_i
            end
            connector.xpath('./threadInfo').first.attributes.each do |k,v|
              data["thread_#{k.gsub('Thread', '')}"] = v.to_s.to_i
            end

            thread_usage = (100.0 * data['thread_currentCount']/data['thread_maxs'])
            data['thread_usage'] = thread_usage.round(2)
          end
        rescue Exception => e
          return {key: :parse_result, error: "could not parse status xml: #{e}", severity: :warning}
        end

        data
      end

      def heap_size
        "#{guest.memory_size / 1024 / 1024 - 128}m"
      end
    end
  end
end