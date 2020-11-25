module CloudModel
  module Services
    class Fuseki < Base
      field :port, type: Integer, default: 3030

      def kind
        :http
      end

      def components_needed
        ([:fuseki] + super).uniq
      end

      def read_server_info uri
        res = nil

        begin
          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => uri.scheme == 'https',
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

            req = Net::HTTP::Get.new uri.request_uri
            res = http.request req
          end
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        if res.code == '404'
          return {key: :no_fuseki_status, error: "404: solr status not found on server, but server running", severity: :warning}
        end
        if res.code == '401'
          return {key: :fuseki_status_forbidden, error: "401: no privileges to access fuseki status on server", severity: :warning}
        end

       begin
          json = {}
          res.body.lines.each do |line|
            line.strip!
            unless line.first == '#'
              key, attrs, value = line.match(/^(.+)\{(.+)\}(.*)$/).captures
              value.strip!
              description = false

              if value =~ /^\-?[0-9]+\.[0-9]+(E\-?[0-9]+)?$/
                value = value.to_f
              end
              if value.to_i.to_f == value
                value = value.to_i
              end

              path = []

              if key =~ /^jvm_gc_/
                path << ['jvm', 'gc']
                path << ['gc', key.gsub(/^jvm_gc_/, '')]
                key = 'jvm'
              elsif key =~ /^jvm_/
                path << ['jvm', key.gsub(/^jvm_/, '')]
                key = 'jvm'
              elsif key =~ /^fuseki_/
                path << ['fuseki', key.gsub(/^fuseki_/, '')]
                key = 'fuseki'
              end

              attrs.split(',').each do |attr|
                if attr
                  k, v = attr.match(/(.+)="?(.+)?"/).captures
                  case k
                  when 'application'
                  when 'description'
                    description = v
                  when 'dataset'
                    path << [k, v.gsub(/^\//, '')]
                  else
                    path << [k, v]
                  end
                end
              end

              if path.blank?
                json[key] = value
              else
                target = json[key] ||= {}
                last = path.pop

                path.each do |pair|
                  target = target[pair[1] || '_'] ||= {}
                end

                target[last[1]] = value
                if description
                  target["#{last[1]}_description"] = description
                end
              end
            end
          end

          json
       rescue
         return {key: :parse_result, error: "can't parse prometheus format for #{uri}\n\n#{res.body}", severity: :warning}
       end
      end

      def service_status
        #base_url = "http#{ssl_supported ? 's' : ''}://#{guest.private_address}:8080/solr/admin"
        base_url = "http://#{guest.private_address}:#{port}/$"

        data = {}
        metrics_uri = URI("#{base_url}/metrics")

        data = read_server_info metrics_uri

        data
      end

      def heap_size
        "#{guest.memory_size / 1024 / 1024 - 128}m"
      end
    end
  end
end