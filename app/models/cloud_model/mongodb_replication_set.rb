module CloudModel
  class MongodbReplicationSet
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    field :name, type: String # Name of the replication set

    def guests
      CloudModel::Guest.where("services.mongodb_replication_set_id" => id)
    end

    def services
      guests.map{ |guest|
        guest.services.where(mongodb_replication_set_id: id).to_a
      }.flatten
    end

    def add_service service
      service.update_attribute :mongodb_replication_set_id, id
    end

    def init_rs_cmd
      cmd = "rs.initiate( {\n" +
            "   _id : \"#{name}\",\n" +
            "   members: [\n"

      services.each_with_index do |service,i|
        cmd += "      { _id: #{i}, host: \"#{service.private_address}:#{service.port}\" },\n"
      end

      cmd += "   ]\n" +
             "})\n"

      cmd
    end

    def service_uris
      services.map do |service|
        service.server_uri
      end
    end

    def operational_service_uris
      services.map do |service|
        service.server_uri if service.state != :critical
      end - [nil]
    end

    def client
      if operational_service_uris.first
        begin
          Mongo::Client.new(operational_service_uris, connect_timeout: 2, timeout: 2)
        rescue
          false
        end
      else
        nil
      end
    end

    def db_command command
      if c = client
        begin
          c.database.command(command).documents
        rescue Exception => e
          [{'retval' => {error: "Can´t execute #{command}"}, 'exception' => e}]
        end
      end
    end

    def eval js
      if res = db_command(eval: js)
        res.first['retval']
      else
        false
      end
    end

    def status
      # Issue an administrative command
      #data = db_command(replSetGetStatus: 1).as_json.first
      data = eval 'rs.status()'
      data ||= {}
      data['members'] ||= []

      services.each do |service|
        member = data['members'].find{|member| member['name'] == service.server_uri}

        if member
          member['found'] = true
          member['service'] = service
        else
          data['members'] << {
            '_id' => nil,
            'name' => service.server_uri,
            'found' => false,
            'service' => service,
            'state' => -1,
            'stateStr' => 'N/C'
          }
        end
      end

      data
    end

    def initiate
      guests.first.exec "mongo --eval '#{init_rs_cmd}'"
      #eval init_rs_cmd
    end

    def add host
      eval "rs.add('#{host}')"
    end

    def remove host
      eval "rs.remove('#{host}')"
    end

  end
end