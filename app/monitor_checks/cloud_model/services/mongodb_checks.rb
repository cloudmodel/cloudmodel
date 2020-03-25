module CloudModel
  module Services
    class MongodbChecks < CloudModel::Services::BaseChecks  
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable'
        }
      end
    end
  end
end